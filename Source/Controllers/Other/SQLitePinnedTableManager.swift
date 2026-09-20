//
// Created by Shashwat Chaudhary on 20/10/21.
// Copyright (c) 2021 Sequel-Ace. All rights reserved.
//

import Foundation
import FMDB
import OSLog

@objc final class SQLitePinnedTableManager: NSObject {

    @objc static let sharedInstance = SQLitePinnedTableManager()
    @objc private var queue: FMDatabaseQueue
    private let Log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "pinnedTablesDatabase")
    private let prefs: UserDefaults = UserDefaults.standard
    private var traceExecution: Bool
    private var newSchemaVersion: Int32 = 0
    private var migratedLegacyPinnedTableTokens: Set<String> = []
    /// The empty group name represents the historical, global pinned section.
    private var pinnedTablesDatabaseDictionary: [String: [String: [String: [String]]]] = [:]
    private var collapsedPinnedTableGroups: [String: [String: Set<String>]] = [:]

    override private init() {
        traceExecution = prefs.bool(forKey: SPTraceSQLiteExecutions)
        migratedLegacyPinnedTableTokens = Set(prefs.stringArray(forKey: SPMigratedPinnedTablesToConnectionIDs) ?? [])

        var SPDataPath: String = ""
        do {
            SPDataPath = try FileManager.default.applicationSupportDirectory(forSubDirectory: SPDataSupportFolder)
        } catch {
            Log.error("Could not get path to applicationSupportDirectory. Error: \(error.localizedDescription)")
            queue = FMDatabaseQueue(path: " ")!
            super.init()
            return
        }

        let sqlitePath = SPDataPath + "/" + "pinnedTables.db"
        queue = FMDatabaseQueue(path: sqlitePath)!
        super.init()
        setupPinnedTablesDatabase()
        loadPinnedTablesHistory()

    }

    private func setupPinnedTablesDatabase() {

        let schemaBlock: SASchemaBuilder = { [self] db, schemaVersion in

            db.beginTransaction()

            if schemaVersion < 1 {
                Log.info("schemaVersion < 1, creating database")

                let createTableSQL = "CREATE TABLE PinnedTables ("
                        + "    id                   INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,"
                        + "    hostName             TEXT NOT NULL,"
                        + "    databaseName         TEXT NOT NULL,"
                        + "    pinnedTableName      TEXT NOT NULL,"
                        + "    groupName            TEXT NOT NULL DEFAULT '',"
                        + "    CONSTRAINT host_db_table UNIQUE (hostName, databaseName, pinnedTableName))"

                do {
                    try db.executeUpdate(createTableSQL, values: nil)
                    try db.executeUpdate("CREATE INDEX IF NOT EXISTS host_db_idx ON PinnedTables (hostName, databaseName)", values: nil)
                } catch {
                    db.rollback()
                    failed(error: error)
                }

                newSchemaVersion = Int32(schemaVersion + 1)
                Log.debug("self.newSchemaVersion \(newSchemaVersion)")
                Log.info("database created successfully")
            }

            if schemaVersion < 2 {
                Log.info("schemaVersion < 2, adding pinned table groups")
                do {
                    if schemaVersion >= 1 {
                        try db.executeUpdate("ALTER TABLE PinnedTables ADD COLUMN groupName TEXT NOT NULL DEFAULT ''", values: nil)
                    }
                    try db.executeUpdate("CREATE TABLE IF NOT EXISTS PinnedTableGroups (hostName TEXT NOT NULL, databaseName TEXT NOT NULL, groupName TEXT NOT NULL, CONSTRAINT host_db_group UNIQUE (hostName, databaseName, groupName))", values: nil)
                    try db.executeUpdate("CREATE INDEX IF NOT EXISTS host_db_group_idx ON PinnedTableGroups (hostName, databaseName)", values: nil)
                } catch {
                    db.rollback()
                    failed(error: error)
                }

                newSchemaVersion = 2
            }

            if schemaVersion < 3 {
                Log.info("schemaVersion < 3, adding pinned table group collapse state")
                do {
                    try db.executeUpdate("ALTER TABLE PinnedTableGroups ADD COLUMN isCollapsed INTEGER NOT NULL DEFAULT 0", values: nil)
                } catch {
                    db.rollback()
                    failed(error: error)
                }

                newSchemaVersion = 3
            } else {
                Log.info("schemaVersion >= 1, not creating database")
                newSchemaVersion = Int32(schemaVersion)
            }

            db.commit()

        }

        queue.inDatabase { db in
            do {
                db.traceExecution = traceExecution
                var startingSchemaVersion: Int32 = 0

                let rs = try db.executeQuery("PRAGMA user_version", values: nil)

                if rs.next() {
                    startingSchemaVersion = rs.int(forColumnIndex: 0)
                    startingSchemaVersion = Int32(rs.long(forColumnIndex: 0))
                    Log.debug("startingSchemaVersion = \(startingSchemaVersion)")
                }
                rs.close()

                schemaBlock(db, Int(startingSchemaVersion))

                if newSchemaVersion != startingSchemaVersion, newSchemaVersion > 0 {
                    let query = "PRAGMA user_version = " + String(newSchemaVersion)
                    Log.debug("query = \(query)")
                    try db.executeUpdate(query, values: nil)
                } else {
                    Log.info("db schema did not need an update")
                }
            } catch {
                Log.error("Something went wrong: \(error.localizedDescription)")
            }
        }
    }

    private func loadPinnedTablesHistory() {

        queue.inDatabase { db in
            do {
                db.traceExecution = traceExecution
                // select by id desc to get latest first
                let groupResult = try db.executeQuery("SELECT hostName, databaseName, groupName, isCollapsed FROM PinnedTableGroups", values: nil)
                while groupResult.next() {
                    let hostName = groupResult.string(forColumn: "hostName") ?? ""
                    let databaseName = groupResult.string(forColumn: "databaseName") ?? ""
                    let groupName = groupResult.string(forColumn: "groupName") ?? ""
                    addGroupToPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, groupName: groupName)
                    setPinnedTableGroupCollapsedInMemory(hostName: hostName, databaseName: databaseName, groupName: groupName, isCollapsed: groupResult.bool(forColumn: "isCollapsed"))
                }
                groupResult.close()

                let rs = try db.executeQuery("SELECT hostName, databaseName, pinnedTableName, groupName FROM PinnedTables order by id desc", values: nil)

                while rs.next() {
                    let hostName = rs.string(forColumn: "hostname")!
                    let databaseName = rs.string(forColumn: "databaseName")!
                    let pinnedTableName = rs.string(forColumn: "pinnedTableName")!
                    addToPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, tableToPin: pinnedTableName, groupName: rs.string(forColumn: "groupName") ?? "")
                }
                rs.close()
            } catch {
                logDBError(error)
            }
        }
        queue.close()
    }

    @objc func getPinnedTables(hostName: String, databaseName: String) -> [String] {
        return pinnedTablesDatabaseDictionary[hostName]?[databaseName]?.values.flatMap { $0 } ?? []
    }

    @objc(getPinnedTableGroupsWithHostName:databaseName:)
    func getPinnedTableGroups(hostName: String, databaseName: String) -> NSDictionary {
        return pinnedTablesDatabaseDictionary[hostName]?[databaseName] as NSDictionary? ?? [:]
    }

    @objc func pinTable(hostName: String, databaseName: String, tableToPin: String) {
        pinTable(hostName: hostName, databaseName: databaseName, tableToPin: tableToPin, groupName: "")
    }

    @objc(pinTableWithHostName:databaseName:tableToPin:groupName:)
    func pinTable(hostName: String, databaseName: String, tableToPin: String, groupName: String) {
        let normalizedGroupName = PinnedTableGroupPlanner.normalizedGroupName(groupName)
        if normalizedGroupName.isNotEmpty,
           pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[normalizedGroupName] == nil {
            createPinnedTableGroup(hostName: hostName, databaseName: databaseName, groupName: normalizedGroupName)
        }
        let existingGroupName = groupNameForPinnedTable(hostName: hostName, databaseName: databaseName, tableName: tableToPin)
        if existingGroupName == normalizedGroupName {
            return
        }

        if existingGroupName != nil {
            removeFromPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, tableToUnpin: tableToPin)
            addToPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, tableToPin: tableToPin, groupName: normalizedGroupName)
            queue.inDatabase { db in
                db.traceExecution = traceExecution
                do {
                    try db.executeUpdate("UPDATE PinnedTables SET groupName=? WHERE hostName=? AND databaseName=? AND pinnedTableName=?", values: [normalizedGroupName, hostName, databaseName, tableToPin])
                } catch {
                    logDBError(error)
                }
            }
        } else {
            addToPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, tableToPin: tableToPin, groupName: normalizedGroupName)
        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                    try db.executeUpdate("INSERT INTO PinnedTables (hostName, databaseName, pinnedTableName, groupName) VALUES (?, ?, ?, ?)",
                        values: [hostName, databaseName, tableToPin, normalizedGroupName])
            } catch {
                logDBError(error)
            }
        }
        }
        queue.close()
    }

    @objc(createPinnedTableGroupWithHostName:databaseName:groupName:)
    func createPinnedTableGroup(hostName: String, databaseName: String, groupName: String) {
        let normalizedGroupName = PinnedTableGroupPlanner.normalizedGroupName(groupName)
        guard normalizedGroupName.isNotEmpty, pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[normalizedGroupName] == nil else { return }
        addGroupToPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, groupName: normalizedGroupName)
        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                try db.executeUpdate("INSERT INTO PinnedTableGroups (hostName, databaseName, groupName) VALUES (?, ?, ?)", values: [hostName, databaseName, normalizedGroupName])
            } catch {
                logDBError(error)
            }
        }
        queue.close()
    }

    @objc(renamePinnedTableGroupWithHostName:databaseName:groupName:toGroupName:)
    func renamePinnedTableGroup(hostName: String, databaseName: String, groupName: String, toGroupName: String) {
        let normalizedGroupName = PinnedTableGroupPlanner.normalizedGroupName(groupName)
        let normalizedNewGroupName = PinnedTableGroupPlanner.normalizedGroupName(toGroupName)
        guard normalizedGroupName.isNotEmpty,
              normalizedNewGroupName.isNotEmpty,
              normalizedGroupName != normalizedNewGroupName,
              pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[normalizedGroupName] != nil,
              pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[normalizedNewGroupName] == nil else { return }

        let groupTables = pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[normalizedGroupName] ?? []
        let isCollapsed = isPinnedTableGroupCollapsed(hostName: hostName, databaseName: databaseName, groupName: normalizedGroupName)
        pinnedTablesDatabaseDictionary[hostName]?[databaseName]?.removeValue(forKey: normalizedGroupName)
        pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[normalizedNewGroupName] = groupTables
        setPinnedTableGroupCollapsedInMemory(hostName: hostName, databaseName: databaseName, groupName: normalizedGroupName, isCollapsed: false)
        setPinnedTableGroupCollapsedInMemory(hostName: hostName, databaseName: databaseName, groupName: normalizedNewGroupName, isCollapsed: isCollapsed)

        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                try db.executeUpdate("UPDATE PinnedTableGroups SET groupName=? WHERE hostName=? AND databaseName=? AND groupName=?", values: [normalizedNewGroupName, hostName, databaseName, normalizedGroupName])
                try db.executeUpdate("UPDATE PinnedTables SET groupName=? WHERE hostName=? AND databaseName=? AND groupName=?", values: [normalizedNewGroupName, hostName, databaseName, normalizedGroupName])
            } catch {
                logDBError(error)
            }
        }
        queue.close()
    }

    /// Deleting a group preserves its tables by returning them to the global pinned section.
    @objc(deletePinnedTableGroupWithHostName:databaseName:groupName:)
    func deletePinnedTableGroup(hostName: String, databaseName: String, groupName: String) {
        let normalizedGroupName = PinnedTableGroupPlanner.normalizedGroupName(groupName)
        guard normalizedGroupName.isNotEmpty, let groupTables = pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[normalizedGroupName] else { return }
        for tableName in groupTables {
            pinTable(hostName: hostName, databaseName: databaseName, tableToPin: tableName, groupName: "")
        }
        pinnedTablesDatabaseDictionary[hostName]?[databaseName]?.removeValue(forKey: normalizedGroupName)
        setPinnedTableGroupCollapsedInMemory(hostName: hostName, databaseName: databaseName, groupName: normalizedGroupName, isCollapsed: false)
        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                try db.executeUpdate("DELETE FROM PinnedTableGroups WHERE hostName=? AND databaseName=? AND groupName=?", values: [hostName, databaseName, normalizedGroupName])
            } catch {
                logDBError(error)
            }
        }
        queue.close()
    }

    @objc(isPinnedTableGroupCollapsedWithHostName:databaseName:groupName:)
    func isPinnedTableGroupCollapsed(hostName: String, databaseName: String, groupName: String) -> Bool {
        let normalizedGroupName = PinnedTableGroupPlanner.normalizedGroupName(groupName)
        return collapsedPinnedTableGroups[hostName]?[databaseName]?.contains(normalizedGroupName) ?? false
    }

    @objc(setPinnedTableGroupCollapsedWithHostName:databaseName:groupName:isCollapsed:)
    func setPinnedTableGroupCollapsed(hostName: String, databaseName: String, groupName: String, isCollapsed: Bool) {
        let normalizedGroupName = PinnedTableGroupPlanner.normalizedGroupName(groupName)
        guard normalizedGroupName.isNotEmpty,
              pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[normalizedGroupName] != nil else { return }
        setPinnedTableGroupCollapsedInMemory(hostName: hostName, databaseName: databaseName, groupName: normalizedGroupName, isCollapsed: isCollapsed)
        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                try db.executeUpdate("UPDATE PinnedTableGroups SET isCollapsed=? WHERE hostName=? AND databaseName=? AND groupName=?", values: [isCollapsed, hostName, databaseName, normalizedGroupName])
            } catch {
                logDBError(error)
            }
        }
        queue.close()
    }

    /// Migrates host-scoped pinned tables to a connection-scoped key once per host+connection+database tuple.
    /// - Parameters:
    ///   - legacyHostName: Legacy key used by older versions (host only, can be empty for socket connections).
    ///   - connectionIdentifier: New key based on connectionID.
    ///   - databaseName: Database scope for pinned tables.
    @objc(migratePinnedTablesFromLegacyHost:toConnectionIdentifier:databaseName:)
    func migratePinnedTablesFromLegacyHost(_ legacyHostName: String, toConnectionIdentifier connectionIdentifier: String, databaseName: String) {
        let trimmedLegacyHostName = legacyHostName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConnectionIdentifier = connectionIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDatabaseName = databaseName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let migrationToken = PinnedTableMigrationPlanner.migrationToken(
                legacyHostName: trimmedLegacyHostName,
                connectionIdentifier: trimmedConnectionIdentifier,
                databaseName: trimmedDatabaseName
        ) else {
            return
        }

        guard migratedLegacyPinnedTableTokens.contains(migrationToken) == false else {
            return
        }

        let legacyPinnedTables = getPinnedTables(hostName: trimmedLegacyHostName, databaseName: trimmedDatabaseName)
        let existingPinnedTables = getPinnedTables(hostName: trimmedConnectionIdentifier, databaseName: trimmedDatabaseName)
        let tablesToMigrate = PinnedTableMigrationPlanner.tablesToMigrate(legacyPinnedTables: legacyPinnedTables, existingPinnedTables: existingPinnedTables)

        if tablesToMigrate.isNotEmpty {
            Log.info("Migrating pinned tables from legacy host key '\(trimmedLegacyHostName)' to connection key '\(trimmedConnectionIdentifier)' for database '\(trimmedDatabaseName)'")
        }

        for tableName in tablesToMigrate {
            pinTable(hostName: trimmedConnectionIdentifier, databaseName: trimmedDatabaseName, tableToPin: tableName)
        }

        markLegacyPinnedTableMigrationComplete(migrationToken: migrationToken)
    }
    

    @objc func unpinTable(hostName: String, databaseName: String, tableToUnpin: String) {
        if groupNameForPinnedTable(hostName: hostName, databaseName: databaseName, tableName: tableToUnpin) != nil {
            removeFromPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, tableToUnpin: tableToUnpin)
            queue.inDatabase { db in
                db.traceExecution = traceExecution
                do {
                    try db.executeUpdate("DELETE FROM PinnedTables where hostName=? and databaseName=? and pinnedTableName=?",
                            values: [hostName, databaseName, tableToUnpin])
                } catch {
                    logDBError(error)
                }
            }
            queue.close()
        }
    }
    
    
    @objc(groupNameForPinnedTableWithHostName:databaseName:tableName:)
    func groupNameForPinnedTable(hostName: String, databaseName: String, tableName: String) -> String? {
        return pinnedTablesDatabaseDictionary[hostName]?[databaseName]?.first(where: { $0.value.contains(tableName) })?.key
    }

    private func addGroupToPinnedTablesDatabaseDictionary(hostName: String, databaseName: String, groupName: String) {
        if pinnedTablesDatabaseDictionary[hostName] == nil {
            pinnedTablesDatabaseDictionary[hostName] = [:]
        }
        if pinnedTablesDatabaseDictionary[hostName]?[databaseName] == nil {
            pinnedTablesDatabaseDictionary[hostName]?[databaseName] = [:]
        }
        if pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[groupName] == nil {
            pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[groupName] = []
        }
    }

    private func addToPinnedTablesDatabaseDictionary(hostName: String, databaseName: String, tableToPin: String, groupName: String) {
        addGroupToPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, groupName: groupName)
        pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[groupName]?.append(tableToPin)
    }

    private func removeFromPinnedTablesDatabaseDictionary(hostName: String, databaseName: String, tableToUnpin: String) {
        guard let groupName = groupNameForPinnedTable(hostName: hostName, databaseName: databaseName, tableName: tableToUnpin) else { return }
        pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[groupName]?.removeAll { $0 == tableToUnpin }
    }

    private func setPinnedTableGroupCollapsedInMemory(hostName: String, databaseName: String, groupName: String, isCollapsed: Bool) {
        guard groupName.isNotEmpty else { return }
        if collapsedPinnedTableGroups[hostName] == nil {
            collapsedPinnedTableGroups[hostName] = [:]
        }
        if collapsedPinnedTableGroups[hostName]?[databaseName] == nil {
            collapsedPinnedTableGroups[hostName]?[databaseName] = []
        }
        if isCollapsed {
            collapsedPinnedTableGroups[hostName]?[databaseName]?.insert(groupName)
        } else {
            collapsedPinnedTableGroups[hostName]?[databaseName]?.remove(groupName)
        }
    }

    private func markLegacyPinnedTableMigrationComplete(migrationToken: String) {
        migratedLegacyPinnedTableTokens.insert(migrationToken)
        prefs.set(migratedLegacyPinnedTableTokens.sorted(), forKey: SPMigratedPinnedTablesToConnectionIDs)
    }
    
    
    /// Handles db fails
    /// - Parameters:
    ///   - error: the thrown Error
    /// - Returns: nothing, should crash
    private func failed(error: Error) {
        assert(0 != 0, "Migration failed: \(error.localizedDescription)")
    }

    /// Logs db errors
    /// - Parameters:
    ///   - error: the thrown Error
    /// - Returns: nothing
    private func logDBError(_ error: Error) {
        Log.error("Query failed: \(error.localizedDescription)")
    }


}
