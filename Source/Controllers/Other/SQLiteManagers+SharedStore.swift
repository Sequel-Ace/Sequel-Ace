//
//  SQLiteManagers+SharedStore.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
import OSLog

// The shared SQLite managers keep their stores in the application-support
// folder, which is found through the Objective-C file-manager additions and
// constants. This file is therefore a member of the "Sequel Ace" target only:
// the Unit Tests target compiles the managers themselves and gives them a path
// of its own, without a bridging header (AGENTS.md, "Unit Tests target — sharp
// edges").

extension SQLiteDisplayFormatManager {
    /// The shared store in the application-support folder.
    @objc static let sharedInstance = SQLiteDisplayFormatManager(
        databasePath: SQLiteSharedStoreLocation.path(forFileName: dbFileName, log: log, consequence: "Column display formats are not persisted.")
    )
}

extension SQLitePinnedTableManager {
    /// The shared store in the application-support folder, with the migration
    /// record in the standard user defaults.
    @objc static let sharedInstance = SQLitePinnedTableManager(
        databasePath: SQLiteSharedStoreLocation.path(forFileName: dbFileName, log: log, consequence: "Pinned tables are not persisted."),
        prefs: UserDefaults.standard
    )
}

/// Where the shared SQLite stores live.
private enum SQLiteSharedStoreLocation {
    /// The path of `fileName` in the application-support data folder.
    ///
    /// - Parameters:
    ///   - fileName: The store's file name.
    ///   - log: Where a missing folder is reported.
    ///   - consequence: What the missing folder means for the user, appended to the log message.
    /// - Returns: The path, or `nil` when the folder cannot be found or created.
    static func path(forFileName fileName: String, log: OSLog, consequence: String) -> String? {
        do {
            let dataPath = try FileManager.default.applicationSupportDirectory(forSubDirectory: SPDataSupportFolder)
            return dataPath + "/" + fileName
        } catch {
            log.error("No location for \(fileName): \(error.localizedDescription). \(consequence)")
            return nil
        }
    }
}
