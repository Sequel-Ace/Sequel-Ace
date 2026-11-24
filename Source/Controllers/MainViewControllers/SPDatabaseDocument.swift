//
//  SPDatabaseDocument.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 11.03.2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import AppKit

// MARK: - SADatabaseDocumentProviding

// SPDatabaseDocument conforms to SADatabaseDocumentProviding.
// All requirements are satisfied by the ObjC declarations in SPDatabaseDocument.h.
// If a requirement is not visible to Swift, we add an explicit forwarding stub below.
// isProcessing property requirement is satisfied by the ObjC @property (readwrite) BOOL isProcessing.
extension SPDatabaseDocument: SADatabaseDocumentProviding {}

// MARK: - SATaskManaging

// SPDatabaseDocument conforms to SATaskManaging.
// All methods are implemented in SPDatabaseDocument.m.
// The ObjC method names map directly to the protocol requirements:
//   startTask(withDescription:) -> startTaskWithDescription:
//   endTask -> endTask
//   setTaskPercentage(_:) -> setTaskPercentage:
//   setTaskProgressToIndeterminate(afterDelay:) -> setTaskProgressToIndeterminateAfterDelay:
//   enableTaskCancellation(withTitle:callbackObject:callbackFunction:) -> enableTaskCancellationWithTitle:callbackObject:callbackFunction:
//   disableTaskCancellation -> disableTaskCancellation
//   isWorking -> isWorking
//   setDatabaseListIsSelectable(_:) -> setDatabaseListIsSelectable:
//   setTaskDescription(_:) -> setTaskDescription:
// The protocol requirements use @objc(...) to bind each Swift method to the
// exact existing ObjC selector on SPDatabaseDocument (declared in
// SPDatabaseDocument.h / implemented in SPDatabaseDocument.m), so conformance
// is satisfied directly by those ObjC methods — no forwarding stub needed.
//
// The previous stubs recursed: a Swift method marked @objc with the same
// selector as the ObjC method it tried to call ends up pointing at itself
// in the class method table, so `method(for:)` (or a regular Swift call)
// dispatches straight back into the stub until the stack overflows.
extension SPDatabaseDocument: SATaskManaging {}

// MARK: - SATaskControllerDelegate

// SPDatabaseDocument hosts the SATaskController extracted in Phase A2.
// `taskParentWindow` and `taskControllerDidRequestCancellation` are
// implemented in SPDatabaseDocument.m (they reach into the live MySQL
// connection and the parent window controller).
extension SPDatabaseDocument: SATaskControllerDelegate {}

// MARK: - Sidebar Columns

@objc(SASidebarColumn) final class SASidebarColumn: NSObject {
    let name: String
    let type: String

    init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

extension SPDatabaseDocument {
    @objc(loadSidebarColumnsForTable:completion:)
    func loadSidebarColumns(forTable table: String, completion: @escaping ([SASidebarColumn]?) -> Void) -> Bool {
        // Capture the selected database before dispatch. It can change while the lookup is queued.
        guard let database = database() else { return false }
        let structure = databaseStructureRetrieval
        DispatchQueue.global(qos: .userInitiated).async {
            let columns = Self.readSidebarColumns(table: table, database: database, from: structure)
            DispatchQueue.main.async { completion(columns) }
        }
        return true
    }

    private static func readSidebarColumns(table: String, database: String, from structure: SPDatabaseStructure) -> [SASidebarColumn]? {
        // Qualify both identifiers because the metadata connection has its own session state.
        guard let quotedTable = (table as NSString).backtickQuoted(),
              let quotedDatabase = (database as NSString).backtickQuoted(),
              let connection = structure.connection(),
              let result = connection.queryString("SHOW COLUMNS FROM \(quotedTable) FROM \(quotedDatabase)") else {
            return nil
        }

        result.returnDataAsStrings = true
        var columns: [SASidebarColumn] = []
        while let row = result.getRowAsDictionary() {
            guard let name = row["Field"] as? String, let type = row["Type"] as? String else { continue }
            columns.append(SASidebarColumn(name: name, type: type))
        }
        return columns.isEmpty ? nil : columns
    }
}

// MARK: - Save Accessory

extension SPDatabaseDocument {
    @objc func prepareSaveAccessoryView(panel: NSSavePanel) {
        guard Bundle.main.loadNibNamed("SaveSPFAccessory", owner: self, topLevelObjects: nil) else {
            Swift.print("❌ SaveSPFAccessory accessory dialog could not be loaded.")
            return
        }

        guard let appDelegate = NSApp.delegate as? SPAppController else {
            return
        }

        let sessionData = appDelegate.spfSessionDocData()

        // Restore accessory view settings if possible
        if let save_password = sessionData?["save_password"] as? Bool {
            saveConnectionSavePassword?.state = save_password ? .on : .off
        }
        if let auto_connect = sessionData?["auto_connect"] as? Bool {
            saveConnectionAutoConnect?.state = auto_connect ? .on : .off
        }
        if let encrypted = sessionData?["encrypted"] as? Bool {
            saveConnectionEncrypt?.state = encrypted ? .on : .off
        }
        if let include_session = sessionData?["include_session"] as? Bool {
            saveConnectionIncludeData?.state = include_session ? .on : .off
        }
        if let save_editor_content = sessionData?["save_editor_content"] as? Bool {
            saveConnectionIncludeQuery?.state = save_editor_content ? .on : .off
        } else {
            saveConnectionIncludeQuery?.state = .on
        }
    }
}
