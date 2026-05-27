//
//  AppDelegate.swift
//  AgentPadLauncher
//
//  Created by magicien on 2020/03/08.
//  Copyright © 2020 DarkHorse. All rights reserved.
//

import Cocoa

let mainAppID = "com.rtx3.agentpad"

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Ensure the app is not already running
        guard NSRunningApplication.runningApplications(withBundleIdentifier: mainAppID).isEmpty else {
            NSApp.terminate(nil)
            return
        }

        let pathComponents = (Bundle.main.bundlePath as NSString).pathComponents
        let mainPath = NSString.path(withComponents: Array(pathComponents[0...(pathComponents.count - 5)]))
        NSWorkspace.shared.launchApplication(mainPath)
        NSApp.terminate(nil)
    }
}
