//
//  AgentMonitorEmptyView.swift
//  AgentPad
//

import AppKit

final class AgentMonitorEmptyView: NSView {
    init() {
        super.init(frame: .zero)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder); setup()
    }
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: NSLocalizedString("agent.monitor.empty.title", comment: ""))
        title.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: NSLocalizedString("agent.monitor.empty.subtitle", comment: ""))
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 0
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        addSubview(title)
        addSubview(subtitle)
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            title.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            subtitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            subtitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
        ])
    }
}
