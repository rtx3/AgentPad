# AgentPad 已完成计划归档

> 本文档归档已落地并合入主干的计划完整正文，供后续追溯。
> `docs/plan.md` 仅保留尚未落地的计划。

---

## 计划 5：新增「Agent」捕获模式（v1：宏指令序列，≤5 步）

> 完成日期：2026-05-28

### 5.1 现状分析

- 现有 capture mode 为 `simple` / `detailed` 两档（`KeyConfigViewController.swift` + `KeyCaptureField.swift`），二者最终都产出 `keyboard` 类 KeyMap（`keyCode` + `modifiers` + `mouseButton`）。
- 现有「按键 → 单一动作」模型无法表达「先把焦点切到目标 App、再切到指定输入法、再写入短语」这种连贯操作。
- 用户的真实诉求是「按一下手柄键 → 自动跳到 Claude Code 终端窗口 → 切到英文 ABC → 输入预备好的 prompt」，需要一个轻量的「宏指令序列」入口。

### 5.2 目标

在 `KeyConfigViewController` 的 capture mode 段控件里增加第三档 **Agent**：

- 用户选 Agent 后，弹窗呈现「宏指令列表」编辑器，最多 5 条指令，可任意顺序排列、增删、上下移。
- 支持的指令类型（v1 共 4 种）：
  1. **Activate app** — 参数：Bundle ID（下拉枚举本机已运行/已安装 App，可手填）。
  2. **Switch input method** — 参数：Input Source ID（下拉枚举本机已启用输入源）。
  3. **Input phrase** — 参数：短语（多行文本，≤ 4096 字符），复用计划 6 `Writeback`（`auto` 链）。
  4. **Delay** — 参数：毫秒（10–2000），用于给 App 激活 / IME 切换留时序窗口。
- 按下绑定的手柄键 → AgentPad 按序执行 macro；任一步失败即终止并发系统通知。
- v1 不做变量替换、不调 LLM、不读上下文；纯静态宏。
- 命名为 `Agent` 以保留演进空间：v2 接入计划 6 的 `script` 作为 macro 中的一种 step type，v3 增加 LLM 调用 step。本计划只交付 v1。

### 5.3 与已有计划的关系

| 维度 | 关系 |
| --- | --- |
| 现有 simple/detailed | UI 层平级：`Capture mode: Simple | Detailed | Agent`。Agent 时隐藏所有键盘录入控件，只露 macro 列表编辑器。 |
| 计划 6（script action） | 数据层平级：`KeyMap.action ∈ { keyboard, script, agent }`。Agent 不走 `ScriptRunner`，由独立 `AgentMacroRunner` 执行。 |
| 计划 6 的 `ScriptInputGuard` | macro 总耗时通常 < 1s，**不**进入 inflight 静音守护；运行期间若再次按键，由 `AgentMacroRunner.inflight` 自身丢弃。 |
| 计划 6 的 `Writeback` | `inputPhrase` step 直接调用 `Writeback.apply(.auto)`，需要把 originPID 比对目标从「按下时的 frontmost」改为「macro 运行时声明的 expected target PID」（见 5.4.4）。 |
| 现有透传逻辑 | 透传 App 不进 `handleButton` 派发，Agent 自然不触发。 |

### 5.4 方案设计

#### 5.4.1 数据模型

`KeyMap` 在计划 6 字段基础上再加 1 个：

```xml
<attribute name="agentMacro" optional="YES" attributeType="String"/>
```

存储 JSON 编码的 macro 数组：

```jsonc
[
  { "type": "activateApp", "bundleID": "com.apple.Terminal" },
  { "type": "delay", "ms": 200 },
  { "type": "switchInputMethod", "sourceID": "com.apple.keylayout.ABC" },
  { "type": "delay", "ms": 100 },
  { "type": "inputPhrase", "phrase": "Refactor this function to ..." }
]
```

- `action` 枚举扩为 `{ "keyboard", "script", "agent" }`，旧数据 `action == nil` 仍按 `"keyboard"` 处理。
- `agentMacro` 仅在 `action == "agent"` 时有意义；为 nil / 空数组时按下手柄键 = 空操作。
- 数组长度上限 5；超限 UI 阻止添加。
- 复用计划 6 的 `scriptWritebackMode`：`inputPhrase` step 默认 `"auto"`，UI 不暴露选择。

对应 Swift 结构：

```swift
enum AgentMacroStep: Codable {
    case activateApp(bundleID: String)
    case switchInputMethod(sourceID: String)
    case inputPhrase(text: String)
    case delay(ms: Int)
}

enum AgentMacroCodec {
    static func decode(_ json: String?) -> [AgentMacroStep]?
    static func encode(_ steps: [AgentMacroStep]) -> String
}
```

#### 5.4.2 触发链路

```
JoyConBackend buttonPressHandler
    -> GameController.handleButton(button)
        if ScriptRunner.shared.inflight != nil: return
        if AgentMacroRunner.shared.inflight: return
        let keyMap = currentConfig[button]
        switch keyMap.action {
        case "keyboard": existing path (KeyboardEventSender)
        case "script":   ScriptRunner.shared.run(...)
        case "agent":
            guard let steps = AgentMacroCodec.decode(keyMap.agentMacro), !steps.isEmpty else { return }
            AgentMacroRunner.shared.run(steps: steps, fromButton: button)
        }
```

#### 5.4.3 宏执行器（`AgentMacroRunner`）

新建 `AgentPad/DataModels/Agent/AgentMacroRunner.swift`，单例，主队列串行执行：

```swift
final class AgentMacroRunner {
    static let shared = AgentMacroRunner()
    private(set) var inflight: Bool = false
    private var expectedTargetPID: pid_t?

    func run(steps: [AgentMacroStep], fromButton: ControllerButton)
}
```

各 step 实现：

| Step | 实现 | 阻塞 / 异步 |
| --- | --- | --- |
| `activateApp(bundleID:)` | `NSRunningApplication.runningApplications(withBundleIdentifier:).first?.activate(options: [.activateAllWindows])`；未运行则 `NSWorkspace.shared.launchApplication(withBundleIdentifier:)`；更新 `expectedTargetPID`；隐式 200ms 等系统切换。 | 隐式 200ms |
| `switchInputMethod(sourceID:)` | `TISCreateInputSourceList` 找到 `kTISPropertyInputSourceID == sourceID` 的源 → `TISSelectInputSource(src)`；失败发通知并中止。 | 同步 |
| `inputPhrase(text:)` | 调用 `Writeback.apply(output: text, expectedTargetPID: expectedTargetPID, mode: .auto)`；焦点 PID 与 expected 不符则发通知并中止。 | 同步（auto 链 axSet→paste→typing） |
| `delay(ms:)` | `DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms))` 让出主线程，回调继续执行下一步。 | 异步 |

执行模型：

- 主队列串行；`delay` 用 `asyncAfter` 让出主线程；其他 step 同步执行。
- 任一 step 抛错 → 终止剩余 step + 发系统通知 `Macro step <N> failed: <reason>`。
- 全部完成 → `inflight = false`，不发完成通知（避免常规操作打扰）。

#### 5.4.4 `Writeback.apply` 扩展

为支持 `activateApp` + `inputPhrase` 组合，`Writeback.apply` 接口扩 1 个可选参数：

```swift
static func apply(output: String,
                  expectedTargetPID: pid_t?,    // 新增；nil 时回退到旧的 originPID 语义
                  mode: WritebackMode,
                  notificationTitle: String? = nil)
```

- 计划 6 现有调用方传 nil 即可，行为不变。
- macro 调用方传 `expectedTargetPID = activateApp` 切到的目标 PID；Writeback 内部用它替代 `originPID` 与 `frontmost` 比对。

#### 5.4.5 UI

`KeyConfigViewController` capture mode 段控件由 2 段 (`Simple | Detailed`) 改为 3 段 (`Simple | Detailed | Agent`)。

Agent 视图：

- 顶部说明：`Macro (up to 5 steps)`。
- `NSTableView`，单列，rowHeight ≈ 48pt，最多 5 行；空表显示 placeholder `Add a step to get started`。
- 行内左侧：步骤类型下拉（4 选 1）；右侧：参数编辑控件（按类型切换）：
  - `activateApp`：`NSComboBox`，下拉给出「正在运行 + 已安装 App」列表（显示名 + bundle ID），可手填 bundle ID。
  - `switchInputMethod`：`NSPopUpButton`，列出 `TISCreateInputSourceList(nil, false)` 返回的已启用输入源（本地化名 + ID）。
  - `inputPhrase`：`NSTextView`，多行编辑器（4 行高），上限 4096 字符 + 计数标签。
  - `delay`：`NSStepper` + 数字框，步进 10，范围 10–2000。
- 表格右侧工具栏：`+` 加新 step（达到 5 时禁用） / `−` 删除 / `↑↓` 上下移。
- 不显示 timeout / writeback 等高级项，保持极简。

切换 mode 时 KeyMap 临时态保留：

- simple/detailed → agent：清空 keyboard 字段，agentMacro 保留旧值（首次为空）。
- agent → simple/detailed：保留 agentMacro，但生效配置以 keyboard 字段为准。
- 弹窗保存按钮按当前 mode 决定 `action` 写入值。

#### 5.4.6 默认 capture mode

- 现有 `AppSettings.defaultKeyCaptureMode: String`（`simple` / `detailed`，默认 `simple`）。
- 计划 5 扩充取值集合为 `simple` / `detailed` / `agent`，**默认仍为 `simple`**。
- Settings UI 下拉项相应增加 `Agent` 一项。

### 5.5 数据模型影响

- `KeyMap` 新增 `agentMacro: String?`；与计划 6 同次 lightweight migration 一起处理（新增可选 String 属性，无需自定义迁移代码）。
- `action` 枚举扩 1 个值，无 schema 变化（仍是 `String`）。
- `AppSettings.defaultKeyCaptureMode` 取值集合扩充，仍为 `String`，无 schema 变化。
- 不引入 `agentPhrase` 字段（短语作为 `inputPhrase` step 的参数嵌入 `agentMacro` JSON）。

### 5.6 本地化

新增字符串（EN / JA）：

| key | EN | JA |
| --- | --- | --- |
| `keymap.captureMode.agent` | `Agent` | `エージェント` |
| `keymap.agent.macro.title` | `Macro (up to 5 steps)` | `マクロ（最大 5 ステップ）` |
| `keymap.agent.macro.empty` | `Add a step to get started` | `ステップを追加してください` |
| `keymap.agent.step.activateApp` | `Activate app` | `App をアクティブ化` |
| `keymap.agent.step.switchInputMethod` | `Switch input method` | `入力ソースを切り替え` |
| `keymap.agent.step.inputPhrase` | `Input phrase` | `フレーズを入力` |
| `keymap.agent.step.delay` | `Delay (ms)` | `待機（ミリ秒）` |
| `keymap.agent.step.inputPhrase.placeholder` | `Type the text to insert.` | `挿入するテキストを入力してください。` |
| `keymap.agent.macro.fail.fmt` | `Macro step %d failed: %@` | `マクロ ステップ %d 失敗: %@` |

### 5.7 实施步骤

1. **数据模型** —— `KeyMap` 加 `agentMacro`；`AgentMacroStep` Codable 类型 + 编解码工具；`action` 取值集合文档更新。
2. **`Writeback.apply`** —— 增加 `expectedTargetPID` 与 `notificationTitle` 可选参数；默认行为不变。
3. **`AgentMacroRunner`** —— 主队列串行执行器；4 种 step 实现；inflight 守护。
4. **`GameController.handleButton`** —— `switch keyMap.action` 增加 `case "agent"` 分支。
5. **`KeyConfigViewController`** —— capture mode 段控件加第三段；macro 列表编辑器（表格 + 4 类参数控件 + 增删 / 上下移）。
6. **`AppSettings`** —— `defaultKeyCaptureMode` 下拉加 `agent` 选项。
7. **本地化** —— EN / JA 各 9 条。
8. **回归** —— 旧 KeyMap（`action` 缺省 + `agentMacro` 缺省）保持 keyboard 行为零变化。

### 5.8 验证点

- 5 步典型链路（Activate Terminal → Delay 200 → Switch ABC → Delay 100 → Input "hello"）执行后：Terminal 在前、输入法为 ABC、光标位置插入 `hello`。
- 任意顺序：先 `inputPhrase` 再 `activateApp` 也能工作（短语写入按下时刻的 frontmost App）。
- `activateApp` 目标 App 未安装 → 通知 `Macro step 1 failed: app not found`，剩余 step 不执行。
- `switchInputMethod` 目标 source ID 未启用 → 通知 `Macro step N failed: input source unavailable`。
- `inputPhrase` step 单独存在（macro 只含一步）等价于旧「单短语」行为。
- macro 长度上限 5：UI `+` 按钮在第 5 步后禁用。
- 焦点不在输入框 / 焦点 App 与 expected target 不符 → `inputPhrase` 走通知 `Done. Click to copy.`。
- 含 Unicode（中文、emoji）短语 → `auto` 链 axSet 成功；axSet 失败的 App（VSCode）回退 paste，剪贴板恢复。
- 4096 字符上限：UI 阻止继续输入；计数标签红色提示。
- 旧数据库：迁移后 `action` 缺省值仍为 `keyboard`，不会误进入 agent 路径。
- 切换 capture mode 不丢数据：simple→agent 编 macro→detailed→回 agent，macro 仍在。
- macro 运行期间再按同键 / 它键 → 全部丢弃；`AgentMacroRunner.inflight` 通常 < 1s。
- 计划 6 `ScriptRunner.inflight` 期间按 agent 键 → 同样被守护短路。

### 5.9 风险与待决项

- **App 激活时序**：`activate(options:)` 在某些系统版本下 200ms 内未必完成切换；隐式 sleep + 显式 `delay` step 互补，文档建议在 `activateApp` 后插入 200–300ms `delay`。
- **TIS 输入源 ID 漂移**：第三方 IME 升级可能改 source ID；UI 用下拉枚举本机已启用源避免手填出错，但导出 / 导入配置时仍可能因 ID 失效；macro 失败发通知不静默。
- **焦点窗口非顶层**：`activate(options:)` 仅激活 App，目标 App 可能有多窗口；v1 不指定窗口标题，由 App 自行决定 key window；后续可加 `focusWindow(title:)` step。
- **回填可靠性继承计划 6 风险**：Electron 类 App `axSet` 失败后走 paste，需保证剪贴板 snapshot / restore 与计划 6 同实现。
- **长短语**：4096 字符且 typing 回退时 `CGEventKeyboardSetUnicodeString` 会有明显延迟（按 1ms / 字符 ≈ 4s）；UI 上限即取这个量级。
- **演进风险**：v2 加入 LLM step 时引入异步 + 取消 + 流式，届时需要把 `AgentMacroRunner` 改为非串行模型 + 抽 step protocol；但**不要为这个未来重构 v1**。
- **命名争议**：v1 行为只是宏序列，"Agent" 名字偏大；保留命名为长期演进留口子，UI 文案旁可加 tooltip：`Run up to 5 actions in order. Will support scripts and LLM agents in future versions.`
