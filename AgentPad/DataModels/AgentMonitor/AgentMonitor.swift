//
//  AgentMonitor.swift
//  AgentPad
//
//  调度入口。AppDelegate 持有一份实例（非单例，决策点 5.b）。
//  每轮 poll：枚举命中进程 → 每进程跑 JSONL 主路 → PTY 兜底 → 排序发布事件。
//

import Foundation
import AppKit

final class AgentMonitor {
    /// 主线程回调；订阅方在 main queue 中安全更新 UI。
    /// 仅在 self.queue 上读写；setter 见 `setEventHandler(_:)`。
    private var _eventHandler: ((AgentMonitorEvent) -> Void)?

    private(set) var lastEvent: AgentMonitorEvent = .empty
    private(set) var lastProcesses: [AgentProcess] = []

    private let queue = DispatchQueue(label: "com.rtx3.agentpad.agentmonitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var consecutiveFailures: Int = 0
    private var intervalSec: Int

    /// pid → JSONL tail 上下文。已退出的进程在下一轮被清理。
    private var jsonlContexts: [pid_t: JSONLProbeContext] = [:]

    /// 各 pattern 对应的 SessionLocator。当前仅 Claude Code 有实现。
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

    private func tickLocked() {
        let started = Date()
        do {
            let patterns = AppSettings.AgentMonitor.patterns
            let sessionRoots = AppSettings.AgentMonitor.sessionRoots
            let enablePTY = AppSettings.AgentMonitor.enablePTYProbe
            let failureThreshold = AppSettings.AgentMonitor.pollFailureThreshold
            let axTrusted = AccessibilityPermission.isTrusted()

            let snapshots = try ProcessScanner.scan(matching: patterns)
            let liveSet = Set(snapshots.map { $0.pid })
            jsonlContexts = jsonlContexts.filter { liveSet.contains($0.key) }

            NSLog("[agent.monitor] tick patterns=\(patterns) matched=\(snapshots.count) axTrusted=\(axTrusted) enablePTY=\(enablePTY)")
            for s in snapshots {
                NSLog("[agent.monitor]   snap pid=\(s.pid) name=\(s.name) cwd=\(s.cwd ?? "<nil>")")
            }

            var processes: [AgentProcess] = []
            processes.reserveCapacity(snapshots.count)

            for snap in snapshots {
                let agent = buildAgent(from: snap,
                                       patterns: patterns,
                                       sessionRoots: sessionRoots,
                                       enablePTY: enablePTY)
                processes.append(agent)
                NSLog("[agent.monitor]   result pid=\(agent.pid) state=\(agent.state) source=\(agent.source) detail=\(agent.detail)")
            }
            processes.sort { lhs, rhs in
                if lhs.state != rhs.state { return lhs.state > rhs.state }
                return lhs.startedAt < rhs.startedAt
            }
            let elapsed = Date().timeIntervalSince(started)
            let budget = TimeInterval(intervalSec) * 0.8
            if elapsed > budget {
                NSLog("[agent.monitor] tick elapsed=\(String(format: "%.3f", elapsed))s budget=\(budget)s → failure tick")
                handleFailure(threshold: failureThreshold)
            } else {
                consecutiveFailures = 0
            }
            lastProcesses = processes
            let evt: AgentMonitorEvent = processes.isEmpty ? .empty : .updated(processes: processes)
            publish(evt)
        } catch {
            NSLog("[agent.monitor] tick scan error: \(error)")
            handleFailure(threshold: AppSettings.AgentMonitor.pollFailureThreshold)
        }
    }

    private func buildAgent(from snap: ProcessSnapshot,
                            patterns: [String],
                            sessionRoots: [String: String],
                            enablePTY: Bool) -> AgentProcess {
        // 1. JSONL 主路
        let pattern = ProcessScanner.matchedPattern(name: snap.name, patterns: patterns)
        let root = pattern.flatMap { sessionRoots[$0.lowercased()] ?? sessionRoots[$0] }
        let loc = pattern.flatMap { self.locator(for: $0) }
        let url = (loc != nil) ? loc!.locate(pid: snap.pid, cwd: snap.cwd, sessionRoot: root ?? "") : nil
        NSLog("[agent.monitor]     jsonl pid=\(snap.pid) pattern=\(pattern ?? "<nil>") root=\(root ?? "<nil>") urlFound=\(url?.lastPathComponent ?? "<nil>")")

        if let url = url, let pattern = pattern, root != nil {
            let ctx = jsonlContexts[snap.pid] ?? JSONLProbeContext(pid: snap.pid, cwd: snap.cwd)
            jsonlContexts[snap.pid] = ctx
            ctx.bind(to: url)
            ctx.tick()
            let lastType = ctx.lastRecord?.type ?? "<nil>"
            let lastStop = ctx.lastRecord?.stopReason ?? "<nil>"
            let lastTool = ctx.lastRecord?.toolUseName ?? "<nil>"
            NSLog("[agent.monitor]     jsonl tick pid=\(snap.pid) lastType=\(lastType) stop=\(lastStop) tool=\(lastTool)")
            _ = pattern
            if let cls = JSONLSessionProbe.classify(record: ctx.lastRecord, lastWriteAt: ctx.lastWriteAt) {
                let sid = url.deletingPathExtension().lastPathComponent
                return AgentProcess(
                    pid: snap.pid, name: snap.name,
                    executablePath: snap.executablePath, cwd: snap.cwd,
                    startedAt: snap.startedAt,
                    state: cls.state, detail: cls.detail,
                    source: .jsonl(sessionId: sid)
                )
            }
        }
        // 2. PTY 兜底
        if enablePTY {
            let pty = PTYStateProbe.probe(forAgentPID: snap.pid)
            NSLog("[agent.monitor]     pty pid=\(snap.pid) hit=\(pty != nil) snippet=\(pty?.snippet ?? "<nil>")")
            if let pty = pty {
                return AgentProcess(
                    pid: snap.pid, name: snap.name,
                    executablePath: snap.executablePath, cwd: snap.cwd,
                    startedAt: snap.startedAt,
                    state: pty.state, detail: pty.detail,
                    source: .pty(snippet: pty.snippet)
                )
            }
        }
        // 3. 兜底 idle
        return AgentProcess(
            pid: snap.pid, name: snap.name,
            executablePath: snap.executablePath, cwd: snap.cwd,
            startedAt: snap.startedAt,
            state: .idle, detail: .unknown,
            source: .none
        )
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
