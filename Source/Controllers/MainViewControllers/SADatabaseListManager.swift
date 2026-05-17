//
//  SADatabaseListManager.swift
//  Sequel Ace
//
//  Owns the "choose database" popup configuration and (eventually) the
//  database selection flow. Phase A1a extracts only -setDatabases —
//  -chooseDatabase:, -selectDatabase:item:, and the background-thread
//  -_selectDatabaseAndItem: path will move here in follow-up steps.
//

import AppKit

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

@objc final class SADatabaseListManager: NSObject {

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
}
