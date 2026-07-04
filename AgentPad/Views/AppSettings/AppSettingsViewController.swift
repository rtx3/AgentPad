//
//  AppSettingsViewController.swift
//  AgentPad
//
//  Created by magicien on 2020/03/11.
//  Copyright © 2020 DarkHorse. All rights reserved.
//

import AppKit
import Sparkle

class AppSettingsViewController: NSViewController {
    @IBOutlet weak var disconnectTime: NSPopUpButton!
    @IBOutlet weak var notifyConnection: NSButton!
    @IBOutlet weak var notifyBatteryLevel: NSButton!
    @IBOutlet weak var notifyBatteryCharge: NSButton!
    @IBOutlet weak var notifyBatteryFull: NSButton!
    @IBOutlet weak var launchOnLogin: NSButton!
    private let languagePopup = NSPopUpButton()
    private let accessibilityStatusBadge = NSTextField(labelWithString: "")
    private let accessibilitySettingsButton = NSButton(title: "", target: nil, action: nil)
    private let accessibilitySubtitleLabel = NSTextField(labelWithString: "")
    private var accessibilityStatusTimer: Timer?

    private let showStatusBadgeCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoUpdateCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.disconnectTime.selectItem(withTag: AppSettings.disconnectTime)
        self.notifyConnection.state = AppSettings.notifyConnection ? .on : .off
        self.notifyBatteryLevel.state = AppSettings.notifyBatteryLevel ? .on : .off
        self.notifyBatteryCharge.state = AppSettings.notifyBatteryCharge ? .on : .off
        self.notifyBatteryFull.state = AppSettings.notifyBatteryFull ? .on : .off
        self.launchOnLogin.state = AppSettings.launchOnLogin ? .on : .off
        // The storyboard's Launch at Login checkbox is hidden — the General
        // tab renders its own checkbox via installMenuBarAndSystemRows().
        // The storyboard outlet is kept so installLanguageRow() can still
        // anchor against its bottomAnchor without touching three .storyboard
        // files.
        self.launchOnLogin.isHidden = true

        self.installLanguageRow()
        self.installAccessibilityStatusRow()
        self.installMenuBarAndSystemRows()

        self.preferredContentSize = NSSize(width: 480, height: 500)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        self.refreshAccessibilityStatus()
        self.startAccessibilityStatusTimer()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        self.stopAccessibilityStatusTimer()
    }

    deinit {
        self.stopAccessibilityStatusTimer()
    }
    
    @IBAction func didChangeDisconnectTime(_ sender: NSPopUpButton) {
        AppSettings.disconnectTime = self.disconnectTime.selectedTag()
    }
    
    @IBAction func didChangeNotifyConnection(_ sender: NSButton) {
        AppSettings.notifyConnection = self.notifyConnection.state == .on
    }
    
    @IBAction func didChangeNotifyBatteryLevel(_ sender: NSButton) {
        AppSettings.notifyBatteryLevel = self.notifyBatteryLevel.state == .on
    }
    
    @IBAction func didChangeNotifyBatteryCharge(_ sender: NSButton) {
        AppSettings.notifyBatteryCharge = self.notifyBatteryCharge.state == .on
    }
    
    @IBAction func didChangeNotifyBatteryFull(_ sender: NSButton) {
        AppSettings.notifyBatteryFull = self.notifyBatteryFull.state == .on
    }
    
    @IBAction func didChangeLaunchOnLogin(_ sender: NSButton) {
        AppSettings.launchOnLogin = self.launchOnLogin.state == .on
    }

    private func installLanguageRow() {
        let titleLabel = NSTextField(labelWithString: NSLocalizedString("Language", comment: "Language setting title"))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        languagePopup.removeAllItems()
        languagePopup.addItem(withTitle: "English")
        languagePopup.addItem(withTitle: "日本語")
        languagePopup.addItem(withTitle: "简体中文")

        let currentLanguage = AppSettings.language
        switch currentLanguage {
        case "en":
            languagePopup.selectItem(at: 0)
        case "ja":
            languagePopup.selectItem(at: 1)
        case "zh-Hans":
            languagePopup.selectItem(at: 2)
        default:
            languagePopup.selectItem(at: 0)
        }

        languagePopup.target = self
        languagePopup.action = #selector(didChangeLanguage(_:))

        view.addSubview(titleLabel)
        view.addSubview(languagePopup)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            // launchOnLogin is hidden in this tab but still participates in
            // layout — its bottomAnchor sits right under the Notification
            // NSBox, which is the correct visual anchor for Language.
            titleLabel.topAnchor.constraint(equalTo: self.launchOnLogin.bottomAnchor, constant: 20),

            languagePopup.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            languagePopup.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            languagePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
    }

    @objc private func didChangeLanguage(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        let languageCode: String

        switch selectedIndex {
        case 0:
            languageCode = "en"
        case 1:
            languageCode = "ja"
        case 2:
            languageCode = "zh-Hans"
        default:
            languageCode = "en"
        }

        if languageCode != AppSettings.language {
            AppSettings.language = languageCode

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Language", comment: "")
            alert.informativeText = NSLocalizedString("Restart required to apply language change", comment: "")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    @objc private func didPushAccessibilitySettings(_ sender: NSButton) {
        AccessibilityPermission.requestTrust()
        AccessibilityPermission.openSettings()
        self.refreshAccessibilityStatus()
    }

    private func installAccessibilityStatusRow() {
        let titleLabel = NSTextField(labelWithString: NSLocalizedString("Accessibility access", comment: "Accessibility status title"))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        accessibilitySubtitleLabel.stringValue = NSLocalizedString("Required for keyboard / mouse mapping", comment: "Accessibility status subtitle")
        accessibilitySubtitleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        accessibilitySubtitleLabel.textColor = .secondaryLabelColor
        accessibilitySubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        accessibilitySubtitleLabel.isBezeled = false
        accessibilitySubtitleLabel.drawsBackground = false
        accessibilitySubtitleLabel.isEditable = false
        accessibilitySubtitleLabel.isSelectable = false

        accessibilityStatusBadge.translatesAutoresizingMaskIntoConstraints = false
        accessibilityStatusBadge.alignment = .right
        accessibilityStatusBadge.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        accessibilitySettingsButton.translatesAutoresizingMaskIntoConstraints = false
        accessibilitySettingsButton.bezelStyle = .rounded
        accessibilitySettingsButton.target = self
        accessibilitySettingsButton.action = #selector(didPushAccessibilitySettings(_:))

        view.addSubview(titleLabel)
        view.addSubview(accessibilitySubtitleLabel)
        view.addSubview(accessibilityStatusBadge)
        view.addSubview(accessibilitySettingsButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: self.languagePopup.bottomAnchor, constant: 20),

            accessibilitySubtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            accessibilitySubtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            accessibilitySubtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessibilityStatusBadge.leadingAnchor, constant: -12),

            accessibilitySettingsButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            accessibilitySettingsButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            accessibilityStatusBadge.trailingAnchor.constraint(equalTo: accessibilitySettingsButton.leadingAnchor, constant: -8),
            accessibilityStatusBadge.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            accessibilityStatusBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
        ])

        self.refreshAccessibilityStatus()
    }

    /// Hosts the three settings that previously lived under the Agent Monitor
    /// tab: menu-bar status badge and system integration (Launch at Login /
    /// auto-update). Anchored beneath the Accessibility subtitle so it slots
    /// below the existing General rows.
    private func installMenuBarAndSystemRows() {
        showStatusBadgeCheckbox.title = NSLocalizedString("settings.agentMonitor.showStatusBadge", comment: "")
        showStatusBadgeCheckbox.target = self
        showStatusBadgeCheckbox.action = #selector(didChangeShowStatusBadge(_:))
        showStatusBadgeCheckbox.translatesAutoresizingMaskIntoConstraints = false
        showStatusBadgeCheckbox.state = AppSettings.AgentMonitor.showStatusBadge ? .on : .off

        launchAtLoginCheckbox.title = NSLocalizedString("settings.agentMonitor.launchAtLogin", comment: "")
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(didChangeLaunchAtLoginCheckbox(_:))
        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        launchAtLoginCheckbox.state = AppSettings.launchOnLogin ? .on : .off

        autoUpdateCheckbox.title = NSLocalizedString("settings.agentMonitor.autoUpdate", comment: "")
        autoUpdateCheckbox.target = self
        autoUpdateCheckbox.action = #selector(didChangeAutoUpdate(_:))
        autoUpdateCheckbox.translatesAutoresizingMaskIntoConstraints = false
        autoUpdateCheckbox.state = (self.sparkleUpdater?.automaticallyChecksForUpdates ?? true) ? .on : .off

        view.addSubview(showStatusBadgeCheckbox)
        view.addSubview(launchAtLoginCheckbox)
        view.addSubview(autoUpdateCheckbox)

        NSLayoutConstraint.activate([
            showStatusBadgeCheckbox.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            showStatusBadgeCheckbox.topAnchor.constraint(equalTo: accessibilitySubtitleLabel.bottomAnchor, constant: 20),

            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            launchAtLoginCheckbox.topAnchor.constraint(equalTo: showStatusBadgeCheckbox.bottomAnchor, constant: 8),

            autoUpdateCheckbox.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            autoUpdateCheckbox.topAnchor.constraint(equalTo: launchAtLoginCheckbox.bottomAnchor, constant: 8),
        ])
    }

    @objc private func didChangeShowStatusBadge(_ sender: NSButton) {
        AppSettings.AgentMonitor.showStatusBadge = (sender.state == .on)
        AppSettings.AgentMonitor.postSettingsDidChange()
    }

    @objc private func didChangeLaunchAtLoginCheckbox(_ sender: NSButton) {
        AppSettings.launchOnLogin = (sender.state == .on)
    }

    @objc private func didChangeAutoUpdate(_ sender: NSButton) {
        // Sparkle persists this to UserDefaults under SUEnableAutomaticChecks,
        // overriding the Info.plist default.
        self.sparkleUpdater?.automaticallyChecksForUpdates = (sender.state == .on)
    }

    /// Reach into AppDelegate's Sparkle controller, same path the Agent
    /// Monitor tab previously used.
    private var sparkleUpdater: SPUUpdater? {
        return (NSApp.delegate as? AppDelegate)?.updaterController?.updater
    }

    private func refreshAccessibilityStatus() {
        let trusted = AccessibilityPermission.isTrusted()
        if trusted {
            self.accessibilityStatusBadge.stringValue = NSLocalizedString("Granted", comment: "Accessibility granted status")
            self.accessibilityStatusBadge.textColor = .systemGreen
            self.accessibilitySettingsButton.title = NSLocalizedString("Granted", comment: "Accessibility granted button")
            self.accessibilitySettingsButton.isEnabled = false
        } else {
            self.accessibilityStatusBadge.stringValue = NSLocalizedString("Not granted", comment: "Accessibility missing status")
            self.accessibilityStatusBadge.textColor = .systemRed
            self.accessibilitySettingsButton.title = NSLocalizedString("Open Privacy Settings…", comment: "Open privacy settings button")
            self.accessibilitySettingsButton.isEnabled = true
        }
    }

    private func startAccessibilityStatusTimer() {
        self.stopAccessibilityStatusTimer()
        self.accessibilityStatusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshAccessibilityStatus()
        }
    }

    private func stopAccessibilityStatusTimer() {
        self.accessibilityStatusTimer?.invalidate()
        self.accessibilityStatusTimer = nil
    }

    @IBAction func didPushOK(_ sender: NSButton) {
        guard let window = self.view.window else { return }
        window.sheetParent?.endSheet(window, returnCode: .OK)
    }
}
