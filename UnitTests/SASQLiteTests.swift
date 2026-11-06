import SQLite3
import XCTest

final class SASQLiteTests: XCTestCase {
    private var directory: URL!
    private var database: SASQLiteConnection!
    private var cancellation: SASQLiteCancellation!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        database = try SASQLiteConnection(url: file("source.sqlite"), readOnly: false, create: true)
        cancellation = SASQLiteCancellation()
    }

    override func tearDownWithError() throws {
        database = nil
        try FileManager.default.removeItem(at: directory)
    }

    func testOpenModesAndInvalidFiles() throws {
        let url = file("source.sqlite")
        XCTAssertThrowsError(try SASQLiteConnection(url: url, readOnly: false, create: true))
        XCTAssertThrowsError(try SASQLiteConnection(url: file("missing.sqlite"), readOnly: false))
        let invalid = file("invalid.sqlite")
        try Data("this is not a database".utf8).write(to: invalid)
        XCTAssertThrowsError(try SASQLiteConnection(url: invalid, readOnly: true))
        let readOnly = try SASQLiteConnection(url: url, readOnly: true)
        XCTAssertEqual(try readOnly.query("SELECT 1").rows, [[.integer(1)]])
        XCTAssertThrowsError(try readOnly.query("CREATE TABLE t(a)"))
    }

    func testMetadataAndCompositeWithoutRowIDEditing() throws {
        try run("""
            CREATE TABLE parent(id INTEGER PRIMARY KEY);
            CREATE TABLE "odd "" name" (a TEXT COLLATE NOCASE, b INT, payload BLOB, p INTEGER REFERENCES parent(id),
                g TEXT GENERATED ALWAYS AS (a || b), PRIMARY KEY(a,b)) WITHOUT ROWID;
            CREATE INDEX payload_idx ON "odd "" name"(payload);
            CREATE VIEW sample AS SELECT a FROM "odd "" name";
            CREATE TRIGGER sample_insert AFTER INSERT ON "odd "" name" BEGIN SELECT 'a;b'; SELECT 2; END;
            """)
        let object = try XCTUnwrap(database.objects().first { $0.name == "odd \" name" })
        let structure = try database.structure(object)
        XCTAssertTrue(object.withoutRowID)
        XCTAssertEqual(structure.primaryKey.map(\.name), ["a", "b"])
        XCTAssertEqual(structure.indexes.rows.count, 2)
        XCTAssertEqual(structure.foreignKeys.rows.count, 1)
        XCTAssertEqual(structure.triggers.rows.count, 1)
        XCTAssertEqual(structure.writableColumns.map(\.name), ["a", "b", "payload", "p"])
        try database.insert([0: .init("hé💾"), 1: .integer(5), 2: .blob(Data())], into: structure)
        let row = try XCTUnwrap(database.page(object, offset: 0, size: 1).rows.first)
        XCTAssertEqual(row.values, [.init("hé💾"), .integer(5), .blob(Data()), .null, .init("hé💾5")])
        try database.update([0: .init("Hé💾"), 2: .blob(Data([0, 255]))], row: row, in: structure)
        let edited = try XCTUnwrap(database.page(object, offset: 0, size: 1).rows.first)
        XCTAssertEqual(edited.values[2], .blob(Data([0, 255])))
        try database.delete(edited, in: structure)
        XCTAssertTrue(try database.page(object, offset: 0, size: 1).rows.isEmpty)
    }

    func testPaginationAndShadowedRowID() throws {
        try run("CREATE TABLE t(rowid TEXT, a TEXT); INSERT INTO t VALUES ('same',''), ('same',NULL), ('same','third');")
        let object = try XCTUnwrap(database.objects().first)
        let first = try database.page(object, offset: 0, size: 2)
        let next = try database.page(object, offset: 2, size: 2)
        XCTAssertTrue(first.hasMore)
        XCTAssertFalse(next.hasMore)
        XCTAssertEqual(first.structure.accessibleRowID, "_rowid_")
        XCTAssertEqual(first.rows.map { $0.values[1] }, [.init(""), .null])
        try database.delete(first.rows[1], in: first.structure)
        XCTAssertEqual(try database.query("SELECT a FROM t ORDER BY _rowid_").rows, [[.init("")], [.init("third")]])
    }

    func testConcurrentUpdateDoesNotOverwriteNewValues() throws {
        try run("CREATE TABLE t(a); INSERT INTO t VALUES('before');")
        let object = try XCTUnwrap(database.objects().first)
        let page = try database.page(object, offset: 0, size: 2)
        let other = try SASQLiteConnection(url: file("source.sqlite"), readOnly: false)
        try other.query("UPDATE t SET a='other'")
        XCTAssertThrowsError(try database.update([0: .init("mine")], row: page.rows[0], in: page.structure)) {
            guard case SASQLiteError.rowChanged = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertEqual(try database.query("SELECT a FROM t").rows, [[.init("other")]])
        XCTAssertFalse(database.inTransaction)
    }

    func testSchemaChangesAndIdentifierQuoting() throws {
        let column = SASQLiteColumnDefinition(name: "a\"b", type: .text, notNull: false, primaryKey: false)
        try database.apply(.createTable("a\"table", [column]))
        let original = try XCTUnwrap(database.objects().first)
        let definition = SASQLiteColumnDefinition(name: "key", type: .integer, notNull: false, primaryKey: false)
        try database.apply(.addColumn(original, definition))
        let key = try XCTUnwrap(database.structure(original).columns.last)
        try database.apply(.renameColumn(original, key, "new key"))
        let renamed = try XCTUnwrap(database.structure(original).columns.last)
        XCTAssertEqual(renamed.name, "new key")
        try database.apply(.dropColumn(original, renamed))
        try database.apply(.renameTable(original, "other"))
        try database.apply(.dropObject(XCTUnwrap(database.objects().first)))
        XCTAssertTrue(try database.objects().isEmpty)
    }

    func testScriptReturnsResultsBeforeErrorAndFinishesReturningWrites() throws {
        let results = try database.runScript("""
            CREATE TABLE t(a);
            INSERT INTO t VALUES(1),(2),(3) RETURNING a;
            SELECT count(*) FROM t; SELECT missing FROM t;
            """, limit: 1, cancellation: cancellation)
        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(results[1].result?.rows, [[.integer(1)]])
        XCTAssertEqual(results[1].result?.truncated, true)
        XCTAssertEqual(results[1].result?.changedRows, 3)
        XCTAssertNotNil(results[3].error)
        XCTAssertEqual(try database.query("SELECT count(*) FROM t").rows, [[.integer(3)]])
    }

    func testRunningQueryCanBeCancelled() throws {
        let signal = cancellation!
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { signal.cancel() }
        XCTAssertThrowsError(try database.withCancellation(signal) {
            try database.query("""
                WITH RECURSIVE long(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM long WHERE x < 1000000000)
                SELECT sum(x) FROM long
                """)
        }) {
            guard case SASQLiteError.cancelled = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertEqual(try database.query("SELECT 1").rows, [[.integer(1)]])
    }

    func testCancelledSQLImportRollsBackEarlierStatements() throws {
        let input = file("long.sql")
        try Data("""
            CREATE TABLE t(a);
            INSERT INTO t VALUES(42);
            WITH RECURSIVE long(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM long WHERE x < 1000000000)
            INSERT INTO t SELECT sum(x) FROM long;
            """.utf8).write(to: input)
        let signal = cancellation!
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { signal.cancel() }
        XCTAssertThrowsError(try database.withCancellation(signal) {
            try database.importSQL(input, cancellation: signal)
        }) {
            guard case SASQLiteError.cancelled = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertFalse(database.inTransaction)
        XCTAssertTrue(try database.objects().isEmpty)
        XCTAssertEqual(try database.query("PRAGMA foreign_keys").rows, [[.integer(1)]])
    }

    func testSQLDumpRoundTripPreservesSchemaAndTypes() throws {
        try run("""
            CREATE TABLE t(id INTEGER PRIMARY KEY AUTOINCREMENT, data, generated AS (typeof(data)));
            INSERT INTO t(data) VALUES(NULL), (''), (X''), (X'00FF'), (CAST(X'610062' AS TEXT)), (1.25), ('O''Brien 🐈');
            CREATE INDEX idx ON t(data);
            CREATE VIEW v AS SELECT data FROM t;
            CREATE TRIGGER log AFTER INSERT ON t BEGIN SELECT ';;'; SELECT 2; END;
            UPDATE sqlite_sequence SET seq=90 WHERE name='t';
            CREATE TABLE implicit_key(data TEXT);
            INSERT INTO implicit_key(rowid, data) VALUES(75, 'row identity');
            """)
        let dump = file("dump.sql")
        try database.exportSQL(to: dump, cancellation: cancellation)
        let restored = try SASQLiteConnection(url: file("restore.sqlite"), readOnly: false, create: true)
        try restored.importSQL(dump, cancellation: cancellation)
        XCTAssertEqual(try restored.query("SELECT * FROM t ORDER BY id").rows, try database.query("SELECT * FROM t ORDER BY id").rows)
        XCTAssertEqual(try restored.query("SELECT type,name,sql FROM sqlite_schema ORDER BY name").rows,
                       try database.query("SELECT type,name,sql FROM sqlite_schema ORDER BY name").rows)
        XCTAssertEqual(try restored.query("SELECT seq FROM sqlite_sequence").rows, [[.integer(90)]])
        XCTAssertEqual(try restored.query("SELECT rowid FROM implicit_key").rows, [[.integer(75)]])
        XCTAssertThrowsError(try database.exportSQL(to: file("source.sqlite"), cancellation: cancellation))
    }

    func testImportSQLRollsBackErrorsAndRejectsExternalDatabases() throws {
        try run("CREATE TABLE t(id INTEGER PRIMARY KEY);")
        let input = file("bad.sql")
        for sql in [
            "BEGIN; INSERT INTO t VALUES(1); INSERT INTO t VALUES(1); COMMIT;",
            "INSERT INTO t VALUES(1); ATTACH 'external.sqlite' AS external;",
            "INSERT INTO t VALUES(1); PRAGMA journal_mode=OFF;",
            "BEGIN; INSERT INTO t VALUES(1);",
            "BEGIN; INSERT INTO t VALUES(1); COMMIT; INSERT INTO t VALUES(2);"
        ] {
            try Data(sql.utf8).write(to: input)
            XCTAssertThrowsError(try database.importSQL(input, cancellation: cancellation), sql)
            XCTAssertFalse(database.inTransaction)
            XCTAssertTrue(try database.query("SELECT * FROM t").rows.isEmpty)
        }
    }

    func testImportSQLChecksForeignKeysBeforeCommitting() throws {
        let input = file("related.sql")
        let schema = """
            PRAGMA foreign_keys=OFF;
            BEGIN TRANSACTION;
            CREATE TABLE child(parent_id REFERENCES parent(id));
            INSERT INTO child VALUES(42);
            CREATE TABLE parent(id INTEGER PRIMARY KEY);
            """
        try Data((schema + "\nCOMMIT;").utf8).write(to: input)
        XCTAssertThrowsError(try database.importSQL(input, cancellation: cancellation))
        XCTAssertTrue(try database.objects().isEmpty)
        try Data((schema + "\nINSERT INTO parent VALUES(42); COMMIT;").utf8).write(to: input)
        try database.importSQL(input, cancellation: cancellation)
        XCTAssertEqual(try database.query("SELECT parent_id FROM child").rows, [[.integer(42)]])
        XCTAssertEqual(try database.query("PRAGMA foreign_keys").rows, [[.integer(1)]])
    }

    func testCSVRoundTripAndColumnMapping() throws {
        try run(#"""
            CREATE TABLE t(a TEXT, b TEXT, c TEXT);
            INSERT INTO t VALUES('é,💾', NULL, ''), ('\N','"quoted"' || char(13, 10) || 'next','c');
            """#)
        let object = try XCTUnwrap(database.objects().first)
        let csv = file("data.csv")
        try database.exportCSV(object, to: csv, cancellation: cancellation)
        try database.importCSV(csv, into: .newTable("roundtrip", columns: ["a", "b", "c"]), hasHeader: true, cancellation: cancellation)
        XCTAssertEqual(try database.query("SELECT * FROM roundtrip").rows, try database.query("SELECT * FROM t").rows)
        try run("CREATE TABLE mapped(z, y, with_default DEFAULT 'default');")
        let mapped = try XCTUnwrap(database.objects().first { $0.name == "mapped" })
        let structure = try database.structure(mapped)
        try database.importCSV(csv, into: .existing(structure, mapping: [1, nil, 0]), hasHeader: true, cancellation: cancellation)
        XCTAssertEqual(try database.query("SELECT * FROM mapped LIMIT 1").rows, [[.init(""), .init("é,💾"), .init("default")]])
    }

    func testCSVFailureRollsBackNewTableAndImportedRecords() throws {
        let input = file("bad.csv")
        try Data("a,b\r\nfirst,ok\r\nbad\r\n".utf8).write(to: input)
        XCTAssertThrowsError(try database.importCSV(input, into: .newTable("bad", columns: ["a", "b"]),
                                                   hasHeader: true, cancellation: cancellation))
        XCTAssertTrue(try database.objects().isEmpty)
    }

    func testBackupIncludesCommittedWALAndRestoresToNewFile() throws {
        try run("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE t(a); INSERT INTO t VALUES(42);")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file("source.sqlite-wal").path))
        let backup = file("backup.sqlite")
        try database.backup(to: backup, cancellation: cancellation)
        let copy = try SASQLiteConnection(url: backup, readOnly: true)
        XCTAssertEqual(try copy.query("SELECT a FROM t").rows, [[.integer(42)]])
        XCTAssertThrowsError(try database.backup(to: backup, cancellation: cancellation))
        let restore = file("restored.sqlite")
        try copy.backup(to: restore, cancellation: cancellation)
        let restored = try SASQLiteConnection(url: restore, readOnly: false)
        try restored.query("UPDATE t SET a=99")
        XCTAssertEqual(try database.query("SELECT a FROM t").rows, [[.integer(42)]])
        XCTAssertEqual(try restored.query("SELECT a FROM t").rows, [[.integer(99)]])
    }

    private func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

    private func run(_ sql: String, file: StaticString = #filePath, line: UInt = #line) throws {
        for result in try database.runScript(sql, cancellation: cancellation) {
            XCTAssertNil(result.error, file: file, line: line)
        }
    }
}
