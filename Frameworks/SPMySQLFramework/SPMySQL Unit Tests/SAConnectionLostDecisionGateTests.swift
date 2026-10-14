//
//  SAConnectionLostDecisionGateTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

final class SAConnectionLostDecisionGateTests: XCTestCase {
    private let gate = SAConnectionLostDecisionGate()

    /// Waits until a condition holds, for up to two seconds.
    /// - Parameter condition: What has to hold.
    /// - Returns: Whether it held in time.
    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else {
                return false
            }
            usleep(1_000)
        }
        return true
    }

    /// A lone thread gets its own answer.
    func testALoneThreadGetsItsOwnAnswer() {
        XCTAssertEqual(gate.decision(askingWith: { 2 }), 2)
    }

    /// Threads that lose the connection together share one question.
    func testThreadsThatLoseTheConnectionTogetherShareOneQuestion() {
        let questionIsOpen = DispatchSemaphore(value: 0)
        let userMayAnswer = DispatchSemaphore(value: 0)
        let answersCollected = DispatchGroup()
        let lock = NSLock()
        var questionsAsked = 0
        var answers: [Int] = []

        let askingThread = Thread {
            let answer = self.gate.decision(askingWith: {
                lock.lock()
                questionsAsked += 1
                lock.unlock()
                questionIsOpen.signal()
                userMayAnswer.wait()
                return 1
            })
            lock.lock()
            answers.append(answer)
            lock.unlock()
            answersCollected.leave()
        }
        answersCollected.enter()
        askingThread.start()
        XCTAssertEqual(questionIsOpen.wait(timeout: .now() + 2), .success)

        for _ in 0..<3 {
            answersCollected.enter()
            Thread.detachNewThread {
                let answer = self.gate.decision(askingWith: {
                    lock.lock()
                    questionsAsked += 1
                    lock.unlock()
                    return 99
                })
                lock.lock()
                answers.append(answer)
                lock.unlock()
                answersCollected.leave()
            }
        }

        // The answer is given only once all latecomers are waiting on the open question.
        XCTAssertTrue(waitUntil { self.gate.threadsWaitingForAnswer == 3 })
        userMayAnswer.signal()

        XCTAssertEqual(answersCollected.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(questionsAsked, 1)
        XCTAssertEqual(answers, [1, 1, 1, 1])
    }

    /// A waiting thread takes the answer to the question it waited for, even when the next question
    /// has been asked and answered before it gets to take it.
    func testAWaitingThreadTakesTheAnswerToItsOwnQuestion() {
        for round in 1...50 {
            let questionIsOpen = DispatchSemaphore(value: 0)
            let userMayAnswer = DispatchSemaphore(value: 0)
            let waiterIsDone = DispatchSemaphore(value: 0)
            let askerIsDone = DispatchSemaphore(value: 0)
            let lock = NSLock()
            var waiterAnswer: Int?

            Thread.detachNewThread {
                _ = self.gate.decision(askingWith: {
                    questionIsOpen.signal()
                    userMayAnswer.wait()
                    return round
                })

                // The next loss, answered at once, while the waiting thread is still waking up.
                _ = self.gate.decision(askingWith: { -round })
                askerIsDone.signal()
            }
            XCTAssertEqual(questionIsOpen.wait(timeout: .now() + 2), .success)

            Thread.detachNewThread {
                let answer = self.gate.decision(askingWith: { 0 })
                lock.lock()
                waiterAnswer = answer
                lock.unlock()
                waiterIsDone.signal()
            }
            XCTAssertTrue(waitUntil { self.gate.threadsWaitingForAnswer == 1 })
            userMayAnswer.signal()

            XCTAssertEqual(waiterIsDone.wait(timeout: .now() + 2), .success)
            XCTAssertEqual(askerIsDone.wait(timeout: .now() + 2), .success)
            lock.lock()
            XCTAssertEqual(waiterAnswer, round)
            lock.unlock()
        }
    }

    /// A loss after an answer is asked about again.
    func testALossAfterAnAnswerIsAskedAboutAgain() {
        XCTAssertEqual(gate.decision(askingWith: { 1 }), 1)
        XCTAssertEqual(gate.decision(askingWith: { 0 }), 0)
    }
}

/// Puts the question about a lost connection, which the connection keeps to itself.
@objc private protocol SALostConnectionAsking {
    @objc(_delegateDecisionForLostConnection)
    func askWhatToDoAboutTheLostConnection() -> SPMySQLConnectionLostDecision
}

/// Answers the question about a lost connection, and reports whether the lock that guards the
/// stored answer was free while it was being asked. The question is a sheet, which runs a run loop
/// of its own, so anything that reaches the connection on this thread meanwhile has to find that
/// lock free - it is not recursive, and the thread that holds it is the one inside the sheet.
private final class SAConnectionLostProbingDelegate: NSObject, SPMySQLConnectionDelegate {
    /// The connection to read the lock from.
    weak var connection: SPMySQLConnection?

    /// Whether the lock was free while the question was out; nil until it was asked.
    var lockWasFreeWhileAsking: Bool?

    func connectionLost(_ connection: Any) -> SPMySQLConnectionLostDecision {
        if let lock = self.connection?.value(forKey: "delegateDecisionLock") as? NSLock {
            let taken = lock.try()
            lockWasFreeWhileAsking = taken
            if taken {
                lock.unlock()
            }
        }
        return SPMySQLConnectionLostDisconnect
    }
}

/// Counts how often it was asked about a lost connection.
private final class SAConnectionLostCountingDelegate: NSObject, SPMySQLConnectionDelegate {
    private(set) var timesAsked = 0

    func connectionLost(_ connection: Any) -> SPMySQLConnectionLostDecision {
        timesAsked += 1
        return SPMySQLConnectionLostDisconnect
    }
}

/// A question the user has already declined to wait for is not put to them.
final class SAStoppedQuestionTests: XCTestCase {

    /// Putting the question waits for another modal window to go, for up to five seconds, and the
    /// user can stop waiting in there. Asking anyway shows a dialog about a wait they have ended -
    /// and holds the session until it is answered.
    func testAQuestionIsNotPutToSomebodyWhoHasStoppedWaiting() {
        let connection = SPMySQLConnection()
        let delegate = SAConnectionLostCountingDelegate()
        connection.useKeepAlive = false
        connection.setDelegate(delegate)
        defer { connection.setDelegate(nil) }

        let itCameBack = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            // What the user's Stop leaves behind on the thread that was going to ask.
            Thread.current.cancel()
            _ = unsafeBitCast(connection, to: SALostConnectionAsking.self)
                .askWhatToDoAboutTheLostConnection()
            itCameBack.signal()
        }

        XCTAssertEqual(itCameBack.wait(timeout: .now() + 5), .success,
                       "it comes back instead of waiting out the modal checks")
        XCTAssertEqual(delegate.timesAsked, 0,
                       "and the user is not asked about a wait they have already ended")
    }
}

/// The question about a lost connection is asked with nothing of the connection held.
final class SAConnectionLostQuestionTests: XCTestCase {
    func testTheQuestionIsAskedWithoutHoldingTheStoredAnswersLock() {
        let connection = SPMySQLConnection()
        let delegate = SAConnectionLostProbingDelegate()
        delegate.connection = connection
        connection.useKeepAlive = false
        connection.setDelegate(delegate)
        defer { connection.setDelegate(nil) }

        // The question is put on the thread it is put to the user on, which is this one.
        XCTAssertTrue(Thread.isMainThread)
        let decision = unsafeBitCast(connection, to: SALostConnectionAsking.self)
            .askWhatToDoAboutTheLostConnection()

        XCTAssertEqual(decision, SPMySQLConnectionLostDisconnect, "the delegate's answer is what comes back")
        XCTAssertEqual(delegate.lockWasFreeWhileAsking, true,
                       "a question asked under that lock cannot be asked again from its own run loop")
    }
}
