//  VaultClientTests.swift
//  Sequel Ace

import XCTest

final class VaultClientTests: XCTestCase {

    // MARK: - buildBaseURL

    func testBuildBaseURLCombinesHostAndPort() {
        let url = VaultClient.buildBaseURL(host: "vault.example.com", port: "8200")
        XCTAssertEqual(url?.absoluteString, "https://vault.example.com:8200")
    }

    func testBuildBaseURLUsesDefaultPortWhenEmpty() {
        let url = VaultClient.buildBaseURL(host: "vault.example.com", port: "")
        XCTAssertEqual(url?.absoluteString, "https://vault.example.com:443")
    }

    func testBuildBaseURLReturnsNilForEmptyHost() {
        let url = VaultClient.buildBaseURL(host: "", port: "8200")
        XCTAssertNil(url)
    }

    // MARK: - parseCredentials

    func testParseCredentialsExtractsUsernamePasswordAndLease() throws {
        let json = """
        {
          "lease_duration": 3600,
          "data": {
            "username": "v-token-myuser",
            "password": "s3cr3t"
          }
        }
        """.data(using: .utf8)!
        let result = try VaultClient.parseCredentials(from: json)
        XCTAssertEqual(result.username, "v-token-myuser")
        XCTAssertEqual(result.password, "s3cr3t")
        XCTAssertEqual(result.leaseDuration, 3600)
    }

    func testParseCredentialsThrowsWhenUsernameAbsent() {
        let json = """
        { "lease_duration": 3600, "data": { "password": "s3cr3t" } }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try VaultClient.parseCredentials(from: json))
    }

    func testParseCredentialsThrowsWhenPasswordAbsent() {
        let json = """
        { "lease_duration": 3600, "data": { "username": "user" } }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try VaultClient.parseCredentials(from: json))
    }

    func testParseCredentialsDefaultsLeaseDurationWhenAbsent() throws {
        // cache-eviction margin (30 s) is applied to leaseDuration, so the
        // fallback value must be exactly 3600 for the default to be meaningful.
        let json = """
        { "data": { "username": "v-user", "password": "s3cr3t" } }
        """.data(using: .utf8)!
        let result = try VaultClient.parseCredentials(from: json)
        XCTAssertEqual(result.leaseDuration, 3600)
    }

    // MARK: - parseOIDCAuthURL

    func testParseOIDCAuthURLExtractsURL() throws {
        let json = """
        { "data": { "auth_url": "https://idp.example.com/oauth2/auth?state=abc" } }
        """.data(using: .utf8)!
        let url = try VaultClient.parseOIDCAuthURL(from: json)
        XCTAssertEqual(url.absoluteString, "https://idp.example.com/oauth2/auth?state=abc")
    }

    func testParseOIDCAuthURLThrowsWhenMissing() {
        let json = """
        { "data": {} }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try VaultClient.parseOIDCAuthURL(from: json))
    }

    func testParseOIDCAuthURLRejectsHTTP() {
        // Vault should only return HTTPS auth URLs; plaintext HTTP must be rejected
        // to prevent a compromised Vault instance from directing the user to an
        // HTTP OIDC provider.
        let json = """
        { "data": { "auth_url": "http://idp.example.com/oauth2/auth?state=abc" } }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try VaultClient.parseOIDCAuthURL(from: json))
    }

    func testParseOIDCAuthURLRejectsNonHTTPSSchemes() {
        // A compromised Vault could return javascript:, file:, or custom schemes
        // that NSWorkspace.open() would dispatch. The HTTPS-only guard must reject
        // all of them to prevent open-redirect and code-execution attacks.
        let hostileURLs = [
            "javascript:alert(1)",
            "file:///etc/passwd",
            "x-myapp://attacker.example.com/steal",
            "data:text/html,<script>alert(1)</script>",
        ]
        for urlString in hostileURLs {
            let json = "{ \"data\": { \"auth_url\": \"\(urlString)\" } }".data(using: .utf8)!
            XCTAssertThrowsError(
                try VaultClient.parseOIDCAuthURL(from: json),
                "Scheme must be rejected: \(urlString)"
            )
        }
    }

    func testOIDCAuthURLRequestBodyUsesClientNonce() {
        let body = VaultClient.oidcAuthURLRequestBody(
            redirectURI: "http://localhost:8250/oidc/callback",
            role: "reader",
            state: "state-123",
            nonce: "nonce-123"
        )

        XCTAssertEqual(body["redirect_uri"] as? String, "http://localhost:8250/oidc/callback")
        XCTAssertEqual(body["role"] as? String, "reader")
        XCTAssertEqual(body["state"] as? String, "state-123")
        XCTAssertEqual(body["client_nonce"] as? String, "nonce-123")
        XCTAssertNil(body["nonce"], "Vault expects client_nonce, not nonce")
    }

    func testOIDCCallbackURLUsesClientNonce() throws {
        let baseURL = try XCTUnwrap(VaultClient.buildBaseURL(host: "vault.example.com", port: "8200"))
        let url = try XCTUnwrap(VaultClient.oidcCallbackURL(
            baseURL: baseURL,
            mount: "oidc",
            state: "state-123",
            nonce: "nonce-123",
            code: "code-123"
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/v1/auth/oidc/oidc/callback")
        XCTAssertEqual(items["state"] ?? nil, "state-123")
        XCTAssertEqual(items["client_nonce"] ?? nil, "nonce-123")
        XCTAssertEqual(items["code"] ?? nil, "code-123")
        XCTAssertNil(items["nonce"] ?? nil, "Vault expects client_nonce, not nonce")
    }

    // MARK: - parseToken

    func testParseTokenExtractsClientToken() throws {
        let json = """
        { "auth": { "client_token": "s.abc123" } }
        """.data(using: .utf8)!
        let token = try VaultClient.parseToken(from: json)
        XCTAssertEqual(token, "s.abc123")
    }

    func testParseTokenThrowsWhenMissing() {
        let json = """
        { "auth": {} }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try VaultClient.parseToken(from: json))
    }

    // MARK: - parseRoleList

    func testParseRoleListExtractsAndSortsKeys() throws {
        let json = """
        { "data": { "keys": ["prod", "dev", "Analytics"] } }
        """.data(using: .utf8)!
        let roles = try VaultClient.parseRoleList(from: json)
        XCTAssertEqual(roles, ["Analytics", "dev", "prod"]) // case-insensitive ascending
    }

    func testParseRoleListEmptyKeysReturnsEmptyArray() throws {
        let json = """
        { "data": { "keys": [] } }
        """.data(using: .utf8)!
        XCTAssertEqual(try VaultClient.parseRoleList(from: json), [])
    }

    func testParseRoleListThrowsWhenDataMissing() {
        let json = "{ \"foo\": 1 }".data(using: .utf8)!
        XCTAssertThrowsError(try VaultClient.parseRoleList(from: json))
    }

    // MARK: - rolesURL (mount validation + encoding)

    private var vaultBase: URL { VaultClient.buildBaseURL(host: "vault.example.com", port: "443")! }

    func testRolesURLForSimpleMount() throws {
        let url = try VaultClient.rolesURL(baseURL: vaultBase, mount: "databases_credentials")
        XCTAssertEqual(url.host, "vault.example.com")
        XCTAssertEqual(url.path, "/v1/databases_credentials/roles")
    }

    func testRolesURLPreservesNestedMountSegments() throws {
        let url = try VaultClient.rolesURL(baseURL: vaultBase, mount: "team/db")
        XCTAssertEqual(url.path, "/v1/team/db/roles")
    }

    func testRolesURLTrimsWhitespaceAndSurroundingSlashes() throws {
        let url = try VaultClient.rolesURL(baseURL: vaultBase, mount: "  /databases_credentials/  ")
        XCTAssertEqual(url.path, "/v1/databases_credentials/roles")
    }

    func testRolesURLAllowsVaultLegalCharacters() throws {
        // '+', '@', and spaces are valid in Vault mount paths and must be accepted
        // (they are percent-encoded on the wire, not rejected).
        for mount in ["db+role", "team@corp", "my mount"] {
            let url = try VaultClient.rolesURL(baseURL: vaultBase, mount: mount)
            XCTAssertEqual(url.host, "vault.example.com", "host must never change for \(mount)")
            XCTAssertTrue(url.absoluteString.hasPrefix("https://vault.example.com:443/v1/"))
            XCTAssertTrue(url.absoluteString.hasSuffix("/roles"))
        }
    }

    func testRolesURLRejectsEmptyMount() {
        XCTAssertThrowsError(try VaultClient.rolesURL(baseURL: vaultBase, mount: "   "))
    }

    func testRolesURLRejectsTraversalSegments() {
        XCTAssertThrowsError(try VaultClient.rolesURL(baseURL: vaultBase, mount: "../secret"))
        XCTAssertThrowsError(try VaultClient.rolesURL(baseURL: vaultBase, mount: "team/../secret"))
        XCTAssertThrowsError(try VaultClient.rolesURL(baseURL: vaultBase, mount: "."))
    }

    func testRolesURLRejectsEmptyInteriorSegment() {
        XCTAssertThrowsError(try VaultClient.rolesURL(baseURL: vaultBase, mount: "team//db"))
    }

    func testRolesURLRejectsControlCharacters() {
        XCTAssertThrowsError(try VaultClient.rolesURL(baseURL: vaultBase, mount: "team\u{0000}db"))
        XCTAssertThrowsError(try VaultClient.rolesURL(baseURL: vaultBase, mount: "team\ndb"))
    }

    func testRolesURLPercentEncodedTraversalDoesNotEscapeMount() throws {
        // A literal "%2e%2e" is printable and passes the segment guard, but must
        // NOT decode into a ".." traversal: appendingPathComponent re-encodes the
        // "%" so it stays a literal segment, keeping the request under the mount.
        let url = try VaultClient.rolesURL(baseURL: vaultBase, mount: "team/%2e%2e/secret")
        XCTAssertEqual(url.host, "vault.example.com")
        XCTAssertTrue(url.absoluteString.contains("%252e%252e"), "percent must be re-encoded: \(url.absoluteString)")
        XCTAssertFalse(url.absoluteString.contains("/../"))
    }

    func testRolesURLCannotChangeHost() throws {
        // A mount that looks like an authority component stays a path segment.
        let url = try VaultClient.rolesURL(baseURL: vaultBase, mount: "@evil.com")
        XCTAssertEqual(url.host, "vault.example.com")
        XCTAssertEqual(url.path, "/v1/@evil.com/roles")
    }
}
