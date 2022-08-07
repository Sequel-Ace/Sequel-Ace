//
//  SPDatabaseDocument.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 11.03.2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import AppKit

extension SPDatabaseDocument {
    @objc func prepareSaveAccessoryView(panel: NSSavePanel) {
        guard Bundle.main.loadNibNamed("SaveSPFAccessory", owner: self, topLevelObjects: nil) else {
            Swift.print("❌ SaveSPFAccessory accessory dialog could not be loaded.")
            return
        }
        panel.allowedFileTypes = [SPBundleFileExtension]

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
