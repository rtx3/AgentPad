//
//  JSONLSessionProbe.swift
//  AgentPad
//
//  Tail Claude Code / Codex 等 agent 写入的 session JSONL。
//  按 poll 节奏：每轮从持有的 fd 起读取新增字节，按行解析，缓存末条记录，
//  按末条记录类型 + freshness 映射状态。
//

import Foundation

/// 单进程的 JSONL tail 上下文。AgentMonitor 按 pid 维护一份。
final class JSONLProbeContext {
    static let newlineByte: UInt8 = 0x0a

    let pid: pid_t
    let cwd: String?
    private(set) var sessionURL: URL?
    private var fileHandle: FileHandle?
    private var offset: UInt64 = 0
    /// 字节级缓冲。不预转 String，避免在多字节 UTF-8 边界处丢字节。
    private var pendingData: Data = Data()
    private(set) var lastRecord: JSONLRecord?
    /// 末条 record 的真实写入时刻：优先取 record.timestamp（最准），
    /// 否则 fall back 到 tick 时刻读到的文件 mtime；都没有时为 nil。
    /// 注意：这里**不是** `Date()`(当前时刻)，否则 freshness 判定会失效。
    private(set) var lastWriteAt: Date?
    /// 末条「状态信号行」—— 跳过 turn 间隙的装饰行（system/summary/...）。
    /// Claude Code 在每个 turn 结束后会写一串非状态行，会把真正决定状态的
    /// assistant/user 行从「物理末行」位置挤走；classify 必须基于这个字段
    /// 才能避免把"间隙"误判为 idle。Codex 用的 type 都不在装饰集合里，
    /// 因此 lastStateSignalRecord 与 lastRecord 在 codex 上等价。
    private(set) var lastStateSignalRecord: JSONLRecord?
    private(set) var lastStateSignalAt: Date?

    /// Claude Code 在 turn 之间或异步写入的"装饰行"——出现在物理末行但不携带
    /// 状态信号。把它们当末行会把 inter-turn 间隙 / 异步晚到的标题写入误判为 idle。
    /// - permission-mode / attachment 不属于此集合：前者是 idle.waitingInput("permission")
    ///   的真实信号；后者会紧跟新一轮 user→assistant 流，本身视为 callingAPI。
    fileprivate static let decorativeTypes: Set<String> = [
        "system",
        "summary",
        "file-history-snapshot",
        "ai-title",
        "last-prompt"
    ]

    init(pid: pid_t, cwd: String?) {
        self.pid = pid
        self.cwd = cwd
    }

    /// 绑定 / 切换到新的 session 文件。若 URL 改变会关闭旧 fd。
    func bind(to url: URL) {
        if sessionURL == url { return }
        close()
        sessionURL = url
        fileHandle = try? FileHandle(forReadingFrom: url)
        offset = 0
        pendingData.removeAll(keepingCapacity: true)
        lastRecord = nil
        lastWriteAt = nil
        lastStateSignalRecord = nil
        lastStateSignalAt = nil
    }

    func close() {
        fileHandle?.closeFile()
        fileHandle = nil
        offset = 0
        pendingData.removeAll(keepingCapacity: true)
        sessionURL = nil
    }

    /// 读取自上次以来的新增字节，解析 lastRecord。
    /// 返回是否有任何新内容。
    @discardableResult
    func tick() -> Bool {
        guard let handle = fileHandle, let url = sessionURL else { return false }
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let fileSize = (attrs[.size] as? UInt64) ?? 0
        let fileMtime = attrs[.modificationDate] as? Date
        if fileSize == offset { return false }
        if fileSize < offset {
            // 文件被截断 / rotate：从头读。
            offset = 0
            handle.seek(toFileOffset: 0)
            pendingData.removeAll(keepingCapacity: true)
        }
        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        offset = handle.offsetInFile
        guard !data.isEmpty else { return false }
        pendingData.append(data)

        var didUpdate = false
        // 按字节查找换行，保证每条完整行都是合法 UTF-8 边界。
        while let nlIdx = pendingData.firstIndex(of: Self.newlineByte) {
            let lineRange = pendingData.startIndex..<nlIdx
            let lineData = pendingData.subdata(in: lineRange)
            pendingData.removeSubrange(pendingData.startIndex...nlIdx)
            guard !lineData.isEmpty,
                  let line = String(data: lineData, encoding: .utf8) else {
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let rec = JSONLRecord.parse(line: trimmed) {
                lastRecord = rec
                lastWriteAt = rec.timestamp ?? fileMtime
                // 装饰行只刷新 lastRecord/lastWriteAt 用于日志和兜底，
                // 不污染状态信号轨。
                if !Self.decorativeTypes.contains(rec.type) {
                    lastStateSignalRecord = rec
                    lastStateSignalAt = rec.timestamp ?? fileMtime
                }
                didUpdate = true
            }
        }
        return didUpdate
    }

    deinit { close() }
}

/// JSONL 中单条记录的极简模型。仅解析状态判定必需的字段。
/// 兼容两套结构：
/// - Claude Code: `type` + `message.{stop_reason, content[]}` + `timestamp`
/// - Codex:       `type` + `payload.type` + `timestamp`
struct JSONLRecord {
    let type: String                  // top-level "type"
    let payloadType: String?          // codex: payload.type（状态主信号）
    let stopReason: String?           // claude: message.stop_reason
    let toolUseName: String?          // claude: message.content[] 含 tool_use 时的工具名
    let hasToolResult: Bool           // claude: message.content[] 含 tool_result 时为 true
    let sessionId: String?
    let timestamp: Date?              // record.timestamp 解析后；用于 freshness 判定
    /// 错误信息文本，用于 error 状态副行展示。三路解析：
    /// 1) `dict["error"]`（平铺）
    /// 2) `message.error`（Claude 嵌套）
    /// 3) `payload.error`（Codex 嵌套）
    let errorMessage: String?

    static func parse(line: String) -> JSONLRecord? {
        guard let data = line.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let dict = obj as? [String: Any] else { return nil }
        let type = (dict["type"] as? String) ?? ""
        guard !type.isEmpty else { return nil }
        let sessionId = dict["sessionId"] as? String ?? dict["session_id"] as? String
        let timestamp = (dict["timestamp"] as? String).flatMap { parseTimestamp($0) }

        // Claude: message.{stop_reason, content[]}
        var stopReason: String? = nil
        var toolUseName: String? = nil
        var hasToolResult = false

        if let message = dict["message"] as? [String: Any] {
            stopReason = message["stop_reason"] as? String
            if let content = message["content"] as? [Any] {
                for item in content {
                    guard let entry = item as? [String: Any] else { continue }
                    let t = entry["type"] as? String
                    if t == "tool_use" {
                        toolUseName = entry["name"] as? String
                    } else if t == "tool_result" {
                        hasToolResult = true
                    }
                }
            }
        }
        // 兼容平铺 stop_reason 字段。
        if stopReason == nil {
            stopReason = dict["stop_reason"] as? String
        }

        // Codex: payload.type 是状态判定主信号
        let payloadType = (dict["payload"] as? [String: Any])?["type"] as? String

        // 错误信息：dict["error"] / message.error / payload.error；取首个 string 命中。
        var errorMessage: String? = dict["error"] as? String
        if errorMessage == nil, let m = dict["message"] as? [String: Any] {
            errorMessage = m["error"] as? String
        }
        if errorMessage == nil, let p = dict["payload"] as? [String: Any] {
            errorMessage = p["error"] as? String
        }

        return JSONLRecord(
            type: type,
            payloadType: payloadType,
            stopReason: stopReason,
            toolUseName: toolUseName,
            hasToolResult: hasToolResult,
            sessionId: sessionId,
            timestamp: timestamp,
            errorMessage: errorMessage
        )
    }

    // MARK: - timestamp 解析

    /// Claude Code 写的格式：`2026-06-02T06:05:08.570Z`（含毫秒）。
    /// Codex 同样使用 ISO-8601。
    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func parseTimestamp(_ s: String) -> Date? {
        if let d = isoFormatterWithFractional.date(from: s) { return d }
        if let d = isoFormatterNoFractional.date(from: s) { return d }
        return nil
    }
}

/// Claude Code 的 JSONL 末行 → 状态结论。
enum JSONLSessionProbe {
    /// 单条记录 + 距上次写入的间隔 → 状态结论。
    ///
    /// - `coldStartWindow`：纯 user 末行的"冷启动"窗口，窗口内视为 callingAPI。
    /// - `stalenessThreshold`：末行 timestamp 距 now 超过此阈值 → 不再相信末行映射，强制 idle。
    ///   解决"死会话残留在某个非 idle 状态被永久误报"问题。
    static func classify(record: JSONLRecord?,
                         lastWriteAt: Date?,
                         now: Date = Date(),
                         coldStartWindow: TimeInterval = 30,
                         stalenessThreshold: TimeInterval = 90) -> (state: AgentState, detail: AgentStateDetail)? {
        guard let rec = record else { return nil }

        // staleness 闸门：末行时间距 now 超过阈值 → 强制 idle。
        // 仅当 lastWriteAt 已知时启用；未知时按原逻辑走。
        if let writeAt = lastWriteAt, now.timeIntervalSince(writeAt) > stalenessThreshold {
            return (.idle, .unknown)
        }

        switch rec.type {
        case "assistant":
            if let tool = rec.toolUseName {
                return (.working, .toolUse(name: tool))
            }
            if rec.stopReason == "error" {
                return (.error, .errored(reason: rec.errorMessage))
            }
            if rec.stopReason == nil {
                return (.callingAPI, .streaming)
            }
            return (.idle, .waitingInput(prompt: nil))
        case "user":
            // tool_result 已回填，等 assistant 继续 → callingAPI
            if rec.hasToolResult { return (.callingAPI, .streaming) }
            // 纯 user prompt：冷启动窗口内仍认为在等响应
            if let writeAt = lastWriteAt, now.timeIntervalSince(writeAt) < coldStartWindow {
                return (.callingAPI, .streaming)
            }
            return (.idle, .waitingInput(prompt: nil))
        case "system", "summary", "file-history-snapshot", "ai-title", "last-prompt":
            // 装饰行：turn 间隙 / session 收尾 / 文件快照 / 异步晚到的会话标题 /
            // 用户输入草稿快照。它们不携带状态信号，且会在 turn 中间被 hook
            // 注入——映射成 idle 会把正在 working 的状态错误降级。
            // 返回 nil 让 AgentMonitor.carryover 接管，沿用上一拍非 idle 状态。
            // 注意：JSONLProbeContext 也用同一个 decorativeTypes 集合在 tick()
            // 期间跳过这些行的 lastStateSignalRecord 更新，正常路径走不到这里；
            // 这里是双重保险（initial bind 后只读到装饰行时仍需保护）。
            //
            // 例外：携带 errorMessage 的 system 行（claude 写 api_error / 校验失败时）
            // 仍归 error。装饰行通常不带 error 字段，所以这里几乎不会假阳性。
            if rec.errorMessage != nil {
                return (.error, .errored(reason: rec.errorMessage))
            }
            return nil
        case "permission-mode":
            // claude 在等用户授权（y/n / 接受 edit）→ 升级为 querying，UI 单独分桶显示 ?N。
            return (.querying, .querying(question: "permission"))
        case "attachment":
            // SessionStart hook / 附件刚被注入，紧接着会有 user → assistant 流。
            return (.callingAPI, .streaming)
        default:
            return nil
        }
    }
}

/// Codex 的 JSONL 末行 → 状态结论。
/// 状态主信号在 `event_msg` / `response_item` 的 `payload.type`。
enum CodexJSONLProbe {
    static func classify(record: JSONLRecord?,
                         lastWriteAt: Date?,
                         now: Date = Date(),
                         coldStartWindow: TimeInterval = 30,
                         stalenessThreshold: TimeInterval = 90) -> (state: AgentState, detail: AgentStateDetail)? {
        guard let rec = record else { return nil }

        if let writeAt = lastWriteAt, now.timeIntervalSince(writeAt) > stalenessThreshold {
            return (.idle, .unknown)
        }

        switch rec.type {
        case "event_msg":
            return classifyEventMsg(rec, lastWriteAt: lastWriteAt, now: now, coldStartWindow: coldStartWindow)
        case "response_item":
            return classifyResponseItem(rec)
        case "turn_context":
            // turn metadata，通常在 task_started 之前/之后插入一次。视为 turn 内中间状态。
            return (.callingAPI, .streaming)
        case "session_meta", "compacted":
            return (.idle, .unknown)
        default:
            return nil
        }
    }

    private static func classifyEventMsg(_ rec: JSONLRecord,
                                         lastWriteAt: Date?,
                                         now: Date,
                                         coldStartWindow: TimeInterval) -> (state: AgentState, detail: AgentStateDetail)? {
        switch rec.payloadType {
        case "task_started":
            return (.working, .toolUse(name: nil))
        case "task_complete", "turn_aborted", "context_compacted":
            // turn_aborted 不归 error：用户主动按 ESC 中断是常态，不应该高亮红色。
            // 真正的"agent 自爆"会走 payload.type=error 路径。
            return (.idle, .unknown)
        case "error":
            return (.error, .errored(reason: rec.errorMessage))
        case "agent_message":
            // assistant 完整消息写出；turn 通常还未 task_complete。
            return (.callingAPI, .streaming)
        case "patch_apply_end", "mcp_tool_call_end", "web_search_end":
            // 工具刚出结果，等下一轮 API。
            return (.callingAPI, .streaming)
        case "user_message":
            if let writeAt = lastWriteAt, now.timeIntervalSince(writeAt) < coldStartWindow {
                return (.callingAPI, .streaming)
            }
            return (.idle, .waitingInput(prompt: nil))
        case "token_count":
            // 后台 metric 行。它出现通常意味着 turn 内仍在跑；交给 freshness 决定。
            return (.callingAPI, .streaming)
        default:
            return nil
        }
    }

    private static func classifyResponseItem(_ rec: JSONLRecord) -> (state: AgentState, detail: AgentStateDetail)? {
        switch rec.payloadType {
        case "function_call", "custom_tool_call", "tool_search_call":
            return (.working, .toolUse(name: nil))
        case "function_call_output", "custom_tool_call_output", "tool_search_output":
            return (.callingAPI, .streaming)
        case "message", "reasoning":
            return (.callingAPI, .streaming)
        default:
            return nil
        }
    }
}
