# AgentPad 产品说明文档

> macOS 上的 AI Coding Agent 控制台 —— 看得见状态，按得下决策。

---

## 1. 产品概述

AgentPad 是一款面向 AI 编程助手用户的 macOS 原生应用。它把"看 agent 在干什么"与"控制 agent 下一步动作"两件事合并在同一个菜单栏入口里：

- 一边实时监控 Claude Code、Codex、opencode 等自主运行的 AI agent 进程，通过三态指示器让用户一眼掌握每个 agent 当前是在执行命令、调用 API，还是空闲等待输入；
- 一边把游戏手柄变成 agent 的专用遥控器，让 approve / reject / 翻页 / 切窗口这些高频小决策不再打断阅读节奏。

形态上是常驻菜单栏的 AppKit 原生应用，配合独立的 Popover 详情面板和设置窗口。

### 核心价值

- **零干扰感知**：常驻菜单栏，不占用 Dock 和任务栏空间
- **实时状态可视化**：彩色圆点 + 状态标签，瞬间区分多个 agent 的工作阶段
- **拇指级决策**：高频的 y/n、翻页、切窗口动作交给手柄，眼睛留在 diff 上

---

## 2. 目标用户与场景

### 2.1 用户画像

- 长时间挂着多个 AI Coding Agent 会话的开发者
- 常在多个 Terminal / IDE 之间切换、被 agent 的 y/n 询问频繁打断的人
- 希望"放空大脑读代码、手指轻按确认"的重度使用者

### 2.2 典型场景

- 在沙发上读 diff，靠手柄拇指完成 approve / reject
- 多个 agent 并行跑任务，需要一眼看出哪个在等输入、哪个在调 API、哪个在跑命令
- 一边写代码一边玩游戏，希望同一个手柄在游戏里仍是原生手柄

---

## 3. 核心功能

### 3.1 Agent 状态监控

#### 3.1.1 智能进程发现

通过 macOS 底层系统调用扫描所有运行中的进程，根据用户配置的进程名模式进行匹配。匹配采用大小写不敏感的子串包含策略，确保能准确识别各种命名变体。

**默认监控目标：**

| 模式 | 匹配工具 |
|------|----------|
| `claude` | Claude Code CLI |
| `opencode` | opencode CLI |
| `codex` | codex CLI |

用户可在设置中添加任意自定义模式以监控其他 AI agent 工具。

#### 3.1.2 三态状态引擎

每个被监控的 agent 进程会被实时判定为以下三种状态之一：

| 状态 | 图标 | 含义 |
|------|------|------|
| **Working** | 🟢 绿色 | Agent 正在执行工具调用 / 命令 |
| **Calling API** | 🟡 橙色 | Agent 正在与大模型通信 |
| **Idle** | ⚪ 灰色 | Agent 空闲，等待用户输入 |

状态判定仅基于两路本地信号，不依赖任何网络嗅探或子进程探测：

- **Session JSONL tail（主路）**：对会把会话写到本地 JSONL 的 agent（首发覆盖 Claude Code，其他 agent 后续适配），tail 当前 session 文件，按末尾记录类型推断状态。
  - 末尾为 assistant 含 `tool_use` 或 tool_result 未闭合 → Working
  - 末尾为 assistant 处于 streaming（无终止 `stop_reason`）→ Calling API
  - 末尾为 assistant 已完成（带终止 `stop_reason`）或 user 消息等待响应 → Idle
- **PTY 内容抓取（兜底）**：通过 Accessibility 权限读取宿主 Terminal / iTerm / Ghostty 等窗口文本，匹配 agent 输出的提示串。
  - 含 "esc to interrupt" / "running tool" 等执行中提示 → Working
  - 含 "thinking" / 流式 token 持续刷新等通信提示 → Calling API
  - 仅显示输入提示符 / "Do you want to …" 等待确认 → Idle

**状态优先级**：Working > Calling API > Idle。当 JSONL 路可用时以 JSONL 为准；否则回退至 PTY 路；两路同时给出结论按优先级合并取高者。

#### 3.1.3 菜单栏状态概览

菜单栏图标区域以紧凑方式呈现所有被监控 agent 的状态：

- **彩色圆点**：每个 agent 对应一个圆点，颜色反映当前状态（最多显示 4 个）
- **计数器**：可选显示当前活跃 agent 总数
- **空闲指示**：当无 agent 运行时，显示虚线圆圈图标（`circle.dashed`）

#### 3.1.4 Popover 详情面板

点击菜单栏图标弹出详情面板（320×400pt），包含：

- **标题栏**：显示 "AGENT MONITOR" 及进程总数
- **进程列表**：按状态优先级排序，每条目包含：
  - 状态圆点（彩色）
  - 进程名与工作目录（如 `claude — ~/Projects/myapp`）
  - PID 和状态详情（如 `PID 12345 · subprocess: 3 active`）
  - 状态标签（胶囊形）
  - 已运行时长（如 `5m`、`1h 23m`）
- **空状态提示**：无 agent 运行时显示引导文案
- **底部操作栏**：Settings / Quit 按钮

### 3.2 手柄遥控

#### 3.2.1 按键映射

将控制器按钮 / 摇杆映射到键盘按键、鼠标按钮或系统动作。捕捉对话框支持两种模式：

- **Simple**：按下任意键盘按键即刻分配并关闭对话框，无需勾选修饰键
- **Detailed**：选择按键并叠加 ⌘ / ⌥ / ⌃ / ⇧ 修饰键，或选择鼠标按钮（用于组合键）
- **Agent**： 和Agent有关的快捷操作

**示例：Claude Code in Terminal**

| Button | Action |
| --- | --- |
| A | `y`（approve） |
| B | `n`（reject） |
| L / R | 向上 / 向下滚动 |
| Start | `Ctrl+C` |
| Home | 聚焦终端 / 切换 profile |

#### 3.2.2 Per-App Profile

为每个应用单独维护一套按键映射，AgentPad 根据当前 frontmost app 自动切换。Claude Code 在 Terminal、Cursor、浏览器各可一套，无需手动切换。

**Sync from Default** 一键将默认 profile 复制覆盖到选中 app（支持撤销）。

#### 3.2.3 Passthrough

为指定 app 勾选 Passthrough，AgentPad 不再拦截手柄事件，让控制器在该应用中保持原生游戏手柄身份。启动游戏时无需手动切换。

#### 3.2.4 支持的控制器

当前支持：Joy-Con (L)、Joy-Con (R)、Pro Controller、Famicom Controller 1 / 2、SNES Online Controller。

控制器列表在每个图标下显示型号名称。

### 3.3 配置与权限

#### 3.3.1 设置项

通过独立设置窗口提供以下配置：

| 设置项 | 默认值 | 说明 |
|--------|--------|------|
| 监控进程模式 | `claude`, `opencode`, `codex` | 进程名匹配模式列表，支持增删 |
| 轮询间隔 | 3 秒 | 可选 2s / 3s / 5s / 10s |
| 菜单栏显示计数 | 开启 | 在圆点旁显示 agent 数量 |
| 登录时启动 | 关闭 | 开机自启动（需 macOS 13+ SMAppService） |
| Per-App 映射 | 默认空 | 添加要单独配置的应用 |
| Passthrough App | 默认空 | 指定保留原生手柄身份的应用 |

所有设置通过 `UserDefaults` / Core Data 持久化，即时生效。

#### 3.3.2 权限

- **Accessibility（辅助功能）**：手柄遥控功能必需（`CGEventPost` 注入键盘 / 鼠标事件）；同时也是 Agent 状态 PTY 兜底路径必需（读取 Terminal 窗口文本）。首次启动通过应用内引导走查向用户解释并跳转「系统设置 > 隐私与安全性 > 辅助功能」开启。
- **进程监控**：基于公开系统调用，无需额外权限。
- **会话日志读取**：读取 `~/.claude/projects/**/<sessionId>.jsonl` 等 agent 自身写入的本地会话文件，无需额外权限。

---

## 4. 支持的 AI Agent

### 4.1 开箱即用

| Agent 工具 | 匹配模式 | 说明 |
|-----------|---------|------|
| Claude Code | `claude` | Anthropic 官方 CLI 编程助手 |
| opencode | `opencode` | 开源 AI 编程助手 |
| codex CLI | `codex` | codex CLI 编程助手 |

### 4.2 自定义扩展

设置中添加任意进程名模式即可监控其他 AI agent 工具。

---

## 5. 技术约束与分发

- **运行依赖**：macOS 原生 AppKit；使用 `CGEventPost` 向其他进程注入键盘 / 鼠标事件
- **沙盒**：因依赖 Accessibility 权限，应用不开启 App Sandbox
- **分发渠道**：仅通过 GitHub Releases 直接分发（Developer ID + Notarization + Stapling），不上 Mac App Store
- **详细分发资源清单**：见 `docs/distribution.md`

---

## 6. 路线图

- **更多控制器支持**：DualShock 4 / DualSense / Xbox / MFi（通过 `GameController.framework`）
- **状态—遥控联动**：
  - Agent 进入 Idle（等待输入）时手柄震动 / LED 提醒
  - Popover 中"等待用户输入"的 agent 一键聚焦到对应终端窗口
  - 根据当前活跃 agent 自动切换到对应 per-app profile
- **审计能力**：记录 agent 执行的命令、读写的文件、访问的网络端点
- **Agent 统计**：每个 agent 的运行时长、活跃比例、状态分布等多维度统计
- **Sparkle 2 自动更新**：GitHub build 走 Sparkle 内置更新通道

完整工程任务列表见 `docs/plan.md`。
