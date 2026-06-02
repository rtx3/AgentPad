//
//  ProcessScanner.swift
//  AgentPad
//
//  proc_listpids / proc_name / proc_pidpath / proc_pidinfo 的 Swift 封装。
//  仅用于「列出哪些进程命中 patterns」+ 取元信息（cwd / startedAt / ppid），
//  不参与状态判定。
//

import Foundation
import Darwin

struct ProcessSnapshot {
    let pid: pid_t
    let name: String
    let executablePath: String?
    let cwd: String?
    let startedAt: Date
    let parentPid: pid_t
}

enum ProcessScannerError: Error {
    case enumerationFailed(errno: Int32)
}

enum ProcessScanner {
    /// `<libproc.h>` 的 `PROC_PIDPATHINFO_MAXSIZE = 4 * PATH_MAX = 4096`。
    /// C 宏不被 Swift 自动导入，这里硬编码同值。
    private static let pidPathInfoMaxSize: Int = 4 * Int(PATH_MAX)

    /// 全部存活进程的 PID 列表。
    static func listAllPIDs() throws -> [pid_t] {
        let neededBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard neededBytes > 0 else {
            throw ProcessScannerError.enumerationFailed(errno: errno)
        }
        // 预留 20% 余量，避免在两次调用之间新进程创建时溢出。
        let slotCount = (Int(neededBytes) / MemoryLayout<pid_t>.size) + 32
        var pids = [pid_t](repeating: 0, count: slotCount)
        let actualBytes = pids.withUnsafeMutableBufferPointer { ptr -> Int32 in
            let cap = Int32(slotCount * MemoryLayout<pid_t>.size)
            return proc_listpids(UInt32(PROC_ALL_PIDS), 0, ptr.baseAddress, cap)
        }
        guard actualBytes > 0 else {
            throw ProcessScannerError.enumerationFailed(errno: errno)
        }
        let actualCount = Int(actualBytes) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(actualCount)).filter { $0 > 0 }
    }

    static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: pidPathInfoMaxSize)
        let result = proc_name(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    /// 取 argv[0] 的 basename，对应 `ps -A -o comm` 列。
    /// 与 `name(of:)`（kernel 端 `p_comm`，不可被进程修改）互补：
    /// - 原生 binary（Rust/Go/Swift CLI）：两者一致
    /// - Node.js 等设置了 `process.title` 的 CLI（如 Claude Code）：
    ///   `name(of:)` 返回 "node"，本函数返回 "claude"。
    /// 用 `sysctl KERN_PROCARGS2` 读取用户态 argv 区域。
    /// 跨用户进程或受 SIP 保护的进程可能返回 nil（EPERM）。
    static func argv0Basename(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0

        // 先探需要的 buffer 大小。
        let probe = mib.withUnsafeMutableBufferPointer { mibPtr -> Int32 in
            sysctl(mibPtr.baseAddress, 3, nil, &size, nil, 0)
        }
        guard probe == 0, size >= MemoryLayout<Int32>.size else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        let fill = buffer.withUnsafeMutableBufferPointer { bufPtr -> Int32 in
            mib.withUnsafeMutableBufferPointer { mibPtr -> Int32 in
                sysctl(mibPtr.baseAddress, 3, bufPtr.baseAddress, &size, nil, 0)
            }
        }
        guard fill == 0, size >= MemoryLayout<Int32>.size else { return nil }

        // Layout (KERN_PROCARGS2):
        //   [argc: Int32][exec_path NUL][NUL padding ...][argv[0] NUL][argv[1] NUL]...
        var i = MemoryLayout<Int32>.size
        // 跳过 exec_path 到首个 NUL
        while i < size, buffer[i] != 0 { i += 1 }
        // 跳过对齐 padding（连续 NUL）
        while i < size, buffer[i] == 0 { i += 1 }
        guard i < size else { return nil }
        let argvStart = i
        while i < size, buffer[i] != 0 { i += 1 }
        guard i > argvStart else { return nil }

        let argv0Data = Data(buffer[argvStart..<i])
        guard let argv0 = String(data: argv0Data, encoding: .utf8), !argv0.isEmpty else { return nil }

        // basename + 去除空格后的参数（process.title 可能是 "claude (idle)"）。
        let lastComp = (argv0 as NSString).lastPathComponent
        if let space = lastComp.firstIndex(of: " ") {
            let head = String(lastComp[..<space])
            return head.isEmpty ? nil : head
        }
        return lastComp
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: pidPathInfoMaxSize)
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    static func bsdInfo(of pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard result == Int32(size) else { return nil }
        return info
    }

    static func cwd(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(size))
        guard result == Int32(size) else { return nil }
        let cwd = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw -> String in
            let p = raw.bindMemory(to: CChar.self).baseAddress!
            return String(cString: p)
        }
        return cwd.isEmpty ? nil : cwd
    }

    static func parentPid(of pid: pid_t) -> pid_t? {
        guard let info = bsdInfo(of: pid) else { return nil }
        return pid_t(info.pbi_ppid)
    }

    static func snapshot(of pid: pid_t, nameOverride: String? = nil) -> ProcessSnapshot? {
        let resolvedName = nameOverride ?? name(of: pid) ?? argv0Basename(of: pid)
        guard let nm = resolvedName, let info = bsdInfo(of: pid) else { return nil }
        let sec = TimeInterval(info.pbi_start_tvsec)
        let usec = TimeInterval(info.pbi_start_tvusec) / 1_000_000.0
        return ProcessSnapshot(
            pid: pid,
            name: nm,
            executablePath: executablePath(of: pid),
            cwd: cwd(of: pid),
            startedAt: Date(timeIntervalSince1970: sec + usec),
            parentPid: pid_t(info.pbi_ppid)
        )
    }

    /// 扫描全部 PID，按 patterns 匹配，返回命中快照。
    /// 匹配规则见 `matchedPattern(name:patterns:)`。
    /// cwd 过滤：取不到 cwd 时仍保留进程（CLI 工具受 SIP/权限限制可能读不到 cwd）；
    /// 仅当 cwd 明确是 "/" 或系统路径时才拒绝（用于剔除桌面 GUI 主进程）。
    static func scan(matching patterns: [String]) throws -> [ProcessSnapshot] {
        guard !patterns.isEmpty else { return [] }
        let pids = try listAllPIDs()
        var results: [ProcessSnapshot] = []
        results.reserveCapacity(min(pids.count, 32))
        var diagCandidateCount = 0
        for pid in pids {
            // 双路取名：
            // - nProc：kernel `p_comm`（不可修改）。原生 binary 直接对得上。
            // - nArgv：argv[0] basename（含 process.title 修改）。Node.js CLI 等用得上。
            let nProc = name(of: pid)
            let nArgv = argv0Basename(of: pid)
            let candidates = [nProc, nArgv].compactMap { $0 }
            guard !candidates.isEmpty else { continue }

            // 诊断 isCandidate：任一名字含 pattern 子串。
            let isCandidate = candidates.contains { nm in
                let lower = nm.lowercased()
                return patterns.contains(where: { lower.contains($0.lowercased()) })
            }
            if isCandidate { diagCandidateCount += 1 }

            // 取第一个能命中规则的 candidate 作为 displayName，对应的 pattern。
            var displayName: String? = nil
            var matchedPat: String? = nil
            for nm in candidates {
                if let p = matchedPattern(name: nm, patterns: patterns) {
                    displayName = nm
                    matchedPat = p
                    break
                }
            }
            guard let nm = displayName, let pattern = matchedPat else {
                if isCandidate {
                    NSLog("[agent.monitor.diag] pid=\(pid) procName=\"\(nProc ?? "<nil>")\" argv0=\"\(nArgv ?? "<nil>")\" → REJECTED by matchedPattern")
                }
                continue
            }
            guard let snap = snapshot(of: pid, nameOverride: nm) else {
                NSLog("[agent.monitor.diag] pid=\(pid) name=\"\(nm)\" pattern=\(pattern) → snapshot() FAILED")
                continue
            }
            // 排除桌面 GUI app 子进程：可执行文件在 /Applications/*.app/ 下。
            // 用于抓 Codex.app / Claude.app 这类没有 Helper 标记的桌面子进程。
            if let exe = snap.executablePath, isDesktopAppExecutable(exe) {
                NSLog("[agent.monitor.diag] pid=\(pid) name=\"\(nm)\" pattern=\(pattern) exe=\(exe) → REJECTED desktop app in /Applications")
                continue
            }
            // cwd nil 是常见情况（CLI 跑在不同 sandbox 域），不拒绝；
            // 只在能读到 cwd 且确为 "/" / 系统路径时拒绝。
            if let cwd = snap.cwd, !isWorkingCWD(cwd) {
                NSLog("[agent.monitor.diag] pid=\(pid) name=\"\(nm)\" pattern=\(pattern) cwd=\(cwd) → REJECTED non-working cwd")
                continue
            }
            results.append(snap)
        }
        NSLog("[agent.monitor.diag] scan: PIDs=\(pids.count) candidates(name-substr)=\(diagCandidateCount) accepted=\(results.count)")
        return results
    }

    /// 桌面 GUI 子进程通常带这些标记词；排除它们。
    private static let excludedNameKeywords: [String] = [
        "Helper", "Renderer", "GPU", "Plugin", "Squirrel"
    ]

    /// pattern 后允许的分隔符（codex-aarch64-apple-darwin / claude_v2 / claude.x 都接受）。
    private static let patternBoundarySeparators: Set<Character> = ["-", "_", "."]

    /// 收窄后的匹配规则：
    /// 1. name 命中任一排除关键词 → 拒绝（Claude Helper / Claude Helper (Renderer) 等桌面 GUI 子进程）。
    /// 2. lowercased(name) 完全等于 lowercased(pattern) → 命中。
    /// 3. lowercased(name) 以 lowercased(pattern) 开头，且 pattern 后紧跟分隔符 → 命中。
    /// 否则不命中。返回匹配到的 pattern 原值。
    static func matchedPattern(name: String, patterns: [String]) -> String? {
        for kw in excludedNameKeywords {
            if name.contains(kw) { return nil }
        }
        let lower = name.lowercased()
        for p in patterns {
            let lp = p.lowercased()
            if lower == lp { return p }
            if lower.count > lp.count, lower.hasPrefix(lp) {
                let nextIdx = lower.index(lower.startIndex, offsetBy: lp.count)
                if patternBoundarySeparators.contains(lower[nextIdx]) {
                    return p
                }
            }
        }
        return nil
    }

    /// 判定为「桌面 GUI app 的可执行体」：路径在 `/Applications/Xxx.app/` 下。
    /// 用户安装的 CLI 工具一般在 `/usr/local/bin` / `~/.bun/bin` / homebrew prefix，
    /// 不会误伤。
    static func isDesktopAppExecutable(_ path: String) -> Bool {
        return path.hasPrefix("/Applications/") && path.contains(".app/")
    }

    /// cwd 必须是用户工作目录：非空、不是根，也不在系统路径下。
    /// 用于排除桌面 GUI 主进程（cwd 常为 "/"）。
    static func isWorkingCWD(_ cwd: String) -> Bool {
        guard !cwd.isEmpty, cwd != "/" else { return false }
        let systemPrefixes = ["/System/", "/Library/", "/Applications/", "/private/var/"]
        for prefix in systemPrefixes {
            if cwd.hasPrefix(prefix) { return false }
        }
        return true
    }
}
