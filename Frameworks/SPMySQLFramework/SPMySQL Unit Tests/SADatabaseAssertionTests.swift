//
//  SADatabaseAssertionTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Dispatch
import Foundation
import XCTest
@testable import SPMySQL

final class SADatabaseAssertionTests: XCTestCase {
    private let latin1CharacterSet = Data("latin1".utf8)

    func testDisabledAssertionDoesNotConsultOrMutateSession() {
        let error = assertDatabase(
            "target",
            required: false,
            selectedDatabaseName: "other",
            databaseStateKnown: true,
            databaseIsSelected: true,
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("Unexpected charset query") },
            executeSQL: { _ in unexpectedError("Unexpected SQL") },
            selectDatabase: { _ in unexpectedError("Unexpected database selection") }
        )

        XCTAssertNil(error)
    }

    func testMatchingKnownDatabaseAvoidsAllSessionMutations() {
        let database = "tracked_é"
        let error = assertDatabase(
            database,
            selectedDatabaseName: database,
            databaseStateKnown: true,
            databaseIsSelected: true,
            stringEncodingProvider: { _ in unexpectedEncoding("UTF-8 match should not require charset mapping") },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("Unexpected charset query") },
            executeSQL: { _ in unexpectedError("Unexpected SQL") },
            selectDatabase: { _ in unexpectedError("Unexpected database selection") }
        )

        XCTAssertNil(error)
    }

    func testSelectedDatabaseWithUnknownNameIsReselected() {
        var selectedDatabase: Data?

        let error = assertDatabase(
            "target",
            selectedDatabaseName: nil,
            databaseStateKnown: true,
            databaseIsSelected: true,
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("ASCII names should not query the charset") },
            executeSQL: { _ in unexpectedError("Unexpected SQL") },
            selectDatabase: { data in
                selectedDatabase = data
                return nil
            }
        )

        XCTAssertNil(error)
        XCTAssertEqual(selectedDatabase, nullTerminated(Data("target".utf8)))
    }

    func testUnknownDatabaseStateSelectsRequestedDatabase() {
        var selectedDatabase: Data?

        let error = assertDatabase(
            "target",
            selectedDatabaseName: nil,
            databaseStateKnown: false,
            databaseIsSelected: false,
            queryActiveDatabaseData: { unexpectedLookup("Named contexts should reselect without querying") },
            queryClientCharacterSetData: { unexpectedLookup("ASCII names should not query the charset") },
            executeSQL: { _ in unexpectedError("Unexpected SQL") },
            selectDatabase: { data in
                selectedDatabase = data
                return nil
            }
        )

        XCTAssertNil(error)
        XCTAssertEqual(selectedDatabase, nullTerminated(Data("target".utf8)))
    }

    func testExplicitEmptyContextUsesTrackedState() {
        let selectedError = assertDatabase(
            nil,
            selectedDatabaseName: "selected",
            databaseStateKnown: true,
            databaseIsSelected: true,
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") }
        )
        let emptyError = assertDatabase(
            nil,
            selectedDatabaseName: nil,
            databaseStateKnown: true,
            databaseIsSelected: false,
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") }
        )

        XCTAssertEqual(selectedError?.errorID, 1046)
        XCTAssertEqual(selectedError?.message, "A database is unexpectedly selected on this connection.")
        XCTAssertEqual(selectedError?.sqlState, "3D000")
        XCTAssertNil(emptyError)
    }

    func testExplicitEmptyContextQueriesLiveStateOnLegacyConnection() {
        var queryCount = 0
        let selectedError = assertDatabase(
            nil,
            selectedDatabaseName: nil,
            databaseStateKnown: false,
            databaseIsSelected: false,
            queryActiveDatabaseData: {
                queryCount += 1
                return .init(data: Data("selected".utf8), error: nil)
            }
        )
        let emptyError = assertDatabase(
            nil,
            selectedDatabaseName: nil,
            databaseStateKnown: false,
            databaseIsSelected: false,
            queryActiveDatabaseData: {
                queryCount += 1
                return .init(data: nil, error: nil)
            }
        )

        XCTAssertEqual(selectedError?.errorID, 1046)
        XCTAssertNil(emptyError)
        XCTAssertEqual(queryCount, 2)
    }

    func testSelectionUsesLiveClientCharset() throws {
        let database = "legacy_é"
        let expectedSelection = try XCTUnwrap(database.data(using: .windowsCP1252))
        var selectedDatabase: Data?
        var charsetQueryCount = 0

        let error = assertDatabase(
            database,
            selectedDatabaseName: "other",
            databaseStateKnown: true,
            databaseIsSelected: true,
            stringEncodingProvider: { name in
                XCTAssertEqual(name, "latin1")
                return String.Encoding.windowsCP1252.rawValue
            },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: {
                charsetQueryCount += 1
                return .init(data: self.latin1CharacterSet, error: nil)
            },
            executeSQL: { _ in unexpectedError("Representable name should not change the charset") },
            selectDatabase: { data in
                selectedDatabase = data
                return nil
            }
        )

        XCTAssertNil(error)
        XCTAssertEqual(charsetQueryCount, 1)
        XCTAssertEqual(selectedDatabase, nullTerminated(expectedSelection))
    }

    func testUnrepresentableNameTemporarilyUsesUTF8AndRestoresLiveCharset() {
        let database = "legacy_日"
        var actions: [String] = []

        let error = assertDatabase(
            database,
            selectedDatabaseName: "other",
            databaseStateKnown: true,
            databaseIsSelected: true,
            stringEncodingProvider: { _ in String.Encoding.windowsCP1252.rawValue },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { .init(data: self.latin1CharacterSet, error: nil) },
            executeSQL: { sql in
                actions.append(sql)
                return nil
            },
            selectDatabase: { data in
                actions.append("SELECT:\(data.base64EncodedString())")
                return nil
            }
        )

        XCTAssertNil(error)
        XCTAssertEqual(actions, [
            "SET CHARACTER_SET_CLIENT=utf8mb4",
            "SELECT:\(nullTerminated(Data(database.utf8)).base64EncodedString())",
            "SET CHARACTER_SET_CLIENT=latin1"
        ])
    }

    func testSelectionErrorWinsOverRestoreError() {
        let selectionError = SADatabaseAssertionError(errorID: 1049, message: "selection", sqlState: "42000")
        let restoreError = SADatabaseAssertionError(errorID: 2013, message: "restore", sqlState: "HY000")

        let error = assertDatabase(
            "legacy_日",
            selectedDatabaseName: "other",
            databaseStateKnown: true,
            databaseIsSelected: true,
            stringEncodingProvider: { _ in String.Encoding.windowsCP1252.rawValue },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { .init(data: self.latin1CharacterSet, error: nil) },
            executeSQL: { sql in sql.hasSuffix("utf8mb4") ? nil : restoreError },
            selectDatabase: { _ in selectionError }
        )

        XCTAssertTrue(error === selectionError)
    }

    func testRestoreErrorStopsOtherwiseSuccessfulQuery() {
        let restoreError = SADatabaseAssertionError(errorID: 2013, message: "restore", sqlState: "HY000")

        let error = assertDatabase(
            "legacy_日",
            selectedDatabaseName: "other",
            databaseStateKnown: true,
            databaseIsSelected: true,
            stringEncodingProvider: { _ in String.Encoding.windowsCP1252.rawValue },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { .init(data: self.latin1CharacterSet, error: nil) },
            executeSQL: { sql in sql.hasSuffix("utf8mb4") ? nil : restoreError },
            selectDatabase: { _ in nil }
        )

        XCTAssertTrue(error === restoreError)
    }

    func testClientCharsetLookupErrorIsPreserved() {
        let lookupError = SADatabaseAssertionError(errorID: 2013, message: "lookup", sqlState: "HY000")

        let error = assertDatabase(
            "legacy_日",
            selectedDatabaseName: "other",
            databaseStateKnown: true,
            databaseIsSelected: true,
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { .init(data: nil, error: lookupError) },
            executeSQL: { _ in unexpectedError("Lookup failure must stop before SQL") },
            selectDatabase: { _ in unexpectedError("Lookup failure must stop before database selection") }
        )

        XCTAssertTrue(error === lookupError)
    }

    func testTemporaryCharsetFailureStopsBeforeSelection() {
        let charsetError = SADatabaseAssertionError(errorID: 1227, message: "denied", sqlState: "42000")
        var statements: [String] = []

        let error = assertDatabase(
            "legacy_日",
            selectedDatabaseName: "other",
            databaseStateKnown: true,
            databaseIsSelected: true,
            stringEncodingProvider: { _ in String.Encoding.windowsCP1252.rawValue },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { .init(data: self.latin1CharacterSet, error: nil) },
            executeSQL: { sql in
                statements.append(sql)
                return charsetError
            },
            selectDatabase: { _ in unexpectedError("Failed charset change must stop before database selection") }
        )

        XCTAssertTrue(error === charsetError)
        XCTAssertEqual(statements, ["SET CHARACTER_SET_CLIENT=utf8mb4"])
    }

    func testUnsafeQueriedCharsetIsRejectedBeforeSQLConstruction() {
        let error = assertDatabase(
            "legacy_日",
            selectedDatabaseName: "other",
            databaseStateKnown: true,
            databaseIsSelected: true,
            stringEncodingProvider: { _ in unexpectedEncoding("Unsafe charset must not be mapped") },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { .init(data: Data("latin1;DROP".utf8), error: nil) },
            executeSQL: { _ in unexpectedError("Unsafe charset must not reach SQL") },
            selectDatabase: { _ in unexpectedError("Unsafe charset must not select a database") }
        )

        XCTAssertEqual(error?.errorID, 0)
        XCTAssertEqual(error?.message, "Unable to determine the connection character set before selecting the database.")
    }

    func testEmbeddedNullIsRejectedBeforeConsultingSessionState() {
        let error = assertDatabase(
            "invalid\0database",
            selectedDatabaseName: "other",
            databaseStateKnown: true,
            databaseIsSelected: true,
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("Unexpected charset query") },
            executeSQL: { _ in unexpectedError("Unexpected SQL") },
            selectDatabase: { _ in unexpectedError("Unexpected database selection") }
        )

        XCTAssertEqual(error?.errorID, 0)
        XCTAssertEqual(error?.message, "Unable to encode the database name before selecting it.")
    }

    func testDatabaseContextChangingQueriesInvalidateAssertionState() {
        XCTAssertTrue(queryMayChangeDatabaseContext("USE `target``name`"))
        XCTAssertTrue(queryMayChangeDatabaseContext("USE`target`"))
        XCTAssertTrue(queryMayChangeDatabaseContext("DROP DATABASE IF EXISTS target"))
        XCTAssertTrue(queryMayChangeDatabaseContext("DROP DATABASE`target`"))
        XCTAssertTrue(queryMayChangeDatabaseContext("DROP DATABASE IF EXISTS`target`"))
        XCTAssertTrue(queryMayChangeDatabaseContext("DROP SCHEMA target;"))
        XCTAssertTrue(queryMayChangeDatabaseContext("/*!80000 USE target */"))
    }

    func testDatabaseContextPrefixGuardSkipsOrdinaryStatements() {
        for query in [
            "INSERT INTO t VALUES (1)",
            "UPDATE t SET value = 1",
            "DELETE FROM t",
            "SELECT 1",
            "USEFUL identifier",
            "DROPLET identifier"
        ] {
            XCTAssertFalse(SADatabaseAssertion.queryCouldChangeDatabaseContext(query), query)
        }

        for query in [
            "USE target",
            " use target",
            "DROP DATABASE target",
            "drop schema target",
            "# comment\nUSE target",
            "-- comment\nUSE target",
            "/* comment */ USE target"
        ] {
            XCTAssertTrue(SADatabaseAssertion.queryCouldChangeDatabaseContext(query), query)
        }
    }

    func testCommentsAndQuotedTextDoNotInvalidateAssertionState() {
        XCTAssertFalse(queryMayChangeDatabaseContext("SELECT 'USE target'"))
        XCTAssertFalse(queryMayChangeDatabaseContext("/* USE target */ SELECT 1"))
        XCTAssertFalse(queryMayChangeDatabaseContext("-- USE target\nSELECT 1"))
        XCTAssertFalse(queryMayChangeDatabaseContext("SELECT 'DROP DATABASE target'"))
        XCTAssertEqual(
            SADatabaseAssertion.stripSQLComments(
                "SELECT 1--",
                serverVersion: 80_046,
                serverIsMariaDB: false
            ),
            "SELECT 1 "
        )
    }

    func testExecutableCommentVersionAndVendorGatesAreRespected() {
        XCTAssertFalse(queryMayChangeDatabaseContext("/*!99999 USE target */"))
        XCTAssertFalse(queryMayChangeDatabaseContext("/*M!80000 USE target */"))
        XCTAssertFalse(queryMayChangeDatabaseContext("/*!80000 USE target */", serverIsMariaDB: true))
        XCTAssertTrue(queryMayChangeDatabaseContext("/*M!80000 USE target */", serverIsMariaDB: true))
        XCTAssertFalse(queryMayChangeDatabaseContext("/*!999999999999999999999999 USE target */"))
    }

    func testMariaDBDoesNotTreatBracketsAsQuotedIdentifiers() {
        XCTAssertEqual(
            SADatabaseAssertion.stripSQLComments(
                "SELECT [/* comment */]",
                serverVersion: 101_100,
                serverIsMariaDB: true
            ),
            "SELECT [ ]"
        )
        XCTAssertFalse(
            SADatabaseAssertion.queryMayChangeDatabaseContext(
                "USE [new database]",
                serverVersion: 101_100,
                serverIsMariaDB: true
            )
        )
    }

    private func assertDatabase(
        _ databaseName: String?,
        required: Bool = true,
        selectedDatabaseName: String?,
        databaseStateKnown: Bool,
        databaseIsSelected: Bool,
        stringEncodingProvider: (String) -> UInt = { _ in String.Encoding.utf8.rawValue },
        queryActiveDatabaseData: () -> SADatabaseSessionValueLookup,
        queryClientCharacterSetData: () -> SADatabaseSessionValueLookup = { .init(data: nil, error: nil) },
        executeSQL: (String) -> SADatabaseAssertionError? = { _ in nil },
        selectDatabase: (Data) -> SADatabaseAssertionError? = { _ in nil }
    ) -> SADatabaseAssertionError? {
        SADatabaseAssertion.assertDatabase(
            databaseName,
            required: required,
            selectedDatabaseName: selectedDatabaseName,
            databaseStateKnown: databaseStateKnown,
            databaseIsSelected: databaseIsSelected,
            stringEncodingProvider: stringEncodingProvider,
            queryActiveDatabaseData: queryActiveDatabaseData,
            queryClientCharacterSetData: queryClientCharacterSetData,
            executeSQL: executeSQL,
            selectDatabase: selectDatabase
        )
    }

    private func queryMayChangeDatabaseContext(
        _ query: String,
        serverIsMariaDB: Bool = false
    ) -> Bool {
        SADatabaseAssertion.queryMayChangeDatabaseContext(
            query,
            serverVersion: 80_046,
            serverIsMariaDB: serverIsMariaDB
        )
    }

    private func unexpectedLookup(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> SADatabaseSessionValueLookup {
        XCTFail(message, file: file, line: line)
        return .init(data: nil, error: nil)
    }

    private func unexpectedError(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> SADatabaseAssertionError? {
        XCTFail(message, file: file, line: line)
        return nil
    }

    private func unexpectedEncoding(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> UInt {
        XCTFail(message, file: file, line: line)
        return 0
    }

    private func nullTerminated(_ data: Data) -> Data {
        var data = data
        data.append(0)
        return data
    }
}

private final class SADatabaseAssertionMismatchRecorder {
    private let lock = NSLock()
    private var firstMessage: String?

    func record(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        if firstMessage == nil {
            firstMessage = message
        }
    }

    var message: String? {
        lock.lock()
        defer { lock.unlock() }
        return firstMessage
    }
}

final class SADatabaseAssertionIntegrationTests: XCTestCase, SPMySQLStreamingResultStoreDelegate {
    private var resultStoreDownloadExpectation: XCTestExpectation?

    func resultStoreDidFinishLoadingData(_ resultStore: SPMySQLStreamingResultStore!) {
        resultStoreDownloadExpectation?.fulfill()
    }

    func testQueriesCanAssertDatabaseAtomicallyOnSharedConnection() throws {
        guard let connection = newLocalConnection() else {
            throw XCTSkip("No local MySQL connection configured. Set SPMYSQL_TEST_SOCKET or SPMYSQL_TEST_HOST to run this integration regression.")
        }
        guard connection.connect() else {
            throw XCTSkip("Local MySQL connection is unavailable for the database assertion regression.")
        }

        let identifier = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let databaseA = "sa_atomic_\(identifier)_a"
        let databaseB = "sa_atomic_\(identifier)_b"
        let unicodeDatabase = "sa_atomic_\(identifier)_é"
        let unrepresentableDatabase = "sa_atomic_\(identifier)_日"
        let noDatabaseContextDatabase = "sa_atomic_\(identifier)_none"
        let databases = [databaseA, databaseB, unicodeDatabase, unrepresentableDatabase, noDatabaseContextDatabase]
        var workersFinished = true

        defer {
            if workersFinished {
                _ = connection.setEncoding("utf8mb4")
                for database in databases {
                    _ = connection.queryString("DROP DATABASE IF EXISTS \(backtickQuoted(database))")
                }
                connection.disconnect()
            }
        }

        for database in databases {
            _ = connection.queryString("CREATE DATABASE \(backtickQuoted(database))")
            assertQuerySucceeded(connection)
        }

        XCTAssertTrue(connection.selectDatabase(databaseB))
        let selectedResult = connection.queryString("SELECT DATABASE()", assertingDatabase: databaseA)
        XCTAssertEqual(try row(from: selectedResult).first as? String, databaseA)
        XCTAssertEqual(
            connection.getFirstField(fromQuery: "SELECT DATABASE()", assertingDatabase: databaseA) as? String,
            databaseA
        )
        let allRows = try XCTUnwrap(
            connection.getAllRows(fromQuery: "SELECT DATABASE() AS db", assertingDatabase: databaseA)
        )
        let databaseRow = try XCTUnwrap(allRows.first as? [String: Any])
        XCTAssertEqual(databaseRow["db"] as? String, databaseA)

        let originalEncoding = try XCTUnwrap(connection.encoding())
        XCTAssertTrue(connection.setEncoding("latin1"))
        let unicodeResult = connection.queryString("SELECT DATABASE()", assertingDatabase: unicodeDatabase)
        assertQuerySucceeded(connection)
        XCTAssertEqual(try row(from: unicodeResult).first as? String, unicodeDatabase)
        XCTAssertEqual(connection.encoding(), "latin1")

        _ = connection.queryString("SELECT 1", assertingDatabase: "\(unicodeDatabase)_missing")
        XCTAssertTrue(connection.queryErrored())
        XCTAssertEqual(connection.lastErrorID(), 1049)
        XCTAssertEqual(connection.encoding(), "latin1")
        XCTAssertTrue(connection.setEncoding(originalEncoding))

        // Imports can issue SET NAMES directly, leaving the framework's cached
        // encoding different from the caller-managed server session.
        XCTAssertTrue(connection.setEncoding("latin1"))
        _ = connection.queryString("SET NAMES utf8mb4 COLLATE utf8mb4_bin")
        assertQuerySucceeded(connection)
        XCTAssertTrue(unicodeDatabase.canBeConverted(to: .windowsCP1252))
        let representableResult = connection.queryString(
            "SELECT @@character_set_client, @@character_set_results, @@character_set_connection, @@collation_connection",
            assertingDatabase: unicodeDatabase
        )
        assertQuerySucceeded(connection)
        let representableState = try row(from: representableResult)
        XCTAssertEqual(representableState[0] as? String, "utf8mb4")
        XCTAssertEqual(representableState[1] as? String, "utf8mb4")
        XCTAssertEqual(representableState[2] as? String, "utf8mb4")
        XCTAssertEqual(representableState[3] as? String, "utf8mb4_bin")

        XCTAssertFalse(unrepresentableDatabase.canBeConverted(to: .ascii))
        let callerManagedResult = connection.queryString(
            "SELECT @@character_set_client, @@character_set_results, @@character_set_connection, @@collation_connection",
            usingEncoding: String.Encoding.ascii.rawValue,
            with: SPMySQLResultAsResult,
            assertingDatabase: unrepresentableDatabase
        ) as? SPMySQLResult
        assertQuerySucceeded(connection)
        let callerManagedState = try row(from: callerManagedResult)
        XCTAssertEqual(callerManagedState[0] as? String, "utf8mb4")
        XCTAssertEqual(callerManagedState[1] as? String, "utf8mb4")
        XCTAssertEqual(callerManagedState[2] as? String, "utf8mb4")
        XCTAssertEqual(callerManagedState[3] as? String, "utf8mb4_bin")
        XCTAssertEqual(connection.encoding(), "latin1")
        XCTAssertTrue(connection.setEncoding(originalEncoding))

        // Exercise the inverse stale-cache direction: the framework cache is
        // UTF-8 while the caller-managed session expects latin1 bytes.
        _ = connection.queryString("SET NAMES latin1 COLLATE latin1_bin")
        assertQuerySucceeded(connection)
        let inverseResult = connection.queryString(
            "SELECT @@character_set_client, @@character_set_results, @@character_set_connection, @@collation_connection",
            assertingDatabase: unicodeDatabase
        )
        assertQuerySucceeded(connection)
        let inverseState = try row(from: inverseResult)
        XCTAssertEqual(inverseState[0] as? String, "latin1")
        XCTAssertEqual(inverseState[1] as? String, "latin1")
        XCTAssertEqual(inverseState[2] as? String, "latin1")
        XCTAssertEqual(inverseState[3] as? String, "latin1_bin")

        _ = connection.queryString(
            "SET CHARACTER_SET_RESULTS=NULL, CHARACTER_SET_CONNECTION=utf8mb4, COLLATION_CONNECTION=utf8mb4_bin"
        )
        assertQuerySucceeded(connection)
        let inverseUnrepresentableResult = connection.queryString(
            "SELECT @@character_set_client, @@character_set_results IS NULL, @@character_set_connection, @@collation_connection",
            assertingDatabase: unrepresentableDatabase
        )
        assertQuerySucceeded(connection)
        let inverseUnrepresentableState = try row(from: inverseUnrepresentableResult)
        XCTAssertEqual(inverseUnrepresentableState[0] as? String, "latin1")
        XCTAssertEqual(inverseUnrepresentableState[1] as? String, "1")
        XCTAssertEqual(inverseUnrepresentableState[2] as? String, "utf8mb4")
        XCTAssertEqual(inverseUnrepresentableState[3] as? String, "utf8mb4_bin")
        XCTAssertEqual(connection.encoding(), originalEncoding)

        _ = connection.queryString("SELECT 1", assertingDatabase: "\(unrepresentableDatabase)_missing")
        XCTAssertTrue(connection.queryErrored())
        XCTAssertEqual(connection.lastErrorID(), 1049)
        let failedAssertionResult = connection.queryString(
            "SELECT @@character_set_client, @@character_set_results IS NULL, @@character_set_connection, @@collation_connection"
        )
        assertQuerySucceeded(connection)
        let failedAssertionState = try row(from: failedAssertionResult)
        XCTAssertEqual(failedAssertionState[0] as? String, "latin1")
        XCTAssertEqual(failedAssertionState[1] as? String, "1")
        XCTAssertEqual(failedAssertionState[2] as? String, "utf8mb4")
        XCTAssertEqual(failedAssertionState[3] as? String, "utf8mb4_bin")

        _ = connection.queryString("SET NAMES utf8mb4")
        assertQuerySucceeded(connection)

        // Negotiating CLIENT_SESSION_TRACK does not guarantee that charset
        // variables are actually included in the tracking payload.
        let trackedSystemVariables = connection.getFirstField(
            fromQuery: "SELECT @@session.session_track_system_variables",
            assertingDatabase: nil
        ) as? String
        if !connection.queryErrored(), let trackedSystemVariables, !trackedSystemVariables.isEmpty {
            _ = connection.queryString("SELECT DATABASE()", assertingDatabase: databaseA)
            assertQuerySucceeded(connection)
            _ = connection.queryString("SET SESSION session_track_system_variables=''")
            assertQuerySucceeded(connection)
            _ = connection.queryString("SET NAMES latin1")
            assertQuerySucceeded(connection)

            XCTAssertEqual(
                connection.getFirstField(
                    fromQuery: "SELECT @@character_set_client",
                    assertingDatabase: unicodeDatabase
                ) as? String,
                "latin1"
            )
            assertQuerySucceeded(connection)

            _ = connection.queryString(
                "SET SESSION session_track_system_variables=\(tickQuoted(trackedSystemVariables))"
            )
            assertQuerySucceeded(connection)
            _ = connection.queryString("SET NAMES utf8mb4")
            assertQuerySucceeded(connection)
        }

        // The schema tracker can also be disabled while the capability remains
        // negotiated. A successful USE must invalidate assertion state.
        let schemaTrackingEnabled = connection.getFirstField(
            fromQuery: "SELECT @@session.session_track_schema",
            assertingDatabase: nil
        ) as? String
        if !connection.queryErrored(), let schemaTrackingEnabled, !schemaTrackingEnabled.isEmpty {
            _ = connection.queryString("SELECT DATABASE()", assertingDatabase: databaseA)
            assertQuerySucceeded(connection)
            _ = connection.queryString("SET SESSION session_track_schema=OFF")
            assertQuerySucceeded(connection)
            _ = connection.queryString("USE \(backtickQuoted(databaseB))")
            assertQuerySucceeded(connection)

            XCTAssertEqual(
                connection.getFirstField(fromQuery: "SELECT DATABASE()", assertingDatabase: databaseA) as? String,
                databaseA
            )
            assertQuerySucceeded(connection)

            let restoreValue = (Int(schemaTrackingEnabled) ?? 0) != 0 ? "ON" : "OFF"
            _ = connection.queryString("SET SESSION session_track_schema=\(restoreValue)")
            assertQuerySucceeded(connection)
        }

        XCTAssertTrue(connection.setEncoding("latin2"))
        let expectedConnectionCharacterSet = connection.getFirstField(
            fromQuery: "SELECT @@character_set_connection",
            assertingDatabase: nil
        ) as? String
        XCTAssertTrue(connection.setEncodingUsesLatin1Transport(true))
        let latin1TransportResult = connection.queryString(
            "SELECT DATABASE()",
            assertingDatabase: unicodeDatabase
        )
        assertQuerySucceeded(connection)
        XCTAssertEqual(try row(from: latin1TransportResult).first as? String, unicodeDatabase)
        XCTAssertEqual(connection.encoding(), "latin2")
        XCTAssertTrue(connection.encodingUsesLatin1Transport())

        let transportResult = connection.queryString(
            "SELECT @@character_set_client, @@character_set_results, @@character_set_connection"
        )
        let transportState = try row(from: transportResult)
        XCTAssertEqual(transportState[0] as? String, "latin1")
        XCTAssertEqual(transportState[1] as? String, "latin1")
        XCTAssertEqual(transportState[2] as? String, expectedConnectionCharacterSet)
        XCTAssertTrue(connection.setEncodingUsesLatin1Transport(false))
        XCTAssertTrue(connection.setEncoding(originalEncoding))

        // A matching assertion must not issue a hidden query or redundant
        // mysql_select_db that overwrites diagnostics inspected by the next SQL.
        _ = connection.queryString(
            "CREATE TABLE assertion_diagnostics (id INT PRIMARY KEY, value INT)",
            assertingDatabase: unicodeDatabase
        )
        assertQuerySucceeded(connection)
        _ = connection.queryString(
            "INSERT INTO assertion_diagnostics VALUES (1, 0)",
            assertingDatabase: unicodeDatabase
        )
        assertQuerySucceeded(connection)
        _ = connection.queryString(
            "UPDATE assertion_diagnostics SET value = value + 1 WHERE id = 1",
            assertingDatabase: unicodeDatabase
        )
        assertQuerySucceeded(connection)
        XCTAssertEqual(
            connection.getFirstField(fromQuery: "SELECT ROW_COUNT()", assertingDatabase: unicodeDatabase) as? String,
            "1"
        )

        _ = connection.queryString(
            "DROP TABLE IF EXISTS assertion_missing_table",
            assertingDatabase: unicodeDatabase
        )
        assertQuerySucceeded(connection)
        let warningsResult = connection.queryString("SHOW WARNINGS", assertingDatabase: unicodeDatabase)
        assertQuerySucceeded(connection)
        XCTAssertGreaterThan(warningsResult?.numberOfRows() ?? 0, 0)

        _ = connection.queryString(
            "SELECT SQL_CALC_FOUND_ROWS value FROM assertion_diagnostics UNION ALL SELECT 2 UNION ALL SELECT 3 LIMIT 1",
            assertingDatabase: unicodeDatabase
        )
        assertQuerySucceeded(connection)
        XCTAssertEqual(
            connection.getFirstField(fromQuery: "SELECT FOUND_ROWS()", assertingDatabase: unicodeDatabase) as? String,
            "3"
        )

        // The context API treats nil as an explicit no-database state. The
        // legacy assertingDatabase:nil API remains intentionally nonasserting.
        XCTAssertTrue(connection.selectDatabase(noDatabaseContextDatabase))
        _ = connection.queryString(
            "DROP DATABASE \(backtickQuoted(noDatabaseContextDatabase))",
            assertingDatabase: noDatabaseContextDatabase
        )
        assertQuerySucceeded(connection)
        let noDatabaseResult = connection.queryString("SELECT DATABASE()", assertingDatabaseContext: nil)
        assertQuerySucceeded(connection)
        XCTAssertTrue(try row(from: noDatabaseResult).first is NSNull)

        _ = connection.queryString(
            "CREATE TABLE assertion_no_database_guard (id INT)",
            assertingDatabaseContext: nil
        )
        XCTAssertTrue(connection.queryErrored())
        XCTAssertEqual(connection.lastErrorID(), 1046)

        XCTAssertTrue(connection.selectDatabase(databaseB))
        _ = connection.queryString(
            "CREATE TABLE assertion_no_database_guard (id INT)",
            assertingDatabaseContext: nil
        )
        XCTAssertTrue(connection.queryErrored())
        XCTAssertEqual(connection.lastErrorID(), 1046)
        XCTAssertEqual(connection.lastSqlstate(), "3D000")
        XCTAssertEqual(connection.lastErrorMessage(), "A database is unexpectedly selected on this connection.")
        XCTAssertEqual(
            connection.getFirstField(fromQuery: "SELECT DATABASE()", assertingDatabase: nil) as? String,
            databaseB
        )
        XCTAssertEqual(
            connection.getFirstField(
                fromQuery: "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'assertion_no_database_guard'",
                assertingDatabase: databaseB
            ) as? String,
            "0"
        )

        let resultStore = try XCTUnwrap(
            connection.resultStore(fromQueryString: "SELECT DATABASE()", assertingDatabase: databaseA)
        )
        resultStoreDownloadExpectation = expectation(description: "Streaming result store download completes")
        resultStore.delegate = self
        resultStore.startDownload()
        let resultStoreWait = XCTWaiter.wait(
            for: [try XCTUnwrap(resultStoreDownloadExpectation)],
            timeout: 5
        )
        XCTAssertEqual(resultStoreWait, .completed)
        if resultStoreWait == .completed {
            XCTAssertEqual(resultStore.numberOfRows(), 1)
            let resultStoreRow = resultStore.rowContents(at: 0) as? [Any]
            XCTAssertEqual(resultStoreRow?.first as? String, databaseA)
        }
        resultStore.cancelLoad()
        resultStore.delegate = nil
        resultStoreDownloadExpectation = nil

        let mismatchRecorder = SADatabaseAssertionMismatchRecorder()
        let workerGroup = DispatchGroup()
        let workerQueue = DispatchQueue.global(qos: .userInitiated)
        let iterations = 500
        workersFinished = false

        workerQueue.async(group: workerGroup) {
            for iteration in 0..<iterations {
                let shouldStop = autoreleasepool {
                    let result = connection.queryString("SELECT DATABASE()", assertingDatabase: databaseA)
                    let selectedDatabase = (result?.getRowAsArray() as? [Any])?.first as? String
                    guard selectedDatabase == databaseA else {
                        mismatchRecorder.record(
                            "Expected \(databaseA), got \(selectedDatabase ?? "nil") at iteration \(iteration)"
                        )
                        return true
                    }
                    return false
                }
                if shouldStop { break }
            }
        }

        workerQueue.async(group: workerGroup) {
            for iteration in 0..<iterations {
                let shouldStop = autoreleasepool {
                    guard connection.selectDatabase(databaseB) else {
                        mismatchRecorder.record(
                            "selectDatabase failed at iteration \(iteration): \(connection.lastErrorMessage() ?? "unknown error")"
                        )
                        return true
                    }
                    return false
                }
                if shouldStop { break }
            }
        }

        let workerWait = workerGroup.wait(timeout: .now() + 30)
        workersFinished = workerWait == .success
        XCTAssertEqual(workerWait, .success)
        XCTAssertNil(mismatchRecorder.message)
    }

    private func newLocalConnection() -> SPMySQLConnection? {
        let environment = ProcessInfo.processInfo.environment
        var socketPath = environment["SPMYSQL_TEST_SOCKET"]
        let testHost = environment["SPMYSQL_TEST_HOST"]

        if (socketPath?.isEmpty ?? true), (testHost?.isEmpty ?? true) {
            socketPath = ["/tmp/mysql.sock", "/opt/homebrew/var/mysql/mysql.sock"]
                .first(where: { FileManager.default.fileExists(atPath: $0) })
        }

        let connection = SPMySQLConnection()
        let testUser = environment["SPMYSQL_TEST_USER"]
        connection.username = testUser?.isEmpty == false ? testUser : "root"
        connection.password = environment["SPMYSQL_TEST_PASSWORD"]
        connection.useKeepAlive = false

        if let testHost, !testHost.isEmpty {
            connection.useSocket = false
            connection.host = testHost
            if let port = environment["SPMYSQL_TEST_PORT"].flatMap(UInt.init) {
                connection.port = port
            }
        } else if let socketPath, !socketPath.isEmpty {
            connection.useSocket = true
            connection.socketPath = socketPath
        } else {
            return nil
        }

        return connection
    }

    private func assertQuerySucceeded(
        _ connection: SPMySQLConnection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            connection.queryErrored(),
            connection.lastErrorMessage() ?? "Unknown MySQL error",
            file: file,
            line: line
        )
    }

    private func row(
        from result: SPMySQLResult?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [Any] {
        try XCTUnwrap(
            result?.getRowAsArray() as? [Any],
            "Expected a result row",
            file: file,
            line: line
        )
    }

    private func backtickQuoted(_ value: String) -> String {
        "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }

    private func tickQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}
