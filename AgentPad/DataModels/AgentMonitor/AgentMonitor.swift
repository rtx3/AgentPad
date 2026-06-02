//
//  AgentMonitor.swift
//  AgentPad
//
//  调度入口。AppDelegate 持有一份实例（非单例）。
//  每轮 poll：枚举命中进程 → 按 (cwd, pattern) 聚合 → 组内跑 JSONL 主路 → PTY 兜底
//   → 排序发布事件。
//
//  聚合的原因（见 git log 与 docs）：claude/codex 进程与 session 文件是 N:M 关系，
//  同 cwd 多进程时无法精确把 pid 对应到唯一 session。改为「项目级」单元更符合用户感知。
//

import Foundation
import AppKit

final class AgentMonitor {
    /// 主线程回调；订阅方在 main queue 中安全更新 UI。
    /// 仅在 self.queue 上读写；setter 见 `setEventHandler(_:)`。
    private var _eventHandler: ((AgentMonitorEvent) -> Void)?

    private(set) var lastEvent: AgentMonitorEvent = .empty
    private(set) var lastProjects: [AgentProject] = []

    private let queue = DispatchQueue(label: "com.rtx3.agentpad.agentmonitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var consecutiveFailures: Int = 0
    private var intervalSec: Int

    /// groupKey → JSONL tail 上下文（key 形如 "<cwd>|<pattern>"）。
    /// 不再以 pid 为单位：同 cwd 多进程共享同一 context（同 session 文件）。
    private var jsonlContexts: [String: JSONLProbeContext] = [:]

    /// 各 pattern 对应的 SessionLocator。当前仅 Claude Code / Codex 有实现。
    private let locators: [String: SessionLocator]

    init(intervalSec: Int = AppSettings.AgentMonitor.pollIntervalSec) {
        self.intervalSec = intervalSec
        self.locators = [
            "claude": ClaudeCodeSessionLocator(),
            "codex": CodexSessionLocator()
        ]
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: AppSettings.AgentMonitor.settingsDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }

    // MARK: - Public API

    /// 替换 / 注销事件回调。线程安全。
    func setEventHandler(_ handler: ((AgentMonitorEvent) -> Void)?) {
        queue.async { [weak self] in
            self?._eventHandler = handler
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.scheduleTimer()
            self?.tickLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    func restart(interval: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.intervalSec = interval
            self.timer?.cancel()
            self.timer = nil
            self.scheduleTimer()
            self.tickLocked()
        }
    }

    /// 立即触发一次轮询（不重置 timer）。供 UI Retry 按钮调用。
    func pollOnce() {
        queue.async { [weak self] in
            self?.tickLocked()
        }
    }

    // MARK: - Timer

    private func scheduleTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .seconds(intervalSec),
                   repeating: .seconds(intervalSec),
                   leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in
            self?.tickLocked()
        }
        t.resume()
        timer = t
    }

    @objc private func settingsDidChange() {
        restart(interval: AppSettings.AgentMonitor.pollIntervalSec)
    }

    // MARK: - Poll core (queue-only)

    private struct ScanGroup {
        let cwd: String?
        let pattern: String
        var snaps: [ProcessSnapshot]
    }

    private func tickLocked() {
        let started = Date()
        do {
            let patterns = AppSettings.AgentMonitor.patterns
            let sessionRoots = AppSettings.AgentMonitor.sessionRoots
            let enablePTY = AppSettings.AgentMonitor.enablePTYProbe
            let failureThreshold = AppSettings.AgentMonitor.pollFailureThreshold
            let staleness = TimeInterval(AppSettings.AgentMonitor.stalenessThresholdSec)
            let axTrusted = AccessibilityPermission.isTrusted()

            let snapshots = try ProcessScanner.scan(matching: patterns)

            NSLog("[agent.monitor] tick patterns=\(patterns) matched=\(snapshots.count) axTrusted=\(axTrusted) enablePTY=\(enablePTY)")
            for s in snapshots {
                NSLog("[agent.monitor]   snap pid=\(s.pid) name=\(s.name) cwd=\(s.cwd ?? "<nil>")")
            }

            // 按 (cwd, pattern) 分组；保留 first-seen 顺序便于日志可读。
            var groups: [String: ScanGroup] = [:]
            var insertionOrder: [String] = []
            for s in snapshots {
                guard let pat = ProcessScanner.matchedPattern(name: s.name, patterns: patterns) else { continue }
                let key = Self.groupKey(cwd: s.cwd, pattern: pat, pid: s.pid)
                if groups[key] == nil {
                    groups[key] = ScanGroup(cwd: s.cwd, pattern: pat, snaps: [s])
                    insertionOrder.append(key)
                } else {
                    groups[key]!.snaps.append(s)
                }
            }

            // 清理已退出 group 对应的 jsonl context。
            let liveKeys = Set(groups.keys)
            jsonlContexts = jsonlContexts.filter { liveKeys.contains($0.key) }

            var projects: [AgentProject] = []
            projects.reserveCapacity(groups.count)
            for key in insertionOrder {
                guard let g = groups[key] else { continue }
                let project = buildProject(key: key,
                                           cwd: g.cwd,
                                           pattern: g.pattern,
                                           snaps: g.snaps,
                                           sessionRoots: sessionRoots,
                                           enablePTY: enablePTY,
                                           staleness: staleness)
                projects.append(project)
                NSLog("[agent.monitor]   result project=\(key) state=\(project.state) source=\(project.source) detail=\(project.detail) instances=\(project.instanceCount)")
            }
            projects.sort { lhs, rhs in
                if lhs.state != rhs.state { return lhs.state > rhs.state }
                return lhs.earliestStartedAt < rhs.earliestStartedAt
            }
            let elapsed = Date().timeIntervalSince(started)
            let budget = TimeInterval(intervalSec) * 0.8
            if elapsed > budget {
                NSLog("[agent.monitor] tick elapsed=\(String(format: "%.3f", elapsed))s budget=\(budget)s → failure tick")
                handleFailure(threshold: failureThreshold)
            } else {
                consecutiveFailures = 0
            }
            lastProjects = projects
            let evt: AgentMonitorEvent = projects.isEmpty ? .empty : .updated(projects: projects)
            publish(evt)
        } catch {
            NSLog("[agent.monitor] tick scan error: \(error)")
            handleFailure(threshold: AppSettings.AgentMonitor.pollFailureThreshold)
        }
    }

    /// 同 (cwd, pattern) 的所有进程聚合为一个 AgentProject。
    private func buildProject(key: String,
                              cwd: String?,
                              pattern: String,
                              snaps: [ProcessSnapshot],
                              sessionRoots: [String: String],
                              enablePTY: Bool,
                              staleness: TimeInterval) -> AgentProject {
        // 组内最近启动的代表（PTY 兜底用），与组内最早启动（duration / 排序用）。
        let primary = snaps.max(by: { $0.startedAt < $1.startedAt }) ?? snaps[0]
        let earliest = snaps.min(by: { $0.startedAt < $1.startedAt })?.startedAt ?? primary.startedAt
        let kindLower = pattern.lowercased()

        // 1. JSONL 主路（组内共享 context）
        let root = sessionRoots[kindLower] ?? sessionRoots[pattern]
        let loc = self.locator(for: pattern)
        let url = (loc != nil) ? loc!.locate(pid: primary.pid, cwd: cwd, sessionRoot: root ?? "") : nil
        NSLog("[agent.monitor]     jsonl group=\(key) pattern=\(pattern) root=\(root ?? "<nil>") urlFound=\(url?.lastPathComponent ?? "<nil>")")

        if let url = url, root != nil {
            let ctx = jsonlContexts[key] ?? JSONLProbeContext(pid: primary.pid, cwd: cwd)
            jsonlContexts[key] = ctx
            ctx.bind(to: url)
            ctx.tick()
            let lastType = ctx.lastRecord?.type ?? "<nil>"
            let lastPayload = ctx.lastRecord?.payloadType ?? "<nil>"
            let lastStop = ctx.lastRecord?.stopReason ?? "<nil>"
            let lastTool = ctx.lastRecord?.toolUseName ?? "<nil>"
            NSLog("[agent.monitor]     jsonl tick group=\(key) lastType=\(lastType) payload=\(lastPayload) stop=\(lastStop) tool=\(lastTool)")
            let cls = Self.classifyByPattern(
                pattern: pattern,
                record: ctx.lastRecord,
                lastWriteAt: ctx.lastWriteAt,
                stalenessThreshold: staleness
            )
            if let cls = cls {
                let sid = url.deletingPathExtension().lastPathComponent
                return AgentProject(
                    id: key,
                    cwd: cwd,
                    agentKind: kindLower,
                    state: cls.state,
                    detail: cls.detail,
                    source: .jsonl(sessionId: sid),
                    instanceCount: snaps.count,
                    primaryPid: primary.pid,
                    earliestStartedAt: earliest,
                    sessionId: sid,
                    lastActivityAt: ctx.lastWriteAt
                )
            }
        }
        // 2. PTY 兜底：用最近启动的 pid 做 host 查找（更可能对应用户当前活跃窗口）。
        if enablePTY {
            let pty = PTYStateProbe.probe(forAgentPID: primary.pid)
            NSLog("[agent.monitor]     pty group=\(key) pid=\(primary.pid) hit=\(pty != nil) snippet=\(pty?.snippet ?? "<nil>")")
            if let pty = pty {
                return AgentProject(
                    id: key,
                    cwd: cwd,
                    agentKind: kindLower,
                    state: pty.state,
                    detail: pty.detail,
                    source: .pty(snippet: pty.snippet),
                    instanceCount: snaps.count,
                    primaryPid: primary.pid,
                    earliestStartedAt: earliest,
                    sessionId: nil,
                    lastActivityAt: nil
                )
            }
        }
        // 3. 兜底 idle
        return AgentProject(
            id: key,
            cwd: cwd,
            agentKind: kindLower,
            state: .idle,
            detail: .unknown,
            source: .none,
            instanceCount: snaps.count,
            primaryPid: primary.pid,
            earliestStartedAt: earliest,
            sessionId: nil,
            lastActivityAt: nil
        )
    }

    /// 组 key：cwd 有值时 "<cwd>|<pattern>"，否则退化按 pid「不聚合」。
    /// 退化时仍带 pattern 前缀以便和有 cwd 的组区分；多 nil-cwd 进程各自独立显示。
    private static func groupKey(cwd: String?, pattern: String, pid: pid_t) -> String {
        let pat = pattern.lowercased()
        if let c = cwd, !c.isEmpty {
            return "\(c)|\(pat)"
        }
        return "<pid:\(pid)>|\(pat)"
    }

    /// 按 pattern 选用对应 classifier。
    /// 当前：`codex` → CodexJSONLProbe；其他（含 `claude`） → JSONLSessionProbe。
    private static func classifyByPattern(pattern: String,
                                          record: JSONLRecord?,
                                          lastWriteAt: Date?,
                                          stalenessThreshold: TimeInterval) -> (state: AgentState, detail: AgentStateDetail)? {
        switch pattern.lowercased() {
        case "codex":
            return CodexJSONLProbe.classify(record: record,
                                            lastWriteAt: lastWriteAt,
                                            stalenessThreshold: stalenessThreshold)
        default:
            return JSONLSessionProbe.classify(record: record,
                                              lastWriteAt: lastWriteAt,
                                              stalenessThreshold: stalenessThreshold)
        }
    }

    private func locator(for pattern: String) -> SessionLocator? {
        return locators[pattern.lowercased()] ?? locators[pattern]
    }

    private func handleFailure(threshold: Int) {
        consecutiveFailures += 1
        if consecutiveFailures >= threshold {
            publish(.pollingFailed(consecutiveFailures: consecutiveFailures))
        }
    }

    private func publish(_ event: AgentMonitorEvent) {
        lastEvent = event
        let handler = _eventHandler   // 只在 self.queue 上读，无 race
        DispatchQueue.main.async {
            handler?(event)
        }
    }
}
