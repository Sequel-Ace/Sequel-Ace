//
//  SAInFlightQueryTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Darwin
import XCTest
@testable import SPMySQL

final class SAInFlightQueryTests: XCTestCase {
    private let inFlightQuery = SAInFlightQuery()
    private var descriptors: [Int32] = [-1, -1]

    /// Creates the connected socket pair the tests work with.
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0, "no local socket pair available")
    }

    /// Closes the socket pair.
    override func tearDown() {
        descriptors.filter { $0 >= 0 }.forEach { Darwin.close($0) }
        super.tearDown()
    }

    /// Only the waiting query is ended.
    func testOnlyTheWaitingQueryIsEnded() {
        inFlightQuery.beginWaiting(forGeneration: 5, onSocket: descriptors[0], serverThread: 42)

        XCTAssertFalse(inFlightQuery.closeSocket(ifGenerationIsWaiting: 4, beforeClosing: {}))
        XCTAssertFalse(peerSawTheSocketClose())

        XCTAssertTrue(inFlightQuery.closeSocket(ifGenerationIsWaiting: 5, beforeClosing: {}))
        XCTAssertTrue(peerSawTheSocketClose())
    }

    /// A query that stopped waiting is left alone.
    func testAQueryThatStoppedWaitingIsLeftAlone() {
        inFlightQuery.beginWaiting(forGeneration: 5, onSocket: descriptors[0], serverThread: 42)
        inFlightQuery.endWaiting(forGeneration: 5)

        XCTAssertFalse(inFlightQuery.closeSocket(ifGenerationIsWaiting: 5, beforeClosing: {}))
        XCTAssertFalse(peerSawTheSocketClose())
    }

    /// A stale end does not end the query that followed.
    func testAStaleEndDoesNotEndTheQueryThatFollowed() {
        inFlightQuery.beginWaiting(forGeneration: 6, onSocket: descriptors[0], serverThread: 42)
        inFlightQuery.endWaiting(forGeneration: 5)

        XCTAssertTrue(inFlightQuery.closeSocket(ifGenerationIsWaiting: 6, beforeClosing: {}))
    }

    /// The preparation runs only when the socket is closed.
    func testThePreparationRunsOnlyWhenTheSocketIsClosed() {
        var preparedFor: [UInt] = []
        inFlightQuery.beginWaiting(forGeneration: 7, onSocket: descriptors[0], serverThread: 42)

        inFlightQuery.closeSocket(ifGenerationIsWaiting: 3, beforeClosing: { preparedFor.append(3) })
        inFlightQuery.closeSocket(ifGenerationIsWaiting: 7, beforeClosing: { preparedFor.append(7) })

        XCTAssertEqual(preparedFor, [7])
    }

    /// A kill only concerns the query that is still waiting.
    func testAKillOnlyConcernsTheQueryThatIsStillWaiting() {
        inFlightQuery.beginWaiting(forGeneration: 8, onSocket: descriptors[0], serverThread: 17)

        XCTAssertEqual(inFlightQuery.beginKill(ifGenerationIsWaiting: 7), 0)
        XCTAssertEqual(inFlightQuery.beginKill(ifGenerationIsWaiting: 8), 17)

        // Only one request at a time is on its way.
        XCTAssertEqual(inFlightQuery.beginKill(ifGenerationIsWaiting: 8), 0)

        var marked = false
        inFlightQuery.endKill(forGeneration: 8, succeeded: true) { marked = true }
        XCTAssertTrue(marked)
    }

    /// A failed or late kill marks nothing.
    func testAFailedOrLateKillMarksNothing() {
        var marked: [String] = []
        inFlightQuery.beginWaiting(forGeneration: 8, onSocket: descriptors[0], serverThread: 17)

        XCTAssertEqual(inFlightQuery.beginKill(ifGenerationIsWaiting: 8), 17)
        inFlightQuery.endKill(forGeneration: 8, succeeded: false) { marked.append("failed") }

        XCTAssertEqual(inFlightQuery.beginKill(ifGenerationIsWaiting: 8), 17)
        inFlightQuery.endWaiting(forGeneration: 8)
        inFlightQuery.endKill(forGeneration: 8, succeeded: true) { marked.append("late") }

        XCTAssertEqual(marked, [])
    }

    /// A new query waits until a kill has gone out.
    func testANewQueryWaitsUntilAKillHasGoneOut() {
        inFlightQuery.beginWaiting(forGeneration: 8, onSocket: descriptors[0], serverThread: 17)
        XCTAssertEqual(inFlightQuery.beginKill(ifGenerationIsWaiting: 8), 17)
        inFlightQuery.endWaiting(forGeneration: 8)

        let nextQueryStarted = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            self.inFlightQuery.beginWaiting(forGeneration: 9, onSocket: self.descriptors[0], serverThread: 17)
            nextQueryStarted.signal()
        }

        // The request names the same server session, so the next query must not be waiting yet.
        XCTAssertEqual(nextQueryStarted.wait(timeout: .now() + 0.3), .timedOut)

        // Ending a wait and asking for requests never wait, even meanwhile.
        inFlightQuery.endWaiting(forGeneration: 8)
        inFlightQuery.requestCancellation(ofGeneration: 8)

        inFlightQuery.endKill(forGeneration: 8, succeeded: true) {}
        XCTAssertEqual(nextQueryStarted.wait(timeout: .now() + 2), .success)
    }

    /// A request is remembered under the query's original number.
    func testARequestIsRememberedUnderTheQuerysOriginalNumber() {
        inFlightQuery.requestCancellation(ofGeneration: 12)

        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGeneration: 12))
        XCTAssertFalse(inFlightQuery.cancellationWasRequested(forGeneration: 13))
        XCTAssertFalse(inFlightQuery.cancellationWasRequested(forGeneration: 0))
    }

    /// Nothing is ever waiting before the first query.
    func testNothingIsEverWaitingBeforeTheFirstQuery() {
        XCTAssertFalse(inFlightQuery.closeSocket(ifGenerationIsWaiting: 0, beforeClosing: {}))
    }

    /// Whether the other end of the pair has seen its peer shut down, without waiting for it.
    private func peerSawTheSocketClose() -> Bool {
        var byte: UInt8 = 0
        return recv(descriptors[1], &byte, 1, MSG_PEEK | MSG_DONTWAIT) == 0
    }
}
