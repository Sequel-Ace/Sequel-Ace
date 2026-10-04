//
//  SAKeychainDisabledTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on August 31, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//

import XCTest

/// The disabled-mode null object: no-ops, nils and false everywhere — never
/// a crash, never a stored secret. (The semantics mirror what Objective-C
/// callers historically got from messaging the retired SPKeychain's nil
/// disabled-mode instance.)
final class SAKeychainDisabledTests: XCTestCase {

    private let store: SAKeychainProviding = SAKeychainDisabled()

    func testStoreOperationsAreInertAndNeverFind() {
        store.add(password: "pw", name: "name", account: "account")
        store.add(password: "pw", name: "name", account: "account", label: "label")
        XCTAssertNil(store.password(name: "name", account: "account"))
        XCTAssertFalse(store.passwordExists(name: "name", account: "account"))
        store.updateItem(name: "name", account: "account",
                         toName: "new", newAccount: "new", password: "pw")
        store.deletePassword(name: "name", account: "account")
        XCTAssertNil(store.password(name: "new", account: "new"))
    }

    func testNamingHelpersReturnNil() {
        XCTAssertNil(store.name(favoriteName: "F", id: "1"))
        XCTAssertNil(store.account(user: "u", host: "h", database: "d"))
        XCTAssertNil(store.sshName(favoriteName: "F", id: "1"))
        XCTAssertNil(store.sshAccount(user: "u", host: "h"))
    }

    func testNilArgumentsAreAccepted() {
        store.add(password: nil, name: nil, account: nil)
        XCTAssertNil(store.password(name: nil, account: nil))
        XCTAssertFalse(store.passwordExists(name: nil, account: nil))
    }
}
