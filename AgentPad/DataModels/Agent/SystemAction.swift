//
//  SystemAction.swift
//  AgentPad
//
//  系统级动作绑定。区别于 AgentMacroStep：
//  - AgentMacroStep 是「步骤列表」，按顺序执行（激活 App、切输入法、写入文本）。
//  - SystemAction 是单次系统行为（切 Space、Mission Control 等），无序列概念。
//
//  存储路径：KeyMap.action = "system"；KeyMap.agentMacro 字段复用作 JSON payload。
//

import Foundation

enum SystemAction: String, Codable, CaseIterable {
    case moveToSpaceLeft
    case moveToSpaceRight
    case missionControl
    case launchpad
    case notificationCenter
    case showDesktop

    /// 本地化标题，用于 KeyConfig 弹窗的下拉选项与 KeyMap 列表的右列显示。
    var displayName: String {
        switch self {
        case .moveToSpaceLeft:
            return NSLocalizedString("Move to Space Left", comment: "System action: switch to previous Space")
        case .moveToSpaceRight:
            return NSLocalizedString("Move to Space Right", comment: "System action: switch to next Space")
        case .missionControl:
            return NSLocalizedString("Mission Control", comment: "System action: open Mission Control")
        case .launchpad:
            return NSLocalizedString("Launchpad", comment: "System action: open Launchpad")
        case .notificationCenter:
            return NSLocalizedString("Notification Center", comment: "System action: open Notification Center")
        case .showDesktop:
            return NSLocalizedString("Show Desktop", comment: "System action: hide all windows")
        }
    }
}

enum SystemActionCodec {
    /// 把 SystemAction 编码进 KeyMap.agentMacro 字段（String），与 AgentMacroCodec 共存。
    /// 因为 action 字段的 "system" 标记已经区分了走哪条解码路径，payload 直接是单值 rawValue
    /// 即可——避免引入额外 JSON 容器层。
    static func encode(_ action: SystemAction) -> String {
        return action.rawValue
    }

    static func decode(_ raw: String?) -> SystemAction? {
        guard let raw = raw else { return nil }
        return SystemAction(rawValue: raw)
    }
}
