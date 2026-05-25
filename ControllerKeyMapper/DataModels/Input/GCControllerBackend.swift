//
//  GCControllerBackend.swift
//  ControllerKeyMapper
//
//  Adapts an Apple GameController.framework controller (DualShock 4 /
//  DualSense / Xbox / MFi / generic Extended Gamepad) to the
//  ControllerBackend protocol. The framework reports per-button
//  `pressedChangedHandler` callbacks already on the main thread, so we wire
//  them straight through to the abstract handlers. Stick directions are
//  quantised into 8 octants + neutral using a fixed dead-zone (matches the
//  granularity exposed elsewhere by JoyConBackend so business code doesn't
//  branch on backend kind).
//
//  GameController.framework does NOT allow user code to release the
//  exclusive HID seize that the system holds, so `supportsPassthrough` is
//  false. Plan 3 §3.8 covers the degraded passthrough behaviour: we simply
//  stop emitting synthetic keyboard / mouse events; the system keeps
//  delivering controller input to the foreground app via the normal channel.
//

import AppKit
import GameController

@available(macOS 10.15, *)
final class GCControllerBackend: ControllerBackend {

    let gcController: GCController
    let stableID: String

    private let stickDeadZone: CGFloat = 0.25
    private var lastLeftDirection: ControllerStickDirection = .neutral
    private var lastRightDirection: ControllerStickDirection = .neutral
    private var observers: [NSObjectProtocol] = []

    init(gcController: GCController, stableID: String) {
        self.gcController = gcController
        self.stableID = stableID
        self.installForwarders()
    }

    deinit {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Identity

    var identifier: String { "gc::\(stableID)" }

    var displayName: String {
        if let name = gcController.vendorName, !name.isEmpty { return name }
        return gcController.productCategory
    }

    var kind: ControllerKind { GCControllerBackend.kind(from: gcController) }

    // MARK: - Live state

    var battery: BatteryLevel {
        guard #available(macOS 11.0, *) else { return .unknown }
        guard let battery = gcController.battery else { return .unknown }
        if battery.batteryState == .unknown { return .unknown }
        let level = CGFloat(battery.batteryLevel)
        if battery.batteryState == .charging && level >= 0.95 { return .full }
        switch level {
        case ..<0.05: return .empty
        case ..<0.15: return .critical
        case ..<0.30: return .low
        case ..<0.60: return .medium
        default: return .full
        }
    }

    var isCharging: Bool {
        guard #available(macOS 11.0, *) else { return false }
        guard let battery = gcController.battery else { return false }
        return battery.batteryState == .charging || battery.batteryState == .full
    }

    var bodyColor: NSColor? {
        // DualSense lightbar / touchpad query is gated behind macOS 11.3+ and
        // currently has no stable public API for the body colour itself.
        // Returning nil lets the icon layer pick a fallback.
        return nil
    }
    var buttonColor: NSColor? { nil }
    var leftGripColor: NSColor? { nil }
    var rightGripColor: NSColor? { nil }

    // MARK: - Capabilities

    var supportsBattery: Bool {
        if #available(macOS 11.0, *) { return gcController.battery != nil }
        return false
    }
    var supportsRumble: Bool {
        if #available(macOS 11.0, *) { return gcController.haptics != nil }
        return false
    }
    var supportsPlayerLights: Bool { true }
    /// GameController.framework owns HID seize at the system level — user
    /// code cannot release it. Passthrough degrades to "mapping disabled,
    /// system reads natively"; the AppDelegate stops emitting events.
    var supportsPassthrough: Bool { false }

    // MARK: - Handlers

    var buttonPressHandler: ((ControllerButton) -> Void)?
    var buttonReleaseHandler: ((ControllerButton) -> Void)?
    var stickHandler: ((ControllerStick, ControllerStickDirection, ControllerStickDirection) -> Void)?
    var stickPosHandler: ((ControllerStick, CGPoint) -> Void)?
    var batteryChangeHandler: ((BatteryLevel, BatteryLevel) -> Void)?
    var isChargingChangeHandler: ((Bool) -> Void)?

    private func installForwarders() {
        guard let pad = gcController.extendedGamepad else { return }

        let dispatch: (ControllerButton, GCControllerButtonInput) -> Void = { [weak self] semantic, btn in
            btn.pressedChangedHandler = { [weak self] _, _, pressed in
                guard let self = self else { return }
                if pressed {
                    self.buttonPressHandler?(semantic)
                } else {
                    self.buttonReleaseHandler?(semantic)
                }
            }
        }

        // Face buttons. The semantic-to-physical mapping is identical across
        // PS / Xbox / MFi because `extendedGamepad.buttonA/.buttonB/.buttonX/.buttonY`
        // are already named by physical position (A=bottom, B=right, X=left, Y=top).
        dispatch(.faceDown, pad.buttonA)
        dispatch(.faceRight, pad.buttonB)
        dispatch(.faceLeft, pad.buttonX)
        dispatch(.faceUp, pad.buttonY)

        // D-pad — each axis is its own button input.
        dispatch(.dpadUp, pad.dpad.up)
        dispatch(.dpadDown, pad.dpad.down)
        dispatch(.dpadLeft, pad.dpad.left)
        dispatch(.dpadRight, pad.dpad.right)

        // Shoulders & triggers.
        dispatch(.l1, pad.leftShoulder)
        dispatch(.r1, pad.rightShoulder)
        dispatch(.l2, pad.leftTrigger)
        dispatch(.r2, pad.rightTrigger)

        // Stick clicks (L3 / R3) are optional on the protocol but present on
        // all modern PS / Xbox / MFi extended gamepads we target here.
        if let l3 = pad.leftThumbstickButton { dispatch(.l3, l3) }
        if let r3 = pad.rightThumbstickButton { dispatch(.r3, r3) }

        // System buttons.
        dispatch(.start, pad.buttonMenu)
        if let options = pad.buttonOptions { dispatch(.select, options) }
        if #available(macOS 11.0, *), let home = pad.buttonHome { dispatch(.home, home) }

        // Sticks. Cast to GCControllerDirectionPad to access valueChangedHandler.
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.handleStick(.left, x: CGFloat(x), y: CGFloat(y))
        }
        pad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.handleStick(.right, x: CGFloat(x), y: CGFloat(y))
        }
    }

    private func handleStick(_ stick: ControllerStick, x: CGFloat, y: CGFloat) {
        let pos = CGPoint(x: x, y: y)
        stickPosHandler?(stick, pos)

        let newDir = GCControllerBackend.direction(x: x, y: y, deadZone: stickDeadZone)
        switch stick {
        case .left:
            let old = lastLeftDirection
            if newDir != old {
                lastLeftDirection = newDir
                stickHandler?(.left, newDir, old)
            }
        case .right:
            let old = lastRightDirection
            if newDir != old {
                lastRightDirection = newDir
                stickHandler?(.right, newDir, old)
            }
        }
    }

    // MARK: - Lifecycle

    @discardableResult
    func setSeized(_ seized: Bool) -> Bool {
        // GameController.framework does not expose seize control.
        return false
    }

    func disconnect() {
        // No public disconnect API for system-managed controllers; releasing
        // our backend reference is the strongest signal we can send.
    }

    // MARK: - Static helpers

    static func kind(from controller: GCController) -> ControllerKind {
        let category = controller.productCategory.lowercased()
        if category.contains("dualsense") { return .dualSense }
        if category.contains("dualshock") { return .dualShock4 }
        if category.contains("xbox") { return .xbox }
        if category.contains("mfi") { return .mfi }
        return .generic
    }

    /// Quantise a continuous stick reading into the 8 cardinal/diagonal
    /// directions plus neutral. Mirrors the granularity JoyConSwift produces
    /// so the downstream pipeline (stick-to-key mapping) doesn't care which
    /// backend generated the event.
    static func direction(x: CGFloat, y: CGFloat, deadZone: CGFloat) -> ControllerStickDirection {
        if abs(x) < deadZone && abs(y) < deadZone { return .neutral }
        // Angle in radians, 0 = +x (right), pi/2 = +y (up).
        let angle = atan2(y, x)
        let twoPi = CGFloat.pi * 2
        let normalized = (angle + twoPi).truncatingRemainder(dividingBy: twoPi) // [0, 2pi)
        // Octants of 45° each, centred so 0° -> .right.
        let octant = Int(((normalized + .pi / 8) / (.pi / 4)).rounded(.down)) % 8
        switch octant {
        case 0: return .right
        case 1: return .upRight
        case 2: return .up
        case 3: return .upLeft
        case 4: return .left
        case 5: return .downLeft
        case 6: return .down
        case 7: return .downRight
        default: return .neutral
        }
    }

    /// True if the controller appears to be a Nintendo device. GameController.framework
    /// on recent macOS may surface Joy-Cons / Pro Controller as extended gamepads;
    /// we let JoyConBackend own those exclusively to avoid double-discovery.
    static func looksLikeNintendo(_ controller: GCController) -> Bool {
        let category = controller.productCategory.lowercased()
        if category.contains("joy-con") || category.contains("joy con") { return true }
        if category.contains("pro controller") { return true }
        if category.contains("nintendo") { return true }
        if let vendor = controller.vendorName?.lowercased() {
            if vendor.contains("nintendo") { return true }
        }
        return false
    }
}
