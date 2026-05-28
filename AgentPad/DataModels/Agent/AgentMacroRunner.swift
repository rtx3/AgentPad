//
//  AgentMacroRunner.swift
//  AgentPad
//
//  Main-queue serial macro executor. inflight guard discards subsequent
//  button presses until current macro finishes or aborts.
//

import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import UserNotifications

// MARK: - CGS private SPI
// Used to read which Space a window lives on and to switch the user-visible
// Space on a given display. Required because public APIs (NSWorkspace,
// NSRunningApplication.activate, AX kAXFrontmostAttribute) only move focus —
// they cannot follow the target across Spaces. Same approach Hammerspoon /
// AltTab / Rectangle use. Project is not sandboxed, so symbols resolve at link.

private typealias CGSConnectionID = Int32
private typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

// mask: include all user spaces (current + others). 7 = all-user-spaces
// (kCGSAllSpacesMask) per public reverse-engineering refs.
@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: CGSConnectionID,
                                     _ mask: Int32,
                                     _ windowIDs: CFArray) -> CFArray?

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
private func CGSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID,
                                              _ display: CFString,
                                              _ space: CGSSpaceID)

// Pair of SPIs that actually drive the visible Space transition on
// macOS 13+ — CGSManagedDisplaySetCurrentSpace alone only updates the CGS
// bookkeeping; WindowServer/Dock won't repaint until Show+Hide is called.
// yabai / AltTab / skhd use the same combo.
@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: CFArray)

@_silgen_name("CGSHideSpaces")
private func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: CFArray)

// SLPS window-raise SPI (alt-tab / Hammerspoon path). Brings a specific
// CGWindowID to front and crucially makes WindowServer follow the user
// to that window's Space — unlike CGSManagedDisplaySetCurrentSpace which
// only updates CGS bookkeeping and is increasingly ignored on macOS 14+.
private let kSLPSModeUserGenerated: UInt32 = 0x200

@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
private func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>,
                                             _ wid: CGWindowID,
                                             _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo") @discardableResult
private func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>,
                                   _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

// GetProcessForPID is marked unavailable in Swift but the symbol still
// exists in ApplicationServices. Re-declare via @_silgen_name.
@_silgen_name("GetProcessForPID") @discardableResult
private func GetProcessForPID_(_ pid: pid_t,
                               _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("_AXUIElementGetWindow") @discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                   _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

private let kCGSAllSpacesMask: Int32 = 7

final class AgentMacroRunner {
    static let shared = AgentMacroRunner()

    private(set) var inflight: Bool = false
    private var expectedTargetPID: pid_t?

    private init() {}

    func run(steps: [AgentMacroStep]) {
        guard !inflight, !steps.isEmpty else { return }
        inflight = true
        expectedTargetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        NSLog("[AgentPad] macro run start: %d steps, frontPID=%d",
              steps.count, Int(expectedTargetPID ?? -1))
        runNext(steps: steps, index: 0)
    }

    private func runNext(steps: [AgentMacroStep], index: Int) {
        guard index < steps.count else {
            NSLog("[AgentPad] macro done")
            finish()
            return
        }
        let step = steps[index]
        let stepNumber = index + 1
        NSLog("[AgentPad] step %d: %@", stepNumber, String(describing: step))

        switch step {
        case .activateApp(let bundleID):
            do {
                try activateApp(bundleID: bundleID)
            } catch {
                fail(stepNumber: stepNumber, reason: error.localizedDescription)
                return
            }
            waitForFrontmost(bundleID: bundleID, deadline: .now() + 1.5) { [weak self] ok in
                NSLog("[AgentPad] step %d activateApp settled ok=%@ front=%@",
                      stepNumber, String(ok),
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")
                guard let self = self else { return }
                if !ok {
                    let fmt = NSLocalizedString(
                        "App window not on active Space: %@",
                        comment: "Macro activateApp failed because target window is on another Space")
                    self.fail(stepNumber: stepNumber,
                              reason: String(format: fmt, bundleID))
                    return
                }
                self.runNext(steps: steps, index: index + 1)
            }

        case .switchInputMethod(let sourceID):
            if let err = switchInputMethod(sourceID: sourceID) {
                fail(stepNumber: stepNumber, reason: err)
                return
            }
            // IME selection is async; give it a small settle window before any
            // subsequent inputPhrase posts CGEvents.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
                self?.runNext(steps: steps, index: index + 1)
            }

        case .inputPhrase(let text):
            NSLog("[AgentPad] step %d inputPhrase len=%d expectPID=%d frontPID=%d",
                  stepNumber, text.count, Int(expectedTargetPID ?? -1),
                  Int(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1))
            Writeback.apply(output: text, expectedTargetPID: expectedTargetPID,
                            notificationTitle: nil)
            runNext(steps: steps, index: index + 1)

        case .delay(let ms):
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
                self?.runNext(steps: steps, index: index + 1)
            }
        }
    }

    private func finish() {
        inflight = false
        expectedTargetPID = nil
    }

    private func fail(stepNumber: Int, reason: String) {
        inflight = false
        expectedTargetPID = nil
        let fmt = NSLocalizedString("Macro step %d failed: %@",
            comment: "Agent macro failure notification")
        let body = String(format: fmt, stepNumber, reason)
        notify(body: body)
    }

    private func notify(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "AgentPad"
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content,
                                        trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: - Step impls

    private enum MacroError: LocalizedError {
        case appNotFound(String)
        case appLaunchFailed(String)

        var errorDescription: String? {
            switch self {
            case .appNotFound(let id): return "app not found: \(id)"
            case .appLaunchFailed(let id): return "app launch failed: \(id)"
            }
        }
    }

    private func activateApp(bundleID: String) throws {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            activate(running)
            expectedTargetPID = running.processIdentifier
            return
        }

        let launched = NSWorkspace.shared.launchApplication(
            withBundleIdentifier: bundleID,
            options: [.default],
            additionalEventParamDescriptor: nil,
            launchIdentifier: nil)
        guard launched else {
            throw MacroError.appLaunchFailed(bundleID)
        }

        // Wait briefly for the launched process to register so subsequent
        // inputPhrase steps see the right frontmost PID.
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                activate(app)
                expectedTargetPID = app.processIdentifier
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw MacroError.appLaunchFailed(bundleID)
    }

    private func activate(_ app: NSRunningApplication) {
        let pid = app.processIdentifier

        // Check if we need to switch Space first.
        let needsSpaceSwitch = windowNotOnActiveSpace(forPID: pid)

        if needsSpaceSwitch {
            // CGS space switch, then SLPS raise after animation settles.
            switchSpaceIfNeeded(forPID: pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) { [weak self] in
                self?.slpsRaise(pid: pid)
            }
        } else {
            slpsRaise(pid: pid)
        }
    }

    private func slpsRaise(pid: pid_t) {
        if let wid = pickTargetWindow(forPID: pid) {
            var psn = ProcessSerialNumber()
            if GetProcessForPID_(pid, &psn) == noErr {
                _SLPSSetFrontProcessWithOptions(&psn, wid, kSLPSModeUserGenerated)
                makeKeyWindow(psn: &psn, wid: wid)
                raiseWindowViaAX(pid: pid, wid: wid)
                NSLog("[AgentPad] activate(SLPS+AX) pid=%d wid=%u",
                      Int(pid), wid)
                return
            }
        }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// Returns true if all windows of `pid` are on spaces other than the
    /// currently active space.
    private func windowNotOnActiveSpace(forPID pid: pid_t) -> Bool {
        let cid = CGSMainConnectionID()
        let activeSpace = CGSGetActiveSpace(cid)
        let targetSpaces = spaces(forPID: pid, connection: cid)
        if targetSpaces.isEmpty { return false }
        return !targetSpaces.contains(activeSpace)
    }

    /// AXRaiseAction on the target window — completes the SLPS sequence by
    /// ensuring the window is visually on top.
    private func raiseWindowViaAX(pid: pid_t, wid: CGWindowID) {
        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString,
                                            &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }
        for axWin in axWindows {
            var cgWid: CGWindowID = 0
            if _AXUIElementGetWindow(axWin, &cgWid) == .success, cgWid == wid {
                AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
                return
            }
        }
    }

    /// Hammerspoon byte sequence that tells WindowServer to make `wid` the
    /// key window of `psn`. Required after _SLPSSetFrontProcessWithOptions
    /// for the focus to actually settle on the chosen window.
    /// Source: https://github.com/Hammerspoon/hammerspoon/issues/370
    private func makeKeyWindow(psn: UnsafeMutablePointer<ProcessSerialNumber>,
                               wid: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        var widCopy = wid
        memcpy(&bytes[0x3c], &widCopy, MemoryLayout<UInt32>.size)
        memset(&bytes[0x20], 0xff, 0x10)
        bytes[0x08] = 0x01
        SLPSPostEventRecordTo(psn, &bytes)
        bytes[0x08] = 0x02
        SLPSPostEventRecordTo(psn, &bytes)
    }

    /// Choose a CGWindowID belonging to `pid` to raise. Prefers a window on
    /// a Space the user can naturally land on; falls back to first layer-0
    /// window. Returns nil if the process owns no real windows.
    private func pickTargetWindow(forPID pid: pid_t) -> CGWindowID? {
        let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(opts, kCGNullWindowID)
                as? [[String: Any]] else { return nil }

        var titled: CGWindowID? = nil
        var anyLayer0: CGWindowID? = nil
        for info in infoList {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t,
                  owner == pid,
                  let wid = info[kCGWindowNumber as String] as? UInt32 else { continue }
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 {
                continue
            }
            if anyLayer0 == nil { anyLayer0 = wid }
            if let title = info[kCGWindowName as String] as? String, !title.isEmpty {
                if titled == nil { titled = wid }
            }
        }
        return titled ?? anyLayer0
    }

    /// For every managed display whose currently-visible Space does not host
    /// one of `pid`'s windows, switch that display to a Space that does.
    /// Uses CGEvent keystroke simulation (Control+N) to switch desktops.
    /// Desktop numbers are global across all displays.
    @discardableResult
    private func switchSpaceIfNeeded(forPID pid: pid_t) -> Bool {
        let cid = CGSMainConnectionID()
        let targetSpaces = Set(spaces(forPID: pid, connection: cid))
        NSLog("[AgentPad] CGS target spaces=%@ pid=%d",
              targetSpaces.map { String($0) }.joined(separator: ","),
              Int(pid))
        guard !targetSpaces.isEmpty else { return false }

        guard let displays = CGSCopyManagedDisplaySpaces(cid)
                as? [[String: Any]] else {
            NSLog("[AgentPad] CGS: CGSCopyManagedDisplaySpaces returned nil")
            return true
        }

        var globalIndex = 0
        var switchTarget: (desktopNumber: Int, displayUUID: String)? = nil

        for entry in displays {
            guard let uuid = entry["Display Identifier"] as? String,
                  let spaces = entry["Spaces"] as? [[String: Any]] else { continue }
            let currentID = (entry["Current Space"] as? [String: Any])
                .flatMap { spaceID($0) }
            NSLog("[AgentPad] CGS display %@ current=%@ spaces=[%@] globalOffset=%d",
                  uuid,
                  currentID.map { String($0) } ?? "nil",
                  spaces.compactMap { spaceID($0).map(String.init) }.joined(separator: ","),
                  globalIndex)

            if let cur = currentID, targetSpaces.contains(cur) {
                globalIndex += spaces.count
                continue
            }

            for (idx, sp) in spaces.enumerated() {
                guard let sid = spaceID(sp), targetSpaces.contains(sid) else { continue }
                let desktopNumber = globalIndex + idx + 1
                NSLog("[AgentPad] CGS: need global desktop %d on display %@ (space %llu)",
                      desktopNumber, uuid, sid)
                if switchTarget == nil {
                    switchTarget = (desktopNumber, uuid)
                }
                break
            }
            globalIndex += spaces.count
        }

        if let target = switchTarget {
            let originalCGPos = CGEvent(source: nil)?.location ?? .zero
            moveMouse(toDisplayUUID: target.displayUUID)
            simulateControlNumber(target.desktopNumber)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
                CGWarpMouseCursorPosition(originalCGPos)
            }
        }
        return true
    }

    /// Move the mouse cursor to the center of the display identified by UUID.
    /// Returns the CG point moved to (for posting a synthetic mouse event).
    @discardableResult
    private func moveMouse(toDisplayUUID uuid: String) -> CGPoint? {
        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            let screenUUID = CGDisplayCreateUUIDFromDisplayID(screenNumber)
                .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
            if screenUUID == uuid {
                let bounds = CGDisplayBounds(screenNumber)
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                CGWarpMouseCursorPosition(center)
                NSLog("[AgentPad] moveMouse to display %@ center=(%.0f,%.0f)",
                      uuid, center.x, center.y)
                return center
            }
        }
        NSLog("[AgentPad] moveMouse: display %@ not found in NSScreen.screens", uuid)
        return nil
    }

    /// Simulate Control+N keystroke to switch to Desktop N.
    /// Requires "Switch to Desktop N" shortcuts enabled in
    /// System Settings → Keyboard → Keyboard Shortcuts → Mission Control.
    /// Key codes for 1-9: 18,19,20,21,23,22,26,28,25
    private func simulateControlNumber(_ number: Int) {
        guard number >= 1, number <= 9 else {
            NSLog("[AgentPad] simulateControlNumber: %d out of range", number)
            return
        }
        // Virtual key codes for digits 1-9 on US keyboard
        let keyCodes: [Int] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let keyCode = keyCodes[number - 1]

        let src = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: src,
                                    virtualKey: CGKeyCode(keyCode),
                                    keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src,
                                  virtualKey: CGKeyCode(keyCode),
                                  keyDown: false) else {
            NSLog("[AgentPad] simulateControlNumber: CGEvent creation failed")
            return
        }
        keyDown.flags = .maskControl
        keyUp.flags = .maskControl
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        NSLog("[AgentPad] simulateControlNumber: sent Control+%d (keyCode=%d)",
              number, keyCode)
    }

    /// Read either `ManagedSpaceID` or `id64` out of a Space dictionary.
    private func spaceID(_ dict: [String: Any]) -> CGSSpaceID? {
        if let v = dict["ManagedSpaceID"] as? UInt64 { return v }
        if let v = dict["id64"] as? UInt64 { return v }
        if let n = dict["ManagedSpaceID"] as? NSNumber { return n.uint64Value }
        if let n = dict["id64"] as? NSNumber { return n.uint64Value }
        return nil
    }

    /// Collect the Spaces that own any window of `pid`. Uses .optionAll so
    /// windows that sit on inactive Spaces are still discovered — the whole
    /// point of this check is to detect that case.
    private func spaces(forPID pid: pid_t,
                        connection cid: CGSConnectionID) -> [CGSSpaceID] {
        let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(opts, kCGNullWindowID)
                as? [[String: Any]] else { return [] }

        var windowIDs: [UInt32] = []
        for info in infoList {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t,
                  owner == pid,
                  let wid = info[kCGWindowNumber as String] as? UInt32 else { continue }
            // Skip layer != 0 (menubar / dock helpers) — only real windows.
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 {
                continue
            }
            windowIDs.append(wid)
        }
        guard !windowIDs.isEmpty else { return [] }

        let widsCF = windowIDs.map { NSNumber(value: $0) } as CFArray
        guard let raw = CGSCopySpacesForWindows(cid, kCGSAllSpacesMask, widsCF)
                as? [NSNumber] else { return [] }
        var seen = Set<CGSSpaceID>()
        var out: [CGSSpaceID] = []
        for n in raw {
            let sid = n.uint64Value
            if seen.insert(sid).inserted { out.append(sid) }
        }
        return out
    }

    /// Find the managed-display UUID whose Spaces list contains `spaceID`.
    private func displayHosting(spaceID: CGSSpaceID,
                                connection cid: CGSConnectionID) -> CFString? {
        guard let displays = CGSCopyManagedDisplaySpaces(cid)
                as? [[String: Any]] else {
            NSLog("[AgentPad] CGS: CGSCopyManagedDisplaySpaces returned nil")
            return nil
        }
        for entry in displays {
            guard let uuid = entry["Display Identifier"] as? String,
                  let spaces = entry["Spaces"] as? [[String: Any]] else { continue }
            for sp in spaces {
                if let sid = self.spaceID(sp), sid == spaceID {
                    return uuid as CFString
                }
            }
        }
        return nil
    }


    /// Poll on the main run loop until the frontmost app's bundleID matches
    /// `bundleID` AND at least one of that app's windows sits on the active
    /// Space (or the app has no windows at all — then activation is best we
    /// can do). Returns false via `completion` on deadline elapse.
    private func waitForFrontmost(bundleID: String,
                                  deadline: DispatchTime,
                                  completion: @escaping (Bool) -> Void) {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID,
           windowOnActiveSpace(bundleID: bundleID) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
                completion(true)
            }
            return
        }
        // After Space switch CGSGetActiveSpace may lag ~100ms; if app is
        // already frontmost but Space check fails, grant extra grace.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID,
           DispatchTime.now() < deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
                self?.waitForFrontmost(bundleID: bundleID,
                                       deadline: deadline,
                                       completion: completion)
            }
            return
        }
        if DispatchTime.now() >= deadline {
            // Final check: if frontmost matches, accept regardless of space
            let isFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
            completion(isFront)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
            self?.waitForFrontmost(bundleID: bundleID,
                                   deadline: deadline,
                                   completion: completion)
        }
    }

    /// True if `bundleID`'s process has no on-screen windows, or has one that
    /// lives on the currently active Space. Used to detect "activation
    /// succeeded but Space did not follow".
    private func windowOnActiveSpace(bundleID: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleID).first else { return false }
        let cid = CGSMainConnectionID()
        let target = spaces(forPID: app.processIdentifier, connection: cid)
        if target.isEmpty { return true }
        return target.contains(CGSGetActiveSpace(cid))
    }

    private func switchInputMethod(sourceID: String) -> String? {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
                as? [TISInputSource] else {
            return "input source list unavailable"
        }
        for src in list {
            guard let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { continue }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            if id == sourceID {
                let err = TISSelectInputSource(src)
                if err != noErr {
                    return "input source select failed (OSStatus \(err))"
                }
                return nil
            }
        }
        return "input source unavailable: \(sourceID)"
    }
}
