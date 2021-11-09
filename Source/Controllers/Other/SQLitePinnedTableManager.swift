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
    private let Log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "queryDatabase")
    private let prefs: UserDefaults = UserDefaults.standard
    private var traceExecution: Bool
    private var newSchemaVersion: Int32 = 0
    @objc private var pinnedTablesDatabaseDictionary: [String: [String: [String]]] = [:]

    override private init() {
        traceExecution = prefs.bool(forKey: SPTraceSQLiteExecutions)

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
                        + "    pinnedTableName      TEXT NOT NULL)"

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
                    addTopinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, tableToPin: pinnedTableName)
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
        addTopinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, tableToPin: tableToPin)
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
    

    @objc func unpinTable(hostName: String, databaseName: String, tableToUnpin: String) {
        if pinnedTablesDatabaseDictionary[hostName]?[databaseName] == nil {
            return
        }
        if !pinnedTablesDatabaseDictionary[hostName]![databaseName]!.contains(tableToUnpin) {
            return
        }
        let index = pinnedTablesDatabaseDictionary[hostName]![databaseName]!.firstIndex(of: tableToUnpin)!
        pinnedTablesDatabaseDictionary[hostName]![databaseName]!.remove(at: index)

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
    
    
    private func addToPinnedTablesDatabaseDictionary(hostName: String, databaseName: String, tableToPin: String) {
        if pinnedTablesDatabaseDictionary[hostName] == nil {
            pinnedTablesDatabaseDictionary[hostName] = [:];
        }
        if pinnedTablesDatabaseDictionary[hostName]?[databaseName] == nil {
            pinnedTablesDatabaseDictionary[hostName]?[databaseName] = []
        }
        pinnedTablesDatabaseDictionary[hostName]?[databaseName]?.append(tableToPin)
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

        DispatchQueue.background(background: {
            Analytics.trackEvent("error", withProperties: ["dbError": error.localizedDescription, "sqliteLibVersion": FMDatabase.sqliteLibVersion()])
        })
    }


}
