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
    /// sheet 写回完成后回调。
    /// - Parameter keyMap: 本次更新的 KeyMap 引用（用于 delegate 端必要时定位被改的按钮）。
    ///   delegate 需要据此刷新运行时绑定（如重建 GameController.currentConfig 字典），
    ///   仅靠 NSManagedObject 字段引用更新不够——首次新建的 KeyMap 不在字典中。
    func setKeyConfig(controller: KeyConfigViewController, keyMap: KeyMap)
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

    /// Detail 模式 key 行的录入式控件（替代原 ComboBox 选择式）。
    /// 与原 `keyAction` ComboBox 叠在同一 frame；ComboBox 自身 isHidden 隐藏。
    /// 共用 `self.keyCode` 字段做写回，updateKeyMap 的 detail 分支无需改动。
    private var detailCaptureField: KeyCaptureField?

    private var agentContainer: NSView!
    private var agentEditor: AgentMacroEditorView!

    /// System mode 容器与下拉控件。整套 UI 同样在 installSimpleModeUI 末尾构造。
    private var systemContainer: NSView!
    private var systemPopUp: NSPopUpButton!

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
        self.installDetailCaptureField()
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
            NSLocalizedString("Agent", comment: "Key capture agent mode"),
            NSLocalizedString("System", comment: "Key capture system action mode")
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

        // 3.6 System action container
        let systemBox = NSView()
        systemBox.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(systemBox)
        self.systemContainer = systemBox

        let systemHelp = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "Choose a system action. Pressing the controller button will trigger it.",
            comment: "System mode help"))
        systemHelp.alignment = .center
        systemHelp.translatesAutoresizingMaskIntoConstraints = false
        systemBox.addSubview(systemHelp)

        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.translatesAutoresizingMaskIntoConstraints = false
        for action in SystemAction.allCases {
            popUp.addItem(withTitle: action.displayName)
            popUp.lastItem?.representedObject = action.rawValue
        }
        systemBox.addSubview(popUp)
        self.systemPopUp = popUp

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

            // System mode container occupies the same area as simple container.
            // 与 simpleContainer 不同：popUp 没有强 intrinsic height；必须显式给
            // bottomAnchor + heightAnchor，否则在某些 AutoLayout 路径下 popUp.frame.height
            // 解出 0，点击下拉无反应。
            systemBox.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 12),
            systemBox.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20),
            systemBox.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20),
            systemBox.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -55),

            systemHelp.topAnchor.constraint(equalTo: systemBox.topAnchor),
            systemHelp.leadingAnchor.constraint(equalTo: systemBox.leadingAnchor),
            systemHelp.trailingAnchor.constraint(equalTo: systemBox.trailingAnchor),

            popUp.topAnchor.constraint(equalTo: systemHelp.bottomAnchor, constant: 14),
            popUp.centerXAnchor.constraint(equalTo: systemBox.centerXAnchor),
            popUp.widthAnchor.constraint(equalToConstant: 260),
            popUp.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    // MARK: - Detail-mode key capture installation

    /// 用 KeyCaptureField 叠在原 ComboBox 的位置上，把 detail 模式的"选键"改为"按键录入"。
    /// 原 keyAction outlet 不动（保留 IB 连接与 self.setKeyCode 的字符串显示路径），
    /// 仅 isHidden 隐藏视觉；用户切回 simple 模式时，detailedContainerViews 整体隐藏会顺带带走本控件。
    private func installDetailCaptureField() {
        guard let comboBox = self.keyAction else { return }
        guard let parent = comboBox.superview else { return }

        let capture = KeyCaptureField()
        capture.delegate = self
        capture.translatesAutoresizingMaskIntoConstraints = false
        capture.placeholder = NSLocalizedString("Press a key…", comment: "Key capture placeholder")
        parent.addSubview(capture, positioned: .above, relativeTo: comboBox)

        NSLayoutConstraint.activate([
            capture.leadingAnchor.constraint(equalTo: comboBox.leadingAnchor),
            capture.trailingAnchor.constraint(equalTo: comboBox.trailingAnchor),
            capture.topAnchor.constraint(equalTo: comboBox.topAnchor),
            capture.bottomAnchor.constraint(equalTo: comboBox.bottomAnchor),
        ])

        // 用 KeyCaptureField 替代 ComboBox 后，原 ComboBox 不再可见。
        // detailedContainerViews 在 installSimpleModeUI 已采集为"非保留视图"，
        // 它会随 simple/agent 模式整体显隐；这里仅永久遮挡 ComboBox 视觉。
        comboBox.isHidden = true

        // 初始把已有 keyCode 同步进 capture field，避免打开 sheet 后控件显示占位符。
        if self.keyCode >= 0 {
            capture.keyCode = self.keyCode
        }
        self.detailCaptureField = capture
    }

    private func applyInitialMode(for keyMap: KeyMap) {
        let hasModifiers = keyMap.modifiers != 0
        let isMouse = keyMap.mouseButton >= 0
        let savedDefault = AppSettings.defaultKeyCaptureMode

        // Existing agent / system payload locks the dialog into the matching mode.
        let storedAction = keyMap.action ?? "keyboard"
        let mode: KeyCaptureMode
        if storedAction == "agent" {
            mode = .agent
        } else if storedAction == "system" {
            mode = .system
        } else if hasModifiers || isMouse {
            mode = .detailed
        } else {
            mode = savedDefault
        }

        self.agentEditor.steps = AgentMacroCodec.decode(keyMap.agentMacro)

        // 把已存储的 SystemAction 选中到下拉里——仅在 storedAction == "system" 时
        // agentMacro 字段才是 SystemAction.rawValue；其它情况下保持下拉默认选中第一项。
        if storedAction == "system",
           let stored = SystemActionCodec.decode(keyMap.agentMacro),
           let idx = SystemAction.allCases.firstIndex(of: stored) {
            self.systemPopUp.selectItem(at: idx)
        }

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
        case 3: mode = .system
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
        case .system: self.modeSegmented.selectedSegment = 3
        }

        let isSimple = (mode == .simple)
        let isAgent = (mode == .agent)
        let isSystem = (mode == .system)
        self.simpleContainer.isHidden = !isSimple
        self.agentContainer.isHidden = !isAgent
        self.systemContainer.isHidden = !isSystem
        // detailed 容器是除 simple / agent / system 之外的情况。
        self.detailedContainerViews.forEach { $0.isHidden = isSimple || isAgent || isSystem }

        if isSimple {
            // 进入简易模式：把 detailed 模式的修饰键 / 鼠标抹掉，仅保留 keyCode
            self.simpleCaptureField.keyCode = self.keyCode
            DispatchQueue.main.async { [weak self] in
                guard let field = self?.simpleCaptureField else { return }
                self?.view.window?.makeFirstResponder(field)
            }
        } else if mode == .detailed {
            // 进入 detail：同步当前 keyCode 到 detail capture field（与 simple 共用 self.keyCode）。
            self.detailCaptureField?.keyCode = self.keyCode
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
            self.delegate?.setKeyConfig(controller: self, keyMap: keyMap)
            return
        }

        if self.currentMode == .system {
            // 取下拉当前选中项作为 SystemAction。
            let selectedIdx = self.systemPopUp.indexOfSelectedItem
            let actions = SystemAction.allCases
            // 保护：如果下拉未选中或索引越界，回退到第一项（不返回禁用，让用户至少能看到 .moveToSpaceLeft 默认绑定）。
            let action = (0..<actions.count).contains(selectedIdx) ? actions[selectedIdx] : actions[0]
            keyMap.action = "system"
            keyMap.agentMacro = SystemActionCodec.encode(action)
            keyMap.modifiers = 0
            keyMap.keyCode = -1
            keyMap.mouseButton = -1
            keyMap.isEnabled = true
            self.delegate?.setKeyConfig(controller: self, keyMap: keyMap)
            return
        }

        // Non-agent / non-system modes: persist keyboard action and preserve macro payload
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
            self.delegate?.setKeyConfig(controller: self, keyMap: keyMap)
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

        self.delegate?.setKeyConfig(controller: self, keyMap: keyMap)
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
