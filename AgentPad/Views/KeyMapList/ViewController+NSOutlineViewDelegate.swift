//
//  ViewController+NSOutlineViewDelegate.swift
//  AgentPad
//
//  Created by magicien on 2019/07/23.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit
import JoyConSwift

let buttonNames: [JoyCon.Button: String] = [
    .Up: "Up",
    .Right: "Right",
    .Down: "Down",
    .Left: "Left",
    .A: "A",
    .B: "B",
    .X: "X",
    .Y: "Y",
    .L: "L",
    .ZL: "ZL",
    .R: "R",
    .ZR: "ZR",
    .Minus: "Minus",
    .Plus: "Plus",
    .Capture: "Capture",
    .Home: "Home",
    .LStick: "LStick Push",
    .RStick: "RStick Push",
    .LeftSL: "Left SL",
    .LeftSR: "Left SR",
    .RightSL: "Right SL",
    .RightSR: "Right SR",
    .Start: "Start",
    .Select: "Select",
]
let directionNames: [JoyCon.StickDirection: String]  = [
    .Up: "Up",
    .Right: "Right",
    .Down: "Down",
    .Left: "Left"
]
let leftStickName = NSLocalizedString("Left Stick", comment: "Left Stick")
let rightStickName = NSLocalizedString("Right Stick", comment: "Right Stick")

let controllerButtons: [JoyCon.ControllerType: [JoyCon.Button]] = [
    .JoyConL: [.Up, .Right, .Down, .Left, .LeftSL, .LeftSR, .L, .ZL, .Minus, .Capture, .LStick],
    .JoyConR: [.A, .B, .X, .Y, .RightSL, .RightSR, .R, .ZR, .Plus, .Home, .RStick],
    .ProController: [.A, .B, .X, .Y, .L, .ZL, .R, .ZR, .Up, .Right, .Down, .Left, .Minus, .Plus, .Capture, .Home, .LStick, .RStick],
    .FamicomController1: [.A, .B, .L, .R, .Up, .Right, .Down, .Left, .Start, .Select],
    .FamicomController2: [.A, .B, .L, .R, .Up, .Right, .Down, .Left],
    .SNESController: [.A, .B, .X, .Y, .L, .ZL, .R, .ZR, .Up, .Right, .Down, .Left, .Start, .Select],
]
let numSticks: [JoyCon.ControllerType: Int] = [
    .JoyConL: 1,
    .JoyConR: 1,
    .ProController: 2,
    .FamicomController1: 0,
    .FamicomController2: 0,
    .SNESController: 0
]
let stickerDirections: [JoyCon.StickDirection] = [
    .Up, .Right, .Down, .Left
]
let stickTypes: [StickType] = [
    .Key, .Mouse, .MouseWheel, .None
]

let buttonNameColumnID = "buttonName"
let buttonKeyColumnID = "buttonKey"

class StickSpeedField: NSTextField {
    var config: KeyConfig
    var stick: JoyCon.Button

    init(frame frameRect: NSRect, config: KeyConfig, stick: JoyCon.Button) {
        self.config = config
        self.stick = stick
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func textDidEndEditing(_ notification: Notification) {
        if self.stick == .LStick {
            self.config.leftStick?.speed = self.floatValue
        } else if self.stick == .RStick {
            self.config.rightStick?.speed = self.floatValue
        }
    }
}

/// Speed 控件用 slider 替代 textField——textField 路径下 NSOutlineView 的 cell editor
/// 不放权给嵌套 NSTextField 直接接键盘事件，编辑体验断掉。
/// 范围 1–50：与 createStickConfig 默认 10.0 / GameController.stickMouseHandler 中
/// `pos.x * speed` 的乘子语义匹配；超过 50 鼠标会瞬移半屏，没有实用价值。
final class StickSpeedSlider: NSSlider {
    var config: KeyConfig
    var stick: JoyCon.Button

    init(config: KeyConfig, stick: JoyCon.Button) {
        self.config = config
        self.stick = stick
        super.init(frame: .zero)
        // minValue=0 让用户可把鼠标静止；maxValue=30 是 stickMouseHandler 中
        // `pos.x * speed` 乘子的实用上限（旧默认 10.0，>30 后单帧位移 30px 已经
        // 远超屏幕滚动直觉，用户报告"速度很快"主要由更大的值引起）。
        self.minValue = 0
        self.maxValue = 30
        self.isContinuous = true
        self.target = self
        self.action = #selector(handleChange(_:))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleChange(_ sender: NSSlider) {
        writeBack(value: Float(sender.doubleValue))
    }

    /// stickMouseView 会覆盖 action 改用本方法，以便拖动时实时刷新右侧数值 label。
    @objc func handleChangeWithLabel(_ sender: NSSlider) {
        let v = Float(sender.doubleValue)
        writeBack(value: v)
        if let label = objc_getAssociatedObject(sender, &stickSpeedLabelAssocKey) as? NSTextField {
            label.stringValue = "\(Int(v.rounded()))"
        }
    }

    private func writeBack(value: Float) {
        if self.stick == .LStick {
            self.config.leftStick?.speed = value
        } else if self.stick == .RStick {
            self.config.rightStick?.speed = value
        }
    }
}

/// Slider 旁边数值 label 的 associated object key。
private var stickSpeedLabelAssocKey: UInt8 = 0

extension ViewController: NSOutlineViewDelegate, NSOutlineViewDataSource, KeyConfigSetDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard self.selectedKeyConfig != nil else { return 0 }
        guard let controller = self.selectedController else { return 0 }
        guard let buttons = controllerButtons[controller.type] else { return 0 }
        guard let config = self.selectedKeyConfig else { return 0 }
        
        if controller.type == .unknown {
            return 0
        }
        
        if let indexOfItem = item as? Int {
            let stickIndex = indexOfItem - buttons.count

            // Stick settings
            if controller.type == .JoyConL {
                return self.numberOfChildItemOfStick(for: config.leftStick?.type)
            }

            if controller.type == .JoyConR {
                return self.numberOfChildItemOfStick(for: config.rightStick?.type)
            }

            if controller.type == .ProController {
                if stickIndex == 0 {
                    return self.numberOfChildItemOfStick(for: config.leftStick?.type)
                }
                if stickIndex == 1 {
                    return self.numberOfChildItemOfStick(for: config.rightStick?.type)
                }
            }

            return 0
        }
        
        return buttons.count + (numSticks[controller.type] ?? 0)
    }
    
    func numberOfChildItemOfStick(for type: String?) -> Int {
        guard let typeStr = type else { return 0 }
        
        switch(typeStr) {
        case StickType.Key.rawValue:
            return 4
        case StickType.Mouse.rawValue:
            return 1
        case StickType.MouseWheel.rawValue:
            return 1
        default:
            return 0
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let controller = self.selectedController else { return false }
        guard let config = self.selectedKeyConfig else { return false }
        guard let buttons = controllerButtons[controller.type] else { return false }
        guard let itemIndex = item as? Int else { return false }

        let stickIndex = itemIndex - buttons.count

        if stickIndex < 0 {
            return false
        }
        
        if controller.type == .JoyConL {
            return self.isStickItemExpandable(for: config.leftStick?.type)
        }
        
        if controller.type == .JoyConR {
            return self.isStickItemExpandable(for: config.rightStick?.type)
        }
        
        if controller.type == .ProController {
            if stickIndex == 0 {
                return self.isStickItemExpandable(for: config.leftStick?.type)
            }
            if stickIndex == 1 {
                return self.isStickItemExpandable(for: config.rightStick?.type)
            }
        }
        
        return false
    }
    
    func isStickItemExpandable(for type: String?) -> Bool {
        guard let typeString = type else { return false }
        
        if typeString == StickType.None.rawValue {
            return false
        }
        
        return true
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let parentItem = item as? Int else { return index }
        guard let controller = self.selectedController else { return false }
        guard let buttons = controllerButtons[controller.type] else { return false }

        let stickIndex = parentItem - buttons.count
        if stickIndex < 0 { return false }

        if controller.type == .JoyConL {
            return (JoyCon.Button.LStick, index)
        }
        
        if controller.type == .JoyConR {
            return (JoyCon.Button.RStick, index)
        }
        
        if controller.type == .ProController {
            if stickIndex == 0 {
                return (JoyCon.Button.LStick, index)
            }
            
            if stickIndex == 1 {
                return (JoyCon.Button.RStick, index)
            }

            return "unknown index"
        }
        
        return "unknown controller"
    }
    
    func stickDirectionView(stick: JoyCon.Button, column: NSTableColumn, row: Int) -> NSView? {
        guard let keyConfig = self.selectedKeyConfig else { return nil }
        
        var stickConfig: StickConfig
        if stick == .LStick {
            guard let conf = keyConfig.leftStick else { return nil }
            stickConfig = conf
        } else if stick == .RStick {
            guard let conf = keyConfig.rightStick else { return nil }
            stickConfig = conf
        } else {
            return nil
        }
        
        if column.identifier.rawValue == buttonNameColumnID {
            guard let itemView = self.configTableView.makeView(withIdentifier: column.identifier, owner: self) as? ButtonNameCellView else {
                return nil
            }

            let view = NSTextView(frame: NSRect(origin: CGPoint.zero, size: itemView.frame.size))
            view.isEditable = false
            view.font = itemView.buttonName.font
            view.backgroundColor = .clear

            if stick == .LStick {
                view.string = leftStickName
            } else if stick == .RStick {
                view.string = rightStickName
            }
            
            return view
        }
        
        if column.identifier.rawValue == buttonKeyColumnID {
            guard let itemView = self.configTableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView else {
                return nil
            }

            let selection = NSPopUpButton(frame: NSRect(origin: CGPoint.zero, size: itemView.frame.size))
            stickTypes.forEach { type in
                selection.addItem(withTitle: NSLocalizedString(type.rawValue, comment: ""))
                selection.lastItem?.representedObject = type
            }
            
            if stickConfig.type == StickType.Mouse.rawValue {
                selection.selectItem(at: 1)
            } else if stickConfig.type == StickType.MouseWheel.rawValue {
                selection.selectItem(at: 2)
            } else if stickConfig.type == StickType.None.rawValue {
                selection.selectItem(at: 3)
            } else {
                // Default: .Key
                selection.selectItem(at: 0)
            }
            
            if stick == .LStick {
                selection.action = Selector(("leftStickTypeDidChange:"))
            } else if stick == .RStick {
                selection.action = Selector(("rightStickTypeDidChange:"))
            }
            selection.target = self
                
            return selection
        }
        
        return nil
    }
    
    func stickChildView(stick: JoyCon.Button, column: NSTableColumn, row: Int) -> NSView? {
        guard let config = self.selectedKeyConfig else { return nil }

        var type: String
        if stick == .LStick {
            guard let typeString = config.leftStick?.type else { return nil }
            type = typeString
        } else if stick == .RStick {
            guard let typeString = config.rightStick?.type else { return nil }
            type = typeString
        } else {
            return nil
        }
        
        if type == StickType.Key.rawValue {
            return self.stickDirectionKeyView(stick: stick, column: column, row: row)
        } else if type == StickType.Mouse.rawValue || type == StickType.MouseWheel.rawValue {
            return self.stickMouseView(stick: stick, column: column, row: row)
        }
        
        return nil
    }
    
    func stickMouseView(stick: JoyCon.Button, column: NSTableColumn, row: Int) -> NSView? {
        guard self.selectedController != nil else { return nil }
        guard let keyConfig = self.selectedKeyConfig else { return nil }

        var stickConfig: StickConfig
        if stick == .LStick {
            guard let conf = keyConfig.leftStick else { return nil }
            stickConfig = conf
        } else if stick == .RStick {
            guard let conf = keyConfig.rightStick else { return nil }
            stickConfig = conf
        } else {
            return nil
        }
        
        if column.identifier.rawValue == buttonNameColumnID {
            guard let itemView = self.configTableView.makeView(withIdentifier: column.identifier, owner: self) as? ButtonNameCellView else {
                return nil
            }

            let view = NSTextView(frame: NSRect(origin: CGPoint.zero, size: itemView.frame.size))
            view.isEditable = false
            view.font = itemView.buttonName.font
            view.string = NSLocalizedString("Speed", comment: "Speed")
            view.backgroundColor = .clear
            
            return view
        }
        
        if column.identifier.rawValue == buttonKeyColumnID {
            guard let itemView = self.configTableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView else {
                return nil
            }

            // Speed 用滑块代替文本框（NSOutlineView 嵌套 NSTextField 编辑路径不可靠）。
            // 右侧加一个紧凑数值 label，拖动时实时刷新让用户感知当前速度。
            // 清掉 prototype 自带的只读 label，避免遮挡 hit test。
            itemView.textField?.removeFromSuperview()
            itemView.textField = nil

            let slider = StickSpeedSlider(config: keyConfig, stick: stick)
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.doubleValue = Double(stickConfig.speed)

            let valueLabel = NSTextField(labelWithString: "\(Int(stickConfig.speed.rounded()))")
            valueLabel.translatesAutoresizingMaskIntoConstraints = false
            valueLabel.alignment = .right
            valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
            valueLabel.textColor = .secondaryLabelColor

            // 拖动时实时刷新 label：在 slider 的 action 之外多挂一个 target 走 NotificationCenter。
            // 用简单方案——把 valueLabel 通过 associated object 或 closure 绑定到 slider
            // 都比 NotificationCenter 干净，但 NSSlider 不支持 closure target；
            // 这里用一个 small inline 类把 valueLabel 引用握住，slider 改值时刷新。
            slider.action = #selector(StickSpeedSlider.handleChangeWithLabel(_:))
            objc_setAssociatedObject(slider, &stickSpeedLabelAssocKey,
                                     valueLabel, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            itemView.addSubview(slider)
            itemView.addSubview(valueLabel)
            NSLayoutConstraint.activate([
                slider.leadingAnchor.constraint(equalTo: itemView.leadingAnchor, constant: 2),
                slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -6),
                slider.centerYAnchor.constraint(equalTo: itemView.centerYAnchor),
                valueLabel.trailingAnchor.constraint(equalTo: itemView.trailingAnchor, constant: -4),
                valueLabel.centerYAnchor.constraint(equalTo: itemView.centerYAnchor),
                valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            ])

            return itemView
        }
        
        return nil
    }
    
    func stickDirectionKeyView(stick: JoyCon.Button, column: NSTableColumn, row: Int) -> NSView? {
        guard self.selectedController != nil else { return nil }
        guard let keyConfig = self.selectedKeyConfig else { return nil }

        var stickConfig: StickConfig
        if stick == .LStick {
            guard let conf = keyConfig.leftStick else { return nil }
            stickConfig = conf
        } else if stick == .RStick {
            guard let conf = keyConfig.rightStick else { return nil }
            stickConfig = conf
        } else {
            return nil
        }
        
        guard let keyMaps = stickConfig.keyMaps else { return nil }
        let direction = stickerDirections[row]
        let directionName = directionNames[direction] ?? ""
        guard let keyMap = keyMaps.first(where: { map in
            guard let keyMap = map as? KeyMap else { return false }
            return keyMap.button == directionName
        }) as? KeyMap else { return nil }
        
        if column.identifier.rawValue == buttonNameColumnID {
            guard let itemView = self.configTableView.makeView(withIdentifier: column.identifier, owner: self) as? ButtonNameCellView else {
                return nil
            }
            
            itemView.buttonName.state = keyMap.isEnabled ? .on : .off
            itemView.buttonName.title = displayName(forStickDirection: directionName)
            itemView.buttonName.identifier = NSUserInterfaceItemIdentifier(directionName)
            if stick == .LStick {
                itemView.buttonName.action = Selector(("leftStickDirectionCheckDidChange:"))
            } else if stick == .RStick {
                itemView.buttonName.action = Selector(("rightStickDirectionCheckDidChange:"))
            }
            itemView.buttonName.target = self
            
            return itemView
        }
        
        if column.identifier.rawValue == buttonKeyColumnID {
            guard let itemView = self.configTableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView else {
                return nil
            }
            
            let keyName = convertKeyName(keyMap: keyMap)
            itemView.textField?.stringValue = keyName
            
            return itemView
        }
        
        return nil
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let column = tableColumn else { return nil }

        if let (stickButton, stickIndex) = item as? (JoyCon.Button, Int) {
            return self.stickChildView(stick: stickButton, column: column, row: stickIndex)
        }

        guard let row = item as? Int else { return nil }
        guard let controller = self.selectedController else { return nil }
        guard let config = self.selectedKeyConfig else { return nil }
        guard let buttons = controllerButtons[controller.type] else { return nil }
        if row >= buttons.count {
            if controller.type == .JoyConL {
                return self.stickDirectionView(stick: .LStick, column: column, row: row)
            }
            if controller.type == .JoyConR {
                return self.stickDirectionView(stick: .RStick, column: column, row: row)
            }
            if controller.type == .ProController {
                if row - buttons.count == 0 {
                    return self.stickDirectionView(stick: .LStick, column: column, row: row)
                }
                return self.stickDirectionView(stick: .RStick, column: column, row: row)
            }
            return nil
        }
        let button = buttons[row]
        
        let keyMap = config.keyMaps?.first(where: { map in
            guard let keyMap = map as? KeyMap else { return false }
            return keyMap.button == buttonNames[button]
        }) as? KeyMap
        
        if column.identifier.rawValue == buttonNameColumnID {
            guard let itemView = outlineView.makeView(withIdentifier: column.identifier, owner: self) as? ButtonNameCellView else {
                return nil
            }
            
            itemView.buttonName.state = (keyMap?.isEnabled ?? false) ? .on : .off
            itemView.buttonName.title = displayName(forLegacyButton: buttonNames[button] ?? "", kind: controller.kind)
            itemView.buttonName.identifier = NSUserInterfaceItemIdentifier(buttonNames[button] ?? "")
            itemView.buttonName.action = Selector(("checkDidChange:"))
            itemView.buttonName.target = self
            
            return itemView
        }
        
        if column.identifier.rawValue == buttonKeyColumnID {
            guard let itemView = outlineView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView else {
                return nil
            }
            
            let keyName = convertKeyName(keyMap: keyMap)
            itemView.textField?.stringValue = keyName

            return itemView
        }
        
        return nil
    }
    
    @IBAction func didClick(_ sender: AnyObject) {
        guard self.keyDownHandler == nil else { return }
        guard let type = self.selectedController?.type else { return }

        let selectedRow = self.configTableView.selectedRow
        let item = self.configTableView.item(atRow: selectedRow)
        
        if let rowIndex = item as? Int {
            guard let buttons = controllerButtons[type] else { return }
            guard rowIndex < buttons.count else { return }
            let button = buttons[rowIndex]
            self.didClick(button: button)
            return
        }
        
        if let (stick, rowIndex) = item as? (JoyCon.Button, Int) {
            let type: String
            if stick == .LStick {
                guard let typeString = self.selectedKeyConfig?.leftStick?.type else { return }
                type = typeString
            } else if stick == .RStick {
                guard let typeString = self.selectedKeyConfig?.rightStick?.type else { return }
                type = typeString
            } else {
                return
            }
            
            if type == StickType.Key.rawValue {
                let direction = stickerDirections[rowIndex]
                self.didClick(stick: stick, direction: direction)
            }
            return
        }
    }
    
    func didClick(button: JoyCon.Button) {
        guard let buttonName = buttonNames[button] else { return }
        
        var keyMap = self.selectedKeyConfig?.keyMaps?.first(where: { map in
            guard let keyMap = map as? KeyMap else { return false }
            return keyMap.button == buttonName
        }) as? KeyMap
        if keyMap == nil {
            keyMap = self.appDelegate?.dataManager?.createKeyMap()
            keyMap?.button = buttonName
            guard let map = keyMap else { return }
            self.selectedKeyConfig?.addToKeyMaps(map)
        }
        guard let map = keyMap else { return }
        
        guard let controller = self.storyboard?.instantiateController(withIdentifier: "KeyConfigViewController") as? KeyConfigViewController else { return }
        controller.keyMap = map
        controller.controllerKind = self.selectedController?.kind ?? .unknown
        controller.delegate = self

        self.presentAsSheet(controller)
    }

    func didClick(stick: JoyCon.Button, direction: JoyCon.StickDirection) {
        guard let directionName = directionNames[direction] else { return }

        var stickConfigData: StickConfig? = nil
        if stick == .LStick {
            stickConfigData = self.selectedKeyConfig?.leftStick
        } else if stick == .RStick {
            stickConfigData = self.selectedKeyConfig?.rightStick
        }
        guard let stickConfig = stickConfigData else { return }

        var keyMap: KeyMap? = stickConfig.keyMaps?.first(where: { map in
            guard let keyMap = map as? KeyMap else { return false }
            return keyMap.button == directionName
        }) as? KeyMap
        if keyMap == nil {
            keyMap = self.appDelegate?.dataManager?.createKeyMap()
            keyMap?.button = directionName
            guard let map = keyMap else { return }
            stickConfig.addToKeyMaps(map)
        }
        guard let map = keyMap else { return }
        
        guard let controller = self.storyboard?.instantiateController(withIdentifier: "KeyConfigViewController") as? KeyConfigViewController else { return }
        controller.keyMap = map
        controller.controllerKind = self.selectedController?.kind ?? .unknown
        controller.delegate = self

        self.presentAsSheet(controller)
    }

    func setKeyConfig(controller: KeyConfigViewController, keyMap: KeyMap) {
        // 关键：仅 reload UI 不够——首次给某按钮配置时 didClick(button:) 走的是
        // createKeyMap + addToKeyMaps 分支，新建的 KeyMap 不在 GameController.currentConfig
        // 字典里；不刷字典的话，按手柄按键时 buttonPressHandler 拿到的 config 是 nil 直接返回，
        // 表现就是"Simple 模式按方向键无响应"。这里显式触发字典重建。
        self.selectedController?.updateKeyMap()
        self.configTableView.reloadData()
    }
    
    @objc func checkDidChange(_ sender: NSButton) {
        guard let controller = self.selectedController else { return }
        guard let config = self.selectedKeyConfig else { return }
        guard let keyMaps = config.keyMaps else { return }

        let buttonName = sender.identifier?.rawValue ?? sender.title
        let result = keyMaps.first(where: { map in
            guard let keyMap = map as? KeyMap else { return false }
            return keyMap.button == buttonName
        })
        guard let keyMapData = result as? KeyMap else {
            guard let keyMap = self.appDelegate?.dataManager?.createKeyMap() else { return }
            keyMap.button = buttonName
            keyMap.isEnabled = sender.state == .on
            config.addToKeyMaps(keyMap)
            controller.updateKeyMap()

            return
        }
        keyMapData.isEnabled = sender.state == .on
        
        controller.updateKeyMap()
    }
    
    @objc func leftStickTypeDidChange(_ sender: NSPopUpButton) {
        guard let config = self.selectedKeyConfig else { return }
        let type = sender.selectedItem?.representedObject as? StickType
        config.leftStick?.type = type?.rawValue ?? ""
        self.configTableView.reloadData()
        self.selectedController?.updateKeyMap()
    }
    
    @objc func rightStickTypeDidChange(_ sender: NSPopUpButton) {
        guard let config = self.selectedKeyConfig else { return }
        let type = sender.selectedItem?.representedObject as? StickType
        config.rightStick?.type = type?.rawValue ?? ""
        self.configTableView.reloadData()
        self.selectedController?.updateKeyMap()
    }
    
    @objc func leftStickDirectionCheckDidChange(_ sender: NSButton) {
        guard let controller = self.selectedController else { return }
        guard let config = self.selectedKeyConfig else { return }
        guard let keyMaps = config.leftStick?.keyMaps else { return }

        let directionName = sender.identifier?.rawValue ?? sender.title
        let result = keyMaps.first(where: { map in
            guard let keyMap = map as? KeyMap else { return false }
            return keyMap.button == directionName
        })
        guard let keyMapData = result as? KeyMap else { return }
        keyMapData.isEnabled = sender.state == .on
        
        controller.updateKeyMap()
    }
    
    @objc func rightStickDirectionCheckDidChange(_ sender: NSButton) {
        guard let controller = self.selectedController else { return }
        guard let config = self.selectedKeyConfig else { return }
        guard let keyMaps = config.rightStick?.keyMaps else { return }

        let directionName = sender.identifier?.rawValue ?? sender.title
        let result = keyMaps.first(where: { map in
            guard let keyMap = map as? KeyMap else { return false }
            return keyMap.button == directionName
        })
        guard let keyMapData = result as? KeyMap else { return }
        keyMapData.isEnabled = sender.state == .on
        
        controller.updateKeyMap()
    }
    
    @objc func leftStickSpeedDidChange(_ sender: NSTextField) {
        guard let config = self.selectedKeyConfig else { return }
        config.leftStick?.speed = sender.floatValue
    }
    
    @objc func rightStickSpeedDidChange(_ sender: NSTextField) {
        guard let config = self.selectedKeyConfig else { return }
        config.rightStick?.speed = sender.floatValue
    }
}
