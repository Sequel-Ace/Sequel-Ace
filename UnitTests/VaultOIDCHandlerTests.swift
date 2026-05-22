//  VaultOIDCHandlerTests.swift
//  Sequel Ace

import XCTest

final class VaultOIDCHandlerTests: XCTestCase {

    // MARK: - Token file isolation

    private var tempTokenDir: URL?

    override func setUp() {
        super.setUp()
        // Point VaultOIDCHandler at a private temp file instead of the real ~/.vault-token
        // so tests never read, write, or delete the developer's Vault CLI session.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultOIDCHandlerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempTokenDir = dir
        VaultOIDCHandler.tokenFilePathOverride = dir.appendingPathComponent(".vault-token").path
    }

    override func tearDown() {
        VaultOIDCHandler.tokenFilePathOverride = nil
        if let dir = tempTokenDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

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
        // Temporarily clear the test override to exercise the real production path.
        let savedOverride = VaultOIDCHandler.tokenFilePathOverride
        VaultOIDCHandler.tokenFilePathOverride = nil
        let path = VaultOIDCHandler.tokenFilePath()
        VaultOIDCHandler.tokenFilePathOverride = savedOverride

        XCTAssertTrue(path.hasPrefix(NSHomeDirectory()))
        XCTAssertTrue(path.hasSuffix(".vault-token"))
    }
}
