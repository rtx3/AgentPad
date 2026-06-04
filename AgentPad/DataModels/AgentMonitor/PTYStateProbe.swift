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
    /// 默认关键词表。命中按 `classify` 内的优先级返回。
    /// 优先级（见 classify 注释）：querying-keyword > error > 末行? > working > callingAPI > idle。
    struct Keywords {
        var querying: [String]
        var error: [String]
        var working: [String]
        var callingAPI: [String]
        var idle: [String]

        static let `default` = Keywords(
            querying: [
                // Claude Code 等待用户 y/n / plan 确认 / 权限授予
                "do you want to", "(y/n)", "press enter", "(esc to cancel)",
                "would you like", "shall i", "confirm"
            ],
            error: [
                // 严格的 error 关键词——避免被普通 "error:" / "failed:" 输出污染。
                // 命中即报红：用户跑测试时不会触发这些精确字符串。
                "api error", "401", "403", "429", "500",
                "rate limit", "overloaded", "context_length_exceeded"
            ],
            working: [
                "to interrupt",
                "running ", "tool_use(", "⏵⏵"
            ],
            callingAPI: [
                "thinking", "streaming",
                "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
                "churned", "caramelizing", "simmering", "whisking", "folding",
                "braising", "searing", "reducing", "proofing", "kneading",
                "marinating", "sautéing", "sauteing", "blanching", "poaching",
                "✻", "✢"
            ],
            idle: []
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
    /// 优先级：querying（关键词）> error > querying（末行 ?）> working > callingAPI > idle。
    ///
    /// error 紧跟 querying 关键词桶后面：
    /// - querying 关键词命中是"用户主动确认"的强信号，比 error 更早响应；
    /// - error 优先于 working/callingAPI，因为发现 api error 比发现在跑更需要展示。
    /// - 末行 ? 形态判定放在 error 后：避免 "API Error: ... continue?" 这类
    ///   末尾带 ? 但本质是 error 的文本被错抢成 querying。
    static func classify(text: String, keywords: Keywords = .default) -> PTYProbeResult? {
        let tail = lastLines(of: text, count: lastLinesForMatch)
        let lowered = tail.lowercased()
        if let kw = keywords.querying.first(where: { lowered.contains($0.lowercased()) }) {
            return PTYProbeResult(state: .querying, detail: .querying(question: kw), snippet: kw)
        }
        if let kw = keywords.error.first(where: { lowered.contains($0.lowercased()) }) {
            // detail.reason 留空：keyword 本身（如 "api error" / "401"）作为副行展示没信息量；
            // snippet 已承载触发原因，UI 可单独展示。需要更详细的错误文本时由 jsonl 路径提供。
            return PTYProbeResult(state: .error, detail: .errored(reason: nil), snippet: kw)
        }
        if endsWithQuestionMark(tail) {
            return PTYProbeResult(state: .querying, detail: .querying(question: nil), snippet: "?")
        }
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

    /// 取 `text` 末 N 行里最后一个非空行，trim 行尾空白后末字符是否为问号。
    /// 末行常是 spinner / 装饰 / 空白，因此倒着扫，找第一个有内容的行。
    /// `?` 与全角 `？` 都算。internal 以便单测覆盖。
    static func endsWithQuestionMark(_ tail: String) -> Bool {
        let lines = tail.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let last = trimmed.last else { return false }
            return last == "?" || last == "？"
        }
        return false
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
