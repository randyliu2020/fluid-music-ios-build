# 流体音乐 · iOS

SwiftUI 原生本地音乐播放器，面向 iOS 27，最低支持 iOS 26.1。

从流体音乐 Android v1.17 提取功能后移植：本地曲库、文件夹/专辑/艺术家、搜索、收藏和歌单、黑胶播放页、同步歌词、十段均衡器、后台播放、系统媒体控制、睡眠定时及可选桌面小组件。

- [完整功能提取与移植对照](docs/ios-feature-matrix.md)
- [IPA 自行签名、安装与验收](docs/ios-install.md)
- [构建记录与下载](https://github.com/randyliu2020/fluid-music-ios-build/actions/workflows/build-ios.yml)
- [iOS 工程说明](ios/README.md)

## 构建与安装

GitHub Actions 使用 Xcode 27 SDK 编译 arm64 真机应用，并运行 iOS 27 模拟器测试。构建完成后，从同一次运行的 `FluidMusic-iOS-unsigned-buildN` artifact 下载 IPA。优先选择 `self-sign-unsigned.ipa`，使用自己的签名工具重签安装。`with-widget` 版本另需匹配的 App Groups 授权。

仓库包含源码不代表已通过构建。实际结果以 Actions 日志与测试报告为准；未完成真机验收时不宣称“完美适配”。

## 边界

纯本地播放器，不包含在线音源、JS 音源或下载。支持系统可解码的 MP3/AAC/M4A/ALAC/FLAC/WAV/AIFF/CAF；本版未加入 Ogg/Opus/WMA/APE 解码器，不支持 DRM 音频。小组件、蓝牙/来电、AirPlay 和长时间锁屏需要签名后在真机验收。

本仓库仅包含 iOS 实现、测试、构建文件、功能说明及应用图标。
