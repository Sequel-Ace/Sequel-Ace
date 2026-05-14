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
            saveConnectionSavePassword.state = save_password ? .on : .off
        }
        if let auto_connect = sessionData?["auto_connect"] as? Bool {
            saveConnectionAutoConnect.state = auto_connect ? .on : .off
        }
        if let encrypted = sessionData?["encrypted"] as? Bool {
            saveConnectionEncrypt.state = encrypted ? .on : .off
        }
        if let include_session = sessionData?["include_session"] as? Bool {
            saveConnectionIncludeData.state = include_session ? .on : .off
        }
        if let save_editor_content = sessionData?["save_editor_content"] as? Bool {
            saveConnectionIncludeQuery.state = save_editor_content ? .on : .off
        } else {
            saveConnectionIncludeQuery.state = .on
        }
    }
}
