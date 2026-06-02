//
//  SessionLocator.swift
//  AgentPad
//
//  给定 (pid, cwd, sessionRoot)，返回该 agent 当前 session 的 JSONL 路径。
//  Claude Code 编码规则：cwd 中每个 `/` 替换为 `-`，得到 sessionRoot 下的子目录名；
//  目录下选 mtime 最新的 `*.jsonl` 文件。
//

import Foundation

protocol SessionLocator {
    /// 返回 JSONL 绝对路径；找不到返回 nil。
    func locate(pid: pid_t, cwd: String?, sessionRoot: String) -> URL?
}

struct ClaudeCodeSessionLocator: SessionLocator {
    func locate(pid: pid_t, cwd: String?, sessionRoot: String) -> URL? {
        let rootURL = URL(fileURLWithPath: Self.expandTilde(sessionRoot), isDirectory: true)
        let fm = FileManager.default

        // 优先：cwd 已知 → 直接按编码规则定位项目目录。
        if let cwd = cwd, !cwd.isEmpty {
            let dirName = Self.encode(cwd: cwd)
            let projectDir = rootURL.appendingPathComponent(dirName, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: projectDir.path, isDirectory: &isDir), isDir.boolValue {
                return Self.latestJSONL(in: projectDir)
            }
        }

        // 兜底：cwd 不可读 / 目录不存在 → 在 sessionRoot 下取「最近被写过的」项目目录。
        // 适用：CLI 进程在沙箱里读不到 cwd 但 session 文件确在写。
        return Self.latestJSONLAcrossProjects(under: rootURL)
    }

    /// Claude Code 的 cwd → 目录名：把 `/` 全部替换为 `-`。
    /// 例：`/Users/mac/foo` → `-Users-mac-foo`。
    static func encode(cwd: String) -> String {
        return cwd.replacingOccurrences(of: "/", with: "-")
    }

    static func expandTilde(_ path: String) -> String {
        return (path as NSString).expandingTildeInPath
    }

    private static func latestJSONL(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let jsonl = contents.filter { $0.pathExtension == "jsonl" }
        return jsonl.max { lhs, rhs in
            mtime(lhs) < mtime(rhs)
        }
    }

    /// 在 sessionRoot 下扫描所有子目录，找出最近 5 分钟内被写过的最新 .jsonl。
    /// 超时阈值避免把昨天结束的 session 误当成「正在跑的」。
    private static func latestJSONLAcrossProjects(under root: URL, activeWindow: TimeInterval = 300) -> URL? {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let cutoff = Date(timeIntervalSinceNow: -activeWindow)
        var best: (URL, Date)? = nil
        for p in projects {
            guard (try? p.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard let latest = latestJSONL(in: p) else { continue }
            let t = mtime(latest)
            if t < cutoff { continue }
            if best == nil || t > best!.1 {
                best = (latest, t)
            }
        }
        return best?.0
    }

    private static func mtime(_ url: URL) -> Date {
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// Codex 的 session 文件按日期分桶：`~/.codex/sessions/YYYY/MM/DD/*.jsonl`
/// （或类似结构）。我们不依赖具体日期，直接在根下递归找最新 .jsonl。
struct CodexSessionLocator: SessionLocator {
    func locate(pid: pid_t, cwd: String?, sessionRoot: String) -> URL? {
        let rootURL = URL(fileURLWithPath: ClaudeCodeSessionLocator.expandTilde(sessionRoot), isDirectory: true)
        return Self.latestJSONLRecursive(under: rootURL)
    }

    /// 递归扫描 root 下所有 .jsonl，取 mtime 最新的一份。
    /// 限制扫描深度避免在巨大目录树上耗时。
    private static func latestJSONLRecursive(under root: URL, maxDepth: Int = 6) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var best: (URL, Date)? = nil
        for case let url as URL in enumerator {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension == "jsonl" else { continue }
            let t = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if best == nil || t > best!.1 {
                best = (url, t)
            }
        }
        return best?.0
    }
}
