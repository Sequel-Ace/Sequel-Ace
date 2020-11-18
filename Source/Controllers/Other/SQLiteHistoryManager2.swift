//
//  SQLiteHistoryManager.swift
//  Sequel Ace
//
//  Created by James on 18/11/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation
import os.log

typealias SASchemaBuilder = (_ db: FMDatabase, _ schemaVersion: Int) -> Void

@objc final class SQLiteHistoryManager2: NSObject {
    @objc static let sharedInstance = SQLiteHistoryManager2()

    @objc public var migratedPrefsToDB: Bool
    @objc public var queryHist: [Double: String]
    @objc public var queue: FMDatabaseQueue
    private let sqlitePath: String
    private var dbSizeHumanReadable: String
    private var dbSize: Double
    private let prefs: UserDefaults
    private let log: OSLog

    private var newSchemaVersion: Int32 = 0

    override private init() {
        log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "database")

        queryHist = [:]
        dbSize = 0
        dbSizeHumanReadable = ""
        prefs = UserDefaults.standard

        migratedPrefsToDB = prefs.bool(forKey: SPMigratedQueriesFromPrefs)

        // error handle
        let tmpPath = try! FileManager.default.applicationSupportDirectory(forSubDirectory: SPDataSupportFolder)

        sqlitePath = tmpPath + "/" + "queryHistory2.db"

        queue = FMDatabaseQueue(path: sqlitePath)!

        os_log("sqlitePath = %@", log: log, type: .info, sqlitePath)

        let str = "Is SQLite compiled with it's thread safe options turned on? : " + String(FMDatabase.isSQLiteThreadSafe())

        os_log("%@", log: log, type: .info, str)

        os_log("sqliteLibVersion = %@", log: log, type: .info, FMDatabase.sqliteLibVersion())

        super.init()

        //		os_log("primaryKeyValueForNewRow = %@", log: log, type: .info, self.primaryKeyValueForNewRow());

        setupQueryHistoryDatabase()

        if migratedPrefsToDB == false {
            migrateQueriesFromPrefs()
        } else {
            loadQueryHistory()
        }

        getDBsize()
    }

    func setupQueryHistoryDatabase() {
        var isDirectory: ObjCBool = false

        //  this doesn't work...
        if !FileManager.default.fileExists(atPath: sqlitePath, isDirectory: &isDirectory) {
            os_log("db doesn't exist, they can't have migrated", log: log, type: .info)
            migratedPrefsToDB = false
            prefs.set(false, forKey: SPMigratedQueriesFromPrefs)
        }

        // this block creates the database, if needed
        // can also be used to modify schema
        let schemaBlock: SASchemaBuilder = { db, schemaVersion in

//            db.traceExecution = true
            //			db.crashOnErrors = true

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
                } catch {
                    self.failedAt(statement: 1, db: db)
                }
                do {
                    try db.executeUpdate("CREATE UNIQUE INDEX IF NOT EXISTS query_idx ON QueryHistory (query)", values: nil)
                } catch {
                    self.failedAt(statement: 2, db: db)
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
                os_log("Something went wrong", log: self.log, type: .error)
            }
        }
    }

    func loadQueryHistory() {
        os_log("loading Query History", log: log, type: .debug)

        queue.inDatabase { db in
            do {
                let rs = try db.executeQuery("SELECT id, query FROM QueryHistory order by createdTime", values: nil)

                while rs.next() {
                    queryHist[rs.double(forColumn: "id")] = rs.string(forColumn: "query")
                    //					rs.string(forColumn: "query")
                    //					rs.double(forColumn: "id")
                }
                rs.close()
            } catch {
                logDBError(db: db)
            }
        }
    }

    func reloadQueryHistory() {
        os_log("reloading Query History", log: log, type: .debug)
        queryHist.removeAll()
        loadQueryHistory()
    }

    func getDBsize() {
        os_log("getDBsize", log: log, type: .debug)

        queue.inDatabase { db in
            do {
                let rs = try db.executeQuery("SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()", values: nil)

                while rs.next() {
                    dbSize = rs.double(forColumn: "size")
                    dbSizeHumanReadable = ByteCountFormatter.string(fromByteCount: Int64(dbSize), countStyle: .file)
                }
                rs.close()
            } catch {
                logDBError(db: db)
            }
        }

        os_log("JIMMY db size = %@", log: log, type: .debug, NSNumber(value: dbSize))
        os_log("JIMMY db size2 = %@", log: log, type: .debug, dbSizeHumanReadable)
    }

    func migrateQueriesFromPrefs() {
        if prefs.object(forKey: SPQueryHistory) != nil {
            os_log("migrateQueriesFromPrefs", log: log, type: .debug)

            //			let queryHistoryArray = Array( arrayLiteral: prefs.object(forKey: SPQueryHistory))
            let queryHistoryArray = prefs.stringArray(forKey: SPQueryHistory) ?? [String]()

            for query in queryHistoryArray {
                if query.count > 0 {
                    os_log("query: %@", log: log, type: .debug, query)

                    let newKeyValue = primaryKeyValueForNewRow()

                    queue.inDatabase { db in
                        do {
                            try db.executeUpdate("INSERT OR IGNORE INTO QueryHistory (id, query, createdTime) VALUES (?, ?, ?)", values: [newKeyValue, query, Date()])
                        } catch {
                            logDBError(db: db)
                        }

                        os_log("insert successful", log: self.log, type: .debug)
                        queryHist[Double(truncating: newKeyValue)] = query
                    }
                }
            }
            // JCS note: at the moment I'm not deleting the queryHistory key from prefs
            // in case something goes horribly wrong.
            os_log("migrated prefs query hist to db", log: log, type: .info)
            migratedPrefsToDB = true
            prefs.set(true, forKey: SPMigratedQueriesFromPrefs)
        } else {
            os_log("no query history?", log: log, type: .error)
            migratedPrefsToDB = false
            prefs.set(false, forKey: SPMigratedQueriesFromPrefs)
        }
    }

    @objc func updateQueryHistory(newHist: [String]) {
        os_log("updateQueryHistory", log: log, type: .debug)

        for query in newHist {
            if query.count > 0 {
                let idForExistingRow = idForQueryAlreadyInDB(query: query)

                if idForExistingRow > 0 {
                    queue.inDatabase { db in
                        do {
                            try db.executeUpdate("UPDATE QueryHistory set modifiedTime = ? where id = ?", values: [Date(), NSNumber(value: idForExistingRow)])
                        } catch {
                            logDBError(db: db)
                        }
                    }
                } else {
                    // if this is not unique then it's going to break
                    // we could check, but max 100 items ... probability of clash is low.
                    let newKeyValue = primaryKeyValueForNewRow()

                    queue.inDatabase { db in
                        do {
                            try db.executeUpdate("INSERT OR IGNORE INTO QueryHistory (id, query, createdTime) VALUES (?, ?, ?)", values: [newKeyValue, query, Date()])
                        } catch {
                            logDBError(db: db)
                        }
                    }
                    queryHist[Double(truncating: newKeyValue)] = query
                }
            }
        }
    }

    @objc func deleteQueryHistory() {
        os_log("deleteQueryHistory", log: log, type: .debug)
        queue.inDatabase { db in
            do {
                try db.executeUpdate("DELETE FROM QueryHistory", values: nil)
            } catch {
                logDBError(db: db)
            }
        }

        queryHist.removeAll()
        execSQLiteVacuum()
        getDBsize()
    }

    func execSQLiteVacuum() {
        os_log("execSQLiteVacuum", log: log, type: .debug)

        queue.inDatabase { db in
            do {
                try db.executeUpdate("vacuum", values: nil)
            } catch {
                logDBError(db: db)
            }
        }
    }

    func idForQueryAlreadyInDB(query: String) -> Double {
        os_log("idForQueryAlreadyInDB", log: log, type: .debug)

        var idForExistingRow: Double = 0

        queue.inDatabase { db in
            do {
                let rs = try db.executeQuery("SELECT id FROM QueryHistory where query = ?", values: [query])
                while rs.next() {
                    idForExistingRow = rs.double(forColumn: "id")
                }
                rs.close()
            } catch {
                logDBError(db: db)
            }
        }

        return idForExistingRow
    }

    func failedAt(statement: Int, db: FMDatabase) {
        let lastErrorCode = db.lastErrorCode()
        let lastErrorMessage = db.lastErrorMessage()
        db.rollback()
        assert(0 != 0, "Migration statement \(statement) failed, code \(lastErrorCode): \(lastErrorMessage)")
    }

    func logDBError(db: FMDatabase) {
        let lastErrorCode = db.lastErrorCode()
        let lastErrorMessage = db.lastErrorMessage()
        os_log("Query failed, code %@:%@", log: log, type: .error, lastErrorCode, lastErrorMessage)
    }

    func primaryKeyValueForNewRow() -> NSNumber {
        return NSNumber(value: Int64.random(in: 0 ... 1_000_000_000_000_000_000))
    }
}
