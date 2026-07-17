//
//  SADatabaseAssertionTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

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
        XCTAssertEqual(selectedError?.message, "No database selected")
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
        XCTAssertTrue(queryMayChangeDatabaseContext("DROP DATABASE IF EXISTS target"))
        XCTAssertTrue(queryMayChangeDatabaseContext("DROP SCHEMA target;"))
        XCTAssertTrue(queryMayChangeDatabaseContext("/*!80000 USE target */"))
    }

    func testCommentsAndQuotedTextDoNotInvalidateAssertionState() {
        XCTAssertFalse(queryMayChangeDatabaseContext("SELECT 'USE target'"))
        XCTAssertFalse(queryMayChangeDatabaseContext("/* USE target */ SELECT 1"))
        XCTAssertFalse(queryMayChangeDatabaseContext("-- USE target\nSELECT 1"))
        XCTAssertFalse(queryMayChangeDatabaseContext("SELECT 'DROP DATABASE target'"))
    }

    func testExecutableCommentVersionAndVendorGatesAreRespected() {
        XCTAssertFalse(queryMayChangeDatabaseContext("/*!99999 USE target */"))
        XCTAssertFalse(queryMayChangeDatabaseContext("/*M!80000 USE target */"))
        XCTAssertFalse(queryMayChangeDatabaseContext("/*!80000 USE target */", serverIsMariaDB: true))
        XCTAssertTrue(queryMayChangeDatabaseContext("/*M!80000 USE target */", serverIsMariaDB: true))
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
