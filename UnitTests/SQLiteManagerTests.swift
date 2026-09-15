//
//  SQLiteManagerTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import FMDB
import XCTest

// MARK: - SQLiteDisplayFormatManager

/// The display-format store must survive a folder it cannot write to and a
/// file it cannot read: formats are then not persisted, nothing crashes.
final class SASQLiteDisplayFormatManagerTests: XCTestCase {
    private var directory: URL!

    /// Creates an empty temporary directory for the test's store.
    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SASQLiteDisplayFormatManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Removes the temporary directory and everything in it.
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    /// Verifies that stored formats are read back per column, a later format replaces
    /// an earlier one, and the formats survive reopening the store.
    func testFormatsRoundTripThroughTheStore() {
        let path = directory.appendingPathComponent("formats.db").path
        let manager = SQLiteDisplayFormatManager(databasePath: path)
        XCTAssertTrue(manager.isPersistent)
        XCTAssertNil(manager.displayOverrideFor(hostName: "h", databaseName: "d", tableName: "t", columnName: "c"))

        manager.replaceOverrideFor(hostName: "h", databaseName: "d", tableName: "t", colName: "c", format: "hex")
        manager.replaceOverrideFor(hostName: "h", databaseName: "d", tableName: "t", colName: "c2", format: "base64")
        manager.replaceOverrideFor(hostName: "h", databaseName: "d", tableName: "t", colName: "c", format: "binary")

        XCTAssertEqual(manager.displayOverrideFor(hostName: "h", databaseName: "d", tableName: "t", columnName: "c"), "binary")
        XCTAssertEqual(manager.allDisplayOverridesFor(hostName: "h", databaseName: "d", tableName: "t"), ["c": "binary", "c2": "base64"])
        XCTAssertEqual(manager.allDisplayOverridesFor(hostName: "h", databaseName: "d", tableName: "other"), [:])

        let reopened = SQLiteDisplayFormatManager(databasePath: path)
        XCTAssertTrue(reopened.isPersistent)
        XCTAssertEqual(reopened.allDisplayOverridesFor(hostName: "h", databaseName: "d", tableName: "t"), ["c": "binary", "c2": "base64"])
    }

    /// Verifies that a store in a missing folder leaves the manager without persistence,
    /// returning no formats and creating no file.
    func testUnwritableLocationDegradesToDefaults() {
        let path = directory.appendingPathComponent("missing/formats.db").path
        let manager = SQLiteDisplayFormatManager(databasePath: path)
        XCTAssertFalse(manager.isPersistent)

        manager.replaceOverrideFor(hostName: "h", databaseName: "d", tableName: "t", colName: "c", format: "hex")
        XCTAssertNil(manager.displayOverrideFor(hostName: "h", databaseName: "d", tableName: "t", columnName: "c"))
        XCTAssertEqual(manager.allDisplayOverridesFor(hostName: "h", databaseName: "d", tableName: "t"), [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    /// Verifies that a `nil` path leaves the manager without persistence, returning no formats.
    func testMissingLocationDegradesToDefaults() {
        let manager = SQLiteDisplayFormatManager(databasePath: nil)
        XCTAssertFalse(manager.isPersistent)

        manager.replaceOverrideFor(hostName: "h", databaseName: "d", tableName: "t", colName: "c", format: "hex")
        XCTAssertNil(manager.displayOverrideFor(hostName: "h", databaseName: "d", tableName: "t", columnName: "c"))
        XCTAssertEqual(manager.allDisplayOverridesFor(hostName: "h", databaseName: "d", tableName: "t"), [:])
    }

    /// Verifies that a file that is not a database is not used and is left untouched.
    func testDamagedStoreDegradesToDefaults() throws {
        let url = directory.appendingPathComponent("formats.db")
        let garbage = Data(repeating: 0x5A, count: 4096)
        try garbage.write(to: url)

        let manager = SQLiteDisplayFormatManager(databasePath: url.path)
        XCTAssertFalse(manager.isPersistent)

        manager.replaceOverrideFor(hostName: "h", databaseName: "d", tableName: "t", colName: "c", format: "hex")
        XCTAssertNil(manager.displayOverrideFor(hostName: "h", databaseName: "d", tableName: "t", columnName: "c"))
        XCTAssertEqual(manager.allDisplayOverridesFor(hostName: "h", databaseName: "d", tableName: "t"), [:])
        XCTAssertEqual(try Data(contentsOf: url), garbage)
    }

    /// Verifies that a read-only empty file, in which the table cannot be created, is not used.
    func testReadOnlyStoreDegradesWhenTheTableCannotBeCreated() throws {
        let url = directory.appendingPathComponent("formats.db")
        try Data().write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)

        let manager = SQLiteDisplayFormatManager(databasePath: url.path)
        XCTAssertFalse(manager.isPersistent)

        manager.replaceOverrideFor(hostName: "h", databaseName: "d", tableName: "t", colName: "c", format: "hex")
        XCTAssertNil(manager.displayOverrideFor(hostName: "h", databaseName: "d", tableName: "t", columnName: "c"))
    }
}

extension SASQLiteDisplayFormatManagerTests {
    /// Verifies that a store whose table lacks a column the queries read is not used and
    /// receives no rows.
    func testStoreWhoseTableCannotBeReadIsNotUsed() throws {
        let path = directory.appendingPathComponent("ColumnDisplayOverrides.db").path
        // Schema version 1, so the table is not created again, but it lacks the id column the queries order by;
        // an insert would still succeed, so a store kept like this would take formats it can never read back.
        try makeSQLiteFile(at: path, statements: [
            "CREATE TABLE ColumnDisplayOverrides (hostName TEXT NOT NULL, databaseName TEXT NOT NULL, tableName TEXT NOT NULL, columnName TEXT NOT NULL, format TEXT NOT NULL)",
            "PRAGMA user_version = 1",
        ])

        let manager = SQLiteDisplayFormatManager(databasePath: path)
        XCTAssertFalse(manager.isPersistent)
        manager.replaceOverrideFor(hostName: "host", databaseName: "db", tableName: "orders", colName: "id", format: "UUID")
        XCTAssertNil(manager.displayOverrideFor(hostName: "host", databaseName: "db", tableName: "orders", columnName: "id"))
        XCTAssertEqual(try rowCount(inSQLiteFile: path, table: "ColumnDisplayOverrides"), 0)
    }
}

// MARK: - SQLitePinnedTableManager

/// Pins must stay consistent when several threads pin, unpin and migrate at
/// once, and must keep working in memory when the store is unusable.
final class SASQLitePinnedTableManagerTests: XCTestCase {
    private var directory: URL!
    private var prefsSuiteName: String!
    private var prefs: UserDefaults!

    /// Creates an empty temporary directory for the store and a separate user-defaults
    /// suite for the migration record.
    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SASQLitePinnedTableManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        prefsSuiteName = "SASQLitePinnedTableManagerTests-\(UUID().uuidString)"
        prefs = try XCTUnwrap(UserDefaults(suiteName: prefsSuiteName))
    }

    /// Removes the user-defaults suite and the temporary directory.
    override func tearDownWithError() throws {
        prefs.removePersistentDomain(forName: prefsSuiteName)
        prefs = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    private var storePath: String {
        directory.appendingPathComponent("pinnedTables.db").path
    }

    /// Verifies that pinning twice keeps one pin, unpinning ignores tables that are not
    /// pinned, and the pins survive reopening the store.
    func testPinsPersistAcrossManagers() {
        let manager = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        XCTAssertTrue(manager.isPersistent)
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn", databaseName: "db"), [])

        manager.pinTable(hostName: "conn", databaseName: "db", tableToPin: "orders")
        manager.pinTable(hostName: "conn", databaseName: "db", tableToPin: "orders")
        manager.pinTable(hostName: "conn", databaseName: "db", tableToPin: "users")
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn", databaseName: "db"), ["orders", "users"])

        manager.unpinTable(hostName: "conn", databaseName: "db", tableToUnpin: "orders")
        manager.unpinTable(hostName: "conn", databaseName: "db", tableToUnpin: "never pinned")
        manager.pinTable(hostName: "conn", databaseName: "db", tableToPin: "customers")
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn", databaseName: "db"), ["users", "customers"])
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn", databaseName: "other"), [])

        let reopened = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        XCTAssertTrue(reopened.isPersistent)
        XCTAssertEqual(Set(reopened.getPinnedTables(hostName: "conn", databaseName: "db")), ["users", "customers"])
    }

    /// Verifies that with a store in a missing folder pins and unpins work in memory and
    /// no file is created.
    func testUnwritableLocationKeepsPinsInMemory() {
        let path = directory.appendingPathComponent("missing/pinnedTables.db").path
        let manager = SQLitePinnedTableManager(databasePath: path, prefs: prefs)
        XCTAssertFalse(manager.isPersistent)

        manager.pinTable(hostName: "conn", databaseName: "db", tableToPin: "orders")
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn", databaseName: "db"), ["orders"])
        manager.unpinTable(hostName: "conn", databaseName: "db", tableToUnpin: "orders")
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn", databaseName: "db"), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    /// Verifies that a read-only empty file, in which the table cannot be created, still
    /// lets pins work in memory.
    func testReadOnlyStoreKeepsPinsInMemory() throws {
        try Data().write(to: URL(fileURLWithPath: storePath))
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: storePath)

        let manager = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        XCTAssertFalse(manager.isPersistent)

        manager.pinTable(hostName: "conn", databaseName: "db", tableToPin: "orders")
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn", databaseName: "db"), ["orders"])
    }

    /// Verifies that concurrent pins and unpins across hosts leave no duplicates and the
    /// same pins in memory and in the store.
    func testConcurrentPinningStaysConsistent() {
        let manager = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        let iterations = 64
        let hosts = 4

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let host = "conn\(index % hosts)"
            manager.pinTable(hostName: host, databaseName: "db", tableToPin: "table\(index)")
            manager.pinTable(hostName: host, databaseName: "db", tableToPin: "shared")
            _ = manager.getPinnedTables(hostName: host, databaseName: "db")
            if index.isMultiple(of: 2) {
                manager.unpinTable(hostName: host, databaseName: "db", tableToUnpin: "table\(index)")
            }
        }

        let reopened = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        for hostIndex in 0..<hosts {
            let host = "conn\(hostIndex)"
            let pinned = manager.getPinnedTables(hostName: host, databaseName: "db")
            let expected = Set((0..<iterations)
                .filter { $0 % hosts == hostIndex && !$0.isMultiple(of: 2) }
                .map { "table\($0)" }).union(["shared"])
            XCTAssertEqual(pinned.count, Set(pinned).count, "\(host) holds duplicate pins")
            XCTAssertEqual(Set(pinned), expected, host)
            XCTAssertEqual(Set(reopened.getPinnedTables(hostName: host, databaseName: "db")), expected, "\(host) in the store")
        }
    }

    /// Verifies that concurrent pins and unpins without a store leave exactly the shared pin.
    func testConcurrentInMemoryPinningStaysConsistent() {
        let manager = SQLitePinnedTableManager(databasePath: nil, prefs: prefs)
        let iterations = 500

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            manager.pinTable(hostName: "conn", databaseName: "db", tableToPin: "table\(index)")
            manager.pinTable(hostName: "conn", databaseName: "db", tableToPin: "shared")
            _ = manager.getPinnedTables(hostName: "conn", databaseName: "db")
            manager.unpinTable(hostName: "conn", databaseName: "db", tableToUnpin: "table\(index)")
        }

        XCTAssertEqual(manager.getPinnedTables(hostName: "conn", databaseName: "db"), ["shared"])
    }

    /// Verifies that concurrent migrations of one tuple move its pins and record it once,
    /// never run again for it, and treat another database as its own tuple.
    func testLegacyMigrationRunsOncePerTupleUnderConcurrency() {
        let manager = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        manager.pinTable(hostName: "legacy.host", databaseName: "db", tableToPin: "orders")
        manager.pinTable(hostName: "legacy.host", databaseName: "db", tableToPin: "users")
        manager.pinTable(hostName: "conn-1", databaseName: "db", tableToPin: "users")

        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            manager.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
        }

        XCTAssertEqual(manager.getPinnedTables(hostName: "conn-1", databaseName: "db"), ["users", "orders"])
        XCTAssertEqual(manager.getPinnedTables(hostName: "legacy.host", databaseName: "db"), ["orders", "users"])
        let token = PinnedTableMigrationPlanner.migrationToken(legacyHostName: "legacy.host", connectionIdentifier: "conn-1", databaseName: "db")
        XCTAssertEqual(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey), [token].compactMap { $0 })

        // The tuple is done: a pin removed afterwards does not come back.
        manager.unpinTable(hostName: "conn-1", databaseName: "db", tableToUnpin: "orders")
        manager.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn-1", databaseName: "db"), ["users"])

        // Nor with a fresh manager reading the same store and record.
        let reopened = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        reopened.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
        XCTAssertEqual(reopened.getPinnedTables(hostName: "conn-1", databaseName: "db"), ["users"])

        // A different database of the same connection is its own tuple.
        manager.pinTable(hostName: "legacy.host", databaseName: "db2", tableToPin: "logs")
        manager.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db2")
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn-1", databaseName: "db2"), ["logs"])
        XCTAssertEqual(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey)?.count, 2)
    }

    /// Verifies that concurrent migrations of different databases all reach the migration record.
    func testConcurrentMigrationsRecordEveryTuple() {
        let databases = (0..<32).map { "db\($0)" }
        let seeding = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        for database in databases {
            seeding.pinTable(hostName: "legacy.host", databaseName: database, tableToPin: "orders")
        }

        // Several documents migrate different databases at once; every finished tuple must reach the record.
        let manager = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        DispatchQueue.concurrentPerform(iterations: databases.count) { index in
            manager.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: databases[index])
        }

        let expected = Set(databases.compactMap {
            PinnedTableMigrationPlanner.migrationToken(legacyHostName: "legacy.host", connectionIdentifier: "conn-1", databaseName: $0)
        })
        XCTAssertEqual(expected.count, databases.count)
        XCTAssertEqual(Set(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey) ?? []), expected)
    }

    /// Verifies that a user-defaults observer calling into the manager while the migration
    /// record is written does not deadlock.
    func testRecordingAMigrationDoesNotHoldTheLockWhileDefaultsObserversRun() {
        let manager = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        manager.pinTable(hostName: "legacy.host", databaseName: "db", tableToPin: "orders")

        // Setting a default notifies its observers on the setting thread, and the app's observer waits for
        // the main thread; an observer that reaches the manager must not find its lock taken.
        let observer = SADefaultsObserver { _ = manager.getPinnedTables(hostName: "conn-1", databaseName: "db") }
        let key = SQLitePinnedTableManager.migratedPinnedTablesKey
        prefs.addObserver(observer, forKeyPath: key, options: [.new], context: nil)

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            manager.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 5) == .success else {
            // Leave the stuck thread alone; only keep the observer from blocking tearDown as well.
            observer.isEnabled = false
            XCTFail("recording the migration deadlocked against a defaults observer")
            return
        }
        prefs.removeObserver(observer, forKeyPath: key)
        XCTAssertGreaterThan(observer.callCount, 0, "the observer never ran")
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn-1", databaseName: "db"), ["orders"])
    }

    /// Verifies that a store whose pins cannot be read is not used: pins stay in memory,
    /// no migration is recorded and no row is added.
    func testStoreThatOpensButCannotBeReadKeepsPinsInMemory() throws {
        // Schema version 1, so preparing the store succeeds, but the table lacks the id column the first read
        // orders by; an insert would still work, so a store kept after that read would take rows it never loaded.
        try makeSQLiteFile(at: storePath, statements: [
            "CREATE TABLE PinnedTables (hostName TEXT NOT NULL, databaseName TEXT NOT NULL, pinnedTableName TEXT NOT NULL, CONSTRAINT host_db_table UNIQUE (hostName, databaseName, pinnedTableName))",
            "INSERT INTO PinnedTables (hostName, databaseName, pinnedTableName) VALUES ('legacy.host', 'db', 'orders')",
            "PRAGMA user_version = 1",
        ])

        let manager = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        XCTAssertFalse(manager.isPersistent)
        XCTAssertEqual(manager.getPinnedTables(hostName: "legacy.host", databaseName: "db"), [])

        manager.pinTable(hostName: "conn-1", databaseName: "db", tableToPin: "users")
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn-1", databaseName: "db"), ["users"])
        manager.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
        XCTAssertNil(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey))
        XCTAssertEqual(try rowCount(inSQLiteFile: storePath, table: "PinnedTables"), 1, "only the row that was there before")
    }

    /// Verifies a store whose table exists while the schema version is still 0 - a launch that
    /// died between the two - is taken over instead of disabling persistence for good.
    func testTableWithoutItsSchemaVersionIsTakenOver() throws {
        try makeSQLiteFile(at: storePath, statements: [
            "CREATE TABLE PinnedTables (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, hostName TEXT NOT NULL, databaseName TEXT NOT NULL, pinnedTableName TEXT NOT NULL, CONSTRAINT host_db_table UNIQUE (hostName, databaseName, pinnedTableName))",
            "INSERT INTO PinnedTables (hostName, databaseName, pinnedTableName) VALUES ('conn-1', 'db', 'orders')",
        ])

        let manager = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        XCTAssertTrue(manager.isPersistent)
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn-1", databaseName: "db"), ["orders"])

        manager.pinTable(hostName: "conn-1", databaseName: "db", tableToPin: "users")
        XCTAssertEqual(try rowCount(inSQLiteFile: storePath, table: "PinnedTables"), 2)
        XCTAssertEqual(SQLitePinnedTableManager(databasePath: storePath, prefs: prefs).getPinnedTables(hostName: "conn-1", databaseName: "db").sorted(), ["orders", "users"])
    }

    /// Verifies a row without a host, database or table name fails the whole read instead of
    /// being skipped, so an incomplete pin list can never close a legacy migration.
    func testRowMissingARequiredFieldMakesTheStoreUnusable() throws {
        // A table that allows NULL in the columns the reader needs - a damaged or foreign schema.
        try makeSQLiteFile(at: storePath, statements: [
            "CREATE TABLE PinnedTables (id INTEGER PRIMARY KEY AUTOINCREMENT, hostName TEXT, databaseName TEXT, pinnedTableName TEXT, CONSTRAINT host_db_table UNIQUE (hostName, databaseName, pinnedTableName))",
            "INSERT INTO PinnedTables (hostName, databaseName, pinnedTableName) VALUES ('legacy.host', 'db', 'orders')",
            "INSERT INTO PinnedTables (hostName, databaseName, pinnedTableName) VALUES ('legacy.host', 'db', NULL)",
            "PRAGMA user_version = 1",
        ])

        let manager = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        XCTAssertFalse(manager.isPersistent)
        XCTAssertEqual(manager.getPinnedTables(hostName: "legacy.host", databaseName: "db"), [])

        manager.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
        XCTAssertNil(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey))
        XCTAssertEqual(try rowCount(inSQLiteFile: storePath, table: "PinnedTables"), 2, "no row was added")
    }

    /// Verifies that a launch without the store neither migrates nor records the tuple,
    /// and a later launch with the store does both.
    func testLegacyMigrationWaitsUntilTheStoreCanBeRead() {
        SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
            .pinTable(hostName: "legacy.host", databaseName: "db", tableToPin: "orders")

        // A launch that cannot open the store does not know the legacy pins and must not close the tuple.
        let withoutStore = SQLitePinnedTableManager(databasePath: directory.appendingPathComponent("missing/pinnedTables.db").path, prefs: prefs)
        XCTAssertFalse(withoutStore.isPersistent)
        withoutStore.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
        XCTAssertEqual(withoutStore.getPinnedTables(hostName: "conn-1", databaseName: "db"), [])
        XCTAssertNil(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey))

        // The next launch with the store back migrates and records the tuple.
        let recovered = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        recovered.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
        XCTAssertEqual(recovered.getPinnedTables(hostName: "conn-1", databaseName: "db"), ["orders"])
        XCTAssertEqual(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey)?.count, 1)
    }

    /// Verifies that a migration into a read-only store is neither recorded nor repeated
    /// within the session, and completes once the store is writable again.
    func testLegacyMigrationWaitsWhileTheStoreRejectsWrites() throws {
        SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
            .pinTable(hostName: "legacy.host", databaseName: "db", tableToPin: "orders")

        // A store that can be read but not written: the moved pin lives in memory only.
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: storePath)
        let readOnly = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        XCTAssertTrue(readOnly.isPersistent)
        readOnly.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
        XCTAssertEqual(readOnly.getPinnedTables(hostName: "conn-1", databaseName: "db"), ["orders"])
        XCTAssertNil(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey))
        // Unpinning in that session sticks: refreshing the table list migrates again, which must not restore the
        // pin, and still does not claim success.
        readOnly.unpinTable(hostName: "conn-1", databaseName: "db", tableToUnpin: "orders")
        readOnly.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
        XCTAssertEqual(readOnly.getPinnedTables(hostName: "conn-1", databaseName: "db"), [])
        XCTAssertNil(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey))

        // The next launch that can write moves the pin into the store and records the tuple.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storePath)
        let writable = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        writable.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
        XCTAssertEqual(writable.getPinnedTables(hostName: "conn-1", databaseName: "db"), ["orders"])
        XCTAssertEqual(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey)?.count, 1)
        XCTAssertEqual(SQLitePinnedTableManager(databasePath: storePath, prefs: prefs).getPinnedTables(hostName: "conn-1", databaseName: "db"), ["orders"])
    }

    /// Verifies that a pin refused earlier for another database does not keep a stored
    /// migration from being recorded.
    func testARefusedWriteElsewhereDoesNotHoldBackAStoredMigration() throws {
        SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
            .pinTable(hostName: "legacy.host", databaseName: "db2", tableToPin: "logs")
        let manager = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)

        // An unrelated pin fails while the file is read-only ...
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: storePath)
        manager.pinTable(hostName: "conn-1", databaseName: "db", tableToPin: "orders")
        // ... and the store is writable again when another database migrates.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storePath)
        manager.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db2")
        XCTAssertEqual(manager.getPinnedTables(hostName: "conn-1", databaseName: "db2"), ["logs"])
        XCTAssertEqual(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey)?.count, 1)

        // Unpinning the migrated table survives a relaunch: the migration does not run again.
        manager.unpinTable(hostName: "conn-1", databaseName: "db2", tableToUnpin: "logs")
        let relaunched = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        relaunched.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db2")
        XCTAssertEqual(relaunched.getPinnedTables(hostName: "conn-1", databaseName: "db2"), [])
    }

    /// Verifies that a moved pin another manager stored first counts as stored, so both
    /// managers record the migration.
    func testPinAlreadyStoredByAnotherManagerStillCompletesTheMigration() throws {
        SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
            .pinTable(hostName: "legacy.host", databaseName: "db", tableToPin: "orders")

        // Two managers read the store before either migrates; the second one's insert hits the unique constraint.
        let first = SQLitePinnedTableManager(databasePath: storePath, prefs: prefs)
        let secondPrefsName = "SASQLitePinnedTableManagerTests-second-\(UUID().uuidString)"
        let secondPrefs = try XCTUnwrap(UserDefaults(suiteName: secondPrefsName))
        defer { secondPrefs.removePersistentDomain(forName: secondPrefsName) }
        let second = SQLitePinnedTableManager(databasePath: storePath, prefs: secondPrefs)

        first.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")
        second.migratePinnedTablesFromLegacyHost("legacy.host", toConnectionIdentifier: "conn-1", databaseName: "db")

        XCTAssertEqual(prefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey)?.count, 1)
        XCTAssertEqual(secondPrefs.stringArray(forKey: SQLitePinnedTableManager.migratedPinnedTablesKey)?.count, 1, "a row that is already there is not a rejected write")
        XCTAssertEqual(SQLitePinnedTableManager(databasePath: storePath, prefs: prefs).getPinnedTables(hostName: "conn-1", databaseName: "db"), ["orders"])
    }
}

/// A key-value observer of a user default that runs a block on the thread
/// that changed the default, as the app's defaults observer does.
private final class SADefaultsObserver: NSObject {
    private let lock = NSLock()
    private let onChange: () -> Void
    private var enabled = true
    private var calls = 0

    /// Creates an observer that runs `onChange` for every change it is notified of
    /// while it is enabled.
    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
    }

    /// Whether a change still runs the block.
    var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue } }
    }

    /// How often the block ran.
    var callCount: Int {
        lock.withLock { calls }
    }

    /// Runs the block and counts the call, unless the observer has been disabled.
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard isEnabled else {
            return
        }
        onChange()
        lock.withLock { calls += 1 }
    }
}

/// Creates an SQLite file at `path` and runs `statements` in it.
private func makeSQLiteFile(at path: String, statements: [String]) throws {
    let db = FMDatabase(path: path)
    guard db.open() else {
        throw db.lastError()
    }
    defer { db.close() }
    for statement in statements {
        try db.executeUpdate(statement, values: nil)
    }
}

/// The number of rows in `table` of the SQLite file at `path`.
private func rowCount(inSQLiteFile path: String, table: String) throws -> Int {
    let db = FMDatabase(path: path)
    guard db.open() else {
        throw db.lastError()
    }
    defer { db.close() }
    let rs = try db.executeQuery("SELECT COUNT(*) FROM \(table)", values: nil)
    defer { rs.close() }
    guard rs.next() else {
        return -1
    }
    return Int(rs.int(forColumnIndex: 0))
}
