//
//  SessionLocator.swift
//  AgentPad
//
//  给定 (pid, cwd, sessionRoot)，返回该 agent 当前 session 的 JSONL 路径。
//  Claude Code 编码规则：cwd 中每个 `/` 替换为 `-`，得到 sessionRoot 下的子目录名；
//  目录下选 mtime 最新的 `*.jsonl` 文件。
//

import Foundation
import CoreServices

protocol SessionLocator {
    /// 返回 JSONL 绝对路径；找不到返回 nil。
    func locate(pid: pid_t, cwd: String?, sessionRoot: String) -> URL?
}

/// FSEvents 监听单个 sessionRoot，维护「自上次消费以来是否有变更」的 dirty 位。
/// 回调只置位、不做扫描——扫描由消费方在自己的队列上按需执行。
/// dirty 位用锁保护：FSEvents 回调（共享事件队列）与消费方（AgentMonitor.queue）跨线程。
final class SessionRootWatcher {
    private var stream: FSEventStreamRef?
    private let lock = NSLock()
    private var dirty = true   // 初始 dirty：首次 locate 必须真实扫描

    /// 所有 watcher 共享的回调队列；回调只置位，无阻塞工作。
    private static let eventQueue = DispatchQueue(label: "com.rtx3.agentpad.sessionroot.fsevents", qos: .utility)

    /// root 不存在或 stream 创建失败时返回 nil（调用方逐 tick 降级为直扫）。
    init?(rootPath: String, latency: CFTimeInterval = 2.0) {
        // FSEvents 对符号链接路径（/tmp、/var/folders）不可靠，先解析真实路径。
        let resolved = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        // deferred 模式（不带 NoDefer flag）：事件攒到 latency 末尾合并投递，
        // 活跃写入期间每 latency 秒至多唤醒一次。
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info = info else { return }
                Unmanaged<SessionRootWatcher>.fromOpaque(info).takeUnretainedValue().markDirty()
            },
            &context,
            [resolved] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else { return nil }
        FSEventStreamSetDispatchQueue(stream, Self.eventQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    deinit {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func markDirty() {
        lock.lock()
        dirty = true
        lock.unlock()
    }

    /// 读取并清零 dirty。必须在触发扫描*之前*调用：
    /// 扫描期间新落的事件会重新置位，下一拍再失效——不丢更新。
    func consumeDirty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let d = dirty
        dirty = false
        return d
    }
}

/// SessionLocator 的缓存装饰器。每个 sessionRoot 挂一个 FSEvents watcher，
/// root 无变更的 tick 直接复用上次 locate 结果，跳过目录枚举
/// （codex 根目录的递归扫描是 tick 的主要 I/O 开销）。
///
/// 线程契约：locate / reset 仅在单一串行队列（AgentMonitor.queue）上调用；
/// 唯一跨线程状态是 watcher 的 dirty 位，由其内部锁保护。
///
/// 已知行为差异：ClaudeCodeSessionLocator 的 cwd==nil 兜底带 5 分钟活跃窗口
/// （纯时间条件，无 FS 事件也会翻转）。缓存后窗口过期不会立即反映，但下游
/// classify 以文件 lastWriteAt 判 staleness，最终 UI 状态一致（均为 idle）。
final class CachingSessionLocator: SessionLocator {
    private let wrapped: SessionLocator
    private let watcherLatency: CFTimeInterval
    /// resolvedRoot → watcher。创建失败不记录，下一 tick 重试。
    private var watchers: [String: SessionRootWatcher] = [:]
    /// key = "<resolvedRoot>|<cwd>"。nil（miss）也缓存：root 无变更时 miss 依然成立。
    private var cache: [String: URL?] = [:]

    init(wrapping wrapped: SessionLocator, watcherLatency: CFTimeInterval = 2.0) {
        self.wrapped = wrapped
        self.watcherLatency = watcherLatency
    }

    func locate(pid: pid_t, cwd: String?, sessionRoot: String) -> URL? {
        let root = URL(fileURLWithPath: ClaudeCodeSessionLocator.expandTilde(sessionRoot))
            .resolvingSymlinksInPath().path

        // watcher 不存在则尝试创建；创建失败（root 缺失等）→ 直扫，
        // 与无缓存行为一致（缺失目录的扫描开销可忽略）。
        let watcher: SessionRootWatcher
        if let w = watchers[root] {
            watcher = w
        } else if let w = SessionRootWatcher(rootPath: root, latency: watcherLatency) {
            watchers[root] = w
            watcher = w
        } else {
            return wrapped.locate(pid: pid, cwd: cwd, sessionRoot: sessionRoot)
        }

        // 先消费 dirty 再扫描：扫描期间的新事件会重新置位，下一拍重扫。
        if watcher.consumeDirty() {
            invalidate(root: root)
        }

        let key = "\(root)|\(cwd ?? "")"
        if let entry = cache[key] {
            if let url = entry {
                // 防御 FSEvents 丢事件（kernel 队列溢出等）：命中的 URL 必须仍存在。
                if FileManager.default.fileExists(atPath: url.path) { return url }
            } else {
                return nil
            }
        }
        let result = wrapped.locate(pid: pid, cwd: cwd, sessionRoot: sessionRoot)
        cache.updateValue(result, forKey: key)
        return result
    }

    /// settings 变更（sessionRoots / patterns）后调用：丢弃全部缓存与 watcher。
    func reset() {
        watchers.removeAll()
        cache.removeAll()
    }

    private func invalidate(root: String) {
        let prefix = root + "|"
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
    }
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
