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
/// The first problem with the store is handed to `problems`, which the app
/// shows.
@objc final class SQLitePinnedTableManager: NSObject {

    static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "pinnedTablesDatabase")
    /// The store's file name; the app-only `sharedInstance` in
    /// SASQLiteSharedStoreLocation.swift places it in the application-support folder.
    static let dbFileName = "pinnedTables.db"

    /// The user-defaults key of the SQLite trace switch. A literal, so the
    /// Unit Tests target compiles this file without the Objective-C
    /// constants; keep in sync with `SPTraceSQLiteExecutions` in SPConstants.m.
    static let traceSQLiteExecutionsKey = "SPTraceSQLiteExecutions"
    /// The user-defaults key of the completed legacy migrations; keep in sync
    /// with `SPMigratedPinnedTablesToConnectionIDs` in SPConstants.m.
    static let migratedPinnedTablesKey = "SPMigratedPinnedTablesToConnectionIDs"

    /// The store, or `nil` when it turned out to be unusable.
    private let queue: FMDatabaseQueue?
    /// Whether the pins in the store were read at start-up. Only then does a
    /// legacy migration see every pin it has to move, so only then is its
    /// completion recorded.
    private let storeWasLoaded: Bool
    private let prefs: UserDefaults
    private let traceExecution: Bool
    /// Where the store lives, for the problems reported about it.
    private let databasePath: String?
    /// Receives the first problem with the store: one that left the manager
    /// without a store, or a write the store refused.
    let problems = SASQLiteStoreProblemReporter()

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
    /// Counts the changes to `migratedLegacyPinnedTableTokens`, so a writer of
    /// the migration record can tell whether a newer record exists.
    private var recordGeneration = 0
    /// The named groups and the groups' collapse state; tables outside every
    /// named group belong to the global pinned section. Guarded by `stateLock`.
    private var groupState = SAPinnedGroupState()

    /// The schema version this manager writes: 1 created `PinnedTables`, 2 adds
    /// the pin's group and the `PinnedTableGroups` table.
    private static let currentSchemaVersion = 2

    /// SQLite's primary result code for a violated constraint; a pin another
    /// manager on the same file stored already fails with it, and so does a pin
    /// any other constraint refused.
    private static let sqliteConstraint = 19

    /// Opens or creates the store at `databasePath` and loads the pins it
    /// holds. A `nil` path, a file that cannot be opened, a schema that
    /// cannot be created or pins that cannot be read leave the manager
    /// without a store, and are reported to `problems`. The app uses
    /// `sharedInstance`, declared in the app-target-only
    /// SASQLiteSharedStoreLocation.swift.
    ///
    /// - Parameters:
    ///   - databasePath: Where the SQLite file lives.
    ///   - prefs: Where the record of completed legacy migrations is kept.
    init(databasePath: String?, prefs: UserDefaults) {
        let traceExecution = prefs.bool(forKey: Self.traceSQLiteExecutionsKey)
        self.prefs = prefs
        self.traceExecution = traceExecution
        migratedLegacyPinnedTableTokens = Set(prefs.stringArray(forKey: Self.migratedPinnedTablesKey) ?? [])
        self.databasePath = databasePath
        var problem: SASQLiteStoreProblem?
        var openedQueue: FMDatabaseQueue?
        var storedPins: [String: [String: [String]]]?
        var storedGroups = SAPinnedGroupState()
        if let databasePath {
            openedQueue = Self.openStore(at: databasePath, traceExecution: traceExecution, problem: &problem)
            if let openedQueue {
                let loaded = Self.loadPinnedTablesHistory(from: openedQueue, traceExecution: traceExecution)
                storedPins = loaded.pins
                storedGroups = loaded.groups
                if loaded.pins == nil {
                    problem = SASQLiteStoreProblem(kind: .cannotUse, path: databasePath, reason: loaded.failure)
                }
            }
        } else {
            problem = SASQLiteStoreProblem(kind: .noLocation, path: nil, reason: nil)
        }
        // A store that opened but could not be read is not used: its pins are
        // unknown, so writing to it would add rows next to ones this session
        // never loaded. loadPinnedTablesHistory has closed it already.
        queue = storedPins == nil ? nil : openedQueue
        storeWasLoaded = storedPins != nil
        pinnedTablesDatabaseDictionary = storedPins ?? [:]
        groupState = storedPins == nil ? SAPinnedGroupState() : storedGroups
        super.init()
        if let problem {
            problems.report(problem)
        }
    }

    /// Whether pins are persisted; `false` when the store is unusable.
    var isPersistent: Bool {
        queue != nil
    }

    /// Opens the store at `databasePath` and brings its schema up to date.
    /// Returns `nil` when the file cannot be opened or prepared; the failure
    /// is logged and described in `problem`.
    private static func openStore(at databasePath: String, traceExecution: Bool, problem: inout SASQLiteStoreProblem?) -> FMDatabaseQueue? {
        guard let queue = FMDatabaseQueue(path: databasePath) else {
            log.error("Could not open \(databasePath). Pinned tables are not persisted.")
            problem = SASQLiteStoreProblem(kind: .cannotOpen, path: databasePath, reason: nil)
            return nil
        }
        if let failure = setupPinnedTablesDatabase(in: queue, traceExecution: traceExecution) {
            queue.close()
            problem = SASQLiteStoreProblem(kind: .cannotUse, path: databasePath, reason: failure)
            return nil
        }
        return queue
    }

    /// Creates the pinned-tables table when the store's schema version predates it
    /// and records the new version. Returns the description of the step that
    /// failed, which is logged, or `nil` when the store is ready.
    private static func setupPinnedTablesDatabase(in queue: FMDatabaseQueue, traceExecution: Bool) -> String? {
        // Every step up to `currentSchemaVersion` and the version itself are written
        // in one transaction: when a step fails, nothing is committed, the version
        // stays where it was and the store is reported as unusable instead of
        // being marked as upgraded.
        let schemaBlock: (FMDatabase, Int) throws -> Int = { db, schemaVersion in
            guard schemaVersion < currentSchemaVersion else {
                log.info("schemaVersion >= \(currentSchemaVersion), nothing to migrate")
                return schemaVersion
            }
            guard db.beginTransaction() else {
                throw db.lastError()
            }

            do {
                if schemaVersion < 1 {
                    log.info("schemaVersion < 1, creating database")
                    // IF NOT EXISTS: a launch that died between creating the table and
                    // writing the version leaves the table in place at version 0.
                    // Creating it again would fail and switch persistence off for good,
                    // so the existing table is taken over here; a table with another
                    // schema fails the column check below, leaves the file as it was
                    // and the store unused.
                    let createTableSQL = "CREATE TABLE IF NOT EXISTS PinnedTables ("
                            + "    id                   INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,"
                            + "    hostName             TEXT NOT NULL,"
                            + "    databaseName         TEXT NOT NULL,"
                            + "    pinnedTableName      TEXT NOT NULL,"
                            + "    CONSTRAINT host_db_table UNIQUE (hostName, databaseName, pinnedTableName))"
                    try db.executeUpdate(createTableSQL, values: nil)
                    try db.executeUpdate("CREATE INDEX IF NOT EXISTS host_db_idx ON PinnedTables (hostName, databaseName)", values: nil)
                    // A table taken over has to be one this manager can read;
                    // otherwise nothing is committed and no version is written.
                    let columns = try db.executeQuery("SELECT id, hostName, databaseName, pinnedTableName FROM PinnedTables LIMIT 0", values: nil)
                    columns.close()
                }

                if schemaVersion < 2 {
                    log.info("schemaVersion < 2, adding pinned table groups")
                    // The empty group name is the historical, global pinned section, so
                    // every pin stored before groups existed stays where it was.
                    if try !Self.table(named: "PinnedTables", hasColumn: "groupName", in: db) {
                        try db.executeUpdate("ALTER TABLE PinnedTables ADD COLUMN groupName TEXT NOT NULL DEFAULT ''", values: nil)
                    }
                    try db.executeUpdate("CREATE TABLE IF NOT EXISTS PinnedTableGroups ("
                            + "    hostName      TEXT NOT NULL,"
                            + "    databaseName  TEXT NOT NULL,"
                            + "    groupName     TEXT NOT NULL,"
                            + "    isCollapsed   INTEGER NOT NULL DEFAULT 0,"
                            + "    CONSTRAINT host_db_group UNIQUE (hostName, databaseName, groupName))", values: nil)
                    try db.executeUpdate("CREATE INDEX IF NOT EXISTS host_db_group_idx ON PinnedTableGroups (hostName, databaseName)", values: nil)
                }

                try db.executeUpdate("PRAGMA user_version = \(currentSchemaVersion)", values: nil)
                guard db.commit() else {
                    throw db.lastError()
                }
            } catch {
                db.rollback()
                throw error
            }
            log.info("database is at schema version \(currentSchemaVersion)")
            return currentSchemaVersion
        }

        var failure: String? = nil
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

                _ = try schemaBlock(db, startingSchemaVersion)
            } catch {
                log.error("Preparing \(dbFileName) failed: \(error.localizedDescription). Pinned tables are not persisted.")
                failure = error.localizedDescription
            }
        }
        queue.close()
        return failure
    }

    /// Whether `tableName` has a column called `columnName`.
    private static func table(named tableName: String, hasColumn columnName: String, in db: FMDatabase) throws -> Bool {
        let rs = try db.executeQuery("PRAGMA table_info(\(tableName))", values: nil)
        defer { rs.close() }
        while rs.next() {
            if rs.string(forColumn: "name")?.caseInsensitiveCompare(columnName) == .orderedSame {
                return true
            }
        }
        return false
    }

    /// Reads every pin and group from the store, latest first per host and database.
    ///
    /// - Parameters:
    ///   - queue: The open store; it is closed here.
    ///   - traceExecution: Whether SQLite logs every statement.
    /// - Returns: The pins and groups, or `pins == nil` when the store cannot be read, with
    ///   `failure` describing the error where there is one. Every failure is logged.
    private static func loadPinnedTablesHistory(from queue: FMDatabaseQueue, traceExecution: Bool) -> (pins: [String: [String: [String]]]?, groups: SAPinnedGroupState, failure: String?) {
        var pins: [String: [String: [String]]]? = nil
        var groups = SAPinnedGroupState()
        var failure: String? = nil
        queue.inDatabase { db in
            do {
                db.traceExecution = traceExecution
                // select by id desc to get latest first
                let rs = try db.executeQuery("SELECT hostName, databaseName, pinnedTableName, groupName FROM PinnedTables order by id desc", values: nil)
                var loaded: [String: [String: [String]]] = [:]
                var loadedGroups = SAPinnedGroupState()

                while rs.next() {
                    // A row without one of these is a damaged or foreign
                    // schema: skipping it would hand out an incomplete list,
                    // and a legacy migration reading that list would record
                    // itself as done although a pin never made it across.
                    guard let hostName = rs.string(forColumn: "hostname"),
                          let databaseName = rs.string(forColumn: "databaseName"),
                          let pinnedTableName = rs.string(forColumn: "pinnedTableName") else {
                        rs.close()
                        log.error("Reading \(dbFileName) failed: a row has no host, database or table name. Pinned tables start empty.")
                        return
                    }
                    loaded[hostName, default: [:]][databaseName, default: []].append(pinnedTableName)
                    let groupName = SAPinnedTableGroupPlanner.normalizedGroupName(rs.string(forColumn: "groupName") ?? "")
                    if groupName.isNotEmpty {
                        loadedGroups.addGroup(groupName, hostName: hostName, databaseName: databaseName)
                        loadedGroups.setGroup(groupName, forTable: pinnedTableName, hostName: hostName, databaseName: databaseName)
                    }
                }
                rs.close()

                let groupRows = try db.executeQuery("SELECT hostName, databaseName, groupName, isCollapsed FROM PinnedTableGroups", values: nil)
                while groupRows.next() {
                    guard let hostName = groupRows.string(forColumn: "hostName"),
                          let databaseName = groupRows.string(forColumn: "databaseName"),
                          let groupName = groupRows.string(forColumn: "groupName") else {
                        groupRows.close()
                        log.error("Reading \(dbFileName) failed: a group has no host, database or name. Pinned tables start empty.")
                        return
                    }
                    loadedGroups.addGroup(groupName, hostName: hostName, databaseName: databaseName)
                    loadedGroups.setCollapsed(groupRows.bool(forColumn: "isCollapsed"), group: groupName, hostName: hostName, databaseName: databaseName)
                }
                groupRows.close()
                pins = loaded
                groups = loadedGroups
            } catch {
                log.error("Reading \(dbFileName) failed: \(error.localizedDescription). Pinned tables start empty.")
                failure = error.localizedDescription
            }
        }
        queue.close()
        return (pins, groups, failure)
    }

    /// Returns the tables pinned for `hostName` and `databaseName`; empty when
    /// none are pinned.
    @objc func getPinnedTables(hostName: String, databaseName: String) -> [String] {
        stateLock.withLock {
            pinnedTablesDatabaseDictionary[hostName]?[databaseName] ?? []
        }
    }

    /// Pins a table for a host and database, in memory and in the store when there
    /// is one; a table that is pinned already stays as it is.
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

        let record: SAMigrationRecord? = stateLock.withLock {
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
            recordGeneration += 1
            return SAMigrationRecord(generation: recordGeneration, tokens: migratedLegacyPinnedTableTokens.sorted())
        }
        guard let record else {
            return
        }
        persistMigrationRecord(record)
    }

    /// The completed migrations as of one change to them.
    private struct SAMigrationRecord {
        let generation: Int
        let tokens: [String]
    }

    /// Writes the completed migrations to the user defaults.
    ///
    /// The write happens without `stateLock`: setting a default notifies its
    /// observers synchronously on this thread, and the app's observer
    /// (`SPAppController`'s `defaultsChanged:`) waits for the main thread, which
    /// may itself be waiting for the lock. Two migrations finishing at the same
    /// time may therefore write in either order, and an older record written
    /// last would drop a token, letting the next launch migrate again and bring
    /// back a pin the user removed. So a writer that finds a newer record once
    /// its write is done writes that one as well: the last write always holds
    /// every completed migration.
    private func persistMigrationRecord(_ record: SAMigrationRecord) {
        var current = record
        while true {
            prefs.set(current.tokens, forKey: Self.migratedPinnedTablesKey)
            let newer: SAMigrationRecord? = stateLock.withLock {
                guard recordGeneration > current.generation else {
                    return nil
                }
                return SAMigrationRecord(generation: recordGeneration, tokens: migratedLegacyPinnedTableTokens.sorted())
            }
            guard let newer else {
                return
            }
            current = newer
        }
    }

    /// Unpins a table for a host and database, in memory and in the store when
    /// there is one; a table that is not pinned is ignored.
    @objc func unpinTable(hostName: String, databaseName: String, tableToUnpin: String) {
        stateLock.withLock {
            guard let pinnedTables = pinnedTablesDatabaseDictionary[hostName]?[databaseName], pinnedTables.contains(tableToUnpin) else {
                return
            }
            pinnedTablesDatabaseDictionary[hostName]?[databaseName]?.removeAll(where: { $0 == tableToUnpin })
            groupState.removeTable(tableToUnpin, hostName: hostName, databaseName: databaseName)

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
                    problems.report(SASQLiteStoreProblem(kind: .cannotSave, path: databasePath, reason: error.localizedDescription))
                }
            }
            queue.close()
        }
    }

    /// Pins a table in memory and in the store unless it is pinned already;
    /// the caller holds `stateLock`.
    ///
    /// - Returns: `false` when the store refused the pin for a reason other
    ///   than holding it already - a read-only file or folder, a full disk, a
    ///   constraint other than its unique key - so the pin lives in memory
    ///   only and the refusal is reported to `problems`; `true` otherwise,
    ///   including when there is no store at all.
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
                // violates the unique constraint; the store holds it. Any
                // other constraint - a CHECK in a schema this version did not
                // create, say - reports the same code but refused the pin, so
                // only a row that is actually there counts.
                stored = (error as NSError).code & 0xFF == Self.sqliteConstraint
                    && storeHoldsPin(in: db, hostName: hostName, databaseName: databaseName, tableName: tableToPin)
                if stored == false {
                    problems.report(SASQLiteStoreProblem(kind: .cannotSave, path: databasePath, reason: error.localizedDescription))
                }
            }
        }
        queue.close()
        return stored
    }

    /// Whether the store holds the row for a pin; `false` when it cannot be read.
    ///
    /// - Parameters:
    ///   - db: The open store.
    ///   - hostName: The pin's host or connection key.
    ///   - databaseName: The pin's database.
    ///   - tableName: The pinned table.
    /// - Returns: Whether exactly this pin has a row.
    private func storeHoldsPin(in db: FMDatabase, hostName: String, databaseName: String, tableName: String) -> Bool {
        do {
            let rs = try db.executeQuery("SELECT 1 FROM PinnedTables WHERE hostName=? AND databaseName=? AND pinnedTableName=? LIMIT 1",
                    values: [hostName, databaseName, tableName])
            defer { rs.close() }
            return rs.next()
        } catch {
            logDBError(error)
            return false
        }
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

// MARK: - Pinned table groups

/// The outcome of renaming a group of pinned tables.
enum SAPinnedGroupRenameResult: Equatable {
    case renamed
    /// Another group of the database already has the new name.
    case duplicateName
    /// The new name is empty or the group does not exist.
    case invalidName
    /// The store refused the write; nothing was changed.
    case storageFailure
}

/// One section of the pinned tables: the global section (empty `groupName`) or a
/// named group, with its tables in display order.
@objc(SAPinnedTableSection) final class SAPinnedTableSection: NSObject {
    @objc let groupName: String
    @objc let tableNames: [String]
    @objc let isCollapsed: Bool

    init(groupName: String, tableNames: [String], isCollapsed: Bool) {
        self.groupName = groupName
        self.tableNames = tableNames
        self.isCollapsed = isCollapsed
        super.init()
    }
}

/// The named groups per host and database, which group each pinned table is in,
/// and which groups are collapsed. A table that is in no group is in the global
/// section. A value type, so a change can be prepared, written to the store and
/// only then published.
struct SAPinnedGroupState {
    private var names: [String: [String: Set<String>]] = [:]
    private var tableGroups: [String: [String: [String: String]]] = [:]
    private var collapsed: [String: [String: Set<String>]] = [:]

    func groupNames(hostName: String, databaseName: String) -> Set<String> {
        names[hostName]?[databaseName] ?? []
    }

    /// The group of a table; empty for the global section.
    func group(ofTable tableName: String, hostName: String, databaseName: String) -> String {
        tableGroups[hostName]?[databaseName]?[tableName] ?? ""
    }

    func isCollapsed(group: String, hostName: String, databaseName: String) -> Bool {
        collapsed[hostName]?[databaseName]?.contains(group) ?? false
    }

    mutating func addGroup(_ group: String, hostName: String, databaseName: String) {
        names[hostName, default: [:]][databaseName, default: []].insert(group)
    }

    /// Removes a group; its tables return to the global section.
    mutating func removeGroup(_ group: String, hostName: String, databaseName: String) {
        names[hostName]?[databaseName]?.remove(group)
        collapsed[hostName]?[databaseName]?.remove(group)
        for (table, tableGroup) in tableGroups[hostName]?[databaseName] ?? [:] where tableGroup == group {
            tableGroups[hostName]?[databaseName]?[table] = nil
        }
    }

    mutating func renameGroup(_ group: String, to newGroup: String, hostName: String, databaseName: String) {
        let wasCollapsed = isCollapsed(group: group, hostName: hostName, databaseName: databaseName)
        for (table, tableGroup) in tableGroups[hostName]?[databaseName] ?? [:] where tableGroup == group {
            tableGroups[hostName]?[databaseName]?[table] = newGroup
        }
        names[hostName]?[databaseName]?.remove(group)
        collapsed[hostName]?[databaseName]?.remove(group)
        addGroup(newGroup, hostName: hostName, databaseName: databaseName)
        setCollapsed(wasCollapsed, group: newGroup, hostName: hostName, databaseName: databaseName)
    }

    /// Puts a table in a group; the empty group is the global section.
    mutating func setGroup(_ group: String, forTable tableName: String, hostName: String, databaseName: String) {
        if group.isEmpty {
            tableGroups[hostName]?[databaseName]?[tableName] = nil
        } else {
            tableGroups[hostName, default: [:]][databaseName, default: [:]][tableName] = group
        }
    }

    mutating func removeTable(_ tableName: String, hostName: String, databaseName: String) {
        tableGroups[hostName]?[databaseName]?[tableName] = nil
    }

    mutating func renameTable(_ tableName: String, to newTableName: String, hostName: String, databaseName: String) {
        let group = self.group(ofTable: tableName, hostName: hostName, databaseName: databaseName)
        removeTable(tableName, hostName: hostName, databaseName: databaseName)
        setGroup(group, forTable: newTableName, hostName: hostName, databaseName: databaseName)
    }

    mutating func setCollapsed(_ isCollapsed: Bool, group: String, hostName: String, databaseName: String) {
        if isCollapsed {
            collapsed[hostName, default: [:]][databaseName, default: []].insert(group)
        } else {
            collapsed[hostName]?[databaseName]?.remove(group)
        }
    }
}

extension SQLitePinnedTableManager {

    /// The pinned tables as sections for the table list: the global section first
    /// when it holds tables, then every named group - empty ones too - in order.
    @objc(pinnedTableSectionsWithHostName:databaseName:)
    func pinnedTableSections(hostName: String, databaseName: String) -> [SAPinnedTableSection] {
        stateLock.withLock {
            let pins = pinnedTablesDatabaseDictionary[hostName]?[databaseName] ?? []
            var tablesByGroup: [String: [String]] = [:]
            for table in pins {
                tablesByGroup[groupState.group(ofTable: table, hostName: hostName, databaseName: databaseName), default: []].append(table)
            }
            var sections: [SAPinnedTableSection] = []
            if let globalTables = tablesByGroup[""], globalTables.isNotEmpty {
                sections.append(SAPinnedTableSection(groupName: "", tableNames: SAPinnedTableGroupPlanner.orderedTableNames(globalTables), isCollapsed: false))
            }
            let groups = SAPinnedTableGroupPlanner.orderedGroupNames(Array(groupState.groupNames(hostName: hostName, databaseName: databaseName)))
            for group in groups {
                sections.append(SAPinnedTableSection(
                    groupName: group,
                    tableNames: SAPinnedTableGroupPlanner.orderedTableNames(tablesByGroup[group] ?? []),
                    isCollapsed: groupState.isCollapsed(group: group, hostName: hostName, databaseName: databaseName)))
            }
            return sections
        }
    }

    /// The names of the groups, in display order.
    @objc(pinnedTableGroupNamesWithHostName:databaseName:)
    func pinnedTableGroupNames(hostName: String, databaseName: String) -> [String] {
        stateLock.withLock {
            SAPinnedTableGroupPlanner.orderedGroupNames(Array(groupState.groupNames(hostName: hostName, databaseName: databaseName)))
        }
    }

    /// The group a pinned table is in: the empty string for the global section,
    /// `nil` when the table is not pinned.
    @objc(groupNameForPinnedTableWithHostName:databaseName:tableName:)
    func groupNameForPinnedTable(hostName: String, databaseName: String, tableName: String) -> String? {
        stateLock.withLock {
            guard pinnedTablesDatabaseDictionary[hostName]?[databaseName]?.contains(tableName) == true else {
                return nil
            }
            return groupState.group(ofTable: tableName, hostName: hostName, databaseName: databaseName)
        }
    }

    @objc(isPinnedTableGroupCollapsedWithHostName:databaseName:groupName:)
    func isPinnedTableGroupCollapsed(hostName: String, databaseName: String, groupName: String) -> Bool {
        stateLock.withLock {
            groupState.isCollapsed(group: groupName, hostName: hostName, databaseName: databaseName)
        }
    }

    /// Pins the tables that are not pinned yet into `groupName`, and moves the pinned
    /// ones to it; the empty name is the global section. The group is created when
    /// needed. All of it is stored in one transaction and published only once the
    /// store has it.
    ///
    /// - Returns: `false` when nothing changed because the name is not usable as a
    ///   group name or the store refused the change.
    @objc(movePinnedTablesWithHostName:databaseName:tableNames:toGroupName:)
    @discardableResult
    func movePinnedTables(hostName: String, databaseName: String, tableNames: [String], toGroupName groupName: String) -> Bool {
        let group = SAPinnedTableGroupPlanner.normalizedGroupName(groupName)
        let tables = tableNames.reduce(into: [String]()) { if !$0.contains($1) && $1.isNotEmpty { $0.append($1) } }
        return stateLock.withLock {
            let pinned = Set(pinnedTablesDatabaseDictionary[hostName]?[databaseName] ?? [])
            var next = groupState
            if group.isNotEmpty {
                next.addGroup(group, hostName: hostName, databaseName: databaseName)
            }
            let changed = tables.filter {
                !pinned.contains($0) || groupState.group(ofTable: $0, hostName: hostName, databaseName: databaseName) != group
            }
            let groupIsNew = group.isNotEmpty && !groupState.groupNames(hostName: hostName, databaseName: databaseName).contains(group)
            guard changed.isNotEmpty || groupIsNew else {
                return true
            }
            guard writeLocked({ db in
                if group.isNotEmpty {
                    try db.executeUpdate("INSERT OR IGNORE INTO PinnedTableGroups (hostName, databaseName, groupName) VALUES (?, ?, ?)",
                            values: [hostName, databaseName, group])
                }
                for table in changed {
                    try db.executeUpdate("INSERT OR IGNORE INTO PinnedTables (hostName, databaseName, pinnedTableName, groupName) VALUES (?, ?, ?, ?)",
                            values: [hostName, databaseName, table, group])
                    try db.executeUpdate("UPDATE PinnedTables SET groupName=? WHERE hostName=? AND databaseName=? AND pinnedTableName=?",
                            values: [group, hostName, databaseName, table])
                }
            }) else {
                return false
            }
            for table in changed {
                if !pinned.contains(table) {
                    addToPinnedTablesDatabaseDictionary(hostName: hostName, databaseName: databaseName, tableToPin: table)
                }
                next.setGroup(group, forTable: table, hostName: hostName, databaseName: databaseName)
            }
            groupState = next
            return true
        }
    }

    /// Creates an empty group. Returns `false` for an unusable name or when the store refused it.
    @objc(createPinnedTableGroupWithHostName:databaseName:groupName:)
    @discardableResult
    func createPinnedTableGroup(hostName: String, databaseName: String, groupName: String) -> Bool {
        let group = SAPinnedTableGroupPlanner.normalizedGroupName(groupName)
        guard group.isNotEmpty else {
            return false
        }
        return movePinnedTables(hostName: hostName, databaseName: databaseName, tableNames: [], toGroupName: group)
    }

    /// Renames a group, keeping its tables and collapse state.
    ///
    /// - Returns: `.renamed` on success (also when the name is unchanged), `.duplicateName`
    ///   when another group already has the new name, `.invalidName` for an empty name or
    ///   an unknown group, and `.storageFailure` when the store refused the write; nothing
    ///   changes in memory in the last three cases.
    func renamePinnedTableGroup(hostName: String, databaseName: String, groupName: String, toGroupName newGroupName: String) -> SAPinnedGroupRenameResult {
        let group = SAPinnedTableGroupPlanner.normalizedGroupName(groupName)
        let newGroup = SAPinnedTableGroupPlanner.normalizedGroupName(newGroupName)
        guard group.isNotEmpty, newGroup.isNotEmpty else {
            return .invalidName
        }
        return stateLock.withLock {
            let existing = groupState.groupNames(hostName: hostName, databaseName: databaseName)
            guard existing.contains(group) else {
                return .invalidName
            }
            guard group == newGroup || !existing.contains(newGroup) else {
                return .duplicateName
            }
            guard group != newGroup else {
                return .renamed
            }
            guard writeLocked({ db in
                try db.executeUpdate("UPDATE PinnedTableGroups SET groupName=? WHERE hostName=? AND databaseName=? AND groupName=?",
                        values: [newGroup, hostName, databaseName, group])
                try db.executeUpdate("UPDATE PinnedTables SET groupName=? WHERE hostName=? AND databaseName=? AND groupName=?",
                        values: [newGroup, hostName, databaseName, group])
            }) else {
                return .storageFailure
            }
            groupState.renameGroup(group, to: newGroup, hostName: hostName, databaseName: databaseName)
            return .renamed
        }
    }

    /// Deletes a group. Its tables stay pinned and return to the global section.
    @objc(deletePinnedTableGroupWithHostName:databaseName:groupName:)
    @discardableResult
    func deletePinnedTableGroup(hostName: String, databaseName: String, groupName: String) -> Bool {
        let group = SAPinnedTableGroupPlanner.normalizedGroupName(groupName)
        return stateLock.withLock {
            guard group.isNotEmpty, groupState.groupNames(hostName: hostName, databaseName: databaseName).contains(group) else {
                return false
            }
            guard writeLocked({ db in
                try db.executeUpdate("UPDATE PinnedTables SET groupName='' WHERE hostName=? AND databaseName=? AND groupName=?",
                        values: [hostName, databaseName, group])
                try db.executeUpdate("DELETE FROM PinnedTableGroups WHERE hostName=? AND databaseName=? AND groupName=?",
                        values: [hostName, databaseName, group])
            }) else {
                return false
            }
            groupState.removeGroup(group, hostName: hostName, databaseName: databaseName)
            return true
        }
    }

    /// Stores whether a group is shown collapsed. Returns `false` when the group does
    /// not exist or the store refused the change.
    @objc(setPinnedTableGroupCollapsedWithHostName:databaseName:groupName:isCollapsed:)
    @discardableResult
    func setPinnedTableGroupCollapsed(hostName: String, databaseName: String, groupName: String, isCollapsed: Bool) -> Bool {
        let group = SAPinnedTableGroupPlanner.normalizedGroupName(groupName)
        return stateLock.withLock {
            guard group.isNotEmpty, groupState.groupNames(hostName: hostName, databaseName: databaseName).contains(group) else {
                return false
            }
            guard writeLocked({ db in
                try db.executeUpdate("UPDATE PinnedTableGroups SET isCollapsed=? WHERE hostName=? AND databaseName=? AND groupName=?",
                        values: [isCollapsed ? 1 : 0, hostName, databaseName, group])
            }) else {
                return false
            }
            groupState.setCollapsed(isCollapsed, group: group, hostName: hostName, databaseName: databaseName)
            return true
        }
    }

    /// Follows a renamed table: the pin keeps its place and its group. When the new
    /// name is pinned already, the old pin is dropped.
    @objc(renamePinnedTableWithHostName:databaseName:from:to:)
    @discardableResult
    func renamePinnedTable(hostName: String, databaseName: String, from oldTableName: String, to newTableName: String) -> Bool {
        stateLock.withLock {
            let pinned = pinnedTablesDatabaseDictionary[hostName]?[databaseName] ?? []
            guard oldTableName != newTableName, pinned.contains(oldTableName) else {
                return false
            }
            let newIsPinned = pinned.contains(newTableName)
            guard writeLocked({ db in
                if newIsPinned {
                    try db.executeUpdate("DELETE FROM PinnedTables WHERE hostName=? AND databaseName=? AND pinnedTableName=?",
                            values: [hostName, databaseName, oldTableName])
                } else {
                    try db.executeUpdate("UPDATE PinnedTables SET pinnedTableName=? WHERE hostName=? AND databaseName=? AND pinnedTableName=?",
                            values: [newTableName, hostName, databaseName, oldTableName])
                }
            }) else {
                return false
            }
            if newIsPinned {
                pinnedTablesDatabaseDictionary[hostName]?[databaseName]?.removeAll { $0 == oldTableName }
                groupState.removeTable(oldTableName, hostName: hostName, databaseName: databaseName)
            } else if let index = pinned.firstIndex(of: oldTableName) {
                pinnedTablesDatabaseDictionary[hostName]?[databaseName]?[index] = newTableName
                groupState.renameTable(oldTableName, to: newTableName, hostName: hostName, databaseName: databaseName)
            }
            return true
        }
    }

    /// Runs `body` in one transaction; the caller holds `stateLock`. Nothing is
    /// kept when it fails.
    ///
    /// - Returns: `false` when the store refused the change, which is reported to
    ///   `problems`; `true` otherwise, including when there is no store at all.
    private func writeLocked(_ body: (FMDatabase) throws -> Void) -> Bool {
        guard let queue else {
            return true
        }
        var stored = true
        queue.inDatabase { db in
            db.traceExecution = traceExecution
            guard db.beginTransaction() else {
                logDBError(db.lastError())
                problems.report(SASQLiteStoreProblem(kind: .cannotSave, path: databasePath, reason: db.lastErrorMessage()))
                stored = false
                return
            }
            do {
                try body(db)
                guard db.commit() else {
                    throw db.lastError()
                }
            } catch {
                db.rollback()
                logDBError(error)
                problems.report(SASQLiteStoreProblem(kind: .cannotSave, path: databasePath, reason: error.localizedDescription))
                stored = false
            }
        }
        queue.close()
        return stored
    }
}
