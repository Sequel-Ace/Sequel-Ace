//
//  SAClaudeRecordFieldsTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

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
        XCTAssertEqual(SAClaudeRecordFields.visibleFields(fields, query: "ada", editingFieldID: nil).map(\.id), [1, 3])
        XCTAssertEqual(SAClaudeRecordFields.visibleFields(fields, query: "ada", editingFieldID: 0).map(\.id), [0, 1, 3])
        XCTAssertEqual(SAClaudeRecordFields.visibleFields(fields, query: "ada", editingFieldID: 3).map(\.id), [1, 3])
        XCTAssertEqual(SAClaudeRecordFields.visibleFields(fields, query: "", editingFieldID: 2).map(\.id), [0, 1, 2, 3])
        XCTAssertEqual(SAClaudeRecordFields.visibleFields(fields, query: "zzz", editingFieldID: 2).map(\.id), [2])
        XCTAssertEqual(SAClaudeRecordFields.visibleFields(fields, query: "zzz", editingFieldID: nil), [])
    }

    func testVisibleFieldsMatchNamesAndNullChip() {
        let fields = [field(0, "deleted_at", "", isNull: true), field(1, "title", "hello")]
        XCTAssertEqual(SAClaudeRecordFields.visibleFields(fields, query: "null", editingFieldID: nil).map(\.id), [0])
        XCTAssertEqual(SAClaudeRecordFields.visibleFields(fields, query: "TITLE", editingFieldID: nil).map(\.id), [1])
    }

    // MARK: - Collapse

    func testMatchBelowCollapsedLinesForcesExpansion() {
        let lines = (1...10).map { "line \($0)" }
        let text = lines.joined(separator: "\n")
        let f = field(1, "body", text)
        let query = "line 8"
        let match = SAClaudeRecordFields.match(f, display: display(f), query: query)!
        let start = match.valueRanges[0].location
        XCTAssertEqual(SAClaudeRecordFields.lineIndex(of: start, in: text), 7)
        let below = SAClaudeRecordFields.lineIndex(of: start, in: text) >= SAClaudeRecordFields.collapsedLineLimit
        XCTAssertTrue(below)
        XCTAssertFalse(SAClaudeRecordFields.isCollapsed(lineCount: 10, expanded: false, matchStartsBelowLimit: below))

        let early = SAClaudeRecordFields.match(f, display: display(f), query: "line 2")!
        let earlyBelow = SAClaudeRecordFields.lineIndex(of: early.valueRanges[0].location, in: text) >= SAClaudeRecordFields.collapsedLineLimit
        XCTAssertFalse(earlyBelow)
        XCTAssertTrue(SAClaudeRecordFields.isCollapsed(lineCount: 10, expanded: false, matchStartsBelowLimit: earlyBelow))
    }

    func testIsCollapsedRules() {
        XCTAssertEqual(SAClaudeRecordFields.collapsedLineLimit, 6)
        XCTAssertFalse(SAClaudeRecordFields.isCollapsed(lineCount: 6, expanded: false, matchStartsBelowLimit: false))
        XCTAssertTrue(SAClaudeRecordFields.isCollapsed(lineCount: 7, expanded: false, matchStartsBelowLimit: false))
        XCTAssertFalse(SAClaudeRecordFields.isCollapsed(lineCount: 7, expanded: true, matchStartsBelowLimit: false))
    }

    func testLineIndex() {
        XCTAssertEqual(SAClaudeRecordFields.lineIndex(of: 0, in: "a\nb\nc"), 0)
        XCTAssertEqual(SAClaudeRecordFields.lineIndex(of: 2, in: "a\nb\nc"), 1)
        XCTAssertEqual(SAClaudeRecordFields.lineIndex(of: 4, in: "a\nb\nc"), 2)
        XCTAssertEqual(SAClaudeRecordFields.lineIndex(of: 99, in: "a\nb\nc"), 2)
        XCTAssertEqual(SAClaudeRecordFields.lineIndex(of: -3, in: "a\nb"), 0)
        XCTAssertEqual(SAClaudeRecordFields.lineIndex(of: 5, in: "😀\nb"), 1)
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
