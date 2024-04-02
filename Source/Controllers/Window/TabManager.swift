//
//  TabManager.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 07.03.2021.
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

import AppKit

@objc final class TabManager: NSObject {

    // MARK: - Custom struct

    private struct ManagedWindow {
        /// Keep the controller around to store a strong reference to it
        let windowController: SPWindowController

        /// Keep the window around to identify instances of this type
        let window: NSWindow

        /// React to window closing, auto-unsubscribing on dealloc
        let closingSubscription: NotificationToken
    }

    // MARK: - Private properties

    private var managedWindows: [ManagedWindow] = []

    /// Returns the main window of the managed window stack.
    /// Falls back the first element if no window is main. Note that this would
    /// likely be an internal inconsistency we gracefully handle here.
    private var mainWindow: NSWindow? {
        let mainManagedWindow = managedWindows.first { $0.window.isMainWindow }

        // In case we run into the inconsistency, let it crash in debug mode so we
        // can fix our window management setup to prevent this from happening.
        assert(mainManagedWindow != nil || managedWindows.isEmpty)

        return (mainManagedWindow ?? managedWindows.first).map { $0.window }
    }

    // MARK: - Public properties

    @objc var activeWindowController: SPWindowController? {
        return managedWindows.first { $0.window.isMainWindow }?.windowController
    }

    @objc var windowControllers: [SPWindowController] {
        return managedWindows.compactMap { $0.windowController}
    }

    @objc var windows: Set<NSWindow> {
        return Set(windowControllers.compactMap { $0.window })
    }

    weak var appController: SPAppController?

    // MARK: - Lifecycle

    @objc init(appController: SPAppController) {
        self.appController = appController

        super.init()
    }

    // MARK: - Public API

    @objc func switchToPreviousTab() {
        activeWindowController?.window!.selectPreviousTab(nil)
    }

    @objc func switchToNextTab() {
        activeWindowController?.window!.selectNextTab(nil)
    }

    @discardableResult
    @objc func newWindowForTab() -> SPWindowController {
        if let existingWindow = mainWindow {
            let windowController = createNewWindowController()
            createTab(newWindowController: windowController, inWindow: existingWindow, ordered: .above)
            return windowController
        } else {
            return replaceTabServiceWithInitialWindow()
        }
    }

    @discardableResult
    @objc func newWindowForWindow() -> SPWindowController {
        let windowController = createNewWindowController()
        createWindow(newWindowController: windowController, inWindow: SPWindow(), ordered: .above)
        return windowController
    }

    @discardableResult
    @objc func replaceTabServiceWithInitialWindow() -> SPWindowController {
        let windowController = createNewWindowController()
        createWindow(newWindowController: windowController, inWindow: SPWindow(), ordered: .above)
        windowController.showWindow(self)
        return windowController
    }

    @objc func windowControllerWithDocument(processID: String) -> SPWindowController? {
        return managedWindows.first(where: { $0.windowController.databaseDocument.processID == processID })?.windowController
    }
}

// MARK: - Private API

private extension TabManager {
    func createNewWindowController() -> SPWindowController {
        let windowController = SPWindowController(windowNibName: "MainWindow")
        windowController.window?.delegate = windowController
        return windowController
    }

    func createTab(newWindowController: SPWindowController, inWindow window: NSWindow, ordered orderingMode: NSWindow.OrderingMode) {

        guard let newManagement = addManagedWindow(windowController: newWindowController) else { preconditionFailure() }
        let newWindow = newManagement.window

        // In case user hits "+" in the UI in tab bar - system automatically creates a tab for us and adds it to the tabGroup - there is no way to avoid it and no way to work around it. In case user hits CMD+T or "New tab" in Menu, it's upon us to do so, so we add tabbed window manually
        if managedWindows.first(where: { $0.window.isMainWindow }) != nil {
            window.addTabbedWindow(newWindow, ordered: orderingMode)
        }
        let index = window.tabGroup?.windows.firstIndex(of: newWindow) ?? 0
        managedWindows.insert(newManagement, at: index)
        newWindow.makeKeyAndOrderFront(nil)
    }

    func createWindow(newWindowController: SPWindowController, inWindow window: NSWindow, ordered orderingMode: NSWindow.OrderingMode) {

        guard let newManagement = addManagedWindow(windowController: newWindowController) else { preconditionFailure() }
        let newWindow = newManagement.window

        window.addChildWindow(newWindow, ordered: orderingMode)
        let index = window.tabGroup?.windows.firstIndex(of: newWindow) ?? 0
        managedWindows.insert(newManagement, at: index)
        newWindow.collectionBehavior = [newWindow.collectionBehavior, .participatesInCycle]
        newWindow.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    private func addManagedWindow(windowController: SPWindowController) -> ManagedWindow? {
        guard let window = windowController.window else {
            return nil
        }

        let subscription = NotificationCenter.default.observe(name: NSWindow.willCloseNotification, object: window) { [unowned self] notification in
            guard let window = notification.object as? NSWindow else {
                return
            }
            self.removeManagedWindow(forWindow: window)
        }
        return ManagedWindow(windowController: windowController, window: window, closingSubscription: subscription)
    }

    func removeManagedWindow(forWindow window: NSWindow) {
        managedWindows.removeAll(where: { $0.window === window })
    }
}
