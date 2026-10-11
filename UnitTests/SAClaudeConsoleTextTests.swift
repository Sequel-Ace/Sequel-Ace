//
//  SAClaudeConsoleTextTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeConsoleTextTests: XCTestCase {

    private let style = SAClaudeConsoleTextStyle(font: .systemFont(ofSize: 13), text: .white, muted: .gray, error: .orange,
                                                 keyword: .blue, string: .green, backtick: .red, number: .purple, comment: .brown)

    private func colour(_ s: NSAttributedString, at index: Int) -> NSColor? {
        s.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    func testColumnIdentifiers() {
        XCTAssertEqual(SAClaudeConsoleColumn(identifier: "messageDate"), .time)
        XCTAssertEqual(SAClaudeConsoleColumn(identifier: "messageConnection"), .connection)
        XCTAssertEqual(SAClaudeConsoleColumn(identifier: "messageDatabase"), .database)
        XCTAssertEqual(SAClaudeConsoleColumn(identifier: "message"), .query)
    }

    func testQueryColumnIsColouredAndMetaIsMuted() {
        let q = SAClaudeConsoleText.attributed("SELECT 'a', 42 FROM `t`", column: .query, isError: false, style: style)
        XCTAssertEqual(q.string, "SELECT 'a', 42 FROM `t`")
        XCTAssertEqual(colour(q, at: 0), .blue)                          // SELECT
        XCTAssertEqual(colour(q, at: 7), .green)                         // 'a'
        XCTAssertEqual(colour(q, at: 12), .purple)                       // 42
        XCTAssertEqual(colour(q, at: 20), .red)                          // `t`
        XCTAssertEqual(colour(q, at: 6), .white)                         // plain text
        let meta = SAClaudeConsoleText.attributed("beato", column: .database, isError: false, style: style)
        XCTAssertEqual(colour(meta, at: 0), .gray)
    }

    func testErrorRowsAreErrorColouredInEveryColumn() {
        for column in [SAClaudeConsoleColumn.time, .connection, .database, .query] {
            let s = SAClaudeConsoleText.attributed("SELEC 2", column: column, isError: true, style: style)
            XCTAssertEqual(colour(s, at: 0), .orange)
            XCTAssertEqual(colour(s, at: 6), .orange)
        }
    }

    func testFontHasTabularDigits() {
        var tabular = style
        tabular.font = SAClaudeGridChrome.valueFont(.systemFont(ofSize: 13))
        let s = SAClaudeConsoleText.attributed("20:14:02", column: .time, isError: false, style: tabular)
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let features = font?.fontDescriptor.object(forKey: .featureSettings) as? [[NSFontDescriptor.FeatureKey: Int]] ?? []
        XCTAssertTrue(features.contains { $0[.typeIdentifier] == kNumberSpacingType && $0[.selectorIdentifier] == kMonospacedNumbersSelector })
    }

    func testTruncatedQueryWithOpenQuoteStillColours() {
        let s = SAClaudeConsoleText.attributed("SELECT 'unterminated /* cut", column: .query, isError: false, style: style)
        XCTAssertEqual(s.string, "SELECT 'unterminated /* cut")
        XCTAssertEqual(colour(s, at: 0), .blue)
        XCTAssertEqual(colour(s, at: 10), .green)
    }
}
