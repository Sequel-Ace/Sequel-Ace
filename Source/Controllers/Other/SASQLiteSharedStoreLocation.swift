//
//  SASQLiteSharedStoreLocation.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import AppKit
import Foundation
import OSLog

// The shared SQLite managers keep their stores in the application-support
// folder, which is found through the Objective-C file-manager additions and
// constants. This file is therefore a member of the "Sequel Ace" target only:
// the Unit Tests target compiles the managers themselves and gives them a path
// of its own, without a bridging header (AGENTS.md, "Unit Tests target — sharp
// edges"). It is also where a store the managers cannot use reaches the user.

extension SQLiteDisplayFormatManager {
    /// The shared store in the application-support folder. A problem with it is
    /// shown once, the first time this instance is used.
    @objc static let sharedInstance: SQLiteDisplayFormatManager = {
        let consequence = NSLocalizedString("Display formats you choose still work until you quit Sequel Ace, but they are not kept.", comment: "SQLite store problem: what an unusable display-format store means for the user")
        let manager = SQLiteDisplayFormatManager(
            databasePath: SASQLiteSharedStoreLocation.path(forFileName: dbFileName, log: log, consequence: "Column display formats are not persisted.")
        )
        manager.problems.onProblem { problem in
            SASQLiteStoreProblemAlert.show(
                problem,
                title: NSLocalizedString("Column display formats are not being saved", comment: "SQLite store problem alert title: the display-format store is unusable"),
                consequence: consequence
            )
        }
        return manager
    }()
}

extension SQLitePinnedTableManager {
    /// The shared store in the application-support folder, with the migration
    /// record in the standard user defaults. A problem with the store is shown
    /// once, the first time this instance is used.
    @objc static let sharedInstance: SQLitePinnedTableManager = {
        let consequence = NSLocalizedString("Tables you pin still stay at the top until you quit Sequel Ace, but they are not kept.", comment: "SQLite store problem: what an unusable pinned-tables store means for the user")
        let manager = SQLitePinnedTableManager(
            databasePath: SASQLiteSharedStoreLocation.path(forFileName: dbFileName, log: log, consequence: "Pinned tables are not persisted."),
            prefs: UserDefaults.standard
        )
        manager.problems.onProblem { problem in
            SASQLiteStoreProblemAlert.show(
                problem,
                title: NSLocalizedString("Pinned tables are not being saved", comment: "SQLite store problem alert title: the pinned-tables store is unusable"),
                consequence: consequence
            )
        }
        return manager
    }()
}

/// Where the shared SQLite stores live.
private enum SASQLiteSharedStoreLocation {
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

/// Tells the user that one of the SQLite stores cannot be used, so the app does
/// not silently forget what they set.
private enum SASQLiteStoreProblemAlert {
    /// Shows one problem, on the main thread. The manager reports only the
    /// first problem per store, so this appears at most once per store and launch.
    ///
    /// - Parameters:
    ///   - problem: What went wrong with the store.
    ///   - title: The alert's headline, naming what is not being saved.
    ///   - consequence: What the problem means for the user's data.
    static func show(_ problem: SASQLiteStoreProblem, title: String, consequence: String) {
        let message = problem.message(consequence: consequence)
        let revealURL = problem.revealURL
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            // Order of buttons matters! The first one is the default.
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            if revealURL != nil {
                alert.addButton(withTitle: NSLocalizedString("Show in Finder", comment: "button that reveals a file in Finder"))
            }
            if alert.runModal() != .alertFirstButtonReturn, let revealURL {
                NSWorkspace.shared.activateFileViewerSelecting([revealURL])
            }
        }
    }
}
