//
//  GamepadModeToggleView.swift
//  AgentPad
//
//  状态栏菜单顶部的 "Gamepad Mode" 总开关行：NSTextField 标题 + NSSwitch。
//  NSMenuItem.view 用法允许把交互控件放进菜单；NSSwitch 在用户点击时触发
//  AppDelegate.toggleUserPaused，状态由外部通过 `setOn(_:)` 同步。
//

import AppKit

final class GamepadModeToggleView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let toggle = NSSwitch()

    var onToggle: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.commonInit()
    }

    private func commonInit() {
        // 标题与系统菜单条目对齐：左 14pt 缩进、字号沿用系统菜单字号。
        // 右侧 NSSwitch 与菜单右边距留 12pt 透气。
        self.label.font = NSFont.menuFont(ofSize: 0)
        self.label.textColor = .labelColor
        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.label)

        self.toggle.controlSize = .small
        self.toggle.target = self
        self.toggle.action = #selector(switchChanged)
        self.toggle.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.toggle)

        NSLayoutConstraint.activate([
            self.label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 14),
            self.label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.toggle.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -12),
            self.toggle.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    func setTitle(_ text: String) {
        self.label.stringValue = text
    }

    /// 外部驱动开关状态，不会触发 onToggle 回调（避免 setOn → action → setOn 死循环）。
    func setOn(_ on: Bool) {
        self.toggle.state = on ? .on : .off
    }

    @objc private func switchChanged() {
        self.onToggle?(self.toggle.state == .on)
    }
}
