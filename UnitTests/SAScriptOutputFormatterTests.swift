//
//  SAScriptOutputFormatterTests.swift
//  Unit Tests
//
//  Byte-exact checks that "Run All as Script" output matches the mysql
//  command-line client in batch mode with -vv.
//

import XCTest

final class SAScriptOutputFormatterTests: XCTestCase {

    func testStatementHeaderWrapsStatementInSeparators() {
        XCTAssertEqual(SAScriptOutputFormatter.statementHeader("SELECT 1"),
                       "--------------\nSELECT 1\n--------------\n\n")
    }

    func testResultHeaderIsTabSeparated() {
        XCTAssertEqual(SAScriptOutputFormatter.resultHeader(columns: ["id", "name"]), "id\tname\n")
    }

    func testResultHeaderEscapesColumnNames() {
        XCTAssertEqual(SAScriptOutputFormatter.resultHeader(columns: ["a\tb"]), "a\\tb\n")
    }

    func testRowRendersNullTextAndBinary() {
        let row: [SAScriptCell] = [.text("1"), .null, .binary(Data([0x00, 0xAB, 0x10]))]
        XCTAssertEqual(SAScriptOutputFormatter.row(row), "1\tNULL\t0x00AB10\n")
    }

    func testEmptyBinaryRendersAsEmptyString() {
        XCTAssertEqual(SAScriptOutputFormatter.render(.binary(Data())), "")
    }

    func testEscapeMatchesMysqlBatchMode() {
        XCTAssertEqual(SAScriptOutputFormatter.escape("a\\b"), "a\\\\b")
        XCTAssertEqual(SAScriptOutputFormatter.escape("a\tb"), "a\\tb")
        XCTAssertEqual(SAScriptOutputFormatter.escape("a\nb"), "a\\nb")
        XCTAssertEqual(SAScriptOutputFormatter.escape("a\u{0}b"), "a\\0b")
        XCTAssertEqual(SAScriptOutputFormatter.escape("plain ünïcode"), "plain ünïcode")
    }

    func testTextNULLStringIsNotConfusedWithEscaping() {
        XCTAssertEqual(SAScriptOutputFormatter.render(.text("NULL")), "NULL")
    }

    func testRowsInSetFooter() {
        XCTAssertEqual(SAScriptOutputFormatter.rowsInSetFooter(count: 0), "Empty set\n\n")
        XCTAssertEqual(SAScriptOutputFormatter.rowsInSetFooter(count: 1), "1 row in set\n\n")
        XCTAssertEqual(SAScriptOutputFormatter.rowsInSetFooter(count: 2), "2 rows in set\n\n")
    }

    func testQueryOK() {
        XCTAssertEqual(SAScriptOutputFormatter.queryOK(affectedRows: 0), "Query OK, 0 rows affected\n\n")
        XCTAssertEqual(SAScriptOutputFormatter.queryOK(affectedRows: 1), "Query OK, 1 row affected\n\n")
        XCTAssertEqual(SAScriptOutputFormatter.queryOK(affectedRows: 42), "Query OK, 42 rows affected\n\n")
    }

    func testErrorLine() {
        XCTAssertEqual(SAScriptOutputFormatter.error(code: 1146, sqlState: "42S02", line: 12,
                                                     message: "Table 'db.x' doesn't exist"),
                       "ERROR 1146 (42S02) at line 12: Table 'db.x' doesn't exist\n\n")
    }

    func testCancelledLine() {
        XCTAssertEqual(SAScriptOutputFormatter.cancelled, "Query cancelled.\n")
    }

    func testFullSelectBlockComposition() {
        let output = SAScriptOutputFormatter.statementHeader("SELECT id, name FROM users LIMIT 2")
            + SAScriptOutputFormatter.resultHeader(columns: ["id", "name"])
            + SAScriptOutputFormatter.row([.text("1"), .text("alice")])
            + SAScriptOutputFormatter.row([.text("2"), .text("bob")])
            + SAScriptOutputFormatter.rowsInSetFooter(count: 2)
        XCTAssertEqual(output, """
            --------------
            SELECT id, name FROM users LIMIT 2
            --------------

            id\tname
            1\talice
            2\tbob
            2 rows in set


            """)
    }

    // MARK: - Statement echo

    func testEchoTextRemovesLeadingLineComments() {
        XCTAssertEqual(SAScriptOutputFormatter.echoText(for: "-- Create the table\n# another note\nSELECT 1"), "SELECT 1")
    }

    func testEchoTextRemovesInlineBlockComment() {
        XCTAssertEqual(SAScriptOutputFormatter.echoText(for: "SELECT /* c */ 1"), "SELECT   1")
    }

    func testEchoTextKeepsExecutableCommentBody() {
        // stripSQLComments unwraps executable comments: the SQL inside the
        // version gate is kept, the /*!40101 … */ wrapper is not.
        let echo = SAScriptOutputFormatter.echoText(for: "/*!40101 SET NAMES utf8 */")
        XCTAssertEqual(echo, "SET NAMES utf8")
    }

    func testEchoTextKeepsCommentMarkersInsideStrings() {
        XCTAssertEqual(SAScriptOutputFormatter.echoText(for: "SELECT '-- not a comment', \"/* nor this */\""),
                       "SELECT '-- not a comment', \"/* nor this */\"")
    }

    func testEchoTextFallsBackToOriginalWhenOnlyComments() {
        XCTAssertEqual(SAScriptOutputFormatter.echoText(for: "-- only a note"), "-- only a note")
        XCTAssertEqual(SAScriptOutputFormatter.echoText(for: "/* block */"), "/* block */")
    }
}
