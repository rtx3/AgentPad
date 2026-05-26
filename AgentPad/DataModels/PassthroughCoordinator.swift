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

    private weak var manager: JoyConManager?
    private(set) var state: State = .mapping
    private var retryTimer: Timer?
    private var retryStartedAt: Date?

    /// Notification posted whenever `state` changes; observers refresh UI.
    static let stateChangedNotification = Notification.Name("PassthroughCoordinatorStateChanged")

    private let retryInterval: TimeInterval = 2.0
    private let retryWindow: TimeInterval = 60.0

    init(manager: JoyConManager) {
        self.manager = manager
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
