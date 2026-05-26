//
//  AccessibilityPermission.swift
//  AgentPad
//

import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static let onboardingShownDefaultsKey = "hasShownAccessibilityOnboarding"

    static func isTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// 强制把进程登记到 System Settings → Privacy & Security → Accessibility 列表。
    /// 仅靠 AXIsProcessTrustedWithOptions 在重命名后的 BID 上未必能让 macOS 自动添加条目，
    /// 但任何到达 .cghidEventTap 的 CGEvent.post 都会让 tccd 把进程加入列表（默认未勾）。
    /// 这里 post 一个"鼠标移动到当前位置"事件——无视觉副作用，仅用于触发登记。
    static func registerInTCCList() {
        let mouse = NSEvent.mouseLocation
        let screenH = NSScreen.main?.frame.maxY ?? 0
        let pos = CGPoint(x: mouse.x, y: screenH - mouse.y)
        let src = CGEventSource(stateID: .hidSystemState)
        let ev = CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: pos, mouseButton: .left)
        ev?.post(tap: .cghidEventTap)
    }

    @discardableResult
    static func openSettings() -> Bool {
        let primary = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        let fallback = "x-apple.systempreferences:com.apple.preference.security"
        if let url = URL(string: primary), NSWorkspace.shared.open(url) {
            return true
        }
        if let url = URL(string: fallback) {
            return NSWorkspace.shared.open(url)
        }
        return false
    }

    static var hasShownOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingShownDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingShownDefaultsKey) }
    }
}
