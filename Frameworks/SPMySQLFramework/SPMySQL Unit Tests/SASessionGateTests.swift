//
//  SASessionGateTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// A connection stand-in whose state the test sets, recording what the gate does with it.
private final class SAScriptedGateHost: NSObject, SASessionGateHost {
    var hasSessionToUse = true
    var sessionIsMarkedForReplacement = false
    var sessionProtocolCannotBeTrusted = false
    var sessionReportsOpenTransaction = false
    /// What the check does, and answers.
    var check: () -> Bool = { true }
    private(set) var calls: [String] = []

    func lockConnection() { calls.append("lock") }
    func unlockConnection() { calls.append("unlock") }
    func closeSessionMarkedForReplacement() {
        calls.append("close")
        hasSessionToUse = false
        sessionIsMarkedForReplacement = false
        sessionProtocolCannotBeTrusted = false
    }
    func checkIfNecessary() -> Bool {
        calls.append("check")
        return check()
    }

    /// Whether the connection is held on the way out - one lock more than unlocks.
    var holdsTheConnection: Bool {
        calls.filter { $0 == "lock" }.count == calls.filter { $0 == "unlock" }.count + 1
    }

    /// Whether the connection is released on the way out.
    var holdsNothing: Bool {
        calls.filter { $0 == "lock" }.count == calls.filter { $0 == "unlock" }.count
    }
}

/// The gate a statement passes to take the session, against a scripted connection.
final class SASessionGateTests: XCTestCase {
    private let host = SAScriptedGateHost()

    /// A session that is not marked is taken as it is.
    func testAnUnmarkedSessionIsTakenAsItIs() {
        XCTAssertTrue(SASessionGate.lock(host))
        XCTAssertEqual(host.calls, ["lock"])
        XCTAssertTrue(host.holdsTheConnection)
    }

    /// A marked session is closed under the lock, the connection checked - which restores one -
    /// and taken again.
    func testAMarkedSessionIsClosedCheckedAndTakenAgain() {
        host.sessionIsMarkedForReplacement = true
        host.check = { [host] in host.hasSessionToUse = true; return true }

        XCTAssertTrue(SASessionGate.lock(host))
        XCTAssertEqual(host.calls, ["lock", "close", "unlock", "check", "lock"])
        XCTAssertTrue(host.holdsTheConnection)
    }

    /// A marked session with a transaction open is kept, and the mark stands.
    func testAMarkedSessionWithATransactionOpenIsKept() {
        host.sessionIsMarkedForReplacement = true
        host.sessionReportsOpenTransaction = true

        XCTAssertTrue(SASessionGate.lock(host))
        XCTAssertEqual(host.calls, ["lock"])
        XCTAssertTrue(host.sessionIsMarkedForReplacement, "the mark stands until nothing is open in the session")
    }

    /// A marked session the protocol cannot be trusted on goes, transaction or not.
    func testAMarkedSessionTheProtocolCannotBeTrustedOnGoesDespiteTheTransaction() {
        host.sessionIsMarkedForReplacement = true
        host.sessionReportsOpenTransaction = true
        host.sessionProtocolCannotBeTrusted = true
        host.check = { [host] in host.hasSessionToUse = true; return true }

        XCTAssertTrue(SASessionGate.lock(host))
        XCTAssertEqual(host.calls, ["lock", "close", "unlock", "check", "lock"])
    }

    /// A check that cannot restore a session leaves the connection released.
    func testAFailedCheckLeavesTheConnectionReleased() {
        host.hasSessionToUse = false
        host.check = { false }

        XCTAssertFalse(SASessionGate.lock(host))
        XCTAssertEqual(host.calls, ["lock", "unlock", "check"])
        XCTAssertTrue(host.holdsNothing)
    }

    /// A check that says yes without a session appearing is not repeated for ever: the gate gives
    /// up after its checks, with the connection released.
    func testTheGateGivesUpAfterItsChecksAndReleasesTheConnection() {
        host.hasSessionToUse = false
        host.check = { true }

        XCTAssertFalse(SASessionGate.lock(host))
        XCTAssertEqual(host.calls.filter { $0 == "check" }.count, SASessionGate.checks)
        XCTAssertEqual(host.calls.last, "unlock")
        XCTAssertTrue(host.holdsNothing)
    }
}
