//
//  SQLiteHistoryManager.swift
//  Sequel Ace
//
//  Created by James on 18/11/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Firebase
import Foundation
import os.log
import FMDB

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
	log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "queryDatabase")

        migratedPrefsToDB = prefs.bool(forKey: SPMigratedQueriesFromPrefs)
        traceExecution = prefs.bool(forKey: SPTraceSQLiteExecutions)
        var tmpPath: String = ""
        // error handle
        do {
            tmpPath = try FileManager.default.applicationSupportDirectory(forSubDirectory: SPDataSupportFolder)
        } catch {
            os_log("Could not get path to applicationSupportDirectory. Error: %@", log: log, type: .error, error as CVarArg)
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
                    + "    query        TEXT NOT NULL,"
                    + "    createdTime  REAL NOT NULL)"

                do {
                    try db.executeUpdate(createTableSQL, values: nil)
                    try db.executeUpdate("CREATE UNIQUE INDEX IF NOT EXISTS query_idx ON QueryHistory (query)", values: nil)
                } catch {
                    db.rollback()
                    self.failed(error: error)
                }

                self.newSchemaVersion = Int32(schemaVersion + 1)
                os_log("self.newSchemaVersion = %d", log: self.log, type: .debug, self.newSchemaVersion)

                os_log("database created successfully", log: self.log, type: .info)
            } else {
                os_log("schemaVersion >= 1, not creating database", log: self.log, type: .info)
                // need to do this here in case, a user has the first version of the db
                self.newSchemaVersion = Int32(schemaVersion)
            }

            /*

             JCS - we want to add an auto_inc primary key called 'id'
                 - you can't so that with ALTER TABLE in sqlite
                 - so need to rename, re-create, copy data, drop

             ALTER TABLE QueryHistory RENAME TO QueryHistory_Old;

             CREATE TABLE IF NOT EXISTS QueryHistory (
               "query" text NOT NULL,
               createdTime real NOT NULL,
               id integer PRIMARY KEY AUTOINCREMENT NOT NULL
             );

             INSERT INTO QueryHistory(query, createdTime) SELECT query, createdTime FROM QueryHistory_Old;

             DROP TABLE QueryHistory_Old

             CREATE UNIQUE INDEX query_idx ON QueryHistory ("query");

             */

            if self.newSchemaVersion < 2 {
                os_log("schemaVersion = %d", log: self.log, type: .debug, self.newSchemaVersion)
                os_log("schemaVersion < 2, altering database", log: self.log, type: .info)

                do {
                    try db.executeUpdate("ALTER TABLE QueryHistory RENAME TO QueryHistory_Old", values: nil)

                    let createTableSQL = "CREATE TABLE QueryHistory ("
                        + "    id integer PRIMARY KEY AUTOINCREMENT NOT NULL,"
                        + "    query        TEXT NOT NULL,"
                        + "    createdTime  REAL NOT NULL)"

                    try db.executeUpdate(createTableSQL, values: nil)
                    try db.executeUpdate("INSERT INTO QueryHistory(query, createdTime) SELECT query, createdTime FROM QueryHistory_Old", values: nil)
                    try db.executeUpdate("DROP TABLE QueryHistory_Old", values: nil)
                    try db.executeUpdate("CREATE UNIQUE INDEX IF NOT EXISTS query_idx ON QueryHistory (query)", values: nil)
                }
                catch {
                    db.rollback()
                    self.failed(error: error)
                }
                self.newSchemaVersion = self.newSchemaVersion + 1
                os_log("newSchemaVersion = %d", log: self.log, type: .debug, self.newSchemaVersion)

            }
            else {
               os_log("schemaVersion >= 2, not altering database", log: self.log, type: .info)
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
        os_log("loading Query History. SPCustomQueryMaxHistoryItems: %i", log: log, type: .debug, prefs.integer(forKey: SPCustomQueryMaxHistoryItems))
        Crashlytics.crashlytics().log("loading Query History. SPCustomQueryMaxHistoryItems: \(prefs.integer(forKey: SPCustomQueryMaxHistoryItems))")
        queue.inDatabase { db in
            do {
                db.traceExecution = traceExecution
                // select by id desc to get latest first, limit to max pref
                let rs = try db.executeQuery("SELECT id, query FROM QueryHistory order by id desc LIMIT (?)", values: [prefs.integer(forKey: SPCustomQueryMaxHistoryItems)])

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
        Crashlytics.crashlytics().log("reloading Query History")
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
    }

    /// Migrates existing query history in the prefs plist to the SQLite db.
    private func migrateQueriesFromPrefs() {
        guard prefs.object(forKey: SPQueryHistory) != nil else {
            os_log("no query history?", log: log, type: .error)
            migratedPrefsToDB = false
            prefs.set(false, forKey: SPMigratedQueriesFromPrefs)
            return
        }

        os_log("migrateQueriesFromPrefs", log: log, type: .debug)
        Crashlytics.crashlytics().log("migrateQueriesFromPrefs")

        let queryHistoryArray = prefs.stringArray(forKey: SPQueryHistory) ?? [String]()

        // we want to reverse the array from prefs
        // prefs is stored by created date asc
        // we want to insert in the opposite order
        // so that drop down displays by latest created
        for query in queryHistoryArray.reversed() where query.isNotEmpty {
            os_log("query: [%@]", log: log, type: .debug, query)

            let newDate = Date()

            os_log("date: %@", log: log, type: .debug, newDate as CVarArg)

            queue.inDatabase { db in
                db.traceExecution = traceExecution
                do {
                    try db.executeUpdate("INSERT OR IGNORE INTO QueryHistory (query, createdTime) VALUES (?, ?)",
                                         values: [query.trimmedString, newDate])
                } catch {
                    logDBError(error)
                }
                queryHist[db.lastInsertRowId] = query
            }
        }
        // JCS note: at the moment I'm not deleting the queryHistory key from prefs
        // in case something goes horribly wrong.
        os_log("migrated prefs query hist to db", log: log, type: .info)
        migratedPrefsToDB = true
        prefs.set(true, forKey: SPMigratedQueriesFromPrefs)
        reloadQueryHistory()
    }

    /// Updates the history.
    /// - Parameters:
    ///   - newHist: Array of Strings - the Strings being the new history to update
    /// - Returns: Nothing
    @objc func updateQueryHistory(newHist: [String]) {
        os_log("updateQueryHistory", log: log, type: .debug)

        // dont delete any history, keep it all?
        for query in newHist where query.isNotEmpty {
            let newDate = Date()

            queue.inDatabase { db in
                db.traceExecution = traceExecution
                do {
                    try db.executeUpdate("INSERT OR IGNORE INTO QueryHistory (query, createdTime) VALUES (?, ?)",
                                         values: [query.trimmedString, newDate])
                } catch {
                    logDBError(error)
                }

                queryHist[db.lastInsertRowId] = query
            }
        }
        getDBsize()
        queue.close()
    }

    /// Deletes all query history from the db
    @objc func deleteQueryHistory() {
        os_log("deleteQueryHistory", log: log, type: .debug)
        Crashlytics.crashlytics().log("deleteQueryHistory")
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
        Crashlytics.crashlytics().log("execSQLiteVacuum")
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

    /// Handles db fails
    /// - Parameters:
    ///   - error: the thrown Error
    /// - Returns: nothing, should crash
    func failed(error: Error) {
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
}
