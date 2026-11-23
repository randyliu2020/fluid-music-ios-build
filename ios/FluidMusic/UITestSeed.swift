#if DEBUG
import Foundation
import AVFoundation

@MainActor enum UITestSeed {
    static func prepare() async {
        let library = LibraryStore.shared
        guard library.data.songs.isEmpty else { return }
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("试听测试", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for (index, title) in ["晨光", "微风", "夜航"].enumerated() {
                let url = root.appendingPathComponent(title + ".wav")
                if !FileManager.default.fileExists(atPath: url.path) {
                    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
                    let file = try AVAudioFile(forWriting: url, settings: format.settings)
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
                    buffer.frameLength = 44_100
                    for frame in 0..<44_100 {
                        buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * Double(220 + index * 110) / 44_100)) * 0.015
                    }
                    for _ in 0..<60 { try file.write(from: buffer) }
                }
                try "[00:00.00]测试前奏\n[00:05.00]微风带来一段旋律\n[00:10.00]让音乐留在此刻\n[00:15.00]微风带来一段旋律\n[00:20.00]测试结束\n".write(to: root.appendingPathComponent(title + ".lrc"), atomically: true, encoding: .utf8)
            }
            await library.importURLs([root]); library.importMessage = nil
        } catch { library.errorMessage = "测试音频准备失败：\(error.localizedDescription)" }
    }
}
#endif
