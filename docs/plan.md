# AgentPad 后续计划

> 起草日期：2026-05-07
> 适用工程：`AgentPad.xcworkspace`
> 主要语言：Swift / AppKit / Core Data
> 范围：以下两项功能演进

---

## 计划 1：新增「单键映射」简易模式

### 1.1 现状分析

- 按键设置弹窗实现于 `AgentPad/Views/KeyConfigView/KeyConfigViewController.swift`，配合 `KeyConfigComboBox.swift` 完成键码录入。
- `KeyConfigComboBox` 继承自 `NSComboBox`，在 `becomeFirstResponder()` 中通过 `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` 捕获键码：

  ```swift
  override func becomeFirstResponder() -> Bool {
      self.stringValue = ""
      self.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { ... })
      ...
  }
  ```

- 实际表现：
  - 普通字母 / 数字键被 ComboBox 自身的文本输入路径捕获，monitor 行为不稳定，用户难以录入纯单键。
  - `keyCodeList` 下拉项里只列出了 F 键、方向键、回车、Tab、Space、键盘小键盘、亮度 / 音量等"特殊键"，**不包含 A–Z / 0–9 / 普通符号**，必须靠键盘 monitor 才能选中。
  - 配合 `shiftKey / optionKey / controlKey / commandKey` 四个 checkbox，整体 UI 偏向"组合键"配置，普通用户想"把手柄 A 键映射成键盘 A"很别扭。

### 1.2 目标

为最常见的"手柄按键 → 单个键盘按键"场景提供一条更直接的录入路径，在不破坏既有详细模式的前提下，新增「简易映射模式」：

- 进入弹窗后，用户可在「详细 / 简易」两种模式间切换。
- 简易模式下：UI 极简，只有一个"按下手柄要映射到的键盘按键"的录入区；按下任意键盘按键即录入并自动确认。
- 自动写回 `KeyMap` 时：`keyCode = 实际键码`，`modifiers = 0`，`mouseButton = -1`。

### 1.3 方案设计

- **新建 `KeyCaptureField`**（自定义 `NSView`）
  - 重写 `acceptsFirstResponder = true`、`becomeFirstResponder()`、`keyDown(with:)`、`flagsChanged(with:)`。
  - 在 `keyDown` 中拿到 `event.keyCode` → 通过 delegate 回传给 ViewController。
  - 用 `NSVisualEffectView` + 高亮边框给出"等待按键"的视觉态。
  - **不**继承 `NSTextField` / `NSComboBox`，避免文本输入路径吞键。

- **`KeyConfigViewController` 改造**
  - 增加 `enum CaptureMode { case simple, detailed }` + 顶部切换控件（`NSSegmentedControl`）。
  - `simple` 视图：`KeyCaptureField` + 当前已录入键名展示 + "OK / Cancel"。
  - `detailed` 视图：保留现有控件不动。
  - 切换时 `KeyMap` 临时态保留：从详细切到简易仅展示 `keyCode`；从简易切到详细把 `modifiers` 置 0、其它沿用。

- **持久化默认模式**
  - `AppSettings` 新增 `defaultKeyCaptureMode: String`（"simple" / "detailed"），默认 "simple"，让首次安装的用户最快上手。

- **本地化**
  - 需要新增至少以下条目（`Misc/en.lproj`、`Misc/ja.lproj`、以及 `Views/en.lproj`、`Views/ja.lproj` 视实际 .strings 分布而定）：
    - `"Simple"` / `"Detailed"`
    - `"Press a key…"`（录入提示）
    - `"Press any key on your keyboard. It will be assigned immediately."`（说明文字）

### 1.4 数据模型影响

- **不**改动 `ControllerKeyMapper.xcdatamodeld`，仍使用现有 `KeyMap`。
- 简易模式下产生的数据完全是详细模式合法子集（`modifiers = 0` 且 `mouseButton = -1`），无需迁移。

### 1.5 实施步骤

1. 新建 `AgentPad/Views/KeyConfigView/KeyCaptureField.swift`，实现按键捕获组件 + delegate。
2. 修改 `KeyConfigViewController.swift`：增加 mode 切换、视图组合、按键回写逻辑。
3. 在对应 Storyboard / XIB 中加入：分段控件、`KeyCaptureField` 容器、说明文字。
4. `AppSettings.swift` 新增 `defaultKeyCaptureMode`，并在 `AppSettingsViewController` 加偏好开关（可选）。
5. 增补本地化字符串。
6. 验证已有详细模式回归无差异。

### 1.6 验证点

- 简易模式录入：A–Z、0–9、符号、空格、回车、Tab、ESC、方向键、F 键、媒体键 → `KeyMap.keyCode` 正确写入，`modifiers == 0`。
- `convertKeyName(keyMap:)`（`Misc/Utils.swift`）能为简易模式产物显示正确名字（已支持，不需改）。
- 切换模式不丢数据：详细模式录入"⌘+C"后切到简易再切回，仍是"⌘+C"。
- 旧数据加载：已存在的 `modifiers != 0` 或 `mouseButton >= 0` 的 KeyMap 默认进入详细模式。
- 多语言下 UI 不溢出 / 不截断。

### 1.7 风险与待决项

- `flagsChanged` 是否需要支持"长按 Shift / Cmd 自身"作为单键映射？默认暂不支持（仍走详细模式），避免与 modifier 冲突。
- 少量按键（如 CapsLock）在 macOS 上不会发出常规 keyDown，简易模式仍需在文档里说明限制。

---

## 计划 2：支持其他蓝牙手柄（DualShock / DualSense / Xbox / MFi 等）

### 2.1 现状分析

- 手柄发现与连接由 `JoyConSwift.JoyConManager` 完成（`AppDelegate.manager`），仅识别任天堂手柄的特定 vendorID / productID（Joy-Con L/R、Pro Controller、Famicom、SNES Online Controller 等）。
- 业务核心 `DataModels/GameController.swift` 强依赖 `JoyConSwift`：

  ```swift
  var controller: JoyConSwift.Controller? { didSet { ... } }
  var currentConfig: [JoyCon.Button:KeyMap] = [:]
  ...
  controller.buttonPressHandler = { ... }
  controller.leftStickHandler   = { ... }
  ```

- 持久化层 `KeyMap.button: String` 用 `JoyConSwift` 的 `JoyCon.Button` 名做键，下拉里也是固定的 `buttonNames` 表。
- 图标渲染 `GameControllerIcon.swift` 按 `JoyCon.ControllerType` 分支绘制。
- 简言之：**输入源、按键命名、UI 渲染三处都绑死了 JoyConSwift**。

### 2.2 目标

允许在不卸载 / 替换 JoyConSwift 的前提下，新增对常见蓝牙手柄的支持：

- 第一阶段：覆盖 PS4 (DualShock4)、PS5 (DualSense)、Xbox One/Series、苹果 MFi 控制器。
- 第二阶段（可选）：扩展到任意符合 HID 通用游戏手柄描述符的设备。

### 2.3 技术路线对比

| 路线 | 描述 | 优 | 劣 |
| --- | --- | --- | --- |
| **A. Apple `GameController.framework`** | 用 `GCController` / `GCExtendedGamepad` 接收输入 | 原生支持 PS4/PS5/Xbox/MFi，配对走系统蓝牙；API 简洁；不需要权限授权额外权限 | 不支持 Joy-Con；电池 / 灯光等私有能力依赖具体子类（GCDualShockGamepad / GCXboxGamepad） |
| B. 自己写通用 IOKit HID 解析 | 手动解析每家厂商的 HID 报告 | 灵活，理论覆盖一切 | 工作量极大，难维护 |
| **C. 抽象 backend 协议** | 让 JoyConSwift / GameController.framework 共存 | 渐进式演进，老用户零中断 | 需要一次较大的解耦 |

**推荐：A + C 组合**。新增 `GCControllerBackend` 作为 GameController.framework 的适配，原 `JoyConSwift` 适配为 `JoyConBackend`，业务层通过统一协议消费输入。

### 2.4 架构改造

#### 2.4.1 抽象按键 / 摇杆

新建 `AgentPad/DataModels/Input/`：

```swift
// 与具体 backend 解耦的通用按键标识
enum ControllerButton: String, Codable {
    case faceUp, faceDown, faceLeft, faceRight   // ABXY / Cross/Square/Triangle/Circle
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case l1, r1, l2, r2, l3, r3
    case start, select, home, capture
    case sl, sr  // Joy-Con 特有
    case unknown
}

enum ControllerStick: String, Codable { case left, right }

enum ControllerStickDirection: String, Codable { case up, down, left, right }
```

#### 2.4.2 Backend 协议

```swift
protocol ControllerBackend: AnyObject {
    var identifier: String { get }            // 用于持久化匹配（替代 serialID）
    var displayName: String { get }
    var kind: ControllerKind { get }          // joyConL / joyConR / proController / dualShock4 / dualSense / xbox / mfi / generic
    var battery: BatteryLevel { get }
    var isCharging: Bool { get }

    var buttonPressHandler: ((ControllerButton) -> Void)? { get set }
    var buttonReleaseHandler: ((ControllerButton) -> Void)? { get set }
    var stickHandler: ((ControllerStick, ControllerStickDirection, ControllerStickDirection) -> Void)? { get set }
    var stickPosHandler: ((ControllerStick, CGPoint) -> Void)? { get set }
    var batteryChangeHandler: ((BatteryLevel, BatteryLevel) -> Void)? { get set }
    var isChargingChangeHandler: ((Bool) -> Void)? { get set }

    func disconnect()
}

protocol ControllerBackendDiscovery: AnyObject {
    var connectHandler: ((ControllerBackend) -> Void)? { get set }
    var disconnectHandler: ((ControllerBackend) -> Void)? { get set }
    func start()
    func stop()
}
```

#### 2.4.3 Backend 适配

- `JoyConBackend`：包装 `JoyConSwift.Controller`，把 `JoyCon.Button` → `ControllerButton`，把 `JoyCon.StickDirection` → `ControllerStickDirection`。
- `JoyConDiscovery`：包装 `JoyConSwift.JoyConManager`。
- `GCControllerBackend`：监听 `GCController.controllerDidConnectNotification` / `controllerDidDisconnectNotification`，使用 `extendedGamepad?.valueChangedHandler` 派发按键 / 摇杆事件；并对 `GCDualShockGamepad / GCDualSenseGamepad / GCXboxGamepad` 做按键名映射（`buttonA → faceDown`, `buttonB → faceRight`...）。
- `CompositeDiscovery`：汇总多个 discovery，对外只暴露一组回调；`AppDelegate` 只持有它。

#### 2.4.4 业务层 `GameController`

- `var controller: JoyConSwift.Controller?` 改为 `var backend: ControllerBackend?`。
- `currentConfig: [JoyCon.Button:KeyMap]` 改为 `[ControllerButton:KeyMap]`。
- `ControllerData.serialID` 与 `backend.identifier` 对应（已有数据迁移：旧 `serialID` 视为 `joyCon::<serialID>` 的命名空间）。

### 2.5 数据模型影响（Core Data）

- `ControllerData.type` 当前是字符串（来自 `JoyCon.ControllerType.rawValue`），扩充取值集合：
  - 新增 `dualshock4 / dualsense / xboxone / xboxseries / mfi / generic`
- `KeyMap.button` 当前直接存 `JoyCon.Button` 名，迁移到 `ControllerButton.rawValue`。
  - 写一段一次性 lightweight migration / 启动时的代码迁移：把旧值（如 "A", "B", "Up"...）按 `JoyCon.Button → ControllerButton` 映射表批量更新。
- `GameControllerIcon.swift` 增加新分支：根据 `ControllerKind` 选择对应 svg / 资源；缺省时给一个通用占位图标。

### 2.6 UI 影响

- `KeyMapList` 的按键名展示需要按当前手柄的 `kind` 用不同显示文本（PS：Cross / Circle / Square / Triangle；Xbox：A / B / X / Y；任天堂：B / A / Y / X 顺序差异）。
- `KeyConfigViewController` 中按键下拉项随手柄类型动态渲染。
- 偏好设置加一项「启用通用蓝牙手柄（GameController.framework）」，可由用户关闭以排查冲突。

### 2.7 实施步骤

1. **抽象层** —— 新增 `ControllerBackend` 协议、`ControllerButton` / `ControllerStick(Direction)` / `BatteryLevel` / `ControllerKind`。
2. **JoyConSwift 适配** —— 实现 `JoyConBackend` + `JoyConDiscovery`，让 `AppDelegate` 改用新协议；不改任何用户行为。
3. **业务层迁移** —— 把 `GameController` / `DataManager` / 视图层从 `JoyCon.Button` 切换到 `ControllerButton`；同时编写数据迁移代码。
4. **GameController.framework 接入** —— 实现 `GCControllerBackend` + `GCControllerDiscovery`；映射四种 `GCExtendedGamepad` 子类的按键。
5. **UI 适配** —— 按 `ControllerKind` 渲染按键名 / 图标；在「设置」加开关。
6. **本地化 + 文档**。
7. **回归测试**：旧 Joy-Con / Pro Controller 用户配置不丢；新 PS / Xbox 用户能直接配对、按键、映射。

### 2.8 验证点

- Joy-Con / Pro Controller / Famicom / SNES：连接、断开、电量、灯光、按键、摇杆、应用切换全部回归通过。
- DualShock4 / DualSense / Xbox：连接、按键映射 ABXY、十字键、L1/R1/L2/R2、摇杆按键、起始 / 选择键。
- 同时连接 1 个 Joy-Con + 1 个 DualSense：互不干扰。
- 旧版用户（升级前已存在 `KeyMap.button == "A"`）启动后映射继续生效。
- 关闭「启用通用蓝牙手柄」开关后，`GCControllerBackend` 不再上报，`JoyConBackend` 仍工作。

### 2.9 风险与待决项

- **按键命名差异**：PS 的 ✕ ◯ □ △ vs Xbox 的 A B X Y vs 任天堂的 B A Y X。`ControllerButton` 用通用语义（faceDown / faceRight / faceLeft / faceUp），UI 层按 `ControllerKind` 翻译，避免误导用户。
- **能力差异**：电量 / 灯光 / 振动并非所有 backend 都支持，`ControllerBackend` 协议需要可选 capability（如 `var supportsBattery: Bool`），UI 按能力隐藏菜单项。
- **App Store 上架**：GameController.framework 不需要额外 entitlement；JoyConSwift 走 IOKit HID 已在 entitlement 中启用。注意保持沙盒不破坏。
- **多手柄并发**：业务层 `controllers: [GameController]` 已为多手柄设计，但需要复测当前菜单 UI 对混合品牌的展示。
- **Joy-Con 双持模式**：JoyConSwift 现在按单只 Joy-Con 暴露，未来如果接 GameController.framework 的 `GCMicroGamepad` 或合体逻辑，需要在 `ControllerBackend` 之上再加层"组合手柄"。

---

## 计划 3：按 App 透传（游戏中保留手柄身份）

### 3.1 现状分析

- `AppDelegate.didActivateApp(notification:)` 监听 `NSWorkspace.didActivateApplicationNotification`，App 切换时调用 `GameController.switchApp(bundleID:)`。
- `GameController.switchApp(bundleID:)`：在 `data.appConfigs` 中按 `bundleID` 查找 `AppConfig`，命中则用 `appConfig.config`，否则回退 `data.defaultConfig`。
- **整套架构里所有 `AppConfig` 都是"键映射"**：每条 `KeyMap` 把手柄按键 / 摇杆方向转成键盘 / 鼠标事件。**目前没有"不映射"的选项**。
- HID 接管模式由 `Pods/JoyConSwift/Source/JoyConManager.swift:200` 决定：
  ```swift
  let ret = IOHIDManagerOpen(self.manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
  ```
  即 `kIOHIDOptionsTypeSeizeDevice` 全局独占——只要本 App 在运行并连上手柄，**Steam / 任何游戏 / 系统其它进程都看不到这只手柄**。
- 也就是说：单纯"我们这边不再发键盘事件"并不能让游戏看到手柄，必须**主动释放 seize**，让系统蓝牙 HID 重新可见。

### 3.2 目标

- 用户能为某个特定 App（典型场景：原生支持手柄的 Steam 游戏）配置「保持为手柄」：
  - 切到该 App 时，**释放本 App 对手柄的独占**，让游戏直接读手柄原生输入；
  - 离开该 App 时，**自动重新接管**手柄，恢复键盘 / 鼠标映射。
- **粒度（实施期决策）**：JoyConSwift 0.2.1 的 `IOHIDManager` 用全局 seize，无法 per-device 切换。M1.5 实施时确认**降级为「全局透传」**——任一前台 App 命中 passthrough 配置即释放所有手柄；离开时全部接管。「按单只手柄」放到 plan 2/3 的 backend 抽象层后再考虑。
- 透传期间 AgentPad 本身不产生任何键盘 / 鼠标 / 系统媒体键事件，避免重复输入。

### 3.3 关键约束与风险

- `JoyConManager` 当前用单个 `IOHIDManager` + seize 模式打开**所有**手柄，无法在不改 JoyConSwift 的前提下做"per-device 切换"。
- 释放 seize 后 Joy-Con 输入回到默认 HID 报告 `0x3F`（无 IMU、按键编码与 setInputMode 后不同）；系统 / Steam 看到的是 Joy-Con 原生协议。这是必然的代价。
- 重新接管时，如果其它进程仍占用手柄，`IOHIDDeviceOpen(seize)` 会失败；需要 retry 机制。
- Joy-Con 在闲置一段时间会自动断蓝牙；透传期间断开则需用户重新配对。
- 透传发生在前台 App 切换的同步路径上，必须保证 reseize / release 不阻塞主线程。

### 3.4 方案设计

#### 3.4.1 数据模型

为 `AppConfig` 增加一个 `passthrough: Bool` 属性：

```xml
<attribute name="passthrough" optional="YES" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
```

- Lightweight migration：新增 default false 的 Bool 属性，Core Data 自动迁移，老数据零中断。
- `KeyConfig`（关系字段）保留，方便用户从透传切回映射时配置可恢复。

#### 3.4.2 JoyConSwift 接口扩展（patch 注入）

在 Podfile 的 `post_install` hook 中追加一段对 `Pods/JoyConSwift/Source/Controller.swift` 的 patch（沿用 M1.5 已建立的 Utils.swift patch 机制），向 `Controller` 公共接口注入：

```swift
public func setSeized(_ seized: Bool) {
    // 内部对持有的 IOHIDDevice 分别调用：
    //   true  -> IOHIDDeviceOpen(device, kIOHIDOptionsTypeSeizeDevice)
    //   false -> IOHIDDeviceClose(device, kIOHIDOptionsTypeSeizeDevice)
    // 并在重新 seize 时复用既有 setInputMode / enableIMU / 回调注册。
}
public var isSeized: Bool { get }
```

- 优先尝试 `IOHIDDeviceClose / Open`（per-device API），不动 `JoyConManager` 的整 manager seize。
- 复用现有 patch 校验机制：检测到上游版本已 ≥ 0.3 自带类似 API 时，post_install hook 自动跳过。

#### 3.4.3 业务层 `GameController`

`switchApp(bundleID:)` 拆成两支：

```
if appConfig.passthrough == true {
    self.applyPassthrough()
} else {
    self.applyMapping(appConfig?.config ?? defaultConfig)
}
```

- `applyPassthrough()`：
  - `currentConfig`、`currentLStickConfig`、`currentRStickConfig` 清空 → 即便 handler 还在收事件也不会发键盘。
  - `controller.setSeized(false)` 释放该手柄给系统。
  - 更新菜单状态："Passthrough to [App]"。
- `applyMapping(...)`：
  - 调用 `controller.setSeized(true)`；若失败，把请求交给 `PassthroughCoordinator` 入队 retry。
  - 成功后调用既有 `updateKeyMap()`。

#### 3.4.4 `PassthroughCoordinator`（重接管协调器）

新建 `JoyKeyMapper/DataModels/PassthroughCoordinator.swift`：

```swift
final class PassthroughCoordinator {
    private var pending: [GameController: Date] = [:]
    private var timer: Timer?
    private let retryInterval: TimeInterval = 2.0
    private let maxRetryWindow: TimeInterval = 60.0

    func requestReseize(_ controller: GameController) { ... }
    func cancel(_ controller: GameController) { ... }
}
```

- 入队后每 `retryInterval` 秒尝试 reseize；成功则出队；超过 `maxRetryWindow` 则停止并发系统通知"无法重新接管手柄"。
- 单实例放在 `AppDelegate`，跨所有 `GameController` 共享。

#### 3.4.5 UI

- **AppList 行右侧**新增 ☐「Keep as controller (don't map)」复选框；绑定到 `AppConfig.passthrough`。
- 勾选后右侧 KeyMapList **整体灰显**并显示 "This app uses the controller directly. No mapping."。
- **状态栏菜单**每只手柄子菜单加一行状态指示：
  - 正常映射：`Mapping`
  - 透传：`Passthrough → [App Name]`
  - 等待重接管：`Reclaiming…`
- AppList 行图标右下角加一个小手柄角标，与勾选 checkbox 联动。

#### 3.4.6 本地化

新增 4 条字符串（`Misc/en.lproj/Localizable.strings` + `Misc/ja.lproj/Localizable.strings`）：

- `Keep as controller (don't map)` / `コントローラーのまま（マッピングしない）`
- `This app uses the controller directly. No mapping.` / `このアプリではコントローラーを直接利用します。マッピングなし。`
- `Passthrough → %@` / `透過 → %@`
- `Reclaiming controller…` / `コントローラー再取得中…`

### 3.5 数据模型影响

- `AppConfig.passthrough: Bool` 新增字段，default false。
- Core Data lightweight migration 自动完成。
- 老数据（passthrough 缺失）→ 视为 false → 行为与今天一致。

### 3.6 实施步骤

1. **Patch JoyConSwift**：Podfile post_install 注入 `setSeized(_:)` / `isSeized` 到 `Controller.swift`。
2. **Core Data**：`AppConfig` 加 `passthrough`。
3. **`PassthroughCoordinator`** 实现 + 接入 `AppDelegate`。
4. **`GameController.switchApp` / `applyPassthrough` / `applyMapping`** 重构。
5. **UI**：AppList checkbox、KeyMapList 灰显态、菜单状态文本。
6. **本地化**：4 条字符串。
7. **回归**：未勾选 passthrough 的所有 App 行为应与今天一致。

### 3.7 验证点

- 勾选某 App 透传后：
  - 切到该 App：菜单显示 `Passthrough → [App]`；按手柄按键，系统**没有**任何键盘 / 鼠标事件；游戏 / Steam 能看到手柄。
  - 切回非透传 App：菜单显示 `Mapping`；映射立即生效；如果手柄此时仍被游戏独占，菜单显示 `Reclaiming…`，2 秒一次 retry，成功后切回 `Mapping`。
- 60 秒 retry 窗口耗尽：发系统通知"无法重新接管 [手柄名]，请重连"。
- 单手柄 + 双手柄两种场景下行为一致。
- 老用户数据库（不含 `passthrough` 字段）首次启动可被 lightweight migration 升级，原有映射继续生效。
- 透传状态下关闭并重开 App：恢复后默认 `Mapping`（不持久化"上一次是 passthrough"，避免误锁）。

### 3.8 风险与待决项

- **重接管失败**：游戏 / Steam 长期占用手柄时无法 reseize；UI 必须明确告知用户。
- **JoyConSwift 上游升级**：若 0.3+ 提供原生 seize 切换 API，post_install hook 检测到后跳过 patch；如果上游 API 命名不一致，需要在 `GameController` 层用 protocol 抽象。
- **macOS 权限提示**：第一次 `IOHIDDeviceOpen(seize)` 可能再次触发蓝牙 / 输入监控权限询问；最好在偏好里加"已知权限"标记，避免反复弹。
- **与计划 2 的对齐**：未来 `ControllerBackend` 协议要把 `setSeized(_:)` 抽象成可选 capability：`GCControllerBackend` 走 `GameController.framework`，系统层不允许应用主动释放，只能选择"不读"——届时 passthrough 在 GC backend 下退化为"我们不模拟键盘"，但系统层一直能读到手柄。
- **极端场景**：用户在透传期间断电 / 蓝牙断开 → 手柄会消失，再次连上时按非透传逻辑恢复（命中的 AppConfig.passthrough 决定接管 vs 释放）。

---

## 计划 4：Accessibility 权限引导（临时需求）

### 4.1 目标

- 首次启动且未授予 Accessibility 权限时，提示用户开启隐私访问权限。
- 引导弹窗提供「打开隐私设置」和「稍后再说」，不区分 MAS / GitHub 版本文案。
- 用户可在 Options 中查看当前 App 的 Accessibility 权限是否设置正确；未授权时，点击入口直接打开系统隐私设置的 Accessibility 面板。

### 4.2 实施提示

- 权限检测使用 `AXIsProcessTrusted()`；主动触发系统引导使用 `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`。
- 跳转系统设置使用 `NSWorkspace.shared.open` 打开 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`。
- 首次引导状态用 `UserDefaults` 记录；「稍后再说」不写入永久跳过标记。

### 4.3 验证点

- 未授权首次启动会展示引导，点击后能进入 Accessibility 设置。
- 点击「稍后再说」后不阻塞主流程。
- Options 中权限状态与系统设置一致，授权变化后能刷新。

---

## 里程碑建议

| 里程碑 | 内容 | 预计 |
| --- | --- | --- |
| **M0.5** | **计划 4 落地（Accessibility 首启引导 + Options 权限状态 + 一键跳转）** | **0.5 周** |
| M1 | 计划 1 落地（简易映射模式 + 本地化 + 偏好） | 1 周 |
| **M1.5** | **计划 3 落地（按 App 透传 + JoyConSwift seize patch + 重接管协调器）** | **1 周** |
| M2 | 计划 2 阶段一：抽象层 + JoyConBackend 适配 + 数据迁移（行为零变化） | 1.5 周 |
| M3 | 计划 2 阶段二：GameController.framework backend + UI 适配 | 2 周 |
| M4 | 回归 + 文档 + App Store 提审 | 0.5 周 |

> 注：里程碑预估仅作排期参考，未计入设计 / 评审 / 反复打磨成本。
> M1.5 单独排在 M2 之前的原因：透传需求是 macOS 10.14 全版本都需要的，等不到 M3；并且现在做能直接在 JoyConSwift 上 patch 出 per-device API，等做完 M2 抽象层再回头改成本更高。
