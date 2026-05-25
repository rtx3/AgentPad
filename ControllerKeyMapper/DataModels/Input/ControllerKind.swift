//
//  ControllerKind.swift
//  ControllerKeyMapper
//
//  Concrete hardware family of a connected controller. Drives icon rendering
//  and the per-vendor face-button labelling (PS: Cross/Circle/Square/Triangle;
//  Xbox: A/B/X/Y; Nintendo: A/B/X/Y with swapped layout).
//

import Foundation

enum ControllerKind: String, Codable, CaseIterable, Hashable {
    // Nintendo (via JoyConSwift / IOHID).
    case joyConL
    case joyConR
    case proController
    case snesController
    case famicomController1
    case famicomController2

    // Sony / Microsoft / Apple-MFi (via GameController.framework).
    case dualShock4
    case dualSense
    case xbox
    case mfi

    // Anything else that exposes itself as a generic extended gamepad.
    case generic
    case unknown
}
