//
//  JSONLSessionProbe.swift
//  AgentPad
//
//  Tail Claude Code 等 agent 写入的 session JSONL。
//  按 poll 节奏：每轮从持有的 fd 起读取新增字节，按行解析，缓存末条记录，
//  按末条记录类型映射状态。
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
    private(set) var lastWriteAt: Date?

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
                lastWriteAt = Date()
                didUpdate = true
            }
        }
        return didUpdate
    }

    deinit { close() }
}

/// JSONL 中单条记录的极简模型。仅解析状态判定必需的字段。
struct JSONLRecord {
    let type: String                  // "assistant" / "user" / "system" / ...
    let stopReason: String?           // assistant 行的终止原因；nil 视为未终止
    let toolUseName: String?          // 末条 content 含 tool_use 时的工具名
    let hasToolResult: Bool           // user 行带 tool_result 时为 true（用于「未闭合 tool_use」判断的反向）
    let sessionId: String?            // Claude Code 把 sessionId 写在每条记录里

    static func parse(line: String) -> JSONLRecord? {
        guard let data = line.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let dict = obj as? [String: Any] else { return nil }
        let type = (dict["type"] as? String) ?? ""
        guard !type.isEmpty else { return nil }
        let sessionId = dict["sessionId"] as? String ?? dict["session_id"] as? String

        // assistant 行：嵌套 message.content[].type 找 tool_use；message.stop_reason 判断流式终止。
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
        // 兼容平铺 stop_reason / tool_use 字段。
        if stopReason == nil {
            stopReason = dict["stop_reason"] as? String
        }
        return JSONLRecord(
            type: type,
            stopReason: stopReason,
            toolUseName: toolUseName,
            hasToolResult: hasToolResult,
            sessionId: sessionId
        )
    }
}

enum JSONLSessionProbe {
    /// 单条记录 + 距上次写入的间隔 → 状态结论。
    /// `coldStartWindow` 之内 user 末行视为 callingAPI（冷启动），超过则降级 idle。
    static func classify(record: JSONLRecord?,
                         lastWriteAt: Date?,
                         now: Date = Date(),
                         coldStartWindow: TimeInterval = 30) -> (state: AgentState, detail: AgentStateDetail)? {
        guard let rec = record else { return nil }
        switch rec.type {
        case "assistant":
            if let tool = rec.toolUseName {
                return (.working, .toolUse(name: tool))
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
        case "system":
            // Claude Code 在 turn 结束 / session 关闭时写 system 行，例如
            // subtype = stop_hook_summary / turn_duration / away_summary。
            // 含义都是「这一轮已经收尾」→ idle。
            return (.idle, .unknown)
        default:
            return nil
        }
    }
}
