//
//  ProgressViewController.swift
//  Sequel Ace
//
//  Created by James on 16/2/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Cocoa
import OSLog

final class ProgressViewController: NSViewController {

    @IBOutlet var bytes: NSTextField!
    @IBOutlet var progressIndicator: NSProgressIndicator!
    @IBOutlet var subtitle: NSTextField!
    @IBOutlet var theTitle: NSTextField!
    private let Log = OSLog(subsystem : "com.sequel-ace.sequel-ace", category : "github")

    @IBAction func cancelAction(_ sender: NSButton) {
        Log.debug("cancelPressed, calling delegate cancel")
        GitHubReleaseManager.sharedInstance.cancelPressed()
    }

}
