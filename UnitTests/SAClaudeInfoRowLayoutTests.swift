//
//  SAClaudeInfoRowLayoutTests.swift
//  Unit Tests
//

import XCTest

final class SAClaudeInfoRowLayoutTests: XCTestCase {

    private typealias L = SAClaudeInfoRowLayout

    func testPartsSplitAtTheFirstTab() {
        XCTAssertEqual(L.parts(of: "Engine\tInnoDB")?.label, "Engine")
        XCTAssertEqual(L.parts(of: "Engine\tInnoDB")?.value, "InnoDB")
        XCTAssertEqual(L.parts(of: "Encoding\tutf8mb4 (general_ci)")?.value, "utf8mb4 (general_ci)")
    }

    func testRowsWithoutATabDrawAsBefore() {
        XCTAssertNil(L.parts(of: "Multiple selection"))
        XCTAssertNil(L.parts(of: "Table information"))
        XCTAssertNil(L.parts(of: ""))
    }

    func testValueIsRightAligned() {
        let row = NSRect(x: 0, y: 0, width: 300, height: 24)
        let frames = L.frames(in: row, labelWidth: 60, valueWidth: 50, leading: 15, trailing: 18)
        XCTAssertEqual(frames.label.minX, 15)
        XCTAssertEqual(frames.label.width, 60)
        XCTAssertEqual(frames.value.maxX, 282)
        XCTAssertEqual(frames.value.width, 50)
    }

    func testValueNarrowsToKeepTheGap() {
        let row = NSRect(x: 0, y: 0, width: 200, height: 24)
        let frames = L.frames(in: row, labelWidth: 100, valueWidth: 150, leading: 15, trailing: 18)
        // Label ends at 115; value may start at 123 and ends at 182.
        XCTAssertEqual(frames.label.maxX, 115)
        XCTAssertEqual(frames.value.minX, 123)
        XCTAssertEqual(frames.value.maxX, 182)
    }
}
