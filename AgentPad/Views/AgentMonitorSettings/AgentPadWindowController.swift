//
//  AgentPadWindowController.swift
//  AgentPad
//
//  Storyboard 加 customClass="AgentPadWindowController"。
//  在 windowDidLoad 时给 window 装 NSToolbar，并把现有 contentViewController（splitView 三栏）
//  作为 "Controllers"，AgentMonitorSettingsViewController 作为 "Agent Monitor"。
//  toolbar 选择切换 window.contentViewController。
//

import AppKit

enum AgentPadSettingsTab: String {
    case controller
    case agentMonitor
}

final class AgentPadWindowController: NSWindowController, NSToolbarDelegate {

    private let toolbarIdentifier = "AgentPadWindowToolbar"
    private let controllerItemID = NSToolbarItem.Identifier("AgentPadWindowToolbar.controller")
    private let agentMonitorItemID = NSToolbarItem.Identifier("AgentPadWindowToolbar.agentMonitor")

    private var controllerVC: NSViewController?
    private var agentMonitorVC: AgentMonitorSettingsViewController?

    override func windowDidLoad() {
        super.windowDidLoad()

        // 既有 storyboard segue 已经把 splitView ViewController 装到 window.contentViewController。
        controllerVC = window?.contentViewController

        installToolbar()
        select(tab: .agentMonitor)
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
        case .controller:
            if let g = controllerVC { window?.contentViewController = g }
            window?.toolbar?.selectedItemIdentifier = controllerItemID
        case .agentMonitor:
            if agentMonitorVC == nil { agentMonitorVC = AgentMonitorSettingsViewController() }
            if let am = agentMonitorVC { window?.contentViewController = am }
            window?.toolbar?.selectedItemIdentifier = agentMonitorItemID
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [agentMonitorItemID, controllerItemID]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [agentMonitorItemID, controllerItemID]
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [agentMonitorItemID, controllerItemID]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        item.action = #selector(toolbarItemSelected(_:))
        if itemIdentifier == controllerItemID {
            item.label = NSLocalizedString("settings.tab.controller", comment: "")
            item.paletteLabel = item.label
            // SF Symbol "gamecontroller.fill" available on macOS 11+.
            // Fallback to preferencesGeneralName (gear) for 10.14 / 10.15.
            if #available(macOS 11.0, *) {
                item.image = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)
            } else {
                item.image = NSImage(named: NSImage.preferencesGeneralName)
            }
        } else if itemIdentifier == agentMonitorItemID {
            item.label = NSLocalizedString("settings.tab.agentMonitor", comment: "")
            item.paletteLabel = item.label
            item.image = NSImage(named: NSImage.networkName)
        }
        return item
    }

    @objc private func toolbarItemSelected(_ sender: NSToolbarItem) {
        if sender.itemIdentifier == controllerItemID { select(tab: .controller) }
        else if sender.itemIdentifier == agentMonitorItemID { select(tab: .agentMonitor) }
    }
}
