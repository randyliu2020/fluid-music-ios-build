# FluidMusic for iOS

SwiftUI 原生本地音乐播放器；从流体音乐 Android v1.17 的已实现功能移植。支持 iOS 26.1+，CI 强制使用 iOS 27 SDK 并在 iOS 27 模拟器执行测试。

- [功能对照](../docs/ios-feature-matrix.md)
- [未签名 IPA 安装和构建](../docs/ios-install.md)
- 构建入口：`.github/workflows/build-ios.yml`
- 工程生成：`xcodegen generate`；不手改生成的 `.xcodeproj`。
- `self-sign` 包移除 Widget 扩展和共享组声明；`with-widget` 包要求 App Groups 签名。

主要实现：`LibraryStore.swift` 导入及曲库；`AudioMetadata.swift` 标签；`Lyrics.swift` 歌词；`PlaybackController.swift` 音频、EQ、系统媒体会话；`*Views.swift` 原生页面；`Shared/WidgetStorage.swift` 与 `FluidMusicWidget` 为扩展。

测试范围与真机待验收项目详见功能对照。未完成真实设备验证时不宣称完美适配。
