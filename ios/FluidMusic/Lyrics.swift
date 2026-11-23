import Foundation

struct LyricLine: Identifiable, Equatable {
    var id: Int
    var time: Double
    var text: String
}

struct Lyrics: Equatable {
    var lines: [LyricLine] = []
    var plain: String = ""
    var chorus: Double? {
        guard lines.count >= 4 else { return nil }
        var counts: [String: (count: Int, first: Double)] = [:]
        for line in lines {
            let key = line.text.lowercased().filter { $0.isLetter || $0.isNumber }
            guard key.count >= 2 else { continue }
            let old = counts[key] ?? (0, line.time)
            counts[key] = (old.count + 1, min(old.first, line.time))
        }
        let best = counts.values.sorted { $0.count == $1.count ? $0.first < $1.first : $0.count > $1.count }.first
        guard let best, best.count >= 2, best.first > 1 else { return nil }
        return best.first
    }
    func activeIndex(at position: Double) -> Int? {
        // Upper bound: duplicate timestamps select the last matching line.
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= position { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? low - 1 : nil
    }
}

enum LRCParser {
    static func parse(_ text: String) -> Lyrics {
        let time = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:\s*([+-]?\d+)\]"#, options: .caseInsensitive)
        let full = text as NSString
        let offsetMatch = offsetPattern.firstMatch(in: text, range: NSRange(location: 0, length: full.length))
        let offset = offsetMatch.flatMap { Double(full.substring(with: $0.range(at: 1))) } ?? 0
        var rows: [(Double, String)] = [], plain: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") {
            let ns = raw as NSString
            let tags = time.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            let start = tags.last.map { NSMaxRange($0.range) } ?? 0
            let content = ns.substring(from: start)
                .replacingOccurrences(of: #"<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if tags.isEmpty && content.range(of: #"^\[(ti|ar|al|by|offset|length|re|ve|au):"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            guard !content.isEmpty else { continue }
            plain.append(content)
            for tag in tags {
                let minutes = Double(ns.substring(with: tag.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: tag.range(at: 2))) ?? 0
                guard seconds < 60 else { continue }
                let fraction = tag.range(at: 3).location == NSNotFound ? 0 : (Double("0." + ns.substring(with: tag.range(at: 3))) ?? 0)
                rows.append((max(0, minutes * 60 + seconds + fraction - offset / 1000), content))
            }
        }
        let sorted = rows.enumerated().sorted { $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0 }
        return Lyrics(lines: sorted.enumerated().map { LyricLine(id: $0.offset, time: $0.element.element.0, text: $0.element.element.1) }, plain: plain.joined(separator: "\n"))
    }
    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count <= 5_000_000 else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .init(rawValue: 0x80000632)) // GB18030
    }
}
