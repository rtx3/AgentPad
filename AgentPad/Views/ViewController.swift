//
//  ViewController.swift
//  AgentPad
//
//  Created by magicien on 2019/07/14.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit
import InputMethodKit
import JoyConSwift

class ViewController: NSViewController {

    @IBOutlet weak var controllerCollectionView: NSCollectionView!
    @IBOutlet weak var appTableView: NSTableView!
    @IBOutlet weak var appAddRemoveButton: NSSegmentedControl!
    @IBOutlet weak var configTableView: NSOutlineView!
    /// Options 按钮 outlet：Sync from Default 按钮锚到它的左侧。
    @IBOutlet weak var optionsButton: NSButton!

    /// 代码动态创建：把 default 配置同步覆盖到当前选中的 AppConfig。
    /// 选中 Default 行（或没选中）时禁用。锚点放在 optionsButton 左侧 8pt + centerY 对齐。
    private weak var syncFromDefaultButton: NSButton?

    /// 选中 passthrough AppConfig 时覆盖在 configTableView 之上的提示层。
    /// 半透明背景 + 居中文案；自身 hitTest 接管所有点击，防止透传期间误改键映射。
    private weak var passthroughOverlay: NSView?

    var appDelegate: AppDelegate? {
        return NSApplication.shared.delegate as? AppDelegate
    }
    var selectedController: GameController? {
        didSet {
            // appTableView outlet 已在 hideAppListSection 中随 enclosingScrollView removeFromSuperview
            // 被置 nil；用可选访问避免崩溃（IBOutlet weak ... ! 的强解包陷阱）。
            self.appTableView?.reloadData()
            self.configTableView.reloadData()
            self.updateAppAddRemoveButtonState()
            self.updateSyncButtonState()
            self.updatePassthroughOverlay()
        }
    }
    var selectedControllerData: ControllerData? {
        return self.selectedController?.data
    }
    // App 列表在 UI 上已完全隐藏（仅运行时隐藏，Core Data 数据保留）。
    // 所有手柄统一只使用各自的 defaultConfig；selectedAppConfig 恒为 nil。
    var selectedAppConfig: AppConfig? {
        return nil
    }
    var selectedKeyConfig: KeyConfig? {
        return self.selectedControllerData?.defaultConfig
    }
    var keyDownHandler: Any?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.preferredContentSize = NSSize(width: 520, height: 560)

        if self.controllerCollectionView == nil { return }
        
        self.controllerCollectionView.delegate = self
        self.controllerCollectionView.dataSource = self
        
        self.appTableView.delegate = self
        self.appTableView.dataSource = self
        
        self.configTableView.delegate = self
        self.configTableView.dataSource = self
        
        self.updateAppAddRemoveButtonState()

        // Options sheet has been promoted to the "General" tab in the Settings
        // window. Hide the button here so there's a single entry point; the
        // outlet + IBAction stay to keep the storyboard connection valid.
        self.optionsButton?.isHidden = true

        // App 列表整段隐藏（storyboard 不动；outlet 全部保留以维持 IB 连接）。
        // 旧的 per-App 配置 / passthrough 复选框 / Sync from Default 按钮 / passthrough overlay
        // 在新形态下都没有意义。所有手柄统一只用各自的 defaultConfig。
        self.hideAppListSection()

        // storyboard 那一行旧按钮在 hideAppListSection 后的约束塌掉、又是 transparent 样式，
        // 直接新建两个程序化按钮挂在根 view 左下角，与 storyboard 解耦。
        self.installImportExportButtons()

        NotificationCenter.default.addObserver(self, selector: #selector(controllerAdded), name: .controllerAdded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerRemoved), name: .controllerRemoved, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerConnected), name: .controllerConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerDisconnected), name: .controllerDisconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerIconChanged), name: .controllerIconChanged, object: nil)
    }
    
    override func viewDidDisappear() {

    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    // MARK: - Apps
    
    @IBAction func clickAppSegmentButton(_ sender: NSSegmentedControl) {
        let selectedSegment = sender.selectedSegment
        
        if selectedSegment == 0 {
            self.addApp()
        } else if selectedSegment == 1 {
            self.removeApp()
        }
    }
    
    func updateAppAddRemoveButtonState() {
        // App 列表已被 hideAppListSection 物理移除；这两个 outlet 都可能为 nil。
        // 用可选链全部静默跳过，逻辑保留不删（用户规则 9）。
        guard let appAddRemoveButton = self.appAddRemoveButton else { return }
        if self.selectedController == nil {
            appAddRemoveButton.setEnabled(false, forSegment: 0)
            appAddRemoveButton.setEnabled(false, forSegment: 1)
        } else if (self.appTableView?.selectedRow ?? -1) < 1 {
            appAddRemoveButton.setEnabled(true, forSegment: 0)
            appAddRemoveButton.setEnabled(false, forSegment: 1)
        } else {
            appAddRemoveButton.setEnabled(true, forSegment: 0)
            appAddRemoveButton.setEnabled(true, forSegment: 1)
        }
    }
    
    func addApp() {
        guard let controller = self.selectedController else { return }
        
        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("Choose an app to add", comment: "Choosing app message")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["app"]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { [weak self] response in
            if response == .OK {
                guard let url = panel.url else { return }
                controller.addApp(url: url)
                self?.appTableView?.reloadData()
            }
        }
    }
    
    func removeApp() {
        guard let controller = self.selectedController else { return }
        guard let appConfig = self.selectedAppConfig else { return }
        let appName = self.convertAppName(appConfig.app?.displayName)
        
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String.localizedStringWithFormat(NSLocalizedString("Do you really want to delete the settings for %@?", comment: "Do you really want to delete the settings for <app>?"), appName)
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        let result = alert.runModal()
        
        if result == .alertSecondButtonReturn {
            controller.removeApp(appConfig)
            self.appTableView?.reloadData()
            self.configTableView.reloadData()
        }
    }
    
    // MARK: - Sync from Default

    /// 在 optionsButton 左侧加一个"Sync from Default"按钮（与 Options 同行）。
    /// 用代码加而不是改 storyboard，避免同时维护 en/ja 两份 IB。
    private func installSyncFromDefaultButton() {
        guard let options = self.optionsButton, let parent = options.superview else { return }

        let btn = NSButton(title: NSLocalizedString("Sync from Default", comment: "Sync default key config to selected app config"),
                           target: self, action: #selector(syncFromDefault(_:)))
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle = options.bezelStyle
        btn.font = options.font
        parent.addSubview(btn)

        NSLayoutConstraint.activate([
            btn.trailingAnchor.constraint(equalTo: options.leadingAnchor, constant: -8),
            btn.centerYAnchor.constraint(equalTo: options.centerYAnchor)
        ])

        self.syncFromDefaultButton = btn
    }

    func updateSyncButtonState() {
        self.syncFromDefaultButton?.isEnabled = (self.selectedAppConfig != nil)
    }

    @objc func syncFromDefault(_ sender: NSButton) {
        guard let appConfig = self.selectedAppConfig else { return }
        guard let defaultConfig = self.selectedControllerData?.defaultConfig else { return }
        guard let dataManager = self.appDelegate?.dataManager else { return }
        let appName = self.convertAppName(appConfig.app?.displayName)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String.localizedStringWithFormat(
            NSLocalizedString("Overwrite the key mapping for %@ with the default configuration?",
                              comment: "Confirm sync-from-default action"),
            appName
        )
        alert.informativeText = NSLocalizedString("This cannot be undone for this app's existing key mapping.",
                                                  comment: "Sync-from-default informative text")
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        let undoManager = dataManager.undoManager
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName(NSLocalizedString("Sync from Default", comment: "Undo action name"))

        if let oldConfig = appConfig.config {
            dataManager.deleteKeyConfigDeeply(oldConfig)
        }
        appConfig.config = dataManager.cloneKeyConfig(from: defaultConfig)

        undoManager?.endUndoGrouping()
        _ = dataManager.save()

        // 如果该 App 正是当前前台 App，让正在运行的映射立刻刷新。
        if let bundleID = appConfig.app?.bundleID,
           let currentBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           bundleID == currentBundleID,
           let selectedController = self.selectedController {
            selectedController.updateKeyMap()
        }

        self.configTableView.reloadData()
    }

    // MARK: - Controllers

    @objc func controllerAdded() {
        DispatchQueue.main.async { [weak self] in
            self?.controllerCollectionView.reloadData()
        }
    }
    
    @objc func controllerConnected() {
        DispatchQueue.main.async { [weak self] in
            self?.controllerCollectionView.reloadData()
        }
    }
    
    @objc func controllerDisconnected() {
        DispatchQueue.main.async { [weak self] in
            self?.controllerCollectionView.reloadData()
        }
    }
    
    @objc func controllerRemoved(_ notification: NSNotification) {
        guard let gameController = notification.object as? GameController else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let _self = self else { return }
            let numItems = _self.controllerCollectionView.numberOfItems(inSection: 0)
            for i in 0..<numItems {
                if let item = self?.controllerCollectionView.item(at: i) as? ControllerViewItem {
                    if item.controller === gameController {
                        self?.controllerCollectionView.deselectAll(nil)
                    }
                }
            }
            self?.controllerCollectionView.reloadData()
        }
    }
    
    @objc func controllerIconChanged(_ notification: NSNotification) {
        guard let gameController = notification.object as? GameController else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.controllerCollectionView.reloadData()
        }
    }
    
    // MARK: - Import

    @IBAction func importKeyMappings(_ sender: NSButton) {
        guard let dataManager = self.appDelegate?.dataManager else { return }
        guard let controllerData = self.selectedControllerData,
              let controller = self.selectedController else {
            self.runNoControllerAlert()
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.message = NSLocalizedString("Choose a key mapping file to import", comment: "Import open panel message")
        openPanel.allowedFileTypes = ["json", "jkmap"]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false

        openPanel.beginSheetModal(for: self.view.window!) { response in
            guard response == .OK, let url = openPanel.url else { return }
            self.performImport(url: url, controllerData: controllerData, controller: controller, dataManager: dataManager)
        }
    }

    private func performImport(url: URL, controllerData: ControllerData, controller: GameController, dataManager: DataManager) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            self.runErrorAlert(title: NSLocalizedString("Failed to read file", comment: "Import error title"), error: error)
            return
        }

        // 第一遍 decode：仅校验 kind 是否一致；不一致先弹 warning 让用户确认。
        // 不一致也可继续——宽松模式，丢弃多余键。
        do {
            let preview = try KeyConfigCodec.decode(data)
            let targetKind = controllerData.type ?? "unknown"
            if preview.kind != targetKind {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Controller type does not match", comment: "Import kind mismatch alert title")
                let fmt = NSLocalizedString("This file was exported from a %@ controller, but the selected controller is %@. Keys that do not exist on the target controller will be ignored. Continue?", comment: "Import kind mismatch alert body")
                alert.informativeText = String(format: fmt, preview.kind, targetKind)
                alert.addButton(withTitle: NSLocalizedString("Import", comment: "Import button"))
                alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
                alert.alertStyle = .warning
                if alert.runModal() != .alertFirstButtonReturn { return }
            }
        } catch {
            self.runErrorAlert(title: NSLocalizedString("Invalid key mapping file", comment: "Import decode error title"), error: error)
            return
        }

        // 第二遍：真正写入。
        let summary: DataManager.ImportSummary
        do {
            summary = try dataManager.importDefaultConfig(data, into: controllerData)
        } catch {
            self.runErrorAlert(title: NSLocalizedString("Failed to import key mappings", comment: "Import write error title"), error: error)
            return
        }

        _ = dataManager.save()
        controller.updateKeyMap()
        self.configTableView?.reloadData()

        let info = String(
            format: NSLocalizedString("Imported %d key mapping(s). Skipped %d.", comment: "Import success info"),
            summary.applied,
            summary.skippedButtons.count
        )
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Import completed", comment: "Import success alert title")
        alert.informativeText = info
        alert.alertStyle = .informational
        alert.runModal()
    }

    // MARK: - Export

    @IBAction func exportKeyMappngs(_ sender: NSButton) {
        guard let dataManager = self.appDelegate?.dataManager else { return }
        guard let controllerData = self.selectedControllerData else {
            self.runNoControllerAlert()
            return
        }

        let data: Data
        do {
            data = try dataManager.exportDefaultConfig(of: controllerData)
        } catch {
            self.runErrorAlert(title: NSLocalizedString("Failed to export key mappings", comment: "Export encode error title"), error: error)
            return
        }

        let savePanel = NSSavePanel()
        savePanel.message = NSLocalizedString("Save key mapping data", comment: "Save key mapping data")
        savePanel.allowedFileTypes = ["json"]
        let kindHint = controllerData.type ?? "controller"
        savePanel.nameFieldStringValue = "agentpad-\(kindHint)-mapping.json"

        savePanel.beginSheetModal(for: self.view.window!) { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                self.runErrorAlert(title: NSLocalizedString("Failed to save file", comment: "Export write error title"), error: error)
            }
        }
    }

    private func runNoControllerAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("No controller selected", comment: "No controller selected alert title")
        alert.informativeText = NSLocalizedString("Select a controller before importing or exporting.", comment: "No controller selected alert body")
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func runErrorAlert(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
    
    // MARK: - Options
    
    @IBAction func didPushOptions(_ sender: NSButton) {
        guard let controller = self.storyboard?.instantiateController(withIdentifier: "AppSettingsViewController") as? AppSettingsViewController else { return }

        self.presentAsSheet(controller)
    }

    // MARK: - Passthrough overlay

    /// 创建覆盖在 configTableView 滚动区域上的提示层（半透明背景 + 居中 label）。
    /// 默认隐藏；selectedAppConfig.passthrough 时显示。
    private func installPassthroughOverlay() {
        guard let scroll = self.configTableView?.enclosingScrollView,
              let parent = scroll.superview else { return }

        let overlay = PassthroughOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.wantsLayer = true
        // 半透明遮罩，沿用系统窗口背景色避免暗色 / 亮色模式偏色。
        overlay.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        overlay.isHidden = true

        let label = NSTextField(labelWithString: NSLocalizedString("This app uses the controller directly. No mapping.",
                                                                    comment: "Passthrough overlay text"))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.textColor = .secondaryLabelColor
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1, weight: .medium)
        overlay.addSubview(label)

        parent.addSubview(overlay, positioned: .above, relativeTo: scroll)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: scroll.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -16)
        ])

        self.passthroughOverlay = overlay
    }

    /// 根据当前 selectedAppConfig.passthrough 显示/隐藏 overlay。
    /// 由 selectedController.didSet / tableViewSelectionDidChange / togglePassthrough 触发。
    func updatePassthroughOverlay() {
        let shouldShow = self.selectedAppConfig?.passthrough ?? false
        self.passthroughOverlay?.isHidden = !shouldShow
    }

    // MARK: - Hide App list

    /// 隐藏 App 列表所在的左栏 + 加减按钮 + "Apps" 标题。
    /// storyboard 完全不动；旧 Core Data 数据保留。
    ///
    /// 实现策略：直接把 App scrollView 从 splitView 中 removeFromSuperview。
    /// 之前试过 setPosition(0) + canCollapseSubview / shouldHideDividerAt delegate
    /// 但 storyboard 的 splitView `arrangesAllSubviews="NO"` 且未显式声明 arrangedSubviews，
    /// 导致 NSSplitView 的"hide subview 自动收回空间"行为不生效，用户仍能看到并拖动左栏。
    /// 物理移除后 splitView 只剩 KeyMap scrollView 一个子视图，自然占满 splitView frame，
    /// 也不再有 divider 可拖。appTableView weak outlet 释放后续访问代码均不会被实际触发
    /// （addApp / removeApp 入口按钮已隐藏；togglePassthrough 依赖列表行点击）。
    /// storyboard 里 Import / Export 按钮的 leading 都靠 appAddRemoveButton(+/-)，
    /// 后者 isHidden=true 后整条约束链塌、按钮被推出窗口；transparent=YES 又让它们在
    /// 暗色模式下完全不可见。这里不再去搬旧按钮，直接新建两个完全程序化的按钮、
    /// 用硬约束钉在窗口左下角，与 storyboard 解耦。
    private func installImportExportButtons() {
        let root: NSView = self.view

        let importBtn = NSButton(
            title: NSLocalizedString("Import", comment: "Import key mappings button"),
            target: self,
            action: #selector(self.importKeyMappings(_:))
        )
        importBtn.bezelStyle = .rounded
        importBtn.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(importBtn)

        let exportBtn = NSButton(
            title: NSLocalizedString("Export", comment: "Export key mappings button"),
            target: self,
            action: #selector(self.exportKeyMappngs(_:))
        )
        exportBtn.bezelStyle = .rounded
        exportBtn.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(exportBtn)

        NSLayoutConstraint.activate([
            importBtn.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            importBtn.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            importBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            exportBtn.leadingAnchor.constraint(equalTo: importBtn.trailingAnchor, constant: 12),
            exportBtn.centerYAnchor.constraint(equalTo: importBtn.centerYAnchor),
            exportBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
    }

    private func hideAppListSection() {
        // 1) App 表所在的 scrollView 物理移除——这是真正让左栏消失的关键。
        if let appScrollView = self.appTableView?.enclosingScrollView {
            let splitView = appScrollView.superview as? NSSplitView
            appScrollView.removeFromSuperview()
            splitView?.adjustSubviews()
        }

        // 2) "+/-" 加减按钮隐藏。
        self.appAddRemoveButton?.isHidden = true

        // 3) "Apps" 标题：storyboard 里没有 outlet，按文案匹配父视图下的兄弟 textField。
        //    匹配既要兼容 EN/JA/zh-Hans，所以按"挨着 segmented control 的 textField"找——
        //    位置上 Apps 标签的底 y 紧贴 appAddRemoveButton 的 segmented control 上方。
        if let host = self.appAddRemoveButton?.superview {
            for sub in host.subviews {
                guard let tf = sub as? NSTextField, !tf.isEditable else { continue }
                // 不动 "Controllers" 标签（它在窗口左上角，y 比 Apps 标签高很多）。
                let title = tf.stringValue
                if title == "Apps" || title == "アプリケーション" || title == "应用" || title == "App" {
                    tf.isHidden = true
                }
            }
        }
    }
}

/// 接管 hitTest，确保 overlay 显示时点击不会穿透到底下的 outlineView。
final class PassthroughOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // 仅当自身可见时拦截事件；隐藏时让点击穿透到底下控件。
        if self.isHidden { return nil }
        return self
    }
}
