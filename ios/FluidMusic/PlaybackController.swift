import Foundation
import AVFoundation
import MediaPlayer
import Combine
import WidgetKit
import UIKit

@MainActor final class PlaybackController: ObservableObject {
    static let shared = PlaybackController()
    @Published private(set) var song: Song?
    @Published private(set) var queue: [String] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var lyrics = Lyrics()
    @Published private(set) var repeatMode = RepeatMode.off
    @Published private(set) var shuffled = false
    @Published private(set) var sleepDeadline: Date?
    @Published var errorMessage: String?
    @Published private(set) var eqEnabled = false
    @Published private(set) var eqGains: [Float] = Array(repeating: 0, count: 10)
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let presets: [(String, [Float])] = [
        ("平直", [0,0,0,0,0,0,0,0,0,0]), ("人声", [-3,-2,-1,1,3,4,3,1,-1,-2]),
        ("流行", [-1,1,3,4,2,0,-1,-1,2,3]), ("摇滚", [4,3,1,-1,-2,1,3,4,4,3]),
        ("古典", [3,2,1,0,-1,-1,0,1,2,3]), ("低音增强", [6,5,4,2,0,0,0,0,0,0])
    ]
    private var engine = AVAudioEngine()
    private var node = AVAudioPlayerNode()
    private var equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var audioFile: AVAudioFile?
    private var segmentStart: Double = 0
    private var generation = UUID()
    private var originalQueue: [String] = []
    private var timer: Timer?
    private var lastSave = Date.distantPast
    private var interruptionResume = false
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var observers: [NSObjectProtocol] = []
    private var rebuilding = false
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    var queueSongs: [Song] {
        let lookup = Dictionary(uniqueKeysWithValues: LibraryStore.shared.data.songs.map { ($0.id, $0) })
        return queue.compactMap { lookup[$0] }
    }

    init() {
        configureEngine()
        eqEnabled = UserDefaults.standard.bool(forKey: "eqEnabled")
        if let gains = UserDefaults.standard.array(forKey: "eqGains") as? [Double], gains.count == 10 { eqGains = gains.map { Float(max(-12, min(12, $0))) } }
        applyEQ(); configureSession(); configureRemoteControls(); observeAudioSession()
        if let bytes = try? Data(contentsOf: LibraryPaths.playback), let snapshot = try? JSONDecoder().decode(PlaybackSnapshot.self, from: bytes) {
            let known = Set(LibraryStore.shared.data.songs.map(\.id))
            queue = snapshot.queue.filter { known.contains($0) }
            originalQueue = snapshot.originalQueue.filter { known.contains($0) }
            if originalQueue.isEmpty { originalQueue = queue }
            repeatMode = snapshot.repeatMode; shuffled = snapshot.shuffled
            if let id = snapshot.currentID, let song = LibraryStore.shared.data.songs.first(where: { $0.id == id }) {
                prepare(song, at: snapshot.position, autoplay: false)
            }
        }
        timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func configureEngine() {
        engine.attach(node); engine.attach(equalizer)
    }
    private func configureSession() {
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio) }
        catch { errorMessage = "音频会话配置失败：\(error.localizedDescription)" }
    }
    func play(_ selected: Song, in songs: [Song]) {
        originalQueue = songs.map(\.id)
        if !originalQueue.contains(selected.id) { originalQueue.insert(selected.id, at: 0) }
        queue = shuffled ? [selected.id] + originalQueue.filter { $0 != selected.id }.shuffled() : originalQueue
        prepare(selected, at: 0, autoplay: true)
    }
    func playQueued(_ id: String) {
        guard queue.contains(id), let song = LibraryStore.shared.data.songs.first(where: { $0.id == id }) else { return }
        prepare(song, at: 0, autoplay: true)
    }
    private func prepare(_ selected: Song, at seconds: Double, autoplay: Bool) {
        generation = UUID(); node.stop(); engine.stop(); isPlaying = false
        song = selected; duration = selected.duration; position = max(0, min(seconds, duration))
        lyrics = LRCParser.parse(selected.lyrics ?? "")
        if let imageURL = selected.artworkURL, let image = UIImage(contentsOfFile: imageURL.path) {
            nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else { nowPlayingArtwork = nil }
        do {
            audioFile = try AVAudioFile(forReading: selected.fileURL)
            guard let file = audioFile, file.length > 0 else { throw ImportWorker.ImportError.invalidAudio }
            duration = Double(file.length) / file.processingFormat.sampleRate
            engine.disconnectNodeOutput(node); engine.disconnectNodeOutput(equalizer)
            engine.connect(node, to: equalizer, format: file.processingFormat)
            engine.connect(equalizer, to: engine.mainMixerNode, format: file.processingFormat)
            applyEQ(); schedule(at: position)
            if autoplay { resume() } else { publishNowPlaying(); publishWidget(); save() }
        } catch {
            audioFile = nil; errorMessage = "无法播放“\(selected.title)”：\(error.localizedDescription)"
            publishNowPlaying(); publishWidget(); save()
        }
    }
    private func schedule(at seconds: Double) {
        guard let file = audioFile, file.length > 0 else { return }
        generation = UUID(); let token = generation
        node.stop()
        let start = max(0, min(AVAudioFramePosition(seconds * file.processingFormat.sampleRate), file.length - 1))
        segmentStart = Double(start) / file.processingFormat.sampleRate; position = segmentStart
        let count = AVAudioFrameCount(min(file.length - start, AVAudioFramePosition(UInt32.max)))
        node.scheduleSegment(file, startingFrame: start, frameCount: count, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.advance(natural: true)
            }
        }
    }
    func resume() {
        guard song != nil, audioFile != nil else {
            if let first = LibraryStore.shared.songs.first { play(first, in: LibraryStore.shared.songs) }
            return
        }
        if let deadline = sleepDeadline, deadline <= Date() { sleepDeadline = nil }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if position >= duration - 0.05 { schedule(at: 0) }
            if !engine.isRunning { try engine.start() }
            node.play(); isPlaying = true
            publishNowPlaying(); publishWidget(); save()
        } catch { isPlaying = false; errorMessage = "启动播放失败：\(error.localizedDescription)" }
    }
    func pause() {
        updatePosition(); node.pause(); isPlaying = false
        publishNowPlaying(); publishWidget(); save()
    }
    func toggle() { isPlaying ? pause() : resume() }
    func seek(to seconds: Double) {
        guard seconds.isFinite, audioFile != nil else { return }
        let wasPlaying = isPlaying
        schedule(at: max(0, min(seconds, duration)))
        if wasPlaying { node.play() }
        publishNowPlaying(); save()
    }
    func next() { advance(natural: false) }
    private func advance(natural: Bool) {
        guard let id = song?.id, let index = queue.firstIndex(of: id), !queue.isEmpty else { return }
        if natural && repeatMode == .one { seek(to: 0); resume(); return }
        let next = index + 1
        if next < queue.count { playQueued(queue[next]) }
        else if repeatMode == .all { playQueued(queue[0]) }
        else {
            generation = UUID(); node.stop(); isPlaying = false
            position = duration; publishNowPlaying(); publishWidget(); save()
        }
    }
    func previous() {
        if position > 3 { seek(to: 0); return }
        guard let id = song?.id, let index = queue.firstIndex(of: id), !queue.isEmpty else { return }
        if index > 0 { playQueued(queue[index - 1]) }
        else if repeatMode == .all { playQueued(queue[queue.count - 1]) }
        else { seek(to: 0) }
    }
    func cycleRepeat() { repeatMode = repeatMode.next; save(); publishNowPlaying() }
    func toggleShuffle() {
        shuffled.toggle()
        if shuffled {
            originalQueue = queue
            queue = (song.map { [$0.id] } ?? []) + queue.filter { $0 != song?.id }.shuffled()
        } else { queue = originalQueue }
        save(); publishNowPlaying()
    }
    func enqueue(_ song: Song, next: Bool) {
        guard !queue.contains(song.id) else { return }
        let index = next ? min((queue.firstIndex(of: self.song?.id ?? "") ?? -1) + 1, queue.count) : queue.count
        queue.insert(song.id, at: max(0, index)); originalQueue.append(song.id); save()
    }
    func removeFromQueue(at offsets: IndexSet) {
        let removed = offsets.filter { queue.indices.contains($0) }.map { queue[$0] }
        for id in removed { removeSong(id) }
    }
    func moveQueue(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().filter { queue.indices.contains($0) }.map { queue[$0] }
        let rest = queue.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let adjusted = max(0, min(destination - offsets.filter { $0 < destination }.count, rest.count))
        queue = Array(rest.prefix(adjusted)) + moving + Array(rest.dropFirst(adjusted))
        if !shuffled { originalQueue = queue }; save()
    }
    func removeSong(_ id: String) {
        let wasCurrent = song?.id == id, wasPlaying = isPlaying
        let index = queue.firstIndex(of: id) ?? 0
        queue.removeAll { $0 == id }; originalQueue.removeAll { $0 == id }
        if wasCurrent {
            if !queue.isEmpty, let next = LibraryStore.shared.data.songs.first(where: { $0.id == queue[min(index, queue.count - 1)] }) {
                prepare(next, at: 0, autoplay: wasPlaying)
            } else {
                generation = UUID(); node.stop(); engine.stop(); audioFile = nil; song = nil
                isPlaying = false; position = 0; duration = 0; lyrics = Lyrics()
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; publishWidget()
            }
        }
        save()
    }
    func refreshLibrary() {
        guard let current = song else { return }
        if let updated = LibraryStore.shared.data.songs.first(where: { $0.id == current.id }) {
            song = updated; lyrics = LRCParser.parse(updated.lyrics ?? "")
        } else { removeSong(current.id) }
    }
    func setSleep(minutes: Int?) {
        sleepDeadline = minutes.map { Date().addingTimeInterval(Double($0 * 60)) }
    }
    func setEQEnabled(_ enabled: Bool) { eqEnabled = enabled; applyEQ(); saveEQ() }
    func setGain(_ gain: Float, band: Int) {
        guard eqGains.indices.contains(band) else { return }
        eqGains[band] = max(-12, min(12, gain)); applyEQ(); saveEQ()
    }
    func applyPreset(_ gains: [Float]) {
        guard gains.count == 10 else { return }
        eqGains = gains; eqEnabled = true; applyEQ(); saveEQ()
    }
    private func applyEQ() {
        for i in equalizer.bands.indices {
            let band = equalizer.bands[i]
            let nyquist = Float(audioFile?.processingFormat.sampleRate ?? 44_100) / 2
            band.filterType = .parametric; band.frequency = min(Self.frequencies[i], nyquist * 0.9); band.bandwidth = 1
            band.gain = eqGains[i]; band.bypass = !eqEnabled || Self.frequencies[i] >= nyquist
        }
        // Reserve headroom when boosting bands to reduce clipping.
        equalizer.globalGain = eqEnabled ? -max(0, eqGains.max() ?? 0) : 0
    }
    private func saveEQ() {
        UserDefaults.standard.set(eqEnabled, forKey: "eqEnabled")
        UserDefaults.standard.set(eqGains.map(Double.init), forKey: "eqGains")
    }
    private func updatePosition() {
        guard isPlaying, let render = node.lastRenderTime, let time = node.playerTime(forNodeTime: render), time.sampleRate > 0 else { return }
        position = min(duration, max(0, segmentStart + Double(time.sampleTime) / time.sampleRate))
    }
    private func tick() {
        updatePosition()
        if let deadline = sleepDeadline, Date() >= deadline { sleepDeadline = nil; pause() }
        if isPlaying && Date().timeIntervalSince(lastSave) >= 3 { save(); publishNowPlaying() }
    }
    func save() {
        let snapshot = PlaybackSnapshot(queue: queue, originalQueue: originalQueue, currentID: song?.id, position: position, repeatMode: repeatMode, shuffled: shuffled)
        do { try LibraryPaths.write(snapshot, to: LibraryPaths.playback); lastSave = Date() }
        catch { errorMessage = "保存播放进度失败：\(error.localizedDescription)" }
    }
    private func publishNowPlaying() {
        guard let song else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: song.title, MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album, MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0, MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: queue.firstIndex(of: song.id) ?? 0,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count]
        if let artwork = nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func publishWidget() {
        WidgetStorage.save(title: song?.title ?? "流体音乐", artist: song?.artist ?? "导入音乐，开始聆听", isPlaying: isPlaying, artworkURL: song?.artworkURL)
        WidgetCenter.shared.reloadTimelines(ofKind: "FluidMusicWidget")
    }
    private func configureRemoteControls() {
        let remote = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand, action: @escaping @MainActor (MPRemoteCommandEvent) -> Void) {
            command.isEnabled = true
            let target = command.addTarget { event in
                Task { @MainActor in action(event) }
                return .success
            }
            remoteTargets.append((command, target))
        }
        bind(remote.playCommand) { [weak self] _ in self?.resume() }
        bind(remote.pauseCommand) { [weak self] _ in self?.pause() }
        bind(remote.togglePlayPauseCommand) { [weak self] _ in self?.toggle() }
        bind(remote.nextTrackCommand) { [weak self] _ in self?.next() }
        bind(remote.previousTrackCommand) { [weak self] _ in self?.previous() }
        bind(remote.changePlaybackPositionCommand) { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent { self?.seek(to: event.positionTime) }
        }
    }
    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                if type == .began { self.interruptionResume = self.isPlaying; self.pause() }
                else {
                    let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                    if self.interruptionResume && options.contains(.shouldResume) { self.rebuildAudio(resume: true) }
                    self.interruptionResume = false
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self else { return }
                if note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self.pause() }
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.rebuilding, self.song != nil else { return }
                self.rebuildAudio(resume: self.isPlaying)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.generation = UUID(); self.engine = AVAudioEngine(); self.node = AVAudioPlayerNode(); self.equalizer = AVAudioUnitEQ(numberOfBands: 10)
                self.configureEngine(); self.configureSession(); self.rebuildAudio(resume: false)
            }
        })
    }
    private func rebuildAudio(resume: Bool) {
        guard !rebuilding, let song else { return }
        rebuilding = true
        prepare(song, at: position, autoplay: resume)
        rebuilding = false
    }
}
