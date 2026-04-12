//  VaultOIDCHandlerTests.swift
//  Sequel Ace

import XCTest

final class VaultOIDCHandlerTests: XCTestCase {

    // MARK: - parseQueryParams

    func testParseQueryParamsExtractsStateAndCode() {
        let requestLine = "GET /oidc/callback?state=abc123&code=xyz HTTP/1.1"
        let params = VaultOIDCHandler.parseQueryParams(from: requestLine)
        XCTAssertEqual(params["state"], "abc123")
        XCTAssertEqual(params["code"], "xyz")
    }

    func testParseQueryParamsDecodesPercentEncoding() {
        let requestLine = "GET /oidc/callback?state=hello%20world&code=a%2Bb HTTP/1.1"
        let params = VaultOIDCHandler.parseQueryParams(from: requestLine)
        XCTAssertEqual(params["state"], "hello world")
        XCTAssertEqual(params["code"], "a+b")
    }

    func testParseQueryParamsReturnsEmptyForMissingQuery() {
        let requestLine = "GET /oidc/callback HTTP/1.1"
        let params = VaultOIDCHandler.parseQueryParams(from: requestLine)
        XCTAssertTrue(params.isEmpty)
    }

    func testParseQueryParamsReturnsEmptyForEmptyString() {
        let params = VaultOIDCHandler.parseQueryParams(from: "")
        XCTAssertTrue(params.isEmpty)
    }

    func testParseQueryParamsHandlesErrorParam() {
        let requestLine = "GET /oidc/callback?error=access_denied HTTP/1.1"
        let params = VaultOIDCHandler.parseQueryParams(from: requestLine)
        XCTAssertEqual(params["error"], "access_denied")
    }

    // MARK: - randomBase64URLToken

    func testRandomBase64URLTokenIsNonEmpty() {
        XCTAssertFalse(VaultOIDCHandler.randomBase64URLToken().isEmpty)
    }

    func testRandomBase64URLTokenContainsOnlyBase64URLCharacters() {
        for _ in 0..<20 {
            let token = VaultOIDCHandler.randomBase64URLToken()
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            XCTAssertTrue(token.unicodeScalars.allSatisfy { allowed.contains($0) },
                          "Token '\(token)' contains characters outside base64url alphabet")
        }
    }

    func testRandomBase64URLTokenContainsNoPadding() {
        for _ in 0..<20 {
            XCTAssertFalse(VaultOIDCHandler.randomBase64URLToken().contains("="))
        }
    }

    func testRandomBase64URLTokenIsUnique() {
        let tokens = Set((0..<50).map { _ in VaultOIDCHandler.randomBase64URLToken() })
        XCTAssertEqual(tokens.count, 50, "Tokens should be unique across invocations")
    }

    // MARK: - saveToken / readCachedToken roundtrip

    func testSaveAndReadRoundtrip() {
        let testToken = "test-hvs-\(UUID().uuidString)"
        VaultOIDCHandler.saveToken(testToken)
        let result = VaultOIDCHandler.readCachedToken()
        XCTAssertEqual(result, testToken)
    }

    func testReadCachedTokenReturnsNilWhenFileAbsent() {
        try? FileManager.default.removeItem(atPath: VaultOIDCHandler.tokenFilePath())
        XCTAssertNil(VaultOIDCHandler.readCachedToken())
    }

    func testReadCachedTokenTrimsWhitespace() {
        VaultOIDCHandler.saveToken("  hvs.abc123\n")
        // saveToken writes exactly what it's given; test that readCachedToken trims
        // by writing via Foundation and reading back
        let path = VaultOIDCHandler.tokenFilePath()
        try? "  hvs.abc123\n".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(VaultOIDCHandler.readCachedToken(), "hvs.abc123")
    }

    func testTokenFileHasMode0600() throws {
        VaultOIDCHandler.saveToken("test-token")
        let attrs = try FileManager.default.attributesOfItem(atPath: VaultOIDCHandler.tokenFilePath())
        let perms = attrs[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600, "~/.vault-token must be mode 0600")
    }

    // MARK: - tokenFilePath

    func testTokenFilePathIsInHomeDirectory() {
        let path = VaultOIDCHandler.tokenFilePath()
        XCTAssertTrue(path.hasPrefix(NSHomeDirectory()))
        XCTAssertTrue(path.hasSuffix(".vault-token"))
    }
}
