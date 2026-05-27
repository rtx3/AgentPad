//
//  Writeback.swift
//  AgentPad
//
//  Minimal auto-chain writeback: axSet -> paste -> typing.
//  Used by AgentMacroRunner inputPhrase step. Plan 6 will extend this with
//  explicit mode selection; today's signature only exposes auto.
//

import AppKit
import ApplicationServices
import UserNotifications

enum Writeback {
    static func apply(output: String,
                      expectedTargetPID: pid_t?,
                      notificationTitle: String? = nil) {
        DispatchQueue.main.async {
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if let expected = expectedTargetPID, frontPID != expected {
                NSLog("[AgentPad] writeback PID mismatch expect=%d front=%d → notify",
                      Int(expected), Int(frontPID ?? -1))
                notifyDone(text: output, title: notificationTitle)
                return
            }

            // AX kAXSelectedTextAttribute set returns .success on terminals
            // (iTerm2, Terminal.app) without actually writing into the tty —
            // the AXTextArea exposes scrollback selection, not input. Same
            // theatre happens in some IME composition states. So we skip the
            // AX shortcut entirely and always inject as keystrokes, which is
            // the path the user actually wants for an "input phrase" macro.
            let role = copyFocusedElement()
                .flatMap { copyStringAttr($0, kAXRoleAttribute as CFString) } ?? "<nil>"
            NSLog("[AgentPad] writeback focused role=%@ path=type", role)
            typeUnicode(output)
        }
    }

    // MARK: - AX

    private static func copyFocusedElement() -> AXUIElement? {
        let sys = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &ref)
        guard err == .success, let raw = ref else { return nil }
        return (raw as! AXUIElement)
    }

    private static func copyStringAttr(_ el: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, attr, &ref)
        guard err == .success, let v = ref as? String else { return nil }
        return v
    }

    private static func trySetSelectedText(_ el: AXUIElement, _ text: String) -> Bool {
        let err = AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        return err == .success
    }

    // MARK: - Paste

    private static func pasteWithSnapshot(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        let snapshot: [NSPasteboard.PasteboardType: Data] = pb.types?.reduce(into: [:]) { acc, t in
            if let d = pb.data(forType: t) { acc[t] = d }
        } ?? [:]

        pb.clearContents()
        let wrote = pb.setString(text, forType: .string)
        if !wrote { return false }

        guard let src = CGEventSource(stateID: .hidSystemState) else { return false }
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) // V
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
            pb.clearContents()
            for (t, d) in snapshot {
                pb.setData(d, forType: t)
            }
        }
        return true
    }

    // MARK: - Typing

    private static func typeUnicode(_ text: String) {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        for scalar in text.unicodeScalars {
            var u16 = Array(String(scalar).utf16)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: u16.count, unicodeString: &u16)
            up?.keyboardSetUnicodeString(stringLength: u16.count, unicodeString: &u16)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    // MARK: - Notification

    private static func notifyDone(text: String, title: String?) {
        let content = UNMutableNotificationContent()
        content.title = title ?? NSLocalizedString("Done. Click to copy.",
            comment: "Writeback fallback notification title")
        content.body = String(text.prefix(140))

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content,
                                        trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
