//
//  SPAppController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 09.03.2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import AppKit

// MARK: - Menu actions

extension SPAppController {

    // MARK: File menu actions

    @IBAction func newWindow(_ sender: Any) {
        tabManager.newWindowForWindow()
    }

    @IBAction func newTab(_ sender: Any) {
        tabManager.newWindowForTab()
    }

    /// Opens a standalone connection window (decoupled from document lifecycle).
    /// This is the modernized connection flow — the connection screen exists
    /// independently, and only creates a document tab on successful connect.
    /// Tracks open standalone connection windows so they don't get deallocated.
    private static var standaloneConnectionWindows: [SAConnectionWindowController] = []

    @IBAction func openStandaloneConnectionWindow(_ sender: Any) {
        let controller = SAConnectionWindowController()
        controller.showWindow(sender)

        // Retain the controller; remove when its window closes.
        Self.standaloneConnectionWindows.append(controller)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: controller.window,
            queue: .main
        ) { _ in
            Self.standaloneConnectionWindows.removeAll { $0 === controller }
        }
    }

    @IBAction func export(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.exportData()
    }

    @IBAction func addConnectionToFavorites(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.addConnectionToFavorites()
    }

    @IBAction func saveConnectionSheet(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.saveConnectionSheet(sender)
    }

    @IBAction func `import`(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.importFile()
    }

    @IBAction func importFromClipboard(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.importFromClipboard()
    }

    @IBAction func printDocument(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.print()
    }

    // MARK: Edit menu actions

    // Override default "CMD+F" for find and if we are on content view, perform Show filter
    @IBAction func performFindPanelAction(_ sender: Any) {
        if tabManager.activeWindowController?.databaseDocument.currentlySelectedView() == .content {
            tabManager.activeWindowController?.databaseDocument.focusOnTableContentFilter()
        }
    }

    // MARK: View menu actions

    @IBAction func viewStructure(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.viewStructure()
    }

    @IBAction func viewContent(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.viewContent()
    }

    @IBAction func viewQuery(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.viewQuery()
    }

    @IBAction func viewStatus(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.viewStatus()
    }

    @IBAction func viewRelations(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.viewRelations()
    }

    @IBAction func viewTriggers(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.viewTriggers()
    }

    @IBAction func backForwardInHistory(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.backForwardInHistory(sender)
    }

    @IBAction func toggleConsole(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.toggleConsole()
    }

    @IBAction func toggleNavigator(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.toggleNavigator()
    }

    // MARK: Database menu actions

    @IBAction func showGotoDatabase(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.showGotoDatabase()
    }

    @IBAction func addDatabase(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.addDatabase(sender)
    }

    @IBAction func removeDatabase(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.removeDatabase(sender)
    }

    @IBAction func copyDatabase(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.copyDatabase()
    }

    @IBAction func renameDatabase(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.renameDatabase()
    }

    @IBAction func alterDatabase(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.alterDatabase()
    }

    @IBAction func refreshTables(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.refreshTables()
    }

    @IBAction func flushPrivileges(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.flushPrivileges()
    }

    @IBAction func setDatabases(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.setDatabases()
    }

    @IBAction func showUserManager(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.showUserManager()
    }

    @IBAction func chooseEncoding(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.chooseEncoding(sender)
    }

    @IBAction func openDatabaseInNewTab(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.openDatabaseInNewTab()
    }

    @IBAction func showServerVariables(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.showServerVariables()
    }

    @IBAction func showServerProcesses(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.showServerProcesses()
    }

    @IBAction func shutdownServer(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.shutdownServer()
    }

    // MARK: Table menu actions

    @IBAction func focusOnTableContentFilter(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.focusOnTableContentFilter()
    }

    @IBAction func showFilterTable(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.showFilterTable()
    }

    @IBAction func makeTableListFilterHaveFocus(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.makeTableListFilterHaveFocus(nil)
    }

    @IBAction func copyCreateTableSyntax(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.copyCreateTableSyntax(nil)
    }

    @IBAction func showCreateTableSyntax(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.showCreateTableSyntax(nil)
    }

    @IBAction func checkTable(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.checkTable()
    }

    @IBAction func repairTable(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.repairTable()
    }

    @IBAction func analyzeTable(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.analyzeTable()
    }

    @IBAction func optimizeTable(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.optimizeTable()
    }

    @IBAction func flushTable(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.flushTable()
    }

    @IBAction func checksumTable(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.checksumTable()
    }

    // MARK: Help menu actions

    @IBAction func showMySQLHelp(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.showMySQLHelp()
    }
}

// MARK: - Standalone Connection Window Menu Item

extension SPAppController {

    /// Adds a "New Connection Window" menu item to the File menu.
    /// Called from applicationDidFinishLaunching via ObjC.
    @objc func installStandaloneConnectionMenuItem() {
        guard let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu else { return }

        // Insert after "New Tab" (index 1) or at index 2
        let insertIndex = min(2, fileMenu.items.count)

        let menuItem = NSMenuItem(
            title: NSLocalizedString("New Connection Window", comment: "Menu item for standalone connection window"),
            action: #selector(openStandaloneConnectionWindow(_:)),
            keyEquivalent: "N"  // Cmd+Shift+N
        )
        menuItem.keyEquivalentModifierMask = [.command, .shift]
        menuItem.target = nil // Uses responder chain

        fileMenu.insertItem(menuItem, at: insertIndex)
    }
}

extension SPAppController {
    @objc func dialogOKCancel(question: String, text: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
