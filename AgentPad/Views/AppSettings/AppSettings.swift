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
    case system
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

    static var language: String {
        get {
            return UserDefaults.standard.string(forKey: "AppLanguage") ?? "en"
        }
        set {
            // 同时写两个 key：
            // - AppLanguage 是应用层 key，AppDelegate.applicationWillFinishLaunching
            //   作为兜底从这里读出再注入 AppleLanguages。
            // - AppleLanguages 是 NSBundle 解析 lproj 时直接读取的 OS key；
            //   App 未启用 sandbox（entitlements 中 app-sandbox=false），
            //   可直接持久化到 ~/Library/Preferences/com.rtx3.agentpad.plist。
            // 写完调 CFPreferencesAppSynchronize 强制 cfprefsd flush，避免用户
            // 立即 Quit 重启时新值还在内存缓冲里没落盘，导致下次启动读到旧值
            // —— 这是用户报告"切不回英文，等几秒后再启动就 ok"的根因。
            UserDefaults.standard.set(newValue, forKey: "AppLanguage")
            UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
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
        static let defaultPollIntervalSec: Int = 10
        static let defaultPollFailureThreshold: Int = 3
        static let allowedPollIntervalsSec: [Int] = [1, 3, 5, 10, 30]
        /// 末条 record 距 now 超过此阈值时，视为"死会话残留"→ classify 强制降级 idle。
        /// 仅 UserDefaults 可调，无 UI 暴露。
        static let defaultStalenessThresholdSec: Int = 90

        private static let patternsKey = "agent.monitor.patterns"
        private static let sessionRootsKey = "agent.monitor.sessionRoots"
        private static let pollIntervalKey = "agent.monitor.pollIntervalSec"
        private static let pollFailureThresholdKey = "agent.monitor.pollFailureThreshold"
        private static let stalenessThresholdKey = "agent.monitor.stalenessThresholdSec"
        private static let enablePTYKey = "agent.monitor.enablePTYProbe"
        private static let showStatusBadgeKey = "agent.monitor.showStatusBadge"
        private static let verboseLogKey = "agent.monitor.verboseLog"

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

        static var stalenessThresholdSec: Int {
            get {
                let v = UserDefaults.standard.integer(forKey: stalenessThresholdKey)
                return v > 0 ? v : defaultStalenessThresholdSec
            }
            set {
                UserDefaults.standard.set(newValue, forKey: stalenessThresholdKey)
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

        /// tick 级诊断日志开关。默认关闭：每 tick 多行 NSLog 是持续功耗源
        /// （unified logging 写入 + 唤醒）。仅 UserDefaults 可调，无 UI 暴露：
        /// `defaults write com.rtx3.agentpad agent.monitor.verboseLog -bool true`
        static var verboseLog: Bool {
            get {
                return UserDefaults.standard.bool(forKey: verboseLogKey)
            }
            set {
                UserDefaults.standard.set(newValue, forKey: verboseLogKey)
            }
        }
    }
}
