//
//  AgentPadWindowController.swift
//  AgentPad
//
//  Storyboard 加 customClass="AgentPadWindowController"。
//  在 windowDidLoad 时给 window 装 NSToolbar。三个 tab：
//    - Agent Monitor (默认): AgentMonitorSettingsViewController
//    - Controllers: storyboard segue 装好的 splitView ViewController
//    - General: storyboard scene "AppSettingsViewController"（已存在）
//

import AppKit

enum AgentPadSettingsTab: String {
    case controller
    case agentMonitor
    case general
}

final class AgentPadWindowController: NSWindowController, NSToolbarDelegate {

    private let toolbarIdentifier = "AgentPadWindowToolbar"
    private let controllerItemID = NSToolbarItem.Identifier("AgentPadWindowToolbar.controller")
    private let agentMonitorItemID = NSToolbarItem.Identifier("AgentPadWindowToolbar.agentMonitor")
    private let generalItemID = NSToolbarItem.Identifier("AgentPadWindowToolbar.general")

    private var controllerVC: NSViewController?
    private var agentMonitorVC: AgentMonitorSettingsViewController?
    private var generalVC: NSViewController?

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
        case .general:
            if generalVC == nil {
                // Reuse the AppSettingsViewController scene that previously
                // got presented as a sheet via didPushOptions:. It still lives
                // in the storyboard under that identifier.
                generalVC = storyboard?.instantiateController(
                    withIdentifier: "AppSettingsViewController"
                ) as? NSViewController
            }
            if let g = generalVC { window?.contentViewController = g }
            window?.toolbar?.selectedItemIdentifier = generalItemID
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [agentMonitorItemID, controllerItemID, generalItemID]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [agentMonitorItemID, controllerItemID, generalItemID]
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [agentMonitorItemID, controllerItemID, generalItemID]
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
        } else if itemIdentifier == generalItemID {
            item.label = NSLocalizedString("settings.tab.general", comment: "")
            item.paletteLabel = item.label
            item.image = NSImage(named: NSImage.preferencesGeneralName)
        }
        return item
    }

    @objc private func toolbarItemSelected(_ sender: NSToolbarItem) {
        if sender.itemIdentifier == controllerItemID { select(tab: .controller) }
        else if sender.itemIdentifier == agentMonitorItemID { select(tab: .agentMonitor) }
        else if sender.itemIdentifier == generalItemID { select(tab: .general) }
    }
}
