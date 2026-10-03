//
//  SPMCPServerTests.swift
//  Unit Tests
//
//  Covers the hand-rolled HTTP request parser and the Origin allow-list used
//  by the MCP server's loopback/DNS-rebinding protection, and the JSON Schema
//  the server advertises for its tools.
//

import XCTest

final class SPMCPServerHTTPRequestTests: XCTestCase {

    private func request(_ raw: String) -> HTTPRequest? {
        HTTPRequest(data: Data(raw.utf8))
    }

    // MARK: - Request line

    func testParsesMethodAndPath() {
        let req = request("GET /sse HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        XCTAssertEqual(req?.method, "GET")
        XCTAssertEqual(req?.path, "/sse")
    }

    func testPathExcludesQueryString() {
        let req = request("POST /message?sessionId=abc123 HTTP/1.1\r\nHost: x\r\n\r\n")
        XCTAssertEqual(req?.path, "/message")
    }

    // MARK: - Query parameters

    func testQueryParamReturnsValue() {
        let req = request("GET /message?sessionId=abc123&foo=bar HTTP/1.1\r\nHost: x\r\n\r\n")
        XCTAssertEqual(req?.queryParam("sessionId"), "abc123")
        XCTAssertEqual(req?.queryParam("foo"), "bar")
    }

    func testQueryParamPercentDecodes() {
        let req = request("GET /message?path=%2Ftmp%2Fa%20b HTTP/1.1\r\nHost: x\r\n\r\n")
        XCTAssertEqual(req?.queryParam("path"), "/tmp/a b")
    }

    func testQueryParamMissingReturnsNil() {
        let req = request("GET /sse HTTP/1.1\r\nHost: x\r\n\r\n")
        XCTAssertNil(req?.queryParam("sessionId"))
    }

    // MARK: - Headers

    func testHeadersAreLowercasedKeys() {
        let req = request("GET /sse HTTP/1.1\r\nOrigin: http://evil.example\r\nContent-Type: application/json\r\n\r\n")
        XCTAssertEqual(req?.headers["origin"], "http://evil.example")
        XCTAssertEqual(req?.headers["content-type"], "application/json")
    }

    func testHeaderValueWithColonPreserved() {
        let req = request("GET /mcp HTTP/1.1\r\nMcp-Session-Id: a:b:c\r\n\r\n")
        XCTAssertEqual(req?.headers["mcp-session-id"], "a:b:c")
    }

    func testHeaderWithoutSpaceAfterColonParsed() {
        // HTTP allows "Name:value" with no space; it must still be parsed so that
        // Content-Length (body) and Origin (security) are honoured.
        let body = "{}"
        let req = request("POST /mcp HTTP/1.1\r\nContent-Length:\(body.utf8.count)\r\nOrigin:http://localhost\r\n\r\n\(body)")
        XCTAssertEqual(req?.headers["content-length"], "2")
        XCTAssertEqual(req?.headers["origin"], "http://localhost")
        XCTAssertEqual(req?.body, Data(body.utf8))
    }

    // MARK: - Body / Content-Length

    func testParsesBodyOfDeclaredLength() {
        let body = "{\"jsonrpc\":\"2.0\"}"
        let req = request("POST /mcp HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
        XCTAssertEqual(req?.body, Data(body.utf8))
    }

    func testNoBodyWhenContentLengthZero() {
        let req = request("POST /mcp HTTP/1.1\r\nContent-Length: 0\r\n\r\n")
        XCTAssertNil(req?.body)
    }

    // MARK: - Incomplete data

    func testIncompleteHeadersReturnsNil() {
        XCTAssertNil(request("GET /sse HTTP/1.1\r\nHost: x"))
    }

    func testIncompleteBodyReturnsNil() {
        // Declares 20 bytes but only 3 are present.
        XCTAssertNil(request("POST /mcp HTTP/1.1\r\nContent-Length: 20\r\n\r\nabc"))
    }
}

final class SPMCPServerOriginTests: XCTestCase {

    func testLoopbackHostsAreAllowed() {
        XCTAssertTrue(SPMCPHTTP.isLoopbackOrigin("http://127.0.0.1:8765"))
        XCTAssertTrue(SPMCPHTTP.isLoopbackOrigin("http://localhost"))
        XCTAssertTrue(SPMCPHTTP.isLoopbackOrigin("http://localhost:3000"))
        XCTAssertTrue(SPMCPHTTP.isLoopbackOrigin("http://[::1]:8765"))
    }

    func testUppercaseLoopbackHostAllowed() {
        XCTAssertTrue(SPMCPHTTP.isLoopbackOrigin("http://LOCALHOST:8765"))
        XCTAssertTrue(SPMCPHTTP.isLoopbackOrigin("HTTP://LocalHost"))
    }

    func testRemoteOriginsAreRejected() {
        XCTAssertFalse(SPMCPHTTP.isLoopbackOrigin("http://evil.example"))
        XCTAssertFalse(SPMCPHTTP.isLoopbackOrigin("https://127.0.0.1.evil.example"))
        XCTAssertFalse(SPMCPHTTP.isLoopbackOrigin("http://10.0.0.5"))
    }

    func testUnparseableOriginIsRejected() {
        XCTAssertFalse(SPMCPHTTP.isLoopbackOrigin(""))
        XCTAssertFalse(SPMCPHTTP.isLoopbackOrigin("not a url"))
    }
}

final class SPMCPJSONTests: XCTestCase {

    // MySQL can return text columns as NSData; serialising them must not throw.
    func testDataValuesAreDecodedNotCrashing() {
        let dict: [String: Any] = [
            "databases": [Data("shop".utf8), Data("mysql".utf8)],
            "connection": "abc"
        ]
        let out = SPMCPJSON.string(from: dict)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("shop"))
        XCTAssertTrue(out!.contains("mysql"))
    }

    func testNonJSONLeavesAreStringifiedNotCrashing() {
        let dict: [String: Any] = [
            "date": Date(timeIntervalSince1970: 0),
            "null": NSNull(),
            "rows": [["n": NSNumber(value: 3), "blob": Data([0x01, 0x02, 0xff])]]
        ]
        // Must produce valid JSON rather than throw on the Date/Data/NSNull values.
        let out = SPMCPJSON.string(from: dict)
        XCTAssertNotNil(out)
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(out!.utf8)))
    }

    func testPlainValuesRoundTrip() {
        let out = SPMCPJSON.string(from: ["a": "x", "n": 1, "arr": [1, 2, 3]])
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("\"a\""))
    }
}

/// Read-only guard tests. The rejected cases are drawn from common SQL-injection
/// and WAF-bypass techniques (stacked queries, comment evasion, MySQL executable
/// /*! */ comments, INTO OUTFILE/DUMPFILE, PREPARE/EXECUTE, EXPLAIN ANALYZE of a
/// write, etc.) so a rogue agent cannot smuggle a write past read-only mode.
final class SPMCPReadOnlyGuardTests: XCTestCase {

    private func assertAllowed(_ sqls: [String], _ msg: String) {
        for sql in sqls { XCTAssertTrue(SPMCPReadOnlyGuard.isReadOnly(sql), "\(msg) should ALLOW: \(sql)") }
    }
    private func assertRejected(_ sqls: [String], _ msg: String) {
        for sql in sqls { XCTAssertFalse(SPMCPReadOnlyGuard.isReadOnly(sql), "\(msg) should REJECT: \(sql)") }
    }

    // MARK: - Legitimate reads are allowed

    func testReadsAllowed() {
        assertAllowed([
            "SELECT * FROM users",
            "select 1",
            "   SELECT 1   ",
            "SELECT 1;",
            "SELECT 1 ;   ",
            "\n\t SELECT 1",
            "SHOW DATABASES",
            "SHOW FULL TABLES IN `app`",
            "DESCRIBE users",
            "DESC users",
            "EXPLAIN SELECT * FROM t",
            "EXPLAIN ANALYZE SELECT * FROM t",
            "EXPLAIN ANALYZE FOR SCHEMA app SELECT * FROM t",
            "EXPLAIN FORMAT=JSON SELECT * FROM t",
            "(SELECT * FROM t)",
            "SELECT a FROM t UNION SELECT b FROM u",
            "/* leading comment */ SELECT 1",
            "-- a comment\nSELECT 1",
            "-- a comment\r\nSELECT 1",
            "--\r\nSELECT 1",
            "--\u{0C}form feed\nSELECT 1",
            "--\u{0B}vertical tab\nSELECT 1",
            "# a comment\r\nSHOW TABLES",
            "SELECT COUNT(*) FROM t WHERE name = 'Bob'",
        ], "read")
    }

    // MARK: - Direct writes / DDL / privileged statements are rejected

    func testWritesAndDDLRejected() {
        assertRejected([
            "UPDATE users SET x = 1",
            "uPdAtE users SET x = 1",
            "  update users set x = 1",
            "DELETE FROM users",
            "INSERT INTO t VALUES (1)",
            "INSERT INTO t (a) SELECT a FROM u",
            "REPLACE INTO t VALUES (1)",
            "DROP TABLE t",
            "DROP DATABASE d",
            "TRUNCATE t",
            "TRUNCATE TABLE t",
            "ALTER TABLE t ADD c INT",
            "CREATE TABLE t (id INT)",
            "CREATE DATABASE d",
            "CREATE TEMPORARY TABLE t (id INT)",
            "RENAME TABLE a TO b",
            "GRANT ALL ON *.* TO u",
            "REVOKE ALL ON *.* FROM u",
            "FLUSH PRIVILEGES",
            "LOCK TABLES t WRITE",
        ], "write/ddl")
    }

    func testProceduralAndSessionStatementsRejected() {
        assertRejected([
            "CALL some_proc()",
            "DO SLEEP(1)",
            "HANDLER t OPEN",
            "SET @x = 1",
            "SET GLOBAL general_log = 'ON'",
            "USE other_db",
            "PREPARE stmt FROM 'DROP TABLE t'",
            "EXECUTE stmt",
            "DEALLOCATE PREPARE stmt",
            "BEGIN",
            "START TRANSACTION",
            "COMMIT",
            "ROLLBACK",
            "LOAD DATA INFILE '/x' INTO TABLE t",
            "INSTALL PLUGIN x SONAME 'x.so'",
            "KILL 1",
            "SHUTDOWN",
        ], "procedural/session")
    }

    // MARK: - Injection / bypass techniques are rejected

    func testStackedStatementsRejected() {
        assertRejected([
            "SELECT 1; DROP TABLE t",
            "SELECT 1 ; DELETE FROM t",
            "SELECT 1;\nUPDATE t SET x = 1",
            "SHOW TABLES; INSERT INTO t VALUES (1)",
            "SELECT 1;UPDATE t SET x=1;",
            "SELECT 1; SET @x = 0x44; PREPARE s FROM @x; EXECUTE s",
        ], "stacked")
    }

    /// Verifies that writes placed behind block, `--` or `#` comments, with LF or
    /// CRLF line endings, are rejected by the read-only guard.
    func testCommentHiddenWritesRejected() {
        assertRejected([
            "/* x */ DELETE FROM t",
            "-- c\nUPDATE t SET x = 1",
            "# c\nDROP TABLE t",
            "-- c\r\nUPDATE t SET x = 1",
            "--\r\nDELETE FROM t",
            "# c\r\nDROP TABLE t",
            "SELECT 1 -- c\r\n; DROP TABLE t",
            "/* multi\nline */ INSERT INTO t VALUES (1)",
        ], "comment-hidden")
    }

    func testMySQLExecutableCommentsRejected() {
        // MySQL runs the contents of /*! ... */, so they must never slip through.
        assertRejected([
            "/*! UPDATE t SET x = 1 */",
            "/*!50000 DELETE FROM t */",
            "SELECT 1 /*! ; DROP TABLE t */",
            "SELECT 1 /*!50000, (SELECT ... ) */",
            "SEL/*!ECT*/ 1",
        ], "executable-comment")
    }

    func testFileWriteRejected() {
        assertRejected([
            "SELECT * INTO OUTFILE '/tmp/x' FROM t",
            "SELECT * INTO DUMPFILE '/tmp/x'",
            "select a into outfile '/tmp/x' from t",
            "SELECT load_file('/etc/passwd') INTO OUTFILE '/tmp/x'",
        ], "file-write")
    }

    // Executable comments run their body on the server: MySQL /*! */ and MariaDB
    // /*M! */. Both must be rejected (the body can hide a write / file clause).
    func testExecutableCommentsRejected() {
        assertRejected([
            "SELECT 1 /*! INTO OUTFILE '/tmp/x' */",
            "SELECT 1 /*!12345 INTO OUTFILE '/tmp/x' */",
            "SELECT 1 /*M! INTO OUTFILE '/tmp/x' */",
            "SELECT 1 /*m! INTO OUTFILE '/tmp/x' */",
            "SELECT 1 /*M!100000 INTO OUTFILE '/tmp/x' */",
        ], "executable-comment")
    }

    func testFileReadRejected() {
        // LOAD_FILE() is a plain SELECT but reads server-local files.
        assertRejected([
            "SELECT LOAD_FILE('/etc/passwd')",
            "select load_file('/etc/passwd') AS secret",
            "SELECT a, LOAD_FILE('/etc/hosts') FROM t",
        ], "file-read")
    }

    // A comment marker inside a string literal must not hide a trailing OUTFILE /
    // LOAD_FILE / `;` from the guard: a quote-unaware strip would drop everything
    // after the in-string `#` or `--`, leaving an apparently-safe `SELECT '`.
    func testCommentMarkerInStringDoesNotHideDanger() {
        assertRejected([
            "SELECT '#' INTO OUTFILE '/tmp/x'",
            "SELECT '-- ' INTO DUMPFILE '/tmp/x'",
            "SELECT '#' AS c, LOAD_FILE('/etc/passwd')",
            "SELECT '#'; DROP TABLE t",
            "SELECT '/* ' INTO OUTFILE '/tmp/x'",
        ], "in-string-comment-marker")
    }

    // The shape produced when a bound parameter closes a comment it sits inside
    // (`SELECT 1 /* ? */` + param `*/ INTO OUTFILE ... /*`): the guard, re-run on the
    // bound SQL, must see the now-live INTO OUTFILE and reject it.
    func testCommentBreakoutAfterBindingRejected() {
        assertRejected([
            "SELECT 1 /* '*/ INTO OUTFILE \"/tmp/x\" /*' */",
            "SELECT 1 /* '*/ ; DROP TABLE t /*' */",
        ], "comment-breakout")
    }

    // A comment is whitespace in MySQL: stripping must replace it with a space so
    // adjacent tokens are not merged (the stripped SQL is also what run_query runs).
    func testCommentStripInsertsWhitespace() {
        XCTAssertEqual(SPMCPReadOnlyGuard.stripCommentsQuoteAware("SELECT 1/* */AS x"), "SELECT 1 AS x")
        XCTAssertEqual(SPMCPReadOnlyGuard.stripCommentsQuoteAware("SELECT * FROM/**/t"), "SELECT * FROM t")
        // A line comment ends at the line feed of a CRLF line ending; the
        // carriage return before it belongs to the comment and a lone CR does
        // not end it, as in MySQL.
        XCTAssertEqual(SPMCPReadOnlyGuard.stripCommentsQuoteAware("SELECT 1 -- c\r\nFROM t"), "SELECT 1  \nFROM t")
        XCTAssertEqual(SPMCPReadOnlyGuard.stripCommentsQuoteAware("SELECT 1 # c\rFROM t"), "SELECT 1  ")
        // A bare `--` directly followed by CRLF starts a comment as well: the
        // stripped query must keep its SELECT prefix so run_query caps it.
        XCTAssertEqual(SPMCPReadOnlyGuard.stripCommentsQuoteAware("--\r\nSELECT 1"), " \nSELECT 1")
        XCTAssertEqual(SPMCPReadOnlyGuard.stripCommentsQuoteAware("SELECT 1 --\r\nFROM t"), "SELECT 1  \nFROM t")
        // MySQL accepts any control character after `--`, e.g. a form feed;
        // `--x` is not a comment.
        XCTAssertEqual(SPMCPReadOnlyGuard.stripCommentsQuoteAware("SELECT 1 --\u{0C}c\nFROM t"), "SELECT 1  \nFROM t")
        XCTAssertEqual(SPMCPReadOnlyGuard.stripCommentsQuoteAware("SELECT 1 --x\nFROM t"), "SELECT 1 --x\nFROM t")
        // Still caught: INTO/**/OUTFILE -> INTO OUTFILE keeps the keyword intact.
        XCTAssertFalse(SPMCPReadOnlyGuard.isReadOnly("SELECT 1 INTO/**/OUTFILE '/tmp/x'"))
        // Still allowed: a comment between other tokens is just whitespace.
        XCTAssertTrue(SPMCPReadOnlyGuard.isReadOnly("SELECT/**/1 AS a"))
    }

    // The placeholder binder scans comments itself: a `?` inside a comment is
    // copied verbatim and never bound, while a live `?` behind a comment is bound
    // whether the comment ends with LF or CRLF.
    func testPlaceholderBindingSkipsCommentsAcrossLineEndings() {
        /// Binds `params` into `sql`, rendering each value as `<value>`; returns the bound SQL or an error.
        func bind(_ sql: String, _ params: [Any]) -> (String?, String?) {
            SPMCPReadOnlyGuard.bindPlaceholders(in: sql, params: params) { "<\($0)>" }
        }

        XCTAssertEqual(bind("SELECT ? -- ?\nFROM t WHERE x = ?", [1, 2]).0, "SELECT <1> -- ?\nFROM t WHERE x = <2>")
        XCTAssertEqual(bind("SELECT ? -- ?\r\nFROM t WHERE x = ?", [1, 2]).0, "SELECT <1> -- ?\r\nFROM t WHERE x = <2>")
        XCTAssertEqual(bind("SELECT ? --\u{0C}?\nFROM t WHERE x = ?", [1, 2]).0, "SELECT <1> --\u{0C}?\nFROM t WHERE x = <2>")
        // DEL is a MySQL control character: even an unmatched quote in the
        // comment must not hide the live placeholder after its line ending.
        XCTAssertEqual(bind("SELECT ? --\u{7F}'?\r\nFROM t WHERE x = ?", [1, 2]).0, "SELECT <1> --\u{7F}'?\r\nFROM t WHERE x = <2>")
        XCTAssertEqual(bind("--\r\nSELECT ? # ?\r\nFROM t WHERE y = ?", ["a", "b"]).0, "--\r\nSELECT <a> # ?\r\nFROM t WHERE y = <b>")
        XCTAssertEqual(bind("SELECT '?' /* ? */ FROM t WHERE x = ?", [3]).0, "SELECT '?' /* ? */ FROM t WHERE x = <3>")
        // A commented `?` must not absorb a param: the counts then disagree.
        XCTAssertNotNil(bind("SELECT ? -- ?\r\nFROM t", [1, 2]).1)
        XCTAssertNotNil(bind("SELECT ?, ?", [1]).1)
    }

    // The binder walks Unicode scalars, so a combining mark after an opening
    // quote does not hide it, and it refuses placeholders whose position
    // depends on NO_BACKSLASH_ESCAPES instead of guessing the reading.
    func testPlaceholderBindingUsesScalarsAndBothBackslashReadings() {
        /// Binds `params` into `sql`, rendering each value as `<value>`; returns the bound SQL or an error.
        func bind(_ sql: String, _ params: [Any]) -> (String?, String?) {
            SPMCPReadOnlyGuard.bindPlaceholders(in: sql, params: params) { "<\($0)>" }
        }

        // `'` + U+0301 is one Character but two scalars: the `?` stays inside the literal.
        XCTAssertNotNil(bind("SELECT '\u{301}?'", [1]).1)
        XCTAssertEqual(bind("SELECT '\u{301}?' WHERE x = ?", [1]).0, "SELECT '\u{301}?' WHERE x = <1>")
        // The quote after the backslash escapes or closes the literal depending on the mode.
        XCTAssertNotNil(bind("SELECT 'a\\' , ?", [1]).1)
        XCTAssertNotNil(bind("SELECT 'a\\', ? -- '", [1]).1)
        // Backslashes that do not change where a literal ends stay bindable.
        XCTAssertEqual(bind("SELECT 'a\\\\b', ?", [1]).0, "SELECT 'a\\\\b', <1>")
        XCTAssertEqual(bind("SELECT `a\\`, ?", [1]).0, "SELECT `a\\`, <1>")
        XCTAssertEqual(bind("SELECT 'it''s', ?", [1]).0, "SELECT 'it''s', <1>")
    }

    /// Verifies that EXPLAIN ANALYZE over a write is rejected, including behind
    /// the MySQL 8.3+ `FOR SCHEMA`/`FOR DATABASE`, `INTO @var` and `FORMAT`
    /// modifiers.
    func testExplainAnalyzeWriteRejected() {
        // EXPLAIN ANALYZE executes its statement in MySQL.
        assertRejected([
            "EXPLAIN ANALYZE UPDATE t SET x = 1",
            "EXPLAIN ANALYZE DELETE FROM t",
            "EXPLAIN ANALYZE INSERT INTO t VALUES (1)",
            // MySQL 8.3+ modifiers between EXPLAIN ANALYZE and the statement.
            "EXPLAIN ANALYZE FOR SCHEMA app DELETE FROM t",
            "EXPLAIN ANALYZE INTO @plan UPDATE t SET x = 1",
            "EXPLAIN ANALYZE FORMAT=JSON INTO @plan FOR DATABASE app DELETE FROM t",
            "EXPLAIN ANALYZE FOR SCHEMA `my db` DELETE FROM t",
            "EXPLAIN ANALYZE INTO @'plan result' UPDATE t SET x = 1",
            "EXPLAIN ANALYZE FOR SCHEMA `app`UPDATE `t` SET x = 1",
            "EXPLAIN ANALYZE INTO @'plan\\' result' UPDATE t SET x = 1",
            "EXPLAIN ANALYZE FOR SCHEMA `app schema` DELETE t FROM t JOIN u ON t.id = u.id",
            // Under NO_BACKSLASH_ESCAPES the quote after the backslash closes the
            // variable, also when a comment follows it.
            "EXPLAIN ANALYZE INTO @'x\\' UPDATE t SET x='v'",
            "EXPLAIN ANALYZE INTO @'x\\' # comment\nUPDATE t SET x='v'",
            // No whitespace is needed between INTO and the variable.
            "EXPLAIN ANALYZE INTO@plan UPDATE t SET x = 1"
        ], "explain-analyze-write")
    }

    // The guard cannot know whether the connection runs with NO_BACKSLASH_ESCAPES,
    // where the quote after a backslash closes the string. Read that way, the `#`
    // below sits inside a literal and the `; DROP` behind it is a second statement,
    // which the backslash reading would have stripped as a comment.
    func testBackslashesAreReadBothWays() {
        assertRejected([
            "SELECT 'a\\' AS b, 'c # d', 1; DROP TABLE t",
            "SELECT 'a\\' AS b, 'c -- d', 1; DROP TABLE t",
            "SELECT 'a\\' AS b, 'c /* d', 1; DROP TABLE t */"
        ], "backslash-reading")
        // Each reading is judged on its own: with escapes the last quote closes
        // the variable, without them the `#` comments it out - a read either way.
        assertAllowed([
            "SELECT 'a\\\\b' # comment",
            "SELECT 'a\\\\b', 'c' /* comment */ FROM t",
            "EXPLAIN ANALYZE INTO @'x\\' # suffix'\nSELECT 1"
        ], "backslash-reading")
    }

    // A combining mark right after a quote must not hide the quote: Swift would
    // merge the two into one Character, the server reads bytes.
    func testCombiningMarksDoNotHideQuotes() {
        assertRejected([
            "SELECT '\u{301}' AS a, 'c # d', 1; DROP TABLE t",
            "EXPLAIN ANALYZE FOR SCHEMA `\u{301}app`UPDATE `t` SET x = 1",
            "EXPLAIN ANALYZE INTO @'\u{301}x' # comment\nUPDATE t SET x = 1"
        ], "combining-mark")
        assertAllowed([
            "SELECT '\u{301}' AS a FROM t"
        ], "combining-mark")
    }

    func testEmptyOrSeparatorOnlyRejected() {
        assertRejected([
            "",
            "   ",
            ";",
            ";;",
            "/* only a comment */",
            "-- only a comment",
        ], "empty")
    }

    // Conservative: a read-only CTE and a semicolon inside a string literal are
    // rejected rather than risk a parser-based bypass. Documents the trade-off.
    func testConservativeRejections() {
        assertRejected([
            "WITH cte AS (SELECT 1) SELECT * FROM cte",
            "SELECT 'a;b'",
        ], "conservative")
    }

    // explainWouldExecute: `EXPLAIN <sql>` only executes when ANALYZE is present, and
    // ANALYZE can sit behind other EXPLAIN modifiers or a /*! */ comment.
    func testExplainWouldExecuteDetectsAnalyze() {
        for sql in [
            "ANALYZE SELECT 1",
            "analyze update t set x = 1",
            "FORMAT=TREE ANALYZE UPDATE t SET x = 1",
            "FORMAT=JSON ANALYZE SELECT * FROM t",
            "/*! ANALYZE */ SELECT 1",
        ] {
            XCTAssertTrue(SPMCPReadOnlyGuard.explainWouldExecute(sql), "should flag as executing: \(sql)")
        }
    }

    func testExplainWouldExecuteAllowsPlainExplain() {
        for sql in [
            "SELECT 1",
            "FORMAT=TREE SELECT 1",
            "FORMAT=JSON SELECT * FROM t",
            "SELECT analyze_total FROM t",       // ANALYZE only as part of a column name
            "SELECT 'ANALYZE' AS label",         // ANALYZE only inside a string literal
        ] {
            XCTAssertFalse(SPMCPReadOnlyGuard.explainWouldExecute(sql), "should allow plain explain: \(sql)")
        }
    }

    /// Verifies that ANALYZE is found whatever whitespace separates it from its
    /// neighbours, a CRLF pair included. Swift folds "\r\n" into one Character that
    /// equals neither "\n" nor "\r", so a split on those alone kept
    /// "ANALYZE\r\nUPDATE" as one word and let an executing EXPLAIN through the
    /// read-only guard.
    func testExplainWouldExecuteDetectsAnalyzeAcrossLineEndings() {
        for sql in [
            "ANALYZE\r\nUPDATE a, b SET a.x = b.x WHERE a.id = b.id",
            "FORMAT=TREE\r\nANALYZE\r\nDELETE a FROM a JOIN b ON a.id = b.id",
            "ANALYZE\nUPDATE t SET x = 1",
            "ANALYZE\rUPDATE t SET x = 1",
            "ANALYZE\u{0B}UPDATE t SET x = 1",   // vertical tab, whitespace to MySQL
            "ANALYZE\u{0C}UPDATE t SET x = 1",   // form feed, whitespace to MySQL
        ] {
            XCTAssertTrue(SPMCPReadOnlyGuard.explainWouldExecute(sql), "should flag as executing: \(sql.debugDescription)")
        }
        XCTAssertFalse(SPMCPReadOnlyGuard.explainWouldExecute("FORMAT=TREE\r\nSELECT 1\r\nFROM t"))
    }

    /// Verifies that text the comment stripper keeps but the server reads as a comment
    /// cannot hide the modifier: a `--` followed by a vertical tab or form feed starts a
    /// comment for MySQL, and a SELECT inside it used to end the scan before the real
    /// ANALYZE on the next line.
    func testExplainWouldExecuteLooksPastTextTheServerIgnores() {
        for sql in [
            "--\u{0B}SELECT\nANALYZE UPDATE a, b SET a.x = b.x WHERE a.id = b.id",
            "--\u{0C} SELECT 1\nANALYZE DELETE a FROM a JOIN b ON a.id = b.id",
            // An unmatched quote in such a comment used to open a string that swallowed ANALYZE.
            "--\u{0B}'\nANALYZE UPDATE t SET x = 1",
            "--\u{7F}'\nANALYZE UPDATE t SET x = 1",
            "--\u{01}\"\nANALYZE UPDATE t SET x = 1",
            "ANALYZE(SELECT 1)",
        ] {
            XCTAssertTrue(SPMCPReadOnlyGuard.explainWouldExecute(sql), "should flag as executing: \(sql.debugDescription)")
        }
    }

    /// Verifies that ANALYZE inside a quoted operand, whatever whitespace surrounds it,
    /// does not count: MySQL 8.3 allows `EXPLAIN FORMAT=JSON INTO @'name'`, and a name
    /// or string may hold any text.
    func testExplainWouldExecuteIgnoresAnalyzeInsideQuotedOperands() {
        for sql in [
            "FORMAT=JSON INTO @'plan\r\nANALYZE\r\ncopy' SELECT 1",
            "SELECT `analyze` FROM t",
            "SELECT \"ANALYZE\" AS label",
            "SELECT 'it''s ANALYZE time' AS label",
            // After a dot MySQL reads a reserved word as an identifier.
            "SELECT t.ANALYZE FROM t",
            "SELECT * FROM db.analyze",
        ] {
            XCTAssertFalse(SPMCPReadOnlyGuard.explainWouldExecute(sql), "should allow plain explain: \(sql.debugDescription)")
        }
    }

    /// Verifies that string introducers and hex or bit literals behave like any other
    /// quoted operand: ANALYZE inside them does not count, and an ANALYZE modifier next
    /// to them is still found.
    func testExplainWouldExecuteHandlesStringIntroducers() {
        for sql in [
            "SELECT N'ANALYZE', X'414E414C595A45', B'01', _utf8mb4'analyze' AS a",
            "SELECT _latin1'it''s ANALYZE' COLLATE latin1_bin",
        ] {
            XCTAssertFalse(SPMCPReadOnlyGuard.explainWouldExecute(sql), "should allow plain explain: \(sql.debugDescription)")
        }
        for sql in [
            "ANALYZE SELECT N'x'",
            "FORMAT=TREE ANALYZE UPDATE t SET a = _utf8mb4'b', c = X'00'",
            "ANALYZE UPDATE t SET a = 'x\\'",
        ] {
            XCTAssertTrue(SPMCPReadOnlyGuard.explainWouldExecute(sql), "should flag as executing: \(sql.debugDescription)")
        }
    }
}

final class SPMCPServerRouteTests: XCTestCase {

    func testStreamableHTTPRoute() {
        XCTAssertEqual(SPMCPHTTP.route(method: "POST", path: "/mcp"), .streamableHTTP)
    }

    func testGetOnMCPPathIsMethodNotAllowed() {
        XCTAssertEqual(SPMCPHTTP.route(method: "GET", path: "/mcp"), .methodNotAllowed)
    }

    func testNonPostOnMCPPathIsMethodNotAllowed() {
        XCTAssertEqual(SPMCPHTTP.route(method: "HEAD", path: "/mcp"), .methodNotAllowed)
        XCTAssertEqual(SPMCPHTTP.route(method: "PUT", path: "/mcp"), .methodNotAllowed)
    }

    func testSSERoute() {
        XCTAssertEqual(SPMCPHTTP.route(method: "GET", path: "/sse"), .sse)
    }

    func testMessageRoute() {
        XCTAssertEqual(SPMCPHTTP.route(method: "POST", path: "/message"), .message)
    }

    func testHealthRoute() {
        XCTAssertEqual(SPMCPHTTP.route(method: "GET", path: "/health"), .health)
    }

    func testUnknownPathIsNotFound() {
        XCTAssertEqual(SPMCPHTTP.route(method: "GET", path: "/nope"), .notFound)
    }
}

final class SPMCPFavoriteTests: XCTestCase {

    func testPathStringWithNestedGroups() {
        XCTAssertEqual(
            SPMCPFavorite.pathString(groups: ["Production", "EU"], favoriteName: "main-db"),
            "Production/EU/main-db"
        )
    }

    func testPathStringWithNoGroupsIsJustTheName() {
        XCTAssertEqual(SPMCPFavorite.pathString(groups: [], favoriteName: "First"), "First")
    }

    func testPathStringDropsEmptyGroupNames() {
        XCTAssertEqual(
            SPMCPFavorite.pathString(groups: ["", "Team", ""], favoriteName: "db"),
            "Team/db"
        )
    }

    func testIDStringFromNumber() {
        XCTAssertEqual(SPMCPFavorite.idString(NSNumber(value: 42)), "42")
    }

    func testIDStringFromString() {
        XCTAssertEqual(SPMCPFavorite.idString("42"), "42")
    }

    func testIDStringIsNilForEmptyOrMissing() {
        XCTAssertNil(SPMCPFavorite.idString(""))
        XCTAssertNil(SPMCPFavorite.idString(nil))
        XCTAssertNil(SPMCPFavorite.idString(Date()))
    }
}

/// Covers the schemas advertised from tools/list. Clients such as VS Code and
/// GitHub Copilot validate them and drop any tool whose schema is malformed.
final class SAMCPToolDefinitionsTests: XCTestCase {

    private let tools = SAMCPToolDefinitions.all()

    /// The tools that write, and so must not be annotated read-only.
    private let writingTools: Set<String> = ["run_query", "kill_query", "export_results"]

    private func name(of tool: [String: Any]) -> String {
        tool["name"] as? String ?? "<unnamed>"
    }

    private func inputSchema(of tool: [String: Any]) -> [String: Any] {
        tool["inputSchema"] as? [String: Any] ?? [:]
    }

    /// The declared properties, still boxed as `Any` so that a value which is
    /// not a schema object fails its own assertion rather than emptying the
    /// whole dictionary through a failed cast.
    private func properties(of tool: [String: Any]) -> [String: Any] {
        inputSchema(of: tool)["properties"] as? [String: Any] ?? [:]
    }

    /// `true` if `schema` declares an array, written either as a bare type or
    /// inside a type union.
    private func declaresArray(_ schema: [String: Any]) -> Bool {
        if let type = schema["type"] as? String { return type == "array" }
        if let types = schema["type"] as? [String] { return types.contains("array") }
        return false
    }

    // MARK: - Catalogue

    func testToolNamesArePresentAndUnique() {
        XCTAssertFalse(tools.isEmpty)
        let names = tools.map { name(of: $0) }
        XCTAssertFalse(names.contains("<unnamed>"))
        XCTAssertEqual(Set(names).count, names.count, "tool names must be unique")
        XCTAssertTrue(names.contains("run_query"))
    }

    func testEveryToolHasADescription() {
        for tool in tools {
            XCTAssertFalse((tool["description"] as? String ?? "").isEmpty, "\(name(of: tool)) has no description")
        }
    }

    // MARK: - Schema validity

    // An array schema without "items" is invalid JSON Schema and strict clients
    // reject the whole tool.
    func testEveryArrayPropertyDeclaresItems() {
        var checked = 0
        for tool in tools {
            for (property, value) in properties(of: tool) {
                guard let schema = value as? [String: Any] else {
                    XCTFail("\(name(of: tool)).\(property) is not a schema object")
                    continue
                }
                guard declaresArray(schema) else { continue }
                checked += 1
                XCTAssertTrue(schema["items"] is [String: Any],
                              "\(name(of: tool)).\(property) declares an array without an items schema")
            }
        }
        XCTAssertGreaterThan(checked, 0, "no array property was reached, so this guard asserted nothing")
    }

    func testRunQueryParamsAcceptsTheScalarsTheBinderSupports() {
        guard let runQuery = tools.first(where: { name(of: $0) == "run_query" }) else {
            XCTFail("run_query is missing from the tool list")
            return
        }
        let params = properties(of: runQuery)["params"] as? [String: Any]
        XCTAssertEqual(params?["type"] as? String, "array")
        let items = params?["items"] as? [String: Any]
        XCTAssertEqual(items?["type"] as? [String], ["string", "number", "boolean", "null"])
    }

    func testEveryToolDeclaresAnObjectInputSchema() {
        for tool in tools {
            XCTAssertEqual(inputSchema(of: tool)["type"] as? String, "object", "\(name(of: tool)) inputSchema is not an object")
        }
    }

    func testEveryRequiredEntryNamesADeclaredProperty() {
        for tool in tools {
            let declared = properties(of: tool)
            for required in inputSchema(of: tool)["required"] as? [String] ?? [] {
                XCTAssertNotNil(declared[required], "\(name(of: tool)) requires \(required) but does not declare it")
            }
        }
    }

    func testEveryToolDefinitionIsJSONSerializable() {
        for tool in tools {
            XCTAssertTrue(JSONSerialization.isValidJSONObject(tool), "\(name(of: tool)) is not JSON-serializable")
        }
    }

    // MARK: - Annotations

    // destructiveHint is derived from the readOnly flag, so dropping that flag
    // would advertise a writing tool as safe to run unattended.
    func testOnlyWritingToolsAreAnnotatedDestructive() {
        for tool in tools {
            let annotations = tool["annotations"] as? [String: Any] ?? [:]
            let writes = writingTools.contains(name(of: tool))
            XCTAssertEqual(annotations["readOnlyHint"] as? Bool, !writes, "\(name(of: tool)) readOnlyHint")
            XCTAssertEqual(annotations["destructiveHint"] as? Bool, writes, "\(name(of: tool)) destructiveHint")
            XCTAssertEqual(annotations["openWorldHint"] as? Bool, false, "\(name(of: tool)) openWorldHint")
        }
    }
}

/// The CSV export must keep numbers as numbers while still neutralising cells a
/// spreadsheet would run as a formula.
final class SAMCPCSVTests: XCTestCase {

    /// Verifies that plain numbers, negative ones included, are written unchanged.
    func testNumbersStayNumbers() {
        for number in ["-5", "-12.50", "+3", "-1.5E+10", "-2e-3", "-.5", "-0", "42", "-7."] {
            XCTAssertEqual(SAMCPCSV.escapedField(number), number, number)
        }
    }

    /// Verifies that anything a spreadsheet could run as a formula is prefixed with a
    /// single quote, including values that only start like a number.
    func testFormulasAreNeutralised() {
        XCTAssertEqual(SAMCPCSV.escapedField("=1+1"), "'=1+1")
        XCTAssertEqual(SAMCPCSV.escapedField("@SUM(A1:A2)"), "'@SUM(A1:A2)")
        XCTAssertEqual(SAMCPCSV.escapedField("-2+3"), "'-2+3")
        XCTAssertEqual(SAMCPCSV.escapedField("+cmd|' /C calc'!A0"), "'+cmd|' /C calc'!A0")
        XCTAssertEqual(SAMCPCSV.escapedField("-1e5x"), "'-1e5x")
        XCTAssertEqual(SAMCPCSV.escapedField("- 5"), "'- 5")
        XCTAssertEqual(SAMCPCSV.escapedField("-"), "'-")
        // Digits outside ASCII are not a number MySQL returns.
        XCTAssertEqual(SAMCPCSV.escapedField("-\u{0663}"), "'-\u{0663}")
    }

    /// Verifies that a leading tab or carriage return is neutralised, also when the
    /// carriage return starts a CRLF pair, which Swift treats as one Character.
    func testLeadingControlCharactersAreNeutralised() {
        XCTAssertEqual(SAMCPCSV.escapedField("\tfoo"), "'\tfoo")
        XCTAssertEqual(SAMCPCSV.escapedField("\r=cmd"), "\"'\r=cmd\"")
        XCTAssertEqual(SAMCPCSV.escapedField("\r\n=cmd"), "\"'\r\n=cmd\"")
    }

    /// Verifies that fields holding a separator, a double quote or a line break are
    /// enclosed in double quotes, a CRLF pair included.
    func testFieldsAreQuotedWhenNeeded() {
        XCTAssertEqual(SAMCPCSV.escapedField("plain"), "plain")
        XCTAssertEqual(SAMCPCSV.escapedField("a,b"), "\"a,b\"")
        XCTAssertEqual(SAMCPCSV.escapedField("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(SAMCPCSV.escapedField("line\nbreak"), "\"line\nbreak\"")
        XCTAssertEqual(SAMCPCSV.escapedField("a\r\nb"), "\"a\r\nb\"")
        XCTAssertEqual(SAMCPCSV.escapedField("-5,0"), "\"'-5,0\"")
    }

    /// Verifies that a double quote followed by a combining mark is found and doubled.
    /// Compared as Characters the two form one cluster that is not a quote, so the
    /// field used to stay unquoted with a bare quote inside.
    func testQuoteFollowedByACombiningMarkIsEscaped() {
        XCTAssertEqual(SAMCPCSV.escapedField("a\"\u{301}b"), "\"a\"\"\u{301}b\"")
    }
}

/// `containsAnyUnicodeScalar(of:)` is the shared answer to Swift folding "\r\n" (and a
/// quote plus a combining mark) into one Character that `contains` does not match.
final class SAStringUnicodeScalarSearchTests: XCTestCase {

    /// Verifies that line breaks are found alone and inside a CRLF pair, and only then.
    func testLineBreaksAreFoundInEveryForm() {
        XCTAssertTrue("a\r\nb".containsAnyUnicodeScalar(of: "\n"))
        XCTAssertTrue("a\r\nb".containsAnyUnicodeScalar(of: "\r"))
        XCTAssertTrue("a\nb".containsAnyUnicodeScalar(of: "\n\r"))
        XCTAssertTrue("a\rb".containsAnyUnicodeScalar(of: "\n\r"))
        XCTAssertFalse("a\tb c".containsAnyUnicodeScalar(of: "\n\r"))
        XCTAssertFalse("".containsAnyUnicodeScalar(of: "\n\r"))
    }

    /// Verifies that any listed scalar is found, also when it is merged into a cluster
    /// with the next one.
    func testAnyListedScalarIsFound() {
        XCTAssertTrue("a\"\u{301}b".containsAnyUnicodeScalar(of: ",\""))
        XCTAssertTrue("x,y".containsAnyUnicodeScalar(of: ",\""))
        XCTAssertFalse("xy".containsAnyUnicodeScalar(of: ",\""))
        XCTAssertFalse("xy".containsAnyUnicodeScalar(of: ""))
        XCTAssertTrue("ab".prefix(1).containsAnyUnicodeScalar(of: "a"))
        XCTAssertFalse("ab".prefix(1).containsAnyUnicodeScalar(of: "b"))
    }
}



/// The query executor must not change a validated read while applying its cap.
final class SAMCPResultLimitSQLTests: XCTestCase {
    func testValidNoBackslashEscapesReadKeepsItsOriginalSQL() {
        let sql = "SELECT 'a\\' AS a, 'b#c' AS b"
        XCTAssertTrue(SPMCPReadOnlyGuard.isReadOnly(sql))
        XCTAssertEqual(SPMCPReadOnlyGuard.stripCommentsQuoteAware(sql, backslashEscapes: false), sql)
        XCTAssertNotEqual(SPMCPReadOnlyGuard.stripCommentsQuoteAware(sql), sql)
        XCTAssertNil(SPMCPReadOnlyGuard.sqlForResultLimiting(sql),
                     "the executor must retain the query and enforce only its read-side cap")
    }

    func testAmbiguousDashAndBlockMarkersAreNotRewritten() {
        for marker in ["-- ", "/*"] {
            let sql = "SELECT 'a\\' AS a, 'b" + marker + "c' AS b"
            XCTAssertTrue(SPMCPReadOnlyGuard.isReadOnly(sql))
            XCTAssertNil(SPMCPReadOnlyGuard.sqlForResultLimiting(sql), marker)
        }
    }

    func testOrdinaryCommentsCanStillBeStrippedAndCapped() {
        let sql = "/* leading */ SELECT 'a\\\\b#c' AS value -- trailing\r\n"
        let stripped = SPMCPReadOnlyGuard.sqlForResultLimiting(sql)
        XCTAssertEqual(stripped?.trimmingCharacters(in: .whitespacesAndNewlines), "SELECT 'a\\\\b#c' AS value")
        XCTAssertTrue(SPMCPReadOnlyGuard.isReadOnly(sql))
    }

    func testExecutableCommentsAreNeverRewrittenForLimiting() {
        for sql in ["SELECT 1 /*! UNION SELECT 2 */", "SELECT 1 /*M! UNION SELECT 2 */"] {
            XCTAssertNil(SPMCPReadOnlyGuard.sqlForResultLimiting(sql))
            XCTAssertFalse(SPMCPReadOnlyGuard.isReadOnly(sql))
        }
    }
}
