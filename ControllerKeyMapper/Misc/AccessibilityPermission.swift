//
//  AccessibilityPermission.swift
//  ControllerKeyMapper
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
