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
}
