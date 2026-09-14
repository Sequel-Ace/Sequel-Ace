//
// Created by Shashwat Chaudhary on 20/10/21.
// Copyright (c) 2021 Sequel-Ace. All rights reserved.
//

import Foundation
import FMDB
import OSLog

/// Keeps the tables pinned to the top of the table list, per connection and
/// database, in memory and in an SQLite store in the application-support
/// folder.
///
/// The shared instance is used from the main thread and, when a document
/// switches databases, from background threads, so every change to the
/// in-memory state and its store happens under one lock. The store is a
/// convenience: when it cannot be opened or created, pins still work for the
/// running session but are not persisted; the app never terminates over it.
@objc final class SQLitePinnedTableManager: NSObject {

    @objc static let sharedInstance = SQLitePinnedTableManager()

    private static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "pinnedTablesDatabase")
    private static let dbFileName = "pinnedTables.db"

    /// The store, or `nil` when it turned out to be unusable.
    private let queue: FMDatabaseQueue?
    /// Whether the pins in the store were read at start-up. Only then does a
    /// legacy migration see every pin it has to move, so only then is its
    /// completion recorded.
    private let storeWasLoaded: Bool
    private let prefs: UserDefaults
    private let traceExecution: Bool

    /// Guards the state below and the store's writes.
    private let stateLock = NSLock()
    private var migratedLegacyPinnedTableTokens: Set<String>
    private var pinnedTablesDatabaseDictionary: [String: [String: [String]]]
    /// Migrations run in this session that could not be recorded as done,
    /// because the store was unreadable or refused one of their pins. Kept apart from
    /// the persisted tokens: they stop the migration from running again in
    /// this session - where it would bring back a pin the user just removed -
    /// but are never written to the user defaults, so a later launch still
    /// retries them.
    private var sessionOnlyMigratedTokens: Set<String> = []

    /// SQLite's primary result code for a violated constraint; a pin another
    /// manager on the same file stored already fails with it.
    private static let sqliteConstraint = 19

    /// The shared store in the application-support folder, with the
    /// migration record in the standard user defaults.
    private override convenience init() {
        var databasePath: String?
        do {
            let dataPath = try FileManager.default.applicationSupportDirectory(forSubDirectory: SPDataSupportFolder)
            databasePath = dataPath + "/" + Self.dbFileName
        } catch {
            Self.log.error("Could not get path to applicationSupportDirectory. Error: \(error.localizedDescription). Pinned tables are not persisted.")
        }
        self.init(databasePath: databasePath, prefs: UserDefaults.standard)
    }

    /// Opens or creates the store at `databasePath` and loads the pins it
    /// holds. A `nil` path, a file that cannot be opened or a schema that
    /// cannot be created leaves the manager without a store.
    ///
    /// - Parameters:
    ///   - databasePath: Where the SQLite file lives.
    ///   - prefs: Where the record of completed legacy migrations is kept.
    init(databasePath: String?, prefs: UserDefaults) {
        let traceExecution = prefs.bool(forKey: SPTraceSQLiteExecutions)
        self.prefs = prefs
        self.traceExecution = traceExecution
        migratedLegacyPinnedTableTokens = Set(prefs.stringArray(forKey: SPMigratedPinnedTablesToConnectionIDs) ?? [])
        queue = databasePath.flatMap { Self.openStore(at: $0, traceExecution: traceExecution) }
        let storedPins = queue.flatMap { Self.loadPinnedTablesHistory(from: $0, traceExecution: traceExecution) }
        storeWasLoaded = storedPins != nil
        pinnedTablesDatabaseDictionary = storedPins ?? [:]
        super.init()
    }

    /// Whether pins are persisted; `false` when the store is unusable.
    var isPersistent: Bool {
        queue != nil
    }

    /// Opens the store at `databasePath` and brings its schema up to date.
    /// Returns `nil` when the file cannot be opened or prepared; the failure
    /// is logged and nothing else happens to the app.
    private static func openStore(at databasePath: String, traceExecution: Bool) -> FMDatabaseQueue? {
        guard let queue = FMDatabaseQueue(path: databasePath) else {
            log.error("Could not open \(databasePath). Pinned tables are not persisted.")
            return nil
        }
        guard setupPinnedTablesDatabase(in: queue, traceExecution: traceExecution) else {
            queue.close()
            return nil
        }
        return queue
    }

    private static func setupPinnedTablesDatabase(in queue: FMDatabaseQueue, traceExecution: Bool) -> Bool {
        let schemaBlock: (FMDatabase, Int) throws -> Int = { db, schemaVersion in
            db.beginTransaction()

            guard schemaVersion < 1 else {
                log.info("schemaVersion >= 1, not creating database")
                db.commit()
                return schemaVersion
            }
            log.info("schemaVersion < 1, creating database")

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
                throw error
            }

            db.commit()
            log.info("database created successfully")
            return schemaVersion + 1
        }

        var usable = false
        queue.inDatabase { db in
            do {
                db.traceExecution = traceExecution
                var startingSchemaVersion = 0

                let rs = try db.executeQuery("PRAGMA user_version", values: nil)
                if rs.next() {
                    startingSchemaVersion = rs.long(forColumnIndex: 0)
                    log.debug("startingSchemaVersion = \(startingSchemaVersion)")
                }
                rs.close()

                let newSchemaVersion = try schemaBlock(db, startingSchemaVersion)

                if newSchemaVersion != startingSchemaVersion, newSchemaVersion > 0 {
                    let query = "PRAGMA user_version = " + String(newSchemaVersion)
                    log.debug("query = \(query)")
                    try db.executeUpdate(query, values: nil)
                } else {
                    log.info("db schema did not need an update")
                }
                usable = true
            } catch {
                log.error("Preparing \(dbFileName) failed: \(error.localizedDescription). Pinned tables are not persisted.")
            }
        }
        queue.close()
        return usable
    }

    /// Reads every pin from the store, latest first per host and database.
    /// Returns `nil` when the store cannot be read; the failure is logged.
    private static func loadPinnedTablesHistory(from queue: FMDatabaseQueue, traceExecution: Bool) -> [String: [String: [String]]]? {
        var pins: [String: [String: [String]]]? = nil
        queue.inDatabase { db in
            do {
                db.traceExecution = traceExecution
                // select by id desc to get latest first
                let rs = try db.executeQuery("SELECT hostName, databaseName, pinnedTableName FROM PinnedTables order by id desc", values: nil)
                var loaded: [String: [String: [String]]] = [:]

                while rs.next() {
                    guard let hostName = rs.string(forColumn: "hostname"),
                          let databaseName = rs.string(forColumn: "databaseName"),
                          let pinnedTableName = rs.string(forColumn: "pinnedTableName") else {
                        continue
                    }
                    loaded[hostName, default: [:]][databaseName, default: []].append(pinnedTableName)
                }
                rs.close()
                pins = loaded
            } catch {
                log.error("Reading \(dbFileName) failed: \(error.localizedDescription). Pinned tables start empty.")
            }
        }
        queue.close()
        return pins
    }

    @objc func getPinnedTables(hostName: String, databaseName: String) -> [String] {
        stateLock.withLock {
            pinnedTablesDatabaseDictionary[hostName]?[databaseName] ?? []
        }
    }

    @objc func pinTable(hostName: String, databaseName: String, tableToPin: String) {
        stateLock.withLock {
            _ = pinLocked(hostName: hostName, databaseName: databaseName, tableToPin: tableToPin)
        }
    }

    /// Migrates host-scoped pinned tables to a connection-scoped key once per host+connection+database tuple.
    /// The tuple is claimed and its pins are moved in one step under the lock, so two documents seeing
    /// the same database at the same time (session restore) migrate it once. While the store could not
    /// be read the legacy pins are not known, and when it refuses one of the moved pins it does not hold
    /// them all, so in both cases the tuple stays open for a later launch; within the session it still
    /// runs only once, so unpinning a moved table does not bring it back. Only this migration's own writes
    /// count: a write that failed earlier for another pin does not hold back a migration that is stored.
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

        let completedTokens: [String]? = stateLock.withLock {
            guard migratedLegacyPinnedTableTokens.contains(migrationToken) == false,
                  sessionOnlyMigratedTokens.contains(migrationToken) == false else {
                return nil
            }

            let legacyPinnedTables = pinnedTablesDatabaseDictionary[trimmedLegacyHostName]?[trimmedDatabaseName] ?? []
            let existingPinnedTables = pinnedTablesDatabaseDictionary[trimmedConnectionIdentifier]?[trimmedDatabaseName] ?? []
            let tablesToMigrate = PinnedTableMigrationPlanner.tablesToMigrate(legacyPinnedTables: legacyPinnedTables, existingPinnedTables: existingPinnedTables)

            if tablesToMigrate.isNotEmpty {
                Self.log.info("Migrating pinned tables from legacy host key '\(trimmedLegacyHostName)' to connection key '\(trimmedConnectionIdentifier)' for database '\(trimmedDatabaseName)'")
            }
            var everyPinStored = true
            for tableName in tablesToMigrate {
                if pinLocked(hostName: trimmedConnectionIdentifier, databaseName: trimmedDatabaseName, tableToPin: tableName) == false {
                    everyPinStored = false
                }
            }

            guard storeWasLoaded, everyPinStored else {
                sessionOnlyMigratedTokens.insert(migrationToken)
                return nil
            }
            migratedLegacyPinnedTableTokens.insert(migrationToken)
            return migratedLegacyPinnedTableTokens.sorted()
        }
        guard let completedTokens else {
            return
        }
        prefs.set(completedTokens, forKey: SPMigratedPinnedTablesToConnectionIDs)
    }

    @objc func unpinTable(hostName: String, databaseName: String, tableToUnpin: String) {
        stateLock.withLock {
            guard let pinnedTables = pinnedTablesDatabaseDictionary[hostName]?[databaseName], pinnedTables.contains(tableToUnpin) else {
                return
            }
            pinnedTablesDatabaseDictionary[hostName]?[databaseName]?.removeAll(where: { $0 == tableToUnpin })

            guard let queue else {
                return
            }
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

    /// Pins a table in memory and in the store unless it is pinned already;
    /// the caller holds `stateLock`.
    ///
    /// - Returns: `false` when the store refused the pin for a reason other
    ///   than holding it already - a read-only file or folder, a full disk -
    ///   so the pin lives in memory only; `true` otherwise, including when
    ///   there is no store at all.
    private func pinLocked(hostName: String, databaseName: String, tableToPin: String) -> Bool {
        if let pinnedTables = pinnedTablesDatabaseDictionary[hostName]?[databaseName], pinnedTables.contains(tableToPin) {
            return true
        }
        addToPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, tableToPin: tableToPin)

        guard let queue else {
            return true
        }
        var stored = true
        queue.inDatabase { db in
            db.traceExecution = traceExecution
            do {
                try db.executeUpdate("INSERT INTO PinnedTables (hostName, databaseName, pinnedTableName) VALUES (?, ?, ?)",
                        values: [hostName, databaseName, tableToPin])
            } catch {
                logDBError(error)
                // A pin another manager on the same file stored already
                // violates the unique constraint; the store holds it.
                stored = (error as NSError).code & 0xFF == Self.sqliteConstraint
            }
        }
        queue.close()
        return stored
    }

    /// Adds a pin to the in-memory state; the caller holds `stateLock`.
    private func addToPinnedTablesDatabaseDictionary(hostName: String, databaseName: String, tableToPin: String) {
        pinnedTablesDatabaseDictionary[hostName, default: [:]][databaseName, default: []].append(tableToPin)
    }

    /// Logs db errors
    /// - Parameters:
    ///   - error: the thrown Error
    /// - Returns: nothing
    private func logDBError(_ error: Error) {
        Self.log.error("Query failed: \(error.localizedDescription)")
    }
}
