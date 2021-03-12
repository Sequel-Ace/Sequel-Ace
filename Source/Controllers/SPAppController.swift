//
//  SPAppController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 09.03.2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import AppKit

extension SPAppController {
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
}
