//
//  SAClaudeRecordFieldsTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest

final class SAClaudeRecordFieldsTests: XCTestCase {
    private func field(
        _ id: Int = 0,
        _ name: String = "col",
        _ value: String = "",
        type: String = "",
        isNull: Bool = false,
        notLoaded: Bool = false
    ) -> SARecordField {
        SARecordField(id: id, name: name, value: value, type: type, isNull: isNull, notLoaded: notLoaded)
    }

    private func field(
        id: Int = 0,
        name: String = "col",
        value: String,
        type: String = "",
        isNull: Bool = false,
        notLoaded: Bool = false
    ) -> SARecordField {
        field(id, name, value, type: type, isNull: isNull, notLoaded: notLoaded)
    }

    private func display(_ field: SARecordField) -> SAClaudeRecordDisplayValue {
        SAClaudeRecordFields.displayValue(field)
    }

    // MARK: - Display value

    func testDisplayValueTextNullNotLoaded() {
        XCTAssertEqual(display(field(value: "Ada")), .text("Ada"))
        XCTAssertEqual(display(field(value: "ignored", isNull: true)), .null)
        XCTAssertEqual(display(field(value: "(not loaded)", notLoaded: true)), .notLoaded)
    }

    func testNullEmptyAndLiteralNullAreDistinct() {
        XCTAssertEqual(display(field(value: "NULL", isNull: true)), .null)
        XCTAssertEqual(display(field(value: "")), .text(""))
        XCTAssertEqual(display(field(value: "NULL", isNull: false)), .text("NULL"))
    }

    func testJSONPrettyPrintedOnlyForJSONType() {
        let source = "{\"b\":1,\"a\":[1,2]}"
        let pretty = "{\n  \"b\": 1,\n  \"a\": [\n    1,\n    2\n  ]\n}"
        XCTAssertEqual(display(field(value: source, type: "JSON")), .text(pretty))
        XCTAssertEqual(display(field(value: source, type: "json")), .text(pretty))
        XCTAssertEqual(display(field(value: source, type: "LONGTEXT")), .text(source))
        XCTAssertEqual(display(field(value: "{\"a\":", type: "json")), .text("{\"a\":"))
        XCTAssertEqual(display(field(value: "\"x\"", type: "JSON")), .text("\"x\""))
    }

    func testPrettyJSONPreservesKeyOrderAndTokens() {
        let source = "{\"z\":1.50,\"a\":{\"y\":null,\"x\":true},\"m\":\"caf\\u00e9 \\\"q\\\"\",\"e\":1e-3}"
        let expected = """
        {
          "z": 1.50,
          "a": {
            "y": null,
            "x": true
          },
          "m": "caf\\u00e9 \\"q\\"",
          "e": 1e-3
        }
        """
        XCTAssertEqual(SAClaudeRecordFields.prettyJSON(source), expected)
    }

    func testPrettyJSONEmptyContainersAndWhitespace() {
        XCTAssertEqual(SAClaudeRecordFields.prettyJSON(" \n[ ] \t"), "[]")
        XCTAssertEqual(SAClaudeRecordFields.prettyJSON("{\"a\":{},\"b\":[]}"), "{\n  \"a\": {},\n  \"b\": []\n}")
        XCTAssertEqual(SAClaudeRecordFields.prettyJSON("[ \"é\" , 1 ]"), "[\n  \"é\",\n  1\n]")
    }

    func testPrettyJSONRejectsInvalidAndScalars() {
        for bad in ["", "1", "\"x\"", "null", "{", "{\"a\":}", "[1,]", "{\"a\":1,}", "[1] x", "[01]", "[\"a\nb\"]", "{a:1}", "[tru]", "[1.]", "['a']"] {
            XCTAssertNil(SAClaudeRecordFields.prettyJSON(bad), bad)
        }
    }

    func testPrettyJSONDeepNestingIsRejectedNotCrashed() {
        let deep = String(repeating: "[", count: 5_000) + String(repeating: "]", count: 5_000)
        XCTAssertNil(SAClaudeRecordFields.prettyJSON(deep))
        let ok = String(repeating: "[", count: 50) + String(repeating: "]", count: 50)
        XCTAssertNotNil(SAClaudeRecordFields.prettyJSON(ok))
    }

    func testDisplayCap() {
        let cap = SAClaudeRecordFields.displayCharacterCap
        XCTAssertEqual(cap, 100_000)
        let text = String(repeating: "x", count: cap + 1)
        XCTAssertEqual(display(field(value: text)), .text(String(repeating: "x", count: cap) + "…"))
        let exact = String(repeating: "x", count: cap)
        XCTAssertEqual(display(field(value: exact)), .text(exact))
    }

    // MARK: - Matching

    private func ns(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

    func testMatchNameAndValueRanges() {
        let f = field(1, "lead_id", "sales lead: the leads")
        let match = SAClaudeRecordFields.match(f, display: display(f), query: "lead")
        XCTAssertEqual(match, SAClaudeRecordMatch(nameRanges: [ns(0, 4)], valueRanges: [ns(6, 4), ns(16, 4)]))
    }

    func testEmptyQueryMatchesEverythingWithNoRanges() {
        let f = field(1, "a", "b")
        let empty = SAClaudeRecordMatch(nameRanges: [], valueRanges: [])
        XCTAssertEqual(SAClaudeRecordFields.match(f, display: display(f), query: ""), empty)
        XCTAssertEqual(SAClaudeRecordFields.match(f, display: display(f), query: "  \n"), empty)
    }

    func testMatchTrimsQueryAndReturnsNilWithoutMatch() {
        let f = field(1, "name", "Ada")
        XCTAssertNotNil(SAClaudeRecordFields.match(f, display: display(f), query: "  ada "))
        XCTAssertNil(SAClaudeRecordFields.match(f, display: display(f), query: "zzz"))
    }

    func testMatchIsCaseAndDiacriticInsensitive() {
        let f = field(1, "city", "café au lait")
        let match = SAClaudeRecordFields.match(f, display: display(f), query: "CAFE")
        XCTAssertEqual(match?.valueRanges, [ns(0, 4)])
        let g = field(2, "Résumé", "x")
        XCTAssertEqual(SAClaudeRecordFields.match(g, display: display(g), query: "resume")?.nameRanges, [ns(0, 6)])
    }

    func testNullMatchesNullQuery() {
        let f = field(1, "deleted_at", "", isNull: true)
        XCTAssertEqual(SAClaudeRecordFields.match(f, display: .null, query: "null")?.valueRanges, [ns(0, 4)])
        let nl = field(2, "x", "(not loaded)", notLoaded: true)
        XCTAssertNil(SAClaudeRecordFields.match(nl, display: .notLoaded, query: "loaded"))
        XCTAssertNil(SAClaudeRecordFields.match(nl, display: .notLoaded, query: "null"))
    }

    func testMatchRangesAreInDisplayedText() {
        let f = field(1, "doc", "{\"a\":\"needle\"}", type: "JSON")
        let shown = display(f)
        guard case .text(let text) = shown else { return XCTFail("expected text") }
        let match = SAClaudeRecordFields.match(f, display: shown, query: "needle")
        XCTAssertEqual(match?.valueRanges.count, 1)
        XCTAssertEqual((text as NSString).substring(with: match!.valueRanges[0]), "needle")
    }

    // MARK: - Visible fields

    func testSearchKeepsEditingFieldVisible() {
        let fields = [field(0, "id", "1"), field(1, "name", "Ada"), field(2, "bio", "mathematician"), field(3, "note", "Ada again")]
        XCTAssertEqual(SAClaudeRecordFields.search(fields, query: "ada", editingFieldID: nil).fields.map(\.id), [1, 3])
        XCTAssertEqual(SAClaudeRecordFields.search(fields, query: "ada", editingFieldID: 0).fields.map(\.id), [0, 1, 3])
        XCTAssertEqual(SAClaudeRecordFields.search(fields, query: "ada", editingFieldID: 3).fields.map(\.id), [1, 3])
        XCTAssertEqual(SAClaudeRecordFields.search(fields, query: "", editingFieldID: 2).fields.map(\.id), [0, 1, 2, 3])
        XCTAssertEqual(SAClaudeRecordFields.search(fields, query: "zzz", editingFieldID: 2).fields.map(\.id), [2])
        XCTAssertEqual(SAClaudeRecordFields.search(fields, query: "zzz", editingFieldID: nil).fields, [])
    }

    func testVisibleFieldsMatchNamesAndNullChip() {
        let fields = [field(0, "deleted_at", "", isNull: true), field(1, "title", "hello")]
        XCTAssertEqual(SAClaudeRecordFields.search(fields, query: "null", editingFieldID: nil).fields.map(\.id), [0])
        XCTAssertEqual(SAClaudeRecordFields.search(fields, query: "TITLE", editingFieldID: nil).fields.map(\.id), [1])
    }

    // MARK: - Collapse

    func testSearchCountsMatchesAndUsesSuppliedDisplay() {
        let fields = [field(0, "id", "1"), field(1, "name", "Ada"), field(2, "note", "Ada again")]
        let result = SAClaudeRecordFields.search(fields, query: "ada", editingFieldID: 0)
        XCTAssertEqual(result.fields.map(\.id), [0, 1, 2])
        XCTAssertEqual(result.matchCount, 2)
        XCTAssertEqual(Set(result.matches.keys), [1, 2])
        XCTAssertEqual(SAClaudeRecordFields.search(fields, query: "  ", editingFieldID: nil),
                       SAClaudeRecordSearchResult(fields: fields, matches: [:], matchCount: 0))

        let cached = SAClaudeRecordFields.search(fields, query: "cached", editingFieldID: nil) { _ in .text("cached value") }
        XCTAssertEqual(cached.fields.map(\.id), [0, 1, 2])
    }

    // MARK: - Wrapped lines and collapse

    private let valueFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    /// A width that holds exactly `columns` characters of the mono value font.
    private func width(columns: Int) -> CGFloat {
        var glyph = CGGlyph()
        var character = UniChar(UInt8(ascii: "x"))
        CTFontGetGlyphsForCharacters(valueFont, &character, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(valueFont, .horizontal, &glyph, &advance, 1)
        return advance.width * CGFloat(columns) + advance.width / 2
    }

    /// One unbroken paragraph of 200 characters, 20 to a wrapped line, with `word` placed at `offset`.
    private func paragraph(with word: String, at offset: Int) -> String {
        var characters = Array(repeating: Character("x"), count: 200)
        for (index, character) in word.enumerated() {
            characters[offset + index] = character
        }
        return String(characters)
    }

    func testMatchOnWrappedLineEightOfOneParagraphForcesExpansion() {
        let text = paragraph(with: "needle", at: 7 * 20 + 5)
        let layout = SAClaudeRecordFields.lineLayout(text, width: width(columns: 20), font: valueFont)
        XCTAssertEqual(layout, SAClaudeRecordLineLayout(lineCount: 10, collapsedEnd: 120))

        let f = field(1, "body", text)
        let match = SAClaudeRecordFields.match(f, display: display(f), query: "needle")!
        XCTAssertTrue(SAClaudeRecordFields.matchStartsBelow(match.valueRanges, collapsedEnd: layout.collapsedEnd))
        XCTAssertEqual(SAClaudeRecordFields.fold(layout, expanded: false, valueRanges: match.valueRanges),
                       SAClaudeRecordFold(collapsed: false, link: .none))
    }

    func testMatchOnWrappedLineThreeStaysCollapsedWithShowAllCount() {
        let text = paragraph(with: "needle", at: 2 * 20 + 5)
        let layout = SAClaudeRecordFields.lineLayout(text, width: width(columns: 20), font: valueFont)
        let f = field(1, "body", text)
        let match = SAClaudeRecordFields.match(f, display: display(f), query: "needle")!

        XCTAssertFalse(SAClaudeRecordFields.matchStartsBelow(match.valueRanges, collapsedEnd: layout.collapsedEnd))
        XCTAssertEqual(SAClaudeRecordFields.fold(layout, expanded: false, valueRanges: match.valueRanges),
                       SAClaudeRecordFold(collapsed: true, link: .showAll(10)))
    }

    func testMatchBelowCollapsedLinesForcesExpansion() {
        let text = (1...40).map { $0 == 30 ? "line 30 needle" : "line \($0)" }.joined(separator: "\n")
        let layout = SAClaudeRecordFields.lineLayout(text, width: 600, font: valueFont)
        XCTAssertEqual(layout.lineCount, 40)
        XCTAssertEqual(layout.collapsedEnd, (text as NSString).range(of: "line 7").location)

        let f = field(1, "body", text)
        let below = SAClaudeRecordFields.match(f, display: display(f), query: "needle")!
        XCTAssertEqual(SAClaudeRecordFields.fold(layout, expanded: false, valueRanges: below.valueRanges),
                       SAClaudeRecordFold(collapsed: false, link: .none))

        let onSixthLine = SAClaudeRecordFields.match(f, display: display(f), query: "line 6")!
        XCTAssertEqual(SAClaudeRecordFields.fold(layout, expanded: false, valueRanges: onSixthLine.valueRanges),
                       SAClaudeRecordFold(collapsed: true, link: .showAll(40)))
    }

    func testFoldLinks() {
        let long = SAClaudeRecordLineLayout(lineCount: 9, collapsedEnd: 50)
        XCTAssertEqual(SAClaudeRecordFields.fold(long, expanded: false, valueRanges: []), SAClaudeRecordFold(collapsed: true, link: .showAll(9)))
        XCTAssertEqual(SAClaudeRecordFields.fold(long, expanded: true, valueRanges: []), SAClaudeRecordFold(collapsed: false, link: .showLess))
        let hitBelow = [NSRange(location: 60, length: 3)]
        XCTAssertEqual(SAClaudeRecordFields.fold(long, expanded: true, valueRanges: hitBelow), SAClaudeRecordFold(collapsed: false, link: .none),
                       "Show less can't fold a value a search hit holds open")
        let short = SAClaudeRecordLineLayout(lineCount: 6, collapsedEnd: 30)
        XCTAssertEqual(SAClaudeRecordFields.fold(short, expanded: false, valueRanges: []), SAClaudeRecordFold(collapsed: false, link: .none))
    }

    func testTrailingLineBreakAddsNoLine() {
        let six = (1...6).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertEqual(SAClaudeRecordFields.lineLayout(six + "\n", width: 600, font: valueFont).lineCount, 6)
        XCTAssertEqual(SAClaudeRecordFields.fold(SAClaudeRecordFields.lineLayout(six + "\n", width: 600, font: valueFont), expanded: false, valueRanges: []),
                       SAClaudeRecordFold(collapsed: false, link: .none))
        XCTAssertEqual(SAClaudeRecordFields.lineLayout(six + "\nline 7", width: 600, font: valueFont).lineCount, 7)
        XCTAssertEqual(SAClaudeRecordFields.lineLayout("", width: 600, font: valueFont), SAClaudeRecordLineLayout(lineCount: 1, collapsedEnd: 0))
        XCTAssertEqual(SAClaudeRecordFields.lineLayout("one", width: 600, font: valueFont), SAClaudeRecordLineLayout(lineCount: 1, collapsedEnd: 3))
    }

    /// The windowed breaker gives the whole-paragraph typesetter's breaks, past the window boundary too.
    func testWindowedBreaksMatchWholeParagraph() {
        let words = ["select", "a", "lorem", "ipsum", "path/to/file.txt", "naïve", "averyveryverylongtokenwithoutspaces", "a-b-c", "中文字符", "🙂"]
        var text = ""
        var index = 0
        while text.utf16.count < 3 * SAClaudeRecordFields.lineBreakWindow(width: 300) {
            text += words[(index * 7) % words.count] + (index % 23 == 0 ? "\n" : " ")
            index += 1
        }
        let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: valueFont]))
        let length = (text as NSString).length
        var breaks: [Int] = []
        var start = 0
        while start < length {
            start += max(CTTypesetterSuggestLineBreak(typesetter, start, 300), 1)
            breaks.append(start)
        }
        XCTAssertGreaterThan(breaks.count, 60)
        XCTAssertEqual(SAClaudeRecordFields.lineLayout(text, width: 300, font: valueFont).lineCount, breaks.count)
        for line in [6, 30, breaks.count / 2, breaks.count - 2] {
            XCTAssertEqual(SAClaudeRecordFields.lineLayout(text, width: 300, font: valueFont, limit: line).collapsedEnd, breaks[line - 1], "line \(line)")
        }
    }

    func testIsCollapsedRules() {
        XCTAssertEqual(SAClaudeRecordFields.collapsedLineLimit, 6)
        XCTAssertFalse(SAClaudeRecordFields.isCollapsed(lineCount: 6, expanded: false, matchStartsBelowLimit: false))
        XCTAssertTrue(SAClaudeRecordFields.isCollapsed(lineCount: 7, expanded: false, matchStartsBelowLimit: false))
        XCTAssertFalse(SAClaudeRecordFields.isCollapsed(lineCount: 7, expanded: true, matchStartsBelowLimit: false))
    }

    // MARK: - Count, stepping, state

    func testMatchCountText() {
        XCTAssertEqual(SAClaudeRecordFields.matchCountText(1), "1 match")
        XCTAssertEqual(SAClaudeRecordFields.matchCountText(3), "3 matches")
        XCTAssertEqual(SAClaudeRecordFields.matchCountText(0), "0 matches")
    }

    func testRowStepEnablement() {
        func step(_ i: Int, _ n: Int) -> [Bool] {
            let s = SAClaudeRecordFields.rowStep(index: i, count: n)
            return [s.previous, s.next]
        }
        XCTAssertEqual(step(0, 1), [false, false])
        XCTAssertEqual(step(0, 3), [false, true])
        XCTAssertEqual(step(1, 3), [true, true])
        XCTAssertEqual(step(2, 3), [true, false])
        XCTAssertEqual(step(-1, 3), [false, false])
        XCTAssertEqual(step(0, 0), [false, false])
        XCTAssertEqual(step(5, 3), [false, false])
    }

    func testUpdateKeepsStateOnlyForSameRow() {
        let state = SAClaudeRecordPanelState(rowKey: "orders#4", expandedFieldIDs: [1, 7])
        XCTAssertEqual(SAClaudeRecordFields.carry(state, toRowKey: "orders#4"), state)
        XCTAssertEqual(
            SAClaudeRecordFields.carry(state, toRowKey: "orders#5"),
            SAClaudeRecordPanelState(rowKey: "orders#5", expandedFieldIDs: [])
        )
    }

    // MARK: - Field mapping

    func testFieldsFromDictionariesMapsNewKeys() {
        let fields = SARecordViewController.fields(from: [
            ["id": 3, "name": "a", "value": "v", "type": "JSON", "isNull": true, "notLoaded": false] as NSDictionary,
            ["name": "b", "value": "w"] as NSDictionary,
            ["id": 9, "name": "c", "value": "", "notLoaded": NSNumber(value: true)] as NSDictionary
        ])
        XCTAssertEqual(fields[0], SARecordField(id: 3, name: "a", value: "v", type: "JSON", isNull: true, notLoaded: false))
        XCTAssertEqual(fields[1], SARecordField(id: 1, name: "b", value: "w", type: "", isNull: false, notLoaded: false))
        XCTAssertEqual(fields[2], SARecordField(id: 9, name: "c", value: "", type: "", isNull: false, notLoaded: true))
    }
}
