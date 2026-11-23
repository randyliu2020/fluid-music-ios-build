# 流体音乐：Android 功能提取与 iOS 移植对照

分析日期：2026-11-22。Android 基线：`d6a739b6ab2ab44377c425afb2679d1bec8e709a`，源码与仓库 v1.17 功能说明交叉核对。

原项目为 Kotlin / Jetpack Compose / Media3 本地播放器，不包含在线音源、联网搜索、JS 音源导入或音乐下载。iOS 工程采用 SwiftUI / AVAudioEngine / AVAudioUnitEQ / MediaPlayer / WidgetKit，保留本地、无账号、无广告的定位。

“实现”表示已加入源码；构建与模拟器验证以对应 GitHub Actions 运行、test-summary.json、xcresult 为准。未取得用户真机反馈前，不宣称“完美适配”或真机全功能验收通过。

| Android 功能及源码证据 | iOS 对应实现 | 差异与验证边界 |
|---|---|---|
| MediaStore 自动扫描，MusicRepository / MediaStoreScanner | 文件/文件夹导入、Music 目录重扫，SHA-256 内容去重 | iOS 沙盒无法全盘扫描；通过系统文件选择器授权并复制到 App 内 |
| 歌曲、专辑、艺术家、文件夹浏览 | 原生导航页面、分类浏览 | 专辑以专辑名＋艺术家分组，降低同名专辑混淆 |
| 标题/艺术家/专辑/添加时间/时长排序 | 五种排序，选择持久化 | 中文通过系统拉丁转写进行拼音排序与 A–Z/# 索引 |
| 实时搜索 | 歌名、艺术家、专辑和拼音搜索 | 仅搜索已导入曲库 |
| 歌单新建/重命名/删除、添加移除 | 本地 JSON 持久化；收藏独立管理 | 删除歌单保留文件；删除音频副本需要确认 |
| Media3 前台播放与媒体会话 | AVAudioEngine、AVAudioSession playback、后台音频 | 系统强制退出后不能继续播放 |
| ColorOS 流体云/常驻通知 | MPNowPlayingInfoCenter + MPRemoteCommandCenter | 接入 iOS 锁屏、控制中心、耳机与系统灵动岛媒体呈现；不复制安卓通知 |
| 播放、暂停、上下首、seek | 原生播放控制、系统远程 seek | 切换设备、来电和拔耳机代码已处理，蓝牙/来电需真机验证 |
| 随机、列表循环、单曲循环、关闭 | 三种循环＋随机；保存原队列恢复顺序 | 无循环时播放完末曲停止 |
| 队列半屏弹层、高亮和定位 | medium/large 原生 sheet，定位当前曲 | 另支持拖动排序、删除队列项 |
| 队列/当前曲/进度持久化 | 相对文件路径＋JSON 原子写；每 3 秒、暂停、seek、后台时保存 | 重启默认暂停；突然进程终止可能损失最后约 3 秒 |
| 15/30/45/60/90 分钟睡眠定时 | 到时暂停，可取消、查看倒计时 | 不跨进程重启保存定时 |
| Android 系统级均衡器/预设 | App 内 AVAudioUnitEQ 十段 ±12dB、预设、自动保存 | 只影响本 App；加增益时自动预留音频余量 |
| 同名 LRC、标签 USLT/SYLT、FLAC LYRICS、M4A ©lyr | LRC 文件、MP3/FLAC 有界标签解析、AVFoundation M4A 元数据读取 | SYLT 只支持毫秒时间单位，MPEG frame 时间不冒充毫秒 |
| 同步滚动、点词跳转、纯文本回退 | 滚动跟随、点击跳转、手动浏览和恢复跟随 | 无歌词时提供单独导入 LRC；支持 UTF-8/UTF-16/GB18030 |
| 副歌节点检测 | 对重复歌词计数，标注首个高频重复行 | 启发式估算，非音频/AI 副歌识别，不保证每首正确 |
| 内嵌/同名/文件夹封面 | 内嵌图、同名 JPG/PNG、cover.jpg、folder.jpg | 图像下采样缓存以控制曲库内存 |
| 旋转黑胶、唱臂、高光与纹路 | SwiftUI Canvas 唱片、封面、旋转与抬臂 | 减少动态效果时停止旋转，后台停动画刷新 |
| 封面/歌词左右切换 | 原生分页 TabView、手动切换按钮 | 播放页原生下滑关闭；导航系统侧滑返回 |
| 迷你播放条、可拖进度、副歌节点 | 原生 tabViewBottomAccessory、进度条、播放/下一首 | 不硬编码 TabBar 高度，避让系统安全区 |
| 磨砂封面背景、深色、Material You | 封面模糊、深/浅/系统主题、Liquid Glass 控件 | iOS 系统外观，无 Android 壁纸动态取色 |
| 默认排除录音文件夹 | 新导入录音目录默认隐藏，可恢复 | 使用文件夹名规则，不全盘扫描 |
| 桌面封面与播放控制小组件 | WidgetKit small/medium、AudioPlaybackIntent 三键 | 单独提供 with-widget 包；需正确 App Groups 签名与真机验证 |
| Android 支持 MP3/FLAC/M4A/WAV/Ogg 等 | 系统可解码 MP3/AAC/M4A/ALAC/FLAC/WAV/AIFF/CAF | **本次未加入 Ogg/Opus/WMA/APE 解码器**，导入明确报出；DRM 音频不支持 |
| APK 自动构建发布 | Xcode 27 SDK arm64 编译、模拟器单元/UI 测试、IPA artifacts | IPA 未签名，用户重签；构建不等同实机验收 |

## iOS 27 适配范围

- SwiftUI `App` / scene 生命周期，符合 iOS 27 场景生命周期要求。
- 原生 Liquid Glass Tab/Navigation/菜单/按钮，以及系统 sheet 交互。
- iPhone 与 iPad 自适应导航、安全区和方向支持；大字时允许滚动，支持 VoiceOver、降低透明度、减少动态效果。
- `AVAudioSession` 延迟到播放时激活，锁屏后台音频、系统播放状态同步。
- 不引入联网 SDK，不要求通知、通讯录、位置或麦克风权限。
- 签名版若需要小组件，App 与扩展必须配置同一 App Group；普通自签包移除扩展与共享组配置，降低安装门槛。

## 测试分层

单元测试：LRC 多时间戳、offset、异常时间与稳定排序；副歌启发式；ID3 USLT/SYLT、畸形帧边界；拼音索引；播放快照序列化。

模拟器 UI 测试：生成无版权合成测试音频，执行导入→播放→歌词→队列→收藏，重开暂停恢复，均衡器页面。测试音频仅 Debug 测试参数触发，Release 不携带演示歌曲。

真机待验收：用户重签安装、长时间锁屏、蓝牙耳机断连/重连、来电中断、AirPlay、系统灵动岛实际呈现、文件提供器/iCloud/U 盘，以及带授权共享组的小组件。真实 MP3/M4A/FLAC 文件应覆盖不同采样率、标签编码与损坏文件。

## Apple 与工具链依据

- https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes
- https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback
- https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md
