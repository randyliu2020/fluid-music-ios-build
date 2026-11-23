import Foundation
import AVFoundation
import UIKit
import ImageIO

struct AudioTags {
    var title: String?
    var artist: String?
    var album: String?
    var lyrics: String?
    var artwork: Data?
    var track: Int = 0
}

enum AudioMetadata {
    static func read(_ url: URL) async -> AudioTags {
        var result = EmbeddedTags.read(url)
        let asset = AVURLAsset(url: url)
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                switch item.commonKey {
                case .commonKeyTitle: result.title = (try? await item.load(.stringValue)) ?? result.title
                case .commonKeyArtist: result.artist = (try? await item.load(.stringValue)) ?? result.artist
                case .commonKeyAlbumName: result.album = (try? await item.load(.stringValue)) ?? result.album
                case .commonKeyArtwork: result.artwork = (try? await item.load(.dataValue)) ?? result.artwork
                default: break
                }
            }
        }
        if result.lyrics == nil { result.lyrics = try? await asset.load(.lyrics) }
        if result.lyrics == nil, let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                guard let items = try? await asset.loadMetadata(for: format) else { continue }
                for item in items {
                    let key = item.identifier?.rawValue.lowercased() ?? ""
                    if key.contains("lyrics") || key.contains("uslt") || key.contains("©lyr") {
                        if let text = try? await item.load(.stringValue), !text.isEmpty { result.lyrics = text; break }
                    }
                }
                if result.lyrics != nil { break }
            }
        }
        return result
    }

    static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 900,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.85)
    }
}

/// Bounded parsers: metadata only, never read an entire lossless audio file into RAM.
enum EmbeddedTags {
    static let limit = 20_000_000
    static func read(_ url: URL) -> AudioTags {
        guard let file = try? FileHandle(forReadingFrom: url) else { return AudioTags() }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 10), header.count >= 4 else { return AudioTags() }
        let bytes = [UInt8](header)
        if String(bytes: bytes.prefix(3), encoding: .ascii) == "ID3", bytes.count == 10 {
            let length = integer(bytes, 6, 4, sync: true)
            guard length > 0, length <= limit, let body = try? file.read(upToCount: length), body.count == length else { return AudioTags() }
            return id3(header: bytes, body: [UInt8](body))
        }
        if String(bytes: bytes.prefix(4), encoding: .ascii) == "fLaC" {
            try? file.seek(toOffset: 4)
            return flac(file)
        }
        return AudioTags()
    }
    static func integer(_ b: [UInt8], _ start: Int, _ count: Int, sync: Bool = false, little: Bool = false) -> Int {
        guard start >= 0, count >= 0, count <= 8, start + count <= b.count else { return 0 }
        let indices = little ? Array((start..<(start + count)).reversed()) : Array(start..<(start + count))
        return indices.reduce(0) { ($0 << (sync ? 7 : 8)) | Int(b[$1] & (sync ? 0x7f : 0xff)) }
    }
    static func text(_ b: [UInt8], encoding: UInt8 = 3) -> String {
        let enc: String.Encoding = encoding == 0 ? .isoLatin1 : encoding == 1 ? .utf16 : encoding == 2 ? .utf16BigEndian : .utf8
        return (String(data: Data(b), encoding: enc) ?? "").trimmingCharacters(in: .init(charactersIn: "\0\u{feff}\n\r "))
    }
    static func terminated(_ b: [UInt8], from start: Int, encoding: UInt8) -> (String, Int) {
        let width = encoding == 1 || encoding == 2 ? 2 : 1
        var end = min(start, b.count)
        while end + width <= b.count {
            if b[end] == 0 && (width == 1 || b[end + 1] == 0) { break }
            end += width
        }
        return (text(Array(b[min(start, b.count)..<min(end, b.count)]), encoding: encoding), min(end + width, b.count))
    }
    static func deunsync(_ bytes: [UInt8]) -> [UInt8] {
        var output: [UInt8] = [], i = 0
        while i < bytes.count {
            output.append(bytes[i])
            if bytes[i] == 255, i + 1 < bytes.count, bytes[i + 1] == 0 { i += 1 }
            i += 1
        }
        return output
    }
    static func id3(header: [UInt8], body input: [UInt8]) -> AudioTags {
        guard header.count == 10, (2...4).contains(header[3]) else { return AudioTags() }
        let version = header[3], flags = header[5]
        let body = flags & 0x80 != 0 && version < 4 ? deunsync(input) : input
        var result = AudioTags(), synced: String?, pos = 0
        if flags & 0x40 != 0 {
            guard version >= 3 else { return result }
            pos = integer(body, 0, 4, sync: version == 4) + (version == 3 ? 4 : 0)
        }
        let headSize = version == 2 ? 6 : 10, nameSize = version == 2 ? 3 : 4
        while pos >= 0, pos + headSize <= body.count {
            let id = text(Array(body[pos..<(pos + nameSize)]), encoding: 0)
            let size = integer(body, pos + nameSize, version == 2 ? 3 : 4, sync: version == 4)
            let frameFlags = version == 2 ? 0 : body[pos + 9]
            pos += headSize
            guard !id.isEmpty, size > 0, size <= body.count - pos else { break }
            var frame = Array(body[pos..<(pos + size)]); pos += size
            // Compressed/encrypted frames require an external decoder; skip safely.
            if version == 3 && frameFlags & 0xc0 != 0 || version == 4 && frameFlags & 0x0c != 0 { continue }
            if version == 4 && (frameFlags & 2 != 0 || flags & 0x80 != 0) { frame = deunsync(frame) }
            if version == 4 && frameFlags & 1 != 0 { frame = Array(frame.dropFirst(4)) }
            if (version == 4 && frameFlags & 0x40 != 0) || (version == 3 && frameFlags & 0x20 != 0) { frame = Array(frame.dropFirst()) }
            guard let enc = frame.first else { continue }
            switch id {
            case "TIT2", "TT2": result.title = text(Array(frame.dropFirst()), encoding: enc)
            case "TPE1", "TP1": result.artist = text(Array(frame.dropFirst()), encoding: enc)
            case "TALB", "TAL": result.album = text(Array(frame.dropFirst()), encoding: enc)
            case "TRCK", "TRK": result.track = Int(text(Array(frame.dropFirst()), encoding: enc).components(separatedBy: "/")[0]) ?? 0
            case "USLT", "ULT":
                guard frame.count >= 4 else { continue }
                let (_, after) = terminated(frame, from: 4, encoding: enc)
                result.lyrics = text(Array(frame.dropFirst(after)), encoding: enc)
            case "SYLT", "SLT":
                guard frame.count >= 7, frame[4] == 2 else { continue } // MPEG frame timestamps are not milliseconds.
                var cursor = terminated(frame, from: 6, encoding: enc).1
                var rows: [String] = []
                while cursor < frame.count {
                    let (line, next) = terminated(frame, from: cursor, encoding: enc)
                    guard next + 4 <= frame.count, next > cursor else { break }
                    let ms = integer(frame, next, 4); cursor = next + 4
                    rows.append(String(format: "[%02d:%02d.%03d]", ms / 60_000, ms / 1000 % 60, ms % 1000) + line)
                }
                if !rows.isEmpty { synced = rows.joined(separator: "\n") }
            case "APIC", "PIC":
                var cursor = id == "PIC" ? 4 : terminated(frame, from: 1, encoding: 0).1
                guard cursor < frame.count else { continue }
                let pictureType = frame[cursor]; cursor += 1
                cursor = terminated(frame, from: cursor, encoding: enc).1
                if cursor < frame.count, result.artwork == nil || pictureType == 3 { result.artwork = Data(frame.dropFirst(cursor)) }
            default: break
            }
        }
        result.lyrics = synced ?? result.lyrics
        return result
    }
    static func flac(_ file: FileHandle) -> AudioTags {
        var tags = AudioTags(), consumed = 0
        while consumed < limit {
            guard let header = try? file.read(upToCount: 4), header.count == 4 else { break }
            let h = [UInt8](header), length = integer(h, 1, 3)
            guard length <= limit - consumed, let block = try? file.read(upToCount: length), block.count == length else { break }
            consumed += length + 4
            let b = [UInt8](block)
            if h[0] & 0x7f == 4, b.count >= 8 {
                var pos = 4 + integer(b, 0, 4, little: true)
                guard pos + 4 <= b.count else { break }
                let count = min(integer(b, pos, 4, little: true), 100_000); pos += 4
                for _ in 0..<count {
                    guard pos + 4 <= b.count else { break }
                    let size = integer(b, pos, 4, little: true); pos += 4
                    guard size <= b.count - pos else { break }
                    let entry = text(Array(b[pos..<(pos + size)])); pos += size
                    guard let equal = entry.firstIndex(of: "=") else { continue }
                    let key = String(entry[..<equal]).uppercased(), value = String(entry[entry.index(after: equal)...])
                    switch key {
                    case "TITLE": tags.title = value
                    case "ARTIST": tags.artist = value
                    case "ALBUM": tags.album = value
                    case "LYRICS", "UNSYNCEDLYRICS", "SYNCEDLYRICS": tags.lyrics = value
                    case "TRACKNUMBER": tags.track = Int(value) ?? 0
                    default: break
                    }
                }
            } else if h[0] & 0x7f == 6, b.count >= 32 {
                let kind = integer(b, 0, 4)
                var pos = 8 + integer(b, 4, 4)
                guard pos + 4 <= b.count else { break }
                pos += 4 + integer(b, pos, 4)
                guard pos + 20 <= b.count else { break }
                pos += 16
                let size = integer(b, pos, 4); pos += 4
                if size <= b.count - pos, tags.artwork == nil || kind == 3 { tags.artwork = Data(b[pos..<(pos + size)]) }
            }
            if h[0] & 0x80 != 0 { break }
        }
        return tags
    }
}
