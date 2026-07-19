//
//  SAConnectionInfoPostgreSQLTests.swift
//  Unit Tests
//
//  Tests for the PostgreSQL-related additions to SAConnectionInfo:
//  - SADatabaseBackend enum properties
//  - databaseBackend round-trip through fromFavoriteDictionary
//  - defaultNewFavoriteDictionary includes the databaseType key
//

import XCTest

final class SAConnectionInfoPostgreSQLTests: XCTestCase {

    // MARK: - SADatabaseBackend enum

    func testMySQLBackendDisplayName() {
        XCTAssertEqual(SADatabaseBackend.mysql.displayName, "MySQL / MariaDB")
    }

    func testPostgreSQLBackendDisplayName() {
        XCTAssertEqual(SADatabaseBackend.postgresql.displayName, "PostgreSQL")
    }

    func testMySQLDefaultPort() {
        XCTAssertEqual(SADatabaseBackend.mysql.defaultPort, 3306)
    }

    func testPostgreSQLDefaultPort() {
        XCTAssertEqual(SADatabaseBackend.postgresql.defaultPort, 5432)
    }

    func testMySQLRawValue() {
        XCTAssertEqual(SADatabaseBackend.mysql.rawValue, 0)
    }

    func testPostgreSQLRawValue() {
        XCTAssertEqual(SADatabaseBackend.postgresql.rawValue, 1)
    }

    // MARK: - Default backend in SAConnectionInfo

    func testDefaultBackendIsMySQL() {
        let info = SAConnectionInfo.fromFavoriteDictionary(nil)
        XCTAssertEqual(info.databaseBackend, .mysql)
    }

    func testEmptyDictionaryDefaultsToMySQL() {
        let info = SAConnectionInfo.fromFavoriteDictionary([:])
        XCTAssertEqual(info.databaseBackend, .mysql)
    }

    // MARK: - Round-trip encoding/decoding

    func testPostgreSQLBackendRoundTrip() {
        let fav: [AnyHashable: Any] = ["databaseType": NSNumber(value: 1)]
        let info = SAConnectionInfo.fromFavoriteDictionary(fav)
        XCTAssertEqual(info.databaseBackend, .postgresql)
    }

    func testMySQLBackendExplicit() {
        let fav: [AnyHashable: Any] = ["databaseType": NSNumber(value: 0)]
        let info = SAConnectionInfo.fromFavoriteDictionary(fav)
        XCTAssertEqual(info.databaseBackend, .mysql)
    }

    func testUnknownBackendRawValueFallsBackToMySQL() {
        // An invalid raw value (e.g. 99) should fall back to .mysql
        let fav: [AnyHashable: Any] = ["databaseType": NSNumber(value: 99)]
        let info = SAConnectionInfo.fromFavoriteDictionary(fav)
        XCTAssertEqual(info.databaseBackend, .mysql)
    }

    // MARK: - defaultNewFavoriteDictionary includes databaseType

    func testDefaultNewFavoriteDictionaryIncludesDatabaseType() {
        let favoriteID = NSNumber(value: 42)
        let dict = SAConnectionInfoObjC.defaultNewFavoriteDictionary(withID: favoriteID)
        XCTAssertNotNil(dict.object(forKey: "databaseType"),
                        "defaultNewFavoriteDictionary must include databaseType key")
    }

    func testDefaultNewFavoriteDictionaryDatabaseTypeIsMySQL() {
        let favoriteID = NSNumber(value: 1)
        let dict = SAConnectionInfoObjC.defaultNewFavoriteDictionary(withID: favoriteID)
        let rawValue = (dict.object(forKey: "databaseType") as? NSNumber)?.intValue
        XCTAssertEqual(rawValue, SADatabaseBackend.mysql.rawValue)
    }
}
