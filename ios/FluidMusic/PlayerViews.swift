import SwiftUI

enum PlayerPanel: String, Identifiable { case queue, sleep, equalizer; var id: String { rawValue } }
struct NowPlayingView: View {
    @EnvironmentObject private var player: PlaybackController
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var panel: PlayerPanel?
    @State private var addToPlaylist = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    header
                    TabView(selection: $page) {
                        VinylDisc(song: player.song, playing: player.isPlaying).padding(.horizontal, 18).tag(0)
                        LyricsView().padding(.horizontal, 20).tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .frame(height: max(230, min(380, geometry.size.height - 540)))
                    .accessibilityIdentifier("coverLyricsPages")
                    trackInformation
                    VStack(spacing: 0) {
                        SeekBar()
                        HStack { Text(timeText(player.position)); Spacer(); Text(timeText(player.duration)) }
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if let chorus = player.lyrics.chorus {
                            Button { player.seek(to: chorus) } label: { Label("跳至副歌 · \(timeText(chorus))", systemImage: "sparkle").font(.caption) }
                                .padding(.top, 8).accessibilityIdentifier("seekChorus")
                        }
                    }.padding(.horizontal, 28)
                    transport
                    HStack(spacing: 16) {
                        Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                        SystemVolumeSlider().frame(height: 24)
                        Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal, 34).padding(.top, 8)
                    footer
                }
                .frame(maxWidth: 660).frame(maxWidth: .infinity).padding(.bottom, 16)
            }
            .accessibilityIdentifier("playerScroll")
            .background { MusicBackdrop() }.scrollIndicators(.hidden)
        }
        .sheet(item: $panel) { panel in
            switch panel {
            case .queue: QueueView().presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            case .sleep: SleepTimerView().presentationDetents([.medium]).presentationDragIndicator(.visible)
            case .equalizer: NavigationStack { EqualizerView() }.presentationDetents([.large]).presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $addToPlaylist) { if let song = player.song { AddToPlaylistView(song: song) } }
    }
    private var header: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                .buttonStyle(.glass).accessibilityLabel("关闭播放页").accessibilityIdentifier("closePlayer")
            Spacer()
            VStack(spacing: 4) {
                Text("正在播放").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                Text(player.song?.album ?? "流体音乐").font(.caption).lineLimit(1)
            }
            Spacer()
            Menu {
                Button("添加到歌单", systemImage: "music.note.list") { addToPlaylist = true }
                Button("均衡器", systemImage: "slider.vertical.3") { panel = .equalizer }
                Button("睡眠定时", systemImage: "moon") { panel = .sleep }
                if let song = player.song { ShareLink(item: song.fileURL) { Label("分享音频", systemImage: "square.and.arrow.up") } }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.buttonStyle(.glass).accessibilityLabel("播放设置")
        }.padding(.horizontal, 24).padding(.top, 16)
    }
    private var trackInformation: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(player.song?.title ?? "还没有音乐").font(.title2.bold()).lineLimit(2).accessibilityIdentifier("playerTitle")
                Text(player.song?.artist ?? "导入你喜欢的歌曲").font(.body).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let song = player.song {
                Button { library.favorite(song) } label: {
                    Image(systemName: library.data.favorites.contains(song.id) ? "heart.fill" : "heart")
                        .font(.title2).foregroundStyle(library.data.favorites.contains(song.id) ? Color.pink : Color.primary)
                        .frame(width: 48, height: 48)
                }.buttonStyle(.glass).accessibilityLabel(library.data.favorites.contains(song.id) ? "取消喜欢" : "喜欢").accessibilityIdentifier("favoriteTrack")
            }
        }.padding(.horizontal, 28)
    }
    private var transport: some View {
        HStack(spacing: 0) {
            Button { player.toggleShuffle() } label: { Image(systemName: "shuffle").font(.title3).foregroundStyle(player.shuffled ? Color.mint : Color.secondary).frame(width: 44, height: 48) }
                .accessibilityLabel(player.shuffled ? "关闭随机播放" : "随机播放")
            Spacer(minLength: 10)
            Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.system(size: 28)).frame(width: 52, height: 56) }.accessibilityLabel("上一首")
            Spacer(minLength: 10)
            Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 30, weight: .semibold)).frame(width: 72, height: 72) }
                .buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(.primary)
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放").accessibilityIdentifier("playerPlayPause")
            Spacer(minLength: 10)
            Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.system(size: 28)).frame(width: 52, height: 56) }.accessibilityLabel("下一首").accessibilityIdentifier("nextTrack")
            Spacer(minLength: 10)
            Button { player.cycleRepeat() } label: { Image(systemName: player.repeatMode.symbol).font(.title3).foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.mint).frame(width: 44, height: 48) }.accessibilityLabel(player.repeatMode.label)
        }
        .buttonStyle(.plain).padding(.horizontal, 24).disabled(player.song == nil)
    }
    private var footer: some View {
        HStack {
            Button { withAnimation(reduceMotion ? nil : .easeInOut) { page = page == 0 ? 1 : 0 } } label: { Image(systemName: page == 1 ? "text.bubble.fill" : "text.bubble").frame(width: 48, height: 44) }
                .accessibilityLabel(page == 0 ? "显示歌词" : "显示唱片").accessibilityIdentifier("toggleLyrics")
            Spacer()
            AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("音频输出设备")
            Spacer()
            Button { panel = .sleep } label: { Image(systemName: player.sleepDeadline == nil ? "moon" : "moon.fill").frame(width: 44, height: 44) }.accessibilityLabel("睡眠定时")
            Spacer()
            Button { panel = .queue } label: { Image(systemName: "list.bullet").frame(width: 48, height: 44) }.accessibilityLabel("播放队列").accessibilityIdentifier("openQueue")
        }.font(.title3).buttonStyle(.plain).padding(.horizontal, 28)
    }
}

struct VinylDisc: View {
    var song: Song?
    var playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var accumulated: Double = 0
    @State private var started = Date()
    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width * 0.92, geometry.size.height - 42)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing || reduceMotion || scenePhase != .active)) { context in
                let angle = accumulated + (playing && !reduceMotion ? context.date.timeIntervalSince(started) * 18 : 0)
                ZStack {
                    ZStack {
                        Circle().fill(RadialGradient(colors: [Color(white: 0.18), .black, Color(white: 0.12)], center: .center, startRadius: 0, endRadius: diameter / 2))
                        Canvas { context, size in
                            for step in 0..<38 {
                                let inset = size.width * (0.08 + Double(step) * 0.008)
                                let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
                                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(step % 4 == 0 ? 0.15 : 0.055)), lineWidth: 0.7)
                            }
                        }
                        AngularGradient(colors: [.clear, .white.opacity(0.18), .clear, .clear, .white.opacity(0.14), .clear], center: .center).clipShape(Circle())
                        Artwork(song: song, corner: diameter).frame(width: diameter * 0.43, height: diameter * 0.43)
                            .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: 6))
                        Circle().fill(Color(white: 0.15)).frame(width: 10, height: 10).overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                    }.rotationEffect(.degrees(angle))
                    Circle().fill(LinearGradient(colors: [.white.opacity(0.11), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .frame(width: diameter, height: diameter)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 18)
                .overlay(alignment: .topTrailing) {
                    Tonearm().stroke(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.35), Color(white: 0.8)], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        .frame(width: diameter * 0.26, height: diameter * 0.46)
                        .rotationEffect(.degrees(playing ? 0 : -24), anchor: .topTrailing)
                        .offset(x: -8, y: -14)
                        .animation(reduceMotion ? nil : .spring(response: 0.55), value: playing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: playing) { old, new in
            if old { accumulated = (accumulated + Date().timeIntervalSince(started) * 18).truncatingRemainder(dividingBy: 360) }
            if new { started = Date() }
        }
        .onChange(of: scenePhase) { old, new in
            if new == .active { started = Date() }
            else if old == .active && playing { accumulated = (accumulated + Date().timeIntervalSince(started) * 18).truncatingRemainder(dividingBy: 360) }
        }
        .accessibilityElement().accessibilityLabel("黑胶唱片，\(playing ? "播放中" : "已暂停")")
    }
}
struct Tonearm: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.width * 0.8, y: 0))
            path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.68))
            path.addLine(to: CGPoint(x: rect.width * 0.28, y: rect.height))
        }
    }
}

struct LyricsView: View {
    @EnvironmentObject private var player: PlaybackController
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var following = true
    @State private var importing = false
    private var current: Int? { player.lyrics.activeIndex(at: player.position) }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if !player.lyrics.lines.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(player.lyrics.lines) { line in
                            Button { player.seek(to: line.time); following = true } label: {
                                Text(line.text).font(.title2.bold()).multilineTextAlignment(.leading)
                                    .foregroundStyle(current == line.id ? Color.primary : Color.secondary.opacity(0.65))
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                            }.buttonStyle(.plain).id(line.id)
                                .accessibilityLabel("\(timeText(line.time))，\(line.text)")
                        }
                    }.padding(.vertical, 80).padding(.horizontal, 10)
                } else if !player.lyrics.plain.isEmpty {
                    Text(player.lyrics.plain).font(.title3).lineSpacing(14).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(.vertical, 32)
                } else {
                    ContentUnavailableView { Label("暂无歌词", systemImage: "text.bubble") }
                        description: { Text("支持同名 LRC 和音频内嵌歌词。") }
                        actions: { Button("导入 LRC 歌词") { importing = true }.buttonStyle(.glass) }
                }
            }.scrollIndicators(.hidden)
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in following = false })
            .overlay(alignment: .bottomTrailing) {
                if !following && !player.lyrics.lines.isEmpty {
                    Button("跟随播放", systemImage: "location.fill") {
                        following = true; if let current { withAnimation { proxy.scrollTo(current, anchor: .center) } }
                    }.font(.caption).buttonStyle(.glass).padding(.bottom, 24)
                }
            }
            .onChange(of: current) { _, index in
                if following, let index { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { proxy.scrollTo(index, anchor: .center) } }
            }
            .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
            .onChange(of: player.song?.id) { _, _ in following = true }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .plainText]) { result in
            if case .success(let url) = result, let song = player.song { Task { await library.importLyrics(url, song: song) } }
        }
    }
}

struct QueueView: View {
    @EnvironmentObject private var player: PlaybackController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(player.queueSongs) { song in
                        Button { player.playQueued(song.id) } label: {
                            HStack(spacing: 12) {
                                Artwork(song: song).frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 3) { Text(song.title).lineLimit(1); Text(song.artist).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                if player.song?.id == song.id { Image(systemName: "waveform").foregroundStyle(.mint) }
                            }.foregroundStyle(.primary)
                        }.id(song.id)
                    }.onDelete(perform: player.removeFromQueue).onMove(perform: player.moveQueue)
                }
                .onAppear { if let id = player.song?.id { proxy.scrollTo(id, anchor: .center) } }
                .navigationTitle("播放队列 · \(player.queue.count)").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                }
            }
        }
    }
}

struct SleepTimerView: View {
    @EnvironmentObject private var player: PlaybackController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let deadline = player.sleepDeadline {
                    HStack { Text("剩余时间"); Spacer(); Text(deadline, style: .timer).monospacedDigit().foregroundStyle(.mint) }
                    Button("取消定时", role: .destructive) { player.setSleep(minutes: nil); dismiss() }
                }
                ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button("\(minutes) 分钟后暂停") { player.setSleep(minutes: minutes); dismiss() }
                }
            }.navigationTitle("睡眠定时").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
