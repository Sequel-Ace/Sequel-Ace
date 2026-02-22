//
// Created by Shashwat Chaudhary on 20/10/21.
// Copyright (c) 2021 Sequel-Ace. All rights reserved.
//

import AppCenterAnalytics
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
    @objc private var pinnedTablesDatabaseDictionary: [String: [String: [String]]] = [:]

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
                let rs = try db.executeQuery("SELECT hostName, databaseName, pinnedTableName FROM PinnedTables order by id desc", values: nil)

                while rs.next() {
                    let hostName = rs.string(forColumn: "hostname")!
                    let databaseName = rs.string(forColumn: "databaseName")!
                    let pinnedTableName = rs.string(forColumn: "pinnedTableName")!
                    addToPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, tableToPin: pinnedTableName)
                }
                rs.close()
            } catch {
                logDBError(error)
            }
        }
        queue.close()
    }

    @objc func getPinnedTables(hostName: String, databaseName: String) -> [String] {
        return pinnedTablesDatabaseDictionary[hostName]?[databaseName] ?? []
    }

    @objc func pinTable(hostName: String, databaseName: String, tableToPin: String) {
        
        if let pinnedTables = pinnedTablesDatabaseDictionary[hostName]?[databaseName], pinnedTables.contains(tableToPin) {
            return
        }
        addToPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, tableToPin: tableToPin)
        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                try db.executeUpdate("INSERT INTO PinnedTables (hostName, databaseName, pinnedTableName) VALUES (?, ?, ?)",
                        values: [hostName, databaseName, tableToPin])
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
        if let pinnedTables = pinnedTablesDatabaseDictionary[hostName]?[databaseName], pinnedTables.contains(tableToUnpin) {
            pinnedTablesDatabaseDictionary[hostName]?[databaseName]?.removeAll(where: { $0 == tableToUnpin })
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
    
    
    private func addToPinnedTablesDatabaseDictionary(hostName: String, databaseName: String, tableToPin: String) {
        if pinnedTablesDatabaseDictionary[hostName] == nil {
            pinnedTablesDatabaseDictionary[hostName] = [:];
        }
        if pinnedTablesDatabaseDictionary[hostName]?[databaseName] == nil {
            pinnedTablesDatabaseDictionary[hostName]?[databaseName] = []
        }
        pinnedTablesDatabaseDictionary[hostName]?[databaseName]?.append(tableToPin)
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

        if prefs.bool(forKey: SPSaveApplicationUsageAnalytics) {
            DispatchQueue.background(background: {
                Analytics.trackEvent("error", withProperties: ["dbError": error.localizedDescription, "sqliteLibVersion": FMDatabase.sqliteLibVersion()])
            })
        }
    }


}
