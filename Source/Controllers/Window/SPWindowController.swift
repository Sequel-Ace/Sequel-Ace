//
//  SPWindowController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 24.01.2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>

import Cocoa
import SnapKit

@objc protocol SPWindowControllerDelegate: AnyObject {
    func windowControllerDidClose(_ windowController: SPWindowController)
}

@objc final class SPWindowController: NSWindowController {

    @objc weak var delegate: SPWindowControllerDelegate?

    @objc lazy var databaseDocument: SPDatabaseDocument = SPDatabaseDocument(windowController: self)

    override func awakeFromNib() {
        super.awakeFromNib()

        if let window = window  {
            window.collectionBehavior = [window.collectionBehavior, .fullScreenPrimary]
        }

        setupAppearance()
    }

    private func setupAppearance() {
        databaseDocument.updateWindowTitle(self)

        window?.contentView?.addSubview(databaseDocument.databaseView())
        databaseDocument.databaseView()?.frame = window?.contentView?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 400)
    }
}

extension SPWindowController: NSWindowDelegate {
    /// Determine whether the window is permitted to close.
    /// Go through the tabs in this window, and ask the database connection view in each one if it can be closed, returning YES only if all can be closed.
    /// - Parameter sender: NSWindow instance
    /// - Returns: true or false
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !databaseDocument.parentTabShouldClose() {
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
