//
//  PTYStateProbeTests.swift
//  AgentPadTests
//

import XCTest
@testable import AgentPad

final class PTYStateProbeTests: XCTestCase {
    func testWorkingKeywordHits() {
        let text = "running tests...\nesc to interrupt"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .working)
    }

    func testCallingAPIKeywordHits() {
        let text = "Thinking…\nstreaming response"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .callingAPI)
    }

    func testIdleKeywordHits() {
        let text = "Do you want to continue?"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .idle)
    }

    func testNoKeywordReturnsNil() {
        let text = "some unrelated terminal noise\n$ ls -la"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertNil(r)
    }

    func testWorkingTakesPriorityOverCallingAPI() {
        let text = "Thinking…\nesc to interrupt"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .working)
    }
}
