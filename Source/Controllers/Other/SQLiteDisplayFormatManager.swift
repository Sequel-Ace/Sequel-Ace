//
//  Created by Luis Aguiniga on 2024.07.05.
//  Copyright © 2024 Sequel-Ace. All rights reserved.
//

import Foundation
import FMDB
import OSLog

@objc final class SQLiteDisplayFormatManager: NSObject {
    typealias SchemaBuilder = (_ db: FMDatabase, _ schemaVersion: Int) throws -> Int

    @objc static let sharedInstance = SQLiteDisplayFormatManager()

    private let sqliteTableName = "ColumnDisplayOverrides"
    private let dbFileName = "ColumnDisplayOverrides.db"
    private var queue: FMDatabaseQueue
    private let LOG = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "DisplayFormatManager")

    override init() {
        do {
            let appSupportPath = try FileManager.default.applicationSupportDirectory(forSubDirectory: SPDataSupportFolder)
            let sqLitePath = "\(appSupportPath)/\(dbFileName)"
            queue = FMDatabaseQueue(path: sqLitePath)!
            super.init()
            setupDatabase()
        }
        catch {
            LOG.error("Error initializing SQLite DB: \(error.localizedDescription)")
            queue = FMDatabaseQueue(path: " ")!
            super.init()
        }
    }

    @objc func displayOverrideFor(hostName: String, databaseName: String, tableName: String, columnName: String) -> String? {
        var found: String? = nil

        let sql = """
            SELECT hostName, databaseName, tableName, columnName, format
            FROM \(self.sqliteTableName)
            WHERE  hostName=? and databaseName=? and tableName=? and columnName=?
            ORDER BY id DESC
            """
        queue.inDatabase { [self] db in
            do {
                let rs = try db.executeQuery(sql, values: [hostName, databaseName, tableName, columnName])
                while rs.next() {
                    let format = rs.string(forColumn: "format")!
                    found = format
                    break
                }
                rs.close()
            }
            catch {
                LOG.error("Query '\(sql), failed with error: \(error.localizedDescription)")
            }
        }
        queue.close()

        return found
    }

    @objc func allDisplayOverridesFor(hostName: String, databaseName: String, tableName: String) -> [String:String] {
        var formats = [String:String]()

        let sql = """
            SELECT hostName, databaseName, tableName, columnName, format
            FROM \(self.sqliteTableName)
            WHERE  hostName=? and databaseName=? and tableName=?
            ORDER BY id DESC
            """

        queue.inDatabase { [self] db in
            do {
                let rs = try db.executeQuery(sql, values: [hostName, databaseName, tableName])
                while rs.next() {
                    let columnName = rs.string(forColumn: "columnName")!
                    let format = rs.string(forColumn: "format")!
                    formats[columnName] = format
                }
                rs.close()
            }
            catch {
                LOG.error("Query '\(sql), failed with error: \(error.localizedDescription)")
            }
        }
        queue.close()

        return formats
    }

    @objc func replaceOverrideFor(hostName: String, databaseName: String, tableName: String, colName: String, format: String) {
        let toAdd = [hostName, databaseName, tableName, colName, format];

        let sql = """
            INSERT OR REPLACE INTO \(sqliteTableName) (hostName, databaseName, tableName, columnName, format) VALUES (?, ?, ?, ?, ?)
            """
        queue.inDatabase { db in
            do {
                try db.executeUpdate(sql, values: toAdd)
            }
            catch {
                LOG.error("\(error.localizedDescription)")
            }
        }
        queue.close()
    }

    private func setupDatabase() {
        let builder: SchemaBuilder = { [self] (db, schemaVersion: Int) in
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
                    fatalError("Creating \(dbFileName) failed with error: \(error)")
                }

                newSchemaVersion = 1
                LOG.debug("self.newSchemaVersion \(newSchemaVersion)")
                LOG.info("Creating ColumnDisplayFormats Version 1 was successful!")
            }

            db.commit()
            return newSchemaVersion
        }

        queue.inDatabase { db in
            do {
                let initialVersion = try loadCurrentSchemaVersion(db)
                let finalVersion = try builder(db, initialVersion)
                try finalizeSchemaVersion(db, initialVersion, finalVersion)
            }
            catch {
                LOG.error("Processing schemaBlock resulted in error:: \(error)")
            }
        }
        queue.close()
    }

    private func loadCurrentSchemaVersion(_ db: FMDatabase) throws -> Int {
        var version = 0
        let rs = try db.executeQuery("PRAGMA user_version")
        if rs.next() {
            version = rs.long(forColumnIndex: 0)
            LOG.debug("startingSchemaVersion = \(version)")
        }
        rs.close()

        return version
    }

    private func finalizeSchemaVersion(_ db: FMDatabase, _ initialVersion: Int, _ finalVersion: Int) throws {
        guard finalVersion != initialVersion, finalVersion > 0 else {
            return
        }

        let query = "PRAGMA user_version = \(finalVersion)"
        LOG.debug("query = \(query)")
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
