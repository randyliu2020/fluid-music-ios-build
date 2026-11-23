import Foundation

struct Song: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var relativePath: String
    var folder: String
    var duration: Double
    var addedAt: Date
    var artworkPath: String?
    var lyrics: String?
    var trackNumber: Int = 0
    var fileURL: URL { LibraryPaths.music.appendingPathComponent(relativePath) }
    var artworkURL: URL? { artworkPath.map { LibraryPaths.artwork.appendingPathComponent($0) } }
    var searchText: String { "\(title) \(artist) \(album)" }
    var indexLetter: String { Self.indexLetter(title) }
    static func sortKey(_ value: String) -> String {
        (value.applyingTransform(.toLatin, reverse: false) ?? value)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func indexLetter(_ value: String) -> String {
        let first = String(sortKey(value).trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        return first.range(of: "^[A-Z]$", options: .regularExpression) == nil ? "#" : first
    }
}

struct Playlist: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var songIDs: [String] = []
}

enum SongSort: String, CaseIterable, Identifiable, Codable {
    case title = "标题 A–Z", artist = "艺术家", album = "专辑", added = "最近添加", duration = "时长"
    var id: String { rawValue }
    func sorted(_ songs: [Song]) -> [Song] {
        songs.sorted { a, b in
            switch self {
            case .title: return Song.sortKey(a.title).localizedStandardCompare(Song.sortKey(b.title)) == .orderedAscending
            case .artist: return Song.sortKey(a.artist + a.title) < Song.sortKey(b.artist + b.title)
            case .album: return a.album == b.album ? a.trackNumber < b.trackNumber : Song.sortKey(a.album) < Song.sortKey(b.album)
            case .added: return a.addedAt > b.addedAt
            case .duration: return a.duration < b.duration
            }
        }
    }
}

enum RepeatMode: String, Codable, CaseIterable {
    case off, all, one
    var symbol: String { self == .one ? "repeat.1" : "repeat" }
    var label: String { self == .off ? "顺序播放" : self == .all ? "列表循环" : "单曲循环" }
    var next: Self { self == .off ? .all : self == .all ? .one : .off }
}

struct PlaybackSnapshot: Codable {
    var queue: [String] = []
    var originalQueue: [String] = []
    var currentID: String?
    var position: Double = 0
    var repeatMode: RepeatMode = .off
    var shuffled: Bool = false
}

struct LibraryData: Codable {
    var schemaVersion: Int = 1
    var songs: [Song] = []
    var playlists: [Playlist] = []
    var favorites: Set<String> = []
    var excludedFolders: Set<String> = []
}

enum LibraryPaths {
    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FluidMusic", isDirectory: true)
    static let music = documents.appendingPathComponent("Music", isDirectory: true)
    static let artwork = support.appendingPathComponent("Artwork", isDirectory: true)
    static let library = support.appendingPathComponent("library.json")
    static let playback = support.appendingPathComponent("playback.json")
    static func prepare() throws {
        for url in [support, music, artwork] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        }
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

func timeText(_ seconds: Double) -> String {
    let total = seconds.isFinite ? max(0, Int(seconds)) : 0
    return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        : String(format: "%d:%02d", total / 60, total % 60)
}
