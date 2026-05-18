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
    weak var passthroughCheckbox: NSButton?

    /// 创建并嵌入 passthrough checkbox（只在首次调用时建）。
    func ensurePassthroughCheckbox() -> NSButton {
        if let existing = self.passthroughCheckbox { return existing }
        let cb = NSButton(checkboxWithTitle: NSLocalizedString("Keep as controller (don't map)", comment: "Passthrough checkbox"),
                          target: nil, action: nil)
        cb.translatesAutoresizingMaskIntoConstraints = false
        cb.font = NSFont.systemFont(ofSize: 10)
        cb.controlSize = .small
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

