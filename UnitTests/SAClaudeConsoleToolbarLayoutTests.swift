//
//  SAClaudeConsoleToolbarLayoutTests.swift
//  Unit Tests
//

import XCTest

final class SAClaudeConsoleToolbarLayoutTests: XCTestCase {
    func testWideWindowKeepsTheFullSearchField() {
        let l = SAClaudeConsoleToolbarLayout.layout(totalWidth: 600, buttonWidths: [28, 70, 70])
        XCTAssertEqual(l.search.x, 10); XCTAssertEqual(l.search.width, 220)
        // Typed local: the inline literal is too slow for the type checker.
        let expected: [CGFloat] = [600 - 10 - 70 - 4 - 70 - 4 - 28, 600 - 10 - 70 - 4 - 70, 600 - 10 - 70]
        XCTAssertEqual(l.buttons.map(\.x), expected)
    }
    func testToolbarLayoutShrinksTheSearchFieldFirst() {
        let l = SAClaudeConsoleToolbarLayout.layout(totalWidth: 360, buttonWidths: [28, 70, 70])
        let firstButton = l.buttons[0].x
        XCTAssertLessThanOrEqual(l.search.x + l.search.width, firstButton - 4)
        XCTAssertGreaterThanOrEqual(l.search.width, 120)
    }
    func testSearchNeverBelowMinimum() {
        XCTAssertEqual(SAClaudeConsoleToolbarLayout.layout(totalWidth: 200, buttonWidths: [28, 70, 70]).search.width, 120)
    }
}
