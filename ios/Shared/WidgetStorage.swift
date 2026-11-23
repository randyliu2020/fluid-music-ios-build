import Foundation
import AppIntents

struct WidgetSnapshot: Codable {
    var title: String = "流体音乐"
    var artist: String = "打开 App 导入本地音乐"
    var isPlaying = false
    var updatedAt = Date()
}

enum WidgetStorage {
    static var container: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FluidMusicAppGroup") as? String, !group.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }
    static func load() -> WidgetSnapshot {
        guard let url = container?.appendingPathComponent("now-playing.json"), let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snapshot
    }
    static func save(title: String, artist: String, isPlaying: Bool, artworkURL: URL?) {
        guard let directory = container else { return }
        let snapshot = WidgetSnapshot(title: title, artist: artist, isPlaying: isPlaying)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: directory.appendingPathComponent("now-playing.json"), options: .atomic) }
        let target = directory.appendingPathComponent("cover.jpg")
        if let artworkURL, let data = try? Data(contentsOf: artworkURL) { try? data.write(to: target, options: .atomic) }
        else { try? FileManager.default.removeItem(at: target) }
    }
}

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "播放或暂停流体音乐"
    static var isDiscoverable = false
    @MainActor func perform() async throws -> some IntentResult {
        #if FLUID_MUSIC_APP
        PlaybackController.shared.toggle()
        #endif
        return .result()
    }
}
struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "流体音乐下一首"
    static var isDiscoverable = false
    @MainActor func perform() async throws -> some IntentResult {
        #if FLUID_MUSIC_APP
        PlaybackController.shared.next()
        #endif
        return .result()
    }
}
struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "流体音乐上一首"
    static var isDiscoverable = false
    @MainActor func perform() async throws -> some IntentResult {
        #if FLUID_MUSIC_APP
        PlaybackController.shared.previous()
        #endif
        return .result()
    }
}
