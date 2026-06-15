//
//  SystemActionRunner.swift
//  AgentPad
//
//  分发 SystemAction：
//  - NSWorkspace.open 路径：Mission Control / Launchpad / Notification Center
//  - 合成 CGEvent：Move Space Left/Right（与 AgentMacroRunner.simulateControlNumber
//    完全一致的路径——合成 Ctrl+← / Ctrl+→ 通过 .cghidEventTap post，
//    Mission Control 接受并切换 Space。前提：系统设置 → 键盘 → 键盘快捷键 →
//    Mission Control → "Move left/right a space" 保持启用，这是 macOS 默认状态。）
//  - 私有 Dock SPI：Show Desktop（CoreDockSendNotification）。
//

import AppKit
import Carbon.HIToolbox

// MARK: - Dock private SPI (Show Desktop)

// Dock 进程订阅了 "com.apple.showdesktop.awake" 这个 darwin notification，
// 收到后会切换"显示桌面"状态。这是 macOS 14+ 没有独立 Show Desktop .app
// 时唯一可靠的触发方式——比模拟 F11 稳，因为 F11 是合成键盘事件可能被吞。
@_silgen_name("CoreDockSendNotification")
private func CoreDockSendNotification(_ name: CFString, _ unknown: Int32)

// MARK: - Runner

final class SystemActionRunner {
    static let shared = SystemActionRunner()
    private init() {}

    func run(_ action: SystemAction) {
        NSLog("[AgentPad] system action: %@", action.rawValue)
        switch action {
        case .moveToSpaceLeft:
            simulateControlArrow(keyCode: CGKeyCode(kVK_LeftArrow))
        case .moveToSpaceRight:
            simulateControlArrow(keyCode: CGKeyCode(kVK_RightArrow))
        case .missionControl:
            openSystemApp(at: "/System/Applications/Mission Control.app")
        case .launchpad:
            openSystemApp(at: "/System/Applications/Launchpad.app")
        case .notificationCenter:
            openSystemApp(at: "/System/Library/CoreServices/NotificationCenter.app")
        case .showDesktop:
            showDesktop()
        }
    }

    // MARK: - .app 启动

    private func openSystemApp(at path: String) {
        let url = URL(fileURLWithPath: path)
        // NSWorkspace.shared.open(_:) 自 macOS 10.0 起可用；不用 openApplication(at:configuration:)
        // 那个 API 要求 macOS 10.15+，本工程 deployment target 低于 10.15。
        if !NSWorkspace.shared.open(url) {
            NSLog("[AgentPad] openSystemApp failed: %@", path)
        }
    }

    // MARK: - Show Desktop

    private func showDesktop() {
        // Dock 收到通知后会触发 "Show Desktop" 切换（再触发一次会还原）。
        CoreDockSendNotification("com.apple.showdesktop.awake" as CFString, 0)
    }

    // MARK: - Space 切换

    /// 合成 Ctrl+方向键。
    /// 与 AgentMacroRunner.simulateControlNumber 的合成路径相同（.cghidEventTap），
    /// 但方向键必须额外带 `.maskSecondaryFn`——这是 macOS 用来标识 function-key
    /// 区按键的标志位（方向键、F1–F12、Help/Home/End/PageUp/PageDown 都属于这一类）。
    /// 真实硬件按 Ctrl+→ 时 CGEvent.flags 实际是 maskControl | maskSecondaryFn；
    /// 漏掉 secondaryFn 会让 Mission Control 的 "Move left/right a space" 处理器不命中。
    /// AltTab / Hammerspoon / Karabiner 合成方向键均同此处理。
    private func simulateControlArrow(keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: src,
                                    virtualKey: keyCode,
                                    keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src,
                                  virtualKey: keyCode,
                                  keyDown: false) else {
            NSLog("[AgentPad] simulateControlArrow: CGEvent creation failed")
            return
        }
        let flags: CGEventFlags = [.maskControl, .maskSecondaryFn]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        NSLog("[AgentPad] simulateControlArrow: sent Control+arrow (keyCode=%d, flags=0x%llx)",
              keyCode, flags.rawValue)
    }
}
