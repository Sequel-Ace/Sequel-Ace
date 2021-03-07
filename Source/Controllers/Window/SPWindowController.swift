//
//  SPWindowController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 24.01.2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import Cocoa
import SnapKit

@objc protocol SPWindowControllerDelegate: AnyObject {
    func windowControllerDidClose(_ windowController: SPWindowController)
}

@objc final class SPWindowController: NSWindowController {

    @objc weak var delegate: SPWindowControllerDelegate?

    @objc lazy var selectedTableDocument: SPDatabaseDocument = SPDatabaseDocument(windowController: self)

    override func awakeFromNib() {
        super.awakeFromNib()

        if let window = window  {
            window.collectionBehavior = [window.collectionBehavior, .fullScreenPrimary]
        }

        selectedTableDocument.didBecomeActiveTabInWindow()
        selectedTableDocument.updateWindowTitle(self)

        setupAppearance()
    }

    func setupAppearance() {
        // Here should happen all UI / layout setups in the future once we remove .xib
        window?.contentView?.addSubview(selectedTableDocument.databaseView())
        selectedTableDocument.databaseView()?.frame = window?.contentView?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 400)
    }
}

extension SPWindowController: NSWindowDelegate {
    /// Determine whether the window is permitted to close.
    /// Go through the tabs in this window, and ask the database connection view in each one if it can be closed, returning YES only if all can be closed.
    /// - Parameter sender: NSWindow instance
    /// - Returns: true or false
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !selectedTableDocument.parentTabShouldClose() {
            return false
        }

        if let appDelegate = NSApp.delegate as? SPAppController, appDelegate.sessionURL() != nil, appDelegate.windowControllers.count == 1 {
            appDelegate.setSessionURL(nil)
            appDelegate.setSpfSessionDocData(nil)
        }
        delegate?.windowControllerDidClose(self)
        return true
    }
}
