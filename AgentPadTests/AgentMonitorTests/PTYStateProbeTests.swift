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
        // querying 桶被引入后，idle 桶默认是空的——没有关键词能直接命中 idle。
        // 这里只验证未命中任何桶时返回 nil（idle 仍由调用方在 PTY 沉默期自行判定）。
        let text = "some idle terminal background\n$ "
        let r = PTYStateProbe.classify(text: text)
        XCTAssertNil(r)
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

    // MARK: - 新版 Claude Code（4.6+）烹饪动词系列实测

    func testChurnedClassifiesAsCallingAPI() {
        let text = "✻ Churned for 3m 29s"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .callingAPI)
    }

    func testCaramelizingClassifiesAsCallingAPI() {
        let text = "✢ Caramelizing… (12s · still thinking with xhigh effort)"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .callingAPI)
    }

    func testProgressGlyphAloneClassifiesAsCallingAPI() {
        let text = "✻ Some future verb we have not seen yet"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .callingAPI)
    }

    func testToInterruptVariantStillHitsWorking() {
        let text = "Running Bash\nctrl+c to interrupt"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .working)
    }

    // MARK: - querying 关键词

    /// "do you want to" 现在归 querying 而不是 idle。
    func testDoYouWantToClassifiesAsQuerying() {
        let text = "Do you want to proceed?"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .querying)
    }

    func testYNPromptClassifiesAsQuerying() {
        let text = "overwrite file? (y/n)"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .querying)
    }

    /// querying 优先级高于 working。
    func testQueryingTakesPriorityOverWorking() {
        let text = "do you want to continue?\nctrl+c to interrupt"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .querying)
    }

    // MARK: - 末行 ? 形态判定（关键词没命中时的兜底）

    /// 末行用英文 ? 收尾 → querying。
    func testTrailingQuestionMarkClassifiesAsQuerying() {
        let text = "Some unrelated context here\nWhat would you prefer?"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .querying)
        XCTAssertEqual(r?.snippet, "?")
    }

    /// 中文全角问号也算。
    func testTrailingFullWidthQuestionMarkClassifiesAsQuerying() {
        let text = "你倾向哪个方案？"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .querying)
    }

    /// 末行后面有空行 / 装饰 spinner 时，扫到的"最后一个非空行"仍命中。
    func testTrailingQuestionFollowedByBlankLinesHits() {
        let text = "Which option do you want?\n\n   \n"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .querying)
    }

    /// 末行不是 ? 不应命中（避免假阳性，例如普通终端输出）。
    func testNonQuestionTrailingDoesNotHit() {
        let text = "Build succeeded.\n$ "
        let r = PTYStateProbe.classify(text: text)
        XCTAssertNil(r)
    }

    /// 关键词命中比形态命中优先：snippet 仍是关键词而不是 "?"。
    func testKeywordTakesPriorityOverQuestionMarkShape() {
        let text = "Do you want to continue?"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .querying)
        XCTAssertEqual(r?.snippet, "do you want to")
    }

    // MARK: - error 关键词

    func testApiErrorKeywordClassifiesAsError() {
        let text = "Something went wrong\nAPI Error: try again later"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .error)
        XCTAssertEqual(r?.snippet, "api error")
        // detail.reason 应为 nil：keyword 本身没信息量，不该污染副行。
        if case .errored(let reason) = r?.detail {
            XCTAssertNil(reason)
        } else {
            XCTFail("expected .errored(nil)")
        }
    }

    func testRateLimitKeywordClassifiesAsError() {
        let text = "rate limit exceeded, retrying"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .error)
    }

    /// HTTP 状态码 401 命中 error（也是严格关键词）。
    func test401KeywordClassifiesAsError() {
        let text = "Request failed with 401 Unauthorized"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .error)
    }

    /// error 优先级高于 working：terminal 既有 spinner 又有 api error 时报 error。
    func testErrorTakesPriorityOverWorking() {
        let text = "api error: overloaded\nesc to interrupt"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .error)
    }

    /// querying 关键词比 error 优先（"do you want to" 是用户主动 prompt，
    /// 即使附近文本有 "api error" 字样也优先按 querying 处理）。
    func testQueryingKeywordTakesPriorityOverError() {
        let text = "api error: overloaded\nDo you want to retry?"
        let r = PTYStateProbe.classify(text: text)
        XCTAssertEqual(r?.state, .querying)
    }

    /// 普通"error:" 输出不命中（避免假阳性，确保严格关键词的设计目标）。
    func testGenericErrorWordDoesNotHit() {
        let text = "error: file not found\n$ "
        let r = PTYStateProbe.classify(text: text)
        XCTAssertNil(r)
    }
}
