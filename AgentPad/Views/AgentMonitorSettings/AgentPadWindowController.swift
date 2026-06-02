//
//  AgentPadWindowController.swift
//  AgentPad
//
//  Storyboard 加 customClass="AgentPadWindowController"。
//  在 windowDidLoad 时给 window 装 NSToolbar，并把现有 contentViewController（splitView 三栏）
//  作为 "General"，AgentMonitorSettingsViewController 作为 "Agent Monitor"。
//  toolbar 选择切换 window.contentViewController。
//

import AppKit

enum AgentPadSettingsTab: String {
    case general
    case agentMonitor
}

final class AgentPadWindowController: NSWindowController, NSToolbarDelegate {

    private let toolbarIdentifier = "AgentPadWindowToolbar"
    private let generalItemID = NSToolbarItem.Identifier("AgentPadWindowToolbar.general")
    private let agentMonitorItemID = NSToolbarItem.Identifier("AgentPadWindowToolbar.agentMonitor")

    private var generalVC: NSViewController?
    private var agentMonitorVC: AgentMonitorSettingsViewController?

    override func windowDidLoad() {
        super.windowDidLoad()

        // 既有 storyboard segue 已经把 splitView ViewController 装到 window.contentViewController。
        generalVC = window?.contentViewController

        installToolbar()
        select(tab: .general)
    }

    private func installToolbar() {
        let tb = NSToolbar(identifier: toolbarIdentifier)
        tb.delegate = self
        tb.displayMode = .iconAndLabel
        tb.allowsUserCustomization = false
        tb.autosavesConfiguration = false
        if #available(macOS 11.0, *) {
            window?.toolbarStyle = .preference
        }
        window?.toolbar = tb
    }

    /// 公开接口：Popover Footer Settings 按钮调用以直达 Agent Monitor 分页。
    func show(tab: AgentPadSettingsTab) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        select(tab: tab)
    }

    private func select(tab: AgentPadSettingsTab) {
        switch tab {
        case .general:
            if let g = generalVC { window?.contentViewController = g }
            window?.toolbar?.selectedItemIdentifier = generalItemID
        case .agentMonitor:
            if agentMonitorVC == nil { agentMonitorVC = AgentMonitorSettingsViewController() }
            if let am = agentMonitorVC { window?.contentViewController = am }
            window?.toolbar?.selectedItemIdentifier = agentMonitorItemID
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [generalItemID, agentMonitorItemID]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [generalItemID, agentMonitorItemID]
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [generalItemID, agentMonitorItemID]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        item.action = #selector(toolbarItemSelected(_:))
        if itemIdentifier == generalItemID {
            item.label = NSLocalizedString("settings.tab.general", comment: "")
            item.paletteLabel = item.label
            item.image = NSImage(named: NSImage.preferencesGeneralName)
        } else if itemIdentifier == agentMonitorItemID {
            item.label = NSLocalizedString("settings.tab.agentMonitor", comment: "")
            item.paletteLabel = item.label
            item.image = NSImage(named: NSImage.networkName)
        }
        return item
    }

    @objc private func toolbarItemSelected(_ sender: NSToolbarItem) {
        if sender.itemIdentifier == generalItemID { select(tab: .general) }
        else if sender.itemIdentifier == agentMonitorItemID { select(tab: .agentMonitor) }
    }
}
