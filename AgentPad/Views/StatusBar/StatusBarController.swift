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
    /// AgentMonitorSettings 变更通知（影响 showBadge）。
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

        let (active, paused, querying, errored) = countsFromEvent(lastEvent)
        let icon = StatusBarIconRenderer.twoLineImage(active: active, paused: paused, querying: querying, error: errored)
        statusItem.button?.image = icon
    }

    /// active = working + callingAPI（第一行 ▶N）
    /// paused = idle（第二行 ⏸L）
    /// querying 单独计数（第二行 ?M）
    /// errored 单独计数（第一行 !K）
    private func countsFromEvent(_ event: AgentMonitorEvent) -> (active: Int, paused: Int, querying: Int, errored: Int) {
        switch event {
        case .empty, .pollingFailed:
            return (0, 0, 0, 0)
        case .updated(let projects):
            var active = 0
            var paused = 0
            var querying = 0
            var errored = 0
            for p in projects {
                switch p.state {
                case .working, .callingAPI:
                    active += 1
                case .querying:
                    querying += 1
                case .error:
                    errored += 1
                case .idle:
                    paused += 1
                }
            }
            return (active, paused, querying, errored)
        }
    }
}
