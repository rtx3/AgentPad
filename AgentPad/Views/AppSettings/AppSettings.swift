//
//  AppSettings.swift
//  AgentPad
//
//  Created by magicien on 2020/03/12.
//  Copyright © 2020 DarkHorse. All rights reserved.
//

import Foundation
import ServiceManagement

let helperAppBundleID = "com.rtx3.agentpad.launcher"

enum KeyCaptureMode: String {
    case simple
    case detailed
    case agent
}

class AppSettings {
    static var disconnectTime: Int {
        get {
            return UserDefaults.standard.integer(forKey: "disconnectTime")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "disconnectTime")
        }
    }
    
    static var notifyConnection: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "notifyConnection")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "notifyConnection")
        }
    }
    
    static var notifyBatteryLevel: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "notifyBatteryLevel")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "notifyBatteryLevel")
        }
    }
    
    static var notifyBatteryCharge: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "notifyBatteryCharge")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "notifyBatteryCharge")
        }
    }
    
    static var notifyBatteryFull: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "notifyBatteryFull")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "notifyBatteryFull")
        }
    }
    
    static var defaultKeyCaptureMode: KeyCaptureMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "defaultKeyCaptureMode") ?? KeyCaptureMode.simple.rawValue
            return KeyCaptureMode(rawValue: raw) ?? .simple
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "defaultKeyCaptureMode")
        }
    }

    static var launchOnLogin: Bool {
        get {
            guard let loginItems = SMCopyAllJobDictionaries(kSMDomainUserLaunchd).takeRetainedValue() as NSArray as? [[String:AnyObject]] else { return false }
            return !loginItems.filter {
                $0["Label"] as! String == helperAppBundleID
            }.isEmpty
        }
        set {
            if (!SMLoginItemSetEnabled(helperAppBundleID as CFString, newValue)) {
                Swift.print("Launch on Login setting error")
            }
        }
    }
}

extension AppSettings {
    /// Agent 监控相关配置。每个字段一个 UserDefaults key，遵从既有
    /// AppSettings 风格（静态属性 + UserDefaults）。
    enum AgentMonitor {
        static let defaultPatterns: [String] = ["claude", "opencode", "codex"]
        static let defaultSessionRoots: [String: String] = [
            "claude": "~/.claude/projects",
            "codex": "~/.codex/sessions"
        ]
        static let defaultPollIntervalSec: Int = 3
        static let defaultPollFailureThreshold: Int = 3
        static let allowedPollIntervalsSec: [Int] = [1, 3, 5, 10, 30]

        private static let patternsKey = "agent.monitor.patterns"
        private static let sessionRootsKey = "agent.monitor.sessionRoots"
        private static let pollIntervalKey = "agent.monitor.pollIntervalSec"
        private static let pollFailureThresholdKey = "agent.monitor.pollFailureThreshold"
        private static let showCountKey = "agent.monitor.showCountInMenuBar"
        private static let enablePTYKey = "agent.monitor.enablePTYProbe"
        private static let showStatusBadgeKey = "agent.monitor.showStatusBadge"

        /// 设置任一字段变更后调用 `postSettingsDidChange()`，AgentMonitor 收到后会 `restart()`。
        static let settingsDidChangeNotification = Notification.Name("AppSettings.AgentMonitor.settingsDidChange")

        static func postSettingsDidChange() {
            NotificationCenter.default.post(name: settingsDidChangeNotification, object: nil)
        }

        static var patterns: [String] {
            get {
                return UserDefaults.standard.array(forKey: patternsKey) as? [String] ?? defaultPatterns
            }
            set {
                UserDefaults.standard.set(newValue, forKey: patternsKey)
            }
        }

        /// pattern → session 文件根目录（绝对路径或 `~/...`）。
        /// 仅含有效条目的 pattern 才会启用 JSONL 主路；其余 pattern 自动走 PTY 兜底。
        static var sessionRoots: [String: String] {
            get {
                return UserDefaults.standard.dictionary(forKey: sessionRootsKey) as? [String: String] ?? defaultSessionRoots
            }
            set {
                UserDefaults.standard.set(newValue, forKey: sessionRootsKey)
            }
        }

        static var pollIntervalSec: Int {
            get {
                let v = UserDefaults.standard.integer(forKey: pollIntervalKey)
                return allowedPollIntervalsSec.contains(v) ? v : defaultPollIntervalSec
            }
            set {
                UserDefaults.standard.set(newValue, forKey: pollIntervalKey)
            }
        }

        static var pollFailureThreshold: Int {
            get {
                let v = UserDefaults.standard.integer(forKey: pollFailureThresholdKey)
                return v > 0 ? v : defaultPollFailureThreshold
            }
            set {
                UserDefaults.standard.set(newValue, forKey: pollFailureThresholdKey)
            }
        }

        static var showCountInMenuBar: Bool {
            get {
                if UserDefaults.standard.object(forKey: showCountKey) == nil { return true }
                return UserDefaults.standard.bool(forKey: showCountKey)
            }
            set {
                UserDefaults.standard.set(newValue, forKey: showCountKey)
            }
        }

        static var enablePTYProbe: Bool {
            get {
                if UserDefaults.standard.object(forKey: enablePTYKey) == nil { return true }
                return UserDefaults.standard.bool(forKey: enablePTYKey)
            }
            set {
                UserDefaults.standard.set(newValue, forKey: enablePTYKey)
            }
        }

        static var showStatusBadge: Bool {
            get {
                if UserDefaults.standard.object(forKey: showStatusBadgeKey) == nil { return true }
                return UserDefaults.standard.bool(forKey: showStatusBadgeKey)
            }
            set {
                UserDefaults.standard.set(newValue, forKey: showStatusBadgeKey)
            }
        }
    }
}
