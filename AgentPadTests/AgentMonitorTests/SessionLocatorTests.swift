//
//  SessionLocatorTests.swift
//  AgentPadTests
//

import XCTest
@testable import AgentPad

final class SessionLocatorTests: XCTestCase {
    func testCWDEncodingReplacesSlashesWithDashes() {
        XCTAssertEqual(ClaudeCodeSessionLocator.encode(cwd: "/Users/mac/foo"), "-Users-mac-foo")
        XCTAssertEqual(ClaudeCodeSessionLocator.encode(cwd: "/"), "-")
    }

    func testLocateReturnsLatestMTime() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agentpad-loc-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        let cwd = "/foo/bar"
        let projectDir = tmp.appendingPathComponent(ClaudeCodeSessionLocator.encode(cwd: cwd), isDirectory: true)
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let older = projectDir.appendingPathComponent("old.jsonl")
        let newer = projectDir.appendingPathComponent("new.jsonl")
        try "".write(to: older, atomically: true, encoding: .utf8)
        // 让 newer mtime 严格大于 older
        try "".write(to: newer, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: older.path)
        try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: newer.path)

        let locator = ClaudeCodeSessionLocator()
        let found = locator.locate(pid: 0, cwd: cwd, sessionRoot: tmp.path)
        XCTAssertEqual(found?.lastPathComponent, "new.jsonl")
    }

    func testLocateReturnsNilWhenDirectoryMissing() {
        let locator = ClaudeCodeSessionLocator()
        let found = locator.locate(pid: 0, cwd: "/nonexistent/path", sessionRoot: "/tmp/does-not-exist-\(UUID().uuidString)")
        XCTAssertNil(found)
    }

    func testLocateFallbackWhenCWDNilUsesRecentlyWrittenProject() throws {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agentpad-loc-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // 两个项目目录：旧的（2 小时前）+ 新的（刚刚）
        let oldDir = tmp.appendingPathComponent("-foo-old", isDirectory: true)
        let newDir = tmp.appendingPathComponent("-foo-new", isDirectory: true)
        try fm.createDirectory(at: oldDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        let oldFile = oldDir.appendingPathComponent("s.jsonl")
        let newFile = newDir.appendingPathComponent("s.jsonl")
        try "".write(to: oldFile, atomically: true, encoding: .utf8)
        try "".write(to: newFile, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: oldFile.path)
        try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: newFile.path)

        // cwd=nil → 应回退到「最近活跃」的项目
        let locator = ClaudeCodeSessionLocator()
        let found = locator.locate(pid: 0, cwd: nil, sessionRoot: tmp.path)
        XCTAssertEqual(found?.deletingLastPathComponent().lastPathComponent, "-foo-new")
    }

    func testCodexLocatorRecursivelyFindsLatestJSONL() throws {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agentpad-codex-\(UUID().uuidString)", isDirectory: true)
        // 模拟 ~/.codex/sessions/2026/05/29/abc.jsonl
        let nested = tmp.appendingPathComponent("2026/05/29", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let older = nested.appendingPathComponent("rollout-old.jsonl")
        let newer = nested.appendingPathComponent("rollout-new.jsonl")
        try "".write(to: older, atomically: true, encoding: .utf8)
        try "".write(to: newer, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: older.path)
        try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: newer.path)

        let locator = CodexSessionLocator()
        let found = locator.locate(pid: 0, cwd: nil, sessionRoot: tmp.path)
        XCTAssertEqual(found?.lastPathComponent, "rollout-new.jsonl")
    }

    // MARK: - CachingSessionLocator

    /// 记录底层 locate 调用次数的桩，用于断言缓存是否生效。
    private final class CountingLocator: SessionLocator {
        private(set) var calls = 0
        var result: URL?
        func locate(pid: pid_t, cwd: String?, sessionRoot: String) -> URL? {
            calls += 1
            return result
        }
    }

    private func makeTempRoot() throws -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agentpad-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    func testCachingLocatorSkipsRescanWhenRootQuiet() throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("s.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let counting = CountingLocator()
        counting.result = file
        let caching = CachingSessionLocator(wrapping: counting, watcherLatency: 0.1)

        // 首次：真实扫描
        XCTAssertEqual(caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path)?.path, file.path)
        XCTAssertEqual(counting.calls, 1)
        // watcher 初始 dirty 已被消费；root 无变更 → 后续命中缓存
        XCTAssertEqual(caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path)?.path, file.path)
        XCTAssertEqual(caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path)?.path, file.path)
        XCTAssertEqual(counting.calls, 1)
    }

    func testCachingLocatorCachesNilMiss() throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let counting = CountingLocator()
        counting.result = nil
        let caching = CachingSessionLocator(wrapping: counting, watcherLatency: 0.1)

        XCTAssertNil(caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path))
        XCTAssertNil(caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path))
        XCTAssertEqual(counting.calls, 1)
    }

    func testCachingLocatorRescansAfterFileChange() throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("s.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let counting = CountingLocator()
        counting.result = file
        let caching = CachingSessionLocator(wrapping: counting, watcherLatency: 0.1)

        XCTAssertNotNil(caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path))
        XCTAssertEqual(counting.calls, 1)

        // 落一个新文件；FSEvents（latency 0.1s）片刻后置 dirty
        let newer = tmp.appendingPathComponent("s2.jsonl")
        try "".write(to: newer, atomically: true, encoding: .utf8)
        counting.result = newer

        // 轮询等待失效生效（deferred 投递 + 共享回调队列，给足余量）
        let deadline = Date(timeIntervalSinceNow: 5)
        var rescanned = false
        while Date() < deadline {
            _ = caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path)
            if counting.calls >= 2 { rescanned = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(rescanned, "FSEvents 变更后应重扫")
        XCTAssertEqual(caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path)?.path, newer.path)
    }

    func testCachingLocatorFallsBackWhenCachedURLDeleted() throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("s.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let counting = CountingLocator()
        counting.result = file
        let caching = CachingSessionLocator(wrapping: counting, watcherLatency: 0.1)

        XCTAssertNotNil(caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path))
        XCTAssertEqual(counting.calls, 1)

        // 缓存 URL 被删（即使 dirty 尚未投递）→ 存在性防御触发重扫
        try FileManager.default.removeItem(at: file)
        counting.result = nil
        XCTAssertNil(caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path))
        XCTAssertEqual(counting.calls, 2)
    }

    func testCachingLocatorMissingRootDegradesToDirectScan() {
        let counting = CountingLocator()
        counting.result = nil
        let caching = CachingSessionLocator(wrapping: counting, watcherLatency: 0.1)
        let missing = "/tmp/does-not-exist-\(UUID().uuidString)"

        // root 不存在 → watcher 创建失败 → 每次直扫（无缓存）
        XCTAssertNil(caching.locate(pid: 0, cwd: nil, sessionRoot: missing))
        XCTAssertNil(caching.locate(pid: 0, cwd: nil, sessionRoot: missing))
        XCTAssertEqual(counting.calls, 2)
    }

    func testCachingLocatorResetForcesRescan() throws {
        let tmp = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("s.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let counting = CountingLocator()
        counting.result = file
        let caching = CachingSessionLocator(wrapping: counting, watcherLatency: 0.1)

        XCTAssertNotNil(caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path))
        XCTAssertEqual(counting.calls, 1)
        caching.reset()
        XCTAssertNotNil(caching.locate(pid: 0, cwd: "/x", sessionRoot: tmp.path))
        XCTAssertEqual(counting.calls, 2)
    }
}
