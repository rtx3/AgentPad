
---

## 计划 6：手柄按键执行脚本并回填输出

### 6.1 现状分析

- 现有 `KeyMap` 仅能把手柄按键 / 摇杆方向映射到键盘 / 鼠标事件（见 `GameController.swift` 的 `currentConfig: [ControllerButton:KeyMap]` 与 `KeyMap.keyCode/modifiers/mouseButton`）。
- 没有"按手柄按键执行任意逻辑并把结果带回当前输入框"的入口。
- 现有 Accessibility 权限已通过 `AccessibilityOnboardingWindowController` 引导用户开启；本计划直接复用，不再额外申请。
- 不引入 Screen Recording / Microphone / Camera 等新权限。

### 6.2 目标

为最常见的"手柄按键 → 调用本地 CLI 工具（典型场景：non-interactive 调用 Codex / Claude Code / 自家 LLM 命令）→ 把结果填回当前输入框"提供原生支持：

- 在 `KeyConfigViewController` 中给单个按键选择 **Action: Keyboard / Script**。
- Script 模式下用户填写：脚本路径、参数、超时、上下文字符数、回填模式。
- AgentPad 在按键按下时：
  1. 抓取焦点 App / 焦点输入框光标前 N 字符 / 选中文本（AX 路径，零新增权限）。
  2. 通过环境变量传给脚本，启动子进程，等待完成（默认 30s 超时）。
  3. 把脚本 stdout 按选择的回填模式写回当前输入框（焦点切换则走系统通知）。
- 安全策略：用户自负，不做白名单；UI 红字警告 + 全局总开关 `Enable Script Mapping` 默认 **关闭**。

### 6.3 关键约束与风险

- AX 读 caret 前 N 字符在 Electron / Chromium / WebKit 控件上不可靠（VSCode、Discord、Slack、Chrome 等）；失败时 env 留空，脚本仍执行。
- Secure Text Field 拒绝读取，等价于 N=0。
- 模拟⌘V 粘贴会暂时污染剪贴板，需要 snapshot / restore，且在 IME 候选窗口下时序敏感。
- 子进程以与 AgentPad 相同 UID 运行，拥有用户全部文件系统 / 网络权限；这是用户行为，不做沙盒。
- 脚本运行时若用户切换 App，回填可能落到错误窗口；本计划采用"脚本启动时记录 frontmost PID，结束时比对，不等则不回填"策略。
- 脚本运行可能 5–30s，期间手柄输入若仍正常映射，可能因用户误操作产生噪声；本计划在脚本运行期间**全局静音手柄→键盘/鼠标映射**。

### 6.4 方案设计

#### 6.4.1 数据模型

`KeyMap` 新增字段（lightweight migration，旧数据 `action` 缺省视为 `"keyboard"`）：

```xml
<attribute name="action" optional="YES" attributeType="String" defaultValueString="keyboard"/>
<attribute name="scriptPath" optional="YES" attributeType="String"/>
<attribute name="scriptArgs" optional="YES" attributeType="String"/>
<attribute name="scriptTimeoutSec" optional="YES" attributeType="Integer 16" defaultValueString="30" usesScalarValueType="YES"/>
<attribute name="scriptContextChars" optional="YES" attributeType="Integer 32" defaultValueString="2000" usesScalarValueType="YES"/>
<attribute name="scriptWritebackMode" optional="YES" attributeType="String" defaultValueString="auto"/>
```

- `action ∈ { "keyboard", "script" }`
- `scriptWritebackMode ∈ { "auto", "axSet", "paste", "typing" }`，默认 `"auto"`：先尝试 `AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute, output)`，失败回退 paste，再回退 typing。

#### 6.4.2 上下文采集（`ContextSnapshot`）

新建 `AgentPad/DataModels/Script/ContextSnapshot.swift`，运行在主线程同步采集：

| Key | 来源 |
| --- | --- |
| `appBundleID` | `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` |
| `appName` | `frontmostApplication?.localizedName` |
| `windowTitle` | `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 按 PID + `kCGWindowLayer == 0` 过滤后取 `kCGWindowName` |
| `focusRole` | AX `kAXRoleAttribute`（如 `AXTextField` / `AXTextArea` / `AXComboBox`） |
| `selected` | AX `kAXSelectedTextAttribute` |
| `contextBefore` | AX：先读 `kAXSelectedTextRangeAttribute`（CFRange），构造 `CFRange(loc - N, N)`，调 `AXUIElementCopyParameterizedAttributeValue(focused, kAXStringForRangeParameterizedAttribute, ...)`。其中 N = `scriptContextChars` |

- 任一字段失败 → 留空，不阻塞执行。
- 采集纯只读：不修改剪贴板、不发按键、不截屏。

#### 6.4.3 子进程执行（`ScriptRunner`）

新建 `AgentPad/DataModels/Script/ScriptRunner.swift`：

```swift
final class ScriptRunner {
    static let shared = ScriptRunner()
    private(set) var inflight: RunningScript?

    func run(keyMap: KeyMap, controller: GameController) {
        guard inflight == nil else { /* 通知 "Busy"，丢弃本次按键 */ return }
        let snapshot = ContextSnapshot.capture(maxChars: keyMap.scriptContextChars)
        let env = makeEnv(snapshot, keyMap)   // AGENTPAD_*
        // /bin/sh -c "<scriptPath> <args>"
        // Process.environment = ProcessInfo + env
        // 异步收集 stdout / stderr，到达 timeoutSec 时 SIGTERM，再 +2s SIGKILL
        // 完成回调 -> Writeback.apply(output:, originPID:, mode:)
    }
}

struct RunningScript {
    let process: Process
    let originPID: pid_t
    let startedAt: Date
    let keyMap: KeyMap
}
```

环境变量集合：

| Env | 含义 |
| --- | --- |
| `AGENTPAD_APP_BUNDLE_ID` | 焦点 App bundleID |
| `AGENTPAD_APP_NAME` | 焦点 App 显示名 |
| `AGENTPAD_WIN_TITLE` | 焦点窗口标题 |
| `AGENTPAD_FOCUS_ROLE` | 焦点 AX role |
| `AGENTPAD_SELECTED` | 选中文本（可空） |
| `AGENTPAD_CTX_BEFORE` | 光标前 N 字符（可空） |
| `AGENTPAD_BUTTON` | 触发按键名（便于"一脚本多键"分支） |

#### 6.4.4 静音守护（`ScriptInputGuard`）

- 当 `ScriptRunner.shared.inflight != nil` 时，`GameController` 的 `buttonPressHandler` / `stickHandler` 中**短路所有 KeyMap 派发**（既不发键盘也不再触发 script），仅允许"取消当前脚本"这一菜单动作。
- 进入 / 退出守护时刷新状态栏菜单文本：`Mapping` ↔ `Running script: <name>`。

#### 6.4.5 输出回填（`Writeback`）

输入：脚本 stdout、`originPID`、`writebackMode`

```
let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
guard frontPID == originPID else {
    notifyDone(output: stdout, copyOnClick: true)   // 焦点已变，走通知
    return
}
let focused = AXUIElementCreateSystemWide().copyFocusedElement()
guard let role = focused?.role,
      role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole else {
    notifyDone(...)
    return
}
switch mode {
case .axSet:  trySetSelectedText(focused, stdout)         // 失败 -> notify
case .paste:  pasteWithSnapshot(stdout)
case .typing: typeUnicode(stdout)                         // CGEventKeyboardSetUnicodeString
case .auto:   axSet ?: paste ?: typing ?: notifyDone(...)
}
```

- `pasteWithSnapshot`：`NSPasteboard.general` 当前内容快照 → 写入 `stdout` → 主线程发⌘V `CGEvent` → 50ms 后 restore。
- `typeUnicode`：按字符循环 `CGEventCreateKeyboardEvent(nil, 0, true)` + `CGEventKeyboardSetUnicodeString`，每 ~1ms post 一次。

#### 6.4.6 UI

- `KeyConfigViewController` 顶部新增段控件 `Action: Keyboard | Script`：
  - Keyboard 段：保留现有控件（与现有简易模式兼容）。
  - Script 段：
    - 文件选择器（`NSOpenPanel.canChooseFiles = true, canChooseDirectories = false`）→ 写 `scriptPath`。
    - Args 文本框 → `scriptArgs`。
    - Timeout 数字输入（5–300，默认 30）。
    - Context Chars 数字输入（0–20000，默认 2000）。
    - Writeback 下拉（auto / axSet / paste / typing）。
    - 红字警告：`⚠ Scripts run with your full user privileges. Only bind trusted scripts.`
- 状态栏菜单：
  - 新增 `Running script: <name>` 项；右侧 `Cancel`（发 SIGTERM）。
- Settings 增加全局开关 `Enable Script Mapping`（`AppSettings.scriptMappingEnabled: Bool = false`），默认关；关闭时 `KeyConfigViewController` 的 Action 段控件禁用 Script 选项并 tooltip 说明。

#### 6.4.7 触发链路

```
JoyConBackend buttonPressHandler
    -> GameController.handleButton(button)
        if ScriptRunner.shared.inflight != nil: return
        let keyMap = currentConfig[button]
        switch keyMap.action {
        case "keyboard": existing path (KeyboardEventSender)
        case "script":   ScriptRunner.shared.run(keyMap, controller: self)
        }
```

### 6.5 数据模型影响

- `KeyMap` 增加 6 个字段（见 6.4.1）；Core Data lightweight migration 自动处理，旧数据 `action` 缺省 → `"keyboard"`，行为不变。
- `AppSettings` 增加 `scriptMappingEnabled: Bool = false`。
- 不影响 `AppConfig` / `KeyConfig` / `ControllerData` 现有结构。

### 6.6 本地化

新增字符串（`Misc/en.lproj/Localizable.strings` + `Misc/ja.lproj/Localizable.strings`），约 12 条：

- `Action` / `アクション`
- `Keyboard` / `キーボード`
- `Script` / `スクリプト`
- `Script path` / `スクリプトパス`
- `Arguments` / `引数`
- `Timeout (sec)` / `タイムアウト（秒）`
- `Context characters` / `コンテキスト文字数`
- `Writeback mode` / `書き戻しモード`
- `⚠ Scripts run with your full user privileges. Only bind trusted scripts.` / `⚠ スクリプトはユーザー権限で実行されます。信頼できるスクリプトのみ登録してください。`
- `Enable Script Mapping` / `スクリプトマッピングを有効化`
- `Running script: %@` / `スクリプト実行中: %@`
- `Script done. Click to copy.` / `スクリプト完了。クリックでコピー。`

### 6.7 实施步骤

1. **数据模型** —— `KeyMap` 加 6 字段 + lightweight migration；`AppSettings` 加 `scriptMappingEnabled`。
2. **`ContextSnapshot`** —— AX 采集封装，单元测试覆盖 `AXTextField` / `AXTextArea` / `AXComboBox` / 不可达 role 四档。
3. **`ScriptRunner`** —— 子进程 + 超时 + 串行守护；最大 1 inflight。
4. **`Writeback`** —— 三种模式 + auto fallback 链；`originPID` 比对。
5. **`ScriptInputGuard`** —— `GameController.handleButton` 中短路，所有 backend 共享。
6. **`KeyConfigViewController`** —— Action 段控件 + Script 子视图 + 警告文案。
7. **状态栏菜单** —— `Running script: ...` + Cancel；与现有透传状态文案区分（不会同时出现）。
8. **AppSettings UI** —— `Enable Script Mapping` 开关。
9. **本地化** —— EN / JA 12 条。
10. **回归** —— 旧 KeyMap（`action == nil` → `"keyboard"`）行为零变化。

### 6.8 验证点

- 触发脚本 `env | grep AGENTPAD_`：7 个变量正确填入；`AGENTPAD_CTX_BEFORE` 在 TextEdit / Notes / Xcode 各取到正确字符数。
- VSCode / Chrome / Discord：`AGENTPAD_CTX_BEFORE` 为空但脚本仍执行，结果回填走通知。
- Writeback：
  - `axSet` 在原生 `NSTextField` / `NSTextView` 成功；在 Electron 自动回退 `paste`。
  - `paste` 后 `NSPasteboard.general` 内容恢复至触发前。
  - `typing` 在中文 IME 候选窗口下结果正确（不被吞字）。
- 焦点切换：脚本启动后立刻 `cmd+tab` 到其它 App → 完成时不回填，仅通知。
- 超时：脚本 `sleep 60` + `timeoutSec=5` → 5s 后 SIGTERM；再过 2s 仍未退出 → SIGKILL；通知 "timeout"。
- 串行：脚本运行期间再按同键 / 它键 → 全部丢弃 + 短提示 `Busy`；菜单 `Running script: ...` 显示。
- 静音：脚本运行期间所有原 KeyMap 不再产生键盘 / 鼠标事件。
- 全局开关 `Enable Script Mapping = false`：UI Action 段控件 Script 项禁用 + tooltip 说明；运行时 `script` action 直接降级为空操作。
- 旧数据库（`action` 缺省）启动后所有 keyboard 映射继续生效。

### 6.9 风险与待决项

- **AX 不可靠 App 列表**：Electron / Chromium / WebKit 焦点元素常缺 `kAXSelectedTextRangeAttribute`，`AGENTPAD_CTX_BEFORE` 留空；文档需明确告知。
- **粘贴时序**：`pasteWithSnapshot` 在快键盘上 50ms 恢复有概率与下一个⌘V 竞争；如遇 bug 改为"粘贴完成 AX 监听"后再恢复。
- **typing IME 干扰**：典型如日 / 中文 IME 转换状态下 `CGEventKeyboardSetUnicodeString` 可能进入候选；文档建议用户在 ASCII 输入态触发 `typing` 模式，或默认走 `auto`（优先 axSet / paste）。
- **脚本被卡死**：默认 30s + SIGTERM/SIGKILL 兜底；用户可自配 5–300s。
- **与现有 backend 解耦**：`ScriptRunner` 与具体 `ControllerBackend` 实现无关，只通过 `GameController.handleButton` 接入。
- **与现有透传互斥**：透传期间根本不进 `handleButton` 派发路径，自然不触发 script，无需特别处理。

---

## 里程碑建议

| 里程碑 | 内容 | 预计 |
| --- | --- | --- |
| **M0** | **计划 A 落地（进程发现 + 三态引擎 + 轮询调度）** | **1.5 周** |
| **M0.5** | **计划 B 落地（菜单栏图标 + Popover + Settings 分页 + NSMenu 改名）** | **1.5 周** |
| M1 | 计划 6 落地（Script Action + AX 上下文采集 + 回填三策略 + 总开关） | 1.5 周 |
| M1.5 | 计划 5 落地（Agent capture mode v1：宏指令序列 ≤5 步 + 复用 Writeback） | 1 周 |
| M2 | 回归 + 文档 + Direct Release 发布（公证 + Sparkle） | 0.5 周 |

> 注：里程碑预估仅作排期参考，未计入设计 / 评审 / 反复打磨成本。
> 计划 A → B 是严格前后依赖（B 消费 A 的 `AgentMonitor.eventHandler`）。
> 计划 5 排在计划 6 之后，是因为 5 复用 6 的 `Writeback`；若临时单独做 5，需要先抽出最小可用的 `Writeback.apply`（auto 链）。
