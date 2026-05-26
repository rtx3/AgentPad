//
//  ControllerButton.swift
//  AgentPad
//
//  Backend-agnostic semantic button identifier. Mapped from JoyConSwift's
//  JoyCon.Button at the backend boundary; serialised as rawValue into
//  KeyMap.button. Legacy JoyCon.Button names are still accepted on read for
//  zero-migration backwards compatibility (see LegacyButtonNameMap).
//

import Foundation

enum ControllerButton: String, Codable, CaseIterable, Hashable {
    // Face buttons by physical position (translated per-vendor at the UI layer).
    case faceUp
    case faceDown
    case faceLeft
    case faceRight

    // D-pad.
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight

    // Shoulders / triggers / stick clicks.
    case l1
    case r1
    case l2
    case r2
    case l3
    case r3

    // System buttons.
    case start
    case select
    case home
    case capture

    // Joy-Con specific.
    case leftSL
    case leftSR
    case rightSL
    case rightSR

    case unknown
}
