import XCTest
import AVFoundation
@testable import FluidMusic

final class FluidMusicTests: XCTestCase {
    func testLRCMultiTimestampOffsetAndWordTags() {
        let lyrics = LRCParser.parse("[ar:歌手]\n[offset:250]\n[00:01.5][00:12:250]<00:01.50>你好\n[00:20]再见")
        XCTAssertEqual(lyrics.lines.map(\.time), [1.25, 12, 19.75])
        XCTAssertEqual(lyrics.lines.map(\.text), ["你好", "你好", "再见"])
        XCTAssertEqual(lyrics.plain, "你好\n再见")
        XCTAssertNil(lyrics.activeIndex(at: 0))
        XCTAssertEqual(lyrics.activeIndex(at: 12), 1)
    }
    func testLRCNegativeOffsetAndStableDuplicateTimestamps() {
        let lyrics = LRCParser.parse("[offset:-500]\n[00:02]一\n[00:01]二\n[00:01]三\n[00:99]无效")
        XCTAssertEqual(lyrics.lines.map(\.time), [1.5, 1.5, 2.5])
        XCTAssertEqual(lyrics.lines.map(\.text), ["二", "三", "一"])
        XCTAssertEqual(lyrics.activeIndex(at: 1.5), 1)
    }
    func testChorusUsesRepeatedLyricsAndEarliestTie() {
        let lyrics = LRCParser.parse("[00:03]重复第一句\n[00:05]重复第二句\n[00:10]重复第二句\n[00:12]重复第一句")
        XCTAssertEqual(lyrics.chorus, 3)
        XCTAssertNil(LRCParser.parse("[00:00]重复\n[00:01]其他\n[00:02]重复\n[00:03]结束").chorus)
        XCTAssertNil(LRCParser.parse("纯文本歌词").chorus)
    }
    func testID3UnsynchronizedLyricsAndTitle() {
        func frame(_ name: String, _ bytes: [UInt8]) -> [UInt8] {
            let count = bytes.count
            return Array(name.utf8) + [UInt8(count >> 24), UInt8(count >> 16 & 255), UInt8(count >> 8 & 255), UInt8(count & 255), 0, 0] + bytes
        }
        let body = frame("TIT2", [3] + Array("测试歌曲".utf8)) + frame("USLT", [3, 101, 110, 103, 0] + Array("[00:05]测试歌词".utf8))
        let tags = EmbeddedTags.id3(header: [73, 68, 51, 3, 0, 0, 0, 0, 0, 0], body: body)
        XCTAssertEqual(tags.title, "测试歌曲")
        XCTAssertEqual(tags.lyrics, "[00:05]测试歌词")
        XCTAssertNil(EmbeddedTags.id3(header: [0], body: []).lyrics)
    }
    func testID3SYLTRejectsMPEGFrameUnits() {
        let payload: [UInt8] = [3,101,110,103,1,1,0,65,0,0,0,3,232]
        let frame = Array("SYLT".utf8) + [0,0,0,UInt8(payload.count),0,0] + payload
        XCTAssertNil(EmbeddedTags.id3(header: [73,68,51,3,0,0,0,0,0,0], body: frame).lyrics)
        var valid = frame; valid[14] = 2
        XCTAssertEqual(EmbeddedTags.id3(header: [73,68,51,3,0,0,0,0,0,0], body: valid).lyrics, "[00:01.000]A")
    }
    func testSnapshotKeepsQueueAndShuffleOrder() throws {
        let original = PlaybackSnapshot(queue: ["b", "a"], originalQueue: ["a", "b"], currentID: "b", position: 31.25, repeatMode: .one, shuffled: true)
        let restored = try JSONDecoder().decode(PlaybackSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.queue, ["b", "a"])
        XCTAssertEqual(restored.originalQueue, ["a", "b"])
        XCTAssertEqual(restored.position, 31.25)
        XCTAssertEqual(restored.repeatMode, .one)
        XCTAssertTrue(restored.shuffled)
    }
    func testPinyinIndexAndTimeFormatting() {
        XCTAssertEqual(Song.indexLetter("张三"), "Z")
        XCTAssertEqual(Song.indexLetter("陈奕迅"), "C")
        XCTAssertEqual(Song.indexLetter("123"), "#")
        XCTAssertEqual(timeText(.nan), "0:00")
        XCTAssertEqual(timeText(3661), "1:01:01")
    }
    func testMalformedTagBoundsAreSafe() {
        for size in 0..<32 {
            let bytes = Array(repeating: UInt8(255), count: size)
            _ = EmbeddedTags.id3(header: [73,68,51,4,0,64,0,0,0,0], body: bytes)
            XCTAssertEqual(EmbeddedTags.integer(bytes, size, 4), 0)
        }
    }

    func testFolderImportDeduplicatesAndRepairsMissingCopy() async throws {
        try LibraryPaths.prepare()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("ImportTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let destination = LibraryPaths.music.appendingPathComponent(source.lastPathComponent)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let audio = source.appendingPathComponent("测试.wav")
        do {
            let file = try AVAudioFile(forWriting: audio, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
            buffer.frameLength = 4410
            for i in 0..<4410 { buffer.floatChannelData![0][i] = Float(i % 23) / 1000 }
            try file.write(from: buffer)
        }
        try "[00:00.00]导入测试歌词".write(to: source.appendingPathComponent("测试.lrc"), atomically: true, encoding: .utf8)
        let importer = ImportWorker()
        let first = await importer.run([source], existing: [])
        XCTAssertTrue(first.failures.isEmpty, first.failures.joined(separator: "\n"))
        XCTAssertEqual(first.songs.count, 1)
        let song = try XCTUnwrap(first.songs.first)
        XCTAssertEqual(song.lyrics, "[00:00.00]导入测试歌词")
        XCTAssertEqual(song.duration, 0.1, accuracy: 0.001)
        let repeated = await importer.run([source], existing: first.songs)
        XCTAssertEqual(repeated.songs.count, 1)
        XCTAssertEqual(repeated.songs.first?.id, song.id)
        try FileManager.default.removeItem(at: song.fileURL)
        let repaired = await importer.run([source], existing: repeated.songs)
        XCTAssertTrue(repaired.failures.isEmpty)
        XCTAssertEqual(repaired.songs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: song.fileURL.path))
    }
}
