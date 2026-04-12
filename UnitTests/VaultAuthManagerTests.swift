//  VaultAuthManagerTests.swift
//  Sequel Ace

import XCTest

final class VaultAuthManagerTests: XCTestCase {

    // MARK: - Credential cache

    func testCredentialCacheReturnsCachedEntryBeforeExpiry() {
        VaultAuthManager.clearCachedCredentials(for: nil)

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
        VaultAuthManager.clearCachedCredentials(for: nil)
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
        VaultAuthManager.clearCachedCredentials(for: nil)
        VaultAuthManager.setCachedCredentials(username: "u1", password: "p1", leaseDuration: 3600, for: "path/a")
        VaultAuthManager.setCachedCredentials(username: "u2", password: "p2", leaseDuration: 3600, for: "path/b")

        VaultAuthManager.clearCachedCredentials(for: "path/a")

        XCTAssertNil(VaultAuthManager.cachedCredentials(for: "path/a"))
        XCTAssertNotNil(VaultAuthManager.cachedCredentials(for: "path/b"))
    }

    func testClearAllCachedCredentials() {
        VaultAuthManager.clearCachedCredentials(for: nil)
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

        let key1 = VaultAuthManager.cacheKey(baseURL: url1, credPath: credPath)
        let key2 = VaultAuthManager.cacheKey(baseURL: url2, credPath: credPath)

        XCTAssertNotEqual(key1, key2, "Two different Vault servers must produce different cache keys even with the same credPath")
    }

    func testCacheDoesNotCrossContaminateBetweenHosts() {
        VaultAuthManager.clearCachedCredentials(for: nil)

        let url1 = VaultClient.buildBaseURL(host: "vault-prod.example.com", port: "443")!
        let url2 = VaultClient.buildBaseURL(host: "vault-staging.example.com", port: "443")!
        let credPath = "databases_credentials/creds/readonly"

        VaultAuthManager.setCachedCredentials(username: "prod-user", password: "prod-pass",
                                              leaseDuration: 3600,
                                              for: VaultAuthManager.cacheKey(baseURL: url1, credPath: credPath))

        let hit = VaultAuthManager.cachedCredentials(for: VaultAuthManager.cacheKey(baseURL: url1, credPath: credPath))
        let miss = VaultAuthManager.cachedCredentials(for: VaultAuthManager.cacheKey(baseURL: url2, credPath: credPath))

        XCTAssertEqual(hit?.username, "prod-user")
        XCTAssertNil(miss, "Staging server must not see prod credentials")
    }

    func testExpiredCacheEntryIsNotReturned() {
        VaultAuthManager.clearCachedCredentials(for: nil)
        // Set with 0 second lease — expires immediately
        VaultAuthManager.setCachedCredentials(username: "u1", password: "p1", leaseDuration: 0, for: "path/expired")
        // Tiny lease = already expired (margin is 30s, so 0 < 30 means expired)
        let result = VaultAuthManager.cachedCredentials(for: "path/expired")
        XCTAssertNil(result, "Zero-duration lease should not be returned from cache")
    }
}
