//
//  ControllerView.swift
//  AgentPad
//
//  Created by magicien on 2019/07/18.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit

class ControllerView: NSView {
    var isSelected: Bool = false
    
    override func draw(_ dirtyRect: NSRect) {
        if self.isSelected {
            NSColor.selectedContentBackgroundColor.setFill()
        } else {
            NSColor.clear.setFill()
        }
        self.bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
}
