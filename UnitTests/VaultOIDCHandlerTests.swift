//  VaultOIDCHandlerTests.swift
//  Sequel Ace

import XCTest

final class VaultOIDCHandlerTests: XCTestCase {

    // MARK: - Token store isolation

    override func setUp() {
        super.setUp()
        VaultOIDCHandler.clearCachedTokensForTesting()
        VaultOIDCHandler.useInMemoryTokenStoreForTesting()
    }

    override func tearDown() {
        VaultOIDCHandler.clearCachedTokensForTesting()
        VaultOIDCHandler.clearInMemoryTokenStoreForTesting()
        VaultOIDCHandler.disableInMemoryTokenStoreForTesting()
        super.tearDown()
    }

    // MARK: - parseQueryParams

    func testCancelActiveLoginRecordsCancellationAndSignalsSemaphore() {
        let semaphore = DispatchSemaphore(value: 0)
        let identifier = VaultOIDCHandler.prepareActiveLogin()
        VaultOIDCHandler.registerActiveLoginForTesting(semaphore: semaphore, identifier: identifier)
        defer { VaultOIDCHandler.clearActiveLoginForTesting(semaphore: semaphore, identifier: identifier) }

        XCTAssertFalse(VaultOIDCHandler.isActiveLoginCancelledForTesting(identifier: identifier))

        VaultOIDCHandler.cancelActiveLogin(identifier: identifier)

        XCTAssertTrue(VaultOIDCHandler.isActiveLoginCancelledForTesting(identifier: identifier))
        XCTAssertEqual(semaphore.wait(timeout: .now()), .success)
    }

    func testCancelActiveLoginRecordsCancellationBeforeSemaphoreRegistration() {
        let semaphore = DispatchSemaphore(value: 0)
        let identifier = VaultOIDCHandler.prepareActiveLogin()
        defer { VaultOIDCHandler.clearActiveLoginForTesting(semaphore: semaphore, identifier: identifier) }

        VaultOIDCHandler.cancelActiveLogin(identifier: identifier)
        XCTAssertTrue(VaultOIDCHandler.isActiveLoginCancelledForTesting(identifier: identifier))

        VaultOIDCHandler.registerActiveLoginForTesting(semaphore: semaphore, identifier: identifier)

        XCTAssertTrue(VaultOIDCHandler.isActiveLoginCancelledForTesting(identifier: identifier))
        XCTAssertEqual(semaphore.wait(timeout: .now()), .timedOut)
    }

    func testClearPreparedActiveLoginRemovesCancelledPreparedLogin() {
        let identifier = VaultOIDCHandler.prepareActiveLogin()

        VaultOIDCHandler.cancelActiveLogin(identifier: identifier)
        XCTAssertTrue(VaultOIDCHandler.isActiveLoginCancelledForTesting(identifier: identifier))

        VaultOIDCHandler.clearPreparedActiveLogin(identifier: identifier)

        XCTAssertFalse(VaultOIDCHandler.isActiveLoginCancelledForTesting(identifier: identifier))
    }

    func testCancelActiveLoginOnlySignalsMatchingIdentifier() {
        let firstSemaphore = DispatchSemaphore(value: 0)
        let secondSemaphore = DispatchSemaphore(value: 0)
        let firstIdentifier = VaultOIDCHandler.prepareActiveLogin()
        let secondIdentifier = VaultOIDCHandler.prepareActiveLogin()
        VaultOIDCHandler.registerActiveLoginForTesting(semaphore: firstSemaphore, identifier: firstIdentifier)
        VaultOIDCHandler.registerActiveLoginForTesting(semaphore: secondSemaphore, identifier: secondIdentifier)
        defer {
            VaultOIDCHandler.clearActiveLoginForTesting(semaphore: firstSemaphore, identifier: firstIdentifier)
            VaultOIDCHandler.clearActiveLoginForTesting(semaphore: secondSemaphore, identifier: secondIdentifier)
        }

        VaultOIDCHandler.cancelActiveLogin(identifier: secondIdentifier)

        XCTAssertFalse(VaultOIDCHandler.isActiveLoginCancelledForTesting(identifier: firstIdentifier))
        XCTAssertTrue(VaultOIDCHandler.isActiveLoginCancelledForTesting(identifier: secondIdentifier))
        XCTAssertEqual(firstSemaphore.wait(timeout: .now()), .timedOut)
        XCTAssertEqual(secondSemaphore.wait(timeout: .now()), .success)
    }

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

    // MARK: - mount-scoped token persistence

    func testSaveAndReadRoundtripForVaultAddress() {
        let baseURL = VaultClient.buildBaseURL(host: "vault-prod.example.com", port: "443")!
        let testToken = "test-hvs-\(UUID().uuidString)"

        VaultOIDCHandler.saveToken(testToken, for: baseURL, mount: "oidc")
        VaultOIDCHandler.clearCachedTokensForTesting()

        XCTAssertEqual(VaultOIDCHandler.cachedToken(for: baseURL, mount: "oidc"), testToken)
    }

    func testCachedTokenReturnsNilWhenNoTokenExistsForVaultAddress() {
        let baseURL = VaultClient.buildBaseURL(host: "vault-prod.example.com", port: "443")!

        XCTAssertNil(VaultOIDCHandler.cachedToken(for: baseURL, mount: "oidc"))
    }

    func testCachedTokenRejectsPersistedTokenForDifferentVaultAddress() {
        let prodURL = VaultClient.buildBaseURL(host: "vault-prod.example.com", port: "443")!
        let stagingURL = VaultClient.buildBaseURL(host: "vault-staging.example.com", port: "443")!

        VaultOIDCHandler.saveToken("prod-token", for: prodURL, mount: "oidc")
        VaultOIDCHandler.clearCachedTokensForTesting()

        XCTAssertNil(VaultOIDCHandler.cachedToken(for: stagingURL, mount: "oidc"))
    }

    func testCachedTokenRejectsPersistedTokenForDifferentOIDCMount() {
        let baseURL = VaultClient.buildBaseURL(host: "vault-prod.example.com", port: "443")!

        VaultOIDCHandler.saveToken("default-token", for: baseURL, mount: "oidc")
        VaultOIDCHandler.clearCachedTokensForTesting()

        XCTAssertNil(VaultOIDCHandler.cachedToken(for: baseURL, mount: "okta"))
    }

    func testCachedTokenStoresDifferentTokensForDifferentOIDCMounts() {
        let baseURL = VaultClient.buildBaseURL(host: "vault-prod.example.com", port: "443")!

        VaultOIDCHandler.saveToken("default-token", for: baseURL, mount: "oidc")
        VaultOIDCHandler.saveToken("okta-token", for: baseURL, mount: "okta")
        VaultOIDCHandler.clearCachedTokensForTesting()

        XCTAssertEqual(VaultOIDCHandler.cachedToken(for: baseURL, mount: "oidc"), "default-token")
        XCTAssertEqual(VaultOIDCHandler.cachedToken(for: baseURL, mount: "okta"), "okta-token")
    }

    func testCachedTokenUsesInSessionTokenBeforePersistedToken() {
        let baseURL = VaultClient.buildBaseURL(host: "vault-prod.example.com", port: "443")!

        VaultOIDCHandler.saveToken("persisted-token", for: baseURL, mount: "oidc")
        XCTAssertEqual(VaultOIDCHandler.cachedToken(for: baseURL, mount: "oidc"), "persisted-token")
        VaultOIDCHandler.saveToken("new-persisted-token", for: baseURL, mount: "oidc")

        XCTAssertEqual(VaultOIDCHandler.cachedToken(for: baseURL, mount: "oidc"), "persisted-token")
    }

    func testEmptyMountUsesDefaultOIDCScope() {
        let baseURL = VaultClient.buildBaseURL(host: "vault-prod.example.com", port: "443")!

        VaultOIDCHandler.saveToken("default-token", for: baseURL, mount: "oidc")
        VaultOIDCHandler.clearCachedTokensForTesting()

        XCTAssertEqual(VaultOIDCHandler.cachedToken(for: baseURL, mount: "  "), "default-token")
    }

    // MARK: - Exclusive login (process-wide OIDC port serialization)

    func testExclusiveLoginGuardBlocksSecondConcurrentLogin() {
        XCTAssertFalse(VaultOIDCHandler.isLoginInProgressForTesting())

        // First claim succeeds and marks a login in progress.
        XCTAssertTrue(VaultOIDCHandler.beginExclusiveLoginForTesting())
        XCTAssertTrue(VaultOIDCHandler.isLoginInProgressForTesting())

        // A second concurrent claim (another window / connect vs refresh) is refused.
        XCTAssertFalse(VaultOIDCHandler.beginExclusiveLoginForTesting())

        // Releasing frees the slot so the next login can claim it.
        VaultOIDCHandler.endExclusiveLoginForTesting()
        XCTAssertFalse(VaultOIDCHandler.isLoginInProgressForTesting())
        XCTAssertTrue(VaultOIDCHandler.beginExclusiveLoginForTesting())
        VaultOIDCHandler.endExclusiveLoginForTesting()
    }
}
