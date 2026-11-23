import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlaybackController
    @AppStorage("appearance") private var appearance = "深色"
    @State private var sleep = false
    var importFiles: () -> Void
    var importFolder: () -> Void
    var body: some View {
        Form {
            Section("曲库") {
                Button("导入歌曲与歌词", systemImage: "doc.badge.plus", action: importFiles).disabled(library.isImporting)
                Button("导入整个文件夹", systemImage: "folder.badge.plus", action: importFolder).disabled(library.isImporting)
                NavigationLink { FolderManagementView() } label: { Label("管理曲库文件夹", systemImage: "folder") }
                Button("重新扫描 Music 文件夹", systemImage: "arrow.clockwise") { Task { await library.rescan() } }.disabled(library.isImporting)
                LabeledContent("曲库歌曲", value: "\(library.data.songs.count) 首")
            }
            Section("播放") {
                NavigationLink { EqualizerView() } label: { Label("均衡器", systemImage: "slider.vertical.3") }
                Button("睡眠定时", systemImage: "moon") { sleep = true }
                LabeledContent("播放模式", value: player.repeatMode.label)
            }
            Section("外观") {
                Picker("主题", selection: $appearance) { ForEach(["跟随系统", "深色", "浅色"], id: \.self) { Text($0).tag($0) } }
                Text("使用原生液态玻璃导航。跟随系统的字体大小、减少动态效果和降低透明度设置。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("使用说明") {
                NavigationLink("文件、歌词和导入") { ImportHelpView() }
                NavigationLink("锁屏、灵动岛与后台播放") { PlaybackHelpView() }
                if Bundle.main.object(forInfoDictionaryKey: "FluidMusicAppGroup") as? String != "" {
                    LabeledContent("小组件共享数据", value: WidgetStorage.container == nil ? "签名未启用 App Groups" : "已启用")
                }
            }
            Section {
                LabeledContent("流体音乐 iOS", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                Text("本地音乐 · 无广告 · 无账号\n歌曲、歌单、歌词与播放记录保存在设备上。App 不请求网络接口。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.musicBackground().navigationTitle("设置")
            .sheet(isPresented: $sleep) { SleepTimerView().presentationDetents([.medium, .large]) }
    }
}

struct EqualizerView: View {
    @EnvironmentObject private var player: PlaybackController
    var body: some View {
        Form {
            Section {
                Toggle("启用均衡器", isOn: Binding(get: { player.eqEnabled }, set: player.setEQEnabled))
                Menu("选择预设") {
                    ForEach(PlaybackController.presets.indices, id: \.self) { index in
                        Button(PlaybackController.presets[index].0) { player.applyPreset(PlaybackController.presets[index].1) }
                    }
                }
            }
            Section("10 段均衡 · ±12 dB") {
                ForEach(PlaybackController.frequencies.indices, id: \.self) { index in
                    VStack(spacing: 7) {
                        HStack {
                            Text(frequencyLabel(PlaybackController.frequencies[index])).font(.subheadline)
                            Spacer()
                            Text(String(format: "%+.1f dB", player.eqGains[index])).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(get: { Double(player.eqGains[index]) }, set: { player.setGain(Float($0), band: index) }), in: -12...12, step: 0.5)
                            .accessibilityLabel(frequencyLabel(PlaybackController.frequencies[index]))
                    }.padding(.vertical, 5)
                }
            }.disabled(!player.eqEnabled)
            Section {
                Button("恢复平直") { player.applyPreset(Array(repeating: 0, count: 10)) }
                Text("均衡器只作用于流体音乐播放的音频。增益提高时自动预留输出余量，降低削波风险。设置自动保存。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.musicBackground().navigationTitle("均衡器").navigationBarTitleDisplayMode(.inline)
    }
    private func frequencyLabel(_ value: Float) -> String { value >= 1000 ? String(format: "%.0f kHz", value / 1000) : String(format: "%.0f Hz", value) }
}

struct FolderManagementView: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        Form {
            Section {
                ForEach(library.allFolders, id: \.self) { folder in
                    Toggle(folder, isOn: Binding(get: { !library.data.excludedFolders.contains(folder) }, set: { library.setFolder(folder, included: $0) }))
                }
            } footer: { Text("关闭文件夹会将其从曲库浏览中隐藏，保留已导入的音频。新导入的录音文件夹默认隐藏。") }
        }.navigationTitle("文件夹管理").musicBackground()
    }
}
struct ImportHelpView: View {
    var body: some View {
        List {
            Section("导入方式") {
                Text("在音乐库右上角点“＋”，选择歌曲或整个文件夹。可以从“我的 iPhone”、iCloud Drive、U 盘及已安装的文件提供器中选择。云端文件由系统先下载后导入。")
                Text("也可以用电脑文件共享，将音乐复制到“流体音乐/Music”，再在设置里重新扫描。iOS 不允许 App 自动扫描其他 App 的私有文件。")
            }
            Section("歌词与封面") {
                Text("导入整个文件夹时，同名 LRC、同名 JPG/PNG、cover.jpg 和 folder.jpg 会一并读取。单独补充歌词可在歌曲“更多操作”中选择“导入歌词”。")
                Text("支持 MP3 的 USLT/SYLT、FLAC 的 Vorbis 歌词和封面，以及系统可读取的 M4A/MP4 内嵌标签。副歌位置根据重复歌词估算。")
            }
            Section("格式") {
                Text("支持系统可解码的 MP3、AAC、M4A/ALAC、FLAC、WAV、AIFF 和 CAF。受 DRM 保护的文件不支持。")
                Text("本版本未集成 Ogg/Opus、WMA、APE 解码器。导入时会明确提示，请先转为 FLAC 或 WAV 保留现有音质。")
            }
            Section("数据") {
                Text("按音频内容去重。卸载 App 会删除导入副本、歌单及收藏，卸载前请通过“文件”或电脑文件共享备份。")
            }
        }.navigationTitle("文件与歌词").navigationBarTitleDisplayMode(.inline)
    }
}
struct PlaybackHelpView: View {
    var body: some View {
        List {
            Section("系统媒体控制") {
                Text("开始播放后，可以通过锁屏、控制中心、耳机按钮和支持机型的灵动岛控制播放。灵动岛的展示由 iOS 管理。")
            }
            Section("后台与耳机") {
                Text("锁屏或返回主屏幕可以继续播放。拔出耳机或断开当前音频设备时暂停；来电等系统中断结束后，按系统允许情况恢复。手动强制退出 App 会停止播放。")
                Text("播放页底部可选择 AirPlay 或蓝牙输出设备。音量使用系统音量控制。")
            }
            Section("恢复与定时") {
                Text("队列、歌曲、进度、随机和循环模式自动保存。重开 App 恢复为暂停，点播放即可继续。睡眠定时到点暂停，本次定时不跨 App 重启恢复。")
            }
            Section("桌面小组件") {
                Text("小组件版需要为主 App 和扩展配置同一 App Group，并使用支持该能力的签名。普通自签版可直接使用系统锁屏、控制中心与灵动岛。")
            }
        }.navigationTitle("系统播放控制").navigationBarTitleDisplayMode(.inline)
    }
}
