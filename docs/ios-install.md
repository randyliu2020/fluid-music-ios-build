# 流体音乐 iOS 安装与验收

## 选择哪个 IPA

`FluidMusic-iOS-1.0.0-buildN-self-sign-unsigned.ipa`：优先使用。主 App，适合使用自己已有的 SideStore/AltStore/爱思或签名工具重新签名安装；不带需要 App Groups 的桌面扩展。

`FluidMusic-iOS-1.0.0-buildN-with-widget-unsigned.ipa`：包含桌面小组件。仅当你的证书、描述文件和签名工具支持 App Groups 时使用；主 App 与扩展需要同一共享组。共享组默认 `group.com.randy.fluidmusic.ios`，自有团队通常需替换为自己已注册的组并重新编译/配置两个 Info.plist 和签名授权。

两份包均是 **未签名 arm64 真机应用**，不能下载后直接点击安装。用户已选择自行签名。未签名 IPA 不附带开发者证书、描述文件或可保证安装的有效期。签名与续签规则由你的工具和证书决定。

## 首次使用

1. 下载 self-sign IPA，用你已有的工具重新签名并安装到 iOS 27 设备。
2. 按签名工具与系统实际提示处理开发者模式/开发者信任，不要求更改其他安全设置。
3. 打开“流体音乐”→音乐库“＋”→导入歌曲或文件夹。
4. 建议把音频、同名 LRC、cover.jpg 放在同一文件夹导入。也可用电脑文件共享写入 Music 后重新扫描。
5. 点击歌曲播放；底部迷你栏进入黑胶播放页；左右滑动切换歌词；底部进入队列、AirPlay、睡眠定时。

## 自行编译与签名

macOS / Xcode 27.2、XcodeGen：

```bash
brew install xcodegen
swift ios/scripts/prepare-icon.swift "$PWD"
cd ios
xcodegen generate
open FluidMusic.xcodeproj
```

在 Xcode 为 `FluidMusic` 与 `FluidMusicWidget` 设置自己的 Team 和唯一 Bundle ID。如需要小组件，将 `APP_GROUP_ID` 改为自己团队已注册的共享组，并为两个 Target 启用对应 App Groups 能力。

CI 使用 Xcode 27 SDK 实际编译，若找不到 iOS 27 SDK 或模拟器会失败，不会自动改用旧 SDK 却声称完成 iOS 27 验证。

## 验收清单

- 导入 MP3、M4A、FLAC、WAV；同名 LRC、中文标签和封面可见。
- 播放、暂停、拖动、上下首、循环、随机、队列排序均正确。
- 关闭并重开 App，恢复队列和暂停进度。
- 锁屏持续播放，控制中心/耳机可控制，灵动岛在支持机型上按系统规则显示。
- 拔出/断开耳机时暂停；来电中断与恢复正常；AirPlay 路由切换正常。
- 均衡器对声音有实际作用，切换预设无异常噪声。
- 睡眠定时到点暂停。
- 大字、减少动态效果、深/浅色模式下按钮可读可点；迷你栏不遮挡列表。

## 已知边界

不扫描其他 App 的沙盒，不含在线音乐、JS 音源与下载。Ogg/Opus/WMA/APE 未集成解码，DRM 音频不支持。副歌为歌词重复规则估算。带扩展版本的小组件需要合法匹配的共享组授权。真机验收前不作“完美适配”保证。

`build-info.json` 记录实际 SDK、Xcode、最低系统、包大小与 SHA-256；`SHA256SUMS.txt` 可校验完整性。是否通过模拟器测试，以同一构建的 Actions 结论和测试报告为准。
