# 上架 / 分发资源清单

双轨分发：**Mac App Store (MAS)** + **GitHub Releases 直接分发**。

---

## 关键决策与风险

本 App 通过 `CGEventPost` 向其他进程注入键盘事件，依赖系统 **Accessibility（辅助功能）** 权限。

- **MAS 路径**：App Sandbox 强制开启，沙盒下申请 Accessibility 历史上几乎必被拒。可行做法：MAS 版仅保留「查看手柄输入 / 配置映射」的只读 + 配置功能，**键盘注入功能裁掉或仅在 GitHub 版启用**。
- **GitHub 直接分发**：使用 Developer ID + Notarization，可正常请求 Accessibility 权限，功能完整版走这条线。

> 决策结果：**双轨发布**。MAS 做「精简版 / 引流」，GitHub 做「完整版」。

---

## 一、共用资源

### 1.1 账号

- [X] Apple Developer Program 个人/组织会员（USD 99/年）
- [X] Apple ID 启用双重认证

### 1.2 App 元数据（Info.plist）

- [ ] `CFBundleShortVersionString`（如 `1.0.0`）
- [ ] `CFBundleVersion`（构建号，每次提交递增）
- [ ] `CFBundleIdentifier`（如 `jp.0spec.AgentPad`，MAS 与 GitHub 可使用同一 Bundle ID 或加后缀区分）
- [ ] `LSApplicationCategoryType`（建议 `public.app-category.utilities`）
- [ ] `LSMinimumSystemVersion`
- [ ] `NSHumanReadableCopyright`
- [ ] 隐私 Usage Description（按实际用到的能力补全）
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

## 二、MAS 路径

### 2.1 证书 / Profile

- [ ] Mac App Distribution 证书
- [ ] Mac Installer Distribution 证书
- [ ] Provisioning Profile（App Store 类型）

### 2.2 Sandbox / 运行时

- [ ] 开启 **App Sandbox**（`com.apple.security.app-sandbox = true`）
- [ ] 开启 **Hardened Runtime**
- [ ] entitlements 按需声明：
  - `com.apple.security.device.usb`（如读取 USB HID 手柄）
  - `com.apple.security.device.bluetooth`（蓝牙手柄）
  - `com.apple.security.files.user-selected.read-write`（导入/导出配置）
- [ ] **不要**期望沙盒内做 `CGEventPost` 注入；MAS 版本需移除/降级该功能

### 2.3 App Store Connect

- [ ] 创建 App 记录（Bundle ID、SKU、主语言）
- [ ] App 名称、副标题、关键字、描述（中/英/日）
- [ ] 支持 URL、营销 URL、隐私政策 URL
- [ ] App Privacy 问卷
- [ ] 年龄分级问卷
- [ ] 价格与可用区域

### 2.4 截图（每语言一套）

- [ ] 1280×800
- [ ] 1440×900
- [ ] 2560×1600
- [ ] 2880×1800（推荐主用）

### 2.5 提交

- [ ] Xcode Archive → Validate → Upload
- [ ] TestFlight 内测
- [ ] Submit for Review

---

## 三、GitHub Releases 直接分发路径

### 3.1 证书

- [ ] **Developer ID Application** 证书（签 .app）
- [ ] **Developer ID Installer** 证书（如发 .pkg；纯 .dmg 不需要）

### 3.2 签名 / 公证

- [ ] Hardened Runtime 开启（公证强制）
- [ ] entitlements（**不开 Sandbox**）：
  - `com.apple.security.cs.allow-jit`（按需）
  - `com.apple.security.cs.disable-library-validation`（按需）
- [ ] `codesign --deep --options runtime --sign "Developer ID Application: ..."`
- [ ] **Notarization**：`xcrun notarytool submit ... --wait`
- [ ] **Stapling**：`xcrun stapler staple <App>.app` / `<App>.dmg`

### 3.3 打包

- [ ] DMG 打包（推荐，带拖拽到 Applications 的背景图）
  - 工具：`create-dmg` / `dmgbuild`
- [ ] 或 ZIP（更简单，无安装器界面）

### 3.4 自动更新（推荐）

- [ ] 集成 **Sparkle 2**
- [ ] 生成 EdDSA 密钥对，公钥写入 Info.plist
- [ ] 维护 `appcast.xml`（托管在 GitHub Pages / Releases）
- [ ] 每次发版生成签名并写入 appcast

### 3.5 GitHub 发布流程

- [ ] `Releases` 页面创建 tag（语义化版本 `vX.Y.Z`）
- [ ] 上传 `<App>-x.y.z.dmg`（已签名 + 已公证 + 已 staple）
- [ ] 上传 `<App>-x.y.z.dmg.sha256`（校验和）
- [ ] Release Notes（中/英）
- [ ] README 增加下载徽章 + 安装说明（首次打开右键「打开」或在「安全性与隐私」放行；引导授予 Accessibility）

### 3.6 CI（可选）

- [ ] GitHub Actions：tag 推送时自动 build / sign / notarize / 发 Release
- [ ] Secrets：`APPLE_ID`、`APP_SPECIFIC_PASSWORD`、`TEAM_ID`、`DEVELOPER_ID_CERT_P12`、`CERT_PASSWORD`、`SPARKLE_PRIVATE_KEY`

---

## 四、文档与运营

- [ ] README：功能介绍、截图/GIF、下载链接（区分 MAS / GitHub 完整版）
- [ ] 用户手册：Accessibility 授权步骤截图
- [ ] CHANGELOG.md
- [ ] LICENSE
- [ ] 隐私政策（HTML，托管 GitHub Pages）
- [ ] Issue 模板 / PR 模板

---

## 五、提交前检查清单

- [ ] `xcrun altool --validate-app` / `notarytool` 通过
- [ ] 在干净的 macOS 用户上测试首次启动 + Accessibility 授权流程
- [ ] 卸载后重装无残留
- [ ] 多分辨率截图无错位
- [ ] 中/英/日三语 UI 检查
- [ ] 版本号、构建号已递增

---

## 六、参考链接（按需补全）

- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Sparkle 2: https://sparkle-project.org/
- create-dmg: https://github.com/create-dmg/create-dmg
