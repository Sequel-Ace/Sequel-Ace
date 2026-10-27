//
//  SAWindowTitleBuilderTests.swift
//  Unit Tests
//
//  Pins the byte-exact format of -[SPDatabaseDocument updateWindowTitle:]
//  and -[SPDatabaseDocument displayName] after the Phase A4 extraction.
//  The em dash and the slash separators are all load-bearing — the strings are user-visible in the
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
            table: "mytable"
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
            table: nil
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
            table: nil
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
            table: nil
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
            table: nil
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
            table: nil
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
            table: "customers"
        )
        XCTAssertEqual(result.windowTitle, "production/orders/customers")
        XCTAssertEqual(result.tabTitle, "production/orders/customers")
    }

    func testConnectedFilePathPrefixesOnlyTheWindowTitle() {
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .connected,
            filePath: "/Users/x/work.spf",
            isUntitled: false,
            bundleName: bundleName,
            connectionName: "production",
            database: "orders",
            table: "customers"
        )
        // Pin the exact preamble: filename — host/db/table
        XCTAssertEqual(result.windowTitle, "work.spf — production/orders/customers")
        // Tab stays compact (no file prefix)
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
            table: ""
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

    func testSubtitleCarriesTheServerVersionOnlyWhenConnectedAndEnabled() {
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .connected, mySQLVersion: "9.6.0", showServerVersionInTitle: true), "MySQL 9.6.0")
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .connected, mySQLVersion: "9.6.0", showServerVersionInTitle: false), "")
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .connected, mySQLVersion: nil, showServerVersionInTitle: true), "")
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .connected, mySQLVersion: "", showServerVersionInTitle: true), "")
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .disconnected, mySQLVersion: "9.6.0", showServerVersionInTitle: true), "")
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .connecting, mySQLVersion: "9.6.0", showServerVersionInTitle: true), "")
    }
}
