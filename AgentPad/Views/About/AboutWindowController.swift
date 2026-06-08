//
//  AboutWindowController.swift
//  AgentPad
//
//  Custom About window. Replaces the standard NSApplication aboutPanel so we
//  can host a "Check for Updates…" button wired to Sparkle's updater.
//
//  Layout (top→bottom, centered): app icon · bundle name · version (short+build)
//  · Check for Updates button · copyright line.
//

import AppKit
import Sparkle

final class AboutWindowController: NSWindowController {

    private weak var updater: SPUStandardUpdaterController?

    init(updater: SPUStandardUpdaterController?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.center()
        window.title = ""
        super.init(window: window)
        self.updater = updater
        installContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; About window is constructed programmatically")
    }

    private func installContent() {
        guard let content = window?.contentView else { return }

        let info = Bundle.main.infoDictionary ?? [:]
        let appName = (info["CFBundleName"] as? String)
            ?? (info["CFBundleDisplayName"] as? String)
            ?? "AgentPad"
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let copyright = info["NSHumanReadableCopyright"] as? String ?? ""

        let iconView = NSImageView()
        iconView.image = NSApplication.shared.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: appName)
        nameLabel.font = NSFont.boldSystemFont(ofSize: 18)
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let versionLabel = NSTextField(labelWithString: "Version \(shortVersion) (\(build))")
        versionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let updateButton = NSButton(
            title: NSLocalizedString("Check for Updates…", comment: "Sparkle button in About window"),
            target: self,
            action: #selector(checkForUpdates(_:))
        )
        updateButton.bezelStyle = .rounded
        updateButton.translatesAutoresizingMaskIntoConstraints = false

        let copyrightLabel = NSTextField(labelWithString: copyright)
        copyrightLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center
        copyrightLabel.lineBreakMode = .byWordWrapping
        copyrightLabel.maximumNumberOfLines = 0
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false

        let githubButton = NSButton(
            title: "github.com/rtx3/AgentPad",
            target: self,
            action: #selector(openGitHub(_:))
        )
        githubButton.bezelStyle = .inline
        githubButton.isBordered = false
        githubButton.contentTintColor = .linkColor
        githubButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        githubButton.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(iconView)
        content.addSubview(nameLabel)
        content.addSubview(versionLabel)
        content.addSubview(updateButton)
        content.addSubview(githubButton)
        content.addSubview(copyrightLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            iconView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 96),
            iconView.heightAnchor.constraint(equalToConstant: 96),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            nameLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            updateButton.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 16),
            updateButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            githubButton.topAnchor.constraint(equalTo: updateButton.bottomAnchor, constant: 12),
            githubButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            copyrightLabel.topAnchor.constraint(greaterThanOrEqualTo: githubButton.bottomAnchor, constant: 12),
            copyrightLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            copyrightLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            copyrightLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        // Sparkle's checkForUpdates(_:) presents its own progress UI; the About
        // window stays open so the user can re-trigger if needed.
        updater?.checkForUpdates(sender)
    }

    @objc private func openGitHub(_ sender: Any?) {
        if let url = URL(string: "https://github.com/rtx3/AgentPad") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Singleton presenter. Reuses the same window across opens so we don't
    /// stack instances if the user spams the menu item.
    private static var shared: AboutWindowController?

    static func present(updater: SPUStandardUpdaterController?) {
        if shared == nil {
            shared = AboutWindowController(updater: updater)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }
}
