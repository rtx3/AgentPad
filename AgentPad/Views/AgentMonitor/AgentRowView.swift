//
//  AgentRowView.swift
//  AgentPad
//
//  Popover 列表的单行视图。代码布局。
//  布局（左→右）：
//    [dot]  [项目名 ─────────────────  duration]
//           [agentKind · detail · pid/procs       ]
//

import AppKit

final class AgentRowView: NSTableCellView {
    static let rowHeight: CGFloat = 48

    private let dot = NSView()
    /// 主行：项目名（cwd 末段）。
    private let projectNameLabel = NSTextField(labelWithString: "")
    /// 主行右侧：duration（紧凑表达）。
    private let durationLabel = NSTextField(labelWithString: "")
    /// 副行：agentKind · detail · pid/procs。
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        projectNameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        projectNameLabel.lineBreakMode = .byTruncatingTail
        projectNameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(projectNameLabel)

        durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.textColor = .secondaryLabelColor
        durationLabel.alignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(durationLabel)

        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dot.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            projectNameLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            projectNameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            projectNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),

            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            durationLabel.centerYAnchor.constraint(equalTo: projectNameLabel.centerYAnchor),

            subtitleLabel.leadingAnchor.constraint(equalTo: projectNameLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: projectNameLabel.bottomAnchor, constant: 3),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }

    /// 缓存当前 project 的状态色，用于 Dark Mode 切换时重绘 CGColor。
    private var currentState: AgentState?

    func configure(with project: AgentProject, now: Date = Date()) {
        currentState = project.state
        applyStateColor()

        projectNameLabel.stringValue = Self.projectName(from: project.cwd)
        durationLabel.stringValue = Self.formatRelativeDuration(from: project.earliestStartedAt, to: now)
        subtitleLabel.stringValue = Self.subtitleText(for: project)
    }

    private func applyStateColor() {
        guard let state = currentState else { return }
        let color = StatusBarIconRenderer.color(for: state)
        dot.layer?.backgroundColor = color.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Dynamic NSColor 在赋值瞬间被解析为当时 appearance 的 cgColor，
        // 切换 light/dark 时需要重新解析。
        applyStateColor()
    }

    // MARK: - Text formatting

    /// cwd 末段作为项目名；cwd 为空时用 "—"。
    /// 例：`/Users/mac/Zero/Proj/Coding/AgentPad` → `AgentPad`。
    static func projectName(from cwd: String?) -> String {
        guard let cwd = cwd, !cwd.isEmpty else { return "—" }
        let parts = cwd.split(separator: "/", omittingEmptySubsequences: true)
        return parts.last.map(String.init) ?? cwd
    }

    /// 副行：agentKind · detail · pid|procs。
    /// detail 简洁化，避免与 state 颜色重复传达「正在工作」。
    static func subtitleText(for project: AgentProject) -> String {
        var parts: [String] = [project.agentKind]
        parts.append(detailText(project.detail, state: project.state))
        if project.instanceCount > 1 {
            parts.append("\(project.instanceCount) procs")
        } else {
            parts.append("pid \(project.primaryPid)")
        }
        return parts.joined(separator: " · ")
    }

    /// detail 的可读文本。同时把 state 信号也带进来：state=idle 但 detail=unknown 时显示 "idle"。
    static func detailText(_ detail: AgentStateDetail, state: AgentState) -> String {
        switch detail {
        case .toolUse(let name):
            if let n = name, !n.isEmpty { return "tool_use: \(n)" }
            return "tool_use"
        case .streaming:
            return "streaming"
        case .waitingInput(let prompt):
            if let p = prompt, !p.isEmpty { return "waiting: \(p)" }
            return "waiting input"
        case .unknown:
            switch state {
            case .working:    return "working"
            case .callingAPI: return "calling API"
            case .idle:       return "idle"
            }
        }
    }

    /// 紧凑 duration：单位 ≤ 1d 时 "Nh Mm"；多日 "Nd Mh"；超 1 周 "Nw Md"。
    /// 设计上限定双单位 + 数字 ≤ 2 位，避免横向溢出。
    static func formatRelativeDuration(from start: Date, to now: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(start)))
        if secs < 60 { return "\(secs)s" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        if hours < 24 {
            let remMin = mins % 60
            return remMin == 0 ? "\(hours)h" : "\(hours)h \(remMin)m"
        }
        let days = hours / 24
        if days < 7 {
            let remHour = hours % 24
            return remHour == 0 ? "\(days)d" : "\(days)d \(remHour)h"
        }
        let weeks = days / 7
        let remDay = days % 7
        return remDay == 0 ? "\(weeks)w" : "\(weeks)w \(remDay)d"
    }
}
