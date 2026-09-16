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

    /// A request made while a query reconnects or retries reaches that query.
    func testARequestReachesAQueryOnItsRetry() {
        // The query started as 20, its reconnect ran 21 and 22, and its retry runs as 23.
        inFlightQuery.requestCancellation(ofGeneration: 23)
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 20, through: 23))

        let reconnecting = SAInFlightQuery()
        reconnecting.requestCancellation(ofGeneration: 21)
        XCTAssertTrue(reconnecting.cancellationWasRequested(forGenerationsFrom: 20, through: 23))
        XCTAssertTrue(reconnecting.cancellationWasRequested(forGenerationsFrom: 21, through: 21))

        // A request for a query before or after it does not.
        XCTAssertFalse(reconnecting.cancellationWasRequested(forGenerationsFrom: 22, through: 23))
        XCTAssertFalse(reconnecting.cancellationWasRequested(forGenerationsFrom: 18, through: 20))
    }

    /// A request to stop a query another thread ran while this one reconnected does not stop this one.
    func testARequestForAnotherQueryBetweenTheAttemptsIsNotForThisQuery() {
        // This query started as 40, its reconnect ran 41, another thread's query ran as 42, and
        // this query's retry runs as 43.
        inFlightQuery.noteLatestGeneration(40, ownedByQueryStartedAt: 40)
        inFlightQuery.noteLatestGeneration(41, ownedByQueryStartedAt: 0)
        inFlightQuery.noteLatestGeneration(42, ownedByQueryStartedAt: 42)
        inFlightQuery.requestCancellation(ofGeneration: 42)
        inFlightQuery.noteLatestGeneration(43, ownedByQueryStartedAt: 40)

        XCTAssertFalse(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 40, through: 43))
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 42, through: 42))
    }

    /// A request to stop this query survives a later request to stop another thread's query.
    func testARequestForThisQuerySurvivesALaterRequestForAnotherQuery() {
        // This query, 40, is asked to stop while it reconnects (41); another thread's query, 42,
        // is asked to stop after it; this query's retry runs as 43.
        inFlightQuery.noteLatestGeneration(40, ownedByQueryStartedAt: 40)
        inFlightQuery.noteLatestGeneration(41, ownedByQueryStartedAt: 0)
        inFlightQuery.requestCancellation(ofGeneration: 41)
        inFlightQuery.noteLatestGeneration(42, ownedByQueryStartedAt: 42)
        inFlightQuery.requestCancellation(ofGeneration: 42)
        inFlightQuery.noteLatestGeneration(43, ownedByQueryStartedAt: 40)

        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 40, through: 43))
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 42, through: 42))
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGeneration: 41))
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGeneration: 42))
    }

    /// A request is kept while other queries are asked to stop, up to the number of kept requests.
    func testARequestIsKeptWhileOtherQueriesAreAskedToStop() {
        inFlightQuery.noteLatestGeneration(1, ownedByQueryStartedAt: 1)
        inFlightQuery.requestCancellation(ofGeneration: 1)
        for generation in 2..<UInt(SAInFlightQuery.rememberedRequests + 1) {
            inFlightQuery.noteLatestGeneration(generation, ownedByQueryStartedAt: generation)
            inFlightQuery.requestCancellation(ofGeneration: generation)
        }

        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGeneration: 1))
    }

    /// A request made for this query, its reconnect or its retry stops this query.
    func testARequestForThisQuerysReconnectOrRetryIsForThisQuery() {
        inFlightQuery.noteLatestGeneration(40, ownedByQueryStartedAt: 40)
        inFlightQuery.noteLatestGeneration(41, ownedByQueryStartedAt: 0)
        inFlightQuery.noteLatestGeneration(42, ownedByQueryStartedAt: 42)
        inFlightQuery.noteLatestGeneration(43, ownedByQueryStartedAt: 40)

        for generation: UInt in [40, 41, 43] {
            inFlightQuery.requestCancellation(ofGeneration: generation)
            XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 40, through: 43), "request for \(generation)")
        }
    }

    /// A request for a number whose query is no longer known counts for the queries it could belong to.
    func testARequestForAForgottenNumberCountsForTheQueriesAroundIt() {
        inFlightQuery.noteLatestGeneration(2, ownedByQueryStartedAt: 2)
        inFlightQuery.noteLatestGeneration(2 + SAInFlightQuery.rememberedOwners + 1, ownedByQueryStartedAt: 1)
        inFlightQuery.requestCancellation(ofGeneration: 2)

        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 1, through: 2 + SAInFlightQuery.rememberedOwners + 1))
    }

    /// After many queries, the owners of the latest numbers are still known.
    func testTheLatestOwnersAreKnownAfterManyQueries() {
        for generation: UInt in 1...200 {
            inFlightQuery.noteLatestGeneration(generation, ownedByQueryStartedAt: generation == 199 ? 0 : generation)
        }

        inFlightQuery.requestCancellation(ofGeneration: 190)
        XCTAssertFalse(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 180, through: 200))
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 190, through: 190))

        inFlightQuery.requestCancellation(ofGeneration: 199)
        XCTAssertTrue(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 180, through: 200))
    }

    /// No request was made before any query ran.
    func testNoRequestMatchesBeforeAnyWasMade() {
        XCTAssertFalse(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 0, through: 0))
        XCTAssertFalse(inFlightQuery.cancellationWasRequested(forGenerationsFrom: 0, through: 5))
    }

    /// The latest number can be read without waiting for the query that set it.
    func testTheLatestNumberIsWhatWasNotedLast() {
        XCTAssertEqual(inFlightQuery.latestGeneration, 0)
        inFlightQuery.noteLatestGeneration(30)
        inFlightQuery.noteLatestGeneration(31)
        XCTAssertEqual(inFlightQuery.latestGeneration, 31)
    }

    /// Only the thread that took the connection counts as holding it, and only until it is given back.
    func testOnlyTheThreadThatTookTheConnectionHoldsIt() {
        XCTAssertFalse(inFlightQuery.connectionIsHeldByCurrentThread)

        inFlightQuery.noteConnectionHeld(byCurrentThread: true)
        XCTAssertTrue(inFlightQuery.connectionIsHeldByCurrentThread)

        let otherThreadChecked = expectation(description: "checked on another thread")
        var heldElsewhere = true
        Thread {
            heldElsewhere = self.inFlightQuery.connectionIsHeldByCurrentThread
            otherThreadChecked.fulfill()
        }.start()
        wait(for: [otherThreadChecked], timeout: 2)
        XCTAssertFalse(heldElsewhere)

        inFlightQuery.noteConnectionHeld(byCurrentThread: false)
        XCTAssertFalse(inFlightQuery.connectionIsHeldByCurrentThread)
    }

    /// A connection taken on one thread and handed to another is held by the thread it was handed to.
    func testTheConnectionMovesToTheThreadItIsHandedTo() {
        let takenElsewhere = expectation(description: "taken on another thread")
        Thread {
            self.inFlightQuery.noteConnectionHeld(byCurrentThread: true)
            takenElsewhere.fulfill()
        }.start()
        wait(for: [takenElsewhere], timeout: 2)
        XCTAssertFalse(inFlightQuery.connectionIsHeldByCurrentThread)

        inFlightQuery.noteConnectionHeld(byCurrentThread: true)
        XCTAssertTrue(inFlightQuery.connectionIsHeldByCurrentThread)
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
