//
//  AppCellView.swift
//  AgentPad
//
//  Created by magicien on 2019/07/21.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit

class AppCellView: NSTableCellView {
    @IBOutlet weak var appIcon: NSImageView!
    @IBOutlet weak var appName: NSTextField!

    /// 透传开关。Default 行不显示，其它 AppConfig 行按需显示并绑定回调。
    /// 由 ViewController+NSTableViewDelegate 在 viewForAppTable 中构造。
    /// 用 strong 引用：NSTableCellView 会被重用，weak 会在重用前被释放，
    /// 导致 ensurePassthroughCheckbox 每次都重新 addSubview，堆叠多个按钮。
    var passthroughCheckbox: NSButton?

    /// 透传角标：appIcon 右下角的小手柄图，提示该 App 处于 passthrough 模式。
    /// 与 passthroughCheckbox 同步显隐。同 strong 引用理由：cell 复用。
    var passthroughBadge: NSImageView?

    /// 创建并嵌入 passthrough checkbox（只在首次调用时建）。
    /// 用纯方框（无标题），完整文案放进 toolTip，避免覆盖 appIcon / appName。
    func ensurePassthroughCheckbox() -> NSButton {
        if let existing = self.passthroughCheckbox { return existing }
        let cb = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        cb.translatesAutoresizingMaskIntoConstraints = false
        cb.controlSize = .small
        cb.toolTip = NSLocalizedString("Keep as controller (don't map)", comment: "Passthrough checkbox")
        self.addSubview(cb)
        NSLayoutConstraint.activate([
            cb.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            cb.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        self.passthroughCheckbox = cb
        return cb
    }

    /// 隐藏 checkbox（Default 行用）。
    func hidePassthroughCheckbox() {
        self.passthroughCheckbox?.isHidden = true
        self.passthroughBadge?.isHidden = true
    }

    /// 显示/隐藏右下角小手柄角标，与 AppConfig.passthrough 联动。
    /// SF Symbol 要 macOS 11+；旧系统回退到 menu_icon（项目内已有的手柄轮廓图）。
    func setPassthroughBadgeVisible(_ visible: Bool) {
        if visible {
            let badge = self.ensurePassthroughBadge()
            badge.isHidden = false
        } else {
            self.passthroughBadge?.isHidden = true
        }
    }

    private func ensurePassthroughBadge() -> NSImageView {
        if let existing = self.passthroughBadge { return existing }
        let badge = NSImageView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.imageScaling = .scaleProportionallyUpOrDown
        if #available(macOS 11.0, *) {
            badge.image = NSImage(systemSymbolName: "gamecontroller.fill",
                                  accessibilityDescription: NSLocalizedString("Passthrough", comment: "Passthrough badge"))
            badge.contentTintColor = .controlAccentColor
        } else {
            badge.image = NSImage(named: "menu_icon")
        }
        badge.toolTip = NSLocalizedString("Keep as controller (don't map)", comment: "Passthrough badge tooltip")
        self.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 14),
            badge.heightAnchor.constraint(equalToConstant: 14),
            badge.trailingAnchor.constraint(equalTo: self.appIcon.trailingAnchor, constant: 3),
            badge.bottomAnchor.constraint(equalTo: self.appIcon.bottomAnchor, constant: 3)
        ])
        self.passthroughBadge = badge
        return badge
    }
}

