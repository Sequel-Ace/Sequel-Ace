//
//  SAConnectionCancellationTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

final class SAConnectionCancellationTests: XCTestCase {

    /// A connection stand-in that records what the cancellation logic asks of it.
    private final class SARecordingHost: NSObject, SAConnectionCancellationHost {
        let lock = NSLock()
        var currentQueryGeneration: UInt = 0
        var connectionIsFree = true
        var calls: [String] = []
        let killRequested = DispatchSemaphore(value: 0)

        /// Records one call the cancellation logic made.
        func note(_ call: String) {
            lock.lock()
            calls.append(call)
            lock.unlock()
        }

        /// The calls recorded so far, in the order they were made.
        func recordedCalls() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }

        /// Records that the next attempt was asked to be short.
        func noteUserEndedWait() { note("endedWait") }
        /// Records that the running query was marked cancelled.
        func markRunningQueryCancelled() { note("marked") }
        /// Records a kill request and lets the test know it was made.
        func killQueryOverSideConnection(forGeneration generation: UInt) {
            note("kill \(generation)")
            killRequested.signal()
        }
        /// Records the attempt to take the connection, which succeeds while it is free.
        func holdConnectionIfFree() -> Bool {
            note("hold")
            return connectionIsFree
        }
        /// Records that the connection was given back.
        func releaseHeldConnection() { note("release") }
        /// Records that the outcome was recorded as cancelled.
        func recordWorkAsCancelled() { note("recorded") }
        /// Records that the session was closed.
        func closeSessionIfConnected() { note("closed") }
    }

    private let host = SARecordingHost()
    private let inFlightQuery = SAInFlightQuery()
    private lazy var cancellation = SAConnectionCancellation(host: host, inFlightQuery: inFlightQuery)

    /// The request is recorded before the server is asked.
    func testTheRequestIsRecordedBeforeTheServerIsAsked() {
        inFlightQuery.beginWaiting(forGeneration: 4, onSocket: -1, serverThread: 11)

        cancellation.requestCancellation(ofGeneration: 4, synchronously: true)

        XCTAssertEqual(host.recordedCalls(), ["kill 4"])
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGeneration: 4))
    }

    /// A request is remembered for a query that is between attempts.
    func testARequestIsRememberedForAQueryThatIsBetweenAttempts() {
        cancellation.requestCancellation(ofGeneration: 4, synchronously: true)

        XCTAssertEqual(host.recordedCalls(), ["kill 4"])
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGeneration: 4))
        XCTAssertFalse(inFlightQuery.cancellationWasRequested(forGeneration: 5))
    }

    /// The main thread never waits for the server.
    func testTheMainThreadNeverWaitsForTheServer() {
        cancellation.requestCancellation(ofGeneration: 4, synchronously: false)

        XCTAssertEqual(host.killRequested.wait(timeout: .now() + 2), .success)
    }

    /// Nothing is requested without a query.
    func testNothingIsRequestedWithoutAQuery() {
        cancellation.requestCancellation(ofGeneration: 0, synchronously: true)

        XCTAssertEqual(host.recordedCalls(), [])
    }

    /// Stopping the wait stops the query that was running.
    func testStoppingTheWaitStopsTheQueryThatWasRunning() {
        host.currentQueryGeneration = 9
        cancellation.userStoppedWaiting(workCoordinator: nil)

        XCTAssertEqual(host.killRequested.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(host.recordedCalls(), ["endedWait", "kill 9"])
    }

    /// Late work is settled while nothing else has run.
    func testLateWorkIsSettledWhileNothingElseHasRun() {
        host.currentQueryGeneration = 3
        cancellation.settleAbandonedWork(fromGeneration: 3)

        XCTAssertEqual(host.recordedCalls(), ["hold", "recorded", "closed", "release"])
    }

    /// Late work leaves a query that came after it alone.
    func testLateWorkLeavesAQueryThatCameAfterItAlone() {
        host.currentQueryGeneration = 4
        cancellation.settleAbandonedWork(fromGeneration: 3)

        XCTAssertEqual(host.recordedCalls(), ["hold", "release"])
    }

    /// Late work leaves a connection that is in use alone.
    func testLateWorkLeavesAConnectionThatIsInUseAlone() {
        host.currentQueryGeneration = 3
        host.connectionIsFree = false
        cancellation.settleAbandonedWork(fromGeneration: 3)

        XCTAssertEqual(host.recordedCalls(), ["hold"])
    }

    /// A cancelled reconnect keeps the connection recoverable.
    func testACancelledReconnectKeepsTheConnectionRecoverable() {
        XCTAssertEqual(recovery(cancelled: true, userDisconnected: false, connected: false, disconnected: true, mayDisconnect: false), .markLost)
        XCTAssertEqual(recovery(cancelled: true, userDisconnected: false, connected: true, disconnected: false, mayDisconnect: true), .discardAndMarkLost)
    }

    /// A connection is only closed where that is safe.
    func testAConnectionIsOnlyClosedWhereThatIsSafe() {
        XCTAssertEqual(recovery(cancelled: true, userDisconnected: false, connected: true, disconnected: false, mayDisconnect: false), .none)
    }

    /// Nothing changes without a cancellation or after the user disconnected.
    func testNothingChangesWithoutACancellationOrAfterTheUserDisconnected() {
        XCTAssertEqual(recovery(cancelled: false, userDisconnected: false, connected: false, disconnected: true, mayDisconnect: true), .none)
        XCTAssertEqual(recovery(cancelled: true, userDisconnected: true, connected: false, disconnected: true, mayDisconnect: true), .none)
    }

    /// Asks the recovery decision with readable argument names.
    private func recovery(cancelled: Bool, userDisconnected: Bool, connected: Bool, disconnected: Bool, mayDisconnect: Bool) -> SAConnectionRecoveryAction {
        SAConnectionCancellation.recoveryAfterCancelledReconnect(threadCancelled: cancelled,
                                                                 userDisconnected: userDisconnected,
                                                                 isConnected: connected,
                                                                 isDisconnected: disconnected,
                                                                 mayDisconnect: mayDisconnect)
    }
}
