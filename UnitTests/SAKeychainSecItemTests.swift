//
//  SAKeychainSecItemTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on August 31, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//
//  Step 4 of docs/development/keychain-secitem-migration-plan.md: the proof
//  obligations for the SecItem* rewrite. The two subclasses rerun the entire
//  characterization suites against SAKeychain (identical behaviour to the
//  legacy store), and the cross-compatibility suite is what turns "zero data
//  migration" from a hope into a verified claim: items written by the legacy
//  SecKeychain* code are found, read, updated and deleted by SAKeychain —
//  simulating every existing user item on upgrade — and the reverse proves
//  downgrade safety.
//

import XCTest

// MARK: - Characterization suite reruns

/// Every store characterization test, run against SAKeychain.
final class SAKeychainSecItemStoreTests: SAKeychainStoreCharacterizationTests {
    override func makeStore() -> SAKeychainProviding? { SAKeychain() }
}

/// Every naming characterization test, run against SAKeychain.
final class SAKeychainSecItemNamingTests: SAKeychainNamingCharacterizationTests {
    override func makeStore() -> SAKeychainProviding? { SAKeychain() }
}

// MARK: - Cross-implementation matrix

final class SAKeychainCrossCompatibilityTests: SAKeychainCharacterizationTestCase {

    /// `store` (from the base class) is the legacy SPKeychain; this is the
    /// SecItem* implementation.
    private var modern: SAKeychainProviding!

    override func setUpWithError() throws {
        try super.setUpWithError()
        modern = SAKeychain()
    }

    private func service(_ label: String, _ function: StaticString = #function) -> String {
        SAKeychainTestSupport.service("\(function) \(label)")
    }

    // MARK: Legacy writes → modern reads (every existing user item on upgrade)

    func testLegacyWrittenItemIsReadByModern() {
        let name = service("item"), account = "user@host/db"
        store.add(password: "legacy-pw", name: name, account: account)
        XCTAssertTrue(modern.passwordExists(name: name, account: account))
        XCTAssertEqual(modern.password(name: name, account: account), "legacy-pw")
    }

    func testLegacyWrittenUnicodeItemIsReadByModern() {
        let name = service("Ünïcode 名前"), account = "üser@høst/db名"
        store.add(password: "pässwörd-🔑", name: name, account: account)
        XCTAssertEqual(modern.password(name: name, account: account), "pässwörd-🔑")
    }

    func testLegacyWrittenItemIsUpdatedInPlaceByModern() {
        let oldName = service("old"), newName = service("new")
        store.add(password: "pw-1", name: oldName, account: "a@h/")
        modern.updateItem(name: oldName, account: "a@h/",
                          toName: newName, newAccount: "b@h/", password: "pw-2")

        // Both implementations agree on the outcome.
        XCTAssertEqual(modern.password(name: newName, account: "b@h/"), "pw-2")
        XCTAssertEqual(store.password(name: newName, account: "b@h/"), "pw-2")
        XCTAssertFalse(store.passwordExists(name: oldName, account: "a@h/"))
    }

    func testLegacyWrittenItemIsDeletedByModern() {
        let name = service("item"), account = "user@host/"
        store.add(password: "pw", name: name, account: account)
        modern.deletePassword(name: name, account: account)
        XCTAssertFalse(store.passwordExists(name: name, account: account))
    }

    func testModernAddIsANoOpWhenALegacyItemExists() {
        // Upgrade scenario: the user re-saves a favorite whose password the
        // legacy build already stored — the add must not clobber it.
        let name = service("item"), account = "user@host/"
        store.add(password: "original", name: name, account: account)
        modern.add(password: "replacement", name: name, account: account)
        XCTAssertEqual(modern.password(name: name, account: account), "original")
    }

    // MARK: Modern writes → legacy reads (downgrade safety)

    func testModernWrittenItemIsReadByLegacy() {
        let name = service("item"), account = "user@host/db"
        modern.add(password: "modern-pw", name: name, account: account)
        XCTAssertTrue(store.passwordExists(name: name, account: account))
        XCTAssertEqual(store.password(name: name, account: account), "modern-pw")
    }

    func testModernWrittenItemIsUpdatedByLegacy() {
        let name = service("item"), account = "user@host/"
        modern.add(password: "pw-1", name: name, account: account)
        store.updateItem(name: name, account: account,
                         toName: name, newAccount: account, password: "pw-2")
        XCTAssertEqual(modern.password(name: name, account: account), "pw-2")
    }

    // MARK: Persisted item shape

    func testPersistedItemShapeMatchesFieldForField() throws {
        let account = "user@host/db"
        let legacyName = service("written by legacy")
        let modernName = service("written by modern")

        store.add(password: "pw", name: legacyName, account: account)
        modern.add(password: "pw", name: modernName, account: account)

        let legacyAttrs = try XCTUnwrap(SAKeychainTestSupport.attributes(service: legacyName, account: account))
        let modernAttrs = try XCTUnwrap(SAKeychainTestSupport.attributes(service: modernName, account: account))

        // The attributes both implementations set, value for value.
        XCTAssertEqual(modernAttrs[kSecAttrAccount as String] as? String,
                       legacyAttrs[kSecAttrAccount as String] as? String)
        XCTAssertEqual(modernAttrs[kSecAttrLabel as String] as? String, modernName)
        XCTAssertEqual(legacyAttrs[kSecAttrLabel as String] as? String, legacyName)
        XCTAssertEqual(modernAttrs[kSecAttrGeneric as String] as? Data,
                       legacyAttrs[kSecAttrGeneric as String] as? Data)

        // And the overall attribute key sets match, so the modern writer
        // neither drops nor invents fields (the risk here is omission —
        // volatile per-item values are excluded).
        let volatile: Set<String> = [
            kSecAttrCreationDate as String,
            kSecAttrModificationDate as String,
            kSecAttrService as String,
        ]
        XCTAssertEqual(Set(modernAttrs.keys).subtracting(volatile),
                       Set(legacyAttrs.keys).subtracting(volatile))
    }
}
