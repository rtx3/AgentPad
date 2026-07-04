//
//  KeyConfigCodec.swift
//  AgentPad
//
//  KeyConfig 的导出 / 导入 JSON 编解码。
//
//  仅处理 defaultConfig（不含 AppConfig 覆盖），保留全部三种 action：
//  keyboard / agent / system；agentMacro 字段当作不透明字符串原样传递，
//  不解码也不校验内部结构（升级时由 AgentMacroCodec / SystemActionCodec 兜底）。
//
//  跨手柄 kind 兼容采用"宽松模式"：导入时若 kind 不一致，由调用方弹 warning
//  让用户决定是否继续；本 codec 只负责忠实序列化与解析，不做拒绝逻辑。
//

import Foundation

/// 顶层文档结构。`version` 用于未来 schema 升级；当前固定为 1。
struct KeyConfigDocument: Codable {
    /// 文件 schema 版本。当前仅支持 1；遇到未知版本时由 DataManager 抛错。
    let version: Int
    /// 导出时来源手柄的 ControllerKind raw value（如 "xbox"/"proController"）。
    /// 导入时若与目标 kind 不一致，UI 层弹 warning 走宽松模式。
    let kind: String
    /// 默认配置正文。
    let defaultConfig: KeyConfigPayload

    static let currentVersion: Int = 1
}

struct KeyConfigPayload: Codable {
    let keyMaps: [KeyMapPayload]
    let leftStick: StickConfigPayload?
    let rightStick: StickConfigPayload?
}

struct StickConfigPayload: Codable {
    /// StickType.rawValue（"Mouse"/"Mouse Wheel"/"Key"/"None"），未设置时省略。
    let type: String?
    let speed: Float
    let keyMaps: [KeyMapPayload]
}

struct KeyMapPayload: Codable {
    /// ControllerButton.rawValue（按既有 LegacyButtonNameMap 命名空间），导入时按名匹配。
    let button: String
    /// "keyboard" / "agent" / "system"；nil 视为 "keyboard"。
    let action: String?
    let keyCode: Int16
    let modifiers: Int32
    let mouseButton: Int16
    let isEnabled: Bool
    /// agent / system 的不透明负载（AgentMacroCodec / SystemActionCodec 编码字符串）。
    let agentMacro: String?
}

enum KeyConfigCodecError: Error, LocalizedError {
    case unsupportedVersion(Int)
    case decodeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "Unsupported key mapping file version: \(v)"
        case .decodeFailed(let e):
            return "Failed to decode key mapping file: \(e.localizedDescription)"
        }
    }
}

enum KeyConfigCodec {
    /// 编码：把 ControllerData.defaultConfig 序列化为 JSON Data。
    /// `kind` 用于跨手柄校验，由调用方按 ControllerData.type 或 backend.kind 传入。
    static func encode(defaultConfig: KeyConfig, kind: String) throws -> Data {
        let doc = KeyConfigDocument(
            version: KeyConfigDocument.currentVersion,
            kind: kind,
            defaultConfig: KeyConfigCodec.payload(from: defaultConfig)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(doc)
    }

    /// 解码：把文件字节解析为 KeyConfigDocument，并校验 version。
    static func decode(_ data: Data) throws -> KeyConfigDocument {
        let decoder = JSONDecoder()
        do {
            let doc = try decoder.decode(KeyConfigDocument.self, from: data)
            guard doc.version == KeyConfigDocument.currentVersion else {
                throw KeyConfigCodecError.unsupportedVersion(doc.version)
            }
            return doc
        } catch let error as KeyConfigCodecError {
            throw error
        } catch {
            throw KeyConfigCodecError.decodeFailed(underlying: error)
        }
    }

    // MARK: - Payload construction

    private static func payload(from config: KeyConfig) -> KeyConfigPayload {
        var keyMaps: [KeyMapPayload] = []
        config.keyMaps?.enumerateObjects { (obj, _) in
            guard let km = obj as? KeyMap else { return }
            keyMaps.append(KeyConfigCodec.payload(from: km))
        }
        return KeyConfigPayload(
            keyMaps: keyMaps,
            leftStick: config.leftStick.map { KeyConfigCodec.payload(from: $0) },
            rightStick: config.rightStick.map { KeyConfigCodec.payload(from: $0) }
        )
    }

    private static func payload(from stick: StickConfig) -> StickConfigPayload {
        var keyMaps: [KeyMapPayload] = []
        stick.keyMaps?.enumerateObjects { (obj, _) in
            guard let km = obj as? KeyMap else { return }
            keyMaps.append(KeyConfigCodec.payload(from: km))
        }
        return StickConfigPayload(
            type: stick.type,
            speed: stick.speed,
            keyMaps: keyMaps
        )
    }

    private static func payload(from km: KeyMap) -> KeyMapPayload {
        return KeyMapPayload(
            button: km.button ?? "",
            action: km.action,
            keyCode: km.keyCode,
            modifiers: km.modifiers,
            mouseButton: km.mouseButton,
            isEnabled: km.isEnabled,
            agentMacro: km.agentMacro
        )
    }
}
