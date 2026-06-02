//
//  AgentMonitorErrorView.swift
//  AgentPad
//

import AppKit

final class AgentMonitorErrorView: NSView {
    var onRetry: (() -> Void)?

    init() {
        super.init(frame: .zero)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder); setup()
    }
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: NSLocalizedString("agent.monitor.error.title", comment: ""))
        title.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let retry = NSButton(title: NSLocalizedString("agent.monitor.error.retry", comment: ""),
                             target: self, action: #selector(handleRetry(_:)))
        retry.bezelStyle = .rounded
        retry.translatesAutoresizingMaskIntoConstraints = false

        addSubview(title)
        addSubview(retry)
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            title.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            retry.centerXAnchor.constraint(equalTo: centerXAnchor),
            retry.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
        ])
    }

    @objc private func handleRetry(_ sender: Any?) {
        onRetry?()
    }
}
