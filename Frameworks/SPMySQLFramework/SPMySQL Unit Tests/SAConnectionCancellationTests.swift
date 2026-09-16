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

        func note(_ call: String) {
            lock.lock()
            calls.append(call)
            lock.unlock()
        }

        func recordedCalls() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }

        func noteUserEndedWait() { note("endedWait") }
        func markRunningQueryCancelled() { note("marked") }
        func killQueryOverSideConnection(forGeneration generation: UInt) {
            note("kill \(generation)")
            killRequested.signal()
        }
        func holdConnectionIfFree() -> Bool {
            note("hold")
            return connectionIsFree
        }
        func releaseHeldConnection() { note("release") }
        func recordWorkAsCancelled() { note("recorded") }
        func closeSessionIfConnected() { note("closed") }
    }

    private let host = SARecordingHost()
    private let inFlightQuery = SAInFlightQuery()
    private lazy var cancellation = SAConnectionCancellation(host: host, inFlightQuery: inFlightQuery)

    func testTheRequestIsRecordedBeforeTheServerIsAsked() {
        inFlightQuery.beginWaiting(forGeneration: 4, onSocket: -1, serverThread: 11)

        cancellation.requestCancellation(ofGeneration: 4, synchronously: true)

        XCTAssertEqual(host.recordedCalls(), ["kill 4"])
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGeneration: 4))
    }

    func testARequestIsRememberedForAQueryThatIsBetweenAttempts() {
        cancellation.requestCancellation(ofGeneration: 4, synchronously: true)

        XCTAssertEqual(host.recordedCalls(), ["kill 4"])
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGeneration: 4))
        XCTAssertFalse(inFlightQuery.cancellationWasRequested(forGeneration: 5))
    }

    func testTheMainThreadNeverWaitsForTheServer() {
        cancellation.requestCancellation(ofGeneration: 4, synchronously: false)

        XCTAssertEqual(host.killRequested.wait(timeout: .now() + 2), .success)
    }

    func testNothingIsRequestedWithoutAQuery() {
        cancellation.requestCancellation(ofGeneration: 0, synchronously: true)

        XCTAssertEqual(host.recordedCalls(), [])
    }

    func testStoppingTheWaitStopsTheQueryThatWasRunning() {
        host.currentQueryGeneration = 9
        cancellation.userStoppedWaiting(workCoordinator: nil)

        XCTAssertEqual(host.killRequested.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(host.recordedCalls(), ["endedWait", "kill 9"])
    }

    func testLateWorkIsSettledWhileNothingElseHasRun() {
        host.currentQueryGeneration = 3
        cancellation.settleAbandonedWork(fromGeneration: 3)

        XCTAssertEqual(host.recordedCalls(), ["hold", "recorded", "closed", "release"])
    }

    func testLateWorkLeavesAQueryThatCameAfterItAlone() {
        host.currentQueryGeneration = 4
        cancellation.settleAbandonedWork(fromGeneration: 3)

        XCTAssertEqual(host.recordedCalls(), ["hold", "release"])
    }

    func testLateWorkLeavesAConnectionThatIsInUseAlone() {
        host.currentQueryGeneration = 3
        host.connectionIsFree = false
        cancellation.settleAbandonedWork(fromGeneration: 3)

        XCTAssertEqual(host.recordedCalls(), ["hold"])
    }

    func testACancelledReconnectKeepsTheConnectionRecoverable() {
        XCTAssertEqual(recovery(cancelled: true, userDisconnected: false, connected: false, disconnected: true, mayDisconnect: false), .markLost)
        XCTAssertEqual(recovery(cancelled: true, userDisconnected: false, connected: true, disconnected: false, mayDisconnect: true), .discardAndMarkLost)
    }

    func testAConnectionIsOnlyClosedWhereThatIsSafe() {
        XCTAssertEqual(recovery(cancelled: true, userDisconnected: false, connected: true, disconnected: false, mayDisconnect: false), .none)
    }

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
