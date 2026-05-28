# 分发资源清单（GitHub Releases 直接分发）

本 App 通过 `CGEventPost` 向其他进程注入键盘/鼠标事件，依赖系统 **Accessibility（辅助功能）** 权限。Sandbox 下 Accessibility 受限，故**仅走 GitHub Direct 分发**（Developer ID + Notarization），不上 Mac App Store。

---

## 一、共用资源

### 1.1 账号

- [X] Apple Developer Program 个人/组织会员（USD 99/年）
- [X] Apple ID 启用双重认证

### 1.2 App 元数据（Info.plist）

- [X] `CFBundleShortVersionString`（如 `1.0.0`）
- [X] `CFBundleVersion`（构建号，每次提交递增）
- [X] `CFBundleIdentifier` = `com.rtx3.agentpad`
- [X] `LSApplicationCategoryType`（建议 `public.app-category.utilities`）
- [X] `LSMinimumSystemVersion`
- [X] `NSHumanReadableCopyright`
- [X] 隐私 Usage Description（按实际用到的能力补全）
  - 手柄/HID 相关：通常不需要 Usage Description，但若用到 `GCController`/IOKit 需自查
  - 不申请 Accessibility 文案；该权限通过 TCC 弹窗，由 App 主动引导

### 1.3 图标

- [ ] AppIcon 全套尺寸（16, 32, 64, 128, 256, 512, 1024 @1x/@2x），打包为 `.icns` / Asset Catalog

### 1.4 本地化

- [x] 已有 `en.lproj`、`ja.lproj`，保持

### 1.5 隐私

- [ ] `PrivacyInfo.xcprivacy`（2024 起强制；声明使用的 Required Reason API、追踪域名等）
- [ ] 隐私政策页面 URL（GitHub Pages / 自建均可）

---

## 二、签名 / 公证

### 2.1 证书

- [ ] **Developer ID Application** 证书（签 .app）
- [ ] **Developer ID Installer** 证书（如发 .pkg；纯 .dmg 不需要）

### 2.2 entitlements（不开 Sandbox）

- `com.apple.security.app-sandbox = false`（已设置）
- 按需添加：
  - `com.apple.security.cs.allow-jit`
  - `com.apple.security.cs.disable-library-validation`

### 2.3 签名 + 公证 + Stapling

- [ ] Hardened Runtime 开启（公证强制）
- [ ] `codesign --deep --options runtime --sign "Developer ID Application: ..."`
- [ ] **Notarization**：`xcrun notarytool submit ... --wait`
- [ ] **Stapling**：`xcrun stapler staple <App>.app` / `<App>.dmg`

---

## 三、打包

- [ ] DMG 打包（推荐，带拖拽到 Applications 的背景图）
  - 工具：`create-dmg` / `dmgbuild`
- [ ] 或 ZIP（更简单，无安装器界面）

---

## 四、自动更新（推荐）

- [ ] 集成 **Sparkle 2**
- [ ] 生成 EdDSA 密钥对，公钥写入 Info.plist
- [ ] 维护 `appcast.xml`（托管在 GitHub Pages / Releases）
- [ ] 每次发版生成签名并写入 appcast

---

## 五、GitHub 发布流程 (代码保存在Private，成品保存在Public项目)

- [ ] `Releases` 页面创建 tag（语义化版本 `vX.Y.Z`）
- [ ] 上传 `<App>-x.y.z.dmg`（已签名 + 已公证 + 已 staple）
- [ ] 上传 `<App>-x.y.z.dmg.sha256`（校验和）
- [ ] Release Notes（中/英/日）
- [ ] README 增加下载徽章 + 安装说明（首次打开右键「打开」或在「安全性与隐私」放行；引导授予 Accessibility）

---

## 六、CI（可选）

- [ ] GitHub Actions：tag 推送时自动 build / sign / notarize / 发 Release
- [ ] Secrets：`APPLE_ID`、`APP_SPECIFIC_PASSWORD`、`TEAM_ID`、`DEVELOPER_ID_CERT_P12`、`CERT_PASSWORD`、`SPARKLE_PRIVATE_KEY`

---

## 七、文档与运营

- [ ] README：功能介绍、截图/GIF、下载链接
- [ ] 用户手册：Accessibility 授权步骤截图
- [ ] CHANGELOG.md
- [ ] LICENSE
- [ ] 隐私政策（HTML，托管 GitHub Pages）
- [ ] Issue 模板 / PR 模板

---

## 八、提交前检查清单

- [ ] `xcrun notarytool` 公证通过
- [ ] 在干净的 macOS 用户上测试首次启动 + Accessibility 授权流程
- [ ] 卸载后重装无残留
- [ ] 多分辨率截图无错位
- [ ] 中/英/日三语 UI 检查
- [ ] 版本号、构建号已递增

---

## 九、参考链接

- Notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Sparkle 2: https://sparkle-project.org/
- create-dmg: https://github.com/create-dmg/create-dmg
