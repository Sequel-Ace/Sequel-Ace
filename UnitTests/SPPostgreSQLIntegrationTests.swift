//
//  SPPostgreSQLIntegrationTests.swift
//  Unit Tests
//
//  Integration test skeleton for PostgreSQL support.
//  These tests are skipped unless the environment variable
//  SEQUEL_ACE_PG_TEST_HOST is set to point at a live PostgreSQL server.
//
//  Required environment variables:
//    SEQUEL_ACE_PG_TEST_HOST      – host (e.g. "localhost")
//    SEQUEL_ACE_PG_TEST_PORT      – port (default: 5432)
//    SEQUEL_ACE_PG_TEST_USER      – username
//    SEQUEL_ACE_PG_TEST_PASSWORD  – password
//    SEQUEL_ACE_PG_TEST_DATABASE  – database name (default: "postgres")
//

import XCTest

final class SPPostgreSQLIntegrationTests: XCTestCase {

    private var host: String { ProcessInfo.processInfo.environment["SEQUEL_ACE_PG_TEST_HOST"] ?? "" }
    private var port: String { ProcessInfo.processInfo.environment["SEQUEL_ACE_PG_TEST_PORT"] ?? "5432" }
    private var user: String { ProcessInfo.processInfo.environment["SEQUEL_ACE_PG_TEST_USER"] ?? "" }
    private var password: String { ProcessInfo.processInfo.environment["SEQUEL_ACE_PG_TEST_PASSWORD"] ?? "" }
    private var database: String { ProcessInfo.processInfo.environment["SEQUEL_ACE_PG_TEST_DATABASE"] ?? "postgres" }

    private var isConfigured: Bool { !host.isEmpty && !user.isEmpty }

    // MARK: - Connection

    private func makeConfiguredWrapper() -> SPPostgreSQLConnectionWrapper {
        let wrapper = SPPostgreSQLConnectionWrapper()
        wrapper.host = host
        wrapper.setPort(UInt(port) ?? 5432)
        wrapper.setUsername(user)
        wrapper.setPassword(password)
        wrapper.database = database
        return wrapper
    }

    func testConnectionSucceeds() throws {
        try XCTSkipUnless(isConfigured, "Set SEQUEL_ACE_PG_TEST_HOST to run integration tests")

        let wrapper = makeConfiguredWrapper()
        XCTAssertTrue(wrapper.connect(), "Expected successful connection to PostgreSQL server")
        XCTAssertTrue(wrapper.isConnected())
        wrapper.disconnect()
    }

    func testServerVersionReturned() throws {
        try XCTSkipUnless(isConfigured, "Set SEQUEL_ACE_PG_TEST_HOST to run integration tests")

        let wrapper = makeConfiguredWrapper()
        XCTAssertTrue(wrapper.connect())
        let version = wrapper.serverVersionString()
        XCTAssertNotNil(version)
        XCTAssertFalse(version?.isEmpty ?? true)
        wrapper.disconnect()
    }

    // MARK: - Querying

    func testSimpleSelectQueryReturnsRows() throws {
        try XCTSkipUnless(isConfigured, "Set SEQUEL_ACE_PG_TEST_HOST to run integration tests")

        let wrapper = makeConfiguredWrapper()
        XCTAssertTrue(wrapper.connect())

        let result = wrapper.queryString("SELECT 1 AS value")
        XCTAssertNotNil(result, "Expected result for SELECT 1")
        XCTAssertEqual(result?.numberOfRows(), UInt(1))
        XCTAssertEqual(result?.numberOfFields(), UInt(1))

        let row = result?.getRowAsDictionary()
        XCTAssertEqual(row?["value"] as? String, "1")
        wrapper.disconnect()
    }

    func testIsPostgreSQLReturnsTrue() throws {
        try XCTSkipUnless(isConfigured, "Set SEQUEL_ACE_PG_TEST_HOST to run integration tests")

        let wrapper = makeConfiguredWrapper()
        XCTAssertTrue(wrapper.connect())
        XCTAssertTrue(wrapper.isPostgreSQL())
        wrapper.disconnect()
    }

    // MARK: - Database listing

    func testListDatabasesReturnsAtLeastOne() throws {
        try XCTSkipUnless(isConfigured, "Set SEQUEL_ACE_PG_TEST_HOST to run integration tests")

        let wrapper = SPPostgreSQLConnectionWrapper()
        wrapper.host = host
        wrapper.setPort(UInt(port) ?? 5432)
        wrapper.setUsername(user)
        wrapper.setPassword(password)
        wrapper.database = database

        XCTAssertTrue(wrapper.connect())
        let databases = wrapper.databases()
        XCTAssertNotNil(databases)
        XCTAssertGreaterThan(databases.count, 0)
        wrapper.disconnect()
    }
}
