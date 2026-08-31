//
//  SAKeychainStoreCharacterizationTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on August 31, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//
//  Step 1 of docs/development/keychain-secitem-migration-plan.md: pin the
//  legacy SPKeychain store behaviour exactly as it is — recovery branches,
//  quirks and defects included. Where a pinned behaviour is a defect, the
//  test says so and names the Step 2 fix that will flip it.
//
//  Every item is created under the SAKeychainTestSupport namespace against
//  the real login keychain (see that file for the isolation story). The
//  suite deliberately never drives SPKeychain's failure paths: those run
//  modal NSAlerts, which would hang the runner (migration plan, defect 4).
//

import XCTest

final class SAKeychainStoreCharacterizationTests: SAKeychainCharacterizationTestCase {

    private func service(_ label: String, _ function: StaticString = #function) -> String {
        SAKeychainTestSupport.service("\(function) \(label)")
    }

    // MARK: - Basic CRUD

    func testAddThenGetRoundTrips() {
        let name = service("item"), account = "user@host/db"
        store.add(password: "secret-123", name: name, account: account)
        XCTAssertEqual(store.password(name: name, account: account), "secret-123")
    }

    func testGetForMissingItemReturnsNil() {
        XCTAssertNil(store.password(name: service("never created"), account: "user@host/"))
    }

    func testPasswordExistsReflectsPresence() {
        let name = service("item"), account = "user@host/"
        XCTAssertFalse(store.passwordExists(name: name, account: account))
        store.add(password: "pw", name: name, account: account)
        XCTAssertTrue(store.passwordExists(name: name, account: account))
    }

    func testExistsDistinguishesAccounts() {
        let name = service("item")
        store.add(password: "pw", name: name, account: "a@h/")
        XCTAssertFalse(store.passwordExists(name: name, account: "b@h/"))
        XCTAssertNil(store.password(name: name, account: "b@h/"))
    }

    func testDeleteRemovesItem() {
        let name = service("item"), account = "user@host/"
        store.add(password: "pw", name: name, account: account)
        store.deletePassword(name: name, account: account)
        XCTAssertFalse(store.passwordExists(name: name, account: account))
        XCTAssertNil(store.password(name: name, account: account))
    }

    func testDeleteForMissingItemIsANoOp() {
        store.deletePassword(name: service("never created"), account: "user@host/")
    }

    func testAddWhenItemExistsIsASilentNoOp() {
        // Callers rely on this: SPConnectionController branches on
        // passwordExists and routes changes through the update path.
        let name = service("item"), account = "user@host/"
        store.add(password: "first", name: name, account: account)
        store.add(password: "second", name: name, account: account)
        XCTAssertEqual(store.password(name: name, account: account), "first")
    }

    // MARK: - Persisted item shape

    func testAddStoresServiceAccountLabelAndGenericAttribute() throws {
        let name = service("item"), account = "user@host/db"
        store.add(password: "pw", name: name, account: account)

        let attrs = try XCTUnwrap(SAKeychainTestSupport.attributes(service: name, account: account))
        XCTAssertEqual(attrs[kSecAttrService as String] as? String, name)
        XCTAssertEqual(attrs[kSecAttrAccount as String] as? String, account)
        // The three-argument add defaults the label to the name.
        XCTAssertEqual(attrs[kSecAttrLabel as String] as? String, name)
        // kSecGenericItemAttr carries the literal "application password"
        // (SPKeychain.m hardcodes the 20-byte string).
        let generic = try XCTUnwrap(attrs[kSecAttrGeneric as String] as? Data)
        XCTAssertEqual(String(data: generic, encoding: .utf8), "application password")
    }

    func testAddWithExplicitLabelStoresIt() throws {
        let name = service("item"), account = "user@host/"
        store.add(password: "pw", name: name, account: account, label: "Custom Label")
        let attrs = try XCTUnwrap(SAKeychainTestSupport.attributes(service: name, account: account))
        XCTAssertEqual(attrs[kSecAttrLabel as String] as? String, "Custom Label")
    }

    // MARK: - Payload edge cases

    func testUnicodePasswordRoundTrips() {
        let name = service("item"), account = "user@host/"
        let password = "pässwörd-🔑-密码"
        store.add(password: password, name: name, account: account)
        XCTAssertEqual(store.password(name: name, account: account), password)
    }

    func testUnicodeServiceAndAccountRoundTrip() {
        let name = service("Ünïcode 名前"), account = "üser@høst/db名"
        store.add(password: "pw", name: name, account: account)
        XCTAssertEqual(store.password(name: name, account: account), "pw")
        XCTAssertTrue(store.passwordExists(name: name, account: account))
    }

    func testEmptyPasswordRoundTripsAsEmptyString() {
        let name = service("item"), account = "user@host/"
        store.add(password: "", name: name, account: account)
        XCTAssertTrue(store.passwordExists(name: name, account: account))
        XCTAssertEqual(store.password(name: name, account: account), "")
    }

    func testLongPasswordRoundTrips() {
        let name = service("item"), account = "user@host/"
        let password = String(repeating: "x", count: 4096)
        store.add(password: password, name: name, account: account)
        XCTAssertEqual(store.password(name: name, account: account), password)
    }

    // MARK: - nil / empty argument handling

    func testNilAndEmptyArgumentsAreRejectedWithoutCrashing() {
        let name = service("item")
        store.add(password: "pw", name: nil, account: "a")
        store.add(password: "pw", name: name, account: nil)
        store.add(password: "pw", name: "", account: "a")
        store.add(password: nil, name: name, account: "a")
        XCTAssertFalse(store.passwordExists(name: name, account: "a"))

        XCTAssertNil(store.password(name: nil, account: "a"))
        XCTAssertNil(store.password(name: name, account: nil))
        XCTAssertFalse(store.passwordExists(name: nil, account: "a"))
        store.deletePassword(name: nil, account: "a")
        store.updateItem(name: nil, account: "a", toName: "b", newAccount: "c", password: "pw")
    }

    // MARK: - Five-argument update

    func testUpdateRenamesItemAndReplacesPassword() {
        let oldName = service("old"), newName = service("new")
        store.add(password: "pw-1", name: oldName, account: "old@host/")
        store.updateItem(name: oldName, account: "old@host/",
                         toName: newName, newAccount: "new@host/", password: "pw-2")

        XCTAssertFalse(store.passwordExists(name: oldName, account: "old@host/"))
        XCTAssertEqual(store.password(name: newName, account: "new@host/"), "pw-2")
    }

    func testUpdateLeavesLabelBehindOnRename() throws {
        // Quirk: the update path modifies only service, account and secret —
        // the label keeps the pre-rename favorite name, which is what users
        // see in Keychain Access. Pinned so the SecItem* implementation
        // reproduces it (changing it is a Step 4 review decision, not an
        // accident).
        let oldName = service("old"), newName = service("new")
        store.add(password: "pw", name: oldName, account: "a@h/")
        store.updateItem(name: oldName, account: "a@h/",
                         toName: newName, newAccount: "a@h/", password: "pw")
        let attrs = try XCTUnwrap(SAKeychainTestSupport.attributes(service: newName, account: "a@h/"))
        XCTAssertEqual(attrs[kSecAttrLabel as String] as? String, oldName)
    }

    func testUpdateWithSameNameAndAccountReplacesPasswordOnly() {
        let name = service("item"), account = "user@host/"
        store.add(password: "pw-1", name: name, account: account)
        store.updateItem(name: name, account: account,
                         toName: name, newAccount: account, password: "pw-2")
        XCTAssertEqual(store.password(name: name, account: account), "pw-2")
    }

    func testUpdateOfMissingItemFallsBackToAdd() {
        // The errSecItemNotFound (-25300) branch: a safe delete, then a
        // fresh add under the *new* name and account.
        let oldName = service("never existed"), newName = service("created by update")
        store.updateItem(name: oldName, account: "old@host/",
                         toName: newName, newAccount: "new@host/", password: "pw")
        XCTAssertEqual(store.password(name: newName, account: "new@host/"), "pw")
        XCTAssertFalse(store.passwordExists(name: oldName, account: "old@host/"))
    }

    func testUpdateWithNilPasswordLeavesItemUntouched() {
        // Fixed in Step 2 (defect 2): a nil password used to reach
        // strlen(NULL). Now the update is rejected and the item is left
        // exactly as it was.
        let name = service("item"), account = "user@host/"
        store.add(password: "pw-1", name: name, account: account)
        store.updateItem(name: name, account: account,
                         toName: service("renamed"), newAccount: "new@host/", password: nil)
        XCTAssertEqual(store.password(name: name, account: account), "pw-1")
        XCTAssertFalse(store.passwordExists(name: service("renamed"), account: "new@host/"))
    }

    func testUpdateOntoExistingDestinationReplacesIt() {
        // The errSecDuplicateItem (-25299) branch: the existing destination
        // item is deleted and the update retried, so the source item wins.
        let source = service("source"), destination = service("destination")
        store.add(password: "source-pw", name: source, account: "s@h/")
        store.add(password: "old-destination-pw", name: destination, account: "d@h/")

        store.updateItem(name: source, account: "s@h/",
                         toName: destination, newAccount: "d@h/", password: "moved-pw")

        XCTAssertEqual(store.password(name: destination, account: "d@h/"), "moved-pw")
        XCTAssertFalse(store.passwordExists(name: source, account: "s@h/"))
    }

}
