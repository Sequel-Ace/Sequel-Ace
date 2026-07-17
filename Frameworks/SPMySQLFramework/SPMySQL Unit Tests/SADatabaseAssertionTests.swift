//
//  SADatabaseAssertionTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
import SPMySQL

final class SADatabaseAssertionTests: XCTestCase {
    private let utf8CharacterSet = Data("utf8mb4".utf8)
    private let latin1CharacterSet = Data("latin1".utf8)

    func testDisabledAssertionDoesNotConsultOrMutateSession() {
        let error = assertDatabase(
            "target",
            required: false,
            activeDatabaseData: Data("other".utf8),
            connectorTracksSessionState: false,
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("Unexpected charset query") },
            executeSQL: { _ in unexpectedError("Unexpected SQL") },
            selectDatabase: { _ in unexpectedError("Unexpected database selection") }
        )

        XCTAssertNil(error)
    }

    func testMatchingTrackedDatabaseAvoidsAllSessionMutations() {
        let database = "tracked_é"
        let error = assertDatabase(
            database,
            activeDatabaseData: Data(database.utf8),
            connectorTracksSessionState: true,
            connectorCharacterSetData: utf8CharacterSet,
            stringEncodingProvider: { _ in unexpectedEncoding("UTF-8 match should not require charset mapping") },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("Unexpected charset query") },
            executeSQL: { _ in unexpectedError("Unexpected SQL") },
            selectDatabase: { _ in unexpectedError("Unexpected database selection") }
        )

        XCTAssertNil(error)
    }

    func testMatchingTrackedDatabaseUsesConnectorEncodingWithoutQuerying() throws {
        let database = "tracked_é"
        let activeDatabase = try XCTUnwrap(database.data(using: .windowsCP1252))
        var mappedCharacterSets: [String] = []

        let error = assertDatabase(
            database,
            activeDatabaseData: activeDatabase,
            connectorTracksSessionState: true,
            connectorCharacterSetData: latin1CharacterSet,
            stringEncodingProvider: { name in
                mappedCharacterSets.append(name)
                return String.Encoding.windowsCP1252.rawValue
            },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("Unexpected charset query") },
            executeSQL: { _ in unexpectedError("Unexpected SQL") },
            selectDatabase: { _ in unexpectedError("Unexpected database selection") }
        )

        XCTAssertNil(error)
        XCTAssertEqual(mappedCharacterSets, ["latin1"])
    }

    func testLegacyConnectionReselectsEvenWhenCachedDatabaseMatches() {
        var selectedDatabase: Data?

        let error = assertDatabase(
            "target",
            activeDatabaseData: Data("target".utf8),
            connectorTracksSessionState: false,
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
            activeDatabaseData: Data("selected".utf8),
            connectorTracksSessionState: true,
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") }
        )
        let emptyError = assertDatabase(
            nil,
            activeDatabaseData: nil,
            connectorTracksSessionState: true,
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
            activeDatabaseData: nil,
            connectorTracksSessionState: false,
            queryActiveDatabaseData: {
                queryCount += 1
                return .init(data: Data("selected".utf8), error: nil)
            }
        )
        let emptyError = assertDatabase(
            nil,
            activeDatabaseData: Data("stale".utf8),
            connectorTracksSessionState: false,
            queryActiveDatabaseData: {
                queryCount += 1
                return .init(data: nil, error: nil)
            }
        )

        XCTAssertEqual(selectedError?.errorID, 1046)
        XCTAssertNil(emptyError)
        XCTAssertEqual(queryCount, 2)
    }

    func testUntrackedConnectionUsesLiveClientCharset() throws {
        let database = "legacy_é"
        let expectedSelection = try XCTUnwrap(database.data(using: .windowsCP1252))
        var selectedDatabase: Data?
        var charsetQueryCount = 0

        let error = assertDatabase(
            database,
            activeDatabaseData: Data("other".utf8),
            connectorTracksSessionState: false,
            connectorCharacterSetData: utf8CharacterSet,
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
            activeDatabaseData: Data("other".utf8),
            connectorTracksSessionState: true,
            connectorCharacterSetData: latin1CharacterSet,
            stringEncodingProvider: { _ in String.Encoding.windowsCP1252.rawValue },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("Tracked charset should be used directly") },
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
            activeDatabaseData: Data("other".utf8),
            connectorTracksSessionState: true,
            connectorCharacterSetData: latin1CharacterSet,
            stringEncodingProvider: { _ in String.Encoding.windowsCP1252.rawValue },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("Unexpected charset query") },
            executeSQL: { sql in sql.hasSuffix("utf8mb4") ? nil : restoreError },
            selectDatabase: { _ in selectionError }
        )

        XCTAssertTrue(error === selectionError)
    }

    func testRestoreErrorStopsOtherwiseSuccessfulQuery() {
        let restoreError = SADatabaseAssertionError(errorID: 2013, message: "restore", sqlState: "HY000")

        let error = assertDatabase(
            "legacy_日",
            activeDatabaseData: Data("other".utf8),
            connectorTracksSessionState: true,
            connectorCharacterSetData: latin1CharacterSet,
            stringEncodingProvider: { _ in String.Encoding.windowsCP1252.rawValue },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("Unexpected charset query") },
            executeSQL: { sql in sql.hasSuffix("utf8mb4") ? nil : restoreError },
            selectDatabase: { _ in nil }
        )

        XCTAssertTrue(error === restoreError)
    }

    func testClientCharsetLookupErrorIsPreserved() {
        let lookupError = SADatabaseAssertionError(errorID: 2013, message: "lookup", sqlState: "HY000")

        let error = assertDatabase(
            "legacy_日",
            activeDatabaseData: Data("other".utf8),
            connectorTracksSessionState: false,
            connectorCharacterSetData: utf8CharacterSet,
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
            activeDatabaseData: Data("other".utf8),
            connectorTracksSessionState: true,
            connectorCharacterSetData: latin1CharacterSet,
            stringEncodingProvider: { _ in String.Encoding.windowsCP1252.rawValue },
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("Unexpected charset query") },
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
            activeDatabaseData: Data("other".utf8),
            connectorTracksSessionState: false,
            connectorCharacterSetData: utf8CharacterSet,
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
            activeDatabaseData: Data("other".utf8),
            connectorTracksSessionState: false,
            queryActiveDatabaseData: { unexpectedLookup("Unexpected active database query") },
            queryClientCharacterSetData: { unexpectedLookup("Unexpected charset query") },
            executeSQL: { _ in unexpectedError("Unexpected SQL") },
            selectDatabase: { _ in unexpectedError("Unexpected database selection") }
        )

        XCTAssertEqual(error?.errorID, 0)
        XCTAssertEqual(error?.message, "Unable to encode the database name before selecting it.")
    }

    private func assertDatabase(
        _ databaseName: String?,
        required: Bool = true,
        activeDatabaseData: Data?,
        connectorTracksSessionState: Bool,
        connectorCharacterSetData: Data? = nil,
        stringEncodingProvider: (String) -> UInt = { _ in String.Encoding.utf8.rawValue },
        queryActiveDatabaseData: () -> SADatabaseSessionValueLookup,
        queryClientCharacterSetData: () -> SADatabaseSessionValueLookup = { .init(data: nil, error: nil) },
        executeSQL: (String) -> SADatabaseAssertionError? = { _ in nil },
        selectDatabase: (Data) -> SADatabaseAssertionError? = { _ in nil }
    ) -> SADatabaseAssertionError? {
        SADatabaseAssertion.assertDatabase(
            databaseName,
            required: required,
            activeDatabaseData: activeDatabaseData,
            connectorTracksSessionState: connectorTracksSessionState,
            connectorCharacterSetData: connectorCharacterSetData,
            stringEncodingProvider: stringEncodingProvider,
            queryActiveDatabaseData: queryActiveDatabaseData,
            queryClientCharacterSetData: queryClientCharacterSetData,
            executeSQL: executeSQL,
            selectDatabase: selectDatabase
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
