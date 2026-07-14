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
        // Claude Code daemon 预热的 spare 进程 cwd 在 /private/tmp 下
        XCTAssertFalse(ProcessScanner.isWorkingCWD("/private/tmp/cc-daemon-501/d78168b1/spare"))
        XCTAssertFalse(ProcessScanner.isWorkingCWD("/tmp/cc-daemon-501/spare"))
    }

    func testIsInfrastructureArgs() {
        // Claude Code 基础设施进程应被识别
        XCTAssertTrue(ProcessScanner.isInfrastructureArgs(
            ["daemon", "run", "--json-path", "/Users/mac/.claude/daemon.json"]))
        XCTAssertTrue(ProcessScanner.isInfrastructureArgs(
            ["bg-spare", "--bg-spare", "/tmp/cc-daemon-501/x/spare/a.claim.sock"]))
        XCTAssertTrue(ProcessScanner.isInfrastructureArgs(
            ["bg-pty-host", "--bg-pty-host", "/tmp/cc-daemon-501/x/spare/a.pty.sock"]))
        XCTAssertTrue(ProcessScanner.isInfrastructureArgs(
            ["--bg-pty-host", "/tmp/cc-daemon-501/x/pty/b"]))
        XCTAssertTrue(ProcessScanner.isInfrastructureArgs(
            ["--bg-spare", "/tmp/cc-daemon-501/x/spare/a.claim.sock"]))
        // 真实会话不应被误伤
        XCTAssertFalse(ProcessScanner.isInfrastructureArgs([]))
        XCTAssertFalse(ProcessScanner.isInfrastructureArgs(["--resume", "0421bc24-469f"]))
        XCTAssertFalse(ProcessScanner.isInfrastructureArgs(["--session-id", "73b0d7e4", "--fork-session"]))
        XCTAssertFalse(ProcessScanner.isInfrastructureArgs(["-p", "hello"]))
    }

    func testArgvArgumentsOfSelf() {
        // xctest 进程自身的 argv 应可读取（可能为空参数列表，但不应崩溃）
        let args = ProcessScanner.argvArguments(of: getpid())
        XCTAssertNotNil(args)
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

    // MARK: - PIDNegativeCache

    func testNegativeCacheMarkAndHit() {
        let cache = PIDNegativeCache(minAgeSec: 10)
        let startedAt = Date(timeIntervalSinceNow: -60).timeIntervalSince1970
        XCTAssertFalse(cache.isRejected(pid: 12345, startedAt: startedAt))
        cache.markRejected(pid: 12345, startedAt: startedAt, now: Date())
        XCTAssertTrue(cache.isRejected(pid: 12345, startedAt: startedAt))
    }

    func testNegativeCacheSkipsYoungProcess() {
        // 进程年龄 < minAgeSec 时不缓存：Node CLI 启动后才设置 process.title，
        // 过早缓存会把尚未改名的 claude 进程永久判为不命中。
        let cache = PIDNegativeCache(minAgeSec: 10)
        let startedAt = Date(timeIntervalSinceNow: -3).timeIntervalSince1970
        cache.markRejected(pid: 12345, startedAt: startedAt, now: Date())
        XCTAssertFalse(cache.isRejected(pid: 12345, startedAt: startedAt))
        XCTAssertEqual(cache.count, 0)
    }

    func testNegativeCachePIDReuseInvalidates() {
        // PID 复用：同 pid 不同 startedAt 不应命中缓存。
        let cache = PIDNegativeCache(minAgeSec: 10)
        let oldStart = Date(timeIntervalSinceNow: -3600).timeIntervalSince1970
        cache.markRejected(pid: 500, startedAt: oldStart, now: Date())
        let newStart = Date(timeIntervalSinceNow: -60).timeIntervalSince1970
        XCTAssertFalse(cache.isRejected(pid: 500, startedAt: newStart))
    }

    func testNegativeCacheCompactRemovesDeadPIDs() {
        let cache = PIDNegativeCache(minAgeSec: 10)
        let startedAt = Date(timeIntervalSinceNow: -60).timeIntervalSince1970
        cache.markRejected(pid: 100, startedAt: startedAt, now: Date())
        cache.markRejected(pid: 200, startedAt: startedAt, now: Date())
        XCTAssertEqual(cache.count, 2)
        cache.compact(keepingAlive: [100])
        XCTAssertEqual(cache.count, 1)
        XCTAssertTrue(cache.isRejected(pid: 100, startedAt: startedAt))
        XCTAssertFalse(cache.isRejected(pid: 200, startedAt: startedAt))
    }

    func testNegativeCacheRemoveAll() {
        let cache = PIDNegativeCache(minAgeSec: 10)
        let startedAt = Date(timeIntervalSinceNow: -60).timeIntervalSince1970
        cache.markRejected(pid: 100, startedAt: startedAt, now: Date())
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
        XCTAssertFalse(cache.isRejected(pid: 100, startedAt: startedAt))
    }

    func testScanWithNegativeCachePopulatesAndStaysConsistent() throws {
        // 第一轮扫描填充负缓存；第二轮结果应与第一轮一致（缓存不改变语义）。
        let cache = PIDNegativeCache(minAgeSec: 10)
        let first = try ProcessScanner.scan(matching: ["xx-no-such-process-xx"], negativeCache: cache)
        XCTAssertTrue(first.isEmpty)
        XCTAssertGreaterThan(cache.count, 0)
        let second = try ProcessScanner.scan(matching: ["xx-no-such-process-xx"], negativeCache: cache)
        XCTAssertTrue(second.isEmpty)
    }
}
