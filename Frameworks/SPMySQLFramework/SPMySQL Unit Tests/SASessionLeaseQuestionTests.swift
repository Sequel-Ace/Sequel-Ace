//
//  SASessionLeaseQuestionTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
import XCTest
@testable import SPMySQL

/// What happens when the thread that holds the session needs an answer from the main thread,
/// and the main thread is meanwhile waiting for that same session.
///
/// Losing a connection asks the user what to do. The question is put on the main thread, and the
/// thread that lost the connection keeps the session until it has an answer. Anything on the main
/// thread that enters the connection meanwhile waits for the session in the access's own wait.
/// Whether the question can still be reached and answered from inside that wait is what these
/// pin down.
final class SASessionLeaseQuestionTests: XCTestCase {

    /// How long the owner waits for its answer before giving up, so a wait that cannot end fails
    /// the test instead of holding the suite. Measured from the moment it starts waiting: XCTest
    /// builds every test instance before it runs any of them, so a limit fixed here would already
    /// have passed by the time a later test reaches it.
    private var answerLimit: DispatchTime { .now() + 10 }

    /// Answered on the main thread, from wherever the main thread happens to be.
    private var theQuestionReachedTheMainThread = false

    /// Set by the answer, through a loop in a mode of its own.
    private var theQuestionWasAnswered = false

    /// Signalled once the question has been answered, which is what the owner waits for.
    private let theAnswerIsBack = DispatchSemaphore(value: 0)

    /// Puts the question the way the connection does, and answers it the way the application
    /// does: through a nested run loop in the mode a modal panel runs in.
    @objc private func answerTheQuestion() {
        theQuestionReachedTheMainThread = Thread.isMainThread

        // What NSApp.runModal does: a loop of its own, in modal panel mode, which something
        // running in that same mode ends. Nothing in the default mode can end it.
        var theAnswerIsIn = false
        let answer = Timer(timeInterval: 0.05, repeats: false) { _ in theAnswerIsIn = true }
        RunLoop.current.add(answer, forMode: .modalPanel)
        let giveUp = Date(timeIntervalSinceNow: 5)
        while !theAnswerIsIn && Date() < giveUp {
            RunLoop.current.run(mode: .modalPanel, before: Date(timeIntervalSinceNow: 0.05))
        }
        answer.invalidate()
        theQuestionWasAnswered = theAnswerIsIn
        theAnswerIsBack.signal()
    }

    /// The question is reached and answered while the main thread waits for the session, and the
    /// waiting caller goes on only once the owner has let the session go.
    func testTheQuestionIsAnsweredWhileTheMainThreadWaitsForTheSession() throws {
        let access = SAConnectionSessionAccess()
        let theQuestionIsOut = DispatchSemaphore(value: 0)
        let theOwnerLetGo = expectation(description: "the owner let the session go")
        let ownerHasFinished = NSLock()
        var theOwnerHasFinished = false
        var theOwnerWaitedInVain = false

        Thread.detachNewThread {
            _ = access.reconnect(allowingRetries: true) {
                // The owner keeps the session until its question has an answer.
                self.performSelector(onMainThread: #selector(self.answerTheQuestion),
                                     with: nil, waitUntilDone: false)
                theQuestionIsOut.signal()
                if self.theAnswerIsBack.wait(timeout: self.answerLimit) != .success {
                    theOwnerWaitedInVain = true
                }
                // Still inside the lease: the session is restored, and anything let in from here
                // on is let into a finished one. Noted after `reconnect` returns it would be
                // noted after the session was already free, and a caller that correctly got in
                // first would look like one that got in too early.
                ownerHasFinished.withLock { theOwnerHasFinished = true }
                return true
            }
            theOwnerLetGo.fulfill()
        }
        XCTAssertEqual(theQuestionIsOut.wait(timeout: .now() + 5), .success)

        // The main thread enters the connection while the owner holds it.
        var theWaitingCallerRan = false
        var theOwnerHadFinished = false
        _ = access.performQuery {
            theWaitingCallerRan = true
            theOwnerHadFinished = ownerHasFinished.withLock { theOwnerHasFinished }
            return nil
        }

        XCTAssertTrue(theQuestionReachedTheMainThread, "the question has to reach the main thread")
        XCTAssertTrue(theQuestionWasAnswered, "and be answerable from where the main thread is")
        XCTAssertFalse(theOwnerWaitedInVain, "the owner must not wait for an answer that never comes")
        XCTAssertTrue(theWaitingCallerRan)
        XCTAssertTrue(theOwnerHadFinished,
                      "the waiting caller must not enter a session the owner is still restoring")
        wait(for: [theOwnerLetGo], timeout: 5)
    }

    /// A timer that enters the connection on the main thread while the question is unanswered
    /// gets in once the owner lets go, and the question is still answered.
    ///
    /// This is the re-entrant shape: the main thread is not already waiting for the session when
    /// the question goes out, it is running its own loop, and what enters the connection is
    /// something that loop delivers.
    func testATimerEnteringTheConnectionOnTheMainThreadDoesNotStrandTheQuestion() throws {
        let access = SAConnectionSessionAccess()
        let theQuestionIsOut = DispatchSemaphore(value: 0)
        let theOwnerLetGo = expectation(description: "the owner let the session go")
        let ownerHasFinished = NSLock()
        var theOwnerHasFinished = false
        var theOwnerWaitedInVain = false

        // The owner takes the session, then waits for the timer to be in the access's wait before
        // it puts its question. Put first, the question would be delivered by the plain loop
        // below, answered there, and the session let go before the timer ever asked for it - the
        // test would then pass without the wait ever having to carry the question.
        let theTimerIsWaiting = DispatchSemaphore(value: 0)
        let theOwnerHoldsTheSession = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            _ = access.reconnect(allowingRetries: true) {
                theOwnerHoldsTheSession.signal()
                XCTAssertEqual(theTimerIsWaiting.wait(timeout: .now() + 10), .success,
                               "the timer has to reach the session's wait first")
                self.performSelector(onMainThread: #selector(self.answerTheQuestion),
                                     with: nil, waitUntilDone: false)
                theQuestionIsOut.signal()
                if self.theAnswerIsBack.wait(timeout: self.answerLimit) != .success {
                    theOwnerWaitedInVain = true
                }
                // Still inside the lease: the session is restored, and anything let in from here
                // on is let into a finished one. Noted after `reconnect` returns it would be
                // noted after the session was already free, and a caller that correctly got in
                // first would look like one that got in too early.
                ownerHasFinished.withLock { theOwnerHasFinished = true }
                return true
            }
            theOwnerLetGo.fulfill()
        }

        // Not before the owner has the session: a timer that got in first would be let in
        // rightly, and would then look like one let into a session still being restored.
        XCTAssertEqual(theOwnerHoldsTheSession.wait(timeout: .now() + 10), .success)

        var theTimerRan = false
        var theOwnerHadFinished = false
        let entersTheConnection = Timer(timeInterval: 0.01, repeats: false) { _ in
            // Signalled on the step before the wait, so the owner's question arrives while the
            // main thread is inside it and can only be delivered by the wait itself.
            theTimerIsWaiting.signal()
            _ = access.performQuery {
                theTimerRan = true
                theOwnerHadFinished = ownerHasFinished.withLock { theOwnerHasFinished }
                return nil
            }
        }
        RunLoop.current.add(entersTheConnection, forMode: .default)
        let giveUp = Date(timeIntervalSinceNow: 20)
        while !theTimerRan && Date() < giveUp {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        entersTheConnection.invalidate()
        XCTAssertEqual(theQuestionIsOut.wait(timeout: .now() + 5), .success,
                       "the question must have gone out")

        XCTAssertTrue(theTimerRan, "the timer's work must reach the connection")
        XCTAssertFalse(theOwnerWaitedInVain, "and the question must not be stranded by it")
        XCTAssertTrue(theQuestionWasAnswered)
        XCTAssertTrue(theOwnerHadFinished,
                      "the timer's work must not enter a session the owner is still restoring")
        wait(for: [theOwnerLetGo], timeout: 5)
    }


    /// The other ordering: the question is already open when something enters the connection.
    ///
    /// Here the modal loop is the outer one and the session's wait runs inside it, which is what
    /// happens when a callback the modal session delivers asks the connection for something. The
    /// answer is a source in the modal mode, so a wait that pumps only the default mode starves
    /// it: the owner cannot be answered, and it holds the session until it gives up waiting.
    func testACallbackDeliveredByTheOpenQuestionDoesNotStarveTheAnswer() throws {
        let access = SAConnectionSessionAccess()
        let theOwnerHoldsTheSession = DispatchSemaphore(value: 0)
        let theOwnerLetGo = expectation(description: "the owner let the session go")
        var theOwnerWaitedInVain = false

        Thread.detachNewThread {
            _ = access.reconnect(allowingRetries: true) {
                theOwnerHoldsTheSession.signal()
                if self.theAnswerIsBack.wait(timeout: self.answerLimit) != .success {
                    theOwnerWaitedInVain = true
                }
                return true
            }
            theOwnerLetGo.fulfill()
        }
        XCTAssertEqual(theOwnerHoldsTheSession.wait(timeout: .now() + 10), .success)

        // The question is up: from here the main thread is in a loop of its own, in the mode a
        // modal panel runs in, and everything it delivers is delivered in that mode.
        access.noteAQuestionWentToTheMainThread()
        defer { access.noteTheQuestionWasAnswered() }

        var theCallbackReturned = false
        var theCallbacksWorkRan = false
        var theSessionWasRefused = false
        let entersTheConnection = Timer(timeInterval: 0.05, repeats: false) { _ in
            _ = access.performQuery {
                theCallbacksWorkRan = true
                return nil
            }
            theSessionWasRefused = access.takeTheRefusalOfThisThreadsLastCall()
            theCallbackReturned = true
        }
        // The answer comes after it, in the same mode - the order Jason-Morcos reproduced.
        var theUserAnswered = false
        let answer = Timer(timeInterval: 0.15, repeats: false) { _ in theUserAnswered = true }
        RunLoop.current.add(entersTheConnection, forMode: .modalPanel)
        RunLoop.current.add(answer, forMode: .modalPanel)

        // The loop the question runs. What matters is where it ends: the owner is told the
        // answer only once this returns, because production asks with
        // `performSelectorOnMainThread:waitUntilDone:YES` and that call does not come back
        // until `NSApp.runModal` has. Signalling from inside the loop instead would let the
        // owner go while the loop was still running, which is not something that can happen.
        let giveUp = Date(timeIntervalSinceNow: 20)
        while !theUserAnswered && Date() < giveUp {
            RunLoop.current.run(mode: .modalPanel, before: Date(timeIntervalSinceNow: 0.05))
        }
        entersTheConnection.invalidate()
        answer.invalidate()
        theAnswerIsBack.signal()

        XCTAssertTrue(theUserAnswered, "the question has to be answerable")
        XCTAssertTrue(theCallbackReturned,
                      "the callback has to return, so the loop it runs in can end and the "
                      + "answer can reach the owner")
        XCTAssertFalse(theCallbacksWorkRan,
                       "and it is turned away rather than let into the session being asked about")
        XCTAssertTrue(theSessionWasRefused,
                      "the refusal has to be distinguishable from work that ran and did nothing")
        XCTAssertFalse(theOwnerWaitedInVain, "so the owner is answered rather than timing out")
        wait(for: [theOwnerLetGo], timeout: 5)
    }


    /// A refusal speaks for the call it refused, and for no other.
    ///
    /// Waiting for the session pumps the main thread's run loop, so a query delivered in there
    /// can be refused while the call that was waiting goes on to succeed. A mark left behind by
    /// that one would make the outer call's own result read as refused - and a statement that
    /// failed for a reason of its own would be reported as never sent.
    func testARefusalSpeaksOnlyForTheCallItRefused() {
        let access = SAConnectionSessionAccess()
        XCTAssertFalse(access.takeTheRefusalOfThisThreadsLastCall(), "nothing has been refused yet")

        // Refused: a question is out and this is the thread that answers it.
        access.noteAQuestionWentToTheMainThread()
        let theOwner = DispatchSemaphore(value: 0)
        let theOwnerMayGo = DispatchSemaphore(value: 0)
        let theOwnerLetGo = expectation(description: "the owner let the session go")
        Thread.detachNewThread {
            _ = access.reconnect(allowingRetries: true) {
                theOwner.signal()
                _ = theOwnerMayGo.wait(timeout: .now() + 10)
                return true
            }
            theOwnerLetGo.fulfill()
        }
        XCTAssertEqual(theOwner.wait(timeout: .now() + 10), .success)

        var theWorkRan = false
        _ = access.performQuery { theWorkRan = true; return nil }
        XCTAssertFalse(theWorkRan)
        XCTAssertTrue(access.takeTheRefusalOfThisThreadsLastCall(), "that call was refused")

        theOwnerMayGo.signal()
        wait(for: [theOwnerLetGo], timeout: 5)
        access.noteTheQuestionWasAnswered()

        // The next call gets in and fails for a reason of its own. The earlier refusal must not
        // answer for it.
        let result = access.performQuery { nil }
        XCTAssertNil(result)
        XCTAssertFalse(access.takeTheRefusalOfThisThreadsLastCall(),
                       "the statement was sent; what it returned is its own")
    }


    /// A refused statement reports itself, and is not mistaken for one the user stopped.
    ///
    /// Each query clears what the one before it left, but a refused one never gets that far:
    /// it is turned away before the statement is prepared. A stop recorded against an earlier
    /// query would then still stand, and callers that read it alongside the error - the content
    /// view among them - take a cancelled query to be one the user already knows about and stay
    /// quiet. The write would be reported nowhere at all.
    func testARefusedStatementIsNotTakenForOneTheUserStopped() throws {
        let connection = SPMySQLConnection()
        connection.useKeepAlive = false
        defer {
            connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
            connection.disconnect()
        }
        let access = try XCTUnwrap(connection.value(forKey: "sessionAccess") as? SAConnectionSessionAccess)

        // What an earlier query left behind.
        connection.setValue(true, forKey: "lastQueryWasCancelled")
        XCTAssertTrue(connection.lastQueryWasCancelled)

        access.noteAQuestionWentToTheMainThread()
        defer { access.noteTheQuestionWasAnswered() }
        let theOwner = DispatchSemaphore(value: 0)
        let theOwnerMayGo = DispatchSemaphore(value: 0)
        let theOwnerLetGo = expectation(description: "the owner let the session go")
        Thread.detachNewThread {
            _ = access.reconnect(allowingRetries: true) {
                theOwner.signal()
                _ = theOwnerMayGo.wait(timeout: .now() + 10)
                return true
            }
            theOwnerLetGo.fulfill()
        }
        XCTAssertEqual(theOwner.wait(timeout: .now() + 10), .success)

        XCTAssertNil(connection.queryString("UPDATE t SET a = 1"))

        XCTAssertTrue(connection.queryErrored(), "the refusal is an error of its own")
        XCTAssertFalse(connection.lastQueryWasCancelled,
                       "and not a query the user stopped, which callers would say nothing about")
        XCTAssertEqual(connection.rowsAffectedByLastQuery(), 0)

        theOwnerMayGo.signal()
        wait(for: [theOwnerLetGo], timeout: 5)
    }

}

/// Cancelling one caller's call must not cancel the work of another caller on the same session.
///
/// Search in All Tables runs its queries on a background thread, and an MCP request can hold
/// the session while the search waits for it. A plain cancel stops whatever the session runs,
/// which there is the MCP request. These pin down that a cancel tied to the search's thread
/// leaves that request alone.
final class SACallerCancellationTests: XCTestCase {

    private let serverThreadID: UInt = 42
    private var sockets: [Int32] = [-1, -1]

    override func setUpWithError() throws {
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
    }

    override func tearDown() {
        sockets.forEach { if $0 >= 0 { close($0) } }
    }

    private func makeAccess() throws -> SAConnectionSessionAccess {
        let access = SAConnectionSessionAccess()
        try access.trackSocket(sockets[0], serverThreadID: serverThreadID)
        return access
    }

    /// Runs `work` as one native statement inside a query call, as `queryString` does.
    /// - Returns: Whether the statement was let through.
    @discardableResult
    private func runStatement(on access: SAConnectionSessionAccess, _ work: () -> Void = {}) -> Bool {
        var sent = false
        _ = access.performQuery {
            sent = access.beginNativeQuery()
            if sent { work() }
            access.endNativeQuery()
            return nil
        }
        return sent
    }

    /// Stop pressed while the search still waits behind another caller's statement.
    func testStoppingACallThatWaitsForTheSessionLeavesTheCallAheadOfItAlone() throws {
        let access = try makeAccess()
        let theOtherCallRuns = DispatchSemaphore(value: 0)
        let letTheOtherCallFinish = DispatchSemaphore(value: 0)
        let theSearchIsAboutToWait = DispatchSemaphore(value: 0)
        let bothHaveEnded = DispatchGroup()
        var theOtherCallWasCancelled = true
        var theSearchStatementWasSent = true
        var theSearchWasReportedCancelled = false
        var searchThread: Thread?

        bothHaveEnded.enter()
        Thread.detachNewThread {
            self.runStatement(on: access) {
                theOtherCallRuns.signal()
                _ = letTheOtherCallFinish.wait(timeout: .now() + 10)
                theOtherCallWasCancelled = access.currentQueryWasCancelled
            }
            bothHaveEnded.leave()
        }
        XCTAssertEqual(theOtherCallRuns.wait(timeout: .now() + 5), .success)

        bothHaveEnded.enter()
        Thread.detachNewThread {
            searchThread = Thread.current
            theSearchIsAboutToWait.signal()
            _ = access.performQuery {
                theSearchStatementWasSent = access.beginNativeQuery()
                theSearchWasReportedCancelled = access.currentQueryWasCancelled
                access.endNativeQuery()
                return nil
            }
            bothHaveEnded.leave()
        }
        XCTAssertEqual(theSearchIsAboutToWait.wait(timeout: .now() + 5), .success)
        // Give the search time to enter its wait for the session.
        Thread.sleep(forTimeInterval: 0.2)

        var killed = false
        access.cancelQuery(on: try XCTUnwrap(searchThread)) { _ in
            killed = true
            return true
        }
        letTheOtherCallFinish.signal()
        XCTAssertEqual(bothHaveEnded.wait(timeout: .now() + 10), .success)

        XCTAssertFalse(killed, "the statement running was the other caller's")
        XCTAssertFalse(theOtherCallWasCancelled)
        XCTAssertFalse(theSearchStatementWasSent)
        XCTAssertTrue(theSearchWasReportedCancelled)
    }

    /// Stop pressed while the search's own statement runs kills that statement.
    func testStoppingACallWhoseStatementRunsKillsIt() throws {
        let access = try makeAccess()
        let theSearchRuns = DispatchSemaphore(value: 0)
        let letTheSearchFinish = DispatchSemaphore(value: 0)
        let theSearchHasEnded = expectation(description: "the search ended")
        var searchThread: Thread?

        Thread.detachNewThread {
            searchThread = Thread.current
            self.runStatement(on: access) {
                theSearchRuns.signal()
                _ = letTheSearchFinish.wait(timeout: .now() + 10)
            }
            theSearchHasEnded.fulfill()
        }
        XCTAssertEqual(theSearchRuns.wait(timeout: .now() + 5), .success)

        var killedServerThread: UInt?
        access.cancelQuery(on: try XCTUnwrap(searchThread)) { thread in
            killedServerThread = thread
            return true
        }
        letTheSearchFinish.signal()
        wait(for: [theSearchHasEnded], timeout: 10)

        XCTAssertEqual(killedServerThread, serverThreadID)
    }

    /// A stop that arrives after the search's call has ended does not reach the next caller,
    /// even one on the same thread.
    func testStoppingACallThatHasEndedDoesNothing() throws {
        let access = try makeAccess()
        let theOtherCallRuns = DispatchSemaphore(value: 0)
        let letTheOtherCallFinish = DispatchSemaphore(value: 0)
        let theOtherCallHasEnded = expectation(description: "the other call ended")
        var theOtherCallWasCancelled = true
        var nextStatementWasSent = false

        let ended = Thread {
            self.runStatement(on: access)
        }
        ended.start()
        while !ended.isFinished { Thread.sleep(forTimeInterval: 0.01) }

        Thread.detachNewThread {
            self.runStatement(on: access) {
                theOtherCallRuns.signal()
                _ = letTheOtherCallFinish.wait(timeout: .now() + 10)
                theOtherCallWasCancelled = access.currentQueryWasCancelled
            }
            theOtherCallHasEnded.fulfill()
        }
        XCTAssertEqual(theOtherCallRuns.wait(timeout: .now() + 5), .success)

        var killed = false
        access.cancelQuery(on: ended) { _ in
            killed = true
            return true
        }
        letTheOtherCallFinish.signal()
        wait(for: [theOtherCallHasEnded], timeout: 10)
        nextStatementWasSent = runStatement(on: access)

        XCTAssertFalse(killed)
        XCTAssertFalse(theOtherCallWasCancelled)
        XCTAssertTrue(nextStatementWasSent)
    }
}
