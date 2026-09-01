//
//  SAKeychainNamingCharacterizationTests.swift
//  Unit Tests
//
//  Created by the Sequel Ace team on August 31, 2026.
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//
//  Step 1 of docs/development/keychain-secitem-migration-plan.md: pin the
//  four keychain name/account format strings byte-exactly. These formats are
//  the keychain wire format — they are persisted in every user's login
//  keychain, and `.spf` documents store the resulting strings verbatim — so
//  any drift silently orphans saved passwords. Characterized off the legacy
//  SPKeychain in Step 1; SAKeychain (via SAKeychainNaming) reproduces every
//  assertion unchanged.
//

import XCTest

final class SAKeychainNamingCharacterizationTests: SAKeychainCharacterizationTestCase {

    override var needsKeychainAccess: Bool { false }

    // MARK: - nameForFavoriteName:id:

    func testFavoriteNameFormatsNameAndNumericID() {
        XCTAssertEqual(store.name(favoriteName: "Prod DB", id: "12345"),
                       "Sequel Ace : Prod DB (12345)")
    }

    func testFavoriteNameCoercesIDThroughLongLong() {
        // The id goes through -longLongValue: non-numeric strings become 0,
        // numeric prefixes are taken as far as they parse, and 64-bit values
        // survive. Changing any of this would orphan existing items.
        XCTAssertEqual(store.name(favoriteName: "F", id: "abc"), "Sequel Ace : F (0)")
        XCTAssertEqual(store.name(favoriteName: "F", id: ""), "Sequel Ace : F (0)")
        XCTAssertEqual(store.name(favoriteName: "F", id: "42abc"), "Sequel Ace : F (42)")
        XCTAssertEqual(store.name(favoriteName: "F", id: "-3"), "Sequel Ace : F (-3)")
        XCTAssertEqual(store.name(favoriteName: "F", id: "9223372036854775807"),
                       "Sequel Ace : F (9223372036854775807)")
    }

    func testFavoriteNameAcceptsTheFavoritesDictionaryNSNumberID() {
        // Objective-C call sites pass [favorite objectForKey:SPFavoriteIDKey]
        // — an NSNumber — straight through the (id)-typed parameter; the
        // legacy implementation coerced it with -longLongValue. Declaring
        // the parameter String? crashed the very first favorite selection
        // in the running app (caught by the Step 5 manual matrix, not by
        // this suite — which is why these tests exist now).
        XCTAssertEqual(store.name(favoriteName: "localhost", id: NSNumber(value: 5185933460730047640)),
                       "Sequel Ace : localhost (5185933460730047640)")
        XCTAssertEqual(store.name(favoriteName: "F", id: 42), "Sequel Ace : F (42)")
    }

    func testFavoriteNameRejectsUnsupportedIDTypes() {
        // The legacy code would have thrown unrecognized-selector here;
        // nothing passes such types, and the Swift store refuses instead.
        XCTAssertNil(store.name(favoriteName: "F", id: [1, 2]))
    }

    func testFavoriteNameRejectsMissingInputs() {
        XCTAssertNil(store.name(favoriteName: nil, id: "1"))
        XCTAssertNil(store.name(favoriteName: "", id: "1"))
        XCTAssertNil(store.name(favoriteName: "F", id: nil))
    }

    func testFavoriteNamePassesNameThroughLiterally() {
        // Names containing format-looking characters are not re-interpreted.
        XCTAssertEqual(store.name(favoriteName: "100% weird %@ name", id: "7"),
                       "Sequel Ace : 100% weird %@ name (7)")
    }

    // MARK: - accountForUser:host:database:

    func testAccountFormatsUserHostDatabase() {
        XCTAssertEqual(store.account(user: "user", host: "db.example.com", database: "shop"),
                       "user@db.example.com/shop")
    }

    func testAccountNilOrEmptyDatabaseYieldsTrailingSlash() {
        XCTAssertEqual(store.account(user: "user", host: "host", database: nil), "user@host/")
        XCTAssertEqual(store.account(user: "user", host: "host", database: ""), "user@host/")
    }

    func testAccountRejectsMissingUserOrHost() {
        XCTAssertNil(store.account(user: nil, host: "host", database: "db"))
        XCTAssertNil(store.account(user: "", host: "host", database: "db"))
        XCTAssertNil(store.account(user: "user", host: nil, database: "db"))
        XCTAssertNil(store.account(user: "user", host: "", database: "db"))
    }

    // MARK: - nameForSSHForFavoriteName:id:

    func testSSHNameFormatsNameAndNumericID() {
        XCTAssertEqual(store.sshName(favoriteName: "Prod DB", id: "12345"),
                       "Sequel Ace SSHTunnel : Prod DB (12345)")
    }

    func testSSHNameCoercesIDThroughLongLong() {
        XCTAssertEqual(store.sshName(favoriteName: "F", id: "abc"),
                       "Sequel Ace SSHTunnel : F (0)")
    }

    func testSSHNameAcceptsTheFavoritesDictionaryNSNumberID() {
        XCTAssertEqual(store.sshName(favoriteName: "intranet-EC2", id: NSNumber(value: 971684326597382539)),
                       "Sequel Ace SSHTunnel : intranet-EC2 (971684326597382539)")
    }

    func testSSHNameRejectsMissingInputs() {
        XCTAssertNil(store.sshName(favoriteName: nil, id: "1"))
        XCTAssertNil(store.sshName(favoriteName: "", id: "1"))
        XCTAssertNil(store.sshName(favoriteName: "F", id: nil))
    }

    // MARK: - accountForSSHUser:sshHost:

    func testSSHAccountFormatsUserAndHost() {
        XCTAssertEqual(store.sshAccount(user: "tunneluser", host: "bastion.example.com"),
                       "tunneluser@bastion.example.com")
    }

    func testSSHAccountRejectsMissingUserOrHost() {
        XCTAssertNil(store.sshAccount(user: nil, host: "host"))
        XCTAssertNil(store.sshAccount(user: "", host: "host"))
        XCTAssertNil(store.sshAccount(user: "user", host: nil))
        XCTAssertNil(store.sshAccount(user: "user", host: ""))
    }

    // MARK: - Unicode

    func testFormatsPreserveUnicode() {
        XCTAssertEqual(store.name(favoriteName: "Datenbänk 🗄️", id: "9"),
                       "Sequel Ace : Datenbänk 🗄️ (9)")
        XCTAssertEqual(store.account(user: "üser", host: "høst", database: "database名"),
                       "üser@høst/database名")
    }
}
