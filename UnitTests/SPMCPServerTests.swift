//
//  SPMCPServerTests.swift
//  Unit Tests
//
//  Covers the hand-rolled HTTP request parser and the Origin allow-list used
//  by the MCP server's loopback/DNS-rebinding protection.
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
            "EXPLAIN FORMAT=JSON SELECT * FROM t",
            "(SELECT * FROM t)",
            "SELECT a FROM t UNION SELECT b FROM u",
            "/* leading comment */ SELECT 1",
            "-- a comment\nSELECT 1",
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

    func testCommentHiddenWritesRejected() {
        assertRejected([
            "/* x */ DELETE FROM t",
            "-- c\nUPDATE t SET x = 1",
            "# c\nDROP TABLE t",
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
        // Still caught: INTO/**/OUTFILE -> INTO OUTFILE keeps the keyword intact.
        XCTAssertFalse(SPMCPReadOnlyGuard.isReadOnly("SELECT 1 INTO/**/OUTFILE '/tmp/x'"))
        // Still allowed: a comment between other tokens is just whitespace.
        XCTAssertTrue(SPMCPReadOnlyGuard.isReadOnly("SELECT/**/1 AS a"))
    }

    func testExplainAnalyzeWriteRejected() {
        // EXPLAIN ANALYZE executes its statement in MySQL.
        assertRejected([
            "EXPLAIN ANALYZE UPDATE t SET x = 1",
            "EXPLAIN ANALYZE DELETE FROM t",
            "EXPLAIN ANALYZE INSERT INTO t VALUES (1)",
        ], "explain-analyze-write")
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
}
