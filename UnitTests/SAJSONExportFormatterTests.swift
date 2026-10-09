//
//  SAJSONExportFormatterTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation
import XCTest

final class SAJSONExportFormatterTests: XCTestCase {

    // MARK: - Binary contract

    /// Which columns really hold bytes is read from the server's field metadata, the same way for
    /// every export source, so the base64 contract cannot depend on which one produced the rows.
    func testCharacterSetNumbersAreReadFromTheFieldDefinitions() {
        let numbers = SAJSONExportFormatter.characterSetNumbers([
            ["name": "note", "charsetnr": 255],
            ["name": "payload", "charsetnr": 63],
        ])

        XCTAssertEqual(numbers, [255, 63])
    }

    /// Table metadata parsed from SHOW CREATE TABLE carries no charsetnr, so a column there falls
    /// back to its type. The text types are text even though a binary collation makes their cells
    /// arrive as bytes; everything else keeps its bytes, which base64 decodes back exactly.
    ///
    /// Every grouping either metadata source can carry is listed rather than a sample of them, so a
    /// grouping left out of the decision shows up here instead of being inferred from the ones
    /// covered. Both sources fall back to `blobdata` for a type they do not recognise, so an
    /// unlisted grouping cannot reach the decision today.
    func testAColumnWithoutACharacterSetNumberFallsBackToItsType() {
        // Per grouping, whether its cells are text that a binary collation merely delivered as bytes
        let groupings: [(grouping: String, isText: Bool)] = [
            ("string", true), // CHAR / VARCHAR, collation aside
            ("textdata", true), // TEXT, and MariaDB's JSON
            ("blobdata", false), // BLOB
            ("binary", false), // BINARY / VARBINARY
            ("integer", false), // the rest never reach the exporter as bytes at all
            ("float", false),
            ("bit", false), // a bit string such as "0101"
            ("date", false),
            ("enum", false),
            ("geometry", false), // listed for completeness: turned into WKT text before textCell
        ]

        for (grouping, isText) in groupings {
            let expected = isText
                ? SAJSONExportFormatter.unknownCharacterSetNumber
                : SAJSONExportFormatter.binaryCharacterSetNumber
            let reason = isText
                ? "text, so its bytes belong in the file as a string"
                : "bytes, which have to be kept for base64"
            XCTAssertEqual(SAJSONExportFormatter.characterSetNumbers([["typegrouping": grouping]]),
                           [expected],
                           "a \(grouping) column holds \(reason)")
        }

        // A column addressing no definition keeps its bytes for the same reason.
        XCTAssertEqual(SAJSONExportFormatter.characterSetNumbers([[:]]),
                       [SAJSONExportFormatter.binaryCharacterSetNumber])
    }

    /// The server's own answer wins: a stated charsetnr decides whether a column holds bytes, and
    /// the type is consulted only in its absence. The definitions below are deliberately
    /// self-contradictory, which no real metadata is, so that the order itself is what gets pinned.
    func testAStatedCharacterSetNumberWinsOverTheColumnType() {
        let binary = SAJSONExportFormatter.binaryCharacterSetNumber
        let definitions: [[String: Any]] = [
            ["name": "code", "typegrouping": "string", "charsetnr": binary],
            ["name": "payload", "typegrouping": "blobdata", "charsetnr": 255],
        ]

        let characterSets = SAJSONExportFormatter.characterSetNumbers(definitions)
        XCTAssertEqual(characterSets, [binary, 255])

        let formatter = SAJSONExportFormatter(columnNames: ["code", "payload"],
                                              numericColumns: SAJSONExportFormatter.numericColumnFlags(definitions),
                                              tableKey: nil,
                                              prettyPrint: false)

        let producedRow: [Any] = [Data([0x41, 0x42]), Data("hej".utf8)]
        let cells = producedRow.enumerated().map { column, cell in
            SAJSONExportFormatter.textCell(cell, characterSetNumber: characterSets[column], encoding: .utf8)
        }

        // The string-typed column kept its bytes and the blob-typed one became text: the opposite
        // of what the groupings alone would have settled on.
        XCTAssertEqual(formatter.row(cells, index: 0), "\n{\"code\":\"QUI=\",\"payload\":\"hej\"}")
    }

    /// The reported case's sibling, on the filtered path: its metadata is the table's own, which
    /// carries no charsetnr. A VARCHAR with a binary collation arrives there as bytes and used to
    /// be written as base64, but it is text and belongs in the file as a string. The BLOB beside
    /// it is bytes and still becomes base64, so one source cannot settle both the same way.
    func testBinaryCollationTextFromTableMetadataStaysText() {
        let definitions: [[String: Any]] = [
            ["name": "code", "typegrouping": "string"],
            ["name": "payload", "typegrouping": "blobdata"],
        ]

        let characterSets = SAJSONExportFormatter.characterSetNumbers(definitions)
        let formatter = SAJSONExportFormatter(columnNames: ["code", "payload"],
                                              numericColumns: SAJSONExportFormatter.numericColumnFlags(definitions),
                                              tableKey: nil,
                                              prettyPrint: false)

        let producedRow: [Any] = [Data("hej".utf8), Data([0x41, 0x42])]
        let cells = producedRow.enumerated().map { column, cell in
            SAJSONExportFormatter.textCell(cell, characterSetNumber: characterSets[column], encoding: .utf8)
        }

        XCTAssertEqual(formatter.row(cells, index: 0), "\n{\"code\":\"hej\",\"payload\":\"QUI=\"}")
    }

    /// The reported case, assembled from the metadata a query result really carries: the numeric
    /// flags and the character sets come from the same definitions, so the BLOB column is
    /// recognised as bytes and `X'4142'` reaches the file as base64 rather than as the text "AB"
    /// the display producers used to hand the exporter.
    func testAQueryResultsBlobColumnIsExportedAsBase64() {
        let definitions: [[String: Any]] = [
            ["name": "id", "typegrouping": "integer", "charsetnr": 63],
            ["name": "payload", "typegrouping": "blobdata", "charsetnr": 63],
        ]

        let formatter = SAJSONExportFormatter(columnNames: ["id", "payload"],
                                              numericColumns: SAJSONExportFormatter.numericColumnFlags(definitions),
                                              tableKey: nil,
                                              prettyPrint: false)

        let characterSets = SAJSONExportFormatter.characterSetNumbers(definitions)
        let producedRow: [Any] = ["7", Data([0x41, 0x42])]
        let cells = producedRow.enumerated().map { column, cell in
            SAJSONExportFormatter.textCell(cell, characterSetNumber: characterSets[column], encoding: .utf8)
        }

        XCTAssertEqual(formatter.row(cells, index: 0), "\n{\"id\":7,\"payload\":\"QUI=\"}")
    }

    /// Bytes that are not valid text in the connection encoding must survive the export. The
    /// display producers replaced them, and that is exactly the loss base64 exists to avoid, so the
    /// test decodes the output back and demands the original bytes.
    func testInvalidBytesSurviveInsteadOfBeingReplaced() {
        let invalid = Data([0xFF, 0xFE, 0x41])

        let cell = SAJSONExportFormatter.textCell(invalid,
                                                  characterSetNumber: SAJSONExportFormatter.binaryCharacterSetNumber,
                                                  encoding: .utf8)

        let formatter = SAJSONExportFormatter(columnNames: ["payload"],
                                              numericColumns: [false],
                                              tableKey: nil,
                                              prettyPrint: false)
        let json = formatter.row([cell], index: 0)

        XCTAssertEqual(json, "\n{\"payload\":\"\(invalid.base64EncodedString())\"}")
        XCTAssertEqual(Data(base64Encoded: invalid.base64EncodedString()), invalid)
        XCTAssertFalse(json.contains("\u{FFFD}"))
    }

    /// An image BLOB was reduced to a thumbnail <IMG> tag by the filtered-export producer. Its
    /// bytes must now reach the file whole.
    func testAnImageBlobKeepsItsBytesRatherThanBecomingMarkup() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        let cell = SAJSONExportFormatter.textCell(png,
                                                  characterSetNumber: SAJSONExportFormatter.binaryCharacterSetNumber,
                                                  encoding: .utf8)

        let formatter = SAJSONExportFormatter(columnNames: ["picture"],
                                              numericColumns: [false],
                                              tableKey: nil,
                                              prettyPrint: false)
        let json = formatter.row([cell], index: 0)

        XCTAssertEqual(json, "\n{\"picture\":\"\(png.base64EncodedString())\"}")
        XCTAssertFalse(json.localizedCaseInsensitiveContains("img"))
    }

    /// A text column whose collation merely sets the BINARY flag is not binary. Its bytes are text
    /// and belong in the file as a JSON string, not as base64.
    func testBytesOfANonBinaryColumnBecomeText() {
        let cell = SAJSONExportFormatter.textCell(Data("hej".utf8), characterSetNumber: 255, encoding: .utf8)

        let formatter = SAJSONExportFormatter(columnNames: ["note"],
                                              numericColumns: [false],
                                              tableKey: nil,
                                              prettyPrint: false)

        XCTAssertEqual(formatter.row([cell], index: 0), "\n{\"note\":\"hej\"}")
    }

    /// Carrying raw cells must not cost the type contract settled earlier: a VARCHAR holding `1e3`
    /// is still text, and its column is still not numeric, so it stays a quoted string.
    func testANumericLookingVarcharStaysAStringOnTheRawPath() {
        let definitions: [[String: Any]] = [
            ["name": "code", "typegrouping": "string", "charsetnr": 255],
        ]

        let formatter = SAJSONExportFormatter(columnNames: ["code"],
                                              numericColumns: SAJSONExportFormatter.numericColumnFlags(definitions),
                                              tableKey: nil,
                                              prettyPrint: false)

        let characterSets = SAJSONExportFormatter.characterSetNumbers(definitions)
        let cell = SAJSONExportFormatter.textCell("1e3", characterSetNumber: characterSets[0], encoding: .utf8)

        XCTAssertEqual(formatter.row([cell], index: 0), "\n{\"code\":\"1e3\"}")
    }

    /// The exporter composes the two pieces of metadata the same way for every data-array source:
    /// the definitions are first put into export order, then read for their character sets. A
    /// column dragged to a new position must therefore carry its own binary decision with it, or a
    /// BLOB would be written as text and the text column beside it as base64.
    func testAReorderedProjectionKeepsEachColumnsBinaryDecision() {
        let definitions: [[String: Any]] = [
            ["name": "note", "typegrouping": "string", "charsetnr": 255],
            ["name": "payload", "typegrouping": "blobdata", "charsetnr": 63],
        ]

        // The BLOB dragged in front of the text column: identifiers are storage indexes.
        let reordered = SAJSONExportFormatter.columnDefinitionsInExportOrder(definitions, identifierIndexes: [1, 0])!
        let characterSets = SAJSONExportFormatter.characterSetNumbers(reordered)

        XCTAssertEqual(characterSets, [63, 255])

        let formatter = SAJSONExportFormatter(columnNames: ["payload", "note"],
                                              numericColumns: SAJSONExportFormatter.numericColumnFlags(reordered),
                                              tableKey: nil,
                                              prettyPrint: false)

        let producedRow: [Any] = [Data([0x41, 0x42]), Data("hej".utf8)]
        let cells = producedRow.enumerated().map { column, cell in
            SAJSONExportFormatter.textCell(cell, characterSetNumber: characterSets[column], encoding: .utf8)
        }

        XCTAssertEqual(formatter.row(cells, index: 0), "\n{\"payload\":\"QUI=\",\"note\":\"hej\"}")
    }

    /// NULL reaches the exporter as NSNull from the raw producers and must stay null, rather than
    /// becoming the placeholder text the display producers substitute for it.
    func testNullCellsStayNull() {
        let formatter = SAJSONExportFormatter(columnNames: ["note"],
                                              numericColumns: [false],
                                              tableKey: nil,
                                              prettyPrint: false)

        XCTAssertEqual(formatter.row([NSNull()], index: 0), "\n{\"note\":null}")
    }

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

    func testUnknownColumnTypesKeepStringsAsStrings() {
        // When the column types are unknown, a cell's database type is never guessed from its
        // text: a VARCHAR "1e3" must not become the JSON number 1e3.
        let text = document(columns: ["a", "b", "c", "d"], numeric: nil, rows: [["42", "-1.5e3", "007", "abc"]], pretty: false)

        XCTAssertEqual(text, "[\n{\"a\":\"42\",\"b\":\"-1.5e3\",\"c\":\"007\",\"d\":\"abc\"}\n]\n")
    }

    // MARK: - Column metadata

    func testNumericColumnFlagsFromFieldDefinitions() {
        // Streaming results and custom-query result stores provide field definitions with
        // typegrouping; BIT is excluded (its values are bit strings such as "0101")
        let definitions: [[String: Any]] = [
            ["name": "id", "typegrouping": "integer"],
            ["name": "price", "typegrouping": "float"],
            ["name": "flags", "typegrouping": "bit"],
            ["name": "note", "typegrouping": "strings"],
            ["name": "created", "typegrouping": "datetime"],
            ["name": "anything"],             // no typegrouping key
            ["name": "odd", "typegrouping": 7], // not a string
        ]
        XCTAssertEqual(SAJSONExportFormatter.numericColumnFlags(definitions),
                       [true, true, false, false, false, false, false])

        // Missing or empty metadata leaves every column a string
        XCTAssertEqual(SAJSONExportFormatter.numericColumnFlags([]), [])
    }

    func testSameValuesKeepTheirTypeAcrossTableQueryAndFilteredExports() {
        // The same schema and row reach the exporter by three paths: a table export reads its
        // field definitions from the streaming result, a query export from the result store, and
        // a filtered export from the table metadata's columns. All three carry typegrouping, so
        // all three must agree: numeric columns emit numbers, text columns keep their strings.
        let columns = ["code", "zip", "qty", "price"]
        let row: [Any] = ["1e3", "94103", "7", "19.99"]

        let streamingDefinitions: [[String: Any]] = [
            ["name": "code", "typegrouping": "strings", "charsetnr": 255],
            ["name": "zip", "typegrouping": "strings", "charsetnr": 255],
            ["name": "qty", "typegrouping": "integer", "charsetnr": 63],
            ["name": "price", "typegrouping": "float", "charsetnr": 63],
        ]
        let resultStoreDefinitions: [[String: Any]] = [
            ["name": "code", "typegrouping": "strings"],
            ["name": "zip", "typegrouping": "strings"],
            ["name": "qty", "typegrouping": "integer"],
            ["name": "price", "typegrouping": "float"],
        ]
        let tableMetadataColumns: [[String: Any]] = [
            ["name": "code", "typegrouping": "strings", "type": "varchar"],
            ["name": "zip", "typegrouping": "strings", "type": "varchar"],
            ["name": "qty", "typegrouping": "integer", "type": "int"],
            ["name": "price", "typegrouping": "float", "type": "decimal"],
        ]

        let expected = "[\n{\"code\":\"1e3\",\"zip\":\"94103\",\"qty\":7,\"price\":19.99}\n]\n"
        for definitions in [streamingDefinitions, resultStoreDefinitions, tableMetadataColumns] {
            let flags = SAJSONExportFormatter.numericColumnFlags(definitions)
            XCTAssertEqual(document(columns: columns, numeric: flags, rows: [row], pretty: false), expected)
        }

        // Parsed back: text columns stay strings (no type change), numeric columns are numbers
        let parsed = parse(expected) as? [[String: Any]]
        XCTAssertEqual(parsed?.first?["code"] as? String, "1e3")
        XCTAssertEqual(parsed?.first?["zip"] as? String, "94103")
        XCTAssertEqual(parsed?.first?["qty"] as? Int, 7)
        XCTAssertEqual(parsed?.first?["price"] as? Double, 19.99)
    }

    func testZerofillAndInvalidNumbersStayStringsEvenInNumericColumns() {
        // Nothing is lost to make a value numeric: text that is not a valid JSON number keeps
        // its exact spelling
        let text = document(columns: ["a", "b"], numeric: [true, true], rows: [["007", "1e"]], pretty: false)

        XCTAssertEqual(text, "[\n{\"a\":\"007\",\"b\":\"1e\"}\n]\n")
    }

    func testZeroFillColumnsStayStringsWhetherOrNotTheirValuesFillTheWidth() {
        // A ZEROFILL column's values are display text padded to the column's width, so the
        // column keeps one JSON type whether or not a value happens to fill its width: `123`
        // in an INT(3) ZEROFILL column is exported as a string, next to a padded `007`.
        // Result field definitions mark the column with ZEROFILL_FLAG; the table metadata's
        // columns mark it with zerofill.
        let columns = ["zpadded", "zfilled", "plain"]
        let row: [Any] = ["007", "123", "45"]
        let expected = "[\n{\"zpadded\":\"007\",\"zfilled\":\"123\",\"plain\":45}\n]\n"

        let resultFieldDefinitions: [[String: Any]] = [
            ["name": "zpadded", "typegrouping": "integer", "ZEROFILL_FLAG": true],
            ["name": "zfilled", "typegrouping": "integer", "ZEROFILL_FLAG": true],
            ["name": "plain", "typegrouping": "integer", "ZEROFILL_FLAG": false],
        ]
        let tableMetadataColumns: [[String: Any]] = [
            ["name": "zpadded", "typegrouping": "integer", "zerofill": true],
            ["name": "zfilled", "typegrouping": "integer", "zerofill": true],
            ["name": "plain", "typegrouping": "integer", "zerofill": false],
        ]

        for definitions in [resultFieldDefinitions, tableMetadataColumns] {
            let flags = SAJSONExportFormatter.numericColumnFlags(definitions)
            XCTAssertEqual(flags, [false, false, true])
            XCTAssertEqual(document(columns: columns, numeric: flags, rows: [row], pretty: false), expected)
        }

        // Parsed back: both ZEROFILL values are strings, the plain INT is a number
        let parsed = parse(expected) as? [[String: Any]]
        XCTAssertEqual(parsed?.first?["zpadded"] as? String, "007")
        XCTAssertEqual(parsed?.first?["zfilled"] as? String, "123")
        XCTAssertEqual(parsed?.first?["plain"] as? Int, 45)
    }

    func testColumnDefinitionsFollowExportedColumnOrder() {
        // Query and filtered exports write rows in their table view's column order, keyed by
        // each column's identifier (the result index). Dragging `code` before `qty` in
        // SELECT 7 AS qty, '1e3' AS code reorders headers and cells together — the definitions
        // must follow the identifiers or the VARCHAR would export as a number and the INT as
        // a string.
        let definitions: [[String: Any]] = [
            ["name": "qty", "typegrouping": "integer"],
            ["name": "code", "typegrouping": "strings"],
        ]
        let reordered = SAJSONExportFormatter.columnDefinitionsInExportOrder(definitions, identifierIndexes: [1, 0])
        let flags = SAJSONExportFormatter.numericColumnFlags(reordered ?? [])

        XCTAssertEqual(flags, [false, true])
        let text = document(columns: ["code", "qty"], numeric: flags, rows: [["1e3", "7"]], pretty: false)
        XCTAssertEqual(text, "[\n{\"code\":\"1e3\",\"qty\":7}\n]\n")

        // Parsed back: the dragged VARCHAR stays a string, the INT is a number
        let parsed = parse(text) as? [[String: Any]]
        XCTAssertEqual(parsed?.first?["code"] as? String, "1e3")
        XCTAssertEqual(parsed?.first?["qty"] as? Int, 7)
    }

    func testDuplicateAliasesKeepTheirOwnDefinitions() {
        // Two columns can share a header (SELECT 1 AS a, '1' AS a); matching definitions by
        // name would cross their types. Each column's identifier addresses its own definition.
        let definitions: [[String: Any]] = [
            ["name": "a", "typegrouping": "integer"],
            ["name": "a", "typegrouping": "strings"],
        ]

        XCTAssertEqual(SAJSONExportFormatter.numericColumnFlags(
            SAJSONExportFormatter.columnDefinitionsInExportOrder(definitions, identifierIndexes: [0, 1]) ?? []), [true, false])
        XCTAssertEqual(SAJSONExportFormatter.numericColumnFlags(
            SAJSONExportFormatter.columnDefinitionsInExportOrder(definitions, identifierIndexes: [1, 0]) ?? []), [false, true])
    }

    func testExportOrderHelperDegenerateInputs() {
        // No metadata keeps the string-preserving default
        XCTAssertNil(SAJSONExportFormatter.columnDefinitionsInExportOrder(nil, identifierIndexes: [0, 1]))
        XCTAssertNil(SAJSONExportFormatter.columnDefinitionsInExportOrder([], identifierIndexes: [0]))
        XCTAssertNil(SAJSONExportFormatter.columnDefinitionsInExportOrder([["name": "a", "typegrouping": "integer"]], identifierIndexes: []))

        // An identifier addressing no definition yields an empty entry, which flags the
        // column as text — never a neighbour's type
        let orphan = SAJSONExportFormatter.columnDefinitionsInExportOrder(
            [["name": "a", "typegrouping": "integer"]], identifierIndexes: [0, 2])
        XCTAssertEqual(SAJSONExportFormatter.numericColumnFlags(orphan ?? []), [true, false])
    }

    /// A row holding fewer cells than the result has columns still produces every key, so the
    /// objects in the file all share one shape and a reader can address a column that a short row
    /// did not reach.
    func testColumnsBeyondAShortRowAreWrittenAsNull() {
        let formatter = SAJSONExportFormatter(columnNames: ["id", "name", "note"],
                                              numericColumns: [true, false, false],
                                              tableKey: nil,
                                              prettyPrint: false)

        XCTAssertEqual(formatter.row(["7"], index: 0), "\n{\"id\":7,\"name\":null,\"note\":null}")
    }

    func testOtherObjectsAreWrittenAsTheirDescription() {
        let text = document(columns: ["n"], numeric: [true], rows: [[NSNumber(value: 5)]], pretty: false)

        XCTAssertEqual(text, "[\n{\"n\":\"5\"}\n]\n")
    }

    func testColumnNamesAreEscaped() {
        let text = document(columns: [#"we"ird\name"#], numeric: nil, rows: [["x"]], pretty: false)

        XCTAssertEqual(text, "[\n{\"we\\\"ird\\\\name\":\"x\"}\n]\n")
    }

    func testDuplicateColumnNamesGetUniqueKeys() {
        XCTAssertEqual(SAJSONExportFormatter.uniqueKeys(["id", "name", "id", "id_2", "id"]),
                       ["id", "name", "id_2", "id_2_2", "id_3"])

        // A query selecting a.id, b.id keeps both values
        let text = document(columns: ["id", "id"], numeric: [true, true], rows: [["1", "2"]], pretty: false)
        XCTAssertEqual(text, "[\n{\"id\":1,\"id_2\":2}\n]\n")
        XCTAssertEqual((parse(text) as? [[String: Any]])?.first?.count, 2)
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
