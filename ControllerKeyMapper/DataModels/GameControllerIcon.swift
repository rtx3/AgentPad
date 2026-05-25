//
//  GameControllerIcon.swift
//  ControllerKeyMapper
//
//  Created by magicien on 2020/03/07.
//  Copyright © 2020 DarkHorse. All rights reserved.
//

import JoyConSwift

let proconBase = NSImage(named: "procon_base")!
let proconLeftGrip = NSImage(named: "procon_left_grip")!
let proconRightGrip = NSImage(named: "procon_right_grip")!
let proconBody = NSImage(named: "procon_body")!
let proconButton = NSImage(named: "procon_button")!

let joyconLBase = NSImage(named: "joycon_left_base")!
let joyconLBody = NSImage(named: "joycon_left_body")!
let joyconLButton = NSImage(named: "joycon_left_button")!

let joyconRBase = NSImage(named: "joycon_right_base")!
let joyconRBody = NSImage(named: "joycon_right_body")!
let joyconRButton = NSImage(named: "joycon_right_button")!

let famicon_1 = NSImage(named: "famicon_1")!
let famicon_2 = NSImage(named: "famicon_2")!
let snescon = NSImage(named: "snescon")!

let unknownController = NSImage(named: "unknown_controller")!

let batteryFull = NSImage(named: "battery_full")!
let batteryMedium = NSImage(named: "battery_medium")!
let batteryLow = NSImage(named: "battery_low")!
let batteryCritical = NSImage(named: "battery_critical")!
let batteryEmpty = NSImage(named: "battery_empty")!
let batteryCharge = NSImage(named: "battery_charge")!

let stop = NSImage(named: "stop")!

func GameControllerIcon(for controller: GameController) -> NSImage {
    switch(controller.kind) {
    case .proController:
        return createProConIcon(for: controller)
    case .joyConL:
        return createJoyConLIcon(for: controller)
    case .joyConR:
        return createJoyConRIcon(for: controller)
    case .famicomController1:
        return famicon_1
    case .famicomController2:
        return famicon_2
    case .snesController:
        return snescon
    case .dualShock4, .dualSense, .xbox, .mfi, .generic, .unknown:
        // M3 backends don't have body / button colour artwork yet — fall back
        // to the placeholder icon. Battery overlay still draws on top.
        return createGenericIcon(for: controller)
    }
}

private func drawBatteryIcon(for controller: GameController) {
    guard let backend = controller.backend else { return }
    if !backend.supportsBattery { return }
    let iconRect = NSRect(origin: CGPoint.zero, size: batteryFull.size)

    switch(backend.battery) {
    case .full:
        batteryFull.draw(in: iconRect)
    case .medium:
        batteryMedium.draw(in: iconRect)
    case .low:
        batteryLow.draw(in: iconRect)
    case .critical:
        batteryCritical.draw(in: iconRect)
    case .empty:
        batteryEmpty.draw(in: iconRect)
    case .unknown:
        break
    }

    if backend.isCharging {
        batteryCharge.draw(in: iconRect)
    }
}

private func drawStopIcon() {
    let iconRect = NSRect(origin: CGPoint.zero, size: stop.size)
    stop.draw(in: iconRect)
}

private func createProConIcon(for controller: GameController) -> NSImage {
    guard
        let leftGripColor = controller.leftGripColor,
        let rightGripColor = controller.rightGripColor
        else { return unknownController }
    
    guard let icon = proconBase.copy() as? NSImage else { return unknownController }
    let iconRect = NSRect(origin: NSZeroPoint, size: icon.size)

    proconLeftGrip.lockFocus()
    leftGripColor.set()
    iconRect.fill(using: .sourceAtop)
    proconLeftGrip.unlockFocus()
    
    proconRightGrip.lockFocus()
    rightGripColor.set()
    iconRect.fill(using: .sourceAtop)
    proconRightGrip.unlockFocus()

    proconBody.lockFocus()
    controller.bodyColor.set()
    iconRect.fill(using: .sourceAtop)
    proconBody.unlockFocus()
    
    proconButton.lockFocus()
    controller.buttonColor.set()
    iconRect.fill(using: .sourceAtop)
    proconButton.unlockFocus()
    
    icon.lockFocus()
    proconLeftGrip.draw(in: iconRect)
    proconRightGrip.draw(in: iconRect)
    proconBody.draw(in: iconRect)
    proconButton.draw(in: iconRect)
    drawBatteryIcon(for: controller)
    if !controller.isEnabled {
        drawStopIcon()
    }
    icon.unlockFocus()

    return icon
}

private func createJoyConLIcon(for controller: GameController) -> NSImage {
    guard let icon = joyconLBase.copy() as? NSImage else {
        return unknownController
    }
    let iconRect = NSRect(origin: NSZeroPoint, size: icon.size)

    joyconLBody.lockFocus()
    controller.bodyColor.set()
    iconRect.fill(using: .sourceAtop)
    joyconLBody.unlockFocus()
    
    joyconLButton.lockFocus()
    controller.buttonColor.set()
    iconRect.fill(using: .sourceAtop)
    joyconLButton.unlockFocus()
    
    icon.lockFocus()
    joyconLBody.draw(in: iconRect)
    joyconLButton.draw(in: iconRect)
    drawBatteryIcon(for: controller)
    if !controller.isEnabled {
        drawStopIcon()
    }
    icon.unlockFocus()

    return icon
}

private func createJoyConRIcon(for controller: GameController) -> NSImage {
    guard let icon = joyconRBase.copy() as? NSImage else {
        return unknownController
    }
    let iconRect = NSRect(origin: NSZeroPoint, size: icon.size)

    joyconRBody.lockFocus()
    controller.bodyColor.set()
    iconRect.fill(using: .sourceAtop)
    joyconRBody.unlockFocus()

    joyconRButton.lockFocus()
    controller.buttonColor.set()
    iconRect.fill(using: .sourceAtop)
    joyconRButton.unlockFocus()

    icon.lockFocus()
    joyconRBody.draw(in: iconRect)
    joyconRButton.draw(in: iconRect)
    drawBatteryIcon(for: controller)
    if !controller.isEnabled {
        drawStopIcon()
    }
    icon.unlockFocus()

    return icon
}

/// Placeholder for non-Nintendo backends (DualShock4 / DualSense / Xbox /
/// MFi / generic). Vendor-specific artwork is a follow-up; for now we reuse
/// the unknown-controller image plus the standard battery / disabled overlay
/// so the icon still updates on connect / state change.
private func createGenericIcon(for controller: GameController) -> NSImage {
    guard let icon = unknownController.copy() as? NSImage else {
        return unknownController
    }
    icon.lockFocus()
    drawBatteryIcon(for: controller)
    if !controller.isEnabled {
        drawStopIcon()
    }
    icon.unlockFocus()
    return icon
}
