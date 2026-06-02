//
//  AgentMonitorPopoverController.swift
//  AgentPad
//
//  NSPopover 持有 + show / hide / toggle。
//

import AppKit

final class AgentMonitorPopoverController {
    let popover: NSPopover
    let viewController: AgentMonitorViewController

    /// Footer Settings 按钮回调。AppDelegate 注入。
    var onOpenSettings: () -> Void = {} {
        didSet { viewController.onOpenSettings = onOpenSettings }
    }
    /// Footer Quit 按钮回调。
    var onQuit: () -> Void = {} {
        didSet { viewController.onQuit = onQuit }
    }
    /// 错误态 Retry 回调。AppDelegate 接 AgentMonitor.pollOnce。
    var onRetry: () -> Void = {} {
        didSet { viewController.onRetry = onRetry }
    }

    init() {
        let vc = AgentMonitorViewController()
        self.viewController = vc
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.contentViewController = vc
        p.contentSize = NSSize(width: 320, height: 400)
        self.popover = p
    }

    func toggle(relativeTo view: NSView) {
        if popover.isShown { popover.performClose(nil) }
        else { show(relativeTo: view) }
    }

    func show(relativeTo view: NSView) {
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func apply(event: AgentMonitorEvent) {
        viewController.apply(event: event)
    }
}
