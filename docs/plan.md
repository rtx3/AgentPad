# ControllerKeyMapper 后续计划

> 起草日期：2026-05-07
> 适用工程：`ControllerKeyMapper.xcworkspace`
> 主要语言：Swift / AppKit / Core Data
> 范围：以下两项功能演进

---

## 计划 1：新增「单键映射」简易模式

### 1.1 现状分析

- 按键设置弹窗实现于 `ControllerKeyMapper/Views/KeyConfigView/KeyConfigViewController.swift`，配合 `KeyConfigComboBox.swift` 完成键码录入。
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

1. 新建 `ControllerKeyMapper/Views/KeyConfigView/KeyCaptureField.swift`，实现按键捕获组件 + delegate。
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

新建 `ControllerKeyMapper/DataModels/Input/`：

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

## 里程碑建议

| 里程碑 | 内容 | 预计 |
| --- | --- | --- |
| M1 | 计划 1 落地（简易映射模式 + 本地化 + 偏好） | 1 周 |
| M2 | 计划 2 阶段一：抽象层 + JoyConBackend 适配 + 数据迁移（行为零变化） | 1.5 周 |
| M3 | 计划 2 阶段二：GameController.framework backend + UI 适配 | 2 周 |
| M4 | 回归 + 文档 + App Store 提审 | 0.5 周 |

> 注：里程碑预估仅作排期参考，未计入设计 / 评审 / 反复打磨成本。
