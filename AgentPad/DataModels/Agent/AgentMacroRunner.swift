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
import UserNotifications

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
                self?.runNext(steps: steps, index: index + 1)
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
        // 1. AX kAXFrontmostAttribute=true on the app-level AXUIElement:
        //    this is the only reliable activation that follows the target's
        //    windows across Spaces (NSWorkspace.openApplication and
        //    NSRunningApplication.activate fail when target's windows live on
        //    a different Space). Requires AX permission, which AgentPad
        //    already prompts for at launch.
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let err = AXUIElementSetAttributeValue(axApp,
                                               kAXFrontmostAttribute as CFString,
                                               kCFBooleanTrue)
        NSLog("[AgentPad] AX frontmost err=%d pid=%d",
              Int(err.rawValue), Int(app.processIdentifier))

        // 2. Also call NSWorkspace.openApplication so that an app with no
        //    open windows gets a new window opened. activates=true keeps
        //    the AX-driven activation but covers the no-windows case.
        if #available(macOS 10.15, *), let url = app.bundleURL {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            cfg.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
            return
        }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    /// Poll the frontmost app's bundleID, on the main run loop, until it
    /// matches `bundleID` or the deadline elapses. Calls `completion` on
    /// main with whether the match was observed.
    private func waitForFrontmost(bundleID: String,
                                  deadline: DispatchTime,
                                  completion: @escaping (Bool) -> Void) {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
            // Tiny extra tick to let keyWindow / focused AX element settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
                completion(true)
            }
            return
        }
        if DispatchTime.now() >= deadline {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
            self?.waitForFrontmost(bundleID: bundleID,
                                   deadline: deadline,
                                   completion: completion)
        }
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
