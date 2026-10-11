//
//  SAScriptConsoleBlockBuilderTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAScriptConsoleBlockBuilderTests: XCTestCase {

    private let style = SAScriptConsoleStyle(font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                                             statusFont: .systemFont(ofSize: 11),
                                             text: .white, keyword: .blue, string: .green, backtick: .red,
                                             number: .orange, comment: .gray, muted: .darkGray, errorText: .systemRed)

    func testTokensFindKeywordsStringsNumbersBackticksAndComments() {
        let sql = "SELECT `id`, 'a b', 42 FROM t -- note"
        let kinds = SAClaudeSQLColouring.tokens(in: sql).map { ((sql as NSString).substring(with: $0.range), $0.kind) }
        XCTAssertTrue(kinds.contains { $0 == ("SELECT", .keyword) })
        XCTAssertTrue(kinds.contains { $0 == ("FROM", .keyword) })
        XCTAssertTrue(kinds.contains { $0 == ("`id`", .backtick) })
        XCTAssertTrue(kinds.contains { $0 == ("'a b'", .string) })
        XCTAssertTrue(kinds.contains { $0 == ("42", .number) })
        XCTAssertTrue(kinds.contains { $0 == ("-- note", .comment) })
        XCTAssertFalse(kinds.contains { $0.0 == "id" && $0.1 == .keyword })
    }

    func testKeywordsInsideStringsAreNotKeywords() {
        let sql = "SELECT 'from where'"
        let kinds = SAClaudeSQLColouring.tokens(in: sql).map { ((sql as NSString).substring(with: $0.range), $0.kind) }
        XCTAssertEqual(kinds.filter { $0.1 == .keyword }.map(\.0), ["SELECT"])
    }

    func testSelectBlockHasSQLRowsAndStatus() {
        let builder = SAScriptConsoleBlockBuilder(style: style)
        let out = builder.append([.statementStarted(sql: "SELECT id FROM t"), .resultHeader("id\n"), .row("101\n"),
                                  .rowsInSet(count: 1), .statementFinished(time: 0.0006, continuing: true)])
        XCTAssertEqual(out.text.string, "SELECT id FROM t\nid\n101\n1 row · 0.6 ms\n")
        XCTAssertEqual(out.text.attribute(.saConsoleBlockStart, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertTrue(out.errorRanges.isEmpty)
    }

    func testLongSQLIsCappedAtSixLines() {
        let sql = (1...9).map { "line \($0)" }.joined(separator: "\n")
        let out = SAScriptConsoleBlockBuilder(style: style).append([.statementStarted(sql: sql)])
        let lines = out.text.string.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(Array(lines.prefix(6)).map(String.init), (1...6).map { "line \($0)" })
        XCTAssertEqual(String(lines[6]), "… 3 more lines")
    }

    func testFailedBlockIsFlaggedAndStatusSaysStopped() {
        let builder = SAScriptConsoleBlockBuilder(style: style)
        _ = builder.append([.statementStarted(sql: "SELECT 1"), .rowsInSet(count: 0), .statementFinished(time: 0.001, continuing: true)])
        let second = builder.append([.statementStarted(sql: "SELEC 2")])
        let third = builder.append([.failed(message: "ERROR 1064 (42000) at line 2: syntax"), .statementFinished(time: 0, continuing: false)])
        XCTAssertTrue(third.text.string.contains("ERROR 1064 (42000) at line 2: syntax\n"))
        XCTAssertTrue(third.text.string.hasSuffix("failed · stopped\n"))
        // The error range covers the whole second block: from its SQL to its status line.
        let blockStart = (builder.allText as NSString).range(of: "SELEC 2").location
        XCTAssertEqual(third.errorRanges.first?.location, blockStart)
        XCTAssertEqual(NSMaxRange(third.errorRanges.first!), builder.allText.utf16.count)
        XCTAssertEqual(second.errorRanges, [])
    }

    func testStatusTexts() {
        XCTAssertEqual(SAScriptConsoleBlockBuilder.statusText(rows: 0, affected: nil, failed: false, cancelled: false, continuing: true, time: 0.0005), "Empty set · 0.5 ms")
        XCTAssertEqual(SAScriptConsoleBlockBuilder.statusText(rows: 2, affected: nil, failed: false, cancelled: false, continuing: true, time: 0.0006), "2 rows · 0.6 ms")
        XCTAssertEqual(SAScriptConsoleBlockBuilder.statusText(rows: nil, affected: 1, failed: false, cancelled: false, continuing: true, time: 0.0012), "1 row affected · 1.2 ms")
        XCTAssertEqual(SAScriptConsoleBlockBuilder.statusText(rows: nil, affected: nil, failed: true, cancelled: false, continuing: true, time: 0), "failed · continued")
        XCTAssertEqual(SAScriptConsoleBlockBuilder.timeText(2.5), "2.50 s")
    }

    func testStopBeforeTheStatementRanStillEndsTheBlock() {
        let out = SAScriptConsoleBlockBuilder(style: style).append([.statementStarted(sql: "DELETE FROM t"), .cancelled])
        XCTAssertEqual(out.text.string, "DELETE FROM t\ncancelled\n")
    }

    func testStopRacingCompletionWritesOneStatusLine() {
        let out = SAScriptConsoleBlockBuilder(style: style).append([.statementStarted(sql: "UPDATE t SET a = 1"), .queryOK(affectedRows: 1),
                                                                     .cancelled, .statementFinished(time: 0.001, continuing: false)])
        XCTAssertEqual(out.text.string, "UPDATE t SET a = 1\ncancelled\n")
    }
}
