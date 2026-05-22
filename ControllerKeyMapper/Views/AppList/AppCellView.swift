//
//  AppCellView.swift
//  ControllerKeyMapper
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
    }
}

