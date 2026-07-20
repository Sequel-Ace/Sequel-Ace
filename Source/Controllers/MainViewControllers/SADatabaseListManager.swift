//
//  SADatabaseListManager.swift
//  Sequel Ace
//
//  Owns the "choose database" popup configuration and the background-
//  thread database selection flow. Phase A1a extracted -setDatabases;
//  A1b extracted the navigator schema path; A1c moves the
//  -_selectDatabaseAndItem: orchestration here behind
//  `SADatabaseSelectionDelegate`. The thin wrappers
//  -chooseDatabase: and -selectDatabase:item: stay on
//  SPDatabaseDocument — they read document-local UI state and
//  haven't earned their own home yet.
//

import AppKit

/// Callbacks the database-selection flow makes back into its host
/// (in practice, `SPDatabaseDocument`) so the manager itself never
/// touches project-specific ObjC types and stays compilable into the
/// Unit Tests target without a bridging header.
///
/// The protocol is intentionally chunky: each member maps to one
/// specific step of the original `-_selectDatabaseAndItem:`
/// implementation. Keeping it that way lets the manager remain a
/// pure orchestration script.
///
/// Threading: the manager calls these from whichever thread its
/// `performSelection(database:item:delegate:)` runs on. Mutations
/// happen on whichever thread is appropriate; UI-thread requirements
/// are documented per-member.
@objc protocol SADatabaseSelectionDelegate: AnyObject {

    // MARK: State the manager reads and writes

    /// Mirrors the document's `selectedDatabase` ivar.
    var currentSelectedDatabase: String? { get set }

    /// Mirrors the document's `selectedTableName` ivar.
    var currentSelectedTable: String? { get set }

    /// Mirrors `[spHistoryControllerInstance modifyingState]`.
    var historyStateIsModifying: Bool { get set }

    // MARK: Predicates

    /// `[mySQLConnection isConnected]`.
    var isDatabaseConnected: Bool { get }

    /// `[self table]` — the currently displayed table name.
    var currentTableName: String? { get }

    // MARK: Bridges to project ObjC objects

    /// The popup button driven by the manager. Backed by the
    /// document's IBOutlet; UI mutations are wrapped in main-queue
    /// dispatch by the manager.
    var chooseDatabaseButton: NSPopUpButton! { get }

    /// `[mySQLConnection selectDatabase:name]`. Safe to call off
    /// the main thread (matches original behavior).
    @discardableResult func selectMySQLDatabase(_ name: String) -> Bool

    /// `[spHistoryControllerInstance updateHistoryEntries]`.
    func updateHistoryEntries()

    /// `[self setDatabases]` — rebuilds the popup. Must be invoked
    /// on the main thread; the manager wraps this in `SPMainQSync`
    /// equivalent dispatch.
    func rebuildDatabasesPopup()

    /// `[self endTask]`.
    func endLoadingTask()

    /// `[databaseDataInstance resetAllData]`.
    func resetDatabaseData()

    /// `[self detectDatabaseEncoding]`.
    func detectDatabaseEncoding()

    /// `[tablesListInstance setConnection:mySQLConnection]`.
    func reattachTablesListConnection()

    /// `[self updateWindowTitle:self]`.
    func refreshWindowTitle()

    /// Show the "Unable to select database" warning alert. The
    /// original code called `[NSAlert createWarningAlertWithTitle:…]`
    /// directly from the background thread; the delegate
    /// implementation should preserve that.
    func presentUnableToSelectDatabaseAlert(name: String)

    // MARK: Tables-list UI (main-thread)

    /// `[tablesListInstance selectItemWithName:name]`. Caller
    /// guarantees main-thread context.
    @discardableResult func selectTablesListItem(named name: String) -> Bool

    /// `[tablesListInstance setTableListSelectability:flag]`.
    func setTableListSelectability(_ flag: Bool)

    /// `[tablesListInstance makeTableListFilterHaveFocus]`.
    func focusTableListFilter()

    /// `[tablesListInstance makeTableListHaveFocus]`.
    func focusTableList()

    // MARK: Post-completion

    /// `[self _processDatabaseChangedBundleTriggerActions]`.
    func processDatabaseChangedBundleTriggers()
}

/// Partition result for system vs. user databases, exposed to ObjC.
@objc final class SADatabasePartition: NSObject {
    @objc let systemDatabases: [String]
    @objc let userDatabases: [String]

    @objc init(systemDatabases: [String], userDatabases: [String]) {
        self.systemDatabases = systemDatabases
        self.userDatabases = userDatabases
        super.init()
    }
}

/// A normalized row from `SHOW FULL TABLES` or `SHOW TABLE STATUS`.
///
/// The server controls the result column labels for these statements. In
/// particular, the table-name label contains the selected database name and
/// some MySQL-compatible servers use different casing or entirely different
/// labels. Normalizing array rows here keeps the table-list UI independent of
/// those labels.
@objc final class SATableListEntry: NSObject {
    @objc let name: String
    @objc let comment: String
    @objc let isView: Bool

    init(name: String, comment: String, isView: Bool) {
        self.name = name
        self.comment = comment
        self.isView = isView
        super.init()
    }
}

@objc final class SATableListResultParser: NSObject {
    /// Normalize rows using the stable result-column order documented by
    /// MySQL and MariaDB. `SHOW FULL TABLES` returns the table name first and
    /// table type second. `SHOW TABLE STATUS` returns the table name first;
    /// its Comment column is located case-insensitively because later server
    /// versions may append additional columns.
    @objc(parseRows:fieldNames:displayTableComments:)
    static func parse(rows: [NSArray],
                      fieldNames: [String],
                      displayTableComments: Bool) -> [SATableListEntry] {
        let commentIndex = displayTableComments
            ? fieldNames.firstIndex { $0.caseInsensitiveCompare("Comment") == .orderedSame }
            : nil

        return rows.compactMap { row in
            guard row.count > 0 else { return nil }

            // Preserve the legacy placeholder for a genuinely missing table
            // name. Non-standard column labels no longer reach this fallback
            // because the name is read directly from the first column.
            let name = string(in: row, at: 0) ?? "..."
            let tableType = displayTableComments ? nil : string(in: row, at: 1)
            let comment = commentIndex.flatMap { string(in: row, at: $0) } ?? ""
            let isView = comment == "VIEW" || tableType == "VIEW"
            return SATableListEntry(name: name, comment: comment, isView: isView)
        }
    }

    private static func string(in row: NSArray, at index: Int) -> String? {
        guard index < row.count else { return nil }
        return row[index] as? String
    }
}

@objc final class SADatabaseListManager: NSObject {

    /// Separator placed between connectionID and database name in
    /// SPNavigatorController schema paths. Matches the value of
    /// `SPUniqueSchemaDelimiter` in SPConstants.m (U+FFF8). Inlined for
    /// the same reason as `systemDatabaseNames` — keeps this file free
    /// of an ObjC bridging-header dependency so the Unit Tests target
    /// can compile it.
    @objc static let schemaPathDelimiter: String = "\u{FFF8}"

    /// Build the path that `SPNavigatorController` uses to highlight
    /// the currently selected database in the schema browser.
    ///
    /// Shape: `<connectionID>` if the popup has no selected title or
    /// it's empty; otherwise `<connectionID><U+FFF8><databaseTitle>`.
    ///
    /// Pulled out of -[SPDatabaseDocument selectDatabase:item:] so it
    /// can be tested without a live NSPopUpButton or
    /// SPNavigatorController.
    @objc static func navigatorSchemaPath(connectionID: String,
                                          selectedDatabaseTitle: String?) -> String {
        guard let title = selectedDatabaseTitle, !title.isEmpty else {
            return connectionID
        }
        return connectionID + schemaPathDelimiter + title
    }

    /// The four built-in databases that get pulled into a separate
    /// "system" section of the popup.
    ///
    /// Literals match the values of the corresponding `SPMySQL*Database`
    /// extern constants in SPConstants.m. They are duplicated here so
    /// this file has no ObjC bridging-header dependency (mirrors the
    /// pattern established for SAViewMode in PR #2402), which lets it
    /// be compiled into the Unit Tests target.
    ///
    /// Must stay in sync with SPConstants.m if anyone renames a system
    /// database — `SADatabaseListManagerTests.testSystemDatabaseNames`
    /// pins the values.
    static let systemDatabaseNames: Set<String> = [
        "mysql",
        "information_schema",
        "performance_schema",
        "sys",
    ]

    /// Split a flat list of database names into a (system, user) pair,
    /// preserving the input order within each bucket.
    @objc static func partition(databases: [String]) -> SADatabasePartition {
        var system: [String] = []
        var user: [String] = []
        for name in databases {
            if systemDatabaseNames.contains(name) {
                system.append(name)
            } else {
                user.append(name)
            }
        }
        return SADatabasePartition(systemDatabases: system, userDatabases: user)
    }

    /// Rebuild a "choose database" `NSPopUpButton`:
    ///   1. Fixed header: "Choose Database..." placeholder, separator,
    ///      "Add Database..." action, "Refresh Databases" action,
    ///      trailing separator.
    ///   2. System databases (mysql, information_schema, ...) in their
    ///      own section followed by a separator.
    ///   3. User databases.
    ///
    /// Then select `currentDatabase` if set, or fall back to the
    /// placeholder at index 0.
    ///
    /// The two header-item actions are added with `target == nil`, so
    /// they dispatch via the responder chain — same as the original
    /// -[SPDatabaseDocument setDatabases] code. The caller is
    /// responsible for ensuring the chain reaches a handler that
    /// implements both selectors (SPDatabaseDocument now provides
    /// `-addDatabase:` and a `-setDatabases:` takes-sender wrapper).
    ///
    /// Must run on the UI thread (mirrors the original
    /// -[SPDatabaseDocument setDatabases] contract).
    ///
    /// Returns the (system, user) partition so the caller can store the
    /// arrays — they still have callers outside this method (database
    /// add/copy/rename enablement, the delete path).
    @objc static func configurePopup(
        _ popup: NSPopUpButton,
        databases: [String],
        currentDatabase: String?,
        addDatabaseSelector: Selector,
        refreshDatabasesSelector: Selector
    ) -> SADatabasePartition {
        popup.removeAllItems()

        popup.addItem(withTitle: NSLocalizedString("Choose Database...", comment: "menu item for choose db"))
        popup.menu?.addItem(NSMenuItem.separator())

        // Nil-target so the message goes through the responder chain.
        popup.menu?.addItem(withTitle: NSLocalizedString("Add Database...", comment: "menu item to add db"),
                            action: addDatabaseSelector,
                            keyEquivalent: "")
        popup.menu?.addItem(withTitle: NSLocalizedString("Refresh Databases", comment: "menu item to refresh databases"),
                            action: refreshDatabasesSelector,
                            keyEquivalent: "")

        popup.menu?.addItem(NSMenuItem.separator())

        let partition = partition(databases: databases)

        // Skip empty-string names defensively — mirrors the
        // -safeAddItemWith(title:) helper used by the original code,
        // inlined here so this file has no cross-file dependency.
        for database in partition.systemDatabases where !database.isEmpty {
            popup.addItem(withTitle: database)
        }
        if !partition.systemDatabases.isEmpty {
            popup.menu?.addItem(NSMenuItem.separator())
        }
        for database in partition.userDatabases where !database.isEmpty {
            popup.addItem(withTitle: database)
        }

        if let current = currentDatabase, !current.isEmpty {
            popup.selectItem(withTitle: current)
        } else {
            popup.selectItem(at: 0)
        }

        return partition
    }

    /// Background-thread orchestration for selecting a database (and
    /// optionally a table). Lifted from
    /// `-[SPDatabaseDocument _selectDatabaseAndItem:]` so the document
    /// no longer owns the threading / popup-rebuild-and-retry
    /// machinery.
    ///
    /// `delegate` is held only for the duration of the call.
    ///
    /// Behavior must match the original byte-for-byte: if the database
    /// hasn't changed the connection isn't touched; if the popup is
    /// stale or `selectDatabase:` fails, the popup is rebuilt and the
    /// selection retried once; if it still fails an alert is shown and
    /// the task is ended early; otherwise the database is switched in,
    /// the tables list is updated, focus is restored, and the task is
    /// ended.
    ///
    /// The caller is responsible for wrapping the call in an
    /// `@autoreleasepool` if invoked from a long-lived background
    /// thread (the original `-_selectDatabaseAndItem:` did this).
    @objc static func performSelection(database: String,
                                       item: String?,
                                       delegate: SADatabaseSelectionDelegate) {
        let historyStateChanging = delegate.historyStateIsModifying
        if !historyStateChanging {
            delegate.updateHistoryEntries()
            delegate.historyStateIsModifying = true
        }

        if database != delegate.currentSelectedDatabase {
            var targetIndex = mainSync {
                delegate.chooseDatabaseButton.indexOfItem(withTitle: database)
            }
            var didSelect = delegate.selectMySQLDatabase(database)

            // Refresh database metadata and retry once when the list
            // is stale or the initial selection failed.
            if (targetIndex == NSNotFound || !didSelect) && delegate.isDatabaseConnected {
                mainSync {
                    delegate.rebuildDatabasesPopup()
                }
                targetIndex = mainSync {
                    delegate.chooseDatabaseButton.indexOfItem(withTitle: database)
                }
                if !didSelect {
                    didSelect = delegate.selectMySQLDatabase(database)
                }
            }

            if !didSelect {
                // End the task first so the popup can be re-selected.
                delegate.endLoadingTask()

                if delegate.isDatabaseConnected {
                    delegate.presentUnableToSelectDatabaseAlert(name: database)
                }

                // Restore the popup's visible selection to the database
                // we're still on: the switch failed, so we never advanced
                // `currentSelectedDatabase`, but the popup is currently
                // showing the un-selectable target the user clicked.
                // Snap it back so the UI stays consistent with the live
                // connection. (The original ObjC left the popup on the
                // failed entry — see PR #2414 review.)
                mainSync {
                    if let current = delegate.currentSelectedDatabase, !current.isEmpty {
                        delegate.chooseDatabaseButton.selectItem(withTitle: current)
                    } else {
                        delegate.chooseDatabaseButton.selectItem(at: 0)
                    }
                }

                if !historyStateChanging {
                    delegate.historyStateIsModifying = false
                    delegate.updateHistoryEntries()
                }
                return
            }

            if targetIndex == NSNotFound {
                mainSync {
                    // Defensive: skip empty titles, mirroring
                    // `-safeAddItemWithTitle:` in the original code.
                    if !database.isEmpty {
                        delegate.chooseDatabaseButton.addItem(withTitle: database)
                    }
                }
                targetIndex = mainSync {
                    delegate.chooseDatabaseButton.indexOfItem(withTitle: database)
                }
            }

            mainSync {
                if targetIndex != NSNotFound {
                    delegate.chooseDatabaseButton.selectItem(withTitle: database)
                } else {
                    delegate.chooseDatabaseButton.selectItem(at: 0)
                }
            }

            delegate.currentSelectedDatabase = database
            delegate.currentSelectedTable = nil

            delegate.resetDatabaseData()

            // Update the stored database encoding, used for views,
            // "default" table encodings, and the View-using-encoding
            // menu.
            delegate.detectDatabaseEncoding()

            // Set the connection of SPTablesList to reload tables
            // in db.
            delegate.reattachTablesListConnection()

            delegate.refreshWindowTitle()
        }

        mainSync {
            var focusOnFilter = true
            if item != nil { focusOnFilter = false }

            // If the table has changed, update the selection.
            if let targetItem = item, targetItem != delegate.currentTableName {
                focusOnFilter = !delegate.selectTablesListItem(named: targetItem)
            }

            // Ensure the window focus is on the table list or the
            // filter as appropriate.
            delegate.setTableListSelectability(true)
            if focusOnFilter {
                delegate.focusTableListFilter()
            } else {
                delegate.focusTableList()
            }
            delegate.setTableListSelectability(false)
        }

        if !historyStateChanging {
            delegate.historyStateIsModifying = false
            delegate.updateHistoryEntries()
        }

        delegate.endLoadingTask()
        delegate.processDatabaseChangedBundleTriggers()
    }

    /// Main-queue equivalent of `SPMainQSync` — run inline if already on
    /// the main thread, otherwise `dispatch_sync` to it. Kept private so
    /// the file stays free of project-wide ObjC dependencies.
    private static func mainSync<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        }
        return DispatchQueue.main.sync(execute: block)
    }
}
