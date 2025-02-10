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
    
    @IBAction func showMegasearch(_ sender: Any) {
        tabManager.activeWindowController?.databaseDocument.showMegasearch()
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
