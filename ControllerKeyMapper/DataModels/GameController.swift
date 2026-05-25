//
//  GameController.swift
//  ControllerKeyMapper
//
//  Created by magicien on 2019/07/14.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import JoyConSwift
import InputMethodKit

extension JoyCon.BatteryStatus {
    static let stringMap: [JoyCon.BatteryStatus: String] = [
        .empty: "Empty",
        .critical: "Critical",
        .low: "Low",
        .medium: "Medium",
        .full: "Full",
        .unknown: "Unknown"
    ]

    var string: String {
        return JoyCon.BatteryStatus.stringMap[self] ?? "Unknown"
    }

    var localizedString: String {
        return NSLocalizedString(self.string, comment: "BatteryStatus localized string")
    }
}

extension BatteryLevel {
    static let stringMap: [BatteryLevel: String] = [
        .empty: "Empty",
        .critical: "Critical",
        .low: "Low",
        .medium: "Medium",
        .full: "Full",
        .unknown: "Unknown"
    ]

    var string: String {
        return BatteryLevel.stringMap[self] ?? "Unknown"
    }

    var localizedString: String {
        return NSLocalizedString(self.string, comment: "BatteryStatus localized string")
    }
}

class GameController {
    let data: ControllerData

    var type: JoyCon.ControllerType
    /// Backend-agnostic hardware family. Defaults to a value derived from
    /// `data.type` so existing JoyCon rows keep rendering correctly; the
    /// active backend overrides this when it connects.
    var kind: ControllerKind
    var bodyColor: NSColor
    var buttonColor: NSColor
    var leftGripColor: NSColor?
    var rightGripColor: NSColor?
    
    var backend: ControllerBackend? {
        didSet {
            self.setBackendHandlers()
        }
    }

    /// Legacy access: returns the wrapped JoyConSwift.Controller when the
    /// active backend is a JoyConBackend. Existing UI code (menu, collection
    /// view items) still reads JoyCon-specific properties via this path;
    /// non-JoyCon backends introduced in M3 will simply yield nil.
    var controller: JoyConSwift.Controller? {
        return (self.backend as? JoyConBackend)?.controller
    }

    var currentConfigData: KeyConfig {
        didSet { self.updateKeyMap() }
    }
    var currentConfig: [ControllerButton:KeyMap] = [:]
    var currentLStickMode: StickType = .None
    var currentLStickConfig: [ControllerStickDirection:KeyMap] = [:]
    var currentRStickMode: StickType = .None
    var currentRStickConfig: [ControllerStickDirection:KeyMap] = [:]

    var isEnabled: Bool = true {
        didSet {
            self.updateControllerIcon()
        }
    }
    var isLeftDragging: Bool = false
    var isRightDragging: Bool = false
    var isCenterDragging: Bool = false
    
    var lastAccess: Date? = nil
    var timer: Timer? = nil
    var icon: NSImage? {
        if self._icon == nil {
            self.updateControllerIcon()
        }

        return self._icon
    }
    private var _icon: NSImage?
    
    var localizedBatteryString: String {
        return (self.backend?.battery ?? .unknown).localizedString
    }

    init(data: ControllerData) {
        self.data = data
        
        guard let defaultConfig = self.data.defaultConfig else {
            fatalError("Failed to get defaultConfig")
        }
        self.currentConfigData = defaultConfig

        let storedType = data.type ?? ""
        let type = JoyCon.ControllerType(rawValue: storedType)
        self.type = type ?? JoyCon.ControllerType(rawValue: "unknown")!
        // Try ControllerKind raw value first (new GC backends), then fall back
        // to a JoyCon-derived kind. Empty / unknown rows land on .unknown.
        if let k = ControllerKind(rawValue: storedType) {
            self.kind = k
        } else if let jc = type {
            self.kind = JoyConBackend.kind(from: jc)
        } else {
            self.kind = .unknown
        }

        let defaultColor = NSColor(red: 55.0 / 255, green: 55.0 / 255, blue: 55.0 / 255, alpha: 1.0)

        self.bodyColor = defaultColor
        if let bodyColorData = data.bodyColor {
            if let bodyColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: bodyColorData) {
                self.bodyColor = bodyColor
            }
        }
        
        self.buttonColor = defaultColor
        if let buttonColorData = data.buttonColor {
            if let buttonColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: buttonColorData) {
                self.buttonColor = buttonColor
            }
        }

        self.leftGripColor = nil
        if let leftGripColorData = data.leftGripColor {
            if let leftGripColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: leftGripColorData) {
                self.leftGripColor = leftGripColor
            }
        }
        
        self.rightGripColor = nil
        if let rightGripColorData = data.rightGripColor {
            if let rightGripColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: rightGripColorData) {
                self.rightGripColor = rightGripColor
            }
        }
    }
    
    // MARK: - Controller event handlers

    func setBackendHandlers() {
        guard let backend = self.backend else { return }
        // Keep the backend-agnostic kind in sync with the active hardware.
        self.kind = backend.kind
        // Bridge to the legacy JoyCon.ControllerType used by the KeyMapList /
        // KeyConfig storyboard tables. PS / Xbox / MFi / generic extended
        // gamepads share the Pro Controller button layout (ABXY + d-pad +
        // L/R + ZL/ZR + sticks + Plus/Minus + Home), so the existing
        // controllerButtons[.ProController] entry covers them correctly.
        switch backend.kind {
        case .dualShock4, .dualSense, .xbox, .mfi, .generic:
            self.type = .ProController
        case .joyConL, .joyConR, .proController, .snesController,
             .famicomController1, .famicomController2, .unknown:
            // Joy-Con family stays on the JoyCon-derived type which the
            // JoyConBackend overwrites below using the real device type.
            break
        }

        // JoyCon-specific setup (lights / IMU / input mode). Non-JoyCon
        // backends (M3) won't expose this surface and skip silently.
        if let joyCon = (backend as? JoyConBackend)?.controller {
            joyCon.setPlayerLights(l1: .on, l2: .off, l3: .off, l4: .off)
            joyCon.enableIMU(enable: true)
            joyCon.setInputMode(mode: .standardFull)
        }

        backend.buttonPressHandler = { [weak self] button in
            self?.buttonPressHandler(button: button)
        }
        backend.buttonReleaseHandler = { [weak self] button in
            if !(self?.isEnabled ?? false) { return }
            self?.buttonReleaseHandler(button: button)
        }
        backend.stickHandler = { [weak self] (stick, newDir, oldDir) in
            if !(self?.isEnabled ?? false) { return }
            switch stick {
            case .left:
                self?.leftStickHandler(newDirection: newDir, oldDirection: oldDir)
            case .right:
                self?.rightStickHandler(newDirection: newDir, oldDirection: oldDir)
            }
        }
        backend.stickPosHandler = { [weak self] (stick, pos) in
            if !(self?.isEnabled ?? false) { return }
            switch stick {
            case .left:
                self?.leftStickPosHandler(pos: pos)
            case .right:
                self?.rightStickPosHandler(pos: pos)
            }
        }

        backend.batteryChangeHandler = { [weak self] newState, oldState in
            self?.batteryChangeHandler(newState: newState, oldState: oldState)
        }
        backend.isChargingChangeHandler = { [weak self] isCharging in
            self?.isChargingChangeHandler(isCharging: isCharging)
        }

        // Persist controller metadata sourced from the backend.
        // Type / color writes keep the legacy JoyCon string format so existing
        // Core Data rows and `JoyCon.ControllerType(rawValue:)` reads continue
        // to function until the persistence migration in s4.
        if let joyCon = (backend as? JoyConBackend)?.controller {
            self.data.type = joyCon.type.rawValue
            self.type = joyCon.type

            let bodyColor = NSColor(cgColor: joyCon.bodyColor)!
            self.data.bodyColor = try! NSKeyedArchiver.archivedData(withRootObject: bodyColor, requiringSecureCoding: false)
            self.bodyColor = bodyColor

            let buttonColor = NSColor(cgColor: joyCon.buttonColor)!
            self.data.buttonColor = try! NSKeyedArchiver.archivedData(withRootObject: buttonColor, requiringSecureCoding: false)
            self.buttonColor = buttonColor

            self.data.leftGripColor = nil
            if let leftGripColor = joyCon.leftGripColor {
                if let nsLeftGripColor = NSColor(cgColor: leftGripColor) {
                    self.data.leftGripColor = try? NSKeyedArchiver.archivedData(withRootObject: nsLeftGripColor, requiringSecureCoding: false)
                    self.leftGripColor = nsLeftGripColor
                }
            }

            self.data.rightGripColor = nil
            if let rightGripColor = joyCon.rightGripColor {
                if let nsRightGripColor = NSColor(cgColor: rightGripColor) {
                    self.data.rightGripColor = try? NSKeyedArchiver.archivedData(withRootObject: nsRightGripColor, requiringSecureCoding: false)
                    self.rightGripColor = nsRightGripColor
                }
            }
        }

        self.updateControllerIcon()
    }

    func buttonPressHandler(button: ControllerButton) {
        guard let config = self.currentConfig[button] else { return }
        self.buttonPressHandler(config: config)
    }
    
    func buttonPressHandler(config: KeyMap) {
        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .hidSystemState)

            if config.keyCode >= 0 {
                metaKeyEvent(config: config, keyDown: true)

                if let systemKey = systemDefinedKey[Int(config.keyCode)] {
                    let mousePos = NSEvent.mouseLocation
                    let flags = NSEvent.ModifierFlags(rawValue: 0x0a00)
                    let data1 = Int((systemKey << 16) | 0x0a00)

                    let ev = NSEvent.otherEvent(
                        with: .systemDefined,
                        location: mousePos,
                        modifierFlags: flags,
                        timestamp: ProcessInfo().systemUptime,
                        windowNumber: 0,
                        context: nil,
                        subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                        data1: data1,
                        data2: -1)
                    ev?.cgEvent?.post(tap: .cghidEventTap)
                } else {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(config.keyCode), keyDown: true)
                    // 叠加：当前所有按住的 KeyMap 贡献的 modifier ∪ 本次 config 自带 modifier。
                    // 关键修复：之前直接 `event.flags = config.modifiers` 会抹掉系统当前真实
                    // modifier 状态——例如 A 映射为 ⌘ 单键、B 映射为 1 单键时，按住 A 再按 B，
                    // B 的事件不带 Cmd flag 会让系统看到"光秃秃的 1"而不是 Cmd+1。
                    let baseFlags = currentSyntheticEventFlags()
                    let ownFlags = CGEventFlags(rawValue: CGEventFlags.RawValue(config.modifiers))
                    event?.flags = CGEventFlags(rawValue: baseFlags.rawValue | ownFlags.rawValue)
                    event?.post(tap: .cghidEventTap)
                }
            }

            if config.mouseButton >= 0 {
                let mousePos = NSEvent.mouseLocation
                let cursorPos = CGPoint(x: mousePos.x, y: NSScreen.main!.frame.maxY - mousePos.y)

                metaKeyEvent(config: config, keyDown: true)

                var event: CGEvent?
                if config.mouseButton == 0 {
                    event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: cursorPos, mouseButton: .left)
                    self.isLeftDragging = true
                } else if config.mouseButton == 1 {
                    event = CGEvent(mouseEventSource: source, mouseType: .rightMouseDown, mouseCursorPosition: cursorPos, mouseButton: .right)
                    self.isRightDragging = true
                } else if config.mouseButton == 2 {
                    event = CGEvent(mouseEventSource: source, mouseType: .otherMouseDown, mouseCursorPosition: cursorPos, mouseButton: .center)
                    self.isCenterDragging = true
                }
                let baseFlags = currentSyntheticEventFlags()
                let ownFlags = CGEventFlags(rawValue: CGEventFlags.RawValue(config.modifiers))
                event?.flags = CGEventFlags(rawValue: baseFlags.rawValue | ownFlags.rawValue)
                event?.post(tap: .cghidEventTap)
            }
        }
    }
    
    func buttonReleaseHandler(button: ControllerButton) {
        guard let config = self.currentConfig[button] else { return }
        self.buttonReleaseHandler(config: config)
    }
    
    func buttonReleaseHandler(config: KeyMap) {
        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .hidSystemState)

            if config.keyCode >= 0 {
                if let systemKey = systemDefinedKey[Int(config.keyCode)] {
                    let mousePos = NSEvent.mouseLocation
                    let flags = NSEvent.ModifierFlags(rawValue: 0x0b00)
                    let data1 = Int((systemKey << 16) | 0x0b00)

                    let ev = NSEvent.otherEvent(
                        with: .systemDefined,
                        location: mousePos,
                        modifierFlags: flags,
                        timestamp: ProcessInfo().systemUptime,
                        windowNumber: 0,
                        context: nil,
                        subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                        data1: data1,
                        data2: -1)
                    ev?.cgEvent?.post(tap: .cghidEventTap)
                } else {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(config.keyCode), keyDown: false)
                    // 抬起时 metaKeyEvent 还未跑（顺序见下方），currentSyntheticEventFlags
                    // 仍含本次 config 的贡献——这与标准 CGEvent 行为一致：松开 ⌘ 时
                    // event.flags 仍带 .maskCommand。其它仍按住的 modifier 也都保留。
                    let baseFlags = currentSyntheticEventFlags()
                    let ownFlags = CGEventFlags(rawValue: CGEventFlags.RawValue(config.modifiers))
                    event?.flags = CGEventFlags(rawValue: baseFlags.rawValue | ownFlags.rawValue)
                    event?.post(tap: .cghidEventTap)
                }

                metaKeyEvent(config: config, keyDown: false)
            }

            if config.mouseButton >= 0 {
                let mousePos = NSEvent.mouseLocation
                let cursorPos = CGPoint(x: mousePos.x, y: NSScreen.main!.frame.maxY - mousePos.y)

                var event: CGEvent?
                if config.mouseButton == 0 {
                    event = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: cursorPos, mouseButton: .left)
                    self.isLeftDragging = false
                } else if config.mouseButton == 1 {
                    event = CGEvent(mouseEventSource: source, mouseType: .rightMouseUp, mouseCursorPosition: cursorPos, mouseButton: .right)
                    self.isRightDragging = false
                } else if config.mouseButton == 2 {
                    event = CGEvent(mouseEventSource: source, mouseType: .otherMouseUp, mouseCursorPosition: cursorPos, mouseButton: .center)
                    self.isCenterDragging = false
                }
                event?.post(tap: .cghidEventTap)
            }
        }
    }
    
    func stickMouseHandler(pos: CGPoint, speed: CGFloat) {
        if pos.x == 0 && pos.y == 0 {
            return
        }
        let mousePos = NSEvent.mouseLocation
        let newX = mousePos.x + pos.x * speed
        let newY = NSScreen.main!.frame.maxY - mousePos.y - pos.y * speed
        
        let newPos = CGPoint(x: newX, y: newY)
        
        let source = CGEventSource(stateID: .hidSystemState)
        if self.isLeftDragging {
            let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: newPos, mouseButton: .left)
            event?.post(tap: .cghidEventTap)
        } else if self.isRightDragging {
            let event = CGEvent(mouseEventSource: source, mouseType: .rightMouseDragged, mouseCursorPosition: newPos, mouseButton: .right)
            event?.post(tap: .cghidEventTap)
        } else if self.isCenterDragging {
            let event = CGEvent(mouseEventSource: source, mouseType: .otherMouseDragged, mouseCursorPosition: newPos, mouseButton: .center)
            event?.post(tap: .cghidEventTap)
        } else {
            CGDisplayMoveCursorToPoint(CGMainDisplayID(), newPos)
        }
    }
    
    func stickMouseWheelHandler(pos: CGPoint, speed: CGFloat) {
        if pos.x == 0 && pos.y == 0 {
            return
        }
        let wheelX = Int32(pos.x * speed)
        let wheelY = Int32(pos.y * speed)
        
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: wheelY, wheel2: wheelX, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }
    
    func leftStickHandler(newDirection: ControllerStickDirection, oldDirection: ControllerStickDirection) {
        if self.currentLStickMode == .Key {
            if let config = self.currentLStickConfig[oldDirection] {
                self.buttonReleaseHandler(config: config)
            }
            if let config = self.currentLStickConfig[newDirection] {
                self.buttonPressHandler(config: config)
            }
        }
    }

    func rightStickHandler(newDirection: ControllerStickDirection, oldDirection: ControllerStickDirection) {
        if self.currentRStickMode == .Key {
            if let config = self.currentRStickConfig[oldDirection] {
                self.buttonReleaseHandler(config: config)
            }
            if let config = self.currentRStickConfig[newDirection] {
                self.buttonPressHandler(config: config)
            }
        }
    }

    func leftStickPosHandler(pos: CGPoint) {
        let speed = CGFloat(self.currentConfigData.leftStick?.speed ?? 0)
        if self.currentLStickMode == .Mouse {
            self.stickMouseHandler(pos: pos, speed: speed)
        } else if self.currentLStickMode == .MouseWheel {
            self.stickMouseWheelHandler(pos: pos, speed: speed)
        }
    }
    
    func rightStickPosHandler(pos: CGPoint) {
        let speed = CGFloat(self.currentConfigData.rightStick?.speed ?? 0)
        if self.currentRStickMode == .Mouse {
            self.stickMouseHandler(pos: pos, speed: speed)
        } else if self.currentRStickMode == .MouseWheel {
            self.stickMouseWheelHandler(pos: pos, speed: speed)
        }
    }
    
    func batteryChangeHandler(newState: BatteryLevel, oldState: BatteryLevel) {
        self.updateControllerIcon()
        
        if newState == .full && oldState != .unknown {
            AppNotifications.notifyBatteryFullCharge(self)
        }
        if newState == .empty {
            AppNotifications.notifyBatteryLevel(self)
        }
        if newState == .critical && oldState != .empty {
            AppNotifications.notifyBatteryLevel(self)
        }
        if newState == .low && oldState != .critical && oldState != .empty {
            AppNotifications.notifyBatteryLevel(self)
        }

        DispatchQueue.main.async {
            guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return }
            delegate.updateControllersMenu()
        }
    }
    
    func isChargingChangeHandler(isCharging: Bool) {
        self.updateControllerIcon()
        
        if isCharging {
            AppNotifications.notifyStartCharge(self)
        } else {
            AppNotifications.notifyStopCharge(self)
        }

        DispatchQueue.main.async {
            guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return }
            delegate.updateControllersMenu()
        }
    }
    
    // MARK: - Controller Icon
    
    func updateControllerIcon() {
        self._icon = GameControllerIcon(for: self)
        NotificationCenter.default.post(name: .controllerIconChanged, object: self)
        
        DispatchQueue.main.async {
            guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return }
            delegate.updateControllersMenu()
        }
    }
    
    // MARK: -

    /// 命中 passthrough 配置时为 true。此状态下 currentConfig 被强制清空，
    /// 即便仍能收到 HID 事件也不会模拟键盘 / 鼠标。释放 seize 的全局操作由
    /// AppDelegate 通过 PassthroughCoordinator 统一处理。
    var isPassthroughActive: Bool = false

    /// `switchApp` 返回值：让上层（AppDelegate）知道该 app 是否选择透传。
    @discardableResult
    func switchApp(bundleID: String) -> Bool {
        let appConfig = self.data.appConfigs?.first(where: {
            guard let appConfig = $0 as? AppConfig else { return false }
            return appConfig.app?.bundleID == bundleID
        }) as? AppConfig

        if appConfig?.passthrough == true {
            self.isPassthroughActive = true
            // 清空映射，避免在 seize 释放窗口期之间仍模拟键盘。
            self.currentConfig = [:]
            self.currentLStickConfig = [:]
            self.currentRStickConfig = [:]
            self.currentLStickMode = .None
            self.currentRStickMode = .None
            return true
        }

        self.isPassthroughActive = false
        if let keyConfig = appConfig?.config {
            self.currentConfigData = keyConfig
            return false
        }

        guard let defaultConfig = self.data.defaultConfig else {
            fatalError("Failed to get defaultConfig")
        }
        self.currentConfigData = defaultConfig
        return false
    }
    
    func updateKeyMap() {
        var newKeyMap: [ControllerButton:KeyMap] = [:]
        self.currentConfigData.keyMaps?.enumerateObjects { (map, _) in
            guard let keyMap = map as? KeyMap else { return }
            guard let buttonStr = keyMap.button else { return }
            guard let button = LegacyButtonNameMap.button(from: buttonStr) else { return }
            newKeyMap[button] = keyMap
        }
        self.currentConfig = newKeyMap

        self.currentLStickMode = .None
        if let stickTypeStr = self.currentConfigData.leftStick?.type,
            let stickType = StickType(rawValue: stickTypeStr) {
            self.currentLStickMode = stickType
        }

        var newLeftStickMap: [ControllerStickDirection:KeyMap] = [:]
        self.currentConfigData.leftStick?.keyMaps?.enumerateObjects { (map, _) in
            guard let keyMap = map as? KeyMap else { return }
            guard let buttonStr = keyMap.button else { return }
            guard let direction = LegacyButtonNameMap.stickDirection(from: buttonStr) else { return }
            newLeftStickMap[direction] = keyMap
        }
        self.currentLStickConfig = newLeftStickMap

        self.currentRStickMode = .None
        if let stickTypeStr = self.currentConfigData.rightStick?.type,
            let stickType = StickType(rawValue: stickTypeStr) {
            self.currentRStickMode = stickType
        }

        var newRightStickMap: [ControllerStickDirection:KeyMap] = [:]
        self.currentConfigData.rightStick?.keyMaps?.enumerateObjects { (map, _) in
            guard let keyMap = map as? KeyMap else { return }
            guard let buttonStr = keyMap.button else { return }
            guard let direction = LegacyButtonNameMap.stickDirection(from: buttonStr) else { return }
            newRightStickMap[direction] = keyMap
        }
        self.currentRStickConfig = newRightStickMap
    }
    
    func addApp(url: URL) {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return }
        guard let manager = delegate.dataManager else { return }
        guard let bundle = Bundle(url: url) else { return }
        guard let info = bundle.infoDictionary else { return }

        let bundleID = info["CFBundleIdentifier"] as? String ?? ""
        let appIndex = self.data.appConfigs?.index(ofObjectPassingTest: { (obj, index, stop) in
            guard let appConfig = obj as? AppConfig else { return false }
            return appConfig.app?.bundleID == bundleID
        })
        if appIndex != nil && appIndex != NSNotFound {
            // The selected app has been already added.
            return
        }
        
        let appConfig = manager.createAppConfig(type: self.type, from: self.data.defaultConfig)

        let displayName = FileManager.default.displayName(atPath: url.absoluteString)
        let iconFile = info["CFBundleIconFile"] as? String ?? ""
        if let iconURL = bundle.url(forResource: iconFile, withExtension: nil) {
            do {
                let iconData = try Data(contentsOf: iconURL)
                appConfig.app?.icon = iconData
            } catch {}
        } else if let iconURL = bundle.url(forResource: "\(iconFile).icns", withExtension: nil) {
            do {
                let iconData = try Data(contentsOf: iconURL)
                appConfig.app?.icon = iconData
            } catch {}
        }
        
        appConfig.app?.bundleID = bundleID
        appConfig.app?.displayName = displayName
        
        self.data.addToAppConfigs(appConfig)
    }
    
    func removeApp(_ app: AppConfig) {
        self.data.removeFromAppConfigs(app)
    }
    
    @objc func toggleEnableKeyMappings() {
        self.isEnabled = !self.isEnabled
    }
    
    @objc func disconnect() {
        self.stopTimer()
        self.backend?.disconnect()
    }
    
    // MARK: - Timer

    func updateAccessTime() {
        self.lastAccess = Date(timeIntervalSinceNow: 0)
    }
    
    func startTimer() {
        self.stopTimer()
        
        let checkInterval: TimeInterval = 1 * 60 // 1 min
        self.timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            if AppSettings.disconnectTime <= 0 { return }
            guard let lastAccess = self?.lastAccess else { return }
            let disconnectTime = TimeInterval(AppSettings.disconnectTime * 60)
            
            let now = Date(timeIntervalSinceNow: 0)
            if now.timeIntervalSince(lastAccess) > disconnectTime {
                self?.disconnect()
            }
        }
        self.updateAccessTime()
    }
    
    func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
    }
}
