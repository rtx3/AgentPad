//
//  GCControllerDiscovery.swift
//  AgentPad
//
//  Listens to GCController.didConnect / didDisconnect notifications and
//  hands out GCControllerBackend instances. Nintendo controllers exposed
//  through GameController.framework on newer macOS are filtered out so that
//  JoyConBackend remains the single source of truth for those devices
//  (matches the conflict-resolution decision in plan 2 §2.4.3).
//
//  GameController.framework does not expose a stable hardware serial, so the
//  backend identifier is derived from `productCategory` + `vendorName` only.
//  This is intentionally coarse-grained: two physical controllers of the same
//  model will share the same identifier (and therefore the same persisted
//  KeyConfig). The previous "per-(category, vendor) sequence number" scheme
//  was reset every process launch and produced a fresh row in Core Data each
//  time the same controller reconnected, leaving ghost entries in the
//  Controllers list. DataManager.migrateGCSerialIDsV1() collapses those
//  legacy rows on first launch after the upgrade.
//

import Foundation
import GameController

@available(macOS 10.15, *)
final class GCControllerDiscovery: ControllerBackendDiscovery {

    private var backends: [ObjectIdentifier: GCControllerBackend] = [:]
    private var observers: [NSObjectProtocol] = []
    private var started: Bool = false

    var connectHandler: ((ControllerBackend) -> Void)?
    var disconnectHandler: ((ControllerBackend) -> Void)?

    init() {}

    deinit {
        stop()
    }

    func start() {
        guard !started else { return }
        started = true

        let center = NotificationCenter.default
        let connect = center.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            self?.handleConnect(controller)
        }
        observers.append(connect)

        let disconnect = center.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            self?.handleDisconnect(controller)
        }
        observers.append(disconnect)

        // Anything already paired before we registered.
        for controller in GCController.controllers() {
            handleConnect(controller)
        }
    }

    func stop() {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        observers.removeAll()
        started = false
    }

    private func handleConnect(_ controller: GCController) {
        if GCControllerBackend.looksLikeNintendo(controller) {
            return
        }
        // Skip controllers that don't expose the extendedGamepad profile —
        // we have nothing useful to map otherwise.
        guard controller.extendedGamepad != nil else { return }

        let key = ObjectIdentifier(controller)
        if backends[key] != nil { return }

        let stableID = Self.stableID(for: controller)
        let backend = GCControllerBackend(gcController: controller, stableID: stableID)
        backends[key] = backend
        connectHandler?(backend)
    }

    private func handleDisconnect(_ controller: GCController) {
        let key = ObjectIdentifier(controller)
        guard let backend = backends[key] else { return }
        disconnectHandler?(backend)
        backends.removeValue(forKey: key)
    }

    /// Derive a cross-process-stable identifier from the controller's
    /// productCategory and vendorName. Used as the trailing portion of
    /// `GCControllerBackend.identifier` (which prefixes "gc::"). Two physical
    /// controllers of the same model/vendor will collide; this is the best
    /// fingerprint GameController.framework offers.
    static func stableID(for controller: GCController) -> String {
        let category = controller.productCategory.replacingOccurrences(of: " ", with: "_")
        let vendor = controller.vendorName?.replacingOccurrences(of: " ", with: "_") ?? "unknown"
        return "\(category)::\(vendor)"
    }
}
