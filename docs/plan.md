# AgentPad 后续计划

> 起草日期：2026-05-07（重排 2026-05-26）
> 适用工程：`AgentPad.xcworkspace`
> 主要语言：Swift / AppKit / Core Data
> 范围：当前未落地的功能演进

> **进度说明**：原计划 1（简易映射模式）/ 2（其他蓝牙手柄 backend）/ 3（按 App 透传）/ 4（Accessibility 引导）/ 5（Agent 捕获模式 v1）已全部实现并合入主干（见 `git log`），本文档不再保留。计划 5 完整正文已归档至 `docs/completed.md`。剩余存量计划保留原编号（6），新增 Agent 监控相关计划以「A / B」前缀编号。

---

## 计划 A：Agent 监控后端（进程发现 + 三态引擎）

### A.1 现状分析

- 现有工程围绕「手柄遥控键盘 / 鼠标」构建，无任何 AI agent 进程感知能力。
- `AppDelegate` 仅持有 `manager`（`CompositeDiscovery`）、`data`（`DataManager`）、菜单栏图标 `statusItem` 三个核心引用，状态栏图标是静态的 SF Symbol。
- 产品文档（`docs/product.md` §3.1）与设计文档（`docs/design.md` §1–§2）已定义 Agent 监控的全部需求，但代码侧零基础。

### A.2 目标

提供与「手柄遥控」并列的另一根产品支柱：

- 周期扫描所有运行中进程，按配置的进程名模式（默认 `claude` / `opencode` / `codex`，大小写不敏感子串匹配）筛出 AI agent。
- 为每个命中进程实时判定三态：**Working** / **Calling API** / **Idle**；优先级 Working > Calling API > Idle。
- **状态判定仅基于两路本地信号**：
  1. **Session JSONL tail（主路）**：tail agent 自身写入的本地会话文件（首发支持 Claude Code 的 `~/.claude/projects/<encoded>/<sessionId>.jsonl`）。
  2. **PTY 内容抓取（兜底）**：通过 Accessibility API 读取宿主 Terminal 窗口文本，匹配 agent UI 提示串。
  - 不引入任何 TCP / 网络嗅探、不再做子进程枚举判定状态、不维护 AI API 域名清单。
- 轮询节奏可配（2/3/5/10s），轮询连续 3 次失败进入 PollingFailed 错误态并对外发布事件。
- 完全后端实现，UI 由计划 B 消费；本计划不引入任何视图代码。

### A.3 方案设计

#### A.3.1 数据结构

新建 `AgentPad/DataModels/AgentMonitor/`：

```swift
struct AgentProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String            // proc_name
    let executablePath: String? // proc_pidpath
    let cwd: String?            // PROC_PIDVNODEPATHINFO
    let startedAt: Date
    let state: AgentState
    let detail: AgentStateDetail
    let source: AgentStateSource
}

enum AgentState: Int, Comparable {
    case working = 3   // 优先级最高
    case callingAPI = 2
    case idle = 1
}

enum AgentStateDetail {
    case toolUse(name: String?)             // Working: JSONL 路给出工具名；PTY 路给出匹配关键词
    case streaming                           // Calling API
    case waitingInput(prompt: String?)       // Idle: PTY 路可附等待中的提示串
    case unknown
}

enum AgentStateSource {
    case jsonl(sessionId: String)
    case pty(window: String)
    case none                                // 两路均未命中，默认 Idle
}

enum AgentMonitorEvent {
    case updated(processes: [AgentProcess])
    case empty
    case pollingFailed(consecutiveFailures: Int)
}
```

#### A.3.2 进程发现

- 用 `proc_listpids(PROC_ALL_PIDS, 0, nil, 0)` 获取 PID 容量，再次调用获取实际列表。
- 每个 PID 用 `proc_name` / `proc_pidpath` / `proc_pidinfo(PROC_PIDVNODEPATHINFO)` 取名称 / 可执行路径 / cwd。
- 按 `AppSettings.agentMonitor.patterns` 做大小写不敏感子串匹配。
- 启动时间由 `proc_pidinfo(PROC_PIDTBSDINFO)` 的 `pbi_start_tvsec` / `pbi_start_tvusec` 还原。
- 进程发现仅用于「列出哪些 agent」，**不再用于状态判定**。

#### A.3.3 主路：Session JSONL Tail

新建 `JSONLSessionProbe`：

- 每个 agent 适配一份 `SessionLocator` 协议，给定 PID / cwd 返回当前 session JSONL 路径。
  - Claude Code v1：`~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`，按 cwd 反查对应目录，取 mtime 最新的一个；若多个进程命中同一 cwd 则按 PID 启动顺序绑定。
- 文件以增量 tail 模式打开（持有 fd + 记录 offset），每轮 poll 读取新增行，解析为消息记录，缓存最后一条。
- 状态映射：
  - 末条为 `type: "assistant"` 且 content 含未闭合 `tool_use`，或紧跟其后无对应 `tool_result` → `working` + `.toolUse(name:)`。
  - 末条为 `type: "assistant"` 处于 streaming（无终止 `stop_reason` 字段，或文件正在持续追加且最近 N ms 内有写入）→ `callingAPI` + `.streaming`。
  - 末条为 `type: "assistant"` 已完成（带 `stop_reason`）且其后再无 user 消息 → `idle`。
  - 末条为 `type: "user"` 等待 assistant 响应（启动后立即出现）→ `callingAPI`（短窗口判定为冷启动 streaming，超过冷启动窗口仍无 assistant 行则降级 `idle`）。
- 其他 agent（codex / opencode）：先注册占位 `SessionLocator`，本计划不实现具体定位逻辑；这些 agent 在 v1 阶段直接走 PTY 路兜底。

#### A.3.4 兜底路：PTY 内容抓取

新建 `PTYStateProbe`：

- 通过 `AXUIElementCreateApplication(pid)` 获取目标 agent **宿主终端进程**（不是 agent 本身）的窗口树。
  - PID → 宿主终端的映射：取 agent 进程的会话祖先（`PROC_PIDTBSDINFO.pbi_ppid` 链），向上追到 `Terminal` / `iTerm` / `Ghostty` / `WezTerm` / `kitty` 等已知 bundle id；未识别则放弃 PTY 路。
- 读取窗口主文本（`kAXValueAttribute` / `kAXSelectedTextAttribute` 不可用时退回 `kAXChildrenAttribute` 递归拼装），保留最后 N 行做匹配。
- 关键词表（可配，默认 EN）：
  - Working：`esc to interrupt` / `Running ` / `tool_use(` / `⏵⏵`。
  - Calling API：`Thinking` / `Streaming` / 末行末尾光标处于动画字符（`⠋⠙⠹⠸…`）。
  - Idle：`Do you want to` / `(y/n)` / 仅显示终端 prompt（`$ ` / `% ` / `> `）末尾且其上方为 assistant 完整段落。
- 关键词命中均生成 `.detail` 含命中片段，便于调试展示。
- 任何步骤失败（无窗口 / 无文本 / 关键词全不命中）→ 视为 `idle` + `source: .none`。

#### A.3.5 路径合并

每轮 poll 对每个命中进程依次跑 JSONL 路 → PTY 路：

- JSONL 路给出非 `.unknown` 状态 → 直接采用，跳过 PTY。
- 否则跑 PTY 路，结果写入 `state` / `source: .pty`。
- 两路均失败 → `state = .idle, source: .none`。

不再做"同时满足多条件取高优先级"的逻辑（旧版 Working/CallingAPI 子进程+TCP 合并），因为同源已直接给出唯一状态；保留 `AgentState` 的 `Comparable` 仅用于 UI 排序。

#### A.3.6 轮询调度

新建 `AgentMonitor` 单例：

```swift
final class AgentMonitor {
    static let shared = AgentMonitor()
    private(set) var lastEvent: AgentMonitorEvent = .empty
    var eventHandler: ((AgentMonitorEvent) -> Void)?

    private var timer: DispatchSourceTimer?
    private var consecutiveFailures: Int = 0
    private let failureThreshold: Int       // 默认 3，可配
    private var interval: TimeInterval      // 默认 3s

    func start()
    func stop()
    func restart(interval: TimeInterval)    // 设置变更时调
    func pollOnce()                          // 供 Retry 按钮调用
}
```

- 轮询跑在专用 `DispatchQueue(label: "agentpad.monitor", qos: .utility)`，结果回主线程发布事件。
- 一次轮询 = 进程枚举 + 每进程 JSONL 路 + PTY 兜底 + 排序（按状态优先级降序，同级 `startedAt` 升序）。
- 任一阶段抛错或耗时超过 `interval * 0.8` → `consecutiveFailures += 1`；成功一次清零。
- `consecutiveFailures >= failureThreshold` → 发布 `.pollingFailed`，轮询继续按原节奏跑（不退避）。
- `pollOnce()` 立即触发一次（不重置 timer），用于 UI 层 Retry。

#### A.3.7 配置接入

`AppSettings` 新增 namespace：

```swift
struct AgentMonitorSettings: Codable {
    var patterns: [String] = ["claude", "opencode", "codex"]
    var pollIntervalSec: Int = 3            // 允许 2/3/5/10
    var pollFailureThreshold: Int = 3
    var showCountInMenuBar: Bool = true
    var enablePTYProbe: Bool = true         // 关闭则只跑 JSONL 路
}
```

存到 `UserDefaults`，键 `agent.monitor.settings`。修改 patterns / interval / enablePTYProbe → 立即 `AgentMonitor.shared.restart(interval:)`。

### A.4 数据模型影响

- **不**改 `AgentPad.xcdatamodeld`；监控配置走 `UserDefaults`，运行时状态不持久化。
- 与现有 `ControllerData / AppConfig / KeyConfig / KeyMap / StickConfig` 完全独立。

### A.5 实施步骤

1. 新增 `AgentPad/DataModels/AgentMonitor/{AgentProcess,AgentMonitor,ProcessScanner,JSONLSessionProbe,ClaudeCodeSessionLocator,PTYStateProbe,TerminalHostResolver}.swift`。
2. `AppSettings` 增加 `AgentMonitorSettings` + 持久化读写。
3. `AppDelegate.applicationDidFinishLaunching` 末尾调 `AgentMonitor.shared.start()`，并接入设置变更通知。
4. 单元测试：
   - 用 fixture JSONL（涵盖 streaming / tool_use / 完成 / 待响应 user 末行四种）覆盖 JSONL 路状态判定。
   - 用 mock `AXUIElement` 文本输入覆盖 PTY 路关键词命中 / 不命中 / 失败兜底。
   - 路径合并：JSONL=working + PTY=idle → working；JSONL=unknown + PTY=callingAPI → callingAPI；两路均失败 → idle。
   - PollingFailed 阈值边界（默认 3 / 改为 1）。

### A.6 验证点

- 启动 `claude` CLI 后 ≤ `pollIntervalSec` 秒内出现 `AgentProcess(pid: …, state: .idle, source: .jsonl, …)`。
- 在 `claude` 内执行 `! sleep 30` → 状态转 Working，detail 含工具名（来自 JSONL `tool_use.name`）。
- `claude` 调用 LLM 时 → 状态转 Calling API，source = `.jsonl`。
- 关闭 `enablePTYProbe` 且 codex / opencode 进程命中 → 状态恒为 `.idle, source: .none`（v1 这些 agent 无 SessionLocator，符合预期）。
- 开启 `enablePTYProbe` 且 codex 终端窗口含 `Thinking` → 状态转 Calling API，source = `.pty`。
- JSONL 文件被外部删除 / 切 session → 下一轮 poll 自动重新定位最新 session 文件，不抛错。
- `proc_listpids` 失败或 `AXUIElementCopyAttributeValue` 抛 timeout → `consecutiveFailures` 累加；`failureThreshold` 默认 3，可改为 1/2/3/5。
- 修改 `pollIntervalSec` 立即重启 timer，新节奏 ≤ 1s 内生效。
- 长跑 1 小时内存稳定（无 leak）；CPU 占用平均 < 0.5%（M1 / 3s 轮询 / 4 命中进程 / JSONL 增量 tail）。

### A.7 风险与待决项

- **Accessibility 权限尚未授予时 PTY 路全部失败**：合并逻辑会自动降级到 `idle, source: .none`；UI 层需在 Popover 给出引导（与手柄遥控的引导走查复用同一个授权入口）。
- **JSONL 文件格式上游变更**：Claude Code 的 JSONL schema 非公开 API，未来字段重命名会导致状态判定失效；解析层需做严格的可选字段处理 + 单测 fixture，发现解析不到关键字段时降级走 PTY。
- **多 `claude` 进程共享同一 cwd**：Session 文件按 mtime 取最新一条会被多进程争用；v1 限制为「同一 cwd 仅取一份 session 状态」，多进程共享时显示同一状态，不视为缺陷。
- **PTY 关键词跨语言/跨终端碎片化**：默认仅匹配 EN 关键词；`kitty` / `WezTerm` 等通过 AX 获取窗口文本可能为空，自动放弃 PTY 路，符合"兜底失败即 idle"。
- **去除子进程探测后的语义变化**：旧设计依赖子进程数量推断 Working；新设计在 JSONL 路缺位时无法仅靠子进程认定 Working，这是有意取舍，避免维护两套独立信号。

---

## 计划 B：Agent 监控前端（菜单栏图标 + Popover + Settings 分页 + NSMenu 改名）

### B.1 现状分析

- 当前 `AppDelegate.statusItem.button.image` 是静态 SF Symbol；左键 / 右键都弹既有 NSMenu（`@IBOutlet weak var menu: NSMenu?`）。
- 设置窗口由 storyboard `AgentPadWindowController` 承载，三栏 splitView（Apps / KeyMap / Controllers），无 Agent Monitor 分页。
- `docs/design.md` §1–§4 已定义全部 UI 细节，需要实现侧严格对齐。

### B.2 目标

完成 design.md §1–§4 描述的所有 UI 入口：

1. 菜单栏图标按 `AgentMonitorEvent` 重绘（Empty / 1–4 / 5+ / PollingFailed 四态）。
2. 左键单击 toggle Agent Monitor Popover；右键 / Ctrl+Click 仍弹既有 NSMenu。
3. Popover 实现 320×400 三区块（Header / List / Footer），含空态与错误态。
4. 主设置窗口新增第四分页 **Agent Monitor**。
5. 既有 NSMenu 仅做 title 改名（不改 IBAction / IBOutlet）。

### B.3 方案设计

#### B.3.1 菜单栏图标重绘

新建 `AgentPad/Views/StatusBar/StatusBarIconRenderer.swift`：

```swift
enum StatusBarIconState {
    case empty
    case agents(states: [AgentState], totalCount: Int)   // states.count ≤ 3 后用 +M
    case pollingFailed
}

enum StatusBarIconRenderer {
    static func image(for state: StatusBarIconState, showCount: Bool) -> NSImage
    // 配色：Working=systemGreen, CallingAPI=systemOrange, Idle=systemGray
    // Empty: SF Symbol "circle.dashed"
    // PollingFailed: SF Symbol "exclamationmark.circle"
    // 1–4 agents: N 个 8pt 圆点横排 + （showCount?N : "")
    // 5+ agents: 3 圆点 + "+M" 灰底胶囊 + （showCount?N : "")
}
```

- `NSStatusItem.button.image` 改用 `NSImage.draw` + `isTemplate = false`（彩色圆点不能走模板渲染）。
- 圆点排序与 `AgentMonitor` 给出的顺序一致（状态优先级降序，同级 startedAt 升序），UI 不再排序。

#### B.3.2 菜单栏图标交互

`StatusBarController`（新增，承接现有 `statusItem` 持有职责）：

```swift
final class StatusBarController {
    let statusItem: NSStatusItem
    let popoverController: AgentMonitorPopoverController
    weak var legacyMenu: NSMenu?            // 既有 NSMenu（计划 B.3.5 改名后）

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let isRight = event.type == .rightMouseUp ||
                      (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if isRight {
            statusItem.menu = legacyMenu
            statusItem.button?.performClick(nil)   // 弹完即解绑，避免下次左键也弹菜单
            statusItem.menu = nil
        } else {
            popoverController.toggle(relativeTo: sender)
        }
    }
}
```

订阅 `AgentMonitor.shared.eventHandler` → 重绘图标。

#### B.3.3 Agent Monitor Popover

新建 `AgentPad/Views/AgentMonitor/`：

```
AgentMonitorPopoverController.swift   // NSPopover 持有 + show/hide/toggle
AgentMonitorViewController.swift      // 320×400 主视图
AgentRowView.swift                    // NSTableCellView 子类，单行 64pt
AgentMonitorEmptyView.swift           // 空态
AgentMonitorErrorView.swift           // 错误态（含 Retry 按钮）
```

布局严格按 design.md §2.1：
- Header（40pt）：左 "AGENT MONITOR" 大写 Caption；右 "<N> running"（N=0 时显示 "idle"）。
- List：`NSTableView` 单列、`rowHeight = 64`，可滚动。
  - 圆点 12pt（颜色 = 状态色）。
  - 主行：`<name> — <short_cwd>`（cwd 路径过长用 `…` 截尾保留尾部段；目标渲染宽度 ≤ 240pt）。
  - 副行：`PID <pid> · <detailText>`，detailText 由 `AgentStateDetail` 派生（如 `tool_use: Bash` / `streaming` / `waiting input` / `idle`）。
  - 右：状态胶囊（圆角 4pt）+ 已运行时长（`formatRelativeDuration(startedAt)` → `5m` / `1h 23m` / `12s`）。
- Footer（36pt）：左 `Settings`（打开主设置窗口，定位到 Agent Monitor 分页）/ 右 `Quit`（`NSApp.terminate(nil)`）。

空态 / 错误态按 design.md §2.1 原样实现，错误态 `Retry` 调 `AgentMonitor.shared.pollOnce()`。

Popover 显示期间持续接收 `AgentMonitor` 事件并刷新表格，不暂停轮询。点击 Popover 外区域自动关闭（`NSPopover.behavior = .transient`）。

#### B.3.4 主设置窗口新增 Agent Monitor 分页

`AgentPadWindowController` 顶部 toolbar 增加第 4 项 "Agent Monitor"：

```
AgentPad/Views/Settings/AgentMonitorSettings/
    AgentMonitorSettingsViewController.swift
    AgentMonitorSettingsViewController.xib
```

字段（与 `AgentMonitorSettings` 一一对应）：
- **Monitored process patterns**：`NSTableView` 单列，`+`/`−` 增删；下方副标题 "case-insensitive substring"。
- **Polling interval**：`NSSegmentedControl` 单选 2s / 3s / 5s / 10s。
- **Show count in menu bar**：`NSButton.checkbox`。
- **Launch at login**：`NSButton.checkbox`，调 `SMAppService.mainApp.register()` / `unregister()`（仅 macOS 13+ 显示；< 13 显示 placeholder 文案）。

所有改动即时生效：
- patterns / interval → `AgentMonitor.shared.restart(interval:)`。
- 计数开关 → 立即重绘 StatusBarIcon。
- Launch at login → 立即调 `SMAppService`，失败弹 sheet 提示。

新增 Popover Footer 的 `Settings` 按钮跳转时，通过 `AgentPadWindowController.show(tab: .agentMonitor)` API 直接选中该分页。

#### B.3.5 既有 NSMenu 改名

按 design.md §4.1 改名映射表：

| 既有 title | 改名后 title |
| --- | --- |
| `Enable key mappings` | 不变 |
| `Controllers`（子菜单） | 不变 |
| `Open AgentPad…`（如有） | `Open Agent Monitor…` |
| `Preferences…` | `Settings…`（`keyEquivalent` 保持 `,`） |
| `Quit AgentPad` | 不变 |

`@IBOutlet weak var menu: NSMenu?` 与 `@IBOutlet weak var controllersMenu: NSMenuItem?` 及对应 `action` / `target` 一律不动；改名仅在 storyboard 的 title 属性 + `Localizable.strings` 中完成。

`Open Agent Monitor…` 的现有 action 改为调用 `StatusBarController.popoverController.show(relativeTo: statusItem.button)`，与左键单击等价。

### B.4 数据模型影响

- 无 Core Data 变更。
- `UserDefaults` 仅消费计划 A 的 `AgentMonitorSettings`，不新增 key。

### B.5 本地化

新增字符串（`Misc/en.lproj/Localizable.strings` + `Misc/ja.lproj/Localizable.strings`）：

| key | EN | JA |
| --- | --- | --- |
| `agent.monitor.header.title` | `AGENT MONITOR` | `エージェントモニター` |
| `agent.monitor.header.count.fmt` | `%d running` | `%d 件実行中` |
| `agent.monitor.header.idle` | `idle` | `アイドル` |
| `agent.monitor.empty.title` | `No agent running` | `エージェントは実行されていません` |
| `agent.monitor.empty.subtitle` | `Start Claude Code / opencode / codex in a terminal to monitor it.` | `Claude Code / opencode / codex をターミナルで起動すると監視されます。` |
| `agent.monitor.error.title` | `Failed to enumerate processes.` | `プロセスの列挙に失敗しました。` |
| `agent.monitor.error.retry` | `Retry` | `再試行` |
| `agent.monitor.state.working` | `Working` | `実行中` |
| `agent.monitor.state.callingAPI` | `Calling API` | `API 呼び出し中` |
| `agent.monitor.state.idle` | `Idle` | `アイドル` |
| `settings.tab.agentMonitor` | `Agent Monitor` | `エージェントモニター` |
| `settings.agentMonitor.patterns.title` | `Monitored process patterns` | `監視するプロセスパターン` |
| `settings.agentMonitor.patterns.hint` | `case-insensitive substring` | `大文字小文字を区別しない部分一致` |
| `settings.agentMonitor.interval` | `Polling interval` | `ポーリング間隔` |
| `settings.agentMonitor.showCount` | `Show count in menu bar` | `メニューバーに件数を表示` |
| `settings.agentMonitor.launchAtLogin` | `Launch at login` | `ログイン時に起動` |
| `menu.openAgentMonitor` | `Open Agent Monitor…` | `エージェントモニターを開く…` |
| `menu.settings` | `Settings…` | `設定…` |

### B.6 实施步骤

1. **StatusBarIconRenderer** + 单元测试（四态产物渲染）。
2. **StatusBarController** + 左/右键路由；接入 `AgentMonitor.eventHandler`。
3. **AgentMonitorPopoverController** + **AgentMonitorViewController**（含 Header / List / Footer / 空态 / 错误态五个子视图）。
4. **AgentMonitorSettingsViewController** + storyboard / xib；接入 `AgentMonitorSettings`。
5. `AgentPadWindowController` toolbar 增加 Agent Monitor 分页 + 切换 API。
6. NSMenu title 改名 + `Open Agent Monitor…` action 重接。
7. 本地化字符串 EN / JA 各 18 条。
8. 回归：旧右键菜单所有 IBAction 行为保持不变；手柄遥控功能零影响。

### B.7 验证点

- 状态栏：空 / 1 / 3 / 4 / 7 / PollingFailed 五种 fixture 下图标渲染像素级对照 design.md §1.2。
- 左键单击图标 → Popover 出现且固定 320×400pt；再次左键单击 → 关闭。
- 右键 / Ctrl+Click → 既有 NSMenu 弹出，所有菜单项行为与改名前一致。
- Popover 显示中 `AgentMonitor` 发布 `.updated` → List 即时刷新（无明显闪烁）。
- Popover Footer `Settings` 点击 → 主设置窗口打开并直接选中 Agent Monitor 分页。
- Agent Monitor 分页内修改 patterns / interval / showCount / launchAtLogin → 即时生效（无 Apply 按钮），重启 AgentPad 后值持久化。
- macOS 12 上 Launch at login 行 disable + 显示 "Requires macOS 13+"。
- 多语言（EN / JA）下 Popover 所有文案不溢出 / 不截断。

### B.8 风险与待决项

- **`NSStatusItem` 同时支持左右键路由的兼容性**：使用 `sendAction(on:)` 派发左/右键已在多个开源项目验证可行；如某些 macOS 版本下 Ctrl+Click 不命中 `.rightMouseUp`，需要补 `NSEvent.modifierFlags` 兜底。
- **图标重绘频率**：3s 轮询每次都重绘图标在 M1 上 < 1ms；如未来加 1s 节奏需要做圆点状态去抖。
- **Popover 失焦关闭与 Settings 跳转的时序**：点击 Footer `Settings` 时 Popover 会先关闭再开窗口，会出现 ≤ 100ms 视觉断层；可在 Settings 窗口 didShow 之前不显式关闭 Popover（让 `.transient` 行为自然触发）。

