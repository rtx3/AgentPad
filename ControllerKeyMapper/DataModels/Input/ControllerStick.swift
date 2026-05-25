//
//  ControllerStick.swift
//  ControllerKeyMapper
//
//  Backend-agnostic stick identifiers and 8-way discrete directions, mirroring
//  JoyCon.StickDirection so that the existing handler signature
//  (newDir, oldDir) -> () translates cleanly.
//

import Foundation

enum ControllerStick: String, Codable, CaseIterable, Hashable {
    case left
    case right
}

enum ControllerStickDirection: String, Codable, CaseIterable, Hashable {
    case up
    case upRight
    case right
    case downRight
    case down
    case downLeft
    case left
    case upLeft
    case neutral
}
