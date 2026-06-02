//
//  TerminalHostResolver.swift
//  AgentPad
//
//  沿 agent 进程的 ppid 链向上找到第一个匹配「已知终端 bundle id」的 PID。
//  返回值用于 PTYStateProbe 走 AX 路读窗口文本。
//

import Foundation
import AppKit

enum TerminalHost: String, CaseIterable {
    case appleTerminal = "com.apple.Terminal"
    case iTerm         = "com.googlecode.iterm2"
    case ghostty       = "com.mitchellh.ghostty"
    case wezterm       = "com.github.wez.wezterm"
    case kitty         = "net.kovidgoyal.kitty"
    case alacritty     = "org.alacritty"
    case warp          = "dev.warp.Warp-Stable"
}

enum TerminalHostResolver {
    private static let maxDepth = 16

    /// 给定 agent PID，沿 ppid 链向上找到第一个 bundle id 命中已知终端的祖先 PID。
    /// 未识别则返回 nil。
    static func hostTerminalPID(forAgent pid: pid_t) -> pid_t? {
        let known = Set(TerminalHost.allCases.map { $0.rawValue })
        var current = pid
        var depth = 0
        while depth < maxDepth, current > 1 {
            guard let parent = ProcessScanner.parentPid(of: current), parent > 0 else { return nil }
            if parent == current { return nil }
            if let bundleId = bundleId(forPID: parent), known.contains(bundleId) {
                return parent
            }
            current = parent
            depth += 1
        }
        return nil
    }

    static func bundleId(forPID pid: pid_t) -> String? {
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}
