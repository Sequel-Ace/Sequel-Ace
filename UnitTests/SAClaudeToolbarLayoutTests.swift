//
//  SAClaudeToolbarLayoutTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeToolbarLayoutTests: XCTestCase {

    private typealias L = SAClaudeToolbarLayout

    func testIdentifiersMatchSPConstants() {
        // Saved toolbar layouts store these strings; they must never change (SPConstants.m "Main window toolbar").
        XCTAssertEqual(L.database, "DatabaseSelectToolbarItemIdentifier")
        XCTAssertEqual(L.history, "HistoryNavigationToolbarItemIdentifier")
        XCTAssertEqual(L.showConsole, "ShowConsoleIdentifier")
        XCTAssertEqual(L.clearConsole, "ClearConsoleIdentifier")
        XCTAssertEqual(L.structure, "SwitchToTableStructureToolbarItemIdentifier")
        XCTAssertEqual(L.content, "SwitchToTableContentToolbarItemIdentifier")
        XCTAssertEqual(L.query, "SwitchToRunQueryToolbarItemIdentifier")
        XCTAssertEqual(L.tableInfo, "SwitchToTableInfoToolbarItemIdentifier")
        XCTAssertEqual(L.relations, "SwitchToTableRelationsToolbarItemIdentifier")
        XCTAssertEqual(L.triggers, "SwitchToTableTriggersToolbarItemIdentifier")
        XCTAssertEqual(L.users, "SwitchToUserManagerToolbarItemIdentifier")
        XCTAssertEqual(L.recordView, "RecordViewToolbarItemIdentifier")
        XCTAssertEqual(L.flexibleSpace, NSToolbarItem.Identifier.flexibleSpace.rawValue)
        XCTAssertEqual(L.space, NSToolbarItem.Identifier.space.rawValue)
    }

    func testDefaultOrder() {
        XCTAssertEqual(L.defaultItems, [L.database, L.flexibleSpace, L.structure, L.content, L.relations, L.triggers, L.tableInfo,
                                        L.query, L.flexibleSpace, L.history, L.recordView, L.users, L.showConsole])
        XCTAssertEqual(L.selectableItems, [L.structure, L.content, L.query, L.tableInfo, L.relations, L.triggers, L.recordView])
    }

    func testMenuItemsAndTitles() {
        XCTAssertEqual(L.menuItems, [L.database, L.structure, L.content, L.relations, L.triggers, L.tableInfo, L.query,
                                     L.history, L.recordView, L.users, L.showConsole, L.clearConsole])
        XCTAssertEqual(L.menuItems.map(L.menuTitle(for:)),
                       ["Database", "Structure", "Content", "Relations", "Triggers", "Table info", "Query",
                        "History", "Record view", "Users", "Console", "Clear console"])
    }

    func testGlyphs() {
        XCTAssertEqual(L.glyph(for: L.structure), .structure)
        XCTAssertEqual(L.glyph(for: L.content), .table)
        XCTAssertEqual(L.glyph(for: L.relations), .relations)
        XCTAssertEqual(L.glyph(for: L.triggers), .triggers)
        XCTAssertEqual(L.glyph(for: L.tableInfo), .info)
        XCTAssertEqual(L.glyph(for: L.query), .query)
        XCTAssertEqual(L.glyph(for: L.recordView), .recordView)
        XCTAssertEqual(L.glyph(for: L.users), .users)
        XCTAssertEqual(L.glyph(for: L.showConsole), .console)
        XCTAssertEqual(L.glyph(for: L.clearConsole), .clearConsole)
        XCTAssertNil(L.glyph(for: L.database))
        XCTAssertNil(L.glyph(for: L.history))
        XCTAssertNil(L.glyph(for: L.flexibleSpace))
        XCTAssertNil(L.glyph(for: "Unknown"))
    }

    func testInsertionIndexFollowsTheDefaultOrder() {
        let current = [L.database, L.flexibleSpace, L.content, L.query, L.flexibleSpace, L.history, L.users]
        // After Database and the flexible space that follows it.
        XCTAssertEqual(L.insertionIndex(of: L.structure, into: current), 2)
        // After Content.
        XCTAssertEqual(L.insertionIndex(of: L.relations, into: current), 3)
        // After History (no space follows it).
        XCTAssertEqual(L.insertionIndex(of: L.recordView, into: current), 6)
        // Console after Users, at the end; Clear console after Console when present.
        XCTAssertEqual(L.insertionIndex(of: L.showConsole, into: current), 7)
        XCTAssertEqual(L.insertionIndex(of: L.clearConsole, into: current + [L.showConsole]), 8)
        // Nothing earlier in the default order is present: the start.
        XCTAssertEqual(L.insertionIndex(of: L.database, into: current.dropFirst().map { $0 }), 0)
        XCTAssertEqual(L.insertionIndex(of: L.structure, into: []), 0)
    }

    func testDatabasePillWidthClamps() {
        XCTAssertEqual(L.databasePillWidth(textWidth: 10), 120)
        XCTAssertEqual(L.databasePillWidth(textWidth: 100.2), 155)
        XCTAssertEqual(L.databasePillWidth(textWidth: 400), 220)
    }
}
