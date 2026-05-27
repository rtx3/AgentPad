//
//  KeyConfigViewController.swift
//  AgentPad
//
//  Created by magicien on 2019/07/29.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit
import InputMethodKit

protocol KeyConfigSetDelegate {
    func setKeyConfig(controller: KeyConfigViewController)
}

class KeyConfigViewController: NSViewController, NSComboBoxDelegate, KeyConfigComboBoxDelegate, KeyCaptureFieldDelegate {
    var delegate: KeyConfigSetDelegate?
    var keyMap: KeyMap?
    var controllerKind: ControllerKind = .unknown
    var keyCode: Int16 = -1

    @IBOutlet weak var titleLabel: NSTextField!

    @IBOutlet weak var shiftKey: NSButton!
    @IBOutlet weak var optionKey: NSButton!
    @IBOutlet weak var controlKey: NSButton!
    @IBOutlet weak var commandKey: NSButton!

    @IBOutlet weak var keyRadioButton: NSButton!
    @IBOutlet weak var mouseRadioButton: NSButton!

    @IBOutlet weak var keyAction: KeyConfigComboBox!
    @IBOutlet weak var mouseAction: NSPopUpButton!

    // MARK: - Simple-mode UI (built programmatically)

    private var modeSegmented: NSSegmentedControl!
    private var simpleContainer: NSView!
    private var simpleHelpLabel: NSTextField!
    private var simpleCaptureField: KeyCaptureField!
    private var detailedContainerViews: [NSView] = []

    private var agentContainer: NSView!
    private var agentEditor: AgentMacroEditorView!

    private var currentMode: KeyCaptureMode = .simple

    override func viewWillAppear() {
        super.viewWillAppear()
        // Detail / agent modes need more vertical space than the storyboard's
        // 234pt sheet provides. Resize on appear so sheet metrics are honored.
        if let window = self.view.window {
            let target = NSSize(width: max(window.frame.width, 460),
                                height: max(window.frame.height, 420))
            if window.frame.size != target {
                var f = window.frame
                f.size = target
                window.setFrame(f, display: true)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let keyMap = self.keyMap else { return }

        let title = NSLocalizedString("%@ Button Key Config", comment: "%@ Button Key Config")
        let buttonName = displayName(forLegacyButton: keyMap.button ?? "", kind: self.controllerKind)
        self.titleLabel.stringValue = String.localizedStringWithFormat(title, buttonName)

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(keyMap.modifiers))
        self.shiftKey.state = modifiers.contains(.shift) ? .on : .off
        self.optionKey.state = modifiers.contains(.option) ? .on : .off
        self.controlKey.state = modifiers.contains(.control) ? .on : .off
        self.commandKey.state = modifiers.contains(.command) ? .on : .off

        if keyMap.keyCode >= 0 {
            self.keyRadioButton.state = .on
            self.keyAction.stringValue = getKeyName(keyCode: UInt16(keyMap.keyCode))
        } else {
            self.mouseRadioButton.state = .on
            self.mouseAction.selectItem(withTag: Int(keyMap.mouseButton))
        }
        self.keyCode = keyMap.keyCode
        self.keyAction.configDelegate = self
        self.keyAction.delegate = self

        self.installSimpleModeUI()
        self.applyInitialMode(for: keyMap)
    }

    // MARK: - Simple-mode UI installation

    private func installSimpleModeUI() {
        // 1. 收集所有详细模式的现有顶层子视图，方便整组显隐。
        //    Storyboard 中的子视图：title label + meta-key box + key/mouse box + 中间 "+" 文本框 + OK + Cancel。
        //    OK / Cancel 在两种模式都需要，因此排除掉。
        let okButton = self.findButton(actionName: "didPushOK:")
        let cancelButton = self.findButton(actionName: "didPushCancel:")
        let keepVisible: Set<NSView> = [self.titleLabel, okButton, cancelButton].compactMap { $0 }.reduce(into: Set<NSView>()) { $0.insert($1) }

        self.detailedContainerViews = self.view.subviews.filter { !keepVisible.contains($0) }

        // 2. 模式切换控件
        let segmented = NSSegmentedControl(labels: [
            NSLocalizedString("Simple", comment: "Key capture simple mode"),
            NSLocalizedString("Detailed", comment: "Key capture detailed mode"),
            NSLocalizedString("Agent", comment: "Key capture agent mode")
        ], trackingMode: .selectOne, target: self, action: #selector(didChangeMode(_:)))
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.selectedSegment = 0
        self.view.addSubview(segmented)
        self.modeSegmented = segmented

        // 3. 简易模式容器
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(container)
        self.simpleContainer = container

        let help = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "Press any key on your keyboard. It will be assigned immediately.",
            comment: "Simple mode help"))
        help.alignment = .center
        help.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(help)
        self.simpleHelpLabel = help

        let capture = KeyCaptureField()
        capture.delegate = self
        capture.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(capture)
        self.simpleCaptureField = capture

        // 3.5 Agent macro container
        let agentBox = NSView()
        agentBox.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(agentBox)
        self.agentContainer = agentBox

        let editor = AgentMacroEditorView(frame: .zero)
        editor.translatesAutoresizingMaskIntoConstraints = false
        agentBox.addSubview(editor)
        self.agentEditor = editor

        // 4. 约束
        //
        // 关键设计：segmented 放在窗口左下角（与 OK/Cancel 同一水平线），而
        // 不是叠在标题下方——storyboard 中 Key/Mouse box 紧贴标题，segmented
        // 放在标题下会盖住 Key/Mouse box 的标签，造成视觉重叠。
        // 简易容器（仅 Simple 模式可见）占据中间主体。
        NSLayoutConstraint.activate([
            // segmented 紧贴右上角，与标题同一水平线，避免与底部 OK/Cancel 重叠。
            segmented.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            segmented.centerYAnchor.constraint(equalTo: self.titleLabel.centerYAnchor),

            // 简易容器（仅 Simple 模式可见）从标题下方一直延伸到按钮上方。
            container.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 12),
            container.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(lessThanOrEqualTo: self.view.bottomAnchor, constant: -55),

            help.topAnchor.constraint(equalTo: container.topAnchor),
            help.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            help.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            capture.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 14),
            capture.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            capture.widthAnchor.constraint(equalToConstant: 220),
            capture.heightAnchor.constraint(equalToConstant: 60),
            capture.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),

            // Agent macro container occupies the same area as simple container.
            agentBox.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 12),
            agentBox.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            agentBox.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            agentBox.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -55),
            agentBox.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),

            editor.topAnchor.constraint(equalTo: agentBox.topAnchor),
            editor.leadingAnchor.constraint(equalTo: agentBox.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: agentBox.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: agentBox.bottomAnchor),
        ])
    }

    private func applyInitialMode(for keyMap: KeyMap) {
        let hasModifiers = keyMap.modifiers != 0
        let isMouse = keyMap.mouseButton >= 0
        let savedDefault = AppSettings.defaultKeyCaptureMode

        // Existing agent payload locks the dialog into agent mode.
        let storedAction = keyMap.action ?? "keyboard"
        let mode: KeyCaptureMode
        if storedAction == "agent" {
            mode = .agent
        } else if hasModifiers || isMouse {
            mode = .detailed
        } else {
            mode = savedDefault
        }

        self.agentEditor.steps = AgentMacroCodec.decode(keyMap.agentMacro)

        self.setMode(mode, persistAsDefault: false)

        if mode == .simple, keyMap.keyCode >= 0 {
            self.simpleCaptureField.keyCode = keyMap.keyCode
        }
    }

    // MARK: - Mode switching

    @objc private func didChangeMode(_ sender: NSSegmentedControl) {
        let mode: KeyCaptureMode
        switch sender.selectedSegment {
        case 0: mode = .simple
        case 1: mode = .detailed
        case 2: mode = .agent
        default: mode = .simple
        }
        self.setMode(mode, persistAsDefault: true)
    }

    private func setMode(_ mode: KeyCaptureMode, persistAsDefault: Bool) {
        self.currentMode = mode
        switch mode {
        case .simple: self.modeSegmented.selectedSegment = 0
        case .detailed: self.modeSegmented.selectedSegment = 1
        case .agent: self.modeSegmented.selectedSegment = 2
        }

        let isSimple = (mode == .simple)
        let isAgent = (mode == .agent)
        self.simpleContainer.isHidden = !isSimple
        self.agentContainer.isHidden = !isAgent
        self.detailedContainerViews.forEach { $0.isHidden = isSimple || isAgent }

        if isSimple {
            // 进入简易模式：把 detailed 模式的修饰键 / 鼠标抹掉，仅保留 keyCode
            self.simpleCaptureField.keyCode = self.keyCode
            DispatchQueue.main.async { [weak self] in
                guard let field = self?.simpleCaptureField else { return }
                self?.view.window?.makeFirstResponder(field)
            }
        }

        if persistAsDefault {
            AppSettings.defaultKeyCaptureMode = mode
        }
    }

    // MARK: - Helpers

    /// 在主 view 的 subviews 中找到指定 selector 的按钮。
    private func findButton(actionName: String) -> NSButton? {
        for sub in self.view.subviews {
            guard let btn = sub as? NSButton else { continue }
            if let sel = btn.action, NSStringFromSelector(sel) == actionName {
                return btn
            }
        }
        return nil
    }

    // MARK: - Key map write-back

    func updateKeyMap() {
        guard let keyMap = self.keyMap else { return }

        if self.currentMode == .agent {
            keyMap.action = "agent"
            keyMap.agentMacro = AgentMacroCodec.encode(self.agentEditor.steps)
            keyMap.modifiers = 0
            keyMap.keyCode = -1
            keyMap.mouseButton = -1
            keyMap.isEnabled = !self.agentEditor.steps.isEmpty
            self.delegate?.setKeyConfig(controller: self)
            return
        }

        // Non-agent modes: persist keyboard action and preserve macro payload
        // so toggling back to agent keeps the previously edited steps.
        keyMap.action = "keyboard"
        keyMap.agentMacro = self.agentEditor.steps.isEmpty
            ? nil
            : AgentMacroCodec.encode(self.agentEditor.steps)

        if self.currentMode == .simple {
            keyMap.modifiers = 0
            keyMap.keyCode = self.simpleCaptureField.keyCode
            keyMap.mouseButton = -1
            keyMap.isEnabled = (keyMap.keyCode >= 0)
            self.delegate?.setKeyConfig(controller: self)
            return
        }

        var flags = NSEvent.ModifierFlags(rawValue: 0)

        if self.shiftKey.state == .on {
            flags.formUnion(.shift)
        } else {
            flags.remove(.shift)
        }

        if self.optionKey.state == .on {
            flags.formUnion(.option)
        } else {
            flags.remove(.option)
        }

        if self.controlKey.state == .on {
            flags.formUnion(.control)
        } else {
            flags.remove(.control)
        }


        if self.commandKey.state == .on {
            flags.formUnion(.command)
        } else {
            flags.remove(.command)
        }

        keyMap.modifiers = Int32(flags.rawValue)

        if self.keyRadioButton.state == .on {
            keyMap.keyCode = self.keyCode
            keyMap.mouseButton = -1
        } else {
            keyMap.keyCode = -1
            keyMap.mouseButton = Int16(self.mouseAction.selectedTag())
        }

        keyMap.isEnabled = true

        self.delegate?.setKeyConfig(controller: self)
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        let index = self.keyAction.indexOfSelectedItem
        if index >= 0 {
            let keyCode = keyCodeList[index]
            self.setKeyCode(UInt16(keyCode))
        }
    }

    func setKeyCode(_ keyCode: UInt16) {
        self.keyCode = Int16(keyCode)
        self.keyAction.stringValue = getKeyName(keyCode: keyCode)
        self.keyRadioButton.state = .on
    }

    // MARK: - KeyCaptureFieldDelegate

    func keyCaptureField(_ field: KeyCaptureField, didCapture keyCode: UInt16) {
        self.keyCode = Int16(keyCode)
        // 同步到详细模式的 ComboBox 显示，便于切回详细模式时保留
        self.keyAction.stringValue = getKeyName(keyCode: keyCode)
        self.keyRadioButton.state = .on
    }

    @IBAction func didPushRadioButton(_ sender: NSButton) {}

    @IBAction func didPushOK(_ sender: NSButton) {
        guard let window = self.view.window else { return }
        self.updateKeyMap()
        window.sheetParent?.endSheet(window, returnCode: .OK)
    }

    @IBAction func didPushCancel(_ sender: NSButton) {
        guard let window = self.view.window else { return }
        window.sheetParent?.endSheet(window, returnCode: .cancel)
    }
}
