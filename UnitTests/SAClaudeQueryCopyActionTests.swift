//
//  SAClaudeQueryCopyActionTests.swift
//  Unit Tests
//

import XCTest

final class SAClaudeQueryCopyActionTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "SAClaudeQueryCopyActionTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testTagsMatchTheGridCopyMenu() {
        // SPEditMenuCopy… in SPCopyTable.m.
        XCTAssertEqual(SAClaudeQueryCopyAction.allCases.map(\.tag), [2001, 2002, 2003, 2004])
        XCTAssertEqual(SAClaudeQueryCopyAction(rawValue: 2003), .sqlInsert)
        XCTAssertEqual(SAClaudeQueryCopyAction.allCases.filter(\.needsColumnDefinitions), [.sqlInsert, .sqlInsertNoAutoIncrement])
    }

    func testLabels() {
        XCTAssertEqual(SAClaudeQueryCopyAction.allCases.map(\.menuTitle),
                       ["Copy", "Copy with column names", "Copy as SQL INSERT", "Copy as SQL INSERT (no auto_inc)"])
        XCTAssertEqual(SAClaudeQueryCopyAction.allCases.map(\.shortLabel),
                       ["Copy", "Copy with names", "Copy as INSERT", "Copy INSERT (no auto_inc)"])
        XCTAssertEqual(SAClaudeQueryCopyAction.copiedLabel, "Copied")
    }

    func testStoredDefaultFallsBackToCopy() {
        XCTAssertEqual(SAClaudeQueryCopyAction.storedDefault(in: defaults), .plain)
        defaults.set(0, forKey: SAClaudeQueryCopyAction.defaultsKey)
        XCTAssertEqual(SAClaudeQueryCopyAction.storedDefault(in: defaults), .plain)
        defaults.set(9999, forKey: SAClaudeQueryCopyAction.defaultsKey)
        XCTAssertEqual(SAClaudeQueryCopyAction.storedDefault(in: defaults), .plain)
        defaults.set("garbage", forKey: SAClaudeQueryCopyAction.defaultsKey)
        XCTAssertEqual(SAClaudeQueryCopyAction.storedDefault(in: defaults), .plain)
    }

    func testStoreRoundTrips() {
        SAClaudeQueryCopyAction.store(.sqlInsertNoAutoIncrement, in: defaults)
        XCTAssertEqual(defaults.integer(forKey: "ClaudeQueryCopyDefaultAction"), 2004)
        XCTAssertEqual(SAClaudeQueryCopyAction.storedDefault(in: defaults), .sqlInsertNoAutoIncrement)
    }

    func testScopeWordingAllVsSelected() {
        XCTAssertEqual(SAClaudeQueryCopyAction.plain.scopeDescription(selectedRows: 0, totalRows: 5), "Copy 5 rows")
        XCTAssertEqual(SAClaudeQueryCopyAction.plain.scopeDescription(selectedRows: 0, totalRows: 1), "Copy 1 row")
        XCTAssertEqual(SAClaudeQueryCopyAction.withColumnNames.scopeDescription(selectedRows: 0, totalRows: 5), "Copy 5 rows with column names")
        XCTAssertEqual(SAClaudeQueryCopyAction.sqlInsert.scopeDescription(selectedRows: 2, totalRows: 5), "Copy 2 selected rows as SQL INSERT")
        XCTAssertEqual(SAClaudeQueryCopyAction.sqlInsertNoAutoIncrement.scopeDescription(selectedRows: 1, totalRows: 5),
                       "Copy 1 selected row as SQL INSERT (no auto_inc)")
        XCTAssertEqual(SAClaudeQueryCopyAction.footer(selectedRows: 0, totalRows: 5), "Copies 5 rows · nothing selected")
        XCTAssertEqual(SAClaudeQueryCopyAction.footer(selectedRows: 0, totalRows: 1), "Copies 1 row · nothing selected")
        XCTAssertEqual(SAClaudeQueryCopyAction.footer(selectedRows: 2, totalRows: 5), "Copies 2 selected rows")
        XCTAssertEqual(SAClaudeQueryCopyAction.footer(selectedRows: 1, totalRows: 5), "Copies 1 selected row")
    }

    func testAvailability() {
        XCTAssertEqual(SAClaudeQueryCopyAction.plain.unavailableReason(totalRows: 0, hasColumnDefinitions: true), "No rows to copy")
        XCTAssertNil(SAClaudeQueryCopyAction.plain.unavailableReason(totalRows: 3, hasColumnDefinitions: false))
        XCTAssertNil(SAClaudeQueryCopyAction.withColumnNames.unavailableReason(totalRows: 3, hasColumnDefinitions: false))
        XCTAssertEqual(SAClaudeQueryCopyAction.sqlInsert.unavailableReason(totalRows: 3, hasColumnDefinitions: false),
                       "SQL INSERT needs a result with column details")
        XCTAssertEqual(SAClaudeQueryCopyAction.sqlInsertNoAutoIncrement.unavailableReason(totalRows: 0, hasColumnDefinitions: false), "No rows to copy")
        XCTAssertNil(SAClaudeQueryCopyAction.sqlInsert.unavailableReason(totalRows: 3, hasColumnDefinitions: true))
    }
}
