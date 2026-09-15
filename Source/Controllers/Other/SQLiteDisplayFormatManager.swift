//
//  Created by Luis Aguiniga on 2024.07.05.
//  Copyright © 2024 Sequel-Ace. All rights reserved.
//

import Foundation
import FMDB
import OSLog

/// Persists the per-column display formats in an SQLite store in the
/// application-support folder. The store is a convenience: when it cannot
/// be opened or created - the folder is not writable, the file is damaged -
/// the manager carries on without it, formats simply do not persist, and the
/// table content keeps working. It never terminates the app.
@objc final class SQLiteDisplayFormatManager: NSObject {
    typealias SchemaBuilder = (_ db: FMDatabase, _ schemaVersion: Int) throws -> Int

    private static let sqliteTableName = "ColumnDisplayOverrides"
    /// The store's file name; the app-only `sharedInstance` in
    /// SASQLiteSharedStoreLocation.swift places it in the application-support folder.
    static let dbFileName = "ColumnDisplayOverrides.db"
    static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "DisplayFormatManager")

    /// The store, or `nil` when it turned out to be unusable.
    private let queue: FMDatabaseQueue?

    /// Opens or creates the store at `databasePath`. A `nil` path, a file
    /// that cannot be opened, a schema that cannot be created or a table
    /// without the columns the manager reads leaves the manager without a
    /// store. The app uses `sharedInstance`, declared in
    /// the app-target-only SASQLiteSharedStoreLocation.swift.
    init(databasePath: String?) {
        queue = databasePath.flatMap { Self.openStore(at: $0) }
        super.init()
    }

    /// Whether formats are persisted; `false` when the store is unusable.
    var isPersistent: Bool {
        queue != nil
    }

    @objc func displayOverrideFor(hostName: String, databaseName: String, tableName: String, columnName: String) -> String? {
        guard let queue else {
            return nil
        }
        var found: String? = nil

        let sql = """
            SELECT hostName, databaseName, tableName, columnName, format
            FROM \(Self.sqliteTableName)
            WHERE  hostName=? and databaseName=? and tableName=? and columnName=?
            ORDER BY id DESC
            """
        queue.inDatabase { db in
            do {
                let rs = try db.executeQuery(sql, values: [hostName, databaseName, tableName, columnName])
                while rs.next() {
                    if let format = rs.string(forColumn: "format") {
                        found = format
                        break
                    }
                }
                rs.close()
            }
            catch {
                Self.log.error("Query '\(sql), failed with error: \(error.localizedDescription)")
            }
        }
        queue.close()

        return found
    }

    @objc func allDisplayOverridesFor(hostName: String, databaseName: String, tableName: String) -> [String:String] {
        guard let queue else {
            return [:]
        }
        var formats = [String:String]()

        let sql = """
            SELECT hostName, databaseName, tableName, columnName, format
            FROM \(Self.sqliteTableName)
            WHERE  hostName=? and databaseName=? and tableName=?
            ORDER BY id DESC
            """

        queue.inDatabase { db in
            do {
                let rs = try db.executeQuery(sql, values: [hostName, databaseName, tableName])
                while rs.next() {
                    guard let columnName = rs.string(forColumn: "columnName"), let format = rs.string(forColumn: "format") else {
                        continue
                    }
                    formats[columnName] = format
                }
                rs.close()
            }
            catch {
                Self.log.error("Query '\(sql), failed with error: \(error.localizedDescription)")
            }
        }
        queue.close()

        return formats
    }

    @objc func replaceOverrideFor(hostName: String, databaseName: String, tableName: String, colName: String, format: String) {
        guard let queue else {
            return
        }
        let toAdd = [hostName, databaseName, tableName, colName, format];

        let sql = """
            INSERT OR REPLACE INTO \(Self.sqliteTableName) (hostName, databaseName, tableName, columnName, format) VALUES (?, ?, ?, ?, ?)
            """
        queue.inDatabase { db in
            do {
                try db.executeUpdate(sql, values: toAdd)
            }
            catch {
                Self.log.error("\(error.localizedDescription)")
            }
        }
        queue.close()
    }

    /// Opens the store at `databasePath` and brings its schema up to date.
    /// Returns `nil` when the file cannot be opened or prepared - the folder
    /// does not exist, the file is not a database, the table cannot be
    /// created; the failure is logged and nothing else happens to the app.
    private static func openStore(at databasePath: String) -> FMDatabaseQueue? {
        guard let queue = FMDatabaseQueue(path: databasePath) else {
            log.error("Could not open \(databasePath). Column display formats are not persisted.")
            return nil
        }
        guard setupDatabase(in: queue) else {
            queue.close()
            return nil
        }
        return queue
    }

    private static func setupDatabase(in queue: FMDatabaseQueue) -> Bool {
        let builder: SchemaBuilder = { (db, schemaVersion: Int) in
            db.beginTransaction()
            var newSchemaVersion = schemaVersion

            if schemaVersion < 1 {
                let createTableSql = """
                    CREATE TABLE \(sqliteTableName) (
                      id            INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                      hostName      TEXT NOT NULL,
                      databaseName  TEXT NOT NULL,
                      tableName     TEXT NOT NULL,
                      columnName    TEXT NOT NULL,
                      format        TEXT NOT NULL,

                      CONSTRAINT host_db_table UNIQUE (hostName, databaseName, tableName, columnName)
                    )
                    """
                let createIndexSql = """
                    CREATE UNIQUE INDEX IF NOT EXISTS host_db_table_idx ON \(sqliteTableName) (hostName, databaseName, tableName, columnName)
                    """

                do {
                    try db.executeUpdate(createTableSql)
                    try db.executeUpdate(createIndexSql)
                }
                catch {
                    db.rollback()
                    throw error
                }

                newSchemaVersion = 1
                log.debug("self.newSchemaVersion \(newSchemaVersion)")
                log.info("Creating ColumnDisplayFormats Version 1 was successful!")
            }

            db.commit()
            return newSchemaVersion
        }

        var usable = false
        queue.inDatabase { db in
            do {
                let initialVersion = try loadCurrentSchemaVersion(db)
                let finalVersion = try builder(db, initialVersion)
                try finalizeSchemaVersion(db, initialVersion, finalVersion)
                try verifyTable(db)
                usable = true
            }
            catch {
                log.error("Preparing \(dbFileName) failed: \(error.localizedDescription). Column display formats are not persisted.")
            }
        }
        queue.close()
        return usable
    }

    private static func loadCurrentSchemaVersion(_ db: FMDatabase) throws -> Int {
        var version = 0
        let rs = try db.executeQuery("PRAGMA user_version")
        if rs.next() {
            version = rs.long(forColumnIndex: 0)
            log.debug("startingSchemaVersion = \(version)")
        }
        rs.close()

        return version
    }

    /// Succeeds only when the table exists with every column the manager
    /// reads. A file whose schema version says the table was created, but
    /// whose table is missing or different, is not used: its formats could
    /// not be read, while writes might still land in it.
    private static func verifyTable(_ db: FMDatabase) throws {
        let rs = try db.executeQuery("SELECT id, hostName, databaseName, tableName, columnName, format FROM \(sqliteTableName) LIMIT 0")
        rs.close()
    }

    private static func finalizeSchemaVersion(_ db: FMDatabase, _ initialVersion: Int, _ finalVersion: Int) throws {
        guard finalVersion != initialVersion, finalVersion > 0 else {
            return
        }

        let query = "PRAGMA user_version = \(finalVersion)"
        log.debug("query = \(query)")
        try db.executeUpdate(query)
    }
}


fileprivate extension FMDatabase {
    func executeQuery(_ sql: String) throws -> FMResultSet {
        try self.executeQuery(sql, values: nil)
    }

    func executeUpdate(_ sql: String) throws {
        try self.executeUpdate(sql, values: nil)
    }
}
