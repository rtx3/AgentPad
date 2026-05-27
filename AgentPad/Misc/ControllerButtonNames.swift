//
//  ControllerButtonNames.swift
//  AgentPad
//
//  Created by Claude on 2026/05/26.
//  Copyright © 2026 DarkHorse. All rights reserved.
//

import Foundation

func displayName(forLegacyButton legacyButtonName: String, kind: ControllerKind) -> String {
    guard let button = LegacyButtonNameMap.button(from: legacyButtonName) else {
        return NSLocalizedString(legacyButtonName, comment: "Controller button name")
    }
    return displayName(for: button, kind: kind)
}

func displayName(for button: ControllerButton, kind: ControllerKind) -> String {
    let key: String
    switch button {
    case .faceUp:
        key = faceUpDisplayKey(for: kind)
    case .faceDown:
        key = faceDownDisplayKey(for: kind)
    case .faceLeft:
        key = faceLeftDisplayKey(for: kind)
    case .faceRight:
        key = faceRightDisplayKey(for: kind)
    case .dpadUp:
        key = "Up"
    case .dpadDown:
        key = "Down"
    case .dpadLeft:
        key = "Left"
    case .dpadRight:
        key = "Right"
    case .l1:
        key = shoulder1DisplayKey(for: kind, left: true)
    case .r1:
        key = shoulder1DisplayKey(for: kind, left: false)
    case .l2:
        key = shoulder2DisplayKey(for: kind, left: true)
    case .r2:
        key = shoulder2DisplayKey(for: kind, left: false)
    case .l3:
        key = "LStick Push"
    case .r3:
        key = "RStick Push"
    case .start:
        key = startDisplayKey(for: kind)
    case .select:
        key = selectDisplayKey(for: kind)
    case .home:
        key = "Home"
    case .capture:
        key = "Capture"
    case .leftSL:
        key = "Left SL"
    case .leftSR:
        key = "Left SR"
    case .rightSL:
        key = "Right SL"
    case .rightSR:
        key = "Right SR"
    case .unknown:
        key = "Unknown"
    }
    return NSLocalizedString(key, comment: "Controller button name")
}

func displayName(forStickDirection legacyDirectionName: String) -> String {
    guard let direction = LegacyButtonNameMap.stickDirection(from: legacyDirectionName) else {
        return NSLocalizedString(legacyDirectionName, comment: "Controller stick direction")
    }
    return displayName(for: direction)
}

func displayName(for direction: ControllerStickDirection) -> String {
    let key: String
    switch direction {
    case .up:
        key = "Up"
    case .right:
        key = "Right"
    case .down:
        key = "Down"
    case .left:
        key = "Left"
    case .upRight:
        key = "Up Right"
    case .downRight:
        key = "Down Right"
    case .downLeft:
        key = "Down Left"
    case .upLeft:
        key = "Up Left"
    case .neutral:
        key = "Neutral"
    }
    return NSLocalizedString(key, comment: "Controller stick direction")
}

private func faceUpDisplayKey(for kind: ControllerKind) -> String {
    switch kind {
    case .dualShock4, .dualSense:
        return "Triangle"
    case .xbox, .mfi, .generic:
        return "Xbox Y"
    case .joyConL, .joyConR, .proController, .snesController, .famicomController1, .famicomController2, .unknown:
        return "X"
    }
}

private func faceDownDisplayKey(for kind: ControllerKind) -> String {
    switch kind {
    case .dualShock4, .dualSense:
        return "Cross"
    case .xbox, .mfi, .generic:
        return "Xbox A"
    case .joyConL, .joyConR, .proController, .snesController, .famicomController1, .famicomController2, .unknown:
        return "B"
    }
}

private func faceLeftDisplayKey(for kind: ControllerKind) -> String {
    switch kind {
    case .dualShock4, .dualSense:
        return "Square"
    case .xbox, .mfi, .generic:
        return "Xbox X"
    case .joyConL, .joyConR, .proController, .snesController, .famicomController1, .famicomController2, .unknown:
        return "Y"
    }
}

private func faceRightDisplayKey(for kind: ControllerKind) -> String {
    switch kind {
    case .dualShock4, .dualSense:
        return "Circle"
    case .xbox, .mfi, .generic:
        return "Xbox B"
    case .joyConL, .joyConR, .proController, .snesController, .famicomController1, .famicomController2, .unknown:
        return "A"
    }
}

private func shoulder1DisplayKey(for kind: ControllerKind, left: Bool) -> String {
    switch kind {
    case .dualShock4, .dualSense:
        return left ? "L1" : "R1"
    case .xbox, .mfi, .generic:
        return left ? "LB" : "RB"
    case .joyConL, .joyConR, .proController, .snesController, .famicomController1, .famicomController2, .unknown:
        return left ? "L" : "R"
    }
}

private func shoulder2DisplayKey(for kind: ControllerKind, left: Bool) -> String {
    switch kind {
    case .dualShock4, .dualSense:
        return left ? "L2" : "R2"
    case .xbox, .mfi, .generic:
        return left ? "LT" : "RT"
    case .joyConL, .joyConR, .proController, .snesController, .famicomController1, .famicomController2, .unknown:
        return left ? "ZL" : "ZR"
    }
}

private func startDisplayKey(for kind: ControllerKind) -> String {
    switch kind {
    case .dualShock4, .dualSense:
        return "Options"
    case .xbox, .mfi, .generic:
        return "Menu"
    case .famicomController1, .famicomController2, .snesController:
        return "Start"
    case .joyConL, .joyConR, .proController, .unknown:
        return "Plus"
    }
}

private func selectDisplayKey(for kind: ControllerKind) -> String {
    switch kind {
    case .dualShock4, .dualSense:
        return "Share"
    case .xbox, .mfi, .generic:
        return "View"
    case .famicomController1, .famicomController2, .snesController:
        return "Select"
    case .joyConL, .joyConR, .proController, .unknown:
        return "Minus"
    }
}
