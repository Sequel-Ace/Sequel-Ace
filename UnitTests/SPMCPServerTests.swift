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
