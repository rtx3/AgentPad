//
//  AgentProcess.swift
//  AgentPad
//
//  Agent 监控领域的核心数据类型。仅描述「某轮 poll 看到的 agent 进程及其状态」，
//  不持久化，不参与 Core Data。
//

import Foundation

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

/// 三态。`Comparable` 仅用于 UI 排序：Working > CallingAPI > Idle。
enum AgentState: Int, Comparable {
    case idle = 1
    case callingAPI = 2
    case working = 3

    static func < (lhs: AgentState, rhs: AgentState) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// 状态详情，主要供 UI 副行展示。
enum AgentStateDetail: Equatable {
    case toolUse(name: String?)
    case streaming
    case waitingInput(prompt: String?)
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
    case updated(processes: [AgentProcess])
    case empty
    case pollingFailed(consecutiveFailures: Int)
}
