//
//  SAWindowTitleBuilderTests.swift
//  Unit Tests
//
//  Pins the byte-exact format of -[SPDatabaseDocument updateWindowTitle:]
//  and -[SPDatabaseDocument displayName] after the Phase A4 extraction.
//  The em dash, the trailing space after "(MySQL X)", and the slash
//  separators are all load-bearing — the strings are user-visible in the
//  window chrome and the tab.
//

import XCTest

final class SAWindowTitleBuilderTests: XCTestCase {

    private let bundleName = "Sequel Ace"

    // MARK: - Connecting state

    func testConnectingStateIgnoresEverythingElse() {
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .connecting,
            filePath: "/Users/x/foo.spf",
            isUntitled: false,
            bundleName: bundleName,
            connectionName: "host",
            database: "mydb",
            table: "mytable",
            mySQLVersion: "8.0",
            showServerVersionInTitle: true
        )
        XCTAssertEqual(result.windowTitle, "Connecting…")
        XCTAssertEqual(result.tabTitle, "Connecting…")
    }

    // MARK: - Disconnected state

    func testDisconnectedUntitledHasNoPathPrefix() {
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .disconnected,
            filePath: nil,
            isUntitled: true,
            bundleName: bundleName,
            connectionName: "ignored",
            database: nil,
            table: nil,
            mySQLVersion: nil,
            showServerVersionInTitle: false
        )
        XCTAssertEqual(result.windowTitle, bundleName)
        XCTAssertEqual(result.tabTitle, bundleName)
    }

    func testDisconnectedWithFilePathPrependsLastComponentAndEmDash() {
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .disconnected,
            filePath: "/Users/x/Sessions/work.spf",
            isUntitled: false,
            bundleName: bundleName,
            connectionName: "ignored",
            database: nil,
            table: nil,
            mySQLVersion: nil,
            showServerVersionInTitle: false
        )
        XCTAssertEqual(result.windowTitle, "work.spf — Sequel Ace")
        XCTAssertEqual(result.tabTitle, "work.spf — Sequel Ace")
    }

    func testDisconnectedUntitledFlagSuppressesPathPrefix() {
        // The document can have a fileURL but still be marked untitled
        // — the path prefix only appears when both conditions hold.
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .disconnected,
            filePath: "/Users/x/Untitled.spf",
            isUntitled: true,
            bundleName: bundleName,
            connectionName: "ignored",
            database: nil,
            table: nil,
            mySQLVersion: nil,
            showServerVersionInTitle: false
        )
        XCTAssertEqual(result.windowTitle, bundleName)
    }

    // MARK: - Connected state

    func testConnectedHostOnly() {
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .connected,
            filePath: nil,
            isUntitled: false,
            bundleName: bundleName,
            connectionName: "production",
            database: nil,
            table: nil,
            mySQLVersion: "8.0.32",
            showServerVersionInTitle: false
        )
        XCTAssertEqual(result.windowTitle, "production")
        XCTAssertEqual(result.tabTitle, "production")
    }

    func testConnectedWithDatabase() {
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .connected,
            filePath: nil,
            isUntitled: false,
            bundleName: bundleName,
            connectionName: "production",
            database: "orders",
            table: nil,
            mySQLVersion: nil,
            showServerVersionInTitle: false
        )
        XCTAssertEqual(result.windowTitle, "production/orders")
        XCTAssertEqual(result.tabTitle, "production/orders")
    }

    func testConnectedWithDatabaseAndTable() {
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .connected,
            filePath: nil,
            isUntitled: false,
            bundleName: bundleName,
            connectionName: "production",
            database: "orders",
            table: "customers",
            mySQLVersion: nil,
            showServerVersionInTitle: false
        )
        XCTAssertEqual(result.windowTitle, "production/orders/customers")
        XCTAssertEqual(result.tabTitle, "production/orders/customers")
    }

    /// Server-version preamble is window-only — the tab stays compact so
    /// the version doesn't waste the limited tab real estate.
    func testConnectedShowServerVersionAffectsOnlyWindowTitle() {
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .connected,
            filePath: nil,
            isUntitled: false,
            bundleName: bundleName,
            connectionName: "production",
            database: "orders",
            table: nil,
            mySQLVersion: "8.0.32",
            showServerVersionInTitle: true
        )
        XCTAssertEqual(result.windowTitle, "(MySQL 8.0.32) production/orders")
        XCTAssertEqual(result.tabTitle, "production/orders")
    }

    func testConnectedShowServerVersionWithMissingVersionIsOmitted() {
        // Defensive: -mySQLVersion can briefly be nil before the
        // post-connect handshake stores it. We must not render
        // "(MySQL (null)) " in the title.
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .connected,
            filePath: nil,
            isUntitled: false,
            bundleName: bundleName,
            connectionName: "production",
            database: nil,
            table: nil,
            mySQLVersion: nil,
            showServerVersionInTitle: true
        )
        XCTAssertEqual(result.windowTitle, "production")
    }

    func testConnectedFilePathAndServerVersionStackInOrder() {
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .connected,
            filePath: "/Users/x/work.spf",
            isUntitled: false,
            bundleName: bundleName,
            connectionName: "production",
            database: "orders",
            table: "customers",
            mySQLVersion: "8.0.32",
            showServerVersionInTitle: true
        )
        // Pin the exact preamble order: filename — (MySQL X) host/db/table
        XCTAssertEqual(result.windowTitle, "work.spf — (MySQL 8.0.32) production/orders/customers")
        // Tab stays compact (no file prefix, no version)
        XCTAssertEqual(result.tabTitle, "production/orders/customers")
    }

    /// Empty strings for database/table should NOT produce stray slashes.
    /// The original code uses `[[self table] length]` for the table check
    /// but only nil-tests the database — passing an empty database string
    /// would have produced "host/" historically. The builder normalizes
    /// both to "treat empty as absent" to avoid that footgun.
    func testConnectedEmptyDatabaseAndTableAreOmitted() {
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .connected,
            filePath: nil,
            isUntitled: false,
            bundleName: bundleName,
            connectionName: "production",
            database: "",
            table: "",
            mySQLVersion: nil,
            showServerVersionInTitle: false
        )
        XCTAssertEqual(result.windowTitle, "production")
        XCTAssertEqual(result.tabTitle, "production")
    }

    // MARK: - displayName

    func testDisplayNameDisconnectedMatchesDisconnectedTitle() {
        let name = SAWindowTitleBuilder.displayName(
            isConnected: false,
            filePath: "/Users/x/work.spf",
            isUntitled: false,
            bundleName: bundleName
        )
        XCTAssertEqual(name, "work.spf — Sequel Ace")
    }

    func testDisplayNameDisconnectedUntitled() {
        let name = SAWindowTitleBuilder.displayName(
            isConnected: false,
            filePath: nil,
            isUntitled: true,
            bundleName: bundleName
        )
        XCTAssertEqual(name, bundleName)
    }

    func testDisplayNameConnectedReturnsLastPathComponent() {
        let name = SAWindowTitleBuilder.displayName(
            isConnected: true,
            filePath: "/Users/x/Sessions/work.spf",
            isUntitled: false,
            bundleName: bundleName
        )
        XCTAssertEqual(name, "work.spf")
    }

    func testDisplayNameConnectedNoFilePathReturnsEmpty() {
        // The original returned "" via -lastPathComponent of "" — pin
        // that behavior so callers that compare against "" still work.
        let name = SAWindowTitleBuilder.displayName(
            isConnected: true,
            filePath: nil,
            isUntitled: true,
            bundleName: bundleName
        )
        XCTAssertEqual(name, "")
    }
}
