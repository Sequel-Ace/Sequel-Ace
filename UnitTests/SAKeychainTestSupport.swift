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
    /// it is what the sweep matches on.
    static let testServicePrefix = "Sequel Ace Test"

    /// Per-run token so concurrent/consecutive runs cannot see each other's
    /// items even before the sweep runs.
    static let runToken: String = String(UUID().uuidString.prefix(8))

    /// A namespaced service name for one test's item.
    static func service(_ label: String) -> String {
        "\(testServicePrefix) \(runToken) : \(label)"
    }

    /// True when the login keychain accepts a write + read-back + delete from
    /// this process. Uses raw SecItem* calls (never the store under test) so
    /// a locked keychain surfaces as a status code here rather than as the
    /// store's modal error alert hanging the test runner.
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

    /// Raw secret read, independent of the store under test.
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

/// Shared setup for suites that construct the keychain store: the env-guard
/// and keychain-availability skips, the namespace sweep, and the store
/// itself. `makeStore()` stays overridable so the identical behaviour tests
/// can run against any future alternative implementation, exactly as they
/// ran against both SPKeychain and SAKeychain while the migration's
/// cross-compatibility matrix was live (Steps 1–5 of the plan).
class SAKeychainCharacterizationTestCase: XCTestCase {

    private static var probeResult: Bool?

    var store: SAKeychainProviding!

    /// Whether this suite touches the keychain (store CRUD) or only the pure
    /// naming helpers. Naming-only suites skip the availability probe.
    var needsKeychainAccess: Bool { true }

    func makeStore() -> SAKeychainProviding? {
        SAKeychain()
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
        // In production this env var makes SAKeychainAccess.make() hand out
        // the SAKeychainDisabled null object (issue #2437) — keychain access
        // is disabled wholesale, so exercising the real store here would not
        // reflect the running configuration.
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
