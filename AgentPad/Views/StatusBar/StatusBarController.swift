//
//  StatusBarController.swift
//  AgentPad
//
//  持有 NSStatusItem，并把：
//  - 左键单击 → toggle Agent Monitor Popover
//  - 右键 / Ctrl+Click → 弹既有 NSMenu
//  接入 AgentMonitor.eventHandler 做图标重绘。
//

import AppKit

final class StatusBarController: NSObject {
    let statusItem: NSStatusItem
    let popover: AgentMonitorPopoverController
    weak var legacyMenu: NSMenu?

    private var lastEvent: AgentMonitorEvent = .empty
    /// AgentMonitorSettings 变更通知（影响 showCount）。
    private var settingsObserver: Any?

    init(legacyMenu: NSMenu?, openSettings: @escaping () -> Void = {}) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = AgentMonitorPopoverController()
        self.legacyMenu = legacyMenu
        super.init()

        self.popover.onOpenSettings = openSettings
        self.popover.onQuit = { NSApp.terminate(nil) }

        if let button = self.statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

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
    func apply(event: AgentMonitorEvent) {
        lastEvent = event
        popover.apply(event: event)
        renderIcon()
    }

    private func renderIcon() {
        // 读取配置：是否显示状态徽章
        let showBadge = AppSettings.AgentMonitor.showStatusBadge

        if !showBadge {
            // 不显示徽章：只显示纯 icon
            let icon = NSImage(named: "menu_icon")
            icon?.size = NSSize(width: 24, height: 24)
            icon?.isTemplate = true
            statusItem.button?.image = icon
            return
        }

        // 显示徽章：使用两行布局
        // 从 lastEvent 提取 running/idle 计数
        let (running, idle) = countsFromEvent(lastEvent)
        let icon = StatusBarIconRenderer.twoLineImage(running: running, idle: idle)
        statusItem.button?.image = icon
    }

    /// 从 AgentMonitorEvent 提取 running 和 idle 计数。
    /// running = working + callingAPI，idle = idle。
    private func countsFromEvent(_ event: AgentMonitorEvent) -> (running: Int, idle: Int) {
        switch event {
        case .empty, .pollingFailed:
            return (0, 0)
        case .updated(let processes):
            var running = 0
            var idle = 0
            for p in processes {
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

    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent, let button = statusItem.button else { return }
        let isRight = event.type == .rightMouseUp ||
                      (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if isRight {
            // 右键 / Ctrl+Click：临时挂 menu，触发后立即解绑，避免下次左键也弹菜单
            statusItem.menu = legacyMenu
            button.performClick(nil)
            statusItem.menu = nil
        } else {
            popover.toggle(relativeTo: button)
        }
    }

    /// 等价于左键单击效果。给「Open Agent Monitor…」menuItem 调。
    func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button)
    }
}
