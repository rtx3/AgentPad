//
//  LegacyButtonNameMap.swift
//  AgentPad
//
//  Bidirectional dictionary between JoyConSwift's legacy stored names and the
//  backend-agnostic `ControllerButton` / `ControllerStickDirection`. Used by
//  the read path so existing user databases keep working without an eager
//  rewrite, and by the write path so new persistence stays on legacy names
//  until s4 explicitly opts a row into the new format.
//
//  IMPORTANT: dpad and stick share the four direction names ("Up", "Right",
//  "Down", "Left") in legacy storage. The decoder MUST tell the caller which
//  collection a KeyMap belongs to — a button row decodes "Up" as `.dpadUp`,
//  a stick row decodes the same string as `.up`.
//

import Foundation

enum ControllerButtonContext {
    case button
    case stick
}

enum LegacyButtonNameMap {
    /// Maps a legacy `KeyMap.button` string to the new `ControllerButton`.
    /// Returns nil when the string is unrecognised (e.g. corrupted row); the
    /// caller should silently skip such rows, matching the prior behaviour
    /// where `buttonNames.first { ... }` would also fall through to nil.
    static func button(from legacyName: String) -> ControllerButton? {
        if let direct = ControllerButton(rawValue: legacyName) { return direct }
        return legacyToButton[legacyName]
    }

    /// Maps a legacy `KeyMap.button` string (stick context) to the new
    /// `ControllerStickDirection`. Only the 4 cardinal directions are valid
    /// in legacy storage; everything else yields nil.
    static func stickDirection(from legacyName: String) -> ControllerStickDirection? {
        if let direct = ControllerStickDirection(rawValue: legacyName) { return direct }
        return legacyToStickDirection[legacyName]
    }

    /// New -> legacy persisted name. Write path keeps using these strings
    /// until the migration flag opts the database into new rawValues, so
    /// rolling back to a prior app version stays safe.
    static func legacyName(for button: ControllerButton) -> String? {
        return buttonToLegacy[button]
    }

    static func legacyName(for direction: ControllerStickDirection) -> String? {
        return stickDirectionToLegacy[direction]
    }

    // MARK: - Tables

    private static let legacyToButton: [String: ControllerButton] = [
        // Face buttons — Nintendo layout: A right, B bottom, X top, Y left.
        "A": .faceRight,
        "B": .faceDown,
        "X": .faceUp,
        "Y": .faceLeft,
        // D-pad.
        "Up": .dpadUp,
        "Right": .dpadRight,
        "Down": .dpadDown,
        "Left": .dpadLeft,
        // Shoulders / triggers / stick clicks.
        "L": .l1,
        "ZL": .l2,
        "R": .r1,
        "ZR": .r2,
        "LStick Push": .l3,
        "RStick Push": .r3,
        // System buttons.
        "Plus": .start,
        "Minus": .select,
        "Home": .home,
        "Capture": .capture,
        // Famicom physical Start / Select share the semantic with Plus / Minus.
        "Start": .start,
        "Select": .select,
        // Joy-Con specific.
        "Left SL": .leftSL,
        "Left SR": .leftSR,
        "Right SL": .rightSL,
        "Right SR": .rightSR,
    ]

    /// Write side: pick the canonical legacy name. For ambiguous mappings
    /// (.start / .select shared with Famicom rows), prefer the Plus/Minus
    /// name — that is what the existing `buttonNames` table uses for all
    /// non-Famicom controllers and matches the bulk of the installed base.
    private static let buttonToLegacy: [ControllerButton: String] = [
        .faceRight: "A",
        .faceDown: "B",
        .faceUp: "X",
        .faceLeft: "Y",
        .dpadUp: "Up",
        .dpadRight: "Right",
        .dpadDown: "Down",
        .dpadLeft: "Left",
        .l1: "L",
        .l2: "ZL",
        .r1: "R",
        .r2: "ZR",
        .l3: "LStick Push",
        .r3: "RStick Push",
        .start: "Plus",
        .select: "Minus",
        .home: "Home",
        .capture: "Capture",
        .leftSL: "Left SL",
        .leftSR: "Left SR",
        .rightSL: "Right SL",
        .rightSR: "Right SR",
    ]

    private static let legacyToStickDirection: [String: ControllerStickDirection] = [
        "Up": .up,
        "Right": .right,
        "Down": .down,
        "Left": .left,
    ]

    private static let stickDirectionToLegacy: [ControllerStickDirection: String] = [
        .up: "Up",
        .right: "Right",
        .down: "Down",
        .left: "Left",
    ]
}
