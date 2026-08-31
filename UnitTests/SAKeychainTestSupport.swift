//
//  SAKeychainTestSupport.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on August 31, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//
//  Test harness for keychain-touching tests — Step 0 of
//  docs/development/keychain-secitem-migration-plan.md.
//
//  The suites run against the real login keychain of the machine, under a
//  unique per-run namespace: every service name is prefixed
//  "Sequel Ace Test <token> : " so nothing can collide with real user items,
//  and the sweep deletes every "Sequel Ace Test" item — including leftovers
//  from aborted earlier runs. Items created by the test process itself read
//  back without ACL prompts, so the suites are prompt-free; on machines where
//  the login keychain is locked or unavailable (some SSH sessions, hardened
//  CI), the probe fails and the store suites skip.
//

import Foundation
import Security
import XCTest

enum SAKeychainTestSupport {

    /// Every keychain item any test creates must carry this service prefix —
    /// it is what the sweep matches on. The fixed random token makes the
    /// namespace collision-proof: the sweep deletes every matching item
    /// (aborted-run leftovers included), so the prefix must be one nothing
    /// else could plausibly use.
    static let testServicePrefix = "Sequel Ace Unit Test 8C41F2D6"

    /// Per-run token so concurrent/consecutive runs cannot see each other's
    /// items even before the sweep runs.
    static let runToken: String = String(UUID().uuidString.prefix(8))

    /// A namespaced service name for one test's item.
    static func service(_ label: String) -> String {
        "\(testServicePrefix) \(runToken) : \(label)"
    }

    /// The legacy SPKeychain, reached via the runtime because the Unit Tests
    /// target has no Objective-C bridging header (see "Test-target ObjC
    /// visibility — known sharp edge" in the modernization plan). SPKeychain
    /// declares SAKeychainProviding conformance in its .m, so the cast is a
    /// real runtime conformance check, not a bit-cast.
    static func makeLegacyStore() -> SAKeychainProviding? {
        guard let cls = NSClassFromString("SPKeychain") as? NSObject.Type else { return nil }
        return cls.init() as? SAKeychainProviding
    }

    /// True when the login keychain accepts a write + read-back + delete from
    /// this process. Uses raw SecItem* calls (never SPKeychain) so a locked
    /// keychain surfaces as a status code here rather than as SPKeychain's
    /// modal error alert hanging the test runner.
    static func probeKeychainUsable() -> Bool {
        let probeService = service("availability probe")
        let probeAccount = "probe@probe/probe"
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probeService,
            kSecAttrAccount as String: probeAccount,
            kSecValueData as String: Data("probe".utf8),
        ]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return false }
        defer { deleteItem(service: probeService, account: probeAccount) }
        return passwordData(service: probeService, account: probeAccount) == Data("probe".utf8)
    }

    /// Raw attribute read for asserting the persisted item shape.
    static func attributes(service: String, account: String) -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? [String: Any]
    }

    /// Raw secret read, bypassing SPKeychain's C-string round-trip.
    static func passwordData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func deleteItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Deletes every generic-password item whose service starts with the test
    /// prefix — this run's items and any leftovers from aborted runs. Reads
    /// only attributes (never secrets), so it cannot prompt.
    static func sweepTestItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return }
        for item in items {
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix(testServicePrefix) else { continue }
            if let account = item[kSecAttrAccount as String] as? String {
                deleteItem(service: service, account: account)
            }
        }
    }
}

/// Shared setup for suites that construct the legacy store: the env-guard and
/// keychain-availability skips, the namespace sweep, and the store itself.
/// Subclassed rather than parameterized so the identical characterization
/// tests can later run against the SecItem* implementation by overriding
/// `makeStore()` (the migration plan's cross-compatibility matrix).
class SAKeychainCharacterizationTestCase: XCTestCase {

    private static var probeResult: Bool?

    var store: SAKeychainProviding!

    /// Whether this suite touches the keychain (store CRUD) or only the pure
    /// naming helpers. Naming-only suites skip the availability probe.
    var needsKeychainAccess: Bool { true }

    func makeStore() -> SAKeychainProviding? {
        SAKeychainTestSupport.makeLegacyStore()
    }

    override class func setUp() {
        super.setUp()
        SAKeychainTestSupport.sweepTestItems()
    }

    override class func tearDown() {
        SAKeychainTestSupport.sweepTestItems()
        super.tearDown()
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // SPKeychain's init returns nil under this env var (issue #2437), so
        // no store can be constructed at all. The guard itself is
        // characterized in the migration plan as defect 3 (the nil init is a
        // trap for Swift callers) and gets a proper testable seam in Step 2;
        // NSProcessInfo caches the environment, so flipping the variable
        // in-process would not be deterministic enough to pin here.
        if ProcessInfo.processInfo.environment["LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN"] != nil {
            throw XCTSkip("keychain access is disabled while LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN is set")
        }
        if needsKeychainAccess {
            if Self.probeResult == nil {
                Self.probeResult = SAKeychainTestSupport.probeKeychainUsable()
            }
            guard Self.probeResult == true else {
                throw XCTSkip("login keychain is locked or unavailable on this machine")
            }
        }
        store = try XCTUnwrap(
            makeStore(),
            "keychain store missing — is the implementation compiled into the Unit Tests target and conforming to SAKeychainProviding?"
        )
    }
}
