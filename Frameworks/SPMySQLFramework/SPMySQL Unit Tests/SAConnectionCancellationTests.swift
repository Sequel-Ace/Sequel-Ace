//
//  SAConnectionCancellationTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Darwin
import XCTest
@testable import SPMySQL

/// How the stand-in server answers a request to kill a query.
private enum SAKillAnswer {
    /// Accepted at once.
    case accepted
    /// Refused at once: the side connection could not be opened, or the server refused.
    case refused
    /// No answer until the test lets it come - a side connection over a route that has gone.
    case blockedThenAccepted
}

/// A connection stand-in with a real lease over a local socket pair, recording what the
/// cancellation logic asks of it.
private final class SACancellationHost: NSObject, SAConnectionCancellationHost {
    let sessionAccess = SAConnectionSessionAccess()
    var sessionHasOpenTransaction = false
    var killAnswer: SAKillAnswer = .accepted
    let letTheKillReturn = DispatchSemaphore(value: 0)
    let killWasAsked = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls: [String] = []

    /// The calls recorded so far, in the order they were made.
    func recordedCalls() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    private func note(_ call: String) {
        lock.lock()
        calls.append(call)
        lock.unlock()
    }

    func killQuery(onServerThread serverThread: UInt) -> Bool {
        note("kill \(serverThread)")
        killWasAsked.signal()
        switch killAnswer {
        case .accepted:
            return true
        case .refused:
            return false
        case .blockedThenAccepted:
            letTheKillReturn.wait()
            return true
        }
    }

    func markRunningQueryCancelled() {
        note("marked")
    }
}

final class SAConnectionCancellationTests: XCTestCase {
    private var sockets: [Int32] = [-1, -1]
    private let host = SACancellationHost()
    private lazy var cancellation = SAConnectionCancellation(host: host)

    /// A session on a local socket pair, with a native query running on it.
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0, "no local socket pair available")
        try host.sessionAccess.trackSocket(sockets[0], serverThreadID: 42)
    }

    override func tearDown() {
        host.sessionAccess.endNativeQuery()
        host.sessionAccess.clearSocket()
        sockets.filter { $0 >= 0 }.forEach { Darwin.close($0) }
        super.tearDown()
    }

    /// Whether the server's end has seen the query's socket shut down, without waiting for it.
    private func theSocketWasShutDown() -> Bool {
        var byte: UInt8 = 0
        return recv(sockets[1], &byte, 1, MSG_PEEK | MSG_DONTWAIT) == 0
    }

    /// Waits up to this long for the query's socket to be shut down.
    private func waitForTheSocketToBeShutDown(within seconds: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while Date() < deadline {
            if theSocketWasShutDown() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return theSocketWasShutDown()
    }

    // MARK: - Recording, asking, marking

    /// The stop is recorded and the query marked before the server is asked, and the lease
    /// holds the query while the request is out.
    func testTheStopIsRecordedAndTheQueryMarkedBeforeTheServerIsAsked() {
        host.sessionAccess.beginNativeQuery()
        host.killAnswer = .blockedThenAccepted
        defer { host.letTheKillReturn.signal() }

        cancellation.requestCancellation(synchronously: false)

        XCTAssertEqual(host.killWasAsked.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(host.recordedCalls(), ["marked", "kill 42"])
        XCTAssertFalse(host.sessionAccess.reserveCancellation().holdsTheQuery,
                       "the lease holds the query for the request that is out")
    }

    /// Without a native query there is nothing to kill and nothing to mark: the stop is recorded
    /// against whatever is pending, which the lease sees to.
    func testAStopWithNothingNativeAsksAndMarksNothing() {
        cancellation.requestCancellation(synchronously: true)

        XCTAssertEqual(host.recordedCalls(), [])
        XCTAssertFalse(theSocketWasShutDown())
    }

    /// A second stop while the first request is on its way sends nothing and marks nothing: the
    /// first one holds the query, and its request may yet be accepted.
    func testASecondStopWhileTheFirstIsOnItsWayDoesNothing() {
        host.sessionAccess.beginNativeQuery()
        host.killAnswer = .blockedThenAccepted
        cancellation.requestCancellation(synchronously: false)
        XCTAssertEqual(host.killWasAsked.wait(timeout: .now() + 2), .success)

        cancellation.requestCancellation(synchronously: true)

        XCTAssertEqual(host.recordedCalls(), ["marked", "kill 42"])
        host.letTheKillReturn.signal()
    }

    /// Once the server accepted a request, a later stop for the same query sends nothing more and
    /// leaves the socket to the server.
    func testALaterStopForAQueryTheServerIsEndingSendsNothingMore() {
        host.sessionAccess.beginNativeQuery()
        host.sessionHasOpenTransaction = true
        cancellation.requestCancellation(synchronously: true)
        XCTAssertEqual(host.recordedCalls(), ["marked", "kill 42"])

        cancellation.requestCancellation(synchronously: true)

        XCTAssertEqual(host.recordedCalls(), ["marked", "kill 42", "marked"], "marked again, asked again never")
        XCTAssertFalse(waitForTheSocketToBeShutDown(within: SAConnectionCancellation.shutdownGrace + 1))
    }

    // MARK: - The grace period

    /// A server that does not answer has the query's socket shut down once the grace period is
    /// over - not before, and not never.
    func testAServerThatDoesNotAnswerHasTheSocketShutDownAfterTheGrace() {
        host.sessionAccess.beginNativeQuery()
        host.killAnswer = .refused
        let started = Date()

        cancellation.requestCancellation(synchronously: true)

        XCTAssertEqual(host.recordedCalls(), ["marked", "kill 42"])
        XCTAssertFalse(theSocketWasShutDown(), "the grace period has not run out")
        XCTAssertTrue(waitForTheSocketToBeShutDown(within: SAConnectionCancellation.shutdownGrace + 2))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), SAConnectionCancellation.shutdownGrace - 0.1)
        XCTAssertEqual(host.recordedCalls(), ["marked", "kill 42", "marked"],
                       "the query is marked again as its read ends, in case it was not waiting any more when first marked")
    }

    /// The grace period runs from the moment stopping was asked for, not from the server's answer.
    ///
    /// Reaching the server over a route that has gone takes the side connection's own timeouts.
    /// If the grace period only started afterwards, the query's socket would stay open for all of
    /// that and two seconds more - the wait this is meant to bound.
    func testTheGracePeriodDoesNotWaitForTheServer() {
        host.sessionAccess.beginNativeQuery()
        host.killAnswer = .blockedThenAccepted

        DispatchQueue.global().async {
            self.cancellation.requestCancellation(synchronously: true)
        }
        XCTAssertEqual(host.killWasAsked.wait(timeout: .now() + 2), .success)

        XCTAssertTrue(waitForTheSocketToBeShutDown(within: SAConnectionCancellation.shutdownGrace + 2),
                      "the socket is shut down while the request is still out there")
        host.letTheKillReturn.signal()
    }

    /// A session with a transaction open is left to a server that accepted the kill: the server
    /// ends the statement on its own time, and shutting the socket down would roll the transaction back.
    func testAnAcceptedKillLeavesASessionWithATransactionOpenToTheServer() {
        host.sessionAccess.beginNativeQuery()
        host.sessionHasOpenTransaction = true
        host.killAnswer = .accepted

        cancellation.requestCancellation(synchronously: true)

        XCTAssertFalse(waitForTheSocketToBeShutDown(within: SAConnectionCancellation.shutdownGrace + 1))
    }

    /// Without a transaction, a query still waiting after the grace period has its socket shut
    /// down whatever the server said: there is nothing to lose, and nothing to wait for.
    func testWithoutATransactionTheGracePeriodEndsTheWaitWhateverTheServerSaid() {
        host.sessionAccess.beginNativeQuery()
        host.killAnswer = .accepted

        cancellation.requestCancellation(synchronously: true)

        XCTAssertTrue(waitForTheSocketToBeShutDown(within: SAConnectionCancellation.shutdownGrace + 2))
    }

    /// With a transaction open, an answer that comes after the grace period decides when it comes:
    /// a refused request shuts the socket down, an accepted one does not.
    func testWithATransactionOpenALateAnswerDecides() {
        host.sessionAccess.beginNativeQuery()
        host.sessionHasOpenTransaction = true
        host.killAnswer = .blockedThenAccepted
        DispatchQueue.global().async {
            self.cancellation.requestCancellation(synchronously: true)
        }
        XCTAssertEqual(host.killWasAsked.wait(timeout: .now() + 2), .success)

        XCTAssertFalse(waitForTheSocketToBeShutDown(within: SAConnectionCancellation.shutdownGrace + 0.5),
                       "the decision waits for the server while a transaction is open")
        host.letTheKillReturn.signal()
        XCTAssertFalse(waitForTheSocketToBeShutDown(within: 0.5), "and an accepted kill leaves the socket alone")
    }

    /// A query that finished before the grace period ran out is not cut off, and neither is the
    /// query that took its place.
    func testAQueryThatFinishedBeforeTheGraceIsNotCutOffAndNeitherIsItsSuccessor() {
        host.sessionAccess.beginNativeQuery()
        host.killAnswer = .refused
        cancellation.requestCancellation(synchronously: true)

        host.sessionAccess.endNativeQuery()
        host.sessionAccess.beginNativeQuery()

        XCTAssertFalse(waitForTheSocketToBeShutDown(within: SAConnectionCancellation.shutdownGrace + 1),
                       "the stop was about a query that is gone")
        XCTAssertEqual(host.recordedCalls(), ["marked", "kill 42"], "and nothing is marked on its successor's behalf")
    }

    // MARK: - The decisions on their own

    /// A session with an open transaction keeps its socket once the server accepted the kill.
    func testAnAcceptedKillLeavesASessionWithAnOpenTransactionAlone() {
        XCTAssertFalse(SAConnectionCancellation.closesSocketAfterGrace(killAccepted: true, sessionHasOpenTransaction: true))
        XCTAssertTrue(SAConnectionCancellation.closesSocketAfterGrace(killAccepted: true, sessionHasOpenTransaction: false))
        XCTAssertTrue(SAConnectionCancellation.closesSocketAfterGrace(killAccepted: false, sessionHasOpenTransaction: true))
        XCTAssertTrue(SAConnectionCancellation.closesSocketAfterGrace(killAccepted: false, sessionHasOpenTransaction: false))
    }

    /// An answer that comes before the grace period ends leaves the decision to the grace period.
    func testAnEarlyAnswerIsDecidedWhenTheGracePeriodEnds() {
        let attempt = SAKillAttempt()
        XCTAssertFalse(attempt.finish(accepted: true))
        XCTAssertEqual(attempt.endGrace(waitingForAnswer: true), true)
    }

    /// With a transaction open, an answer that comes after the grace period ended decides when it comes.
    func testALateAnswerDecidesWhenItIsWaitedFor() {
        let attempt = SAKillAttempt()
        XCTAssertNil(attempt.endGrace(waitingForAnswer: true))
        XCTAssertTrue(attempt.finish(accepted: false))
    }

    /// Without a transaction the grace period decides on its own, and a late answer changes nothing.
    func testTheGracePeriodDecidesAloneWhenNoAnswerIsWaitedFor() {
        let attempt = SAKillAttempt()
        XCTAssertEqual(attempt.endGrace(waitingForAnswer: false), false)
        XCTAssertFalse(attempt.finish(accepted: true))
    }

    /// A mark acted on later does not close a session something else has opened a transaction in -
    /// unless the protocol cannot be trusted on it, which no transaction is worth.
    func testAMarkDoesNotCloseASessionWithWorkGoingOnInIt() {
        XCTAssertTrue(SAConnectionCancellation.markedSessionIsClosedNow(sessionHasOpenTransaction: false,
                                                                        sessionIsProtocolInvalid: false),
                      "nothing is open, so the mark is acted on")
        XCTAssertFalse(SAConnectionCancellation.markedSessionIsClosedNow(sessionHasOpenTransaction: true,
                                                                         sessionIsProtocolInvalid: false),
                       "closing it would roll back work somebody is still doing")
        XCTAssertTrue(SAConnectionCancellation.markedSessionIsClosedNow(sessionHasOpenTransaction: true,
                                                                        sessionIsProtocolInvalid: true),
                      "a cut-off ping's answer would be read as the next statement's result, so it goes")
        XCTAssertTrue(SAConnectionCancellation.markedSessionIsClosedNow(sessionHasOpenTransaction: false,
                                                                        sessionIsProtocolInvalid: true))
    }

    /// A session whose ping was cut off before its answer came is replaced; any other is kept.
    func testASessionIsReplacedOnlyAfterAPingCutOffBeforeItsAnswer() {
        XCTAssertTrue(SAConnectionCancellation.replacesSessionAfterPing(cutOff: true, pingSucceeded: false))
        XCTAssertFalse(SAConnectionCancellation.replacesSessionAfterPing(cutOff: true, pingSucceeded: true))
        XCTAssertFalse(SAConnectionCancellation.replacesSessionAfterPing(cutOff: false, pingSucceeded: false))
        XCTAssertFalse(SAConnectionCancellation.replacesSessionAfterPing(cutOff: false, pingSucceeded: true))
    }
}
