# AgentPad 菜单与设置窗口设计

> 配套 `docs/product.md`。本文画当前 NSMenu → Popover 形态迁移后的菜单栏入口、详情面板，以及主窗口（设置）结构。手柄遥控相关入口本文不涉及，仅保留既有的设置窗口承载位。

---

## 0. 三块视图的总览关系

```
+-------------------+    左键单击      +--------------------------+
|  Menu Bar Icon    | ───────────────▶ |  Agent Monitor Popover   |
|  (圆点 + 计数)    |                  |  320 × 400 pt            |
+-------------------+                  +--------------------------+
       │                                          │
       │ 右键 / Ctrl+Click                        │ 底部 [Settings]
       ▼                                          ▼
+-------------------+   Settings…      +--------------------------+
| Status Bar NSMenu | ───────────────▶ |  Main Settings Window    |
| (重命名后的旧菜单)│                  |  splitView 三栏          |
+-------------------+                  +--------------------------+
                                                   │
                                                   │ 顶部菜单/快捷键
                                                   ▼
                                          (Preferences / About /
                                           Quit … 等系统级菜单)
```

要点：
- 左键 = 弹 Popover（产品主入口，product.md §3.1.4）。
- 右键 / Ctrl+Click = 弹既有 NSMenu（只改 title，不改 IBAction）。
- 设置窗口仍由 storyboard `AgentPadWindowController` 承载，splitView 三栏布局不变。

---

## 1. 菜单栏图标

### 1.1 状态总览

| 状态 | 绘制内容 | 触发条件 |
| --- | --- | --- |
| Empty | `circle.dashed` 单图标 | 没有任何进程命中监控模式 |
| 1–4 agents | N 个彩色圆点横排 + 计数（可关） | 命中模式且 N ≤ 4 |
| 5+ agents | 前 3 个圆点 + `+M`（M = N−3） + 计数 | 命中模式且 N > 4 |
| Polling Failed | 灰色 `exclamationmark.circle` | 轮询连续 3 次失败 |

### 1.2 布局示意

```
Empty:           [ ○ ]
1 agent:         [ ● ] 1
2 agents:        [ ●● ] 2
4 agents:        [ ●●●● ] 4
6 agents:        [ ●●●+3 ] 6     (前 3 圆点真实状态，"+3" 灰底)
Polling failed:  [ ⚠ ]
```

圆点配色严格对应 product.md §3.1.2 三态：
- 绿 = Working
- 橙 = Calling API
- 灰 = Idle

圆点排序：按状态优先级（Working > API > Idle），同级按启动时间升序。计数开关受设置项「菜单栏显示计数」控制。

### 1.3 交互

| 输入 | 动作 |
| --- | --- |
| 左键单击 | toggle Agent Monitor Popover（同图标位置弹/收） |
| 右键 / Ctrl+Click | 弹 Status Bar NSMenu |
| 拖拽 | 系统默认（重排序图标） |

---

## 2. Agent Monitor Popover

固定尺寸 320 × 400pt（product.md §3.1.4）。整体由 4 个区块自顶向下纵向堆叠。

### 2.1 区块布局

```
┌──────────────────────────────────────────┐ ← Popover 320 × 400
│  AGENT MONITOR              3 running    │  Header (高 40pt)
├──────────────────────────────────────────┤
│ ● claude — ~/Projects/myapp              │  Row #1
│   PID 12345 · subprocess: 3 active       │
│                       [ Working ]   5m   │
├──────────────────────────────────────────┤
│ ● codex — ~/Work/site                    │  Row #2
│   PID 12450 · streaming                  │
│                    [ Calling API ] 1h 23m│
├──────────────────────────────────────────┤
│ ○ opencode — ~/scratch                   │  Row #3
│   PID 12888 · idle                       │
│                          [ Idle ]   12s  │
│                                          │
│           ……（List 区可滚动）            │
├──────────────────────────────────────────┤
│  [ Settings ]                  [ Quit ]  │  Footer (高 36pt)
└──────────────────────────────────────────┘
```

#### Header
- 标题文本 `AGENT MONITOR`（大写、Caption 风格）。
- 右侧计数：`<N> running`，N=0 时显示 `idle`。
- 不带任何按钮（避免和 Footer 冲突）。

#### List 区
- `NSTableView` 单列、可滚动；项高约 64pt。
- 行内三段：
  - 左：状态圆点（12pt）。
  - 中：第一行进程名 + cwd（`name — short_cwd`，路径过长用 `…` 截尾保留尾部段）；第二行副信息（PID + 状态详情，如 `tool_use: <name>` / `streaming` / `waiting input` / `idle`，来源由 JSONL 路或 PTY 路给出）。
  - 右：状态胶囊（`Working` / `Calling API` / `Idle`） + 已运行时长（`5m` / `1h 23m` / `12s`）。
- 排序：状态优先级（Working > API > Idle），同级按启动时间升序；新进程出现/状态变化时整体重排，无动画。

#### 空态
当 List 为空：

```
┌──────────────────────────────────────────┐
│  AGENT MONITOR                    idle   │
├──────────────────────────────────────────┤
│                                          │
│            ○  No agent running           │
│   Start Claude Code / opencode / codex   │
│        in a terminal to monitor it.      │
│                                          │
├──────────────────────────────────────────┤
│  [ Settings ]                  [ Quit ]  │
└──────────────────────────────────────────┘
```

#### 错误态
轮询连续失败：

```
│  ⚠  Failed to enumerate processes.      │
│      [ Retry ]                          │
```

`Retry` 立即触发一次轮询；常态化轮询仍按原节奏继续。

#### Footer
- 左 `Settings` → 打开 Main Settings Window（同顶部菜单的 Preferences…）。
- 右 `Quit` → `NSApp.terminate(nil)`。
- 不放其它按钮，避免 Popover 退化成功能面板。

### 2.2 交互

| 输入 | 动作 |
| --- | --- |
| 点击 Popover 外区域 | 关闭 Popover |
| 点击 Row | 暂不响应（Roadmap：聚焦对应终端窗口） |
| 右键 Row | 暂不响应 |
| 点击 `Settings` | 打开主设置窗口，自动定位到 *Agent Monitor* 分页（见 §3.1） |
| 点击 `Quit` | 退出应用 |
| 轮询节奏 | 跟随设置项「轮询间隔」（2/3/5/10s） |

---

## 3. Main Settings Window

storyboard 既有 `AgentPadWindowController` 主窗口保持不变（`splitView` 三栏 + 顶部 toolbar）。本节给出区块划分，并标注 **本次新增** 的区块。

### 3.1 顶层结构

```
┌─ Main Settings Window ─────────────────────────────────────────┐
│ [ Apps │ KeyMap │ Controllers │ Agent Monitor* ]   ← Toolbar  │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│              对应分页内容（splitView 或单视图）                │
│                                                                │
└────────────────────────────────────────────────────────────────┘
   * = 新增分页（本次设计引入）
```

四个分页：
1. **Apps**（既有，三栏 splitView 左侧 AppList → KeyMap → Controllers）
2. **KeyMap**（既有，承接选中 app 的按键映射）
3. **Controllers**（既有，控制器图标网格）
4. **Agent Monitor**（新增，agent 监控配置）

> 说明：1/2/3 的视觉结构与现有 `splitView` 完全一致，本文不重画；只画 4。

### 3.2 Agent Monitor 分页

```
┌─ Agent Monitor ────────────────────────────────────────────────┐
│                                                                │
│  Monitored process patterns                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ claude                                                   │  │
│  │ opencode                                                 │  │
│  │ codex                                                    │  │
│  └──────────────────────────────────────────────────────────┘  │
│     [ + ]  [ − ]                  case-insensitive substring   │
│                                                                │
│  ─────────────────────────────────────────────────────────     │
│                                                                │
│  Polling interval        ( 2s ◯  3s ●  5s ◯  10s ◯ )           │
│                                                                │
│  Show count in menu bar  [ ✓ ]                                 │
│                                                                │
│  Launch at login         [   ]   (macOS 13+ SMAppService)      │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

字段：
- **Monitored process patterns**：`NSTableView` 单列，`+`/`−` 增删；存储到 `UserDefaults` key `agent.monitor.patterns`。
- **Polling interval**：单选 2/3/5/10s。
- **Show count in menu bar**：勾选，对应 §1.2 计数显示。
- **Launch at login**：调 SMAppService 注册 `helperAppID = com.rtx3.agentpad.launcher`（沿用既有 `AppDelegate.swift:14`）。

所有改动 **即时生效**（不需 Apply 按钮）：
- patterns / interval 改动 → 重启轮询定时器。
- 计数开关 → 立即重绘 Status Bar Icon。
- Launch at login → 立即调 SMAppService。

### 3.3 顶部 NSMenu（macOS 菜单栏，主应用菜单）

storyboard 既有，**不改**，仅作占位说明：

```
AgentPad │ File │ Edit │ Format │ View │ Window │ Help
   ├─ About AgentPad
   ├─ Preferences…  (⌘,)         ← 打开 Main Settings Window
   └─ Quit AgentPad  (⌘Q)
```

---

## 4. Status Bar NSMenu（既有右键菜单）

> 既有 storyboard 中挂在 `AppDelegate.menu` 的 NSMenu。**只改 title**，不改 IBAction，不改 IBOutlet 引用。改名后的入口仍保留，给老用户兜底。

### 4.1 改名映射表

| 既有 title | 改名后 title | 备注 |
| --- | --- | --- |
| `Enable key mappings` | `Enable key mappings` | 保留原状（手柄遥控相关，本文不动） |
| `Controllers`（子菜单） | `Controllers` | 保留原状 |
| `Open AgentPad…`（如有） | `Open Agent Monitor…` | 现在打开主窗口；改名后语义对齐 Popover |
| `Preferences…` | `Settings…` | 对齐 macOS 13+ 系统术语；keyEquivalent `,` 不变 |
| `Quit AgentPad` | `Quit AgentPad` | 保留 |

实质运行逻辑不动：`@IBOutlet weak var menu: NSMenu?` 和 `@IBOutlet weak var controllersMenu: NSMenuItem?` 引用保持，所选 menuItem 的 `action`/`target` 不动。

### 4.2 交互

| 输入 | 动作 |
| --- | --- |
| 右键 / Ctrl+Click 状态栏图标 | 弹该 NSMenu |
| 选 `Open Agent Monitor…` | 等价 §2 左键单击效果 |
| 选 `Settings…` | 等价 Popover 底部 `Settings` |
| 选 `Quit AgentPad` | 等价 Popover 底部 `Quit` |

---

## 5. 状态机（菜单栏图标 ↔ Popover ↔ 设置窗口）

```
        ┌────────────┐  poll tick (N>0)   ┌─────────────────┐
        │  Empty ○   │ ──────────────────▶│ Tracking ●●●    │
        │ (no agent) │ ◀──────────────────│ (1..N agents)   │
        └─────┬──────┘  poll tick (N==0)  └────┬────────────┘
              │                                 │
   poll fail ×3                            poll fail ×3
              │                                 │
              ▼                                 ▼
        ┌────────────┐  retry / success   ┌─────────────────┐
        │ Failed ⚠   │ ──────────────────▶│ (上一稳定态)    │
        └────────────┘                    └─────────────────┘

Popover 可在任意态下被左键单击 toggle；
Popover 显示时持续接收 poll 更新，不阻塞轮询。

Main Settings Window 与图标态完全解耦：
设置变更只触发"重启轮询" / "重绘图标"，不改变图标当前可见状态。
```

---

## 6. 未涵盖项（路线图占位）

按 product.md §6 路线图：
- Row 点击聚焦终端窗口（Popover §2.2 暂不响应已标注）。
- Idle 时手柄震动 / LED 提醒（不在本菜单文档范围）。
- Sparkle 2 自动更新菜单项（接入时挂到 §3.3 主应用菜单）。

---

*文档版本：v0.1（2026-05-26）。*
