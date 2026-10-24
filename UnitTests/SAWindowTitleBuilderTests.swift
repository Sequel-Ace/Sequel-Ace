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

    func testSubtitleCarriesTheServerVersionOnlyWhenConnectedAndEnabled() {
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .connected, mySQLVersion: "9.6.0", showServerVersionInTitle: true), "MySQL 9.6.0")
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .connected, mySQLVersion: "9.6.0", showServerVersionInTitle: false), "")
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .connected, mySQLVersion: nil, showServerVersionInTitle: true), "")
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .connected, mySQLVersion: "", showServerVersionInTitle: true), "")
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .disconnected, mySQLVersion: "9.6.0", showServerVersionInTitle: true), "")
        XCTAssertEqual(SAWindowTitleBuilder.subtitle(connectionState: .connecting, mySQLVersion: "9.6.0", showServerVersionInTitle: true), "")
    }

    // MARK: - Name pill

    private func pill(_ windowTitle: String, _ tabTitle: String, _ name: String) -> SAWindowNamePillParts? {
        SAWindowTitleBuilder.namePillParts(windowTitle: windowTitle, tabTitle: tabTitle, connectionName: name)
    }

    func testPillPartsForConnectionDatabaseAndTable() {
        XCTAssertEqual(pill("Localhost/shop/orders", "Localhost/shop/orders", "Localhost"),
                       SAWindowNamePillParts(prefix: "", name: "Localhost", rest: "shop/orders"))
    }

    func testPillPartsWithoutDatabase() {
        XCTAssertEqual(pill("Localhost", "Localhost", "Localhost"),
                       SAWindowNamePillParts(prefix: "", name: "Localhost", rest: ""))
    }

    /// The `.spf` file name is not part of the connection: it stays in front of the pill, in the title's own type.
    func testFilePrefixStaysOutsideThePill() {
        XCTAssertEqual(pill("work.spf — Localhost/shop", "Localhost/shop", "Localhost"),
                       SAWindowNamePillParts(prefix: "work.spf — ", name: "Localhost", rest: "shop"))
    }

    /// The name is matched as a whole, so a "/" inside it is not mistaken for the database separator.
    func testSlashInNameStaysInThePill() {
        XCTAssertEqual(pill("a/b/shop", "a/b/shop", "a/b"),
                       SAWindowNamePillParts(prefix: "", name: "a/b", rest: "shop"))
    }

    func testPillNeedsAName() {
        XCTAssertNil(pill("Localhost/shop", "Localhost/shop", ""))
    }

    /// While connecting (or disconnected) the title is not the connection's: no pill.
    func testPillNeedsAConnectedTitle() {
        XCTAssertNil(pill("Connecting…", "Connecting…", "Localhost"))
        XCTAssertNil(pill("Sequel Ace", "Sequel Ace", "Localhost"))
        XCTAssertNil(pill("Localhost/shop", "Localhost/shop", "Production"))
    }

    /// A name that only starts the first component of the title is not that title's connection.
    func testPillNeedsTheWholeName() {
        XCTAssertNil(pill("Localhost/shop", "Localhost/shop", "Local"))
        XCTAssertNil(pill("Localhost", "Localhost", "Local"))
    }
    // MARK: - Name pill subtitle placement

    private typealias Placement = SAWindowNamePillSubtitlePlacement

    /// The pill's subtitle hangs 18.5pt under the traffic lights' centre; 11pt text reaches about 2.6pt lower.
    private func placement(spaceBelowLights space: CGFloat) -> Placement {
        Placement.forSpace(belowCentre: space, baselineBelowCentre: 18.5, descent: 2.6)
    }

    func testSubtitleGoesUnderTheTitleWhenTheToolbarShows() {
        // With the toolbar the title bar reaches 40pt under the lights' centre.
        XCTAssertEqual(placement(spaceBelowLights: 40), .below)
    }

    func testSubtitleGoesInlineInAShortTitleBar() {
        // Toolbar hidden: a 32pt bar, the lights' centre 16pt above its bottom.
        XCTAssertEqual(placement(spaceBelowLights: 16), .inline)
    }

    func testSubtitleGoesUnderOnlyWhenItsDescentFits() {
        XCTAssertEqual(placement(spaceBelowLights: 21.1), .below)
        XCTAssertEqual(placement(spaceBelowLights: 21.0), .inline)
    }

    func testInlineSubtitleTextMatchesTheNativeForm() {
        XCTAssertEqual(Placement.inlineText("MySQL 8.4"), "– MySQL 8.4")
    }

    // MARK: - Name pill host

    private typealias Host = SAWindowNamePillHost

    func testNoPillKeepsTheNativeTitle() {
        let host = Host.choose(showsPill: false, toolbarVisible: true, nativeTitleAvailable: true)
        XCTAssertEqual(host, .none)
        XCTAssertFalse(host.hidesNativeTitle)
    }

    func testToolbarShownDrawsOverTheNativeTitle() {
        // The native title keeps its flexible room in the toolbar, so the items stay where Off has them.
        let host = Host.choose(showsPill: true, toolbarVisible: true, nativeTitleAvailable: true)
        XCTAssertEqual(host, .nativeTitle)
        XCTAssertFalse(host.hidesNativeTitle)
    }

    func testToolbarHiddenUsesTheAccessory() {
        XCTAssertEqual(Host.choose(showsPill: true, toolbarVisible: false, nativeTitleAvailable: true), .accessory)
        XCTAssertEqual(Host.choose(showsPill: true, toolbarVisible: false, nativeTitleAvailable: false), .accessory)
        XCTAssertTrue(Host.accessory.hidesNativeTitle)
    }

    func testMissingNativeTitleFallsBackToTheAccessory() {
        XCTAssertEqual(Host.choose(showsPill: true, toolbarVisible: true, nativeTitleAvailable: false), .accessory)
    }
}
