//
//  SADatabaseListManagerTests.swift
//  Unit Tests
//
//  Tests for SADatabaseListManager — Phase A1a extraction of
//  -[SPDatabaseDocument setDatabases]. Covers the partition logic
//  (system vs. user split) and the choose-database popup configuration
//  (header items, section ordering, current selection).
//

import XCTest
import AppKit

final class SADatabaseListManagerTests: XCTestCase {

    // MARK: - System database name constants

    /// Locks the SPMySQL*Database wire-format names. The literals live
    /// in SADatabaseListManager.systemDatabaseNames and must stay in
    /// sync with the extern constants in SPConstants.m. Renaming a
    /// system database without updating both fails this test.
    func testSystemDatabaseNames() {
        XCTAssertEqual(SADatabaseListManager.systemDatabaseNames,
                       ["mysql", "information_schema", "performance_schema", "sys"])
    }

    // MARK: - Partition

    func testPartitionSplitsSystemFromUser() {
        let result = SADatabaseListManager.partition(
            databases: ["mysql", "myapp", "information_schema", "analytics", "performance_schema", "sys"]
        )
        XCTAssertEqual(result.systemDatabases, ["mysql", "information_schema", "performance_schema", "sys"])
        XCTAssertEqual(result.userDatabases,   ["myapp", "analytics"])
    }

    func testPartitionPreservesInputOrderWithinEachBucket() {
        let result = SADatabaseListManager.partition(
            databases: ["zeta", "sys", "alpha", "mysql", "beta"]
        )
        XCTAssertEqual(result.systemDatabases, ["sys", "mysql"])
        XCTAssertEqual(result.userDatabases,   ["zeta", "alpha", "beta"])
    }

    func testPartitionEmpty() {
        let result = SADatabaseListManager.partition(databases: [])
        XCTAssertEqual(result.systemDatabases, [])
        XCTAssertEqual(result.userDatabases,   [])
    }

    func testPartitionAllSystem() {
        let result = SADatabaseListManager.partition(
            databases: ["mysql", "information_schema", "performance_schema", "sys"]
        )
        XCTAssertEqual(result.systemDatabases, ["mysql", "information_schema", "performance_schema", "sys"])
        XCTAssertEqual(result.userDatabases,   [])
    }

    func testPartitionAllUser() {
        let result = SADatabaseListManager.partition(
            databases: ["app1", "app2", "app3"]
        )
        XCTAssertEqual(result.systemDatabases, [])
        XCTAssertEqual(result.userDatabases,   ["app1", "app2", "app3"])
    }

    /// Case sensitivity matters: MySQL database names on case-sensitive
    /// filesystems differ between `MySQL` and `mysql`. The partition
    /// must not treat them as the same.
    func testPartitionIsCaseSensitive() {
        let result = SADatabaseListManager.partition(databases: ["MySQL", "MYSQL", "mysql"])
        XCTAssertEqual(result.systemDatabases, ["mysql"])
        XCTAssertEqual(result.userDatabases,   ["MySQL", "MYSQL"])
    }

    // MARK: - Popup configuration

    /// Helper: build a partition expected from a given input.
    private func makePopup() -> NSPopUpButton {
        return NSPopUpButton(frame: .zero, pullsDown: false)
    }

    func testConfigurePopupHeaderItems() {
        let popup = makePopup()
        _ = SADatabaseListManager.configurePopup(
            popup,
            databases: [],
            currentDatabase: nil,
            addDatabaseSelector: #selector(NSObject.description as () -> String),  // dummy
            refreshDatabasesSelector: #selector(NSObject.description as () -> String)
        )
        let items = popup.itemArray
        XCTAssertEqual(items[0].title, "Choose Database...")
        XCTAssertTrue(items[1].isSeparatorItem)
        XCTAssertEqual(items[2].title, "Add Database...")
        XCTAssertEqual(items[3].title, "Refresh Databases")
        XCTAssertTrue(items[4].isSeparatorItem)
    }

    func testConfigurePopupHeaderItemsHaveNilTarget() {
        // Nil-target means AppKit dispatches via the responder chain.
        // SPDatabaseDocument provides -addDatabase: and a -setDatabases:
        // takes-sender wrapper for that chain to land on; pinning
        // nil-target here keeps the manager UI-thread/host-class
        // agnostic and matches the original setDatabases code shape.
        let popup = makePopup()
        _ = SADatabaseListManager.configurePopup(
            popup,
            databases: [],
            currentDatabase: nil,
            addDatabaseSelector: #selector(NSObject.description as () -> String),
            refreshDatabasesSelector: #selector(NSObject.description as () -> String)
        )
        XCTAssertNil(popup.itemArray[2].target, "Add Database menu item must have nil target")
        XCTAssertNil(popup.itemArray[3].target, "Refresh Databases menu item must have nil target")
    }

    func testConfigurePopupSectionsSystemThenSeparatorThenUser() {
        let popup = makePopup()
        _ = SADatabaseListManager.configurePopup(
            popup,
            databases: ["myapp", "mysql", "analytics", "sys"],
            currentDatabase: nil,
            addDatabaseSelector: #selector(NSObject.description as () -> String),
            refreshDatabasesSelector: #selector(NSObject.description as () -> String)
        )
        // Header (5 items: 2 separators + 3 actions) is followed by:
        //   - system DBs (mysql, sys)
        //   - separator
        //   - user DBs (myapp, analytics)
        let titles = popup.itemArray.dropFirst(5).map { $0.isSeparatorItem ? "<sep>" : $0.title }
        XCTAssertEqual(Array(titles), ["mysql", "sys", "<sep>", "myapp", "analytics"])
    }

    func testConfigurePopupNoSystemDatabasesOmitsTheSeparator() {
        let popup = makePopup()
        _ = SADatabaseListManager.configurePopup(
            popup,
            databases: ["myapp", "analytics"],
            currentDatabase: nil,
            addDatabaseSelector: #selector(NSObject.description as () -> String),
            refreshDatabasesSelector: #selector(NSObject.description as () -> String)
        )
        let titles = popup.itemArray.dropFirst(5).map { $0.isSeparatorItem ? "<sep>" : $0.title }
        XCTAssertEqual(Array(titles), ["myapp", "analytics"])
    }

    func testConfigurePopupNoUserDatabasesStillShowsSystemAndSeparator() {
        let popup = makePopup()
        _ = SADatabaseListManager.configurePopup(
            popup,
            databases: ["mysql"],
            currentDatabase: nil,
            addDatabaseSelector: #selector(NSObject.description as () -> String),
            refreshDatabasesSelector: #selector(NSObject.description as () -> String)
        )
        let titles = popup.itemArray.dropFirst(5).map { $0.isSeparatorItem ? "<sep>" : $0.title }
        // Trailing separator is preserved even with no user dbs after it
        // — matches pre-refactor behaviour (the loop just didn't fire).
        XCTAssertEqual(Array(titles), ["mysql", "<sep>"])
    }

    func testConfigurePopupSelectsCurrentDatabase() {
        let popup = makePopup()
        _ = SADatabaseListManager.configurePopup(
            popup,
            databases: ["myapp", "analytics"],
            currentDatabase: "analytics",
            addDatabaseSelector: #selector(NSObject.description as () -> String),
            refreshDatabasesSelector: #selector(NSObject.description as () -> String)
        )
        XCTAssertEqual(popup.titleOfSelectedItem, "analytics")
    }

    func testConfigurePopupSelectsPlaceholderWhenNoCurrentDatabase() {
        let popup = makePopup()
        _ = SADatabaseListManager.configurePopup(
            popup,
            databases: ["myapp"],
            currentDatabase: nil,
            addDatabaseSelector: #selector(NSObject.description as () -> String),
            refreshDatabasesSelector: #selector(NSObject.description as () -> String)
        )
        XCTAssertEqual(popup.indexOfSelectedItem, 0)
        XCTAssertEqual(popup.titleOfSelectedItem, "Choose Database...")
    }

    func testConfigurePopupSelectsPlaceholderWhenCurrentDatabaseIsEmpty() {
        let popup = makePopup()
        _ = SADatabaseListManager.configurePopup(
            popup,
            databases: ["myapp"],
            currentDatabase: "",
            addDatabaseSelector: #selector(NSObject.description as () -> String),
            refreshDatabasesSelector: #selector(NSObject.description as () -> String)
        )
        XCTAssertEqual(popup.indexOfSelectedItem, 0)
    }

    func testConfigurePopupReturnsPartition() {
        let popup = makePopup()
        let partition = SADatabaseListManager.configurePopup(
            popup,
            databases: ["myapp", "mysql", "analytics", "sys"],
            currentDatabase: nil,
            addDatabaseSelector: #selector(NSObject.description as () -> String),
            refreshDatabasesSelector: #selector(NSObject.description as () -> String)
        )
        XCTAssertEqual(partition.systemDatabases, ["mysql", "sys"])
        XCTAssertEqual(partition.userDatabases,   ["myapp", "analytics"])
    }

    // MARK: - Navigator schema path

    /// Locks the SPNavigatorController separator wire format. Matches
    /// SPUniqueSchemaDelimiter in SPConstants.m (U+FFF8).
    func testSchemaPathDelimiter() {
        XCTAssertEqual(SADatabaseListManager.schemaPathDelimiter, "\u{FFF8}")
    }

    func testNavigatorSchemaPathWithDatabase() {
        XCTAssertEqual(
            SADatabaseListManager.navigatorSchemaPath(
                connectionID: "conn-42",
                selectedDatabaseTitle: "analytics"
            ),
            "conn-42\u{FFF8}analytics"
        )
    }

    /// When no database is selected in the popup, the navigator should
    /// just see the connection root — no trailing separator. This is
    /// what the pre-refactor SPMutableString-based code did when
    /// titleOfSelectedItem was nil or empty.
    func testNavigatorSchemaPathWithoutDatabase() {
        XCTAssertEqual(
            SADatabaseListManager.navigatorSchemaPath(
                connectionID: "conn-42",
                selectedDatabaseTitle: nil
            ),
            "conn-42"
        )
        XCTAssertEqual(
            SADatabaseListManager.navigatorSchemaPath(
                connectionID: "conn-42",
                selectedDatabaseTitle: ""
            ),
            "conn-42"
        )
    }

    /// Even an empty connectionID stays empty + no separator — defensive
    /// behaviour because callers (the popup placeholder, connection
    /// startup) sometimes hand us a stub ID before the connection
    /// completes.
    func testNavigatorSchemaPathWithEmptyConnectionID() {
        XCTAssertEqual(
            SADatabaseListManager.navigatorSchemaPath(
                connectionID: "",
                selectedDatabaseTitle: nil
            ),
            ""
        )
        XCTAssertEqual(
            SADatabaseListManager.navigatorSchemaPath(
                connectionID: "",
                selectedDatabaseTitle: "analytics"
            ),
            "\u{FFF8}analytics"
        )
    }

    // MARK: - Popup rebuild idempotency

    /// Calling configurePopup twice must produce the same result on the
    /// second call — i.e. the popup is fully rebuilt, not appended to.
    /// The original setDatabases relied on this (it's called from
    /// "Refresh Databases" and from -_selectDatabaseAndItem: when the
    /// list is stale).
    func testConfigurePopupIsIdempotentAcrossCalls() {
        let popup = makePopup()
        _ = SADatabaseListManager.configurePopup(
            popup,
            databases: ["myapp", "mysql"],
            currentDatabase: "mysql",
            addDatabaseSelector: #selector(NSObject.description as () -> String),
            refreshDatabasesSelector: #selector(NSObject.description as () -> String)
        )
        let firstCount = popup.numberOfItems

        _ = SADatabaseListManager.configurePopup(
            popup,
            databases: ["myapp", "mysql"],
            currentDatabase: "mysql",
            addDatabaseSelector: #selector(NSObject.description as () -> String),
            refreshDatabasesSelector: #selector(NSObject.description as () -> String)
        )
        XCTAssertEqual(popup.numberOfItems, firstCount)
        XCTAssertEqual(popup.titleOfSelectedItem, "mysql")
    }
}

final class SATableListResultParserTests: XCTestCase {

    func testEmptyResponseProducesNoEntries() {
        let result = SATableListResultParser.parse(
            rows: [],
            fieldNames: [],
            displayTableComments: false
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testParsesMySQLShowFullTablesResponse() {
        let result = SATableListResultParser.parse(
            rows: [
                ["accounts", "BASE TABLE"],
                ["active_accounts", "VIEW"],
            ],
            fieldNames: ["Tables_in_app", "Table_type"],
            displayTableComments: false
        )

        XCTAssertEqual(result.map(\.name), ["accounts", "active_accounts"])
        XCTAssertEqual(result.map(\.comment), ["", ""])
        XCTAssertEqual(result.map(\.isView), [false, true])
    }

    func testParsesMariaDBShowFullTablesResponseIncludingSequence() {
        let result = SATableListResultParser.parse(
            rows: [
                ["orders", "BASE TABLE"],
                ["order_summary", "VIEW"],
                ["order_sequence", "SEQUENCE"],
            ],
            fieldNames: ["Tables_in_shop", "Table_type"],
            displayTableComments: false
        )

        XCTAssertEqual(result.map(\.name), ["orders", "order_summary", "order_sequence"])
        XCTAssertEqual(result.map(\.isView), [false, true, false])
    }

    func testParsesPolarDBXResponseWithoutDependingOnColumnLabels() {
        let result = SATableListResultParser.parse(
            rows: [
                ["logical_orders", "BASE TABLE"],
                ["logical_order_summary", "VIEW"],
            ],
            fieldNames: ["TABLES_IN_AGENT_ADMIN_TEST", "TABLE_TYPE"],
            displayTableComments: false
        )

        XCTAssertEqual(result.map(\.name), ["logical_orders", "logical_order_summary"])
        XCTAssertEqual(result.map(\.isView), [false, true])
        XCTAssertFalse(result.map(\.name).contains("..."))
    }

    func testParsesLegacySingleColumnShowTablesResponse() {
        let result = SATableListResultParser.parse(
            rows: [["legacy_table"]],
            fieldNames: ["Tables_in_legacy"],
            displayTableComments: false
        )

        XCTAssertEqual(result.map(\.name), ["legacy_table"])
        XCTAssertEqual(result.map(\.comment), [""])
        XCTAssertEqual(result.map(\.isView), [false])
    }

    func testParsesMySQLShowTableStatusResponse() {
        let fieldNames = [
            "Name", "Engine", "Version", "Row_format", "Rows",
            "Avg_row_length", "Data_length", "Max_data_length",
            "Index_length", "Data_free", "Auto_increment", "Create_time",
            "Update_time", "Check_time", "Collation", "Checksum",
            "Create_options", "Comment",
        ]
        let rows: [NSArray] = [
            ["accounts", "InnoDB", "10", "Dynamic", "42", "390", "16384", "0", "0", "0", "43", "2026-07-17 10:00:00", NSNull(), NSNull(), "utf8mb4_0900_ai_ci", NSNull(), "", "application table"],
            ["active_accounts", NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), "VIEW"],
        ]

        let result = SATableListResultParser.parse(
            rows: rows,
            fieldNames: fieldNames,
            displayTableComments: true
        )

        XCTAssertEqual(result.map(\.name), ["accounts", "active_accounts"])
        XCTAssertEqual(result.map(\.comment), ["application table", "VIEW"])
        XCTAssertEqual(result.map(\.isView), [false, true])
    }

    func testParsesMariaDBShowTableStatusWithExtensionColumns() {
        let fieldNames = [
            "Name", "Engine", "Version", "Row_format", "Rows",
            "Avg_row_length", "Data_length", "Max_data_length",
            "Index_length", "Data_free", "Auto_increment", "Create_time",
            "Update_time", "Check_time", "Collation", "Checksum",
            "Create_options", "Comment", "Max_index_length", "Temporary",
        ]
        let rows: [NSArray] = [
            ["orders", "InnoDB", "10", "Dynamic", "12", "1365", "16384", "0", "0", "0", "13", "2026-07-17 10:00:00", NSNull(), NSNull(), "utf8mb4_general_ci", NSNull(), "", "application table", "0", "N"],
            ["order_summary", NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), "VIEW", NSNull(), "N"],
        ]

        let result = SATableListResultParser.parse(
            rows: rows,
            fieldNames: fieldNames,
            displayTableComments: true
        )

        XCTAssertEqual(result.map(\.name), ["orders", "order_summary"])
        XCTAssertEqual(result.map(\.comment), ["application table", "VIEW"])
        XCTAssertEqual(result.map(\.isView), [false, true])
    }

    func testLocatesCommentColumnCaseInsensitively() {
        let result = SATableListResultParser.parse(
            rows: [["summary", "VIEW", NSNull()]],
            fieldNames: ["Name", "COMMENT", "Engine"],
            displayTableComments: true
        )

        XCTAssertEqual(result.map(\.comment), ["VIEW"])
        XCTAssertEqual(result.map(\.isView), [true])
    }

    func testDefaultsMissingOrNullCommentToEmptyString() {
        let result = SATableListResultParser.parse(
            rows: [
                ["missing_comment"],
                ["null_comment", NSNull()],
            ],
            fieldNames: ["Name", "Comment"],
            displayTableComments: true
        )

        XCTAssertEqual(result.map(\.comment), ["", ""])
        XCTAssertEqual(result.map(\.isView), [false, false])
    }

    func testPreservesLegacyPlaceholderForNullNameAndSkipsEmptyRows() {
        let result = SATableListResultParser.parse(
            rows: [
                [NSNull(), "BASE TABLE"],
                [],
                ["valid_table", NSNull()],
            ],
            fieldNames: ["Tables_in_app", "Table_type"],
            displayTableComments: false
        )

        XCTAssertEqual(result.map(\.name), ["...", "valid_table"])
        XCTAssertEqual(result.map(\.isView), [false, false])
    }
}
