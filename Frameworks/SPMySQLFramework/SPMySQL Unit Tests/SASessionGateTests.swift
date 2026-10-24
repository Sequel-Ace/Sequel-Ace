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
    var sessionReplacementMark = SASessionReplacementMark.notMarked
    var sessionReportsOpenTransaction = false
    /// Whether the connection lock is free for a try.
    var lockIsFree = true
    /// What the check does, and answers.
    var check: () -> Bool = { true }
    private(set) var calls: [String] = []

    func lockConnection() { calls.append("lock") }
    func unlockConnection() { calls.append("unlock") }
    func tryLockConnection() -> Bool {
        calls.append("trylock")
        if lockIsFree { locksHeldThroughATry += 1 }
        return lockIsFree
    }
    private var locksHeldThroughATry = 0
    func closeSessionMarkedForReplacement() {
        calls.append("close")
        hasSessionToUse = false
        sessionReplacementMark = .notMarked
    }
    func checkIfNecessary() -> Bool {
        calls.append("check")
        return check()
    }

    /// Whether the connection is held on the way out - one lock more than unlocks.
    var holdsTheConnection: Bool {
        locksTaken == calls.filter { $0 == "unlock" }.count + 1
    }

    /// Whether the connection is released on the way out.
    var holdsNothing: Bool {
        locksTaken == calls.filter { $0 == "unlock" }.count
    }

    /// Locks taken by waiting or by a successful try.
    private var locksTaken: Int {
        calls.filter { $0 == "lock" }.count + locksHeldThroughATry
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
        host.sessionReplacementMark = .whenNothingIsOpen
        host.check = { [host] in host.hasSessionToUse = true; return true }

        XCTAssertTrue(SASessionGate.lock(host))
        XCTAssertEqual(host.calls, ["lock", "close", "unlock", "check", "lock"])
        XCTAssertTrue(host.holdsTheConnection)
    }

    /// A marked session with a transaction open is kept, and the mark stands.
    func testAMarkedSessionWithATransactionOpenIsKept() {
        host.sessionReplacementMark = .whenNothingIsOpen
        host.sessionReportsOpenTransaction = true

        XCTAssertTrue(SASessionGate.lock(host))
        XCTAssertEqual(host.calls, ["lock"])
        XCTAssertEqual(host.sessionReplacementMark, .whenNothingIsOpen, "the mark stands until nothing is open in the session")
    }

    /// A marked session the protocol cannot be trusted on goes, transaction or not.
    func testAMarkedSessionTheProtocolCannotBeTrustedOnGoesDespiteTheTransaction() {
        host.sessionReplacementMark = .regardless
        host.sessionReportsOpenTransaction = true
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

    // MARK: - Which session a value is escaped for

    /// Escaping asks the mark the way the gate does: an unmarked session is the one there, one
    /// marked regardless is replaced, and one marked to go once nothing is open in it is decided
    /// from the session's own answer with the connection held.
    func testEscapingFollowsTheMarkTheWayTheGateDoes() {
        XCTAssertEqual(SASessionGate.sessionForEscaping(on: host), .theSessionThere)
        XCTAssertEqual(host.calls, [], "an unmarked session needs no lock")

        host.sessionReplacementMark = .regardless
        XCTAssertEqual(SASessionGate.sessionForEscaping(on: host), .theReplacement)
        XCTAssertEqual(host.calls, [], "nor does one that goes regardless")

        host.sessionReplacementMark = .whenNothingIsOpen
        XCTAssertEqual(SASessionGate.sessionForEscaping(on: host), .theReplacement)
        XCTAssertEqual(host.calls, ["trylock", "unlock"], "decided with the connection held, and released")

        host.sessionReportsOpenTransaction = true
        XCTAssertEqual(SASessionGate.sessionForEscaping(on: host), .theSessionThere, "kept for its transaction, so followed")
        XCTAssertTrue(host.holdsNothing)
    }

    /// While another statement runs, whether a session marked to go once nothing is open in it
    /// goes cannot be told, and escaping does not wait to find out: the answer is undecidable.
    func testEscapingCannotBeDecidedForAMarkedSessionWhileAStatementRuns() {
        host.sessionReplacementMark = .whenNothingIsOpen
        host.lockIsFree = false

        XCTAssertEqual(SASessionGate.sessionForEscaping(on: host), .undecidable)
        XCTAssertEqual(host.calls, ["trylock"], "nothing waited, nothing was released that was never held")
    }

    /// A session marked to go while the last check restored it is not taken on the strength of
    /// being there: it is closed and the statement refused, with the connection released - and
    /// a keepalive that marks every restored session cannot keep the gate going round.
    func testASessionMarkedDuringTheLastCheckIsNotTaken() {
        host.hasSessionToUse = false
        host.check = { [host] in
            host.hasSessionToUse = true
            host.sessionReplacementMark = .regardless
            return true
        }

        XCTAssertFalse(SASessionGate.lock(host))
        XCTAssertEqual(host.calls, ["lock", "unlock", "check", "lock", "close", "unlock", "check", "lock", "close", "unlock"])
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
