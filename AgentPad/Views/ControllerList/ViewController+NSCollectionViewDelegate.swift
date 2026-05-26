//
//  ViewController+NSCollectionViewDelegate.swift
//  AgentPad
//
//  Created by magicien on 2019/07/15.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit
import JoyConSwift

let connected = NSLocalizedString("Connected", comment: "Connected")

func controllerDisplayName(for type: JoyCon.ControllerType) -> String {
    switch type {
    case .JoyConL: return "Joy-Con (L)"
    case .JoyConR: return "Joy-Con (R)"
    case .ProController: return "Pro Controller"
    case .SNESController: return "SNES"
    case .FamicomController1: return "Famicom 1"
    case .FamicomController2: return "Famicom 2"
    case .unknown: return NSLocalizedString("Unknown", comment: "Unknown controller")
    }
}

func controllerDisplayName(for kind: ControllerKind, backendName: String? = nil) -> String {
    switch kind {
    case .joyConL: return "Joy-Con (L)"
    case .joyConR: return "Joy-Con (R)"
    case .proController: return "Pro Controller"
    case .snesController: return "SNES"
    case .famicomController1: return "Famicom 1"
    case .famicomController2: return "Famicom 2"
    case .dualShock4: return "DualShock 4"
    case .dualSense: return "DualSense"
    case .xbox: return "Xbox Controller"
    case .mfi: return "MFi Controller"
    case .generic:
        if let backendName = backendName, !backendName.isEmpty {
            return backendName
        }
        return NSLocalizedString("Generic Controller", comment: "Generic Controller")
    case .unknown:
        return NSLocalizedString("Unknown", comment: "Unknown controller")
    }
}

extension ViewController: NSCollectionViewDelegate, NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        let controllers = self.appDelegate?.controllers ?? []

        return controllers.count
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ControllerViewItem"), for: indexPath)

        guard let controllerItem = item as? ControllerViewItem else { return item }
        let index = indexPath.item
        guard let controllers = self.appDelegate?.controllers else { return item }
        guard controllers.count > index else { return item }
        let controller = controllers[index]

        controllerItem.iconView.image = controller.icon
        controllerItem.controller = controller
        let modelName = controllerDisplayName(for: controller.kind, backendName: controller.backend?.displayName)
        let label = controllerItem.label!
        label.stringValue = modelName
        label.isHidden = false
        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.backgroundColor = .clear
        label.textColor = .secondaryLabelColor
        label.toolTip = modelName
        
        return controllerItem
    }
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let index = indexPaths.first?.item else {
            self.selectedController = nil
            return
        }
        guard let controllers = self.appDelegate?.controllers else {
            self.selectedController = nil
            return
        }
        guard controllers.count > index else {
            self.selectedController = nil
            return
        }
        self.selectedController = controllers[index]
    }
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        self.selectedController = nil
    }
}
