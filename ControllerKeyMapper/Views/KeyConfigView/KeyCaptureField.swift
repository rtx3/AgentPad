//
//  KeyCaptureField.swift
//  ControllerKeyMapper
//
//  Created on 2026-05-08.
//

import AppKit
import InputMethodKit

protocol KeyCaptureFieldDelegate: AnyObject {
    func keyCaptureField(_ field: KeyCaptureField, didCapture keyCode: UInt16)
}

/// 单键录入控件。继承 NSView 而非 NSTextField/NSComboBox，
/// 直接拦截 keyDown，避免文本输入路径吞掉普通字母 / 数字键。
class KeyCaptureField: NSView {
    weak var delegate: KeyCaptureFieldDelegate?

    /// 当前已录入的 keyCode（-1 表示未录入）。
    var keyCode: Int16 = -1 {
        didSet { self.updateLabel() }
    }

    /// 占位提示（未录入时显示）。
    var placeholder: String = NSLocalizedString("Press a key…", comment: "Key capture placeholder") {
        didSet { self.updateLabel() }
    }

    private let label: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.alignment = .center
        tf.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.isSelectable = false
        return tf
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.commonInit()
    }

    private func commonInit() {
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.layer?.borderWidth = 1
        self.updateBorderColor(focused: false)
        self.updateBackgroundColor(focused: false)

        self.addSubview(self.label)
        NSLayoutConstraint.activate([
            self.label.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.label.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor, constant: 8),
            self.label.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: -8)
        ])

        self.updateLabel()
    }

    // MARK: - First responder

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            self.updateBorderColor(focused: true)
            self.updateBackgroundColor(focused: true)
            self.needsDisplay = true
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            self.updateBorderColor(focused: false)
            self.updateBackgroundColor(focused: false)
            self.needsDisplay = true
        }
        return ok
    }

    // 让用户点击控件即可获得焦点
    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
    }

    // MARK: - Key handling

    /// 不调用 super，避免事件冒泡到 NSTextInputClient 路径
    override func keyDown(with event: NSEvent) {
        let captured = event.keyCode
        self.keyCode = Int16(captured)
        self.delegate?.keyCaptureField(self, didCapture: captured)
    }

    /// 跟踪上次见到的修饰键状态，用于在 flagsChanged 中区分"按下"与"抬起"。
    /// flagsChanged 不告诉我们方向，只给当前完整 modifierFlags。
    private var lastModifierFlags: NSEvent.ModifierFlags = []

    /// 录制单独的修饰键（⌘ / ⌥ / ⌃ / ⇧ / fn）。当用户在简易模式下只按一个修饰键
    /// 而不组合其它键时，flagsChanged 会被触发；keyDown 不会触发。
    /// 仅在"该修饰键由 0 → 1 翻转"的瞬间录入，避免抬起时再次写入。
    override func flagsChanged(with event: NSEvent) {
        let device = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let added = device.subtracting(self.lastModifierFlags)
        self.lastModifierFlags = device

        // 没有新增的修饰键（说明这是抬起事件），不处理。
        guard !added.isEmpty else { return }

        // event.keyCode 给出本次发生变化的物理键的虚拟键码；直接录入。
        let captured = event.keyCode
        self.keyCode = Int16(captured)
        self.delegate?.keyCaptureField(self, didCapture: captured)
    }

    // MARK: - Visual

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    override func updateLayer() {
        super.updateLayer()
        self.updateBorderColor(focused: self.window?.firstResponder === self)
        self.updateBackgroundColor(focused: self.window?.firstResponder === self)
    }

    private func updateBorderColor(focused: Bool) {
        let color: NSColor = focused ? .controlAccentColor : .separatorColor
        self.layer?.borderColor = color.cgColor
    }

    private func updateBackgroundColor(focused: Bool) {
        let color: NSColor = focused ? NSColor.controlAccentColor.withAlphaComponent(0.08)
                                     : NSColor.textBackgroundColor
        self.layer?.backgroundColor = color.cgColor
    }

    private func updateLabel() {
        if self.keyCode >= 0 {
            self.label.stringValue = getKeyName(keyCode: UInt16(self.keyCode))
            self.label.textColor = .labelColor
        } else {
            self.label.stringValue = self.placeholder
            self.label.textColor = .secondaryLabelColor
        }
    }
}
