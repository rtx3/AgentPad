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

    func testSystemTypeClassifiesAsIdle() {
        // Claude Code 在 turn 收尾时写 type:"system" 行：stop_hook_summary / turn_duration / away_summary
        let rec = JSONLRecord.parse(line:
            "{\"type\":\"system\",\"subtype\":\"turn_duration\",\"durationMs\":1234}")
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .idle)
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

    func testPermissionModeClassifiesAsWaitingInput() {
        let rec = JSONLRecord.parse(line: "{\"type\":\"permission-mode\",\"mode\":\"acceptEdits\"}")
        let cls = JSONLSessionProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .idle)
        if case .waitingInput(let prompt) = cls?.detail {
            XCTAssertEqual(prompt, "permission")
        } else {
            XCTFail("expected .waitingInput(\"permission\")")
        }
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
}
