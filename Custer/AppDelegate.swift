//
//  AppDelegate.swift
//  custer
//
//  Created by Serhiy Mytrovtsiy on 07/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import os.log
import Updater

let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "custer")
var store: Store = Store()
let updater = Updater(user: "exelban", repo: "custer")
var uri: String {
    get {
        return store.string(key: "url", defaultValue: "")
    }
    set {
        store.set(key: "url", value: newValue)
        Player.shared.setURL(newValue)
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, playerDelegate {
    private let menuBarItem = NSStatusBar.system.statusItem(withLength: 28)
    private let autostart: Bool = store.bool(key: "autoplay", defaultValue: false)
    private let menu: Menu = Menu()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        #if !ADHOC
        self.parseArguments()
        #endif
        
        if uri == "" {
            os_log(.debug, log: log, "Stream url is not defined")
            self.menu.showAddressView()
        }
        
        self.menuBarItem.autosaveName = "custer"
        
        self.menuBarItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        self.menuBarItem.button?.action = #selector(click(_:))
        self.menuBarItem.button?.image = NSImage(named: NSImage.Name("error"))
        
        Player.shared.delegate = self
        Player.shared.setURL(uri)
        
        if !store.exist(key: "runAtLoginInitialized") {
            var defaultValue = false
            #if !ADHOC
            defaultValue = true
            #endif
            store.set(key: "runAtLoginInitialized", value: defaultValue)
            LaunchAtLogin.isEnabled = defaultValue
        }
        
        if store.exist(key: "icon") {
            let dockIconStatus = store.bool(key: "icon", defaultValue: false) ? NSApplication.ActivationPolicy.regular : NSApplication.ActivationPolicy.accessory
            NSApp.setActivationPolicy(dockIconStatus)
        }
        
        #if !ADHOC
        self.checkForNewVersion()
        #endif
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {}
    
    @objc func click(_ sender: NSStatusBarButton) {
        guard let event: NSEvent = NSApp.currentEvent else {
            return
        }
        
        if (event.type == NSEvent.EventType.rightMouseDown) {
            self.menuBarItem.menu = self.menu
            self.menuBarItem.button?.performClick(nil)
            self.menuBarItem.menu = nil
            return
        }
        
        if uri == "" {
            self.menu.showAddressView()
        }
        
        if Player.shared.isError() {
            return
        }
        
        if Player.shared.isPlaying() {
            Player.shared.pause()
            return
        }
        
        Player.shared.play()
    }
    
    internal func onError(error: String) {
        let alert = NSAlert()
        alert.messageText = "Error to start player"
        alert.informativeText = error
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        if let window = NSApplication.shared.windows.first{
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
        
        os_log(.error, log: log, "error: %s", error)
    }
    
    internal func stateChange(state: player_state) {
        os_log(.debug, log: log, "new state: %s", state.description)
        
        switch state {
        case .playing:
            self.menuBarItem.button?.image = NSImage(named: NSImage.Name("pause"))
        case .ready:
        self.menuBarItem.button?.image = NSImage(named: NSImage.Name("play"))
            if self.autostart {
                Player.shared.play()
            }
        case .paused:
            self.menuBarItem.button?.image = NSImage(named: NSImage.Name("play"))
        case .error, .undefined:
            self.menuBarItem.button?.image = NSImage(named: NSImage.Name("error"))
        default:
            break
        }
    }
    
    internal func checkForNewVersion() {
        updater.check() { result, error in
            if error != nil {
                os_log(.error, log: log, "error updater.check(): %s", "\(error!.localizedDescription)")
                return
            }
            
            guard error == nil, let version: version_s = result else {
                os_log(.error, log: log, "download error(): %s", "\(error!.localizedDescription)")
                return
            }
            
            DispatchQueue.main.async(execute: {
                if version.newest {
                    os_log(.debug, log: log, "show update window because new version of app found: %s", "\(version.latest)")
                    
                    let alert = NSAlert()
                    alert.messageText = "New version available"
                    alert.informativeText = "Current version:   \(version.current)\nLatest version:     \(version.latest)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Install")
                    alert.addButton(withTitle: "Cancel")
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let url = URL(string: version.url) {
                            updater.download(url, doneHandler: { path in
                                updater.install(path: path)
                            })
                        }
                    }
                }
            })
        }
    }
    
    internal func parseArguments() {
        let args = CommandLine.arguments
        
        if let mountIndex = args.firstIndex(of: "--mount-path") {
            if args.indices.contains(mountIndex+1) {
                let mountPath = args[mountIndex+1]
                asyncShell("/usr/bin/hdiutil detach \(mountPath)")
                asyncShell("/bin/rm -rf \(mountPath)")
                
                os_log(.debug, log: log, "DMG was unmounted and mountPath deleted")
            }
        }
        
        if let dmgIndex = args.firstIndex(of: "--dmg-path") {
            if args.indices.contains(dmgIndex+1) {
                asyncShell("/bin/rm -rf \(args[dmgIndex+1])")
                
                os_log(.debug, log: log, "DMG was deleted")
            }
        }
    }
}

