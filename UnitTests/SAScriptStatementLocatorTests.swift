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

    func testIncrementalLineNumberMatchesFullCount() {
        let text: NSString = "SELECT 1;\nSELECT 2;\r\n\r\nSELECT 3;\rSELECT 4;\n\r\nSELECT 5;"
        let offsets = ["SELECT 1", "SELECT 2", "SELECT 3", "SELECT 4", "SELECT 5"].map { text.range(of: $0).location } + [text.length]
        var previousOffset = 0
        var previousLine = 1
        for offset in offsets {
            let line = SAScriptStatementLocator.lineNumber(ofOffset: offset, in: text, from: previousOffset, startLine: previousLine)
            XCTAssertEqual(line, SAScriptStatementLocator.lineNumber(ofOffset: offset, in: text), "offset \(offset)")
            previousOffset = offset
            previousLine = line
        }
    }

    func testIncrementalLineNumberFromMidText() {
        let text: NSString = "a\nb\r\nc\rd\n\ne"
        let start = text.range(of: "b").location
        let startLine = SAScriptStatementLocator.lineNumber(ofOffset: start, in: text)
        XCTAssertEqual(startLine, 2)
        for target in ["c", "d", "e"] {
            let offset = text.range(of: target).location
            XCTAssertEqual(SAScriptStatementLocator.lineNumber(ofOffset: offset, in: text, from: start, startLine: startLine),
                           SAScriptStatementLocator.lineNumber(ofOffset: offset, in: text), target)
        }
        XCTAssertEqual(SAScriptStatementLocator.lineNumber(ofOffset: text.range(of: "e").location, in: text, from: start, startLine: startLine), 6)
        XCTAssertEqual(SAScriptStatementLocator.lineNumber(ofOffset: start, in: text, from: start, startLine: startLine), startLine)
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
        XCTAssertFalse(SAScriptStatementLocator.isEmptyStatement("/*!40101 SET NAMES utf8 */"))
    }
}
