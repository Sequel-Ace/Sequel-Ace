//
//  SPWindowController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 24.01.2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import Cocoa
import SnapKit

extension SPWindowController {
    @objc func setupAppearance() {
        // Here should happen all UI / layout setups in the future once we remove .xib
    }

    @objc func setupConstraints() {
        // Here we will set constraints in the future once we remove .xib, for now, commented out as it crashes
//        tabBarControl.snp.makeConstraints {
//            $0.top.equalToSuperview()
//            $0.leading.trailing.equalToSuperview()
//            $0.height.equalTo(25)
//        }
//        tabView.snp.makeConstraints {
//            $0.top.equalTo(tabBarControl.snp.bottom)
//            $0.leading.trailing.equalToSuperview()
//            $0.bottom.equalToSuperview()
//        }
    }
}

extension SPWindowController: NSWindowDelegate {
    /// Determine whether the window is permitted to close.
    /// Go through the tabs in this window, and ask the database connection view in each one if it can be closed, returning YES only if all can be closed.
    /// - Parameter sender: NSWindow instance
    /// - Returns: true or false
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        for tabItem in tabView.tabViewItems {
            guard let document = tabItem.databaseDocument else {
                continue
            }
            if !document.parentTabShouldClose() {
                return false
            }
        }

        if let appDelegate = NSApp.delegate as? SPAppController, appDelegate.sessionURL() != nil, appDelegate.windowControllers.count == 1 {
            appDelegate.setSessionURL(nil)
            appDelegate.setSpfSessionDocData(nil)
        }
        delegate.windowControllerDidClose(self)
        return true
    }

    public func windowWillClose(_ notification: Notification) {
        tabView.tabViewItems.forEach {
            tabView.removeTabViewItem($0)
        }
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        selectedTableDocument.tabDidBecomeKey()

        // Update close tab
        closeTabMenuItem.isEnabled = true
        closeTabMenuItem.keyEquivalent = "w"
        closeTabMenuItem.keyEquivalentModifierMask = .command

        // Update the "Close" item to show "Close window"
        closeWindowMenuItem.title = NSLocalizedString("Close Window", comment: "Close Window menu item")
        closeWindowMenuItem.keyEquivalentModifierMask = [.command, .shift]
    }

    public func windowDidResignKey(_ notification: Notification) {
        // Update close tab
        closeTabMenuItem.isEnabled = true
        closeTabMenuItem.keyEquivalentModifierMask = [.command, .shift]

        // Update the "Close window" item to show only "Close"
        closeWindowMenuItem.title = NSLocalizedString("Close", comment: "Close menu item")
        closeWindowMenuItem.keyEquivalentModifierMask = .command
    }

    public func windowDidResize(_ notification: Notification) {
        tabView.tabViewItems.forEach {
            $0.databaseDocument?.tabDidResize()
        }
    }
}
