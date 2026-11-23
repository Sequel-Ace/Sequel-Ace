//
//  SAClaudeTabBarLayoutTests.swift
//  Unit Tests
//

import XCTest

final class SAClaudeTabBarLayoutTests: XCTestCase {

    private typealias L = SAClaudeTabBarLayout

    func testGlyphsFromActions() {
        XCTAssertEqual(L.glyphs(forActions: ["addRow:", "removeRow:", "duplicateRow:", "reloadTable:", "multipleLineEditingButtonClicked:", "toggleRuleEditorVisible:"]),
                       [.add, .remove, .duplicate, .refresh, .editMode, .filter])
        XCTAssertEqual(L.glyphs(forActions: ["addField:", "removeField:", "duplicateField:", "unhideIndexesView:", "viewStatus:", "toggleColumnView:"]),
                       [.add, .remove, .duplicate, .indexes, .info, .columns])
        XCTAssertEqual(L.glyphs(forActions: ["addIndex:", "removeIndex:", "addRelation:", "removeRelation:", "refreshRelations:", "addTrigger:", "removeTrigger:", "refreshTriggers:"]),
                       [.add, .remove, .add, .remove, .refresh, .add, .remove, .refresh])
        // Pagination: the first navigate button is "previous", the second "next".
        XCTAssertEqual(L.glyphs(forActions: ["navigatePaginationFromButton:", "togglePagination:", "navigatePaginationFromButton:"]),
                       [.chevronLeft, .pageOptions, .chevronRight])
        XCTAssertEqual(L.glyphs(forActions: ["", "somethingElse:"]), [nil, nil])
    }

    func testButtonPositions() {
        XCTAssertEqual(L.leftXs(count: 3), [10, 40, 70])
        XCTAssertEqual(L.leftXs(count: 0), [])
        // Rightmost button ends 10pt from the edge; returned left to right.
        XCTAssertEqual(L.rightXs(count: 3, width: 700), [602, 632, 662])
        XCTAssertEqual(L.rightXs(count: 0, width: 700), [])
        XCTAssertEqual(L.centredY(height: 28), 2)
        XCTAssertEqual(L.centredY(height: 24), 4)
        XCTAssertEqual(L.centredY(height: 16), 8)
    }
}
