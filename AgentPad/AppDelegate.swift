//
//  AppDelegate.swift
//  AgentPad
//
//  Created by magicien on 2019/07/14.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit
import ServiceManagement
import UserNotifications
import JoyConSwift

let helperAppID: CFString = "com.rtx3.agentpad.launcher" as CFString

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    @IBOutlet weak var menu: NSMenu?
    var windowController: NSWindowController?
    
    let manager: JoyConManager = JoyConManager()
    /// Owns the manager + bridges to ControllerBackend for downstream code.
    /// Created lazily so AppDelegate can keep its existing `manager` reference
    /// stable for PassthroughCoordinator while we migrate.
    lazy var joyConDiscovery: JoyConDiscovery = JoyConDiscovery(manager: self.manager)
    /// macOS 10.15+ adds discovery for PS / Xbox / MFi controllers via
    /// GameController.framework. nil on 10.14 (the minimum deployment target).
    var gcDiscovery: ControllerBackendDiscovery?
    var dataManager: DataManager?
    var controllers: [GameController] = []
    var passthroughCoordinator: PassthroughCoordinator?
    var accessibilityOnboardingWindowController: AccessibilityOnboardingWindowController?
    /// 当前命中 passthrough 的前台 App 显示名，由 didActivateApp 维护。
    /// 用于状态栏菜单显示 "Passthrough → [App]"。
    var currentPassthroughAppName: String?

    /// Agent 监控后端。计划 A：仅启动 + 持有；UI 由计划 B 接入。
    var agentMonitor: AgentMonitor?
    /// 计划 B：菜单栏图标 + Popover 控制器。
    var statusBarController: StatusBarController?

    /// 状态栏 NSMenu 是否处于打开状态。打开期间 poll 事件需原地刷新已存在的行视图，
    /// 因为 NSMenu tracking 期间不接受 item 增删。
    private var agentMenuOpen: Bool = false
    /// menuWillOpen 时记录每个 project row 对应的视图，poll 期间按 id 原地 configure。
    private var agentRowViewsByProjectId: [String: AgentMenuRowView] = [:]
    /// menuWillOpen 时记录的 header item 引用，poll 期间更新计数文案。
    private weak var agentHeaderItem: NSMenuItem?

    func applicationWillFinishLaunching(_ aNotification: Notification) {
        // 必须在 didFinishLaunching 之前完成：NSBundle 第一次解析 lproj 时读取
        // AppleLanguages。didChangeLanguage 只持久化 AppLanguage（应用层 key），
        // 这里在每次进程启动最早期把它注入到 AppleLanguages，下一次 NSLocalizedString
        // 解析才能命中正确的 lproj。
        if let lang = UserDefaults.standard.string(forKey: "AppLanguage") {
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        
        // Window initialization
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        self.windowController = storyboard.instantiateController(withIdentifier: "AgentPadWindowController") as? NSWindowController
        
        // 状态栏图标：完全交给 StatusBarController（计划 B）。
        let sbController = StatusBarController(
            legacyMenu: self.menu,
            openSettings: { [weak self] in
                self?.openAgentMonitorSettings()
            }
        )
        self.statusBarController = sbController

        // Set controller handlers
        self.joyConDiscovery.connectHandler = { [weak self] backend in
            self?.connectBackend(backend)
        }
        self.joyConDiscovery.disconnectHandler = { [weak self] backend in
            self?.disconnectBackend(backend)
        }
        if #available(macOS 10.15, *) {
            let gc = GCControllerDiscovery()
            gc.connectHandler = { [weak self] backend in
                self?.connectBackend(backend)
            }
            gc.disconnectHandler = { [weak self] backend in
                self?.disconnectBackend(backend)
            }
            self.gcDiscovery = gc
        }

        self.dataManager = DataManager() { [weak self] manager in
            guard let strongSelf = self else { return }
            guard let dataManager = manager else { return }

            dataManager.controllers.forEach { data in
                let gameController = GameController(data: data)
                strongSelf.controllers.append(gameController)
            }
            strongSelf.joyConDiscovery.start()
            strongSelf.gcDiscovery?.start()
            // PassthroughCoordinator 必须在 manager.runAsync() 之后创建，
            // 否则 manager.runLoop 还未赋值，setSeized 会立即 kIOReturnNotReady。
            strongSelf.passthroughCoordinator = PassthroughCoordinator(manager: strongSelf.manager)
            NotificationCenter.default.addObserver(strongSelf, selector: #selector(strongSelf.passthroughStateChanged), name: PassthroughCoordinator.stateChangedNotification, object: nil)

            NSWorkspace.shared.notificationCenter.addObserver(strongSelf, selector: #selector(strongSelf.didActivateApp), name: NSWorkspace.didActivateApplicationNotification, object: nil)

            NotificationCenter.default.post(name: .controllerAdded, object: nil)
        }

        self.updateControllersMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(controllerIconChanged), name: .controllerIconChanged, object: nil)
        
        // Notification settings
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        DispatchQueue.main.async { [weak self] in
            self?.accessibilityOnboardingWindowController = AccessibilityOnboardingWindowController.presentIfNeeded()
        }

        // Agent monitor backend (计划 A)。事件同时扇出给 StatusBarController（菜单栏图标）
        // 与已展开的状态栏 NSMenu（原地刷新行视图与 header 计数）。
        let monitor = AgentMonitor()
        monitor.setEventHandler { [weak self] event in
            self?.statusBarController?.apply(event: event)
            self?.refreshOpenAgentMenuRows(event: event)
        }
        monitor.start()
        self.agentMonitor = monitor

        // 把 status bar 菜单的 delegate 设为 self，在打开前注入当前 agent rows。
        self.menu?.delegate = self
    }

    /// 让 Popover Footer Settings 与新 menuItem 都走这条路径。
    /// 直接显示主窗口并定位到 Agent Monitor 分页。
    @objc func openAgentMonitorSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let wc = self.windowController as? AgentPadWindowController {
            wc.show(tab: .agentMonitor)
        } else {
            self.windowController?.showWindow(self)
        }
    }

    /// 新 menuItem「Open Agent Monitor…」：等价于左键单击图标。
    /// 注：自从左键直接弹出 NSMenu 后，该项已从 storyboard 移除，IBAction 保留以防外部引用。
    @IBAction func openAgentMonitor(_ sender: Any) {
        // No-op: status bar menu already shows agent rows on click.
    }

    // MARK: - Menu
    
    @IBAction func openAbout(_ sender: Any) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(NSApplication.shared)
    }
    
    @IBAction func openSettings(_ sender: Any) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.windowController?.showWindow(self)
        self.windowController?.window?.orderFrontRegardless()
        self.windowController?.window?.delegate = self
    }
    
    @IBAction func quit(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }

    func updateControllersMenu() {
        if !Thread.isMainThread {
            NSLog("[ThreadProbe] updateControllersMenu hop-to-main from queue=%@", String(cString: __dispatch_queue_get_label(nil)))
            DispatchQueue.main.async { [weak self] in
                self?.updateControllersMenu()
            }
            return
        }
        dispatchPrecondition(condition: .onQueue(.main))
        // 新设计：手柄状态行直接显示在主菜单中，不再使用 Controllers 子菜单。
        // 插入位置：在 "Open Agent Monitor" 和 "Settings" 之间。

        guard let menu = self.menu else { return }

        // 先移除所有标记为手柄状态行的 menuItem（tag = 9999）
        menu.items.removeAll { $0.tag == 9999 }

        // 找到 "Settings" 的索引（假设它的 action 是 openSettings）
        guard let settingsIndex = menu.items.firstIndex(where: { $0.action == #selector(openSettings(_:)) }) else {
            return
        }

        // 如果有已连接的手柄，插入状态行
        let connectedControllers = self.controllers.filter { $0.controller?.isConnected ?? false }

        if connectedControllers.isEmpty {
            // 无手柄：插入 "No controllers connected" 占位行
            let item = NSMenuItem()
            item.title = NSLocalizedString("No controllers connected", comment: "No controllers connected")
            item.isEnabled = false
            item.tag = 9999
            menu.insertItem(item, at: settingsIndex)
            menu.insertItem(NSMenuItem.separator(), at: settingsIndex)
        } else {
            // 有手柄：每个手柄一行
            var insertIndex = settingsIndex
            for controller in connectedControllers {
                let item = makeControllerStatusItem(for: controller)
                menu.insertItem(item, at: insertIndex)
                insertIndex += 1
            }
            // 手柄行后加分隔符
            menu.insertItem(NSMenuItem.separator(), at: insertIndex)
        }
    }

    /// 创建单个手柄的状态行 NSMenuItem。
    /// 格式：[icon] 名字    电量% ⚡
    /// 点击 → 弹 disconnect 确认 alert。
    private func makeControllerStatusItem(for controller: GameController) -> NSMenuItem {
        let item = NSMenuItem()
        item.tag = 9999 // 标记为手柄状态行，便于下次更新时移除

        // 图标（20pt）
        item.image = controller.icon
        item.image?.size = NSSize(width: 20, height: 20)

        // 标题：名字 + 右对齐电量
        let name = controller.backend?.displayName ?? "Controller"
        var batteryText = ""
        if let battery = controller.controller?.battery, battery != .unknown {
            let percent = controller.localizedBatteryString
            let charging = (controller.controller?.isCharging ?? false) ? " ⚡" : ""
            batteryText = "\(percent)\(charging)"
        }

        // 使用 NSAttributedString + NSTextTab 实现右对齐
        let attrTitle = NSMutableAttributedString(string: name)
        if !batteryText.isEmpty {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.tabStops = [NSTextTab(textAlignment: .right, location: 200, options: [:])]
            attrTitle.append(NSAttributedString(string: "\t\(batteryText)"))
            attrTitle.addAttribute(NSAttributedString.Key.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attrTitle.length))
        }
        item.attributedTitle = attrTitle

        // 点击 → disconnect 确认
        item.target = self
        item.action = #selector(confirmDisconnectController(_:))
        item.representedObject = controller

        return item
    }

    /// 手柄状态行点击 → 弹 alert 确认 disconnect。
    @objc private func confirmDisconnectController(_ sender: NSMenuItem) {
        guard let controller = sender.representedObject as? GameController else { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Disconnect controller?", comment: "")
        let name = controller.backend?.displayName ?? "Controller"
        alert.informativeText = String(format: NSLocalizedString("Do you want to disconnect %@?", comment: ""), name)
        alert.addButton(withTitle: NSLocalizedString("Disconnect", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            controller.backend?.disconnect()
        }
    }

    /// 当前 PassthroughCoordinator 状态对应的菜单标题。
    /// coordinator 未就绪时按 mapping 处理（启动早期窗口）。
    private func passthroughStatusTitle() -> String {
        let state = self.passthroughCoordinator?.state ?? .mapping
        switch state {
        case .mapping:
            return NSLocalizedString("Mapping", comment: "Passthrough status: mapping active")
        case .passthrough:
            let fmt = NSLocalizedString("Passthrough → %@", comment: "Passthrough status: pass-through to app")
            let appName = self.currentPassthroughAppName ?? ""
            return String(format: fmt, appName)
        case .reclaiming:
            return NSLocalizedString("Reclaiming controller…", comment: "Passthrough status: reclaiming")
        }
    }
    
    // MARK: - Helper app settings
    
    func setLoginItem(enabled: Bool) {
        let succeeded = SMLoginItemSetEnabled(helperAppID, enabled)
        if (!succeeded) {
            
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        _ = self.dataManager?.save()
    }
    
    // MARK: - Notifications
    
    @objc func controllerIconChanged(_ notification: NSNotification) {
        self.updateControllersMenu()
    }

    @objc func passthroughStateChanged(_ notification: NSNotification) {
        self.updateControllersMenu()
    }
    
    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .badge, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    // MARK: - Controller event handlers

    func applicationWillTerminate(_ aNotification: Notification) {
        self.controllers.forEach { controller in
            controller.backend?.disconnect()
        }
    }
    
    func connectController(_ controller: JoyConSwift.Controller) {
        if let gameController = self.controllers.first(where: {
            $0.data.serialID == controller.serialID
        }) {
            gameController.backend = JoyConBackend(controller: controller)
            gameController.startTimer()
            NotificationCenter.default.post(name: .controllerConnected, object: gameController)

            AppNotifications.notifyControllerConnected(gameController)
        } else {
            self.addController(controller)
        }
        self.updateControllersMenu()
    }

    /// Backend-agnostic connect path. Routes JoyConBackend through the
    /// legacy serialID lookup so existing rows keep matching, and uses the
    /// namespaced backend identifier for everything else (GameController.framework).
    func connectBackend(_ backend: ControllerBackend) {
        if let joyCon = (backend as? JoyConBackend)?.controller {
            self.connectController(joyCon)
            return
        }
        let identifier = backend.identifier
        if let gameController = self.controllers.first(where: {
            $0.data.serialID == identifier
        }) {
            gameController.backend = backend
            gameController.startTimer()
            NotificationCenter.default.post(name: .controllerConnected, object: gameController)
            AppNotifications.notifyControllerConnected(gameController)
        } else {
            self.addBackend(backend)
        }
        self.updateControllersMenu()
    }

    func disconnectBackend(_ backend: ControllerBackend) {
        if let joyCon = (backend as? JoyConBackend)?.controller {
            self.disconnectController(joyCon)
            return
        }
        let identifier = backend.identifier
        if let gameController = self.controllers.first(where: {
            $0.data.serialID == identifier
        }) {
            gameController.backend = nil
            gameController.updateControllerIcon()
            NotificationCenter.default.post(name: .controllerDisconnected, object: gameController)
            AppNotifications.notifyControllerDisconnected(gameController)
        }
        self.updateControllersMenu()
    }

    func addBackend(_ backend: ControllerBackend) {
        guard let dataManager = self.dataManager else { return }
        let controllerData = dataManager.getControllerData(forBackend: backend)
        let gameController = GameController(data: controllerData)
        gameController.backend = backend
        gameController.startTimer()
        self.controllers.append(gameController)

        NotificationCenter.default.post(name: .controllerAdded, object: gameController)
        AppNotifications.notifyControllerConnected(gameController)
    }

    @objc func disconnectController(sender: Any) {
        guard let item = sender as? NSMenuItem else { return }
        guard let gameController = item.representedObject as? GameController else { return }
        
        gameController.disconnect()
        self.updateControllersMenu()
    }
    
    func disconnectController(_ controller: JoyConSwift.Controller) {
        if let gameController = self.controllers.first(where: {
            $0.data.serialID == controller.serialID
        }) {
            gameController.backend = nil
            gameController.updateControllerIcon()
            NotificationCenter.default.post(name: .controllerDisconnected, object: gameController)

            AppNotifications.notifyControllerDisconnected(gameController)
        }
        self.updateControllersMenu()
    }

    func addController(_ controller: JoyConSwift.Controller) {
        guard let dataManager = self.dataManager else { return }
        let controllerData = dataManager.getControllerData(controller: controller)
        let gameController = GameController(data: controllerData)
        gameController.backend = JoyConBackend(controller: controller)
        gameController.startTimer()
        self.controllers.append(gameController)

        NotificationCenter.default.post(name: .controllerAdded, object: gameController)

        AppNotifications.notifyControllerConnected(gameController)
    }

    func removeController(_ controller: JoyConSwift.Controller) {
        guard let gameController = self.controllers.first(where: {
            $0.data.serialID == controller.serialID
        }) else { return }
        self.removeController(gameController: gameController)
    }

    func removeController(gameController controller: GameController) {
        controller.backend?.disconnect()

        self.dataManager?.delete(controller.data)
        self.controllers.removeAll(where: { $0 === controller })
        NotificationCenter.default.post(name: .controllerRemoved, object: controller)
    }

    // MARK: - Core Data Saving and Undo support

    @IBAction func saveAction(_ sender: AnyObject?) {
        _ = self.dataManager?.save()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        return self.dataManager?.undoManager
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let isSucceeded = self.dataManager?.save() ?? false
        
        if !isSucceeded {
            let question = NSLocalizedString("Could not save changes while quitting. Quit anyway?", comment: "Quit without saves error question message")
            let info = NSLocalizedString("Quitting now will lose any changes you have made since the last successful save", comment: "Quit without saves error question info");
            let quitButton = NSLocalizedString("Quit anyway", comment: "Quit anyway button title")
            let cancelButton = NSLocalizedString("Cancel", comment: "Cancel button title")
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = info
            alert.addButton(withTitle: quitButton)
            alert.addButton(withTitle: cancelButton)
            
            let answer = alert.runModal()
            if answer == .alertSecondButtonReturn {
                return .terminateCancel
            }
        }
        
        return .terminateNow
    }

    // MARK: - Context switch handling

    @objc func didActivateApp(notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let bundleID = app.bundleIdentifier else { return }

        resetMetaKeyState()

        // 任一手柄命中 passthrough 配置即触发全局 passthrough：
        // JoyConSwift 0.2.1 的 IOHIDManager seize 是全局的，无法 per-device，
        // 因此所有手柄同进同退。
        var anyPassthrough = false
        self.controllers.forEach { controller in
            if controller.switchApp(bundleID: bundleID) {
                anyPassthrough = true
            }
        }

        if anyPassthrough {
            // localizedName 在沙箱环境下可能为 nil，回退到 bundleID 末段。
            self.currentPassthroughAppName = app.localizedName ?? bundleID.components(separatedBy: ".").last ?? bundleID
            self.passthroughCoordinator?.requestPassthrough()
        } else {
            self.currentPassthroughAppName = nil
            self.passthroughCoordinator?.requestMapping()
        }
        // requestPassthrough/requestMapping 若状态未变不会 post 通知；
        // 但 App 名可能从一个 passthrough App 切到另一个，菜单文案需刷新。
        self.updateControllersMenu()
    }

    // MARK: - NSMenuDelegate (status bar menu)

    /// 标记由 `rebuildAgentMonitorRows` 注入的 menu items，便于下一次重建时清理。
    /// 与 `updateControllersMenu` 用的 9999 错开。
    private static let agentMenuItemTag = 9998

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rebuildAgentMonitorRows(in: menu)
        agentMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        agentMenuOpen = false
        agentRowViewsByProjectId.removeAll()
        agentHeaderItem = nil
    }

    private func rebuildAgentMonitorRows(in menu: NSMenu) {
        // 清理上一次注入的 agent 区块。
        menu.items.removeAll { $0.tag == AppDelegate.agentMenuItemTag }
        agentRowViewsByProjectId.removeAll()
        agentHeaderItem = nil

        let projects = self.agentMonitor?.lastProjects ?? []
        var insertIndex = 0

        // Header：标题 + 计数。
        let header = NSMenuItem()
        header.tag = AppDelegate.agentMenuItemTag
        header.isEnabled = false
        header.title = Self.headerTitle(forProjects: projects)
        menu.insertItem(header, at: insertIndex); insertIndex += 1
        agentHeaderItem = header

        // Project rows（自定义 view）。
        let now = Date()
        for p in projects {
            let item = NSMenuItem()
            item.tag = AppDelegate.agentMenuItemTag
            let rowView = AgentMenuRowView(project: p, now: now)
            item.view = rowView
            item.isEnabled = false
            menu.insertItem(item, at: insertIndex); insertIndex += 1
            agentRowViewsByProjectId[p.id] = rowView
        }

        // 与其余菜单内容（手柄状态 / About / Settings / Quit）的分隔。
        let sep = NSMenuItem.separator()
        sep.tag = AppDelegate.agentMenuItemTag
        menu.insertItem(sep, at: insertIndex); insertIndex += 1
    }

    /// 由 monitor.setEventHandler 在每轮 poll 后调用。
    /// 仅当状态栏 NSMenu 处于打开期间生效：按 project.id 命中已有 row 视图调用 configure，
    /// 并刷新 header 计数。新出现 / 已消失的 project 不在本次 tracking 期间增减 item，
    /// 留到下次菜单打开时由 rebuildAgentMonitorRows 重建。
    private func refreshOpenAgentMenuRows(event: AgentMonitorEvent) {
        guard agentMenuOpen else { return }
        let projects: [AgentProject]
        switch event {
        case .updated(let list): projects = list
        case .empty, .pollingFailed: projects = []
        }
        agentHeaderItem?.title = Self.headerTitle(forProjects: projects)
        let now = Date()
        for p in projects {
            agentRowViewsByProjectId[p.id]?.configure(with: p, now: now)
        }
    }

    private static func headerTitle(forProjects projects: [AgentProject]) -> String {
        let title = NSLocalizedString("agent.monitor.header.title", comment: "")
        if projects.isEmpty {
            let empty = NSLocalizedString("agent.monitor.empty.title", comment: "")
            return "\(title) — \(empty)"
        }
        let working = projects.reduce(0) { $0 + ($1.state == .idle ? 0 : 1) }
        let idle = projects.count - working
        let fmt = NSLocalizedString("agent.monitor.header.count.fmt", comment: "")
        let counts = String(format: fmt, working, idle)
        return "\(title) — \(counts)"
    }
}
