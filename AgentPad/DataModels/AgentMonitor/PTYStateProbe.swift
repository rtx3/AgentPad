//
//  PTYStateProbe.swift
//  AgentPad
//
//  通过 Accessibility API 读取宿主终端窗口的可见文本，按关键词推断 agent 状态。
//  作为 JSONLSessionProbe 的兜底；任何步骤失败 → 返回 nil，调用方按 idle 处理。
//

import Foundation
import AppKit
import ApplicationServices

struct PTYProbeResult: Equatable {
    let state: AgentState
    let detail: AgentStateDetail
    let snippet: String
}

enum PTYStateProbe {
    /// 默认关键词表。命中即返回对应状态。多个状态同时命中按 Working > CallingAPI > Idle 取高。
    struct Keywords {
        var working: [String]
        var callingAPI: [String]
        var idle: [String]

        static let `default` = Keywords(
            working: [
                // Claude Code 在跑 tool 时底栏会显示 "esc to interrupt" / "ctrl+b to background"
                // 用 "to interrupt" 取代 "esc to interrupt"，兼容 ctrl 提示行变体。
                "to interrupt",
                "running ", "tool_use(", "⏵⏵"
            ],
            callingAPI: [
                "thinking", "streaming",
                // 旧版 Claude Code spinner
                "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
                // 新版 Claude Code（4.6+）改用"烹饪动词"系列做进度文案：
                // 实测见 `✻ Churned for 3m 29s` / `✢ Caramelizing… (12s · still thinking with xhigh effort)`
                // 子串匹配 + 小写，因此 "Churned"/"churned" 都能命中。
                "churned", "caramelizing", "simmering", "whisking", "folding",
                "braising", "searing", "reducing", "proofing", "kneading",
                "marinating", "sautéing", "sauteing", "blanching", "poaching",
                // 进度装饰符号（出现在每一行前缀），命中其一即认为在 calling。
                "✻", "✢"
            ],
            idle: ["do you want to", "(y/n)"]
        )
    }

    /// 末 N 行用于关键词匹配，避免抓全屏文本造成开销。
    private static let lastLinesForMatch = 20

    /// AX 同步调用的硬超时（秒）。默认 6s 会让 poll 队列被卡死的终端拖垮，
    /// 0.5s 在实际 macOS 上仍足够拿到窗口文本。
    private static let axMessagingTimeoutSec: Float = 0.5

    /// 主入口：给定 agent PID，返回 PTY 路推断的状态。
    /// - 找不到宿主终端 / 取不到窗口文本 / 关键词全不命中 → 返回 nil。
    static func probe(forAgentPID pid: pid_t, keywords: Keywords = .default) -> PTYProbeResult? {
        guard AccessibilityPermission.isTrusted() else { return nil }
        guard let hostPID = TerminalHostResolver.hostTerminalPID(forAgent: pid) else { return nil }
        guard let text = readWindowText(forPID: hostPID) else { return nil }
        return classify(text: text, keywords: keywords)
    }

    /// 把文本按关键词分类。公开以便单元测试不依赖 AX。
    static func classify(text: String, keywords: Keywords = .default) -> PTYProbeResult? {
        let lowered = lastLines(of: text, count: lastLinesForMatch).lowercased()
        if let kw = keywords.working.first(where: { lowered.contains($0.lowercased()) }) {
            return PTYProbeResult(state: .working, detail: .toolUse(name: kw), snippet: kw)
        }
        if let kw = keywords.callingAPI.first(where: { lowered.contains($0.lowercased()) }) {
            return PTYProbeResult(state: .callingAPI, detail: .streaming, snippet: kw)
        }
        if let kw = keywords.idle.first(where: { lowered.contains($0.lowercased()) }) {
            return PTYProbeResult(state: .idle, detail: .waitingInput(prompt: kw), snippet: kw)
        }
        return nil
    }

    // MARK: - AX 文本抓取

    private static func readWindowText(forPID pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        // 关键：防卡死。不设的话单个无响应窗口能让 poll 队列阻塞 6 秒。
        AXUIElementSetMessagingTimeout(app, axMessagingTimeoutSec)
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused)
        guard status == .success, let windowRef = focused else {
            // 退而求其次：取第一扇 window。
            var windows: CFTypeRef?
            let s2 = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
            guard s2 == .success, let arr = windows as? [AXUIElement], let first = arr.first else {
                return nil
            }
            return collectText(from: first)
        }
        // CFTypeRef → AXUIElement
        let window = windowRef as! AXUIElement
        return collectText(from: window)
    }

    /// 递归向下抓 AXValue / AXTitle / AXDescription 拼成纯文本。
    /// 深度受限避免在嵌套很深的视图上耗时。
    private static func collectText(from element: AXUIElement, depth: Int = 0, maxDepth: Int = 6, accumulator: inout String) {
        guard depth <= maxDepth else { return }
        if let v = stringAttribute(element, kAXValueAttribute) { accumulator.append(v); accumulator.append("\n") }
        if let t = stringAttribute(element, kAXTitleAttribute) { accumulator.append(t); accumulator.append("\n") }
        if let d = stringAttribute(element, kAXDescriptionAttribute) { accumulator.append(d); accumulator.append("\n") }
        var children: CFTypeRef?
        let s = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if s == .success, let arr = children as? [AXUIElement] {
            for child in arr {
                collectText(from: child, depth: depth + 1, maxDepth: maxDepth, accumulator: &accumulator)
            }
        }
    }

    private static func collectText(from element: AXUIElement) -> String? {
        var acc = ""
        collectText(from: element, accumulator: &acc)
        return acc.isEmpty ? nil : acc
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let s = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard s == .success else { return nil }
        return value as? String
    }

    private static func lastLines(of text: String, count: Int) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
        guard lines.count > count else { return text }
        return lines.suffix(count).joined(separator: "\n")
    }
}
