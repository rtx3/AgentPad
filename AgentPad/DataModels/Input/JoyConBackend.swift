//
//  JoyConBackend.swift
//  AgentPad
//
//  Adapts a single JoyConSwift.Controller to the ControllerBackend protocol.
//  Lives alongside the legacy code; nothing in the existing pipeline reads
//  this yet (s3 wires it into GameController). Build-only addition.
//

import AppKit
import JoyConSwift

final class JoyConBackend: ControllerBackend {
    let controller: JoyConSwift.Controller

    init(controller: JoyConSwift.Controller) {
        self.controller = controller
        self.installForwarders()
    }

    // MARK: - ControllerBackend identity

    var identifier: String {
        // Namespaced so future GameController.framework identifiers don't clash.
        // Bare serialID is preserved as the suffix for lazy migration lookups.
        return "joycon::\(controller.serialID)"
    }

    var displayName: String { controller.type.rawValue }

    var kind: ControllerKind { JoyConBackend.kind(from: controller.type) }

    // MARK: - Live state

    var battery: BatteryLevel { JoyConBackend.battery(from: controller.battery) }
    var isCharging: Bool { controller.isCharging }

    var bodyColor: NSColor? { NSColor(cgColor: controller.bodyColor) }
    var buttonColor: NSColor? { NSColor(cgColor: controller.buttonColor) }
    var leftGripColor: NSColor? {
        guard let cg = controller.leftGripColor else { return nil }
        return NSColor(cgColor: cg)
    }
    var rightGripColor: NSColor? {
        guard let cg = controller.rightGripColor else { return nil }
        return NSColor(cgColor: cg)
    }

    // MARK: - Capabilities

    var supportsBattery: Bool { true }
    var supportsRumble: Bool { true }
    var supportsPlayerLights: Bool { true }
    /// JoyConSwift 0.2.1 only exposes seize at the JoyConManager (global) level,
    /// so per-device passthrough is NOT available here. The global passthrough
    /// path is owned by `PassthroughCoordinator` + AppDelegate today; flipping
    /// this flag will require the seize patch outlined in Plan 3 §3.4.2.
    var supportsPassthrough: Bool { false }

    // MARK: - Handlers

    var buttonPressHandler: ((ControllerButton) -> Void)?
    var buttonReleaseHandler: ((ControllerButton) -> Void)?
    var stickHandler: ((ControllerStick, ControllerStickDirection, ControllerStickDirection) -> Void)?
    var stickPosHandler: ((ControllerStick, CGPoint) -> Void)?
    var batteryChangeHandler: ((BatteryLevel, BatteryLevel) -> Void)?
    var isChargingChangeHandler: ((Bool) -> Void)?

    private func installForwarders() {
        controller.buttonPressHandler = { [weak self] btn in
            guard let self = self else { return }
            self.buttonPressHandler?(JoyConBackend.button(from: btn))
        }
        controller.buttonReleaseHandler = { [weak self] btn in
            guard let self = self else { return }
            self.buttonReleaseHandler?(JoyConBackend.button(from: btn))
        }
        controller.leftStickHandler = { [weak self] newDir, oldDir in
            guard let self = self else { return }
            let n = JoyConBackend.stickDirection(from: newDir)
            let o = JoyConBackend.stickDirection(from: oldDir)
            self.stickHandler?(.left, n, o)
        }
        controller.rightStickHandler = { [weak self] newDir, oldDir in
            guard let self = self else { return }
            let n = JoyConBackend.stickDirection(from: newDir)
            let o = JoyConBackend.stickDirection(from: oldDir)
            self.stickHandler?(.right, n, o)
        }
        controller.leftStickPosHandler = { [weak self] pos in
            self?.stickPosHandler?(.left, pos)
        }
        controller.rightStickPosHandler = { [weak self] pos in
            self?.stickPosHandler?(.right, pos)
        }
        controller.batteryChangeHandler = { [weak self] new, old in
            guard let self = self else { return }
            let n = JoyConBackend.battery(from: new)
            let o = JoyConBackend.battery(from: old)
            self.batteryChangeHandler?(n, o)
        }
        controller.isChargingChangeHandler = { [weak self] charging in
            self?.isChargingChangeHandler?(charging)
        }
    }

    // MARK: - Lifecycle

    @discardableResult
    func setSeized(_ seized: Bool) -> Bool {
        // Per-device seize toggle not available in JoyConSwift 0.2.1.
        // The global path lives in PassthroughCoordinator; callers that need
        // passthrough should go through there instead.
        return false
    }

    func disconnect() {
        controller.setHCIState(state: .disconnect)
    }

    // MARK: - Static translation tables

    static func kind(from type: JoyCon.ControllerType) -> ControllerKind {
        switch type {
        case .JoyConL: return .joyConL
        case .JoyConR: return .joyConR
        case .ProController: return .proController
        case .SNESController: return .snesController
        case .FamicomController1: return .famicomController1
        case .FamicomController2: return .famicomController2
        case .unknown: return .unknown
        }
    }

    static func battery(from status: JoyCon.BatteryStatus) -> BatteryLevel {
        switch status {
        case .empty: return .empty
        case .critical: return .critical
        case .low: return .low
        case .medium: return .medium
        case .full: return .full
        case .unknown: return .unknown
        }
    }

    static func button(from b: JoyCon.Button) -> ControllerButton {
        switch b {
        // Face buttons (Nintendo physical layout: A right, B bottom, X top, Y left).
        case .A: return .faceRight
        case .B: return .faceDown
        case .X: return .faceUp
        case .Y: return .faceLeft
        // D-pad.
        case .Up: return .dpadUp
        case .Down: return .dpadDown
        case .Left: return .dpadLeft
        case .Right: return .dpadRight
        // Shoulders / triggers.
        case .L: return .l1
        case .ZL: return .l2
        case .R: return .r1
        case .ZR: return .r2
        // Stick clicks.
        case .LStick: return .l3
        case .RStick: return .r3
        // System buttons.
        case .Plus: return .start
        case .Minus: return .select
        case .Home: return .home
        case .Capture: return .capture
        case .Start: return .start      // Famicom physical Start
        case .Select: return .select    // Famicom physical Select
        // Joy-Con specific side buttons.
        case .LeftSL: return .leftSL
        case .LeftSR: return .leftSR
        case .RightSL: return .rightSL
        case .RightSR: return .rightSR
        }
    }

    static func stickDirection(from d: JoyCon.StickDirection) -> ControllerStickDirection {
        switch d {
        case .Up: return .up
        case .UpRight: return .upRight
        case .Right: return .right
        case .DownRight: return .downRight
        case .Down: return .down
        case .DownLeft: return .downLeft
        case .Left: return .left
        case .UpLeft: return .upLeft
        case .Neutral: return .neutral
        }
    }

    /// Reverse map used by the read path in GameController — when a KeyMap is
    /// keyed by ControllerButton we still need to ask the underlying JoyCon
    /// `buttonState` dictionary. Returns nil for buttons that don't exist on
    /// any JoyCon variant (face button aliases collapse to the canonical
    /// Nintendo layout).
    static func joyConButton(from b: ControllerButton) -> JoyCon.Button? {
        switch b {
        case .faceRight: return .A
        case .faceDown: return .B
        case .faceUp: return .X
        case .faceLeft: return .Y
        case .dpadUp: return .Up
        case .dpadDown: return .Down
        case .dpadLeft: return .Left
        case .dpadRight: return .Right
        case .l1: return .L
        case .l2: return .ZL
        case .r1: return .R
        case .r2: return .ZR
        case .l3: return .LStick
        case .r3: return .RStick
        case .start: return .Plus
        case .select: return .Minus
        case .home: return .Home
        case .capture: return .Capture
        case .leftSL: return .LeftSL
        case .leftSR: return .LeftSR
        case .rightSL: return .RightSL
        case .rightSR: return .RightSR
        case .unknown: return nil
        }
    }
}
