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
extension SPDatabaseDocument: SADatabaseDocumentProviding {

    public func setIsProcessing(_ value: Bool) {
        isProcessing = value
    }
}

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
extension SPDatabaseDocument: SATaskManaging {
    // Explicit forwarding stubs to bridge ObjC method signatures to Swift protocol.
    // These call through to the ObjC implementations using the exact ObjC selectors.

    public func setTaskProgressToIndeterminate(afterDelay: Bool) {
        setTaskProgressToIndeterminateAfterDelay(afterDelay)
    }

    public func enableTaskCancellation(withTitle title: String, callbackObject: AnyObject?, callbackFunction: Selector?) {
        enableTaskCancellation(withTitle: title, callbackObject: callbackObject, callbackFunction: callbackFunction ?? Selector(("_")))
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
