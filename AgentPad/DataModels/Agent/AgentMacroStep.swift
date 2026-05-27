//
//  AgentMacroStep.swift
//  AgentPad
//

import Foundation

enum AgentMacroStep: Equatable {
    case activateApp(bundleID: String)
    case switchInputMethod(sourceID: String)
    case inputPhrase(text: String)
    case delay(ms: Int)
}

extension AgentMacroStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case bundleID
        case sourceID
        case phrase
        case ms
    }

    private enum Kind: String {
        case activateApp
        case switchInputMethod
        case inputPhrase
        case delay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .type)
        guard let kind = Kind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "Unknown AgentMacroStep type: \(raw)")
        }
        switch kind {
        case .activateApp:
            self = .activateApp(bundleID: try c.decode(String.self, forKey: .bundleID))
        case .switchInputMethod:
            self = .switchInputMethod(sourceID: try c.decode(String.self, forKey: .sourceID))
        case .inputPhrase:
            self = .inputPhrase(text: try c.decode(String.self, forKey: .phrase))
        case .delay:
            self = .delay(ms: try c.decode(Int.self, forKey: .ms))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .activateApp(let bundleID):
            try c.encode(Kind.activateApp.rawValue, forKey: .type)
            try c.encode(bundleID, forKey: .bundleID)
        case .switchInputMethod(let sourceID):
            try c.encode(Kind.switchInputMethod.rawValue, forKey: .type)
            try c.encode(sourceID, forKey: .sourceID)
        case .inputPhrase(let text):
            try c.encode(Kind.inputPhrase.rawValue, forKey: .type)
            try c.encode(text, forKey: .phrase)
        case .delay(let ms):
            try c.encode(Kind.delay.rawValue, forKey: .type)
            try c.encode(ms, forKey: .ms)
        }
    }
}

enum AgentMacroCodec {
    static let maxSteps = 5
    static let maxPhraseChars = 4096
    static let minDelayMs = 10
    static let maxDelayMs = 2000

    static func decode(_ json: String?) -> [AgentMacroStep] {
        guard let json = json,
              let data = json.data(using: .utf8),
              let steps = try? JSONDecoder().decode([AgentMacroStep].self, from: data)
        else { return [] }
        return steps
    }

    static func encode(_ steps: [AgentMacroStep]) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = []
        guard let data = try? enc.encode(steps),
              let s = String(data: data, encoding: .utf8)
        else { return "[]" }
        return s
    }
}
