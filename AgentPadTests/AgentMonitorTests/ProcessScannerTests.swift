//
//  ProcessScannerTests.swift
//  AgentPadTests
//

import XCTest
@testable import AgentPad

final class ProcessScannerTests: XCTestCase {
    func testListAllPIDsContainsSelf() throws {
        let pids = try ProcessScanner.listAllPIDs()
        XCTAssertTrue(pids.contains(getpid()))
    }

    func testNameOfSelf() {
        let name = ProcessScanner.name(of: getpid())
        XCTAssertNotNil(name)
        XCTAssertFalse(name!.isEmpty)
    }

    func testSnapshotOfSelfHasStartTimeAndPath() {
        let snap = ProcessScanner.snapshot(of: getpid())
        XCTAssertNotNil(snap)
        XCTAssertNotNil(snap?.executablePath)
        // 启动时间应位于过去 24h 内（测试运行的进程必然如此）
        if let s = snap {
            XCTAssertLessThan(s.startedAt, Date())
            XCTAssertGreaterThan(s.startedAt, Date(timeIntervalSinceNow: -86_400))
        }
    }

    func testMatchedPatternExactCaseInsensitive() {
        XCTAssertEqual(ProcessScanner.matchedPattern(name: "claude", patterns: ["claude"]), "claude")
        XCTAssertEqual(ProcessScanner.matchedPattern(name: "Claude", patterns: ["claude"]), "claude")
    }

    func testMatchedPatternPrefixWithSeparator() {
        XCTAssertEqual(ProcessScanner.matchedPattern(name: "codex-aarch64-apple-darwin", patterns: ["codex"]), "codex")
        XCTAssertEqual(ProcessScanner.matchedPattern(name: "claude_v2", patterns: ["claude"]), "claude")
        XCTAssertEqual(ProcessScanner.matchedPattern(name: "claude.x", patterns: ["claude"]), "claude")
    }

    func testMatchedPatternRejectsElectronChildren() {
        // 桌面 GUI 子进程（Claude.app 等）应被排除
        XCTAssertNil(ProcessScanner.matchedPattern(name: "Claude Helper", patterns: ["claude"]))
        XCTAssertNil(ProcessScanner.matchedPattern(name: "Claude Helper (Renderer)", patterns: ["claude"]))
        XCTAssertNil(ProcessScanner.matchedPattern(name: "Claude Helper (GPU)", patterns: ["claude"]))
    }

    func testMatchedPatternRejectsNonBoundaryPrefix() {
        // ClaudeCode 没分隔符，不算 CLI claude
        XCTAssertNil(ProcessScanner.matchedPattern(name: "ClaudeCode", patterns: ["claude"]))
        XCTAssertNil(ProcessScanner.matchedPattern(name: "claudia", patterns: ["claude"]))
    }

    func testIsDesktopAppExecutable() {
        // 桌面 GUI app 应被识别
        XCTAssertTrue(ProcessScanner.isDesktopAppExecutable("/Applications/Codex.app/Contents/Resources/codex"))
        XCTAssertTrue(ProcessScanner.isDesktopAppExecutable("/Applications/Claude.app/Contents/MacOS/Claude"))
        // CLI 工具常见安装路径不应被误伤
        XCTAssertFalse(ProcessScanner.isDesktopAppExecutable("/usr/local/bin/claude"))
        XCTAssertFalse(ProcessScanner.isDesktopAppExecutable("/opt/homebrew/bin/codex"))
        XCTAssertFalse(ProcessScanner.isDesktopAppExecutable("/Users/mac/.bun/bin/opencode"))
        XCTAssertFalse(ProcessScanner.isDesktopAppExecutable("/Users/mac/.local/bin/claude"))
        // /Applications 下但不是 .app 的（少见）
        XCTAssertFalse(ProcessScanner.isDesktopAppExecutable("/Applications/SomeScript.sh"))
    }

    func testIsWorkingCWD() {
        XCTAssertTrue(ProcessScanner.isWorkingCWD("/Users/mac/Zero/Proj"))
        XCTAssertTrue(ProcessScanner.isWorkingCWD("/Users/mac/.claude"))
        XCTAssertFalse(ProcessScanner.isWorkingCWD("/"))
        XCTAssertFalse(ProcessScanner.isWorkingCWD(""))
        XCTAssertFalse(ProcessScanner.isWorkingCWD("/System/Library"))
        XCTAssertFalse(ProcessScanner.isWorkingCWD("/Applications/Claude.app"))
        XCTAssertFalse(ProcessScanner.isWorkingCWD("/Library/Containers"))
        XCTAssertFalse(ProcessScanner.isWorkingCWD("/private/var/folders/xxx"))
    }

    func testScanFiltersByPatterns() throws {
        // 用一个高度独特的字符串保证不会命中任何系统进程
        let results = try ProcessScanner.scan(matching: ["xx-no-such-process-xx"])
        XCTAssertTrue(results.isEmpty)
    }

    func testArgv0BasenameOfSelf() {
        // xctest 自己的进程在 sysctl KERN_PROCARGS2 下应能拿到 argv[0]
        let argv0 = ProcessScanner.argv0Basename(of: getpid())
        XCTAssertNotNil(argv0)
        if let s = argv0 {
            XCTAssertFalse(s.isEmpty)
            // 不应含路径分隔符（basename 已剥离）
            XCTAssertFalse(s.contains("/"))
            // 不应含空格（basename 后段的参数已剥离）
            XCTAssertFalse(s.contains(" "))
        }
    }

    func testSnapshotUsesNameOverride() {
        let snap = ProcessScanner.snapshot(of: getpid(), nameOverride: "custom-name-xyz")
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.name, "custom-name-xyz")
    }
}
