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
    /// Checks that a question whose asking ends without an answer does not leave the others waiting.
    ///
    /// The asking thread publishes its question before it asks. If it then ended without an answer
    /// - cancelled while waiting for the main thread, say - the threads waiting on that question
    /// would wait for one that is never coming, and the connection would never ask again.
    func testWaitingThreadsAreReleasedWhenTheAskingEndsWithoutAnAnswer() {
        let questionIsOpen = DispatchSemaphore(value: 0)
        let askerMayAnswer = DispatchSemaphore(value: 0)
        let askerIsDone = DispatchSemaphore(value: 0)
        let waiterIsDone = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var waiterAnswer: Int?

        Thread.detachNewThread {
            _ = self.gate.decision(askingWith: { () -> Int in
                questionIsOpen.signal()
                // held until the other thread is on the question, so the order is not a matter of
                // scheduling
                askerMayAnswer.wait()
                return 7
            })
            askerIsDone.signal()
        }
        XCTAssertEqual(questionIsOpen.wait(timeout: .now() + 2), .success)

        Thread.detachNewThread {
            let answer = self.gate.decision(askingWith: { XCTFail("the second thread must not ask"); return 1 })
            lock.lock()
            waiterAnswer = answer
            lock.unlock()
            waiterIsDone.signal()
        }
        XCTAssertTrue(waitUntil { self.gate.threadsWaitingForAnswer == 1 })
        askerMayAnswer.signal()

        XCTAssertEqual(waiterIsDone.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(askerIsDone.wait(timeout: .now() + 2), .success)
        lock.lock()
        XCTAssertEqual(waiterAnswer, 7, "it takes the answer of the question it waited on")
        lock.unlock()

        // and the gate is free for the next question
        XCTAssertEqual(gate.decision(askingWith: { 3 }), 3)
    }

    /// Checks that the fallback is the answer that gives the connection up.
    // MARK: - The thread the question is put to the user on

    /// It asks without waiting, and its answer is its own.
    func testTheAskingThreadGetsItsOwnAnswer() {
        let gate = SAConnectionLostDecisionGate()
        XCTAssertEqual(gate.decisionAskingHere(with: { 7 }), 7)
    }

    /// Its question goes through the gate, so a thread that loses the connection while the
    /// question is open shares that answer instead of queueing a dialog behind it.
    func testAThreadArrivingDuringThatQuestionSharesItsAnswer() {
        let gate = SAConnectionLostDecisionGate()
        let joined = expectation(description: "the other thread took the answer")
        let questionIsOpen = DispatchSemaphore(value: 0)
        let otherHasJoined = DispatchSemaphore(value: 0)
        var shared = -1

        DispatchQueue.global().async {
            questionIsOpen.wait()
            otherHasJoined.signal()
            shared = gate.decision(askingWith: {
                XCTFail("a question was open, so this thread must not ask its own")
                return 99
            })
            joined.fulfill()
        }

        let answered = gate.decisionAskingHere(with: { () -> Int in
            questionIsOpen.signal()
            otherHasJoined.wait()
            // Wait until that thread is actually waiting on this question, so the test does not
            // depend on how fast it gets there.
            while gate.threadsWaitingForAnswer < 1 {
                usleep(1000)
            }
            return 4
        })

        wait(for: [joined], timeout: 5)
        XCTAssertEqual(answered, 4)
        XCTAssertEqual(shared, 4, "the thread that arrived during the question must take its answer")
    }

    /// A second question from the same thread, while the first is still open, is not put to the
    /// user: that is the nested case - a background thread asked, and the user is answering on
    /// this thread, which then loses the connection itself. Stacking a dialog there would wait
    /// for an answer this thread is the only one able to give.
    func testANestedQuestionOnThatThreadIsNotPutAgain() {
        let gate = SAConnectionLostDecisionGate()
        var nestedWasAsked = false

        let answered = gate.decisionAskingHere(with: { () -> Int in
            let nested = gate.decisionAskingHere(with: { () -> Int in
                nestedWasAsked = true
                return 5
            })
            XCTAssertEqual(nested, SAConnectionLostDecisionGate.fallbackAnswer,
                           "the nested call gets the fallback rather than a second dialog")
            return 3
        })

        XCTAssertFalse(nestedWasAsked, "no second question may reach the user")
        XCTAssertEqual(answered, 3)
    }

    /// Once that question is answered, a later loss is asked about again.
    func testALaterLossIsAskedAboutAgain() {
        let gate = SAConnectionLostDecisionGate()
        XCTAssertEqual(gate.decisionAskingHere(with: { 1 }), 1)
        XCTAssertEqual(gate.decisionAskingHere(with: { 2 }), 2)
        XCTAssertEqual(gate.decision(askingWith: { 6 }), 6)
    }

    func testTheFallbackAnswerGivesTheConnectionUp() {
        XCTAssertEqual(SAConnectionLostDecisionGate.fallbackAnswer, Int(SPMySQLConnectionLostDisconnect.rawValue))
    }


}
