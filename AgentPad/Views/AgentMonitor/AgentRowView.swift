//
//  AgentRowView.swift
//  AgentPad
//
//  Popover 列表的单行视图。代码布局，64pt 高。
//

import AppKit

final class AgentRowView: NSTableCellView {
    static let rowHeight: CGFloat = 48

    private let dot = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let cwdLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")

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

        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        cwdLabel.font = NSFont.systemFont(ofSize: 11)
        cwdLabel.textColor = .secondaryLabelColor
        cwdLabel.lineBreakMode = .byTruncatingMiddle
        cwdLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cwdLabel)

        secondaryLabel.font = NSFont.systemFont(ofSize: 10)
        secondaryLabel.textColor = .tertiaryLabelColor
        secondaryLabel.lineBreakMode = .byTruncatingTail
        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(secondaryLabel)

        stateLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        stateLabel.alignment = .right
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stateLabel)

        durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        durationLabel.textColor = .tertiaryLabelColor
        durationLabel.alignment = .right
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(durationLabel)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dot.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            nameLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: stateLabel.leadingAnchor, constant: -8),

            cwdLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            cwdLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            cwdLabel.trailingAnchor.constraint(lessThanOrEqualTo: stateLabel.leadingAnchor, constant: -8),

            secondaryLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            secondaryLabel.topAnchor.constraint(equalTo: cwdLabel.bottomAnchor, constant: 1),
            secondaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),

            stateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stateLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            durationLabel.trailingAnchor.constraint(equalTo: stateLabel.trailingAnchor),
            durationLabel.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 2),
        ])
    }

    /// 缓存当前 agent 的状态色，用于 Dark Mode 切换时重绘 CGColor。
    private var currentState: AgentState?

    func configure(with agent: AgentProcess, now: Date = Date()) {
        currentState = agent.state
        applyStateColor()

        nameLabel.stringValue = agent.name
        cwdLabel.stringValue = Self.shortenCWD(agent.cwd)
        secondaryLabel.stringValue = "PID \(agent.pid) · \(Self.detailText(agent.detail))"
        stateLabel.stringValue = Self.stateText(agent.state)
        durationLabel.stringValue = Self.formatRelativeDuration(from: agent.startedAt, to: now)
    }

    private func applyStateColor() {
        guard let state = currentState else { return }
        let color = StatusBarIconRenderer.color(for: state)
        dot.layer?.backgroundColor = color.cgColor
        stateLabel.textColor = color
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Dynamic NSColor 在赋值瞬间被解析为当时 appearance 的 cgColor，
        // 切换 light/dark 时需要重新解析。
        applyStateColor()
    }

    static func shortenCWD(_ cwd: String?) -> String {
        guard let cwd = cwd, !cwd.isEmpty else { return "—" }
        let home = NSHomeDirectory()
        var s = cwd
        if s.hasPrefix(home) {
            s = "~" + s.dropFirst(home.count)
        }
        // 控制长度：保留最后 3 段
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count <= 4 { return s }
        let tail = parts.suffix(3).joined(separator: "/")
        return "…/\(tail)"
    }

    static func detailText(_ detail: AgentStateDetail) -> String {
        switch detail {
        case .toolUse(let name):
            if let n = name, !n.isEmpty { return "tool_use: \(n)" }
            return "tool_use"
        case .streaming:
            return "streaming"
        case .waitingInput(let prompt):
            if let p = prompt, !p.isEmpty { return "waiting input · \(p)" }
            return "waiting input"
        case .unknown:
            return "idle"
        }
    }

    static func stateText(_ state: AgentState) -> String {
        switch state {
        case .working:    return NSLocalizedString("agent.monitor.state.working", comment: "")
        case .callingAPI: return NSLocalizedString("agent.monitor.state.callingAPI", comment: "")
        case .idle:       return NSLocalizedString("agent.monitor.state.idle", comment: "")
        }
    }

    static func formatRelativeDuration(from start: Date, to now: Date) -> String {
        let secs = Int(now.timeIntervalSince(start))
        if secs < 60 { return "\(secs)s" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        let remMin = mins % 60
        return remMin == 0 ? "\(hours)h" : "\(hours)h \(remMin)m"
    }
}
