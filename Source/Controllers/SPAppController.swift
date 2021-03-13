//
//  SPAppController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 09.03.2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import AppKit

extension SPAppController {

    // MARK: - File menu actions

    @IBAction func newWindow(_ sender: Any) {
        tabManager.newWindowForWindow()
    }

    @IBAction func newTab(_ sender: Any) {
        tabManager.newWindowForTab()
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

    // MARK: - View menu actions

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

    // MARK: - Database menu actions

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
}
