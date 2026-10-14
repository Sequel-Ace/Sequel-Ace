//
//  SASessionStateTrackingTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// Turning on the session-state tracking escaping depends on.
final class SASessionStateTrackingTests: XCTestCase {

    /// A server that reports nothing is given the variables the connection needs.
    func testAnEmptyListGetsWhatIsNeeded() {
        XCTAssertEqual(SASessionStateTracking.trackingListToSet(givenCurrentList: ""),
                       "character_set_client")
        XCTAssertEqual(SASessionStateTracking.trackingListToSet(givenCurrentList: nil),
                       "character_set_client")
    }

    /// What the server already reports is kept - the connection adds to the list rather than
    /// replacing it, so nothing else that depends on the tracking stops working.
    func testWhatIsAlreadyTrackedIsKept() {
        let set = SASessionStateTracking.trackingListToSet(givenCurrentList: "time_zone,autocommit")
        XCTAssertEqual(set, "time_zone,autocommit,character_set_client")
    }

    /// A list that already has it is left alone. The server rejects a repeated entry outright,
    /// so adding it again would fail the statement.
    func testAListThatAlreadyHasItIsLeftAlone() {
        XCTAssertNil(SASessionStateTracking.trackingListToSet(givenCurrentList: "character_set_client"))
        XCTAssertNil(SASessionStateTracking.trackingListToSet(
            givenCurrentList: "time_zone,autocommit,character_set_client,character_set_results"))
    }

    /// The server's own default, which already covers it.
    func testTheServerDefaultNeedsNothing() {
        XCTAssertNil(SASessionStateTracking.trackingListToSet(
            givenCurrentList: "time_zone,autocommit,character_set_client,character_set_results,character_set_connection"))
    }

    /// A session tracking everything needs nothing added.
    func testTrackingEverythingNeedsNothing() {
        XCTAssertNil(SASessionStateTracking.trackingListToSet(givenCurrentList: "*"))
    }

    /// Names are matched however the server spells them, and spacing does not hide one.
    func testSpacingAndCaseDoNotHideAnEntry() {
        XCTAssertNil(SASessionStateTracking.trackingListToSet(givenCurrentList: "CHARACTER_SET_CLIENT"))
        XCTAssertNil(SASessionStateTracking.trackingListToSet(givenCurrentList: " time_zone , character_set_client "))
    }

    /// An empty entry in the list is not carried into the value that is set.
    func testEmptyEntriesAreDropped() {
        XCTAssertEqual(SASessionStateTracking.trackingListToSet(givenCurrentList: "time_zone,,"),
                       "time_zone,character_set_client")
    }
    /// The server sends system-variable items as name, value, name, value, and only the names
    /// say which variable was reported.
    func testOnlyTheNamesAreRead() {
        XCTAssertTrue(SASessionStateTracking.characterSetIsNamed(in: ["character_set_client", "gbk"]))
        XCTAssertTrue(SASessionStateTracking.characterSetIsNamed(in: [
            "time_zone", "SYSTEM", "character_set_client", "utf8mb4",
        ]))
        XCTAssertFalse(SASessionStateTracking.characterSetIsNamed(in: ["time_zone", "SYSTEM"]))
        XCTAssertFalse(SASessionStateTracking.characterSetIsNamed(in: []))
    }

    /// A value that happens to read like the name is not one: it sits where a value sits.
    func testAValueIsNotMistakenForAName() {
        XCTAssertFalse(SASessionStateTracking.characterSetIsNamed(in: ["time_zone", "character_set_client"]))
        XCTAssertTrue(SASessionStateTracking.characterSetIsNamed(in: [
            "time_zone", "character_set_client", "character_set_client", "gbk",
        ]), "and the real name after it still counts")
    }

    /// A packet that ends on a name without its value is still read for what it names.
    func testATrailingNameStillCounts() {
        XCTAssertTrue(SASessionStateTracking.characterSetIsNamed(in: ["character_set_client"]))
        XCTAssertTrue(SASessionStateTracking.characterSetIsNamed(in: ["time_zone", "SYSTEM", "character_set_client"]))
    }

}
