//
//  JoyConDiscovery.swift
//  AgentPad
//
//  Wraps JoyConSwift.JoyConManager so the rest of the app can talk through
//  ControllerBackendDiscovery without importing JoyConSwift directly.
//
//  Owns a Controller -> JoyConBackend map so connect / disconnect emit the
//  same backend instance (matters for the GameController bookkeeping path,
//  which reuses backend references across reconnects of the same physical
//  device).
//

import Foundation
import JoyConSwift

final class JoyConDiscovery: ControllerBackendDiscovery {
    /// Exposed so existing code (PassthroughCoordinator, AppDelegate's
    /// global seize calls) can keep talking to the underlying manager
    /// while the abstraction migration is in progress. New code should
    /// prefer the ControllerBackendDiscovery surface.
    let manager: JoyConManager

    private var backends: [ObjectIdentifier: JoyConBackend] = [:]

    var connectHandler: ((ControllerBackend) -> Void)?
    var disconnectHandler: ((ControllerBackend) -> Void)?

    init(manager: JoyConManager = JoyConManager()) {
        self.manager = manager
        self.installForwarders()
    }

    private func installForwarders() {
        manager.connectHandler = { [weak self] controller in
            guard let self = self else { return }
            let key = ObjectIdentifier(controller)
            let backend: JoyConBackend
            if let existing = self.backends[key] {
                backend = existing
            } else {
                backend = JoyConBackend(controller: controller)
                self.backends[key] = backend
            }
            self.connectHandler?(backend)
        }
        manager.disconnectHandler = { [weak self] controller in
            guard let self = self else { return }
            let key = ObjectIdentifier(controller)
            guard let backend = self.backends[key] else { return }
            self.disconnectHandler?(backend)
            // Keep the entry: JoyConSwift reuses the same Controller instance
            // when the same device reconnects, so we want a stable backend
            // identity across the connect/disconnect cycle.
        }
    }

    func start() {
        _ = manager.runAsync()
    }

    func stop() {
        manager.stop()
    }

    /// Returns the JoyConBackend currently wrapping the given native
    /// controller, if one was emitted. Useful while AppDelegate / GameController
    /// still hold raw JoyConSwift.Controller references during the migration.
    func backend(for controller: JoyConSwift.Controller) -> JoyConBackend? {
        return backends[ObjectIdentifier(controller)]
    }
}
