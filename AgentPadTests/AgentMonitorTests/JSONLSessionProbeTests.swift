//
//  JSONLSessionProbeTests.swift
//  AgentPadTests
//

import XCTest
@testable import AgentPad

final class JSONLSessionProbeTests: XCTestCase {

    private func fixtureURL(_ name: String) -> URL {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures") ?? bundle.url(forResource: name, withExtension: "jsonl") else {
            fatalError("Missing fixture: \(name).jsonl")
        }
        return url
    }

    private func readLastRecord(of fixtureName: String) -> JSONLRecord? {
        let url = fixtureURL(fixtureName)
        let ctx = JSONLProbeContext(pid: 0, cwd: nil)
        ctx.bind(to: url)
        ctx.tick()
        return ctx.lastRecord
    }

    func testStreamingAssistantClassifiesAsCallingAPI() {
        let rec = readLastRecord(of: "streaming")
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .callingAPI)
        if case .streaming = cls?.detail { } else { XCTFail("expected .streaming") }
    }

    func testToolUseClassifiesAsWorking() {
        let rec = readLastRecord(of: "tool_use")
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .working)
        if case .toolUse(let name) = cls?.detail {
            XCTAssertEqual(name, "Bash")
        } else {
            XCTFail("expected .toolUse")
        }
    }

    func testCompletedAssistantClassifiesAsIdle() {
        let rec = readLastRecord(of: "completed")
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .idle)
    }

    func testWaitingUserWithinColdStartWindowClassifiesAsCallingAPI() {
        let rec = readLastRecord(of: "waiting_user")
        // 写入「刚刚」→ 冷启动窗口内 → callingAPI
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .callingAPI)
    }

    func testWaitingUserBeyondColdStartWindowFallsBackToIdle() {
        let rec = readLastRecord(of: "waiting_user")
        // 写入时间远早于现在 → 超出窗口 → idle
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date(timeIntervalSinceNow: -120))
        XCTAssertEqual(cls?.state, .idle)
    }

    /// 装饰行：system / summary / file-history-snapshot / ai-title / last-prompt。
    /// 早期实现把它们映射成 idle，会在 turn 中间（hook 注入 system 行时）
    /// 错误降级一个正在 working 的 group。现在统一返回 nil，让 carryover 接管。
    func testDecorativeTypesReturnNil() {
        let lines = [
            "{\"type\":\"system\",\"subtype\":\"turn_duration\",\"durationMs\":1234}",
            "{\"type\":\"summary\",\"summary\":\"...\"}",
            "{\"type\":\"file-history-snapshot\",\"messageId\":\"m1\"}",
            "{\"type\":\"ai-title\",\"title\":\"refactor menu\"}",
            "{\"type\":\"last-prompt\",\"text\":\"draft\"}"
        ]
        for line in lines {
            let rec = JSONLRecord.parse(line: line)
            XCTAssertNotNil(rec, "fixture parse failed: \(line)")
            let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date())
            XCTAssertNil(cls, "decorative type should not classify: \(rec!.type)")
        }
    }

    // MARK: - C1: freshness / new types / timestamp 解析

    func testStalenessForcesIdleEvenWhenRecordSuggestsWorking() {
        // 末行明明是 tool_use（→ working），但 timestamp 太老 → staleness 强制 idle。
        let rec = JSONLRecord.parse(line:
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\"}]}}")
        let cls = JSONLSessionProbe.classify(record: rec,
                                             lastWriteAt: Date(timeIntervalSinceNow: -200),
                                             stalenessThreshold: 90)
        XCTAssertEqual(cls?.state, .idle)
    }

    func testFreshToolUseStaysAsWorking() {
        // 同一记录写入「刚刚」→ 不 stale → 仍判 working。
        let rec = JSONLRecord.parse(line:
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\"}]}}")
        let cls = JSONLSessionProbe.classify(record: rec,
                                             lastWriteAt: Date(),
                                             stalenessThreshold: 90)
        XCTAssertEqual(cls?.state, .working)
    }

    func testPermissionModeClassifiesAsQuerying() {
        let rec = JSONLRecord.parse(line: "{\"type\":\"permission-mode\",\"mode\":\"acceptEdits\"}")
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .querying)
        if case .querying(let q) = cls?.detail {
            XCTAssertEqual(q, "permission")
        } else {
            XCTFail("expected .querying(\"permission\")")
        }
    }

    /// permission-mode 行不带 timestamp、且 fileMtime 已老 → 仍应判 querying，
    /// 不被 staleness 闸门误降级。覆盖"用户离开座位 5 分钟没回 y/n"场景。
    func testPermissionModeBypassesStalenessGate() {
        let rec = JSONLRecord.parse(line: "{\"type\":\"permission-mode\",\"mode\":\"default\"}")
        let cls = JSONLSessionProbe.classify(record: rec,
                                             lastWriteAt: Date(timeIntervalSinceNow: -600),
                                             stalenessThreshold: 90)
        XCTAssertEqual(cls?.state, .querying)
    }

    /// permission-mode 行 lastWriteAt 完全缺失（rec.timestamp 和 fileMtime 都 nil）
    /// 时也要判 querying。
    func testPermissionModeWithNilLastWriteAtClassifiesAsQuerying() {
        let rec = JSONLRecord.parse(line: "{\"type\":\"permission-mode\"}")
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: nil)
        XCTAssertEqual(cls?.state, .querying)
    }

    // MARK: - error 路径

    /// assistant + stop_reason="error" → error，错误信息透出。
    func testAssistantErrorStopReasonClassifiesAsError() {
        let rec = JSONLRecord.parse(line:
            "{\"type\":\"assistant\",\"message\":{\"stop_reason\":\"error\",\"error\":\"overloaded_error: try again\"}}")
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .error)
        if case .errored(let reason) = cls?.detail {
            XCTAssertEqual(reason, "overloaded_error: try again")
        } else {
            XCTFail("expected .errored")
        }
    }

    /// system 装饰行但携带 error 字段 → 仍归 error（不被装饰行的 nil 路径吃掉）。
    func testSystemWithErrorFieldClassifiesAsError() {
        let rec = JSONLRecord.parse(line:
            "{\"type\":\"system\",\"subtype\":\"api_error\",\"error\":\"401 invalid_api_key\"}")
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .error)
        if case .errored(let reason) = cls?.detail {
            XCTAssertEqual(reason, "401 invalid_api_key")
        } else {
            XCTFail("expected .errored")
        }
    }

    /// error 太旧（超过 staleness）→ 降级 idle。error 不粘性的契约由 staleness 闸门兜底。
    func testStaleErrorFallsBackToIdle() {
        let rec = JSONLRecord.parse(line:
            "{\"type\":\"assistant\",\"message\":{\"stop_reason\":\"error\",\"error\":\"x\"}}")
        let cls = JSONLSessionProbe.classify(record: rec,
                                             lastWriteAt: Date(timeIntervalSinceNow: -200),
                                             stalenessThreshold: 90)
        XCTAssertEqual(cls?.state, .idle)
    }

    func testAttachmentClassifiesAsCallingAPI() {
        let rec = JSONLRecord.parse(line:
            "{\"type\":\"attachment\",\"attachment\":{\"type\":\"hook_success\",\"hookEvent\":\"SessionStart\"}}")
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .callingAPI)
    }

    func testRecordTimestampIsParsedIntoDate() {
        let rec = JSONLRecord.parse(line:
            "{\"type\":\"user\",\"timestamp\":\"2026-06-02T06:05:08.570Z\"}")
        XCTAssertNotNil(rec?.timestamp)
        // 校验 timezone：UTC 06:05:08
        let cal = Calendar(identifier: .gregorian)
        var c = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: rec!.timestamp!)
        XCTAssertEqual(c.year, 2026)
        XCTAssertEqual(c.month, 6)
        XCTAssertEqual(c.day, 2)
        XCTAssertEqual(c.hour, 6)
        XCTAssertEqual(c.minute, 5)
        XCTAssertEqual(c.second, 8)
    }

    func testLastWriteAtUsesRecordTimestampNotPollTime() throws {
        // 当 record 自带 timestamp 时，JSONLProbeContext.lastWriteAt 应该取它，
        // 而不是用「读到这条行的本地时刻」（否则 staleness 会永久不触发）。
        let tmp = NSTemporaryDirectory() + "agentpad-ts-\(UUID().uuidString).jsonl"
        let url = URL(fileURLWithPath: tmp)
        defer { try? FileManager.default.removeItem(at: url) }
        let recordedTs = "2026-06-02T06:05:08.570Z"
        let line = "{\"type\":\"user\",\"timestamp\":\"\(recordedTs)\"}\n"
        try line.write(to: url, atomically: true, encoding: .utf8)

        let ctx = JSONLProbeContext(pid: 0, cwd: nil)
        ctx.bind(to: url)
        ctx.tick()
        let expected = JSONLRecord.parseTimestamp(recordedTs)
        XCTAssertEqual(ctx.lastWriteAt, expected)
    }

    func testIncrementalTickPicksUpAppendedLines() throws {
        let tmp = NSTemporaryDirectory() + "agentpad-test-\(UUID().uuidString).jsonl"
        let url = URL(fileURLWithPath: tmp)
        defer { try? FileManager.default.removeItem(at: url) }

        try "".write(to: url, atomically: true, encoding: .utf8)
        let ctx = JSONLProbeContext(pid: 0, cwd: nil)
        ctx.bind(to: url)
        XCTAssertNil(ctx.lastRecord)

        // 追加一条 user 行
        let h1 = try FileHandle(forWritingTo: url)
        h1.seekToEndOfFile()
        h1.write("{\"type\":\"user\",\"sessionId\":\"s\"}\n".data(using: .utf8)!)
        h1.closeFile()
        XCTAssertTrue(ctx.tick())
        XCTAssertEqual(ctx.lastRecord?.type, "user")

        // 追加一条 assistant 含 tool_use
        let h2 = try FileHandle(forWritingTo: url)
        h2.seekToEndOfFile()
        h2.write("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Edit\"}]}}\n".data(using: .utf8)!)
        h2.closeFile()
        XCTAssertTrue(ctx.tick())
        XCTAssertEqual(ctx.lastRecord?.type, "assistant")
        XCTAssertEqual(ctx.lastRecord?.toolUseName, "Edit")
    }

    // MARK: - P0: ai-title + carryover when classify returns nil

    /// ctx 在装饰行后仍把前一条 user/assistant 留作 lastStateSignalRecord，
    /// 避免 turn 间隙 system/ai-title 把状态信号挤走。
    /// 这是修复"Claude 完全失真"日志现象的核心契约。
    func testLastStateSignalRecordSkipsDecorativeRows() throws {
        let tmp = NSTemporaryDirectory() + "agentpad-signal-\(UUID().uuidString).jsonl"
        let url = URL(fileURLWithPath: tmp)
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = [
            "{\"type\":\"user\",\"sessionId\":\"s\",\"timestamp\":\"2026-06-02T10:00:00.000Z\"}\n",
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\"}]},\"timestamp\":\"2026-06-02T10:00:05.000Z\"}\n",
            "{\"type\":\"system\",\"subtype\":\"turn_duration\"}\n",
            "{\"type\":\"file-history-snapshot\",\"messageId\":\"m1\"}\n",
            "{\"type\":\"ai-title\",\"title\":\"x\"}\n"
        ]
        try lines.joined().write(to: url, atomically: true, encoding: .utf8)

        let ctx = JSONLProbeContext(pid: 0, cwd: nil)
        ctx.bind(to: url)
        ctx.tick()

        // 物理末行是装饰行
        XCTAssertEqual(ctx.lastRecord?.type, "ai-title")
        // 状态信号末行仍是 assistant + tool_use
        XCTAssertEqual(ctx.lastStateSignalRecord?.type, "assistant")
        XCTAssertEqual(ctx.lastStateSignalRecord?.toolUseName, "Bash")
        XCTAssertEqual(ctx.lastStateSignalAt,
                       JSONLRecord.parseTimestamp("2026-06-02T10:00:05.000Z"))
    }

    /// 当只读到装饰行时 lastStateSignalRecord 应保持 nil（不强行降级到装饰行）。
    func testLastStateSignalRecordNilWhenOnlyDecorativeSeen() throws {
        let tmp = NSTemporaryDirectory() + "agentpad-decor-\(UUID().uuidString).jsonl"
        let url = URL(fileURLWithPath: tmp)
        defer { try? FileManager.default.removeItem(at: url) }
        try "{\"type\":\"system\",\"subtype\":\"turn_duration\"}\n".write(to: url, atomically: true, encoding: .utf8)
        let ctx = JSONLProbeContext(pid: 0, cwd: nil)
        ctx.bind(to: url)
        ctx.tick()
        XCTAssertEqual(ctx.lastRecord?.type, "system")
        XCTAssertNil(ctx.lastStateSignalRecord)
        XCTAssertNil(ctx.lastStateSignalAt)
    }

    /// classify==nil 时（未知 type / lastRecord==nil），上一拍为 working 且未 stale
    /// → 沿用 working，避免 UI 错误降级。
    func testCarryoverReusesPrevWorkingWithinStaleness() {
        let now = Date()
        let prev = AgentProject(
            id: "/proj|claude",
            cwd: "/proj",
            agentKind: "claude",
            state: .working,
            detail: .toolUse(name: "Edit"),
            source: .jsonl(sessionId: "abc"),
            instanceCount: 1,
            primaryPid: 1234,
            earliestStartedAt: now.addingTimeInterval(-10),
            sessionId: "abc",
            lastActivityAt: now.addingTimeInterval(-5)
        )
        let carry = AgentMonitor.carryover(
            prev: prev,
            key: "/proj|claude",
            cwd: "/proj",
            agentKind: "claude",
            instanceCount: 1,
            primaryPid: 1234,
            earliestStartedAt: prev.earliestStartedAt,
            staleness: 90,
            now: now
        )
        XCTAssertNotNil(carry)
        XCTAssertEqual(carry?.state, .working)
        if case .toolUse(let name) = carry?.detail {
            XCTAssertEqual(name, "Edit")
        } else {
            XCTFail("expected .toolUse(Edit) carried over")
        }
        // lastActivityAt 必须保留 prev 的，不能刷新成 now——否则 staleness 永远不触发。
        XCTAssertEqual(carry?.lastActivityAt, prev.lastActivityAt)
    }

    /// 上一拍 lastActivityAt 超出 staleness → 不沿用，返回 nil（调用方走 PTY 兜底）。
    func testCarryoverDropsWhenPrevStale() {
        let now = Date()
        let prev = AgentProject(
            id: "/proj|claude", cwd: "/proj", agentKind: "claude",
            state: .callingAPI, detail: .streaming,
            source: .jsonl(sessionId: "abc"),
            instanceCount: 1, primaryPid: 1234,
            earliestStartedAt: now.addingTimeInterval(-1000),
            sessionId: "abc",
            lastActivityAt: now.addingTimeInterval(-200)  // 超出 90s
        )
        let carry = AgentMonitor.carryover(
            prev: prev,
            key: "/proj|claude", cwd: "/proj", agentKind: "claude",
            instanceCount: 1, primaryPid: 1234,
            earliestStartedAt: prev.earliestStartedAt,
            staleness: 90,
            now: now
        )
        XCTAssertNil(carry)
    }

    /// 上一拍本来就是 idle → 沿用没意义，返回 nil。
    func testCarryoverIgnoresIdlePrev() {
        let now = Date()
        let prev = AgentProject(
            id: "/proj|claude", cwd: "/proj", agentKind: "claude",
            state: .idle, detail: .unknown,
            source: .jsonl(sessionId: "abc"),
            instanceCount: 1, primaryPid: 1234,
            earliestStartedAt: now.addingTimeInterval(-10),
            sessionId: "abc",
            lastActivityAt: now.addingTimeInterval(-5)
        )
        XCTAssertNil(AgentMonitor.carryover(
            prev: prev,
            key: "/proj|claude", cwd: "/proj", agentKind: "claude",
            instanceCount: 1, primaryPid: 1234,
            earliestStartedAt: prev.earliestStartedAt,
            staleness: 90, now: now
        ))
    }

    /// 上一拍 lastActivityAt==nil（例如来自 PTY 来源）→ 没法判 staleness → 返回 nil。
    func testCarryoverDropsWhenPrevHasNoActivityTimestamp() {
        let now = Date()
        let prev = AgentProject(
            id: "/proj|claude", cwd: "/proj", agentKind: "claude",
            state: .working, detail: .toolUse(name: nil),
            source: .pty(snippet: "..."),
            instanceCount: 1, primaryPid: 1234,
            earliestStartedAt: now.addingTimeInterval(-10),
            sessionId: nil,
            lastActivityAt: nil
        )
        XCTAssertNil(AgentMonitor.carryover(
            prev: prev,
            key: "/proj|claude", cwd: "/proj", agentKind: "claude",
            instanceCount: 1, primaryPid: 1234,
            earliestStartedAt: prev.earliestStartedAt,
            staleness: 90, now: now
        ))
    }

    /// prev==nil（首次出现的 group）→ 没东西沿用。
    func testCarryoverDropsWhenPrevIsNil() {
        XCTAssertNil(AgentMonitor.carryover(
            prev: nil,
            key: "/proj|claude", cwd: "/proj", agentKind: "claude",
            instanceCount: 1, primaryPid: 1234,
            earliestStartedAt: Date(),
            staleness: 90, now: Date()
        ))
    }

    /// 上一拍是 error → 不沿用，让下一拍立即覆盖。error 不粘性的契约。
    /// 真实场景：claude 写出 stop_reason="error" → carryover 不该让红色 badge 残留 90s。
    func testCarryoverDropsWhenPrevIsError() {
        let now = Date()
        let prev = AgentProject(
            id: "/proj|claude", cwd: "/proj", agentKind: "claude",
            state: .error, detail: .errored(reason: "api error"),
            source: .jsonl(sessionId: "abc"),
            instanceCount: 1, primaryPid: 1234,
            earliestStartedAt: now.addingTimeInterval(-10),
            sessionId: "abc",
            lastActivityAt: now.addingTimeInterval(-5)  // 在 staleness 窗口内
        )
        XCTAssertNil(AgentMonitor.carryover(
            prev: prev,
            key: "/proj|claude", cwd: "/proj", agentKind: "claude",
            instanceCount: 1, primaryPid: 1234,
            earliestStartedAt: prev.earliestStartedAt,
            staleness: 90, now: now
        ))
    }
}
