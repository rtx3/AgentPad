//
//  AgentMonitorSettingsViewController.swift
//  AgentPad
//
//  设置窗口的「Agent Monitor」分页。
//  字段：patterns 表格（含 sessionRoot 列）/ interval 单选 / 计数 / 登录启动。
//

import AppKit
import Sparkle

final class AgentMonitorSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private var patterns: [String] = []
    private var sessionRoots: [String: String] = [:]

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let intervalSegment = NSSegmentedControl()
    private let showCountCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let showStatusBadgeCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoUpdateCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    private let patternColumnID = NSUserInterfaceItemIdentifier("pattern")
    private let rootColumnID = NSUserInterfaceItemIdentifier("sessionRoot")

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let patternsLabel = NSTextField(labelWithString:
            NSLocalizedString("settings.agentMonitor.patterns.title", comment: ""))
        patternsLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        patternsLabel.translatesAutoresizingMaskIntoConstraints = false

        configureTable()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .lineBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let addBtn = NSButton(title: "+", target: self, action: #selector(addRow(_:)))
        addBtn.bezelStyle = .rounded
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        let removeBtn = NSButton(title: "−", target: self, action: #selector(removeRow(_:)))
        removeBtn.bezelStyle = .rounded
        removeBtn.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString:
            NSLocalizedString("settings.agentMonitor.patterns.hint", comment: ""))
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let intervalLabel = NSTextField(labelWithString:
            NSLocalizedString("settings.agentMonitor.interval", comment: ""))
        intervalLabel.translatesAutoresizingMaskIntoConstraints = false

        let intervals = AppSettings.AgentMonitor.allowedPollIntervalsSec
        intervalSegment.segmentCount = intervals.count
        for (i, sec) in intervals.enumerated() {
            intervalSegment.setLabel("\(sec)s", forSegment: i)
            intervalSegment.setWidth(48, forSegment: i)
        }
        intervalSegment.target = self
        intervalSegment.action = #selector(intervalChanged(_:))
        intervalSegment.translatesAutoresizingMaskIntoConstraints = false

        showCountCheckbox.title = NSLocalizedString("settings.agentMonitor.showCount", comment: "")
        showCountCheckbox.target = self
        showCountCheckbox.action = #selector(showCountChanged(_:))
        showCountCheckbox.translatesAutoresizingMaskIntoConstraints = false

        showStatusBadgeCheckbox.title = NSLocalizedString("settings.agentMonitor.showStatusBadge", comment: "")
        showStatusBadgeCheckbox.target = self
        showStatusBadgeCheckbox.action = #selector(showStatusBadgeChanged(_:))
        showStatusBadgeCheckbox.translatesAutoresizingMaskIntoConstraints = false

        launchAtLoginCheckbox.title = NSLocalizedString("settings.agentMonitor.launchAtLogin", comment: "")
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged(_:))
        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false

        autoUpdateCheckbox.title = NSLocalizedString("settings.agentMonitor.autoUpdate", comment: "")
        autoUpdateCheckbox.target = self
        autoUpdateCheckbox.action = #selector(autoUpdateChanged(_:))
        autoUpdateCheckbox.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(patternsLabel)
        root.addSubview(scrollView)
        root.addSubview(addBtn)
        root.addSubview(removeBtn)
        root.addSubview(hint)
        root.addSubview(intervalLabel)
        root.addSubview(intervalSegment)
        root.addSubview(showCountCheckbox)
        root.addSubview(showStatusBadgeCheckbox)
        root.addSubview(launchAtLoginCheckbox)
        root.addSubview(autoUpdateCheckbox)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 480),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),

            patternsLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            patternsLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: patternsLabel.bottomAnchor, constant: 8),
            scrollView.heightAnchor.constraint(equalToConstant: 180),

            addBtn.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            addBtn.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 4),
            removeBtn.leadingAnchor.constraint(equalTo: addBtn.trailingAnchor, constant: 4),
            removeBtn.centerYAnchor.constraint(equalTo: addBtn.centerYAnchor),

            hint.leadingAnchor.constraint(equalTo: removeBtn.trailingAnchor, constant: 12),
            hint.centerYAnchor.constraint(equalTo: addBtn.centerYAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor),

            intervalLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            intervalLabel.topAnchor.constraint(equalTo: addBtn.bottomAnchor, constant: 24),
            intervalSegment.leadingAnchor.constraint(equalTo: intervalLabel.trailingAnchor, constant: 16),
            intervalSegment.centerYAnchor.constraint(equalTo: intervalLabel.centerYAnchor),

            showCountCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            showCountCheckbox.topAnchor.constraint(equalTo: intervalLabel.bottomAnchor, constant: 16),

            showStatusBadgeCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            showStatusBadgeCheckbox.topAnchor.constraint(equalTo: showCountCheckbox.bottomAnchor, constant: 8),

            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            launchAtLoginCheckbox.topAnchor.constraint(equalTo: showStatusBadgeCheckbox.bottomAnchor, constant: 8),

            autoUpdateCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            autoUpdateCheckbox.topAnchor.constraint(equalTo: launchAtLoginCheckbox.bottomAnchor, constant: 8),
            autoUpdateCheckbox.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadFromSettings()
    }

    private func configureTable() {
        let c1 = NSTableColumn(identifier: patternColumnID)
        c1.title = NSLocalizedString("settings.agentMonitor.patterns.title", comment: "")
        c1.width = 160
        let c2 = NSTableColumn(identifier: rootColumnID)
        c2.title = NSLocalizedString("settings.agentMonitor.sessionRoot.title", comment: "")
        c2.width = 280
        tableView.addTableColumn(c1)
        tableView.addTableColumn(c2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
    }

    // MARK: - Bindings

    private func loadFromSettings() {
        patterns = AppSettings.AgentMonitor.patterns
        sessionRoots = AppSettings.AgentMonitor.sessionRoots
        let intervals = AppSettings.AgentMonitor.allowedPollIntervalsSec
        let current = AppSettings.AgentMonitor.pollIntervalSec
        intervalSegment.selectedSegment = intervals.firstIndex(of: current) ?? 1
        showCountCheckbox.state = AppSettings.AgentMonitor.showCountInMenuBar ? .on : .off
        showStatusBadgeCheckbox.state = AppSettings.AgentMonitor.showStatusBadge ? .on : .off
        launchAtLoginCheckbox.state = AppSettings.launchOnLogin ? .on : .off
        autoUpdateCheckbox.state = (self.sparkleUpdater?.automaticallyChecksForUpdates ?? true) ? .on : .off
        tableView.reloadData()
    }

    @objc private func addRow(_ sender: Any?) {
        var name = "new-pattern"
        var i = 1
        while patterns.contains(name) { i += 1; name = "new-pattern-\(i)" }
        patterns.append(name)
        AppSettings.AgentMonitor.patterns = patterns
        tableView.reloadData()
        AppSettings.AgentMonitor.postSettingsDidChange()
    }

    @objc private func removeRow(_ sender: Any?) {
        let row = tableView.selectedRow
        guard row >= 0, row < patterns.count else { return }
        let removed = patterns.remove(at: row)
        sessionRoots.removeValue(forKey: removed)
        AppSettings.AgentMonitor.patterns = patterns
        AppSettings.AgentMonitor.sessionRoots = sessionRoots
        tableView.reloadData()
        AppSettings.AgentMonitor.postSettingsDidChange()
    }

    @objc private func intervalChanged(_ sender: Any?) {
        let intervals = AppSettings.AgentMonitor.allowedPollIntervalsSec
        let i = intervalSegment.selectedSegment
        guard i >= 0, i < intervals.count else { return }
        AppSettings.AgentMonitor.pollIntervalSec = intervals[i]
        AppSettings.AgentMonitor.postSettingsDidChange()
    }

    @objc private func showCountChanged(_ sender: Any?) {
        AppSettings.AgentMonitor.showCountInMenuBar = (showCountCheckbox.state == .on)
        AppSettings.AgentMonitor.postSettingsDidChange()
    }

    @objc private func showStatusBadgeChanged(_ sender: Any?) {
        AppSettings.AgentMonitor.showStatusBadge = (showStatusBadgeCheckbox.state == .on)
        AppSettings.AgentMonitor.postSettingsDidChange()
    }

    @objc private func launchAtLoginChanged(_ sender: Any?) {
        AppSettings.launchOnLogin = (launchAtLoginCheckbox.state == .on)
    }

    @objc private func autoUpdateChanged(_ sender: Any?) {
        // Sparkle persists this to UserDefaults under SUEnableAutomaticChecks,
        // overriding the Info.plist default.
        self.sparkleUpdater?.automaticallyChecksForUpdates = (autoUpdateCheckbox.state == .on)
    }

    /// Reach into AppDelegate's Sparkle controller. Settings is only opened
    /// after applicationDidFinishLaunching, so the lookup is reliable here.
    private var sparkleUpdater: SPUUpdater? {
        return (NSApp.delegate as? AppDelegate)?.updaterController?.updater
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { patterns.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // 两列分别用独立 reuse identifier，避免列样式串污染。
        let identifier: NSUserInterfaceItemIdentifier =
            (tableColumn?.identifier == patternColumnID)
            ? NSUserInterfaceItemIdentifier("cell.pattern")
            : NSUserInterfaceItemIdentifier("cell.sessionRoot")
        let cell: NSTableCellView
        if let reuse = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reuse
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let tf = NSTextField()
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.isBordered = false
            tf.drawsBackground = false
            tf.target = self
            tf.action = #selector(cellEditingEnded(_:))
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let pattern = patterns[row]
        if tableColumn?.identifier == patternColumnID {
            cell.textField?.stringValue = pattern
            cell.textField?.tag = row * 2     // even = pattern
        } else {
            cell.textField?.stringValue = sessionRoots[pattern] ?? ""
            cell.textField?.tag = row * 2 + 1 // odd = sessionRoot
        }
        cell.textField?.isEditable = true
        return cell
    }

    @objc private func cellEditingEnded(_ sender: Any?) {
        guard let tf = sender as? NSTextField else { return }
        let row = tf.tag / 2
        let isPatternColumn = (tf.tag % 2) == 0
        guard row >= 0, row < patterns.count else { return }

        if isPatternColumn {
            let oldPattern = patterns[row]
            let newPattern = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newPattern.isEmpty, newPattern != oldPattern else {
                tf.stringValue = oldPattern
                return
            }
            if patterns.contains(newPattern) {
                tf.stringValue = oldPattern
                return
            }
            patterns[row] = newPattern
            if let v = sessionRoots.removeValue(forKey: oldPattern) {
                sessionRoots[newPattern] = v
            }
            AppSettings.AgentMonitor.patterns = patterns
            AppSettings.AgentMonitor.sessionRoots = sessionRoots
        } else {
            let pattern = patterns[row]
            let path = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty {
                sessionRoots.removeValue(forKey: pattern)
            } else {
                sessionRoots[pattern] = path
            }
            AppSettings.AgentMonitor.sessionRoots = sessionRoots
        }
        AppSettings.AgentMonitor.postSettingsDidChange()
    }
}
