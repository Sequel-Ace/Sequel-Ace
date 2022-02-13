//
//  ProgressWindowController.swift
//  Sequel Ace
//
//  Created by James on 19/2/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Cocoa
import OSLog

class ProgressWindowController: NSWindowController, NSWindowDelegate{

    private let Log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "github")

    override var contentViewController: NSViewController?{
        didSet {
            //Any consequences of setting here
            Log.debug("didSet")
        }
    }

    override func awakeFromNib() {
        Log.debug("awakeFromNib")

        guard let tmpPVC = contentViewController as? ProgressViewController else {
            return
        }

        contentViewController = tmpPVC

        super.awakeFromNib()
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
