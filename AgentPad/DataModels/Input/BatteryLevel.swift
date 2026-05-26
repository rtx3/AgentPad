//
//  BatteryLevel.swift
//  AgentPad
//
//  Backend-agnostic battery level. Capability-optional: backends that lack
//  battery telemetry (e.g. some MFi controllers) report `.unknown`.
//

import Foundation

enum BatteryLevel: Int, Codable, CaseIterable, Hashable {
    case empty
    case critical
    case low
    case medium
    case full
    case unknown
}
