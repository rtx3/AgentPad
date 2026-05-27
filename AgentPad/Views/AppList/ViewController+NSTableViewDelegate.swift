//
//  ViewController+NSTableViewDelegate.swift
//  AgentPad
//
//  Created by magicien on 2019/07/21.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit
import JoyConSwift

let appNameColumnID = "appName"

extension ViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === self.appTableView {
            return self.numRowsOfAppTableView()
        }
        
        return 0
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === self.appTableView {
            return self.viewForAppTable(column: tableColumn, row: row)
        }

        return nil
    }

    // MARK: - AppTableView
    
    func convertAppName(_ name: String?) -> String {
        guard var appName = name else { return "" }
        
        if appName.hasSuffix(".app") {
            appName.removeLast(4)
        }
        appName = appName.replacingOccurrences(of: "%20", with: " ")
        
        return appName
    }
    
    func numRowsOfAppTableView() -> Int {
        guard let controller = self.selectedController else { return 0 }
        
        let numApps = controller.data.appConfigs?.count ?? 0
        
        return numApps + 1
    }
    
    func viewForAppTable(column: NSTableColumn?, row: Int) -> NSView? {
        guard let controller = self.selectedController else { return nil }
        guard let col = column else { return nil }
        guard let newView = self.appTableView.makeView(withIdentifier: col.identifier, owner: self) as? AppCellView else { return nil }

        if row == 0 {
            newView.appIcon.image = NSImage(named: "GenericApplicationIcon")
            newView.appName.stringValue = "Default"
            newView.hidePassthroughCheckbox()
        } else {
            guard let appConfig = controller.data.appConfigs?[row - 1] as? AppConfig else { return nil }
            guard let appData = appConfig.app else { return nil }

            if let icon = appData.icon {
                newView.appIcon.image = NSImage(data: icon)
            } else {
                newView.appIcon.image = NSImage(named: "GenericApplicationIcon")
            }

            newView.appName.stringValue = self.convertAppName(appData.displayName)

            let cb = newView.ensurePassthroughCheckbox()
            cb.isHidden = false
            cb.state = appConfig.passthrough ? .on : .off
            cb.target = self
            cb.action = #selector(togglePassthrough(_:))
            cb.tag = row
            newView.setPassthroughBadgeVisible(appConfig.passthrough)
        }

        return newView
    }

    @objc func togglePassthrough(_ sender: NSButton) {
        guard let controller = self.selectedController else { return }
        let row = sender.tag
        guard row >= 1 else { return }
        guard let appConfig = controller.data.appConfigs?[row - 1] as? AppConfig else { return }
        appConfig.passthrough = (sender.state == .on)
        _ = self.appDelegate?.dataManager?.save()
        // 立即重画 KeyMapList + overlay，让用户感知"该 App 透传不再有映射意义"。
        self.configTableView.reloadData()
        self.updatePassthroughOverlay()
        // 切换勾选状态也要让角标重画。
        self.appTableView.reloadData(forRowIndexes: IndexSet(integer: sender.tag),
                                     columnIndexes: IndexSet(integer: 0))
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        self.updateAppAddRemoveButtonState()
        self.updateSyncButtonState()
        self.configTableView.reloadData()
        self.updatePassthroughOverlay()
    }
}
