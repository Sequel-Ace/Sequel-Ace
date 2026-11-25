//
//  SARegistrationDomainSnapshotTests.swift
//  Unit Tests
//
//  UserDefaults.register(defaults:) writes the process-wide registration
//  domain, even when called on a suite instance, so registrations made by one
//  test class leak into every later one. Test classes that register take a
//  snapshot in setUp and restore it in tearDown.
//

import Foundation
import XCTest

/// A copy of the process-wide registration domain that can be put back.
struct SARegistrationDomainSnapshot {

    private let saved: [String: Any]

    init() {
        saved = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
    }

    /// Replaces the registration domain with the snapshot: overwritten keys get
    /// their old values back and keys registered since are dropped.
    func restore() {
        UserDefaults.standard.setVolatileDomain(saved, forName: UserDefaults.registrationDomain)
    }
}

final class SARegistrationDomainSnapshotTests: XCTestCase {

    private let added = "SARegistrationDomainSnapshotTests.added"
    private let changed = "SARegistrationDomainSnapshotTests.changed"
    private var outer: SARegistrationDomainSnapshot!

    override func setUp() { outer = SARegistrationDomainSnapshot() }
    override func tearDown() { outer.restore() }

    /// Verifies a restore drops keys registered since and reverts overwritten ones,
    /// including registrations made through a suite instance.
    func testRestoreUndoesRegistrations() {
        UserDefaults.standard.register(defaults: [changed: "before"])
        let snapshot = SARegistrationDomainSnapshot()

        let suite = UserDefaults(suiteName: "SARegistrationDomainSnapshotTests")!
        suite.register(defaults: [added: true, changed: "after"])
        XCTAssertEqual(UserDefaults.standard.string(forKey: changed), "after", "registration is process-wide")
        XCTAssertNotNil(UserDefaults.standard.object(forKey: added))

        snapshot.restore()
        XCTAssertNil(UserDefaults.standard.object(forKey: added))
        XCTAssertNil(suite.object(forKey: added))
        XCTAssertEqual(UserDefaults.standard.string(forKey: changed), "before")
        XCTAssertEqual(suite.string(forKey: changed), "before")
    }
}
