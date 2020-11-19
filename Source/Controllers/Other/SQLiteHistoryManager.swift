//
//  SQLiteHistoryManager.swift
//  Sequel Ace
//
//  Created by James on 18/11/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation
import os.log
import Firebase

typealias SASchemaBuilder = (_ db: FMDatabase, _ schemaVersion: Int) -> Void

@objc final class SQLiteHistoryManager: NSObject {
    @objc static let sharedInstance = SQLiteHistoryManager()

    @objc public var migratedPrefsToDB: Bool
    @objc public var queryHist: [Int64: String] = [:]
    @objc public var queue: FMDatabaseQueue
    private var traceExecution: Bool
    private let sqlitePath: String
    private var dbSizeHumanReadable: String = ""
    private var dbSize: Double = 0
    private let prefs: UserDefaults = UserDefaults.standard
    private let log: OSLog

    private var newSchemaVersion: Int32 = 0

    override private init() {
        log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "database")

        migratedPrefsToDB = prefs.bool(forKey: SPMigratedQueriesFromPrefs)
        traceExecution = prefs.bool(forKey: SPTraceSQLiteExecutions)

        var tmpPath: String = ""
        // error handle
        do {
            tmpPath = try FileManager.default.applicationSupportDirectory(forSubDirectory: SPDataSupportFolder)
        } catch {
            os_log("Could not get path to applicationSupportDirectory. Error: %@", log: self.log, type: .error, error as CVarArg)
            Crashlytics.crashlytics().log("Could not get path to applicationSupportDirectory. Error: \(error.localizedDescription)")
            migratedPrefsToDB = false
            prefs.set(false, forKey: SPMigratedQueriesFromPrefs)
            sqlitePath = ""
            queue = FMDatabaseQueue(path: sqlitePath)!
            super.init()
            return
        }

        sqlitePath = tmpPath + "/" + "queryHistory.db"

        if !FileManager.default.fileExists(atPath: sqlitePath) {
            os_log("db doesn't exist, they can't have migrated", log: log, type: .info)
            migratedPrefsToDB = false
            prefs.set(false, forKey: SPMigratedQueriesFromPrefs)
        }

        // this creates the db file if it doesn't exist...
        // aborts here though if queue is nil?
        queue = FMDatabaseQueue(path: sqlitePath)!

        os_log("sqlitePath = %@", log: log, type: .info, sqlitePath)
        let str = "Is SQLite compiled with it's thread safe options turned on? : " + String(FMDatabase.isSQLiteThreadSafe())
        os_log("%@", log: log, type: .info, str)
        os_log("sqliteLibVersion = %@", log: log, type: .info, FMDatabase.sqliteLibVersion())

        super.init()

        setupQueryHistoryDatabase()

        if migratedPrefsToDB == false {
            migrateQueriesFromPrefs()
        } else {
            loadQueryHistory()
        }

        getDBsize()
    }

    /// creates the database schema
    /// can also be used to alter the schema
    private func setupQueryHistoryDatabase() {
        // this block creates the database, if needed
        // can also be used to modify schema
        let schemaBlock: SASchemaBuilder = { db, schemaVersion in

            db.beginTransaction()

            if schemaVersion < 1 {
                os_log("schemaVersion < 1, creating database", log: self.log, type: .info)

                let createTableSQL = "CREATE TABLE QueryHistory ("
                    + "    id           INTEGER PRIMARY KEY,"
                    + "    query        TEXT NOT NULL,"
                    + "    createdTime  REAL NOT NULL,"
                    + "    modifiedTime REAL)"

                do {
                    try db.executeUpdate(createTableSQL, values: nil)
                    try db.executeUpdate("CREATE UNIQUE INDEX IF NOT EXISTS query_idx ON QueryHistory (query)", values: nil)
                } catch {
                    db.rollback()
                    self.failed(error)
                }

                self.newSchemaVersion = Int32(schemaVersion + 1)

                os_log("database created successfully", log: self.log, type: .info)
            } else {
                os_log("schemaVersion >= 1, not creating database", log: self.log, type: .info)
            }

            // If you wanted to change the schema in a later app version, you'd add something like this here:
            /*
             if schemaVersion < 3 {
             do {
                try db.executeUpdate("ALTER TABLE QueryHistory ADD COLUMN lastModified INTEGER NULL", values: nil)
             }
             self.newSchemaVersion = Int32(schemaVersion + 1)
              }
              */

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
                    os_log("startingSchemaVersion = %d", log: self.log, type: .debug, startingSchemaVersion)
                }
                rs.close()

                schemaBlock(db, Int(startingSchemaVersion))

                if newSchemaVersion != startingSchemaVersion, newSchemaVersion > 0 {
                    let query = "PRAGMA user_version = " + String(newSchemaVersion)
                    os_log("query: %@", log: self.log, type: .debug, query)
                    try db.executeUpdate(query, values: nil)
                } else {
                    os_log("db schema did not need an update", log: self.log, type: .info)
                }
            } catch {
                Crashlytics.crashlytics().log("Something went wrong: \(error.localizedDescription)")
                os_log("Something went wrong. Error: %@", log: self.log, type: .error, error as CVarArg)
            }
        }
    }

    /// Loads the query history from the SQLite database.
    private func loadQueryHistory() {
        os_log("loading Query History", log: log, type: .debug)

        queue.inDatabase { db in
            do {
                db.traceExecution = traceExecution
                let rs = try db.executeQuery("SELECT id, query FROM QueryHistory order by createdTime", values: nil)

                while rs.next() {
                    queryHist[rs.longLongInt(forColumn: "id")] = rs.string(forColumn: "query")
                }
                rs.close()
            } catch {
                logDBError(error)
            }
        }
        queue.close()
    }

    /// Reloads the query history from the SQLite database.
    private func reloadQueryHistory() {
        os_log("reloading Query History", log: log, type: .debug)
        queryHist.removeAll()
        loadQueryHistory()
    }

    /// Gets the size of the SQLite database.
    private func getDBsize() {
        os_log("getDBsize", log: log, type: .debug)

        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                let rs = try db.executeQuery("SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()", values: nil)

                while rs.next() {
                    dbSize = rs.double(forColumn: "size")
                    dbSizeHumanReadable = ByteCountFormatter.string(fromByteCount: Int64(dbSize), countStyle: .file)
                }
                rs.close()
            } catch {
                logDBError(error)
            }
        }
        queue.close()
        os_log("JIMMY db size = %@", log: log, type: .debug, NSNumber(value: dbSize))
        os_log("JIMMY db size2 = %@", log: log, type: .debug, dbSizeHumanReadable)
    }

    /// Migrates existing query history in the prefs plist to the SQLite db.
    private func migrateQueriesFromPrefs() {
        guard prefs.object(forKey: SPQueryHistory) != nil  else {
            os_log("no query history?", log: log, type: .error)
            migratedPrefsToDB = false
            prefs.set(false, forKey: SPMigratedQueriesFromPrefs)
            return
        }

        os_log("migrateQueriesFromPrefs", log: log, type: .debug)

        let queryHistoryArray = prefs.stringArray(forKey: SPQueryHistory) ?? [String]()

        for query in queryHistoryArray where !query.isEmpty {
            os_log("query: %@", log: log, type: .debug, query)

            let newKeyValue = primaryKeyValueForNewRow

            queue.inDatabase { db in
                db.traceExecution = traceExecution
                do {
                    try db.executeUpdate("INSERT OR IGNORE INTO QueryHistory (id, query, createdTime) VALUES (?, ?, ?)",
                                         values: [newKeyValue, query, Date()])
                } catch {
                    logDBError(error)
                }
                queryHist[newKeyValue] = query
            }
        }
        // JCS note: at the moment I'm not deleting the queryHistory key from prefs
        // in case something goes horribly wrong.
        os_log("migrated prefs query hist to db", log: log, type: .info)
        migratedPrefsToDB = true
        prefs.set(true, forKey: SPMigratedQueriesFromPrefs)

    }

    /// Updates the history.
    /// - Parameters:
    ///   - newHist: Array of Strings - the Strings being the new history to update
    /// - Returns: Nothing
    @objc func updateQueryHistory(newHist: [String]) {
        os_log("updateQueryHistory", log: log, type: .debug)

        for query in newHist where !query.isEmpty {
            let idForExistingRow = idForQueryAlreadyInDB(query: query)

            // not sure we need this
            // if it's already in the db, do we need to know the modified time?
            // could just skip
            if idForExistingRow > 0 {
                queue.inDatabase { db in
                    db.traceExecution = traceExecution
                    do {
                        try db.executeUpdate("UPDATE QueryHistory set modifiedTime = ? where id = ?", values: [Date(), idForExistingRow])
                    } catch {
                        logDBError(error)
                    }
                }
            } else {
                // if this is not unique then it's going to break
                // we could check, but max 100 items ... probability of clash is low.
                let newKeyValue = primaryKeyValueForNewRow

                queue.inDatabase { db in
                    db.traceExecution = traceExecution
                    do {
                        try db.executeUpdate("INSERT OR IGNORE INTO QueryHistory (id, query, createdTime) VALUES (?, ?, ?)",
                                             values: [newKeyValue, query, Date()])
                    } catch {
                        logDBError(error)
                    }
                }
                queryHist[newKeyValue] = query
            }

        }
        getDBsize()
        queue.close()
    }

    /// Deletes all query history from the db
    @objc func deleteQueryHistory() {
        os_log("deleteQueryHistory", log: log, type: .debug)
        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                try db.executeUpdate("DELETE FROM QueryHistory", values: nil)
            } catch {
                logDBError(error)
            }
        }

        queryHist.removeAll()
        execSQLiteVacuum()
        getDBsize()
        queue.close()
    }

    /// Executes the vacuum command on the db
    /// The VACUUM command rebuilds the database file, repacking it into a minimal amount of disk space
	@objc func execSQLiteVacuum() {
        os_log("execSQLiteVacuum", log: log, type: .debug)

        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                try db.executeUpdate("vacuum", values: nil)
            } catch {
                logDBError(error)
            }
        }
        queue.close()
    }

    /// Looks up an ID for a query .. probably not fast....
    /// - Parameters:
    ///   - query: String - the query to search for
    /// - Returns: Int64 - the ID of the row
    private func idForQueryAlreadyInDB(query: String) -> Int64 {
        var idForExistingRow: Int64 = 0

        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                let rs = try db.executeQuery("SELECT id FROM QueryHistory where query = ?", values: [query])
                while rs.next() {
                    idForExistingRow = rs.longLongInt(forColumn: "id")
                }
                rs.close()
            } catch {
                logDBError(error)
            }
        }
        queue.close()

        return idForExistingRow
    }

    /// Handles db fails
    /// - Parameters:
	///   - error: the thrown Error
    /// - Returns: nothing, should crash
    func failed(_ error: Error) {
        Crashlytics.crashlytics().log("Migration failed: \(error.localizedDescription)")
        assert(0 != 0, "Migration failed: \(error.localizedDescription)")
    }

    /// Logs db errors
    /// - Parameters:
    ///   - error: the thrown Error
    /// - Returns: nothing
    func logDBError(_ error: Error) {
        Crashlytics.crashlytics().log("Query failed: \(error.localizedDescription)")
        os_log("Query failed: %@", log: log, type: .error, error.localizedDescription)
    }

    /// Creates a new random Int64 ID
    /// - Returns: Int64 - new ID for the row
    private var primaryKeyValueForNewRow : Int64 {
        return Int64.random(in: 0 ... 1_000_000_000_000_000_000)
    }
}
