//  VaultAuthManagerTests.swift
//  Sequel Ace

import XCTest

final class VaultAuthManagerTests: XCTestCase {

    // Cache is backed by process-wide static state (credentialCache + cacheLock).
    // Tests assume serial execution; enable test-plan parallelization with care.
    override func setUp() {
        super.setUp()
        VaultAuthManager.clearCachedCredentials(for: nil)
    }

    // MARK: - Credential cache

    func testCredentialCacheReturnsCachedEntryBeforeExpiry() {
        let cached = VaultAuthManager.cachedCredentials(for: "databases_credentials/creds/role-a")
        XCTAssertNil(cached, "Cache should be empty initially")

        VaultAuthManager.setCachedCredentials(
            username: "u1",
            password: "p1",
            leaseDuration: 3600,
            for: "databases_credentials/creds/role-a"
        )

        let hit = VaultAuthManager.cachedCredentials(for: "databases_credentials/creds/role-a")
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.username, "u1")
        XCTAssertEqual(hit?.password, "p1")
    }

    func testCredentialCacheMissForDifferentPath() {
        VaultAuthManager.setCachedCredentials(
            username: "u1",
            password: "p1",
            leaseDuration: 3600,
            for: "databases_credentials/creds/role-a"
        )
        let miss = VaultAuthManager.cachedCredentials(for: "databases_credentials/creds/role-b")
        XCTAssertNil(miss)
    }

    func testClearCachedCredentialsForSpecificPath() {
        VaultAuthManager.setCachedCredentials(username: "u1", password: "p1", leaseDuration: 3600, for: "path/a")
        VaultAuthManager.setCachedCredentials(username: "u2", password: "p2", leaseDuration: 3600, for: "path/b")

        VaultAuthManager.clearCachedCredentials(for: "path/a")

        XCTAssertNil(VaultAuthManager.cachedCredentials(for: "path/a"))
        XCTAssertNotNil(VaultAuthManager.cachedCredentials(for: "path/b"))
    }

    func testClearAllCachedCredentials() {
        VaultAuthManager.setCachedCredentials(username: "u1", password: "p1", leaseDuration: 3600, for: "path/a")
        VaultAuthManager.setCachedCredentials(username: "u2", password: "p2", leaseDuration: 3600, for: "path/b")

        VaultAuthManager.clearCachedCredentials(for: nil)

        XCTAssertNil(VaultAuthManager.cachedCredentials(for: "path/a"))
        XCTAssertNil(VaultAuthManager.cachedCredentials(for: "path/b"))
    }

    // MARK: - Composite cache key

    func testCacheKeyIncludesHostAndPort() {
        let url1 = VaultClient.buildBaseURL(host: "vault-prod.example.com", port: "443")!
        let url2 = VaultClient.buildBaseURL(host: "vault-staging.example.com", port: "443")!
        let credPath = "databases_credentials/creds/readonly"

        let key1 = VaultAuthManager.cacheKey(baseURL: url1, oidcMount: "oidc", credPath: credPath)
        let key2 = VaultAuthManager.cacheKey(baseURL: url2, oidcMount: "oidc", credPath: credPath)

        XCTAssertNotEqual(key1, key2, "Two different Vault servers must produce different cache keys even with the same credPath")
    }

    func testCacheDoesNotCrossContaminateBetweenHosts() {
        let url1 = VaultClient.buildBaseURL(host: "vault-prod.example.com", port: "443")!
        let url2 = VaultClient.buildBaseURL(host: "vault-staging.example.com", port: "443")!
        let credPath = "databases_credentials/creds/readonly"

        VaultAuthManager.setCachedCredentials(username: "prod-user", password: "prod-pass",
                                              leaseDuration: 3600,
                                              for: VaultAuthManager.cacheKey(baseURL: url1, oidcMount: "oidc", credPath: credPath))

        let hit = VaultAuthManager.cachedCredentials(for: VaultAuthManager.cacheKey(baseURL: url1, oidcMount: "oidc", credPath: credPath))
        let miss = VaultAuthManager.cachedCredentials(for: VaultAuthManager.cacheKey(baseURL: url2, oidcMount: "oidc", credPath: credPath))

        XCTAssertEqual(hit?.username, "prod-user")
        XCTAssertNil(miss, "Staging server must not see prod credentials")
    }

    func testExpiredCacheEntryIsNotReturned() {
        // Set with 0 second lease — expires immediately
        VaultAuthManager.setCachedCredentials(username: "u1", password: "p1", leaseDuration: 0, for: "path/expired")
        // Tiny lease = already expired (margin is 30s, so 0 < 30 means expired)
        let result = VaultAuthManager.cachedCredentials(for: "path/expired")
        XCTAssertNil(result, "Zero-duration lease should not be returned from cache")
    }

    func testCacheRoundTripThroughCompositeKey() {
        let baseURL = VaultClient.buildBaseURL(host: "vault.example.com", port: "8200")!
        let mount = "oidc"
        let credPath = "database/creds/readonly"
        let key = VaultAuthManager.cacheKey(baseURL: baseURL, oidcMount: mount, credPath: credPath)

        VaultAuthManager.setCachedCredentials(username: "db-user", password: "db-pass",
                                              leaseDuration: 3600, for: key)

        let hit = VaultAuthManager.cachedCredentials(for: key)
        XCTAssertEqual(hit?.username, "db-user")
        XCTAssertEqual(hit?.password, "db-pass")

        // A key built with different inputs must not collide.
        let otherKey = VaultAuthManager.cacheKey(baseURL: baseURL, oidcMount: mount, credPath: "database/creds/admin")
        XCTAssertNil(VaultAuthManager.cachedCredentials(for: otherKey),
                     "Different credPath must not hit the same cache entry")
    }

    func testCacheIsInvalidatedWhenTokenChanges() {
        VaultAuthManager.setCachedCredentials(username: "u1", password: "p1", leaseDuration: 3600, token: "old-token", for: "path/a")

        // Same token — cache hit expected.
        let hit = VaultAuthManager.cachedCredentials(for: "path/a", matchingToken: "old-token")
        XCTAssertNotNil(hit, "Cache should hit when the token matches")

        // Different token — entry must be evicted.
        let miss = VaultAuthManager.cachedCredentials(for: "path/a", matchingToken: "new-token")
        XCTAssertNil(miss, "Cache must be invalidated when the Vault token changes to a different identity")

        // Entry should now be gone from the cache entirely.
        let gone = VaultAuthManager.cachedCredentials(for: "path/a")
        XCTAssertNil(gone, "Evicted entry must not be accessible even without a token check")
    }

    // MARK: - isLoginCancellation

    // Lets the role-refresh completion stay silent for an expected abort (declined
    // browser confirmation, Vault-tab exit, document teardown) instead of alerting.
    private static let vaultErrorDomain = "VaultAuthErrorDomain"

    func testIsLoginCancellationRecognizesCancelledError() {
        let error = NSError(domain: Self.vaultErrorDomain,
                            code: VaultAuthError.loginCancelled.rawValue, userInfo: nil)
        XCTAssertTrue(VaultAuthManager.isLoginCancellation(error))
    }

    func testIsLoginCancellationRejectsOtherErrorCodes() {
        for code in [VaultAuthError.loginFailed, .credentialsFailed, .invalidConfiguration] {
            let error = NSError(domain: Self.vaultErrorDomain, code: code.rawValue, userInfo: nil)
            XCTAssertFalse(VaultAuthManager.isLoginCancellation(error), "code \(code.rawValue) is not a cancellation")
        }
    }

    func testIsLoginCancellationRejectsOtherDomainAndNil() {
        let foreign = NSError(domain: "SomeOtherDomain",
                              code: VaultAuthError.loginCancelled.rawValue, userInfo: nil)
        XCTAssertFalse(VaultAuthManager.isLoginCancellation(foreign))
        XCTAssertFalse(VaultAuthManager.isLoginCancellation(nil))
    }
}
