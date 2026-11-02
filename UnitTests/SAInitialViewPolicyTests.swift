//
//  SAInitialViewPolicyTests.swift
//  Unit Tests
//

import XCTest

final class SAInitialViewPolicyTests: XCTestCase {

    private typealias P = SAInitialViewPolicy

    func testOpensOnQueryWhenNoTableIsSelected() {
        XCTAssertEqual(P.initialMode(preferred: .content, hasTable: false), .query)
        XCTAssertEqual(P.initialMode(preferred: .structure, hasTable: false), .query)
    }

    func testKeepsThePreferredModeWhenATableIsSelected() {
        XCTAssertEqual(P.initialMode(preferred: .content, hasTable: true), .content)
        XCTAssertEqual(P.initialMode(preferred: .query, hasTable: true), .query)
    }

    func testPreferredQueryStaysQueryWithoutATable() {
        XCTAssertEqual(P.initialMode(preferred: .query, hasTable: false), .query)
    }

    func testPreferredModeFollowsThePreferencesValue() {
        XCTAssertEqual(P.preferredMode(forPreferencesValue: 1), .structure)
        XCTAssertEqual(P.preferredMode(forPreferencesValue: 2), .content)
        XCTAssertEqual(P.preferredMode(forPreferencesValue: 5), .query)
        XCTAssertEqual(P.preferredMode(forPreferencesValue: 0), .structure)
    }

    func testJumpsForATableOrViewWhilePendingOnQuery() {
        XCTAssertTrue(P.shouldJump(pending: true, selectedType: 0, currentIsQuery: true))
        XCTAssertTrue(P.shouldJump(pending: true, selectedType: 1, currentIsQuery: true))
    }

    func testDoesNotJumpWhenNothingIsPending() {
        XCTAssertFalse(P.shouldJump(pending: false, selectedType: 0, currentIsQuery: true))
    }

    func testDoesNotJumpWhenTheUserLeftQuery() {
        XCTAssertFalse(P.shouldJump(pending: true, selectedType: 0, currentIsQuery: false))
    }

    func testProceduresFunctionsAndEventsDoNotJump() {
        for type in [2, 3, 4, -1] {
            XCTAssertFalse(P.shouldJump(pending: true, selectedType: type, currentIsQuery: true), "type \(type)")
        }
    }
}
