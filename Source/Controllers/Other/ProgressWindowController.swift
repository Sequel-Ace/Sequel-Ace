//
//  ProgressWindowController.swift
//  Sequel Ace
//
//  Created by James on 19/2/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import Cocoa
import OSLog

class ProgressWindowController: NSWindowController, NSWindowDelegate{

    @IBOutlet weak var theWindow: NSWindow!
    
    private let Log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "github")

    override func loadWindow(){
        Log.debug("loadWindow")
        super.loadWindow()
    }

    override func windowDidLoad() {
        Log.debug("windowDidLoad")
        super.windowDidLoad()

    }

    // MARK: NSWindowDelegate

    internal func windowWillClose(_ notification: Notification) {
        Log.debug("windowWillClose")

        guard let win = notification.object as? NSWindow else {
            return
        }

        if win == self.window {
            Log.debug("stopping download and animation")
            GitHubReleaseManager.sharedInstance.closePressed()
        }
    }

}
