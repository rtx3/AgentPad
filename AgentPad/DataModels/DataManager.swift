//
//  DataManager.swift
//  AgentPad
//
//  Created by magicien on 2019/07/14.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import CoreData
import JoyConSwift

enum StickType: String {
    case Mouse = "Mouse"
    case MouseWheel = "Mouse Wheel"
    case Key = "Key"
    case None = "None"
}

enum StickDirection: String {
    case Left = "Left"
    case Right = "Right"
    case Up = "Up"
    case Down = "Down"
}

class DataManager: NSObject {
    let container: NSPersistentContainer

    var undoManager: UndoManager? {
        return self.container.viewContext.undoManager
    }
    
    var controllers: [ControllerData] {
        let context = self.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ControllerData")
        
        do {
            let result = try context.fetch(request) as! [ControllerData]
            return result
        } catch {
            fatalError("Failed to fetch ControllerData: \(error)")
        }
    }
    
    init(completion: @escaping (DataManager?) -> Void) {
        self.container = NSPersistentContainer(name: "AgentPad")
        super.init()

        self.container.persistentStoreDescriptions.forEach { desc in
            desc.shouldMigrateStoreAutomatically = true
            desc.shouldInferMappingModelAutomatically = true
        }

        self.container.loadPersistentStores { [weak self] (storeDescription, error) in
            if let error = error {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error)")
            }
            self?.container.viewContext.automaticallyMergesChangesFromParent = true
            self?.container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            
            completion(self)
        }
    }
    
    func save() -> Bool {
        let context = self.container.viewContext
         
        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
            return false
        }
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Customize this code block to include application-specific recovery steps.
                let nserror = error as NSError
                NSApplication.shared.presentError(nserror)

                return false
            }
        }
        
        return true
    }
    
    // MARK: - Import/Export data
    
    func createContext(for url: URL) -> NSManagedObjectContext? {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.container.managedObjectModel)
        do {
            // TODO: Set options
            try coordinator.addPersistentStore(ofType: NSBinaryStoreType, configurationName: nil, at: url, options: nil)
        } catch {
            let nserror = error as NSError
            NSApplication.shared.presentError(nserror)

            return nil
        }

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        
        return context
    }
    
    func saveData(object: NSManagedObject, to url: URL) -> Bool {
        guard let context = self.createContext(for: url) else { return false }
        
        context.insert(object)
        if !context.commitEditing() {
            return false
        }
        
        do {
            try context.save()
        } catch {
            // Customize this code block to include application-specific recovery steps.
            let nserror = error as NSError
            NSApplication.shared.presentError(nserror)

            return false
        }
        
        return true
    }
    
    func loadData<T: NSManagedObject>(from url: URL) -> [T]? {
        guard let context = self.createContext(for: url) else { return nil }
        guard let entityName = T.entity().name else { return nil }
        
        let request = NSFetchRequest<T>(entityName: entityName)
        do {
            return try context.fetch(request)
        } catch {
            let nserror = error as NSError
            NSApplication.shared.presentError(nserror)
        }

        return nil
    }

    // MARK: - ControllerData
    
    func createControllerData(type: JoyCon.ControllerType) -> ControllerData {
        let controller = ControllerData(context: self.container.viewContext)
        controller.appConfigs = []
        controller.defaultConfig = self.createKeyConfig(type: type)

        return controller
    }

    /// Backend-agnostic factory used for non-JoyCon controllers (GameController.framework).
    /// Persists `kind.rawValue` directly into `ControllerData.type` — this is the new
    /// namespace that won't collide with JoyCon's legacy ControllerType.rawValue strings
    /// because none of those are equal to a ControllerKind raw value.
    func createControllerData(kind: ControllerKind) -> ControllerData {
        let controller = ControllerData(context: self.container.viewContext)
        controller.appConfigs = []
        controller.type = kind.rawValue
        controller.defaultConfig = self.createKeyConfig(kind: kind)

        return controller
    }
    
    func getControllerData(controller: JoyConSwift.Controller) -> ControllerData {
        let serialID = controller.serialID
        let context = self.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ControllerData")
        request.predicate = NSPredicate(format: "serialID == %@", serialID)

        do {
            let result = try context.fetch(request) as! [ControllerData]
            if result.count > 0 {
                return result[0]
            }
        } catch {
            fatalError("Failed to fetch ControllerData: \(error)")
        }

        let controller = self.createControllerData(type: controller.type)
        controller.serialID = serialID

        return controller
    }

    /// ControllerData lookup keyed by a ControllerBackend's identifier.
    /// JoyConBackend keeps using the bare JoyCon serialID for backwards
    /// compatibility with previously stored rows; non-JoyCon backends use
    /// their namespaced identifier (e.g. "gc::DualSense::Sony_Interactive::1").
    func getControllerData(forBackend backend: ControllerBackend) -> ControllerData {
        if let joyCon = (backend as? JoyConBackend)?.controller {
            return self.getControllerData(controller: joyCon)
        }

        let serialID = backend.identifier
        let context = self.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ControllerData")
        request.predicate = NSPredicate(format: "serialID == %@", serialID)

        do {
            let result = try context.fetch(request) as! [ControllerData]
            if result.count > 0 {
                return result[0]
            }
        } catch {
            fatalError("Failed to fetch ControllerData: \(error)")
        }

        let row = self.createControllerData(kind: backend.kind)
        row.serialID = serialID

        return row
    }
    
    // MARK: - AppConfig
    
    /// 新建 AppConfig。
    /// - Parameter from: 若传入，则把它深拷贝作为本 AppConfig 的初始 config（"inhibit"语义：默认继承 default 的值）。
    ///   不传则创建空白 KeyConfig。
    func createAppConfig(type: JoyCon.ControllerType, from defaultConfig: KeyConfig? = nil) -> AppConfig {
        let appConfig = AppConfig(context: self.container.viewContext)
        appConfig.app = self.createAppData()
        if let defaultConfig = defaultConfig {
            appConfig.config = self.cloneKeyConfig(from: defaultConfig)
        } else {
            appConfig.config = self.createKeyConfig(type: type)
        }

        return appConfig
    }

    // MARK: - AppData

    func createAppData() -> AppData {
        let appData = AppData(context: self.container.viewContext)

        return appData
    }

    // MARK: - KeyConfig

    func createKeyConfig(type: JoyCon.ControllerType) -> KeyConfig {
        let keyConfig = KeyConfig(context: self.container.viewContext)

        if type == .JoyConL || type == .ProController {
            keyConfig.leftStick = self.createStickConfig()
        }
        if type == .JoyConR || type == .ProController {
            keyConfig.rightStick = self.createStickConfig()
        }

        keyConfig.keyMaps = []

        return keyConfig
    }

    /// Creates an empty KeyConfig sized for a given backend-agnostic kind.
    /// PS / Xbox / MFi / generic extended gamepads always have both sticks;
    /// SNES / Famicom variants have neither. Joy-Con singletons keep the
    /// existing single-stick semantics; that path still goes through the
    /// JoyCon.ControllerType overload.
    func createKeyConfig(kind: ControllerKind) -> KeyConfig {
        let keyConfig = KeyConfig(context: self.container.viewContext)

        switch kind {
        case .joyConL:
            keyConfig.leftStick = self.createStickConfig()
        case .joyConR:
            keyConfig.rightStick = self.createStickConfig()
        case .proController, .dualShock4, .dualSense, .xbox, .mfi, .generic:
            keyConfig.leftStick = self.createStickConfig()
            keyConfig.rightStick = self.createStickConfig()
        case .snesController, .famicomController1, .famicomController2, .unknown:
            break
        }

        keyConfig.keyMaps = []
        return keyConfig
    }

    // MARK: - KeyMap

    func createKeyMap() -> KeyMap {
        let keyMap = KeyMap(context: self.container.viewContext)
        
        return keyMap
    }
    
    // MARK: - StickConfig
    
    func createStickConfig() -> StickConfig {
        let stickConfig = StickConfig(context: self.container.viewContext)

        stickConfig.speed = 10.0
        stickConfig.type = StickType.None.rawValue

        let left = self.createKeyMap()
        left.button = StickDirection.Left.rawValue
        stickConfig.addToKeyMaps(left)

        let right = self.createKeyMap()
        right.button = StickDirection.Right.rawValue
        stickConfig.addToKeyMaps(right)

        let up = self.createKeyMap()
        up.button = StickDirection.Up.rawValue
        stickConfig.addToKeyMaps(up)

        let down = self.createKeyMap()
        down.button = StickDirection.Down.rawValue
        stickConfig.addToKeyMaps(down)
        
        return stickConfig
    }
    
    // MARK: - Common

    func delete(_ object: NSManagedObject) {
        self.container.viewContext.delete(object)
    }

    // MARK: - KeyConfig deep copy

    /// 深拷贝一个 KeyConfig（含 keyMaps 与 left/right StickConfig）。
    /// 用于新建 AppConfig 时把 defaultConfig 作为初始值（"inhibit"语义：默认继承 default）。
    /// 不能直接 `appConfig.config = defaultConfig` ——那是关系赋值，会让两条路共享同一个 KeyConfig，
    /// 之后任一处修改都污染对方。
    func cloneKeyConfig(from source: KeyConfig) -> KeyConfig {
        let copy = KeyConfig(context: self.container.viewContext)
        copy.keyMaps = []

        source.keyMaps?.enumerateObjects { (obj, _) in
            guard let src = obj as? KeyMap else { return }
            copy.addToKeyMaps(self.cloneKeyMap(from: src))
        }

        if let srcLeft = source.leftStick {
            copy.leftStick = self.cloneStickConfig(from: srcLeft)
        }
        if let srcRight = source.rightStick {
            copy.rightStick = self.cloneStickConfig(from: srcRight)
        }

        return copy
    }

    private func cloneKeyMap(from source: KeyMap) -> KeyMap {
        let copy = KeyMap(context: self.container.viewContext)
        copy.button = source.button
        copy.isEnabled = source.isEnabled
        copy.keyCode = source.keyCode
        copy.modifiers = source.modifiers
        copy.mouseButton = source.mouseButton
        return copy
    }

    private func cloneStickConfig(from source: StickConfig) -> StickConfig {
        let copy = StickConfig(context: self.container.viewContext)
        copy.speed = source.speed
        copy.type = source.type

        source.keyMaps?.enumerateObjects { (obj, _) in
            guard let src = obj as? KeyMap else { return }
            copy.addToKeyMaps(self.cloneKeyMap(from: src))
        }

        return copy
    }

    /// 删除一条 KeyConfig 时，手动清理它挂着的 keyMaps 与 stickConfigs。
    /// 模型里 KeyConfig→KeyMap、KeyConfig→StickConfig 的 deletionRule 都是 Nullify，
    /// 直接 delete(keyConfig) 会留下孤儿 KeyMap / StickConfig 行。
    func deleteKeyConfigDeeply(_ config: KeyConfig) {
        config.keyMaps?.enumerateObjects { (obj, _) in
            if let m = obj as? KeyMap {
                self.container.viewContext.delete(m)
            }
        }
        if let left = config.leftStick {
            self.deleteStickConfigDeeply(left)
        }
        if let right = config.rightStick {
            self.deleteStickConfigDeeply(right)
        }
        self.container.viewContext.delete(config)
    }

    private func deleteStickConfigDeeply(_ stick: StickConfig) {
        stick.keyMaps?.enumerateObjects { (obj, _) in
            if let m = obj as? KeyMap {
                self.container.viewContext.delete(m)
            }
        }
        self.container.viewContext.delete(stick)
    }
}
