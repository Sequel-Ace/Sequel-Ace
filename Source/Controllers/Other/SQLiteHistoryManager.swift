//
//  SQLiteHistoryManager.swift
//  Sequel Ace
//
//  Created by James on 18/11/2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import AppCenterAnalytics
import Foundation
import FMDB
import OSLog

typealias SASchemaBuilder = (_ db: FMDatabase, _ schemaVersion: Int) -> Void

@objc final class SQLiteHistoryManager: NSObject {
    @objc static let sharedInstance             = SQLiteHistoryManager()
    @objc public var migratedPrefsToDB: Bool
    @objc public var showLogging: Bool          = false
    @objc public var queryHist: [Int64: String] = [:]
    @objc public var queue: FMDatabaseQueue
    private let maxSizeForCrashlyticsLog: Int   = 64000
    private var traceExecution: Bool
    private let sqlitePath: String
    private var dbSizeHumanReadable: String     = ""
    private var dbSize: Double                  = 0
    private var additionalHistArraySize: Int    = 0
    private let prefs: UserDefaults             = UserDefaults.standard
    private let Log                             = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "queryDatabase")
    private var newSchemaVersion: Int32         = 0

    override private init() {

        migratedPrefsToDB = prefs.bool(forKey: SPMigratedQueriesFromPrefs)
        traceExecution = prefs.bool(forKey: SPTraceSQLiteExecutions)
        var tmpPath: String = ""
        // error handle
        do {
            tmpPath = try FileManager.default.applicationSupportDirectory(forSubDirectory: SPDataSupportFolder)
        } catch {
            Log.error("Could not get path to applicationSupportDirectory. Error: \(error.localizedDescription)")
            migratedPrefsToDB = false
            prefs.set(false, forKey: SPMigratedQueriesFromPrefs)
            sqlitePath = ""
            queue = FMDatabaseQueue(path: sqlitePath)!
            super.init()
            return
        }

        sqlitePath = tmpPath + "/" + "queryHistory.db"

        if !FileManager.default.fileExists(atPath: sqlitePath) {
            Log.info("db doesn't exist, they can't have migrated")
            migratedPrefsToDB = false
            prefs.set(false, forKey: SPMigratedQueriesFromPrefs)
        }

        // this creates the db file if it doesn't exist...
        // aborts here though if queue is nil?
        queue = FMDatabaseQueue(path: sqlitePath)!

        Log.info("sqlitePath = \(sqlitePath)")
        Log.info("Is SQLite compiled with it's thread safe options turned on? : \(FMDatabase.isSQLiteThreadSafe())")
        Log.info("sqliteLibVersion = \(FMDatabase.sqliteLibVersion())")

        super.init()

        setupQueryHistoryDatabase()

        if migratedPrefsToDB == false {
            migrateQueriesFromPrefs()
        } else {
            loadQueryHistory()
        }

        DispatchQueue.background(background: {
            self.getDBsize()
        })
    }

    /// creates the database schema
    /// can also be used to alter the schema
    private func setupQueryHistoryDatabase() {
        // this block creates the database, if needed
        // can also be used to modify schema
        let schemaBlock: SASchemaBuilder = { [self] db, schemaVersion in

            db.beginTransaction()

            if schemaVersion < 1 {
                Log.info("schemaVersion < 1, creating database")

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

                newSchemaVersion = Int32(schemaVersion + 1)
                Log.debug("self.newSchemaVersion \(newSchemaVersion)")

                Log.info("database created successfully")
            } else {
                Log.info("schemaVersion >= 1, not creating database")
                // need to do this here in case, a user has the first version of the db
                newSchemaVersion = Int32(schemaVersion)
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

            if newSchemaVersion < 2 {
                Log.debug("schemaVersion = \(newSchemaVersion)")
                Log.info("schemaVersion < 2, altering database")

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
                newSchemaVersion = newSchemaVersion + 1
                Log.debug("schemaVersion = \(newSchemaVersion)")
            }
            else {
                Log.info("schemaVersion >= 2, not altering database")
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
                }
                else {
                    Log.info("db schema did not need an update")
                }
            } catch {
                Log.error("Something went wrong: \(error.localizedDescription)")
            }
        }
    }

    /// Loads the query history from the SQLite database.
    private func loadQueryHistory() {

        let maxHistItems = prefs.integer(forKey: SPCustomQueryMaxHistoryItems)
        Log.debug("loading Query History. SPCustomQueryMaxHistoryItems: \(maxHistItems)")
        queue.inDatabase { db in
            do {
                db.traceExecution = traceExecution
                // select by id desc to get latest first, limit to max pref
                let rs = try db.executeQuery("SELECT id, query FROM QueryHistory order by id desc LIMIT (?)", values: [maxHistItems])

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
        Log.debug("reloading Query History")
        queryHist.removeAll()
        loadQueryHistory()
    }

    /// Gets the size of the SQLite database.
    private func getDBsize() {

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
        Log.debug("dbSize = \(dbSizeHumanReadable)")
    }

    /// Migrates existing query history in the prefs plist to the SQLite db.
    private func migrateQueriesFromPrefs() {
        guard prefs.object(forKey: SPQueryHistory) != nil else {
            Log.error("no query history?")
            migratedPrefsToDB = false
            prefs.set(false, forKey: SPMigratedQueriesFromPrefs)
            return
        }

        Log.debug("migrateQueriesFromPrefs")

        let queryHistoryArray = prefs.stringArray(forKey: SPQueryHistory) ?? [String]()

        // we want to reverse the array from prefs
        // prefs is stored by created date asc
        // we want to insert in the opposite order
        // so that drop down displays by latest created
        for query in queryHistoryArray.reversed() where query.isNotEmpty {
            Log.debug("query: [\(query)]")

            let newDate = Date()

            Log.debug("date: \(query)")

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
        Log.info("migrated prefs query hist to db")
        migratedPrefsToDB = true
        prefs.set(true, forKey: SPMigratedQueriesFromPrefs)
        reloadQueryHistory()
    }

    /// Updates the history.
    /// - Parameters:
    ///   - newHist: Array of Strings - the Strings being the new history to update
    /// - Returns: Nothing
    /// - NOTE
    ///  Sometimes (when saving the entire query editor string on closing the tab)
    /// The incoming array is one line, separated by \n, and still has the trailing ';'
    /// - see SPCustomQuery.m L234: queries = [queryParser splitStringByCharacter:';'];
    /// We need to handle that scenario. See normalizeQueryHistory()
    @objc func updateQueryHistory(newHist: [String]) {
        Log.debug("updateQueryHistory")

        Log.debug("newHist passed in: [\(newHist)]")
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
        reloadQueryHistory()
    }

    /// Deletes all query history from the db
    @objc func deleteQueryHistory() {
        Log.debug("deleteQueryHistory")
        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                try db.executeUpdate("DELETE FROM QueryHistory", values: nil)
            } catch {
                logDBError(error)
            }
        }

        queryHist.removeAll()

        DispatchQueue.background(background: { [self] in
            // do something in background
            execSQLiteVacuum()
            getDBsize()
        }, completion:{
            // when background job finished, do something in main thread
            self.queue.close()
        })
    }

    /// Executes the vacuum command on the db
    /// The VACUUM command rebuilds the database file, repacking it into a minimal amount of disk space
    @objc func execSQLiteVacuum() {
        Log.debug("execSQLiteVacuum")
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
        assert(0 != 0, "Migration failed: \(error.localizedDescription)")
    }

    /// Logs db errors
    /// - Parameters:
    ///   - error: the thrown Error
    /// - Returns: nothing
    func logDBError(_ error: Error) {
        Log.error("Query failed: \(error.localizedDescription)")

        if prefs.bool(forKey: SPSaveApplicationUsageAnalytics) {
            DispatchQueue.background(background: {
                Analytics.trackEvent("error", withProperties: ["dbError":error.localizedDescription, "sqliteLibVersion" : FMDatabase.sqliteLibVersion()])
            })
        }
    }

    /// separates multiline query into individual lines.
    ///  - Parameters:
    ///   - arrayToNormalise: the array of strings/queries to normalise
    /// - Returns: the normalised array of queries
    /// For example, an array with one entry like this:
    /// "SELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT COUNT(*) FROM `HKWarningsLog`;"
    /// Should return this array:
    /// [( "SELECT * FROM `HKWarningsLog` LIMIT 1000", "SELECT COUNT(*) FROM `HKWarningsLog`")]
    @objc func normalizeQueryHistory(arrayToNormalise: [String]) -> [String] {

        Log.debug("normalizeQueryHistory")
        var normalisedQueryArray: [String] = []

        additionalHistArraySize = 0;

        let saveHistoryIndividually = prefs.bool(forKey: SPCustomQuerySaveHistoryIndividually)

        if saveHistoryIndividually == true {
            Log.debug("saveHistoryIndividually: [\(saveHistoryIndividually)]")
            for query in arrayToNormalise where query.isNotEmpty {

                if queryMightBeMultiLine(queryToCheck:query) == true {
                    Log.debug("queryMightBeMultiLine: [\(query)]")
                    normalisedQueryArray = appendToQueryHistory(arrayToAppendTo: normalisedQueryArray, queryToAppend: query)
                    continue
                }

                if query.contains("\n"){
                    Log.debug("query contains newline: [\(query)]")
                    // an array where each entry contains the value from
                    // the history query, delimited by a semi colon
                    let lines = query.separatedIntoLinesByCharset()

                    Log.debug("lines: [\(lines)]")

                    for line in lines {
                        Log.debug("line: [\(line)]")
                        normalisedQueryArray = appendToQueryHistory(arrayToAppendTo: normalisedQueryArray, queryToAppend: line)
                    }
                }
                else{
                    normalisedQueryArray = appendToQueryHistory(arrayToAppendTo: normalisedQueryArray, queryToAppend: query)
                }
            }
            Log.debug("arrayToNormalise: [\(arrayToNormalise)]")
            Log.debug("normalisedQueryArray: [\(normalisedQueryArray)]")
        }
        else{
            Log.debug("saveHistoryIndividually: [\(saveHistoryIndividually)], setting normalisedQueryArray = arrayToNormalise")

            for query in arrayToNormalise where query.isNotEmpty {

                if query == arrayToNormalise.last && query.hasSuffix(";") == false {
                    Log.debug("last and has suffix")
                    normalisedQueryArray.appendIfNotContains(query.trimmedString + ";")
                }
                else {
                    normalisedQueryArray.appendIfNotContains(query.trimmedString)
                }
            }

            Log.debug("normalisedQueryArray: [\(normalisedQueryArray)]")
        }

        // keep a rough track of array size by counting string len
        for arr in normalisedQueryArray {
            additionalHistArraySize = additionalHistArraySize + arr.count
        }

        Log.debug("additionalHistArraySize: [\(additionalHistArraySize)]")

        return normalisedQueryArray
    }

    /// Takes a guess at whether the query might be multi-line
    /// - Parameters:
    ///   - queryToCheck: the query to check
    /// - Returns: bool - if the query contains on of the keywords.
    private func queryMightBeMultiLine(queryToCheck: String) -> Bool {

        let keywordArray: [String] = ["UNION", "JOIN", "ANY", "SOME", "ALL", "IN"] // FIXME: What about IN? Might not be multiline

        for keyword in keywordArray {
            if queryToCheck.contains(keyword) {
                Log.debug("queryToCheck: [\(queryToCheck)]")
                Log.debug("contains: [\(keyword)]")
                return true
            }
        }

        return false
    }

    /// Appends to the query history array (if not already in array) and adds final semi-colon if missing.
    /// - Parameters:
    ///   - arrayToAppendTo: the array to append to
    ///   - queryToAppend: the query to append
    /// - Returns: array of queries with the new query appended.
    private func appendToQueryHistory(arrayToAppendTo: [String], queryToAppend: String) -> [String] {

        var mutableArray = arrayToAppendTo
        
        if queryToAppend.hasSuffix(";") == false {
            mutableArray.appendIfNotContains(queryToAppend.trimmedString + ";")
        }
        else{
            mutableArray.appendIfNotContains(queryToAppend.trimmedString)
        }

        return mutableArray
    }
}
