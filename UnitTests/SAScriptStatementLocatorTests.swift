//
//  SAScriptStatementLocatorTests.swift
//  Unit Tests
//

import XCTest

final class SAScriptStatementLocatorTests: XCTestCase {

    func testLineNumberAtStartIsOne() {
        XCTAssertEqual(SAScriptStatementLocator.lineNumber(ofOffset: 0, in: "SELECT 1;"), 1)
    }

    func testLineNumberCountsLineFeeds() {
        let text: NSString = "SELECT 1;\n\nSELECT 2;"
        XCTAssertEqual(SAScriptStatementLocator.lineNumber(ofOffset: text.range(of: "SELECT 2").location, in: text), 3)
    }

    func testLineNumberCountsCRLFOnce() {
        let text: NSString = "SELECT 1;\r\nSELECT 2;"
        XCTAssertEqual(SAScriptStatementLocator.lineNumber(ofOffset: text.range(of: "SELECT 2").location, in: text), 2)
    }

    func testLineNumberCountsLoneCR() {
        let text: NSString = "SELECT 1;\rSELECT 2;"
        XCTAssertEqual(SAScriptStatementLocator.lineNumber(ofOffset: text.range(of: "SELECT 2").location, in: text), 2)
    }

    func testLineNumberClampsOffsetPastEnd() {
        XCTAssertEqual(SAScriptStatementLocator.lineNumber(ofOffset: 999, in: "a\nb"), 2)
    }

    func testFirstNonWhitespaceOffsetSkipsSpacesAndNewlines() {
        let text: NSString = "SELECT 1;\n  \n\tSELECT 2"
        let range = NSRange(location: 9, length: text.length - 9)
        XCTAssertEqual(SAScriptStatementLocator.firstNonWhitespaceOffset(in: range, of: text),
                       text.range(of: "SELECT 2").location)
    }

    func testFirstNonWhitespaceOffsetOfBlankRangeIsRangeStart() {
        let text: NSString = "a   "
        XCTAssertEqual(SAScriptStatementLocator.firstNonWhitespaceOffset(in: NSRange(location: 1, length: 3), of: text), 1)
    }

    func testIsEmptyStatement() {
        XCTAssertTrue(SAScriptStatementLocator.isEmptyStatement(""))
        XCTAssertTrue(SAScriptStatementLocator.isEmptyStatement("  \n\t "))
        XCTAssertTrue(SAScriptStatementLocator.isEmptyStatement("-- just a note"))
        XCTAssertTrue(SAScriptStatementLocator.isEmptyStatement("# hash note"))
        XCTAssertTrue(SAScriptStatementLocator.isEmptyStatement("/* block */"))
        XCTAssertFalse(SAScriptStatementLocator.isEmptyStatement("-- note\nSELECT 1"))
        XCTAssertFalse(SAScriptStatementLocator.isEmptyStatement("SELECT 1"))
    }
}
