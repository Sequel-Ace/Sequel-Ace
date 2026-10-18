//
//  SAClaudeServerVariablesModelTests.swift
//  Unit Tests
//
//  The Server Variables sheet's logic: search hits, the full-value strip, selection kept by name, layout.
//

import XCTest

final class SAClaudeServerVariablesModelTests: XCTestCase {

    private typealias Search = SAClaudeServerVariablesSearch

    // MARK: Search

    func testRangesAreCaseInsensitiveAndNonOverlapping() {
        // "on" in "=on", inside "union" and in the second "=on".
        XCTAssertEqual(Search.ranges(of: "ON", in: "index_merge=on,index_merge_union=on"),
                       [NSRange(location: 12, length: 2), NSRange(location: 30, length: 2), NSRange(location: 33, length: 2)])
        XCTAssertEqual(Search.ranges(of: "aa", in: "aaaa"), [NSRange(location: 0, length: 2), NSRange(location: 2, length: 2)])
    }

    func testFilterIsTrimmedLikeTheController() {
        XCTAssertEqual(Search.needle("  SQL_Mode \n"), "sql_mode")
        XCTAssertEqual(Search.ranges(of: "  mode ", in: "sql_mode"), [NSRange(location: 4, length: 4)])
    }

    func testEmptyOrBlankFilterHasNoRanges() {
        XCTAssertEqual(Search.ranges(of: "", in: "sql_mode"), [])
        XCTAssertEqual(Search.ranges(of: "   ", in: "sql_mode"), [])
        XCTAssertEqual(Search.ranges(of: "xyz", in: "sql_mode"), [])
    }

    func testRangesAreUTF16() {
        // "é" is one unit, the emoji two: the hit after them starts at 4.
        XCTAssertEqual(Search.ranges(of: "x", in: "é😀 x"), [NSRange(location: 4, length: 1)])
    }

    func testSingleLineKeepsLengthsSoRangesStillFit() {
        let value = "line one\nline\ttwo\r\nthree"
        let line = Search.singleLine(value)
        XCTAssertEqual(line, "line one line two  three")
        XCTAssertEqual((line as NSString).length, (value as NSString).length)
        XCTAssertEqual(Search.ranges(of: "two", in: line), Search.ranges(of: "two", in: value))
        XCTAssertEqual(Search.singleLine("plain"), "plain")
    }

    func testExcerptStartsJustBeforeTheFirstHit() {
        let line = String(repeating: "a", count: 100) + "skip_scan=on,x=skip_scan"
        let ranges = Search.ranges(of: "skip_scan", in: line)
        let excerpt = Search.excerpt(line, ranges: ranges)
        XCTAssertTrue(excerpt.text.hasPrefix("…" + String(repeating: "a", count: 16) + "skip_scan"))
        XCTAssertEqual(excerpt.ranges, [NSRange(location: 17, length: 9), NSRange(location: 32, length: 9)])
        for range in excerpt.ranges { XCTAssertEqual((excerpt.text as NSString).substring(with: range), "skip_scan") }
    }

    func testExcerptLeavesAnEarlyHitAlone() {
        let line = "index_merge=on,skip_scan=on"
        let ranges = Search.ranges(of: "skip", in: line)
        XCTAssertEqual(Search.excerpt(line, ranges: ranges).text, line)
        XCTAssertEqual(Search.excerpt(line, ranges: []).text, line)
    }

    func testExcerptCutsOnAWholeCharacter() {
        // The cut would fall inside the emoji (two UTF-16 units): it starts at the emoji instead.
        let line = String(repeating: "a", count: 20) + "😀" + String(repeating: "b", count: 15) + "hit"
        let ranges = Search.ranges(of: "hit", in: line)
        let excerpt = Search.excerpt(line, ranges: ranges)
        XCTAssertTrue(excerpt.text.hasPrefix("…😀b"))
        XCTAssertEqual((excerpt.text as NSString).substring(with: excerpt.ranges[0]), "hit")
    }

    // MARK: Detail

    func testNothingSelectedHasNoDetail() {
        XCTAssertNil(SAClaudeServerVariablesDetail.make(selected: [], filter: "x"))
    }

    func testOneSelectedShowsAndCopiesTheFullValue() {
        let value = String(repeating: "index_merge=on,", count: 140) + "skip_scan=on"
        XCTAssertGreaterThan(value.utf8.count, 2048)
        let detail = SAClaudeServerVariablesDetail.make(selected: [SAClaudeServerVariable(name: "optimizer_switch", value: value)], filter: "skip")!
        XCTAssertEqual(detail.name, "optimizer_switch")
        XCTAssertEqual(detail.text, value)
        XCTAssertEqual(detail.copyText, value)
        XCTAssertEqual(detail.nameRanges, [])
        XCTAssertEqual(detail.textRanges, [NSRange(location: (value as NSString).length - 12, length: 4)])
        XCTAssertFalse(detail.isEmptyValue)
    }

    func testNameHitsAreHighlighted() {
        let detail = SAClaudeServerVariablesDetail.make(selected: [SAClaudeServerVariable(name: "sql_mode", value: "STRICT_TRANS_TABLES")], filter: "MODE")!
        XCTAssertEqual(detail.nameRanges, [NSRange(location: 4, length: 4)])
        XCTAssertEqual(detail.textRanges, [])
    }

    func testEmptyValueIsMarked() {
        let detail = SAClaudeServerVariablesDetail.make(selected: [SAClaudeServerVariable(name: "init_connect", value: "")], filter: "")!
        XCTAssertTrue(detail.isEmptyValue)
        XCTAssertEqual(detail.copyText, "")
    }

    func testSeveralSelectedShowNameValueLinesAndCopyInTheControllersFormat() {
        let selected = [SAClaudeServerVariable(name: "autocommit", value: "ON"), SAClaudeServerVariable(name: "sql_mode", value: "")]
        let detail = SAClaudeServerVariablesDetail.make(selected: selected, filter: "on")!
        XCTAssertNil(detail.name)
        XCTAssertEqual(detail.count, 2)
        XCTAssertEqual(detail.text, "autocommit = ON\nsql_mode = ")
        XCTAssertEqual(detail.copyText, "autocommit = ON\nsql_mode = \n")
        XCTAssertEqual(detail.textRanges, [NSRange(location: 13, length: 2)])
        XCTAssertFalse(detail.isEmptyValue)
    }

    // MARK: Selection

    func testSelectionFollowsTheNamesAfterAReload() {
        let before = ["autocommit", "sql_mode", "version"]
        let filtered = ["sql_auto_is_null", "sql_mode", "sql_safe_updates"]
        // sql_mode was row 1; after filtering it is still row 1 by chance — and row 0 must not take over autocommit's place.
        XCTAssertEqual(SAClaudeServerVariablesSelection.rows(selecting: [before[0], before[1]], in: filtered), IndexSet(integer: 1))
        XCTAssertEqual(SAClaudeServerVariablesSelection.rows(selecting: ["version"], in: ["a", "b", "version"]), IndexSet(integer: 2))
    }

    func testAFilteredOutSelectionSelectsNothing() {
        XCTAssertEqual(SAClaudeServerVariablesSelection.rows(selecting: ["version"], in: ["sql_mode"]), IndexSet())
        XCTAssertEqual(SAClaudeServerVariablesSelection.rows(selecting: [], in: ["sql_mode"]), IndexSet())
    }

    // MARK: Layout

    func testLayoutStacksHeaderListStripAndFooter() {
        let bounds = NSRect(x: 0, y: 0, width: 680, height: 560)
        let f = SAClaudeServerVariablesLayout.frames(in: bounds, saveWidth: 130, closeWidth: 90, buttonInset: 6)
        // Footer on the margin, drawn edges aligned to it.
        XCTAssertEqual(f.save.minX, 10)
        XCTAssertEqual(f.close.maxX, 670)
        XCTAssertEqual(f.save.minY, 16)
        // The strip above the footer, 30% of the height (168pt), then a hairline, the list, a hairline and the header.
        XCTAssertEqual(f.detail.minY, 16 + 28 + 4)
        XCTAssertEqual(f.detail.height, 168)
        XCTAssertEqual(f.bottomLine.minY, f.detail.maxY)
        XCTAssertEqual(f.table.minY, f.bottomLine.maxY)
        XCTAssertEqual(f.table.maxY, f.topLine.minY)
        XCTAssertEqual(f.topLine.maxY, 560 - 52)
        XCTAssertEqual(f.table.width, 680)
        // Header: search at the right margin, the count to its left, the title before that.
        XCTAssertEqual(f.search.maxX, 664)
        XCTAssertEqual(f.search.width, 245)
        XCTAssertEqual(f.count.maxX, f.search.minX - 8)
        XCTAssertEqual(f.title.minX, 16)
        XCTAssertEqual(f.title.maxX, f.count.minX - 8)
        XCTAssertEqual(f.search.midY, 560 - 26, accuracy: 1)
    }

    func testStripHeightIsClamped() {
        XCTAssertEqual(SAClaudeServerVariablesLayout.detailHeight(forHeight: 440), 150)
        XCTAssertEqual(SAClaudeServerVariablesLayout.detailHeight(forHeight: 1200), 240)
    }

    func testMinimumSizeLeavesTheListRoom() {
        let size = SAClaudeServerVariablesLayout.minimumSize
        let f = SAClaudeServerVariablesLayout.frames(in: NSRect(origin: .zero, size: size), saveWidth: 130, closeWidth: 90, buttonInset: 6)
        XCTAssertGreaterThanOrEqual(f.table.height, 150)
        XCTAssertGreaterThan(f.title.width, 100)
        XCTAssertLessThan(f.save.maxX, f.close.minX)
    }
}
