//
//  SPWindowController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 24.01.2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
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

@objc final class SPWindowController: NSWindowController {

    @objc lazy var databaseDocument: SPDatabaseDocument = SPDatabaseDocument(windowController: self)

    @objc let uniqueID: UUID = UUID()

    /// Autosave name shared by all main windows: the frame the user saw last wins.
    private static let frameAutosaveName = "MainWindow"

    override func awakeFromNib() {
        super.awakeFromNib()

        if let window = window  {
            window.collectionBehavior = [window.collectionBehavior, .fullScreenPrimary]
        }

        setupFramePersistence()
        setupAppearance()
    }

    // MARK: - Accessory
    private lazy var tabAccessoryView: SPWindowTabAccessory = SPWindowTabAccessory()

    deinit {
        print("Deinit called")
    }
}

// MARK: - Private API

private extension SPWindowController {
    /// The main window nib carries `frameAutosaveName="MainWindow"`, but `NSWindowController`
    /// applies its own (empty) `windowFrameAutosaveName` to the window it loads, so the nib
    /// value never takes effect: closing the last window and opening a new one (⌘W → ⌘N/⌘T)
    /// dropped the user's window size and position (#1307). Restore the saved frame explicitly
    /// and claim the autosave name so subsequent moves/resizes are persisted again.
    ///
    /// Only one live window can own an autosave name at a time, so with several windows open
    /// the claim is best-effort. Every window additionally saves its frame when it is moved,
    /// resized, or closed (see the `NSWindowDelegate` methods below), so the most recently
    /// manipulated window always defines the frame the next new window opens with - no
    /// ownership handover is needed when the claiming window closes first.
    func setupFramePersistence() {
        shouldCascadeWindows = false
        windowFrameAutosaveName = Self.frameAutosaveName
        window?.setFrameUsingName(Self.frameAutosaveName)
    }

    func setupAppearance() {
        databaseDocument.updateWindowTitle(self)

        window?.contentView?.addSubview(databaseDocument.databaseView())
        databaseDocument.databaseView().frame = window?.contentView?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 400)

        if #available(macOS 10.13, *) {
            window?.tab.accessoryView = tabAccessoryView
        }
    }
}

// MARK: - Public API

@objc extension SPWindowController {
    func updateWindow(title: String, tabTitle: String) {
        window?.title = title
        if #available(macOS 10.13, *) {
            window?.tab.title = tabTitle
        }
        
        tabAccessoryView.setTitle(title: tabTitle)
    }

    func updateWindowAccessory(color: NSColor?, isSSL: Bool) {
        tabAccessoryView.update(color: color, isSSL: isSSL)
    }
}

extension SPWindowController: NSWindowDelegate {
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !databaseDocument.parentTabShouldClose() {
            return false
        }

        if let appDelegate = NSApp.delegate as? SPAppController{
            appDelegate.setSpfSessionDocData(nil)
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Persist this window's frame as the shared last-used frame even when it never owned
        // the exclusive autosave name (only one live window can): the most recently closed
        // window wins, so the next new window restores the frame the user saw last (#1307).
        window?.saveFrame(usingName: Self.frameAutosaveName)

        // Tell listeners that this database document is being closed - fixes retain cycles and allows cleanup
        NotificationCenter.default.post(name: NSNotification.Name.SPDocumentWillClose, object: databaseDocument)
    }

    // AppKit only auto-persists moves and resizes for the single window that owns the
    // autosave name, so windows that lost the claim would leave stale frame data behind
    // if a new window opened while they were still alive. Save explicitly from every
    // window so the last-manipulated frame is always the one a new window restores.
    func windowDidMove(_ notification: Notification) {
        window?.saveFrame(usingName: Self.frameAutosaveName)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        window?.saveFrame(usingName: Self.frameAutosaveName)
    }
}
