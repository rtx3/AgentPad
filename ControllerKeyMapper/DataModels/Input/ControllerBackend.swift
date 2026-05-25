//
//  ControllerBackend.swift
//  ControllerKeyMapper
//
//  Abstraction layer that lets multiple input sources (JoyConSwift, Apple
//  GameController.framework, ...) feed the same business pipeline in
//  GameController.swift. Each concrete backend wraps a single physical
//  controller; `ControllerBackendDiscovery` enumerates and watches the
//  underlying transport (IOHID / GCController notifications).
//
//  Capabilities are queried (not enforced) so business code can degrade
//  gracefully on backends that lack a feature — e.g. GameController.framework
//  cannot release HID seize on macOS, so `supportsPassthrough == false` and
//  passthrough degrades to "mapping disabled, system reads natively".
//

import Foundation
import AppKit

protocol ControllerBackend: AnyObject {
    /// Stable identifier used for persistence keying. Must remain unique and
    /// stable across reconnects of the same physical device.
    /// Encoded as "<backend>::<deviceId>" so legacy JoyCon serialIDs ("X-Y-Z")
    /// remain readable when prefixed with "joycon::".
    var identifier: String { get }

    var displayName: String { get }
    var kind: ControllerKind { get }

    var battery: BatteryLevel { get }
    var isCharging: Bool { get }

    /// Optional cosmetic colors (Joy-Con / DualSense expose these).
    var bodyColor: NSColor? { get }
    var buttonColor: NSColor? { get }
    var leftGripColor: NSColor? { get }
    var rightGripColor: NSColor? { get }

    // Capabilities. False means the corresponding handler will never fire and
    // the UI should hide the feature.
    var supportsBattery: Bool { get }
    var supportsRumble: Bool { get }
    var supportsPlayerLights: Bool { get }
    /// Whether the backend can release exclusive HID seize so another process
    /// can read the controller (Plan 3 passthrough). GameController.framework
    /// backends return false; the app instead simply stops emitting events.
    var supportsPassthrough: Bool { get }

    // Event handlers. Backends invoke these on the main thread.
    var buttonPressHandler: ((ControllerButton) -> Void)? { get set }
    var buttonReleaseHandler: ((ControllerButton) -> Void)? { get set }
    var stickHandler: ((ControllerStick, ControllerStickDirection, ControllerStickDirection) -> Void)? { get set }
    var stickPosHandler: ((ControllerStick, CGPoint) -> Void)? { get set }
    var batteryChangeHandler: ((BatteryLevel, BatteryLevel) -> Void)? { get set }
    var isChargingChangeHandler: ((Bool) -> Void)? { get set }

    /// Backend-side equivalent of JoyConSwift's setSeized(_:). On backends
    /// without seize control this is a no-op and returns false.
    @discardableResult
    func setSeized(_ seized: Bool) -> Bool

    func disconnect()
}

protocol ControllerBackendDiscovery: AnyObject {
    var connectHandler: ((ControllerBackend) -> Void)? { get set }
    var disconnectHandler: ((ControllerBackend) -> Void)? { get set }

    func start()
    func stop()
}
