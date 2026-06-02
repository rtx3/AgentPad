//
//  StatusBarController.swift
//  AgentPad
//
//  持有 NSStatusItem。
//  统一行为：左键、右键、Ctrl+Click 都弹出 statusItem.menu（NSMenu 版本，
//  AppDelegate 是 menu delegate，负责在 menuWillOpen 时把当前 agent rows 注入）。
//  原 Popover 入口已撤掉；popover 控制器类保留以备未来复用。
//

import AppKit

final class StatusBarController: NSObject {
    let statusItem: NSStatusItem
    weak var legacyMenu: NSMenu?

    private var lastEvent: AgentMonitorEvent = .empty
    /// AgentMonitorSettings 变更通知（影响 showCount / showBadge）。
    private var settingsObserver: Any?

    /// Settings 入口保留为可调用闭包，留给将来菜单或快捷键复用。
    var openSettings: () -> Void

    init(legacyMenu: NSMenu?, openSettings: @escaping () -> Void = {}) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.legacyMenu = legacyMenu
        self.openSettings = openSettings
        super.init()

        // 永久绑定 menu：左/右键、Ctrl+Click 系统会自动弹出。
        self.statusItem.menu = legacyMenu

        renderIcon()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.AgentMonitor.settingsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.renderIcon()
        }
    }

    deinit {
        if let token = settingsObserver { NotificationCenter.default.removeObserver(token) }
    }

    /// AgentMonitor 每轮 poll 调一次。Main thread。
    /// 现在仅用于更新菜单栏图标徽章；菜单内 agent rows 由 AppDelegate 在 menuWillOpen 时按 snapshot 重建。
    func apply(event: AgentMonitorEvent) {
        lastEvent = event
        renderIcon()
    }

    private func renderIcon() {
        let showBadge = AppSettings.AgentMonitor.showStatusBadge

        if !showBadge {
            let icon = NSImage(named: "menu_icon")
            icon?.size = NSSize(width: 24, height: 24)
            icon?.isTemplate = true
            statusItem.button?.image = icon
            return
        }

        let (running, idle) = countsFromEvent(lastEvent)
        let icon = StatusBarIconRenderer.twoLineImage(running: running, idle: idle)
        statusItem.button?.image = icon
    }

    /// 从 AgentMonitorEvent 提取 running 和 idle 计数。
    /// 计数单位为 **project（按 cwd 聚合）**，而不是进程：同 cwd 多个 claude 实例只算一次。
    /// running = working + callingAPI，idle = idle。
    private func countsFromEvent(_ event: AgentMonitorEvent) -> (running: Int, idle: Int) {
        switch event {
        case .empty, .pollingFailed:
            return (0, 0)
        case .updated(let projects):
            var running = 0
            var idle = 0
            for p in projects {
                switch p.state {
                case .working, .callingAPI:
                    running += 1
                case .idle:
                    idle += 1
                }
            }
            return (running, idle)
        }
    }
}
