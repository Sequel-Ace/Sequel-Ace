//
//  ProgressWindowController.swift
//  Sequel Ace
//
//  Created by James on 16/2/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import Cocoa
import OSLog

protocol ProgressWindowControllerDelegate{
    func cancelPressed()
}

final class ProgressWindowController: NSWindowController {

    @IBOutlet weak var bytes: NSTextField!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var subtitle: NSTextField!
    @IBOutlet weak var title: NSTextField!
    private let Log = OSLog(subsystem : "com.sequel-ace.sequel-ace", category : "github")
    var delegate: ProgressWindowControllerDelegate?

    @IBAction func cancelAction(_ sender: NSButton) {
        Log.debug("cancelPressed, calling delegate cancel")
        delegate?.cancelPressed()
    }

    override var windowNibName: String! {
        return "ProgressWindowController"
    }

    override func windowDidLoad() {
        super.windowDidLoad()
    }
    
}
