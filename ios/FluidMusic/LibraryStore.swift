import Foundation
import Combine
import CryptoKit
import AVFoundation
import UIKit

@MainActor final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()
    @Published private(set) var data = LibraryData()
    @Published var isImporting = false
    @Published var importMessage: String?
    @Published var errorMessage: String?
    @Published var sort: SongSort = .title
    private let importer = ImportWorker()
    var songs: [Song] { sort.sorted(data.songs.filter { !data.excludedFolders.contains($0.folder) }) }
    var allFolders: [String] { Array(Set(data.songs.map(\.folder))).sorted() }

    init() {
        do {
            try LibraryPaths.prepare()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-reset") {
                try? FileManager.default.removeItem(at: LibraryPaths.library)
                try? FileManager.default.removeItem(at: LibraryPaths.playback)
            }
            #endif
            if FileManager.default.fileExists(atPath: LibraryPaths.library.path) {
                let bytes = try Data(contentsOf: LibraryPaths.library)
                do { data = try JSONDecoder().decode(LibraryData.self, from: bytes) }
                catch {
                    let backup = LibraryPaths.support.appendingPathComponent("library-recovery-\(Int(Date().timeIntervalSince1970)).json")
                    try bytes.write(to: backup, options: .atomic)
                    errorMessage = "曲库索引无法读取，已保留恢复副本。可在设置中重新扫描；音频文件没有丢失。"
                }
            }
            if let value = UserDefaults.standard.string(forKey: "songSort"), let sort = SongSort(rawValue: value) { self.sort = sort }
        } catch { errorMessage = "读取曲库失败：\(error.localizedDescription)" }
    }
    func persist() {
        do { try LibraryPaths.write(data, to: LibraryPaths.library) }
        catch { errorMessage = "保存曲库失败：\(error.localizedDescription)" }
        UserDefaults.standard.set(sort.rawValue, forKey: "songSort")
    }
    func importURLs(_ urls: [URL]) async {
        guard !isImporting else { return }
        isImporting = true; importMessage = nil
        let result = await importer.run(urls, existing: data.songs)
        data.songs = result.songs
        for folder in Set(result.songs.map(\.folder)).subtracting(result.previousFolders) {
            let lower = folder.lowercased()
            if ["recording", "录音", "通话", "voice memo", "voicerecorder"].contains(where: lower.contains) { data.excludedFolders.insert(folder) }
        }
        persist(); isImporting = false
        importMessage = "已导入 \(result.added) 首，更新 \(result.updated) 首，跳过重复 \(result.duplicates) 首。"
        if !result.failures.isEmpty { importMessage! += "\n\n" + result.failures.prefix(15).joined(separator: "\n") }
        PlaybackController.shared.refreshLibrary()
    }
    func rescan() async { await importURLs([LibraryPaths.music]) }
    func importLyrics(_ url: URL, song: Song) async {
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() } }
        guard let content = LRCParser.read(url), !content.isEmpty else { errorMessage = "无法读取歌词文件，请选择 UTF-8、UTF-16 或 GB18030 编码的 LRC。"; return }
        guard let index = data.songs.firstIndex(where: { $0.id == song.id }) else { return }
        do {
            try content.write(to: song.fileURL.deletingPathExtension().appendingPathExtension("lrc"), atomically: true, encoding: .utf8)
            data.songs[index].lyrics = content; persist(); PlaybackController.shared.refreshLibrary()
        } catch { errorMessage = error.localizedDescription }
    }
    func favorite(_ song: Song) {
        if data.favorites.contains(song.id) { data.favorites.remove(song.id) } else { data.favorites.insert(song.id) }
        persist()
    }
    func createPlaylist(_ name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        data.playlists.append(Playlist(name: cleaned)); persist()
    }
    func renamePlaylist(_ id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = data.playlists.firstIndex(where: { $0.id == id }) else { return }
        data.playlists[index].name = name; persist()
    }
    func deletePlaylist(_ id: UUID) { data.playlists.removeAll { $0.id == id }; persist() }
    func add(_ song: Song, to playlist: UUID) {
        guard let index = data.playlists.firstIndex(where: { $0.id == playlist }), !data.playlists[index].songIDs.contains(song.id) else { return }
        data.playlists[index].songIDs.append(song.id); persist()
    }
    func remove(_ song: Song, from playlist: UUID) {
        guard let index = data.playlists.firstIndex(where: { $0.id == playlist }) else { return }
        data.playlists[index].songIDs.removeAll { $0 == song.id }; persist()
    }
    func playlistSongs(_ id: UUID) -> [Song] {
        let dictionary = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        return data.playlists.first { $0.id == id }?.songIDs.compactMap { dictionary[$0] } ?? []
    }
    func setFolder(_ folder: String, included: Bool) {
        if included { data.excludedFolders.remove(folder) } else { data.excludedFolders.insert(folder) }
        persist()
    }
    func delete(_ song: Song) {
        guard !isImporting else { errorMessage = "请等待本次导入完成后再删除音频。"; return }
        do {
            if FileManager.default.fileExists(atPath: song.fileURL.path) { try FileManager.default.removeItem(at: song.fileURL) }
            data.songs.removeAll { $0.id == song.id }; data.favorites.remove(song.id)
            for index in data.playlists.indices { data.playlists[index].songIDs.removeAll { $0 == song.id } }
            persist(); PlaybackController.shared.removeSong(song.id)
        } catch { errorMessage = "删除失败：\(error.localizedDescription)" }
    }
}

struct ImportResult {
    var songs: [Song]
    var previousFolders: Set<String>
    var added = 0, updated = 0, duplicates = 0
    var failures: [String] = []
}

actor ImportWorker {
    static let audio = Set(["mp3", "flac", "m4a", "mp4", "m4b", "aac", "wav", "aif", "aiff", "aifc", "caf", "alac"])
    static let sidecars = Set(["lrc", "jpg", "jpeg", "png", "heic"])
    func run(_ roots: [URL], existing: [Song]) async -> ImportResult {
        var result = ImportResult(songs: existing, previousFolders: Set(existing.map(\.folder)))
        var positions = Dictionary(uniqueKeysWithValues: existing.enumerated().map { ($0.element.id, $0.offset) })
        for root in roots {
            let accessed = root.startAccessingSecurityScopedResource()
            defer { if accessed { root.stopAccessingSecurityScopedResource() } }
            do {
                let isDirectory = try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                let isOwnMusic = root.standardizedFileURL.path == LibraryPaths.music.standardizedFileURL.path
                var candidates: [URL] = []
                if isDirectory {
                    if let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                        for case let file as URL in iterator {
                            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                            if values?.isRegularFile == true, values?.isSymbolicLink != true { candidates.append(file) }
                        }
                    }
                } else { candidates = [root] }
                func relative(_ file: URL) -> String {
                    if isOwnMusic { return String(file.path.dropFirst(root.path.count + 1)) }
                    if isDirectory { return root.lastPathComponent + "/" + String(file.path.dropFirst(root.path.count + 1)) }
                    return "导入的音乐/" + file.lastPathComponent
                }
                // Copy sidecars first so a folder import finds LRC and cover art immediately.
                for file in candidates where Self.sidecars.contains(file.pathExtension.lowercased()) {
                    let destination = LibraryPaths.music.appendingPathComponent(relative(file))
                    do { try coordinatedCopy(file, to: destination, replace: true) }
                    catch { result.failures.append("\(file.lastPathComponent)：\(error.localizedDescription)"); continue }
                    if file.pathExtension.lowercased() == "lrc", let lyrics = LRCParser.read(destination) {
                        let matches = result.songs.indices.filter {
                            (result.songs[$0].relativePath as NSString).deletingPathExtension.lowercased() == (relative(file) as NSString).deletingPathExtension.lowercased()
                        }
                        for index in matches { result.songs[index].lyrics = lyrics; result.updated += 1 }
                    }
                }
                for file in candidates where Self.audio.contains(file.pathExtension.lowercased()) {
                    do {
                        var destination = LibraryPaths.music.appendingPathComponent(relative(file))
                        // Hash coordinated source reads in chunks for duplicate detection.
                        let hash = try coordinatedHash(file)
                        if let index = positions[hash] {
                            if !FileManager.default.fileExists(atPath: result.songs[index].fileURL.path) {
                                try coordinatedCopy(file, to: result.songs[index].fileURL, replace: false)
                            }
                            let sidecar = sidecarURL(for: destination)
                            if let sidecar, let content = LRCParser.read(sidecar) {
                                result.songs[index].lyrics = content; result.updated += 1
                            } else { result.duplicates += 1 }
                            continue
                        }
                        if destination.standardizedFileURL != file.standardizedFileURL,
                           FileManager.default.fileExists(atPath: destination.path) {
                            destination = destination.deletingPathExtension().appendingPathExtension(String(hash.prefix(8)) + "." + file.pathExtension)
                        }
                        try coordinatedCopy(file, to: destination, replace: false)
                        let audio = try AVAudioFile(forReading: destination)
                        guard audio.length > 0, audio.processingFormat.sampleRate > 0 else { throw ImportError.invalidAudio }
                        var tags = await AudioMetadata.read(destination)
                        let stem = LibraryPaths.music.appendingPathComponent(relative(file)).deletingPathExtension()
                        if let sidecar = sidecarURL(for: stem.appendingPathExtension(file.pathExtension)), let content = LRCParser.read(sidecar) { tags.lyrics = content }
                        if tags.artwork == nil {
                            let parent = destination.deletingLastPathComponent()
                            let covers = [stem.appendingPathExtension("jpg"), stem.appendingPathExtension("png"), parent.appendingPathComponent("cover.jpg"), parent.appendingPathComponent("folder.jpg"), parent.appendingPathComponent("cover.png")]
                            for cover in covers {
                                if let size = try? cover.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 20_000_000, let image = try? Data(contentsOf: cover) { tags.artwork = image; break }
                            }
                        }
                        var artwork: String?
                        if let raw = tags.artwork, let thumbnail = AudioMetadata.thumbnail(raw) {
                            artwork = hash + ".jpg"
                            try thumbnail.write(to: LibraryPaths.artwork.appendingPathComponent(artwork!), options: .atomic)
                        }
                        let path = String(destination.path.dropFirst(LibraryPaths.music.path.count + 1))
                        let folder = (path as NSString).deletingLastPathComponent
                        let song = Song(id: hash, title: tags.title?.nilIfBlank ?? file.deletingPathExtension().lastPathComponent,
                            artist: tags.artist?.nilIfBlank ?? "未知艺术家", album: tags.album?.nilIfBlank ?? "未知专辑",
                            relativePath: path, folder: folder.isEmpty ? "Music" : folder,
                            duration: Double(audio.length) / audio.processingFormat.sampleRate, addedAt: Date(),
                            artworkPath: artwork, lyrics: tags.lyrics, trackNumber: tags.track)
                        positions[hash] = result.songs.count; result.songs.append(song); result.added += 1
                    } catch { result.failures.append("\(file.lastPathComponent)：无法导入（\(error.localizedDescription)）") }
                }
                for file in candidates where ["ogg", "opus", "wma", "ape"].contains(file.pathExtension.lowercased()) {
                    result.failures.append("\(file.lastPathComponent)：当前原生音频引擎不支持此格式，请先无损转为 FLAC 或 WAV。")
                }
                if isOwnMusic {
                    result.songs.removeAll { !FileManager.default.fileExists(atPath: $0.fileURL.path) }
                    positions = Dictionary(uniqueKeysWithValues: result.songs.enumerated().map { ($0.element.id, $0.offset) })
                }
            } catch { result.failures.append("\(root.lastPathComponent)：\(error.localizedDescription)") }
        }
        return result
    }
    private func sidecarURL(for audio: URL) -> URL? {
        let target = audio.deletingPathExtension().lastPathComponent.lowercased() + ".lrc"
        return (try? FileManager.default.contentsOfDirectory(at: audio.deletingLastPathComponent(), includingPropertiesForKeys: nil))?.first { $0.lastPathComponent.lowercased() == target }
    }
    private func coordinatedCopy(_ source: URL, to destination: URL, replace: Bool) throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?, copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            do {
                let temp = destination.deletingLastPathComponent().appendingPathComponent(".import-" + UUID().uuidString)
                try FileManager.default.copyItem(at: readable, to: temp)
                defer { try? FileManager.default.removeItem(at: temp) }
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temp.path)
                if FileManager.default.fileExists(atPath: destination.path) {
                    guard replace else { return }
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
                } else { try FileManager.default.moveItem(at: temp, to: destination) }
            } catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }
    private func coordinatedHash(_ source: URL) throws -> String {
        var coordinationError: NSError?, readError: Error?, digest = ""
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            do {
                let handle = try FileHandle(forReadingFrom: readable)
                defer { try? handle.close() }
                var hasher = SHA256()
                while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty { hasher.update(data: bytes) }
                digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            } catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        return digest
    }
    enum ImportError: LocalizedError {
        case invalidAudio
        var errorDescription: String? { "音频为空或无法解码" }
    }
}

extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
