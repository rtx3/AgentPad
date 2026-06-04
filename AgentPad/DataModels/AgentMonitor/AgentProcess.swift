//
//  AgentProcess.swift
//  AgentPad
//
//  Agent 监控领域的核心数据类型。仅描述「某轮 poll 看到的 agent 进程及其状态」，
//  不持久化，不参与 Core Data。
//

import Foundation

/// 进程级快照 + 状态结论。`AgentMonitor` 内部使用，不直接对 UI 暴露。
struct AgentProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let executablePath: String?
    let cwd: String?
    let startedAt: Date
    let state: AgentState
    let detail: AgentStateDetail
    let source: AgentStateSource

    var id: pid_t { pid }
}

/// 项目级聚合视图。同 (cwd, agentKind) 下的 N 个进程合并为一个 `AgentProject`，
/// 状态来自该组共享的 JSONL session。UI 列表渲染单元。
struct AgentProject: Identifiable, Equatable {
    /// 聚合 key："<cwd>|<agentKind>"；cwd=nil 时退化为 "<pid:N>|<agentKind>"。
    let id: String
    let cwd: String?
    /// "claude" / "codex" 等，来自 patterns 命中。
    let agentKind: String
    let state: AgentState
    let detail: AgentStateDetail
    let source: AgentStateSource
    /// 同 cwd 下命中 patterns 的进程数。
    let instanceCount: Int
    /// 最近启动的进程 pid。用于单 instance 时 UI 显示 / PTY 兜底。
    let primaryPid: pid_t
    /// 组内最早启动时刻。用于排序与 UI duration 显示。
    let earliestStartedAt: Date
    /// 绑定到的 jsonl session id（无绑定时 nil）。
    let sessionId: String?
    /// 末条 record 真实写入时刻；用于 UI 调试 / future 显示。
    let lastActivityAt: Date?
}

/// 五态。`Comparable` 仅用于 UI 排序：error > querying > working > callingAPI > idle。
enum AgentState: Int, Comparable {
    case idle = 1
    case callingAPI = 2
    case working = 3
    case querying = 4
    case error = 5

    static func < (lhs: AgentState, rhs: AgentState) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// 状态详情，主要供 UI 副行展示。
enum AgentStateDetail: Equatable {
    case toolUse(name: String?)
    case streaming
    case waitingInput(prompt: String?)
    case querying(question: String?)
    case errored(reason: String?)
    case unknown
}

/// 状态结论的来源。
enum AgentStateSource: Equatable {
    case jsonl(sessionId: String)
    case pty(snippet: String)
    case none
}

/// `AgentMonitor` 对外发布的事件。
enum AgentMonitorEvent {
    case updated(projects: [AgentProject])
    case empty
    case pollingFailed(consecutiveFailures: Int)
}
