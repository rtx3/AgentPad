//
//  ViewController.swift
//  ControllerKeyMapper
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

    var appDelegate: AppDelegate? {
        return NSApplication.shared.delegate as? AppDelegate
    }
    var selectedController: GameController? {
        didSet {
            self.appTableView.reloadData()
            self.configTableView.reloadData()
            self.updateAppAddRemoveButtonState()
            self.updateSyncButtonState()
        }
    }
    var selectedControllerData: ControllerData? {
        return self.selectedController?.data
    }
    var selectedAppConfig: AppConfig? {
        guard let data = self.selectedControllerData else {
            return nil
        }
        let row = self.appTableView.selectedRow
        if row < 1 {
            return nil
        }
        return data.appConfigs?[row - 1] as? AppConfig
    }
    var selectedKeyConfig: KeyConfig? {
        if self.appTableView.selectedRow < 0 {
            return nil
        }
        return self.selectedAppConfig?.config ?? self.selectedControllerData?.defaultConfig
    }
    var keyDownHandler: Any?

    override func viewDidLoad() {
        super.viewDidLoad()

        if self.controllerCollectionView == nil { return }
        
        self.controllerCollectionView.delegate = self
        self.controllerCollectionView.dataSource = self
        
        self.appTableView.delegate = self
        self.appTableView.dataSource = self
        
        self.configTableView.delegate = self
        self.configTableView.dataSource = self
        
        self.updateAppAddRemoveButtonState()

        self.installSyncFromDefaultButton()
        self.updateSyncButtonState()

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
        if self.selectedController == nil {
            self.appAddRemoveButton.setEnabled(false, forSegment: 0)
            self.appAddRemoveButton.setEnabled(false, forSegment: 1)
        } else if self.appTableView.selectedRow < 1 {
            self.appAddRemoveButton.setEnabled(true, forSegment: 0)
            self.appAddRemoveButton.setEnabled(false, forSegment: 1)
        } else {
            self.appAddRemoveButton.setEnabled(true, forSegment: 0)
            self.appAddRemoveButton.setEnabled(true, forSegment: 1)
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
                self?.appTableView.reloadData()
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
            self.appTableView.reloadData()
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
    }
    
    // MARK: - Export
    
    @IBAction func exportKeyMappngs(_ sender: NSButton) {
        return
        /*
        guard let dataManager = self.appDelegate?.dataManager else { return }

        let savePanel = NSSavePanel()
        savePanel.message = NSLocalizedString("Save key mapping data", comment: "Save key mapping data")
        savePanel.allowedFileTypes = ["jkmap"]
        
        savePanel.begin { response in
            guard response == .OK else { return }
            guard let filePath = savePanel.url?.absoluteString.removingPercentEncoding else { return }
        }
        */
    }
    
    // MARK: - Options
    
    @IBAction func didPushOptions(_ sender: NSButton) {
        guard let controller = self.storyboard?.instantiateController(withIdentifier: "AppSettingsViewController") as? AppSettingsViewController else { return }
        
        self.presentAsSheet(controller)
    }
}
