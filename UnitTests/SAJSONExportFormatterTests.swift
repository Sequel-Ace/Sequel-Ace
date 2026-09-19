//
//  SAJSONExportFormatterTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation
import XCTest

final class SAJSONExportFormatterTests: XCTestCase {

    /// Writes one table the way SAJSONExporter does: opening, rows, closing.
    private func document(columns: [String],
                          numeric: [Bool]?,
                          rows: [[Any]],
                          tableKey: String? = nil,
                          pretty: Bool = true,
                          first: Bool = true,
                          last: Bool = true) -> String {
        let formatter = SAJSONExportFormatter(columnNames: columns, numericColumns: numeric, tableKey: tableKey, prettyPrint: pretty)
        var text = formatter.opening(isFirstInFile: first)
        for (index, row) in rows.enumerated() {
            text += formatter.row(row, index: index)
        }
        return text + formatter.closing(rowCount: rows.count, isLastInFile: last)
    }

    private func parse(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> Any? {
        do {
            return try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        } catch {
            XCTFail("Not valid JSON (\(error)):\n\(text)", file: file, line: line)
            return nil
        }
    }

    // MARK: - String escaping

    func testQuotedEscapesQuotesBackslashesAndControlCharacters() {
        XCTAssertEqual(SAJSONExportFormatter.quoted(#"say "hi" \ bye"#), #""say \"hi\" \\ bye""#)
        XCTAssertEqual(SAJSONExportFormatter.quoted("a\nb\rc\td"), #""a\nb\rc\td""#)
        XCTAssertEqual(SAJSONExportFormatter.quoted("\u{08}\u{0C}\u{01}\u{1F}"), #""\b\f\u0001\u001f""#)
        XCTAssertEqual(SAJSONExportFormatter.quoted(""), #""""#)
    }

    func testQuotedKeepsNonASCIITextAndSlashesAsIs() {
        XCTAssertEqual(SAJSONExportFormatter.quoted("Zoë 日本 🐬 a/b \u{7F}"), "\"Zoë 日本 🐬 a/b \u{7F}\"")
    }

    func testQuotedStringsRoundTripThroughAJSONParser() {
        let samples = ["plain", #"q"uote"#, "back\\slash", "line\nbreak\r\n", "tab\there", "nul\u{0}byte", "Zoë 🐬", "\u{2028}"]
        for sample in samples {
            XCTAssertEqual(parse(SAJSONExportFormatter.quoted(sample)) as? String, sample)
        }
    }

    // MARK: - Number detection

    func testValidJSONNumbers() {
        for number in ["0", "-0", "7", "42", "-17", "3.14", "-0.5", "0.001", "1e10", "1E+5", "-2.5e-3", "123456789012345678901234567890"] {
            XCTAssertTrue(SAJSONExportFormatter.isJSONNumber(number), number)
        }
    }

    func testInvalidJSONNumbers() {
        for text in ["", "-", "007", "01", "-01", "1.", ".5", "+1", "1e", "1e+", " 1", "1 ", "NaN", "Infinity", "0x1F", "1,000", "1.2.3", "12abc"] {
            XCTAssertFalse(SAJSONExportFormatter.isJSONNumber(text), text)
        }
    }

    // MARK: - Cell mapping

    func testTableExportTypeMapping() {
        let columns = ["id", "price", "zip", "code", "note", "blob"]
        let numeric = [true, true, true, false, false, false]
        let row: [Any] = ["1", "19.99", "00501", "123", NSNull(), Data([0x00, 0xFF, 0x10])]

        let text = document(columns: columns, numeric: numeric, rows: [row], pretty: false)

        XCTAssertEqual(text, "[\n{\"id\":1,\"price\":19.99,\"zip\":\"00501\",\"code\":\"123\",\"note\":null,\"blob\":\"AP8Q\"}\n]\n")
    }

    func testUnknownColumnTypesWriteNumericLookingTextAsNumbers() {
        // Query and filtered results carry no column types; like the CSV exporter, text that reads as
        // a number is written as one. Text that is not a valid JSON number stays a string.
        let text = document(columns: ["a", "b", "c", "d"], numeric: nil, rows: [["42", "-1.5e3", "007", "abc"]], pretty: false)

        XCTAssertEqual(text, "[\n{\"a\":42,\"b\":-1.5e3,\"c\":\"007\",\"d\":\"abc\"}\n]\n")
    }

    func testOtherObjectsAreWrittenAsTheirDescription() {
        let text = document(columns: ["n"], numeric: [true], rows: [[NSNumber(value: 5)]], pretty: false)

        XCTAssertEqual(text, "[\n{\"n\":\"5\"}\n]\n")
    }

    func testColumnNamesAreEscaped() {
        let text = document(columns: [#"we"ird\name"#], numeric: nil, rows: [["x"]], pretty: false)

        XCTAssertEqual(text, "[\n{\"we\\\"ird\\\\name\":\"x\"}\n]\n")
    }

    func testBinaryCollationTextIsDecodedButBinaryCharsetStaysBytes() {
        let json = Data(#"{"k": [1]}"#.utf8)

        // utf8mb4_bin text (e.g. MariaDB's JSON type) arrives as bytes but is text
        XCTAssertEqual(SAJSONExportFormatter.textCell(json, characterSetNumber: 46, encoding: .utf8) as? String, #"{"k": [1]}"#)
        // The binary character set (BLOB, VARBINARY) keeps its bytes, to be written as base64
        XCTAssertEqual(SAJSONExportFormatter.textCell(json, characterSetNumber: 63, encoding: .utf8) as? Data, json)
        // Bytes that are not valid in the connection encoding are kept rather than mangled
        XCTAssertEqual(SAJSONExportFormatter.textCell(Data([0xFF, 0xFE]), characterSetNumber: 46, encoding: .utf8) as? Data, Data([0xFF, 0xFE]))
        // Non-data values pass through
        XCTAssertTrue(SAJSONExportFormatter.textCell(NSNull(), characterSetNumber: 46, encoding: .utf8) is NSNull)
    }

    // MARK: - Layout

    func testPrettyPrintedArray() {
        let text = document(columns: ["id", "name"], numeric: [true, false], rows: [["1", "Ann"], ["2", NSNull()]])

        XCTAssertEqual(text, """
        [
          {
            "id": 1,
            "name": "Ann"
          },
          {
            "id": 2,
            "name": null
          }
        ]

        """)
    }

    func testEmptyResultIsAnEmptyArray() {
        XCTAssertEqual(document(columns: ["id"], numeric: [true], rows: []), "[]\n")
        XCTAssertEqual(document(columns: ["id"], numeric: [true], rows: [], pretty: false), "[]\n")
    }

    func testTablesSharingAFileAreKeyedByTableName() {
        let users = document(columns: ["id"], numeric: [true], rows: [["1"], ["2"]], tableKey: "users", first: true, last: false)
        let empty = document(columns: ["id"], numeric: [true], rows: [], tableKey: "empty", first: false, last: false)
        let orders = document(columns: ["total"], numeric: [true], rows: [["9.5"]], tableKey: "orders", first: false, last: true)
        let text = users + empty + orders

        XCTAssertEqual(text, """
        {
          "users": [
            {
              "id": 1
            },
            {
              "id": 2
            }
          ],
          "empty": [],
          "orders": [
            {
              "total": 9.5
            }
          ]
        }

        """)

        let object = parse(text) as? [String: [[String: Any]]]
        XCTAssertEqual(object?["users"]?.count, 2)
        XCTAssertEqual(object?["empty"]?.count, 0)
        XCTAssertEqual(object?["orders"]?.first?["total"] as? Double, 9.5)
    }

    func testCompactKeyedTablesParse() {
        let text = document(columns: ["id"], numeric: [true], rows: [["1"]], tableKey: "a", pretty: false, first: true, last: false)
            + document(columns: ["id"], numeric: [true], rows: [["2"]], tableKey: "b", pretty: false, first: false, last: true)

        XCTAssertEqual(text, "{\n\"a\":[\n{\"id\":1}\n],\n\"b\":[\n{\"id\":2}\n]\n}\n")
        XCTAssertNotNil(parse(text) as? [String: Any])
    }

    func testMixedContentRoundTrips() {
        let columns = ["id", "amount", "note", "doc", "bin", "created"]
        let numeric = [true, true, false, false, false, false]
        let rows: [[Any]] = [
            ["1", "-12.50", "He said \"hi\"\nthen left\t🐬", #"{"k": [1, 2]}"#, Data("héllo".utf8), "2026-09-19 10:00:00"],
            ["2", NSNull(), "", NSNull(), NSNull(), NSNull()],
        ]

        for pretty in [true, false] {
            let parsed = parse(document(columns: columns, numeric: numeric, rows: rows, pretty: pretty)) as? [[String: Any]]

            XCTAssertEqual(parsed?.count, 2)
            XCTAssertEqual(parsed?[0]["id"] as? Int, 1)
            XCTAssertEqual(parsed?[0]["amount"] as? Double, -12.5)
            XCTAssertEqual(parsed?[0]["note"] as? String, "He said \"hi\"\nthen left\t🐬")
            XCTAssertEqual(parsed?[0]["doc"] as? String, #"{"k": [1, 2]}"#)
            XCTAssertEqual((parsed?[0]["bin"] as? String).flatMap { Data(base64Encoded: $0) }, Data("héllo".utf8))
            XCTAssertEqual(parsed?[0]["created"] as? String, "2026-09-19 10:00:00")
            XCTAssertTrue(parsed?[1]["amount"] is NSNull)
            XCTAssertEqual(parsed?[1]["note"] as? String, "")
        }
    }
}
