# FrontendLegends Icons

- `png/`: 通用 144、180、512 像素 PNG。
- `windows/`: 含 16、24、32、48、64、128、256 像素层的 ICO。
- `macos/`: 标准 iconset 与 ICNS。
- `android/`: 五档 launcher PNG、圆形 PNG、自适应图标前景/背景和 Play Store 512px 图标。
- `source/`: 透明母版及生成时使用的色键源图。
- `splash/`: Windows、macOS、Linux 与 Android 共用的 Godot 原生启动图。

Android 自适应图标资源可直接复制到 Android 工程对应的 `res/` 目录。

## Android 签名

本机 release keystore 位于 `android/signing/frontend-legends-release.keystore`，别名为
`frontendlegends`。签名密码保存在 Godot 自动忽略的
`.godot/export_credentials.cfg` 中，keystore 目录也已加入 `.gitignore`。

请将 keystore 和密码备份到安全的密码管理器。Android 应用发布后必须始终使用同一把
release key 更新应用；丢失密钥可能导致无法向现有用户发布更新。
