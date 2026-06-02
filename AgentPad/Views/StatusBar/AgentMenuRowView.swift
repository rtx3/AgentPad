//
//  AgentMenuRowView.swift
//  AgentPad
//
//  状态栏菜单中单个 AgentProject 的行视图，作为 NSMenuItem.view 使用。
//  layout 与 AgentRowView 对齐：dot · projectName · duration / 副行 agentKind · detail · pid|procs。
//
//  注：NSMenu 在 popping 时 host 视图，因此布局必须用 explicit frame，而不是 autoresize 依赖父级。
//  width 取常量；NSMenu 会按所有 item view 中最宽的统一拉宽，避免参差。
//

import AppKit

final class AgentMenuRowView: NSView {
    static let rowHeight: CGFloat = 44
    static let rowWidth: CGFloat = 320

    private let dot = NSView()
    private let projectNameLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init(project: AgentProject, now: Date = Date()) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: Self.rowHeight))
        setupViews()
        configure(with: project, now: now)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        autoresizingMask = [.width]   // 允许 NSMenu 横向拉伸 row 时跟随

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.frame = NSRect(x: 16, y: Self.rowHeight - 16, width: 8, height: 8)
        dot.autoresizingMask = [.minYMargin]
        addSubview(dot)

        projectNameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        projectNameLabel.lineBreakMode = .byTruncatingTail
        projectNameLabel.frame = NSRect(x: 32, y: Self.rowHeight - 24, width: 180, height: 18)
        projectNameLabel.autoresizingMask = [.minYMargin]
        addSubview(projectNameLabel)

        durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.textColor = .secondaryLabelColor
        durationLabel.alignment = .left
        durationLabel.frame = NSRect(x: 220, y: Self.rowHeight - 22, width: 80, height: 14)
        durationLabel.autoresizingMask = [.minYMargin]
        addSubview(durationLabel)

        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.frame = NSRect(x: 32, y: 6, width: Self.rowWidth - 48, height: 14)
        subtitleLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(subtitleLabel)
    }

    /// 缓存当前 project 的状态，用于 Dark Mode 切换时重绘 CGColor。
    private var currentState: AgentState?

    func configure(with project: AgentProject, now: Date = Date()) {
        currentState = project.state
        applyStateColor()

        projectNameLabel.stringValue = AgentRowView.projectName(from: project.cwd)
        durationLabel.stringValue = "· " + AgentRowView.formatRelativeDuration(from: project.earliestStartedAt, to: now)
        subtitleLabel.stringValue = AgentRowView.subtitleText(for: project)

        // 把 durationLabel 紧贴 projectNameLabel 右侧（避免中间大段空白）。
        projectNameLabel.sizeToFit()
        var pf = projectNameLabel.frame
        pf.size.width = min(pf.size.width, Self.rowWidth - 32 - 100)
        projectNameLabel.frame = pf

        durationLabel.sizeToFit()
        var df = durationLabel.frame
        df.origin.x = pf.maxX + 6
        df.origin.y = Self.rowHeight - 22
        durationLabel.frame = df
    }

    private func applyStateColor() {
        guard let state = currentState else { return }
        let color = StatusBarIconRenderer.color(for: state)
        dot.layer?.backgroundColor = color.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStateColor()
    }
}
