//
//  DataManager.swift
//  AgentPad
//
//  Created by magicien on 2019/07/14.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import CoreData
import AppKit
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

            self?.migrateGCSerialIDsV1()

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

    // MARK: - Migrations

    /// One-shot migration that collapses legacy GC controller rows whose
    /// serialID carried a per-process sequence number suffix (e.g.
    /// `gc::Xbox_One::Xbox_Wireless_Controller::2`). Those sequence numbers
    /// were reset every process launch, so the same physical controller
    /// produced a fresh ControllerData row each time it reconnected, leaving
    /// ghost entries in the Controllers list. Newer builds drop the suffix
    /// entirely; this migration rewrites historical rows to the new format,
    /// keeping the most-configured row per (category, vendor) group as
    /// canonical and merging the rest into it.
    ///
    /// Idempotent via `UserDefaults` flag `agentpad.gc.serialID.migrated.v1`.
    /// Any error short-circuits without setting the flag so the next launch
    /// retries — better to keep ghosts than to silently corrupt the store.
    private func migrateGCSerialIDsV1() {
        let flagKey = "agentpad.gc.serialID.migrated.v1"
        if UserDefaults.standard.bool(forKey: flagKey) { return }

        let context = self.container.viewContext
        let request = NSFetchRequest<ControllerData>(entityName: "ControllerData")
        request.predicate = NSPredicate(format: "serialID BEGINSWITH %@", "gc::")

        let rows: [ControllerData]
        do {
            rows = try context.fetch(request)
        } catch {
            NSLog("[Migration] gc-serialID-v1 fetch failed: \(error)")
            return
        }

        // Group legacy "gc::cat::vendor::N" rows by their new identifier
        // "gc::cat::vendor". Rows already in the new shape are recorded so
        // they participate as canonical candidates when their group exists.
        let legacyPattern = try? NSRegularExpression(pattern: "^(gc::[^:]+::[^:]+)::\\d+$")
        var groups: [String: [ControllerData]] = [:]
        for row in rows {
            guard let sid = row.serialID else { continue }
            if let regex = legacyPattern,
               let m = regex.firstMatch(in: sid, range: NSRange(sid.startIndex..., in: sid)),
               let range = Range(m.range(at: 1), in: sid) {
                let newID = String(sid[range])
                groups[newID, default: []].append(row)
            } else if sid.components(separatedBy: "::").count == 3 {
                // Already in the new "gc::cat::vendor" form. Recorded so a
                // freshly-written row participates as a canonical candidate
                // alongside any legacy duplicates of the same model.
                groups[sid, default: []].append(row)
            }
        }

        if groups.isEmpty {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }

        for (newID, members) in groups {
            self.collapseLegacyGCGroup(members: members, newSerialID: newID)
        }

        do {
            try context.save()
        } catch {
            NSLog("[Migration] gc-serialID-v1 save failed: \(error)")
            return
        }

        UserDefaults.standard.set(true, forKey: flagKey)
        NSLog("[Migration] gc-serialID-v1 completed: \(groups.count) group(s)")
    }

    /// Merge `members` into a single canonical row carrying `newSerialID`.
    /// Canonical is picked by `migrationScore(_:)`; ties broken by Z_PK
    /// ascending. Dup rows have their appConfigs reparented (deduped by
    /// `app.bundleID`; conflicts keep the canonical-side appConfig and delete
    /// the dup-side one with its KeyConfig), their defaultConfig deeply
    /// removed, and themselves deleted.
    private func collapseLegacyGCGroup(members: [ControllerData], newSerialID: String) {
        guard !members.isEmpty else { return }
        let context = self.container.viewContext

        let sorted = members.sorted { (a, b) in
            let sa = self.migrationScore(a)
            let sb = self.migrationScore(b)
            if sa != sb { return sa > sb }
            return a.objectID.uriRepresentation().absoluteString
                < b.objectID.uriRepresentation().absoluteString
        }
        let canonical = sorted[0]
        let dups = sorted.dropFirst()

        // Bundle IDs already configured on canonical — used to dedupe.
        var canonicalBundleIDs: Set<String> = []
        canonical.appConfigs?.enumerateObjects { (obj, _, _) in
            if let cfg = obj as? AppConfig, let bid = cfg.app?.bundleID {
                canonicalBundleIDs.insert(bid)
            }
        }

        for dup in dups {
            let dupAppConfigs: [AppConfig] = {
                guard let set = dup.appConfigs else { return [] }
                var out: [AppConfig] = []
                set.enumerateObjects { (obj, _, _) in
                    if let cfg = obj as? AppConfig { out.append(cfg) }
                }
                return out
            }()
            for appCfg in dupAppConfigs {
                let bid = appCfg.app?.bundleID
                if let bid = bid, canonicalBundleIDs.contains(bid) {
                    // Conflict: canonical already has a per-app config for
                    // this bundle. Drop the dup's appConfig (and its
                    // KeyConfig) to avoid duplicate entries in the App list.
                    dup.removeFromAppConfigs(appCfg)
                    if let cfg = appCfg.config {
                        self.deleteKeyConfigDeeply(cfg)
                    }
                    if let appData = appCfg.app {
                        context.delete(appData)
                    }
                    context.delete(appCfg)
                } else {
                    dup.removeFromAppConfigs(appCfg)
                    canonical.addToAppConfigs(appCfg)
                    if let bid = bid {
                        canonicalBundleIDs.insert(bid)
                    }
                }
            }

            if let dupDefault = dup.defaultConfig {
                self.deleteKeyConfigDeeply(dupDefault)
            }
            context.delete(dup)
        }

        canonical.serialID = newSerialID
    }

    /// Heuristic for picking which ControllerData row carries the user's
    /// actual configuration: count of mapped buttons in the default config
    /// plus a small bonus per stick that the user changed off the default
    /// `"None"` type. Higher score wins.
    private func migrationScore(_ data: ControllerData) -> Int {
        guard let cfg = data.defaultConfig else { return 0 }
        var score = 0
        if let kms = cfg.keyMaps {
            score += kms.count
        }
        if let left = cfg.leftStick, let type = left.type, type != StickType.None.rawValue {
            score += 1
        }
        if let right = cfg.rightStick, let type = right.type, type != StickType.None.rawValue {
            score += 1
        }
        return score
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
        // bodyColor / buttonColor 是 Core Data 模型里的 required 字段。
        // JoyCon 路径在 setBackendHandlers 里从硬件读色并写回，所以从来不报错；
        // GC 后端（Xbox / DualSense）没有色彩 API，若不在这里填默认值，
        // 首次保存就会触发 "Multiple validation errors occurred."。
        let defaultColor = NSColor(red: 55.0 / 255, green: 55.0 / 255, blue: 55.0 / 255, alpha: 1.0)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: defaultColor, requiringSecureCoding: false) {
            controller.bodyColor = colorData
            controller.buttonColor = colorData
        }

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

    // MARK: - Import / Export defaultConfig

    /// 导出指定手柄的 defaultConfig 为 JSON Data。
    /// 仅含 defaultConfig；AppConfig 覆盖配置当前 UI 已隐藏，不导出。
    func exportDefaultConfig(of controllerData: ControllerData) throws -> Data {
        guard let config = controllerData.defaultConfig else {
            throw NSError(
                domain: "AgentPad.DataManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Selected controller has no default config"]
            )
        }
        let kind = controllerData.type ?? "unknown"
        return try KeyConfigCodec.encode(defaultConfig: config, kind: kind)
    }

    /// 导入结果摘要，供 UI 弹 alert 提示。
    struct ImportSummary {
        /// 成功写入的 KeyMap 条数（含 face / d-pad / shoulders / triggers / sticks 全部）。
        let applied: Int
        /// 因目标手柄不支持而丢弃的 button 名（如 SNES 导入 ProController 摇杆按键）。
        let skippedButtons: [String]
        /// 文件里的 kind 与目标手柄不一致时记录，供 UI 弹二次确认。
        let kindMismatch: (source: String, target: String)?
    }

    /// 导入：清空目标 defaultConfig 的 keyMaps + stick keyMaps，再按 JSON 内容填回。
    /// 宽松模式：
    /// - kind 不一致：写入 summary.kindMismatch，由调用方决定是否回滚（UI 弹二次确认）。
    /// - 文件含目标手柄不存在的 button：直接跳过、记入 skippedButtons。
    /// - 文件缺少目标手柄某个 button：保持空（与新建 defaultConfig 行为一致）。
    /// 调用方负责后续 save() 与 controller.updateKeyMap() 刷新 UI。
    func importDefaultConfig(_ data: Data, into controllerData: ControllerData) throws -> ImportSummary {
        let doc = try KeyConfigCodec.decode(data)
        guard let target = controllerData.defaultConfig else {
            throw NSError(
                domain: "AgentPad.DataManager",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Target controller has no default config"]
            )
        }

        let context = self.container.viewContext
        let targetKind = controllerData.type ?? "unknown"
        let kindMismatch: (String, String)? = (doc.kind == targetKind) ? nil : (doc.kind, targetKind)

        // 1. 清空旧的 root keyMaps（删除以避免孤儿行；模型 deletionRule = Nullify）。
        target.keyMaps?.enumerateObjects { (obj, _) in
            if let km = obj as? KeyMap { context.delete(km) }
        }
        target.keyMaps = []

        // 2. 清空 left / right stick 的 keyMaps，并按 payload 重建 stick 元数据。
        if let left = target.leftStick {
            self.clearStickKeyMaps(left)
            if let p = doc.defaultConfig.leftStick {
                left.type = p.type
                left.speed = p.speed
            }
        }
        if let right = target.rightStick {
            self.clearStickKeyMaps(right)
            if let p = doc.defaultConfig.rightStick {
                right.type = p.type
                right.speed = p.speed
            }
        }

        // 3. 写入 root keyMaps。target 不存在的 button 名会被 LegacyButtonNameMap 视为合法字符串，
        //    无需在这里逐个白名单——下游 updateKeyMap 在 enumerate 时不会命中即可。
        var applied = 0
        var skipped: [String] = []
        for p in doc.defaultConfig.keyMaps {
            let km = self.createKeyMap()
            self.applyPayload(p, to: km)
            target.addToKeyMaps(km)
            applied += 1
        }

        // 4. Stick keyMaps 必须落到目标手柄实际存在的 stick 上：
        //    源是 ProController（双摇杆）→ 目标 JoyConL（仅 left）：右摇杆条目全部 skipped。
        if let leftPayload = doc.defaultConfig.leftStick {
            if let leftStick = target.leftStick {
                for p in leftPayload.keyMaps {
                    let km = self.createKeyMap()
                    self.applyPayload(p, to: km)
                    leftStick.addToKeyMaps(km)
                    applied += 1
                }
            } else {
                skipped.append(contentsOf: leftPayload.keyMaps.map { "leftStick.\($0.button)" })
            }
        }
        if let rightPayload = doc.defaultConfig.rightStick {
            if let rightStick = target.rightStick {
                for p in rightPayload.keyMaps {
                    let km = self.createKeyMap()
                    self.applyPayload(p, to: km)
                    rightStick.addToKeyMaps(km)
                    applied += 1
                }
            } else {
                skipped.append(contentsOf: rightPayload.keyMaps.map { "rightStick.\($0.button)" })
            }
        }

        return ImportSummary(applied: applied, skippedButtons: skipped, kindMismatch: kindMismatch)
    }

    private func clearStickKeyMaps(_ stick: StickConfig) {
        let context = self.container.viewContext
        stick.keyMaps?.enumerateObjects { (obj, _) in
            if let km = obj as? KeyMap { context.delete(km) }
        }
        stick.keyMaps = []
    }

    private func applyPayload(_ p: KeyMapPayload, to km: KeyMap) {
        km.button = p.button
        km.action = p.action
        km.keyCode = p.keyCode
        km.modifiers = p.modifiers
        km.mouseButton = p.mouseButton
        km.isEnabled = p.isEnabled
        km.agentMacro = p.agentMacro
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
