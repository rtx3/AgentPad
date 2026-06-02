//
//  CodexJSONLProbeTests.swift
//  AgentPadTests
//
//  Codex jsonl 的 payload.type → 状态映射。
//

import XCTest
@testable import AgentPad

final class CodexJSONLProbeTests: XCTestCase {

    private func makeRecord(type: String, payloadType: String, timestamp: String? = nil) -> JSONLRecord? {
        var json = "{\"type\":\"\(type)\",\"payload\":{\"type\":\"\(payloadType)\"}"
        if let ts = timestamp { json += ",\"timestamp\":\"\(ts)\"" }
        json += "}"
        return JSONLRecord.parse(line: json)
    }

    func testTaskStartedIsWorking() {
        let rec = makeRecord(type: "event_msg", payloadType: "task_started")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .working)
    }

    func testTaskCompleteIsIdle() {
        let rec = makeRecord(type: "event_msg", payloadType: "task_complete")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .idle)
    }

    func testTurnAbortedIsIdle() {
        let rec = makeRecord(type: "event_msg", payloadType: "turn_aborted")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .idle)
    }

    func testAgentMessageIsCallingAPI() {
        let rec = makeRecord(type: "event_msg", payloadType: "agent_message")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .callingAPI)
    }

    func testTokenCountIsCallingAPI() {
        // 后台 metric 行；本身无强语义，按 freshness 决定，未 stale 时视为 turn 内中间状态。
        let rec = makeRecord(type: "event_msg", payloadType: "token_count")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .callingAPI)
    }

    func testPatchApplyEndIsCallingAPI() {
        let rec = makeRecord(type: "event_msg", payloadType: "patch_apply_end")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .callingAPI)
    }

    func testFunctionCallIsWorking() {
        let rec = makeRecord(type: "response_item", payloadType: "function_call")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .working)
    }

    func testFunctionCallOutputIsCallingAPI() {
        let rec = makeRecord(type: "response_item", payloadType: "function_call_output")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .callingAPI)
    }

    func testCustomToolCallIsWorking() {
        let rec = makeRecord(type: "response_item", payloadType: "custom_tool_call")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .working)
    }

    func testReasoningIsCallingAPI() {
        let rec = makeRecord(type: "response_item", payloadType: "reasoning")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .callingAPI)
    }

    func testSessionMetaIsIdle() {
        let rec = JSONLRecord.parse(line: "{\"type\":\"session_meta\",\"meta\":{}}")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertEqual(cls?.state, .idle)
    }

    func testStaleTaskStartedFallsBackToIdle() {
        // 末行 task_started（→ working），但 timestamp 太老 → staleness 强制 idle。
        let rec = makeRecord(type: "event_msg", payloadType: "task_started")
        let cls = CodexJSONLProbe.classify(record: rec,
                                           lastWriteAt: Date(timeIntervalSinceNow: -200),
                                           stalenessThreshold: 90)
        XCTAssertEqual(cls?.state, .idle)
    }

    func testUserMessageOutsideColdStartIsIdle() {
        // 等同 claude 路径：user_message 末行超出冷启动窗口（但未 stale）→ idle waitingInput。
        let rec = makeRecord(type: "event_msg", payloadType: "user_message")
        let cls = CodexJSONLProbe.classify(record: rec,
                                           lastWriteAt: Date(timeIntervalSinceNow: -60),
                                           coldStartWindow: 30,
                                           stalenessThreshold: 90)
        XCTAssertEqual(cls?.state, .idle)
    }

    func testUnknownPayloadTypeReturnsNil() {
        let rec = makeRecord(type: "event_msg", payloadType: "totally_made_up_event")
        let cls = CodexJSONLProbe.classify(record: rec, lastWriteAt: Date())
        XCTAssertNil(cls)
    }
}
