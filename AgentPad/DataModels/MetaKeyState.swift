//
//  MetaKeyState.swift
//  AgentPad
//
//  Created by magicien on 2020/06/16.
//  Copyright © 2020 DarkHorse. All rights reserved.
//

import InputMethodKit

private let shiftKey = Int32(kVK_Shift)
private let optionKey = Int32(kVK_Option)
private let controlKey = Int32(kVK_Control)
private let commandKey = Int32(kVK_Command)
private let metaKeys = [kVK_Shift, kVK_Option, kVK_Control, kVK_Command]
private var pushedKeyConfigs = Set<KeyMap>()

func resetMetaKeyState() {
    let source = CGEventSource(stateID: .hidSystemState)
    pushedKeyConfigs.removeAll()

    DispatchQueue.main.async {
        // Release all meta keys
        metaKeys.forEach {
            let ev = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode($0), keyDown: false)
            ev?.post(tap: .cghidEventTap)
        }
    }
}

func getMetaKeyState() -> (shift: Bool, option: Bool, control: Bool, command: Bool) {
    var shift: Bool = false
    var option: Bool = false
    var control: Bool = false
    var command: Bool = false

    pushedKeyConfigs.forEach {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt($0.modifiers))
        shift = shift || modifiers.contains(.shift)
        option = option || modifiers.contains(.option)
        control = control || modifiers.contains(.control)
        command = command || modifiers.contains(.command)
    }

    return (shift, option, control, command)
}

/// 计算"当前所有按住的 KeyMap"贡献给后续按键事件的合成修饰键标志。
///
/// 包括两类来源：
/// 1. KeyMap.modifiers 中显式勾选的修饰键（详细模式产物）。
/// 2. KeyMap.keyCode 本身就是修饰键的情况（简易模式把 ⌘/⌥/⌃/⇧ 映射成
///    一个普通按键时会出现）—— 这种映射在 buttonPressHandler 走 else 分支
///    时 `event.flags = 0` 会把当前 modifier 抹掉，导致后续按键无法组合。
///    在这里把它们也算进合成 flags，调用方就可以 union 进去保住状态。
func currentSyntheticEventFlags() -> CGEventFlags {
    var flags: UInt64 = 0
    pushedKeyConfigs.forEach { config in
        // 来源 1：显式 modifiers。
        flags |= UInt64(config.modifiers)

        // 来源 2：keyCode 本身是 modifier。
        let kc = Int32(config.keyCode)
        switch kc {
        case Int32(kVK_Shift), Int32(kVK_RightShift):
            flags |= UInt64(CGEventFlags.maskShift.rawValue)
        case Int32(kVK_Option), Int32(kVK_RightOption):
            flags |= UInt64(CGEventFlags.maskAlternate.rawValue)
        case Int32(kVK_Control), Int32(kVK_RightControl):
            flags |= UInt64(CGEventFlags.maskControl.rawValue)
        case Int32(kVK_Command):
            flags |= UInt64(CGEventFlags.maskCommand.rawValue)
        default:
            break
        }
    }
    return CGEventFlags(rawValue: flags)
}

/**
 * This command must be called in the main thread
 */
func metaKeyEvent(config: KeyMap, keyDown: Bool) {
    var shift: Bool
    var option: Bool
    var control: Bool
    var command: Bool
    
    if keyDown {
        // Check if meta keys are not pressed before pressing keys
        (shift, option, control, command) = getMetaKeyState()
        pushedKeyConfigs.insert(config)
    } else {
        pushedKeyConfigs.remove(config)
        // Check if meta keys are not pressed after releasing keys
        (shift, option, control, command) = getMetaKeyState()
    }
    
    let source = CGEventSource(stateID: .hidSystemState)
    let modifiers = NSEvent.ModifierFlags(rawValue: UInt(config.modifiers))
    if !shift && modifiers.contains(.shift) {
        let ev = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: keyDown)
        ev?.post(tap: .cghidEventTap)
    }
    
    if !option && modifiers.contains(.option) {
        let ev = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Option), keyDown: keyDown)
        ev?.post(tap: .cghidEventTap)
    }
    
    if !control && modifiers.contains(.control) {
        let ev = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Control), keyDown: keyDown)
        ev?.post(tap: .cghidEventTap)
    }

    if !command && modifiers.contains(.command) {
        let ev = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: keyDown)
        ev?.post(tap: .cghidEventTap)
    }
}
