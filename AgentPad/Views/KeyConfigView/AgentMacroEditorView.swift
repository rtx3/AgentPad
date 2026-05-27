//
//  AgentMacroEditorView.swift
//  AgentPad
//
//  Programmatic editor for an ordered list of AgentMacroStep (<=5).
//  Single column NSTableView; per-row cell view rebuilds its param editor
//  whenever the step type changes.
//

import AppKit
import Carbon

final class AgentMacroEditorView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var isMutatingInternally = false
    var steps: [AgentMacroStep] = [] {
        didSet {
            guard !isMutatingInternally else { return }
            tableView.reloadData()
            refreshToolbar()
        }
    }

    var onChange: (() -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private lazy var addButton = NSButton(title: "+", target: self, action: #selector(didAdd(_:)))
    private lazy var removeButton = NSButton(title: "−", target: self, action: #selector(didRemove(_:)))
    private lazy var upButton = NSButton(title: "↑", target: self, action: #selector(didMoveUp(_:)))
    private lazy var downButton = NSButton(title: "↓", target: self, action: #selector(didMoveDown(_:)))
    private let titleLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = NSLocalizedString("Macro (up to 5 steps)",
            comment: "Agent macro editor title")
        titleLabel.font = .boldSystemFont(ofSize: 12)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        emptyLabel.stringValue = NSLocalizedString("Add a step to get started",
            comment: "Agent macro empty placeholder")
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("step"))
        col.title = ""
        col.minWidth = 280
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 56
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 0, height: 6)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        for b in [addButton, removeButton, upButton, downButton] {
            b.bezelStyle = .rounded
            b.translatesAutoresizingMaskIntoConstraints = false
            addSubview(b)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            addButton.topAnchor.constraint(equalTo: scrollView.topAnchor),
            addButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.heightAnchor.constraint(equalToConstant: 24),

            removeButton.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 4),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 28),
            removeButton.heightAnchor.constraint(equalToConstant: 24),

            upButton.topAnchor.constraint(equalTo: removeButton.bottomAnchor, constant: 4),
            upButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            upButton.widthAnchor.constraint(equalToConstant: 28),
            upButton.heightAnchor.constraint(equalToConstant: 24),

            downButton.topAnchor.constraint(equalTo: upButton.bottomAnchor, constant: 4),
            downButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            downButton.widthAnchor.constraint(equalToConstant: 28),
            downButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        refreshToolbar()
    }

    // MARK: - Toolbar actions

    @objc private func didAdd(_ sender: Any?) {
        guard steps.count < AgentMacroCodec.maxSteps else { return }
        steps.append(.delay(ms: 200))
        notifyChanged()
        tableView.selectRowIndexes(IndexSet(integer: steps.count - 1),
                                   byExtendingSelection: false)
    }

    @objc private func didRemove(_ sender: Any?) {
        let idx = tableView.selectedRow
        guard idx >= 0, idx < steps.count else { return }
        steps.remove(at: idx)
        notifyChanged()
    }

    @objc private func didMoveUp(_ sender: Any?) {
        let idx = tableView.selectedRow
        guard idx > 0, idx < steps.count else { return }
        steps.swapAt(idx, idx - 1)
        notifyChanged()
        tableView.selectRowIndexes(IndexSet(integer: idx - 1),
                                   byExtendingSelection: false)
    }

    @objc private func didMoveDown(_ sender: Any?) {
        let idx = tableView.selectedRow
        guard idx >= 0, idx < steps.count - 1 else { return }
        steps.swapAt(idx, idx + 1)
        notifyChanged()
        tableView.selectRowIndexes(IndexSet(integer: idx + 1),
                                   byExtendingSelection: false)
    }

    private func refreshToolbar() {
        addButton.isEnabled = steps.count < AgentMacroCodec.maxSteps
        let idx = tableView.selectedRow
        let hasSel = idx >= 0 && idx < steps.count
        removeButton.isEnabled = hasSel
        upButton.isEnabled = hasSel && idx > 0
        downButton.isEnabled = hasSel && idx < steps.count - 1
        emptyLabel.isHidden = !steps.isEmpty
    }

    fileprivate func updateStep(at index: Int, _ step: AgentMacroStep) {
        guard index >= 0, index < steps.count else { return }
        isMutatingInternally = true
        steps[index] = step
        isMutatingInternally = false
        // Do NOT reloadData here: that destroys the editing cell view and kills
        // first-responder focus (text view) / popup selection (combobox).
        onChange?()
    }

    fileprivate func replaceStepRebuildingRow(at index: Int, with step: AgentMacroStep) {
        guard index >= 0, index < steps.count else { return }
        isMutatingInternally = true
        steps[index] = step
        isMutatingInternally = false
        tableView.reloadData(forRowIndexes: IndexSet(integer: index),
                             columnIndexes: IndexSet(integer: 0))
        onChange?()
    }

    private func notifyChanged() {
        tableView.reloadData()
        refreshToolbar()
        onChange?()
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { steps.count }

    func tableView(_ tv: NSTableView,
                   viewFor column: NSTableColumn?,
                   row: Int) -> NSView? {
        let cell = AgentMacroRowView(frame: .zero)
        cell.bind(index: row, step: steps[row], host: self)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshToolbar()
    }
}

// MARK: - Row view

private final class AgentMacroRowView: NSTableCellView {
    private let typePopup = NSPopUpButton()
    private var paramHost = NSView()
    private weak var host: AgentMacroEditorView?
    private var index: Int = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layoutChrome()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layoutChrome()
    }

    private func layoutChrome() {
        typePopup.translatesAutoresizingMaskIntoConstraints = false
        typePopup.target = self
        typePopup.action = #selector(didChangeType(_:))
        typePopup.addItem(withTitle: NSLocalizedString("Activate app",
            comment: "Agent macro step: activate app"))
        typePopup.addItem(withTitle: NSLocalizedString("Switch input method",
            comment: "Agent macro step: switch input method"))
        typePopup.addItem(withTitle: NSLocalizedString("Input phrase",
            comment: "Agent macro step: input phrase"))
        typePopup.addItem(withTitle: NSLocalizedString("Delay (ms)",
            comment: "Agent macro step: delay"))
        addSubview(typePopup)

        paramHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(paramHost)

        NSLayoutConstraint.activate([
            typePopup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            typePopup.centerYAnchor.constraint(equalTo: centerYAnchor),
            typePopup.widthAnchor.constraint(equalToConstant: 160),

            paramHost.leadingAnchor.constraint(equalTo: typePopup.trailingAnchor, constant: 8),
            paramHost.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            paramHost.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            paramHost.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    func bind(index: Int, step: AgentMacroStep, host: AgentMacroEditorView) {
        self.host = host
        self.index = index

        let typeIdx: Int
        switch step {
        case .activateApp: typeIdx = 0
        case .switchInputMethod: typeIdx = 1
        case .inputPhrase: typeIdx = 2
        case .delay: typeIdx = 3
        }
        typePopup.selectItem(at: typeIdx)

        installParam(for: step)
    }

    @objc private func didChangeType(_ sender: NSPopUpButton) {
        let newStep: AgentMacroStep
        switch sender.indexOfSelectedItem {
        case 0: newStep = .activateApp(bundleID: "")
        case 1: newStep = .switchInputMethod(sourceID: "")
        case 2: newStep = .inputPhrase(text: "")
        case 3: newStep = .delay(ms: 200)
        default: return
        }
        host?.replaceStepRebuildingRow(at: index, with: newStep)
    }

    // MARK: - Param editors

    private func installParam(for step: AgentMacroStep) {
        paramHost.subviews.forEach { $0.removeFromSuperview() }
        switch step {
        case .activateApp(let bundleID):
            installAppCombobox(bundleID: bundleID)
        case .switchInputMethod(let sourceID):
            installInputSourcePopup(sourceID: sourceID)
        case .inputPhrase(let text):
            installPhraseField(text: text)
        case .delay(let ms):
            installDelayStepper(ms: ms)
        }
    }

    private func installAppCombobox(bundleID: String) {
        let combo = NSComboBox()
        combo.translatesAutoresizingMaskIntoConstraints = false
        combo.usesDataSource = false
        combo.completes = true
        combo.target = self
        combo.action = #selector(didEditBundleID(_:))

        // Collect running regular apps (filter out background daemons/agents).
        // Display localized name; persist bundleID. Maintain bidirectional
        // mapping so selection callback recovers the bundleID and the initial
        // value can show the friendly name when known.
        var nameToBundle: [String: String] = [:]
        var bundleToName: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bid = app.bundleIdentifier,
                  let nm = app.localizedName else { continue }
            nameToBundle[nm] = bid
            bundleToName[bid] = nm
        }

        for name in nameToBundle.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            combo.addItem(withObjectValue: name)
        }

        // Initial display: friendly name if bundleID matches a running app,
        // otherwise raw bundleID (covers macro pointing at not-yet-launched app).
        combo.stringValue = bundleToName[bundleID] ?? bundleID

        paramHost.addSubview(combo)
        NSLayoutConstraint.activate([
            combo.leadingAnchor.constraint(equalTo: paramHost.leadingAnchor),
            combo.trailingAnchor.constraint(equalTo: paramHost.trailingAnchor),
            combo.centerYAnchor.constraint(equalTo: paramHost.centerYAnchor),
        ])
        comboTextDelegateProxy.combo = combo
        comboTextDelegateProxy.nameToBundle = nameToBundle
        comboTextDelegateProxy.onChange = { [weak self] s in
            guard let self = self else { return }
            let bid = nameToBundle[s] ?? s
            self.host?.updateStep(at: self.index, .activateApp(bundleID: bid))
        }
        combo.delegate = comboTextDelegateProxy
    }

    @objc private func didEditBundleID(_ sender: NSComboBox) {
        let s = sender.stringValue
        let bid = comboTextDelegateProxy.nameToBundle[s] ?? s
        host?.updateStep(at: index, .activateApp(bundleID: bid))
    }

    private let comboTextDelegateProxy = ComboBoxDelegateProxy()

    private func installInputSourcePopup(sourceID: String) {
        let popup = NSPopUpButton()
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.target = self
        popup.action = #selector(didPickInputSource(_:))

        let sources = AgentMacroEditorView.enabledInputSources()
        for (id, name) in sources {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.representedObject = id
            popup.menu?.addItem(item)
        }
        if let i = sources.firstIndex(where: { $0.0 == sourceID }) {
            popup.selectItem(at: i)
        }
        paramHost.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: paramHost.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: paramHost.trailingAnchor),
            popup.centerYAnchor.constraint(equalTo: paramHost.centerYAnchor),
        ])
    }

    @objc private func didPickInputSource(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        host?.updateStep(at: index, .switchInputMethod(sourceID: id))
    }

    private func installPhraseField(text: String) {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let tv = NSTextView()
        tv.string = text
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.autoresizingMask = [.width]
        tv.delegate = phraseDelegateProxy
        scroll.documentView = tv

        phraseDelegateProxy.onChange = { [weak self] s in
            guard let self = self else { return }
            let clipped = String(s.prefix(AgentMacroCodec.maxPhraseChars))
            self.host?.updateStep(at: self.index, .inputPhrase(text: clipped))
        }

        paramHost.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: paramHost.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: paramHost.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: paramHost.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: paramHost.bottomAnchor),
        ])
    }

    private let phraseDelegateProxy = TextViewDelegateProxy()

    private func installDelayStepper(ms: Int) {
        let field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.stringValue = String(ms)
        field.alignment = .right
        field.target = self
        field.action = #selector(didEditDelay(_:))

        let stepper = NSStepper()
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.minValue = Double(AgentMacroCodec.minDelayMs)
        stepper.maxValue = Double(AgentMacroCodec.maxDelayMs)
        stepper.increment = 10
        stepper.integerValue = ms
        stepper.target = self
        stepper.action = #selector(didStepDelay(_:))

        delayField = field
        delayStepper = stepper

        paramHost.addSubview(field)
        paramHost.addSubview(stepper)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: paramHost.leadingAnchor),
            field.centerYAnchor.constraint(equalTo: paramHost.centerYAnchor),
            field.widthAnchor.constraint(equalToConstant: 80),

            stepper.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 4),
            stepper.centerYAnchor.constraint(equalTo: paramHost.centerYAnchor),
        ])
    }

    private weak var delayField: NSTextField?
    private weak var delayStepper: NSStepper?

    @objc private func didEditDelay(_ sender: NSTextField) {
        let v = clamp(sender.integerValue)
        sender.integerValue = v
        delayStepper?.integerValue = v
        host?.updateStep(at: index, .delay(ms: v))
    }

    @objc private func didStepDelay(_ sender: NSStepper) {
        let v = clamp(sender.integerValue)
        delayField?.integerValue = v
        host?.updateStep(at: index, .delay(ms: v))
    }

    private func clamp(_ v: Int) -> Int {
        return min(max(v, AgentMacroCodec.minDelayMs), AgentMacroCodec.maxDelayMs)
    }
}

// MARK: - Delegate proxies (kept out of NSTableCellView lifecycle to avoid leaks)

private final class ComboBoxDelegateProxy: NSObject, NSComboBoxDelegate {
    weak var combo: NSComboBox?
    var onChange: ((String) -> Void)?
    var nameToBundle: [String: String] = [:]

    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard let c = combo else { return }
        let value = c.indexOfSelectedItem >= 0
            ? (c.objectValueOfSelectedItem as? String ?? c.stringValue)
            : c.stringValue
        onChange?(value)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let c = combo else { return }
        onChange?(c.stringValue)
    }
}

private final class TextViewDelegateProxy: NSObject, NSTextViewDelegate {
    var onChange: ((String) -> Void)?

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        onChange?(tv.string)
    }
}

// MARK: - Input source enumeration

extension AgentMacroEditorView {
    static func enabledInputSources() -> [(String, String)] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceIsEnabled: kCFBooleanTrue!,
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!,
        ]
        guard let raw = TISCreateInputSourceList(filter as CFDictionary, false)?
                .takeRetainedValue() as? [TISInputSource] else { return [] }

        return raw.compactMap { src -> (String, String)? in
            guard let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            var name = id
            if let namePtr = TISGetInputSourceProperty(src, kTISPropertyLocalizedName) {
                name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
            }
            return (id, name)
        }
    }
}
