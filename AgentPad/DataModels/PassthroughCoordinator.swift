//
//  PassthroughCoordinator.swift
//  AgentPad
//
//  Coordinates global controller passthrough: when the active app is marked
//  passthrough, release the HID seize so games / Steam can see the
//  controllers; when leaving such an app, re-take seize and retry on a timer
//  if a foreign process is still holding the device.
//

import Foundation
import IOKit
import JoyConSwift

final class PassthroughCoordinator {
    enum State: Equatable {
        case mapping            // We own all controllers; mappings active.
        case passthrough        // Released; games/Steam can use the controllers.
        case reclaiming         // We want to own again but reseize failed; retrying.
    }

    /// 弱单例：AppDelegate 创建后赋值。供 GameController 事件回调 / UI 入口
    /// 查询 `isPaused`，避免逐对象传引用。
    /// 弱引用确保 AppDelegate 仍是 owner、生命周期不被单例延长。
    private(set) static weak var shared: PassthroughCoordinator?

    private weak var manager: JoyConManager?
    private(set) var state: State = .mapping
    private var retryTimer: Timer?
    private var retryStartedAt: Date?

    /// 用户级强制 passthrough。优先级高于按 App 自动求值——
    /// 一旦为 true，`requestMapping()` 直接被守卫拦截，App 切换无法把它冲掉。
    /// 仅进程内瞬态，不持久化（防止崩溃后启动锁死在 Gamepad Mode 而用户找不到入口）。
    private(set) var isUserPaused: Bool = false

    /// 给 UI 与 GC 事件守卫使用的统一查询点。
    var isPaused: Bool { state == .passthrough }

    /// Notification posted whenever `state` changes; observers refresh UI.
    static let stateChangedNotification = Notification.Name("PassthroughCoordinatorStateChanged")

    /// Notification posted whenever `isUserPaused` 切换；用于状态栏菜单 toggle 勾选刷新。
    static let userPausedDidChangeNotification = Notification.Name("PassthroughCoordinatorUserPausedDidChange")

    private let retryInterval: TimeInterval = 2.0
    private let retryWindow: TimeInterval = 60.0

    init(manager: JoyConManager) {
        self.manager = manager
        PassthroughCoordinator.shared = self
    }

    // MARK: - Public

    /// Request entering passthrough (release seize globally).
    /// Idempotent — safe to call when already in `.passthrough`.
    func requestPassthrough() {
        self.stopRetry()
        guard let manager = self.manager else { return }
        guard self.state != .passthrough else { return }
        let ret = manager.setSeized(false)
        if ret == kIOReturnSuccess {
            self.setState(.passthrough)
        } else {
            // Failed to release — stay in mapping, but log.
            NSLog("PassthroughCoordinator: setSeized(false) failed: \(ret)")
        }
    }

    /// Request returning to mapping (re-take seize). If another process
    /// (game / Steam) still holds the device, schedule retries.
    func requestMapping() {
        // 用户级 Pause 优先级最高：来自 App 自动求值的 mapping 请求一律拦截，
        // 否则用户切换前台 App 时会被自动求值冲掉手动选择的 Gamepad Mode。
        guard !self.isUserPaused else { return }
        guard let manager = self.manager else { return }
        guard self.state != .mapping else {
            self.stopRetry()
            return
        }
        if self.attemptReseize() == kIOReturnSuccess {
            self.setState(.mapping)
            self.stopRetry()
        } else {
            self.setState(.reclaiming)
            self.startRetryIfNeeded()
        }
    }

    /// 用户从 UI 切换 Takeover ⇄ Gamepad Mode 的统一入口。
    /// `foregroundIsPassthroughApp` 由调用方按当前前台 App 求值后传入：
    /// 切回 Takeover 时若前台仍是 passthrough App，应继续保持 passthrough，
    /// 不立刻强抢 seize 而骚扰游戏。
    func setUserPaused(_ paused: Bool, foregroundIsPassthroughApp: Bool) {
        guard self.isUserPaused != paused else { return }
        self.isUserPaused = paused
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: PassthroughCoordinator.userPausedDidChangeNotification, object: self)
        }
        if paused {
            self.requestPassthrough()
        } else if !foregroundIsPassthroughApp {
            self.requestMapping()
        }
        // paused=false 且前台是 passthrough App → 维持当前 .passthrough 状态。
    }

    // MARK: - Retry loop

    private func attemptReseize() -> IOReturn {
        guard let manager = self.manager else { return kIOReturnNotReady }
        return manager.setSeized(true)
    }

    private func startRetryIfNeeded() {
        guard self.retryTimer == nil else { return }
        self.retryStartedAt = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: self.retryInterval, repeats: true) { [weak self] _ in
            self?.tickRetry()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.retryTimer = timer
    }

    private func stopRetry() {
        self.retryTimer?.invalidate()
        self.retryTimer = nil
        self.retryStartedAt = nil
    }

    private func tickRetry() {
        // Aborted while retry timer is in flight.
        guard self.state == .reclaiming else {
            self.stopRetry()
            return
        }

        // Try once.
        if self.attemptReseize() == kIOReturnSuccess {
            self.setState(.mapping)
            self.stopRetry()
            return
        }

        // Check window.
        if let started = self.retryStartedAt,
           Date().timeIntervalSince(started) > self.retryWindow {
            // Give up. User can manually reconnect the controller via Bluetooth.
            self.stopRetry()
            // Stay in `.reclaiming` so UI can prompt; mapping is effectively dead
            // until the device reconnects (which will reset seize anyway).
            NSLog("PassthroughCoordinator: gave up reseize after \(self.retryWindow)s")
        }
    }

    private func setState(_ new: State) {
        guard self.state != new else { return }
        self.state = new
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: PassthroughCoordinator.stateChangedNotification, object: self)
        }
    }
}
