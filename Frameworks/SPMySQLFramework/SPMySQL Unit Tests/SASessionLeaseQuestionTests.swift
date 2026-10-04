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
    /// the test instead of holding the suite.
    private let answerLimit = DispatchTime.now() + 10

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
                return true
            }
            ownerHasFinished.withLock { theOwnerHasFinished = true }
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

        Thread.detachNewThread {
            _ = access.reconnect(allowingRetries: true) {
                self.performSelector(onMainThread: #selector(self.answerTheQuestion),
                                     with: nil, waitUntilDone: false)
                theQuestionIsOut.signal()
                if self.theAnswerIsBack.wait(timeout: self.answerLimit) != .success {
                    theOwnerWaitedInVain = true
                }
                return true
            }
            ownerHasFinished.withLock { theOwnerHasFinished = true }
            theOwnerLetGo.fulfill()
        }
        XCTAssertEqual(theQuestionIsOut.wait(timeout: .now() + 5), .success)

        var theTimerRan = false
        var theOwnerHadFinished = false
        let entersTheConnection = Timer(timeInterval: 0.01, repeats: false) { _ in
            _ = access.performQuery {
                theTimerRan = true
                theOwnerHadFinished = ownerHasFinished.withLock { theOwnerHasFinished }
                return nil
            }
        }
        RunLoop.current.add(entersTheConnection, forMode: .default)
        let giveUp = Date(timeIntervalSinceNow: 15)
        while !theTimerRan && Date() < giveUp {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        entersTheConnection.invalidate()

        XCTAssertTrue(theTimerRan, "the timer's work must reach the connection")
        XCTAssertFalse(theOwnerWaitedInVain, "and the question must not be stranded by it")
        XCTAssertTrue(theQuestionWasAnswered)
        XCTAssertTrue(theOwnerHadFinished,
                      "the timer's work must not enter a session the owner is still restoring")
        wait(for: [theOwnerLetGo], timeout: 5)
    }

}
