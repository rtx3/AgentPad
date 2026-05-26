//
//  AppSettingsViewController.swift
//  AgentPad
//
//  Created by magicien on 2020/03/11.
//  Copyright © 2020 DarkHorse. All rights reserved.
//

import AppKit

class AppSettingsViewController: NSViewController {
    @IBOutlet weak var disconnectTime: NSPopUpButton!
    @IBOutlet weak var notifyConnection: NSButton!
    @IBOutlet weak var notifyBatteryLevel: NSButton!
    @IBOutlet weak var notifyBatteryCharge: NSButton!
    @IBOutlet weak var notifyBatteryFull: NSButton!
    @IBOutlet weak var launchOnLogin: NSButton!
    private let accessibilityStatusBadge = NSTextField(labelWithString: "")
    private let accessibilitySettingsButton = NSButton(title: "", target: nil, action: nil)
    private var accessibilityStatusTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.disconnectTime.selectItem(withTag: AppSettings.disconnectTime)
        self.notifyConnection.state = AppSettings.notifyConnection ? .on : .off
        self.notifyBatteryLevel.state = AppSettings.notifyBatteryLevel ? .on : .off
        self.notifyBatteryCharge.state = AppSettings.notifyBatteryCharge ? .on : .off
        self.notifyBatteryFull.state = AppSettings.notifyBatteryFull ? .on : .off
        self.launchOnLogin.state = AppSettings.launchOnLogin ? .on : .off
        self.installAccessibilityStatusRow()
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

    @objc private func didPushAccessibilitySettings(_ sender: NSButton) {
        AccessibilityPermission.requestTrust()
        AccessibilityPermission.openSettings()
        self.refreshAccessibilityStatus()
    }

    private func installAccessibilityStatusRow() {
        let titleLabel = NSTextField(labelWithString: NSLocalizedString("Accessibility access", comment: "Accessibility status title"))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: NSLocalizedString("Required for keyboard / mouse mapping", comment: "Accessibility status subtitle"))
        subtitleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        accessibilityStatusBadge.translatesAutoresizingMaskIntoConstraints = false
        accessibilityStatusBadge.alignment = .right
        accessibilityStatusBadge.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        accessibilitySettingsButton.translatesAutoresizingMaskIntoConstraints = false
        accessibilitySettingsButton.bezelStyle = .rounded
        accessibilitySettingsButton.target = self
        accessibilitySettingsButton.action = #selector(didPushAccessibilitySettings(_:))

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(accessibilityStatusBadge)
        view.addSubview(accessibilitySettingsButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: self.launchOnLogin.bottomAnchor, constant: 10),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessibilityStatusBadge.leadingAnchor, constant: -12),

            accessibilitySettingsButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            accessibilitySettingsButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            accessibilityStatusBadge.trailingAnchor.constraint(equalTo: accessibilitySettingsButton.leadingAnchor, constant: -8),
            accessibilityStatusBadge.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            accessibilityStatusBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
        ])

        let minimumHeight: CGFloat = 312
        if self.view.frame.height < minimumHeight {
            self.view.setFrameSize(NSSize(width: self.view.frame.width, height: minimumHeight))
        }

        self.refreshAccessibilityStatus()
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
