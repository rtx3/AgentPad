//
//  AccessibilityOnboardingWindowController.swift
//  ControllerKeyMapper
//

import AppKit

final class AccessibilityOnboardingWindowController: NSWindowController, NSWindowDelegate {

    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(labelWithString: "")
    private let dontShowAgainButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let openSettingsButton = NSButton(title: "", target: nil, action: nil)
    private let laterButton = NSButton(title: "", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Accessibility access", comment: "Onboarding window title")
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
        self.buildLayout()
        self.applyLocalizedStrings()
    }

    private func buildLayout() {
        guard let contentView = self.window?.contentView else { return }

        titleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 2)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.preferredMaxLayoutWidth = 432

        dontShowAgainButton.translatesAutoresizingMaskIntoConstraints = false
        dontShowAgainButton.state = .off

        openSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.keyEquivalent = "\r"
        openSettingsButton.target = self
        openSettingsButton.action = #selector(didTapOpenSettings(_:))

        laterButton.translatesAutoresizingMaskIntoConstraints = false
        laterButton.bezelStyle = .rounded
        laterButton.keyEquivalent = "\u{1b}"
        laterButton.target = self
        laterButton.action = #selector(didTapLater(_:))

        contentView.addSubview(titleLabel)
        contentView.addSubview(bodyLabel)
        contentView.addSubview(dontShowAgainButton)
        contentView.addSubview(openSettingsButton)
        contentView.addSubview(laterButton)

        let pad: CGFloat = 24
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: pad),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            bodyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            dontShowAgainButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 16),
            dontShowAgainButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            openSettingsButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -pad),
            openSettingsButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            laterButton.centerYAnchor.constraint(equalTo: openSettingsButton.centerYAnchor),
            laterButton.trailingAnchor.constraint(equalTo: openSettingsButton.leadingAnchor, constant: -12),
        ])
    }

    private func applyLocalizedStrings() {
        titleLabel.stringValue = NSLocalizedString(
            "Accessibility permission required",
            comment: "Onboarding title"
        )
        bodyLabel.stringValue = NSLocalizedString(
            "ControllerKeyMapper needs Accessibility permission to send keyboard and mouse events. Without it, controller mappings will be silently ignored by the system.",
            comment: "Onboarding body"
        )
        dontShowAgainButton.title = NSLocalizedString("Don't show again", comment: "Don't show again checkbox")
        openSettingsButton.title = NSLocalizedString("Open Privacy Settings", comment: "Open settings button")
        laterButton.title = NSLocalizedString("Later", comment: "Later button")
    }

    @objc private func didTapOpenSettings(_ sender: Any?) {
        AccessibilityPermission.requestTrust()
        AccessibilityPermission.openSettings()
        if dontShowAgainButton.state == .on {
            AccessibilityPermission.hasShownOnboarding = true
        }
        self.close()
    }

    @objc private func didTapLater(_ sender: Any?) {
        if dontShowAgainButton.state == .on {
            AccessibilityPermission.hasShownOnboarding = true
        }
        self.close()
    }

    static func presentIfNeeded() -> AccessibilityOnboardingWindowController? {
        if AccessibilityPermission.isTrusted() { return nil }
        if AccessibilityPermission.hasShownOnboarding { return nil }
        let controller = AccessibilityOnboardingWindowController()
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        return controller
    }
}
