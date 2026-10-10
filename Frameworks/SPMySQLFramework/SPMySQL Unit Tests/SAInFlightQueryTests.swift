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

    /// The socket a query waits on is kept as a duplicate, so the number going back into
    /// circulation cannot turn the shutdown on somebody else's connection.
    ///
    /// The native library closes its descriptor when a query fails or the connection is torn
    /// down, and the number is then free for whatever opens the next one - here a second socket
    /// pair, which the kernel hands the lowest free number. Only the query's own socket may end.
    func testTheWaitingSocketIsNotTheNumberThatGoesBackIntoCirculation() throws {
        inFlightQuery.beginWaiting(forGeneration: 7, onSocket: descriptors[0], serverThread: 42)

        // What the native library does when the query fails: its own descriptor goes.
        let releasedNumber = descriptors[0]
        Darwin.close(descriptors[0])
        descriptors[0] = -1

        var unrelated: [Int32] = [-1, -1]
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &unrelated) == 0, "no local socket pair available")
        defer { unrelated.filter { $0 >= 0 }.forEach { Darwin.close($0) } }
        try XCTSkipUnless(unrelated[0] == releasedNumber, "the freed number was not handed out again")

        XCTAssertTrue(inFlightQuery.closeSocket(ifGenerationIsWaiting: 7, beforeClosing: {}))

        var byte: UInt8 = 0
        XCTAssertEqual(recv(unrelated[1], &byte, 1, MSG_PEEK | MSG_DONTWAIT), -1,
                       "the connection that was given the number must be untouched")
        XCTAssertEqual(errno, EAGAIN)
        XCTAssertTrue(peerSawTheSocketClose(), "and the query's own socket ended")
    }

    /// A query that stopped waiting is left alone.
    func testAQueryThatStoppedWaitingIsLeftAlone() {
        inFlightQuery.beginWaiting(forGeneration: 5, onSocket: descriptors[0], serverThread: 42)
        inFlightQuery.endWaiting(forGeneration: 5)

        XCTAssertFalse(inFlightQuery.closeSocket(ifGenerationIsWaiting: 5, beforeClosing: {}))
        XCTAssertFalse(peerSawTheSocketClose())
    }

    /// A stop meant for a query that has finished leaves the socket of the query that replaced
    /// it alone.
    ///
    /// Reaching the server with a kill request takes time. By the time it comes back, the query
    /// it was meant for can have finished and a reconnect can have put another one on a socket
    /// of its own. Ending that one would take a session nobody asked about, and roll back
    /// whatever it had open.
    func testAStopForAFinishedQueryLeavesItsSuccessorsSocketAlone() throws {
        var replacement: [Int32] = [-1, -1]
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &replacement) == 0, "no local socket pair available")
        defer { replacement.filter { $0 >= 0 }.forEach { Darwin.close($0) } }

        inFlightQuery.beginWaiting(forGeneration: 5, onSocket: descriptors[0], serverThread: 42)
        inFlightQuery.endWaiting(forGeneration: 5)
        inFlightQuery.beginWaiting(forGeneration: 6, onSocket: replacement[0], serverThread: 43)

        XCTAssertFalse(inFlightQuery.closeSocket(ifGenerationIsWaiting: 5, beforeClosing: {
            XCTFail("a query that finished has nothing to prepare for")
        }), "the stop was meant for a query that is no longer there")

        var byte: UInt8 = 0
        XCTAssertEqual(recv(replacement[1], &byte, 1, MSG_PEEK | MSG_DONTWAIT), -1,
                       "the query that replaced it must be untouched")
        XCTAssertEqual(errno, EAGAIN)

        // And the one it is meant for still ends.
        XCTAssertTrue(inFlightQuery.closeSocket(ifGenerationIsWaiting: 6, beforeClosing: {}))
        XCTAssertEqual(recv(replacement[1], &byte, 1, MSG_PEEK | MSG_DONTWAIT), 0)
    }

    /// A query that takes over from one still recorded as waiting ends its own socket, not the
    /// one before it.
    ///
    /// Generation alone does not say which socket was interrupted. A record can still name the
    /// query before this one - `endWaiting` does nothing when the number no longer matches, so a
    /// query whose session was closed from under it leaves its record standing, and the next
    /// query begins waiting on top of it. Keeping the earlier socket then would end a session
    /// nobody asked about, under the right query's number.
    func testAQueryTakingOverEndsItsOwnSocketAndNotTheOneBeforeIt() throws {
        var earlier: [Int32] = [-1, -1]
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &earlier) == 0, "no local socket pair available")
        defer { earlier.filter { $0 >= 0 }.forEach { Darwin.close($0) } }

        // The earlier query's record is never ended - the shape left behind when its session was
        // closed from under it - and the next query begins waiting on a socket of its own.
        inFlightQuery.beginWaiting(forGeneration: 6, onSocket: earlier[0], serverThread: 41)
        inFlightQuery.beginWaiting(forGeneration: 7, onSocket: descriptors[0], serverThread: 42)

        XCTAssertTrue(inFlightQuery.closeSocket(ifGenerationIsWaiting: 7, beforeClosing: {}))

        XCTAssertTrue(peerSawTheSocketClose(), "the query that is waiting had its socket ended")
        var byte: UInt8 = 0
        XCTAssertEqual(recv(earlier[1], &byte, 1, MSG_PEEK | MSG_DONTWAIT), -1,
                       "and the one before it was left alone")
        XCTAssertEqual(errno, EAGAIN)

        // And the earlier number names nothing any more.
        XCTAssertFalse(inFlightQuery.closeSocket(ifGenerationIsWaiting: 6, beforeClosing: {}))
    }

    /// Only the query that is waiting says it is waiting.
    ///
    /// A stop whose kill request took a while asks this before it ends the session: by then the
    /// query it meant can have finished and another can hold the connection, and ending that
    /// one's session would roll back work nobody asked to stop.
    func testOnlyTheWaitingQuerySaysItIsWaiting() {
        XCTAssertFalse(inFlightQuery.generationIsWaiting(5), "nothing waits before the first query")

        inFlightQuery.beginWaiting(forGeneration: 5, onSocket: descriptors[0], serverThread: 42)
        XCTAssertTrue(inFlightQuery.generationIsWaiting(5))
        XCTAssertFalse(inFlightQuery.generationIsWaiting(4))
        XCTAssertFalse(inFlightQuery.generationIsWaiting(0), "no query has that number")

        inFlightQuery.endWaiting(forGeneration: 5)
        XCTAssertFalse(inFlightQuery.generationIsWaiting(5), "it has finished")

        inFlightQuery.beginWaiting(forGeneration: 6, onSocket: descriptors[0], serverThread: 42)
        XCTAssertFalse(inFlightQuery.generationIsWaiting(5), "and the one after it is not it")
        XCTAssertTrue(inFlightQuery.generationIsWaiting(6))
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

        XCTAssertEqual(inFlightQuery.reservationForKill(ofGeneration: 7).serverThread, 0)
        XCTAssertEqual(inFlightQuery.reservationForKill(ofGeneration: 8).serverThread, 17)

        var marked = false
        inFlightQuery.endKill(forGeneration: 8, succeeded: true) { marked = true }
        XCTAssertTrue(marked)
    }

    /// A failed or late kill marks nothing.
    func testAFailedOrLateKillMarksNothing() {
        var marked: [String] = []
        inFlightQuery.beginWaiting(forGeneration: 8, onSocket: descriptors[0], serverThread: 17)

        XCTAssertEqual(inFlightQuery.reservationForKill(ofGeneration: 8).serverThread, 17)
        inFlightQuery.endKill(forGeneration: 8, succeeded: false) { marked.append("failed") }

        XCTAssertEqual(inFlightQuery.reservationForKill(ofGeneration: 8).serverThread, 17)
        inFlightQuery.endWaiting(forGeneration: 8)
        inFlightQuery.endKill(forGeneration: 8, succeeded: true) { marked.append("late") }

        XCTAssertEqual(marked, [])
    }

    /// A second request waits for the one on its way, and reports what the server told it rather
    /// than a failure of its own: the grace period closes the socket of a query whose kill was not
    /// accepted, which ends the session and rolls back a transaction open in it.
    func testASecondRequestSharesTheAnswerOfTheOneOnItsWay() {
        inFlightQuery.beginWaiting(forGeneration: 8, onSocket: descriptors[0], serverThread: 17)
        XCTAssertEqual(inFlightQuery.reservationForKill(ofGeneration: 8).serverThread, 17)

        // The thread a second Stop for the same query reaches this on.
        let secondAnswered = DispatchSemaphore(value: 0)
        var second: SAKillReservation?
        Thread.detachNewThread {
            second = self.inFlightQuery.reservationForKill(ofGeneration: 8)
            secondAnswered.signal()
        }

        // Nothing is answered while the first request is still on its way.
        XCTAssertEqual(secondAnswered.wait(timeout: .now() + 0.3), .timedOut)

        inFlightQuery.endKill(forGeneration: 8, succeeded: true) {}
        XCTAssertEqual(secondAnswered.wait(timeout: .now() + 2), .success)

        // It sends nothing of its own, and the acceptance is its answer.
        XCTAssertEqual(second?.serverThread, 0)
        XCTAssertEqual(second?.killWasAlreadyAccepted, true)

        // So is it for every request that follows, for as long as that query is the one waiting.
        let later = inFlightQuery.reservationForKill(ofGeneration: 8)
        XCTAssertEqual(later.serverThread, 0)
        XCTAssertTrue(later.killWasAlreadyAccepted)
    }

    /// A caller that cannot reach the server at all reports what a request for the same query
    /// already got, not a failure of its own - and waits for one still on its way.
    func testAnAcceptedKillIsTheAnswerForACallerThatCannotAsk() {
        inFlightQuery.beginWaiting(forGeneration: 8, onSocket: descriptors[0], serverThread: 17)
        XCTAssertFalse(inFlightQuery.killWasAlreadyAccepted(ofGeneration: 8),
                       "nothing has been accepted yet")

        XCTAssertEqual(inFlightQuery.reservationForKill(ofGeneration: 8).serverThread, 17)

        // While that request is on its way, the question is not answered early.
        let answered = DispatchSemaphore(value: 0)
        var accepted: Bool?
        Thread.detachNewThread {
            accepted = self.inFlightQuery.killWasAlreadyAccepted(ofGeneration: 8)
            answered.signal()
        }
        XCTAssertEqual(answered.wait(timeout: .now() + 0.3), .timedOut)

        inFlightQuery.endKill(forGeneration: 8, succeeded: true) {}
        XCTAssertEqual(answered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(accepted, true)

        XCTAssertTrue(inFlightQuery.killWasAlreadyAccepted(ofGeneration: 8))
        XCTAssertFalse(inFlightQuery.killWasAlreadyAccepted(ofGeneration: 9), "another query")
        XCTAssertFalse(inFlightQuery.killWasAlreadyAccepted(ofGeneration: 0), "no query named")
    }

    /// A request the server refused leaves the next one free to send its own.
    func testARequestAfterARefusedOneSendsItsOwn() {
        inFlightQuery.beginWaiting(forGeneration: 8, onSocket: descriptors[0], serverThread: 17)
        XCTAssertEqual(inFlightQuery.reservationForKill(ofGeneration: 8).serverThread, 17)
        inFlightQuery.endKill(forGeneration: 8, succeeded: false) {}

        let next = inFlightQuery.reservationForKill(ofGeneration: 8)
        XCTAssertEqual(next.serverThread, 17)
        XCTAssertFalse(next.killWasAlreadyAccepted)
    }

    /// A query that is no longer waiting leaves nothing to do, and nothing to report.
    func testAQueryThatStoppedWaitingHasNothingToKill() {
        inFlightQuery.beginWaiting(forGeneration: 8, onSocket: descriptors[0], serverThread: 17)
        inFlightQuery.endWaiting(forGeneration: 8)

        let reservation = inFlightQuery.reservationForKill(ofGeneration: 8)
        XCTAssertEqual(reservation.serverThread, 0)
        XCTAssertFalse(reservation.killWasAlreadyAccepted)
    }

    /// A new query waits until a kill has gone out.
    func testANewQueryWaitsUntilAKillHasGoneOut() {
        inFlightQuery.beginWaiting(forGeneration: 8, onSocket: descriptors[0], serverThread: 17)
        XCTAssertEqual(inFlightQuery.reservationForKill(ofGeneration: 8).serverThread, 17)
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
        for generation: UInt in [40, 41, 43] {
            let query = SAInFlightQuery()
            query.noteLatestGeneration(40, ownedByQueryStartedAt: 40)
            query.noteLatestGeneration(41, ownedByQueryStartedAt: 0)
            query.noteLatestGeneration(42, ownedByQueryStartedAt: 42)
            query.noteLatestGeneration(43, ownedByQueryStartedAt: 40)
            query.requestCancellation(ofGeneration: generation)
            XCTAssertTrue(query.cancellationWasRequested(forGenerationsFrom: 40, through: 43), "request for \(generation)")
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

    /// Verifies something recorded about a session is only recorded while that session is still
    /// the current one, and that the check and the recording cannot come apart.
    ///
    /// Reading the token and then acting on the answer is two steps: a reconnect finishing between
    /// them would leave what was recorded about the session that has gone standing against the one
    /// that replaced it - which is how a healthy session comes to be closed and somebody else's
    /// transaction rolled back.
    func testSomethingIsRecordedOnlyWhileItIsStillTheSameSession() throws {
        var descriptors: [Int32] = [0, 0]
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0,
                          "no local socket pair available")
        defer { descriptors.forEach { Darwin.close($0) } }

        let access = SAConnectionSessionAccess()
        try access.trackSocket(descriptors[0], serverThreadID: 11)
        let theSession = access.socketToken

        var recorded = false
        XCTAssertTrue(access.whileStillOnSocket(theSession, perform: { recorded = true }),
                      "it is still that session")
        XCTAssertTrue(recorded)

        // A new session takes its place.
        var replacement: [Int32] = [0, 0]
        try XCTSkipUnless(socketpair(AF_UNIX, SOCK_STREAM, 0, &replacement) == 0,
                          "no local socket pair available")
        defer { replacement.forEach { Darwin.close($0) } }
        try access.trackSocket(replacement[0], serverThreadID: 12)
        XCTAssertNotEqual(access.socketToken, theSession, "the session has been replaced")

        var recordedAgain = false
        XCTAssertFalse(access.whileStillOnSocket(theSession, perform: { recordedAgain = true }),
                       "the session it was about has gone")
        XCTAssertFalse(recordedAgain, "and nothing is recorded against the one that replaced it")
    }
}
