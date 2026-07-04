//
//  ControllerViewItem.swift
//  AgentPad
//
//  Created by Yuki Ohno on 2019/07/15.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit

class ControllerViewItem: NSCollectionViewItem {
    @IBOutlet weak var controllerView: ControllerView!
    @IBOutlet weak var iconView: NSImageView!
    @IBOutlet weak var label: NSTextField!
    
    var controller: GameController?
    
    override var isSelected: Bool {
        didSet {
            self.controllerView.isSelected = self.isSelected
            self.controllerView.needsDisplay = true
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        self.controllerView.isSelected = self.isSelected
        self.controllerView.needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        
        if event.modifierFlags.contains(.control) {
            self.showMenu(event)
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        self.showMenu(event)
    }
    
    func showMenu(_ event: NSEvent) {
        let menu = NSMenu(title: "ControllerMenu")

        // Disconnect menu (JoyCon only — GC-backed controllers are managed by
        // the system; GCControllerBackend.disconnect() is a no-op so exposing
        // it would give the user a menu item that silently does nothing).
        if self.controller?.backend is JoyConBackend {
            let disconnectTitle = NSLocalizedString("Disconnect", comment: "Disconnect")
            let disconnectMenu = NSMenuItem(title: disconnectTitle, action: Selector(("disconnect")), keyEquivalent: "")
            disconnectMenu.target = self
            menu.addItem(disconnectMenu)
        }

        /*
        // Separator
        menu.addItem(NSMenuItem.separator())
        
        // Import menu
        let importTitle = NSLocalizedString("Import key mappings", comment: "Import key mappings")
        let importMenu = NSMenuItem(title: importTitle, action: Selector(("importKeyMappings")), keyEquivalent: "")
        importMenu.target = self
        menu.addItem(importMenu)
        
        // Export menu
        let exportTitle = NSLocalizedString("Export key mappings", comment: "Export key mappings")
        let exportMenu = NSMenuItem(title: exportTitle, action: Selector(("exportKeyMappings")), keyEquivalent: "")
        exportMenu.target = self
        menu.addItem(exportMenu)
        */
        
        // Separator
        menu.addItem(NSMenuItem.separator())

        // Remove menu
        let removeTitle = NSLocalizedString("Remove", comment: "Remove")
        let removeMenu = NSMenuItem(title: removeTitle, action: Selector(("remove")), keyEquivalent: "")
        removeMenu.target = self
        menu.addItem(removeMenu)

        let pos = event.cgEvent?.unflippedLocation ?? CGPoint(x: 0, y: 0)
        menu.popUp(positioning: nil, at: pos, in: nil)
    }
    
    @objc func disconnect() {
        self.controller?.disconnect()
    }
    
    @objc func importKeyMappings() {
        
    }
    
    @objc func exportKeyMappings() {
        
    }
    
    @objc func remove() {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return }
        guard let controller = self.controller else { return }
        
        let alert = NSAlert()
        alert.icon = controller.icon
        alert.messageText = NSLocalizedString("Do you really want to remove the controller?", comment: "Do you really want to remove the controller?")
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Cancel
            return
        }
        
        delegate.removeController(gameController: controller)
    }
}
