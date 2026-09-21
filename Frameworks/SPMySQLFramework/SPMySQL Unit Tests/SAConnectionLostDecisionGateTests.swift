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
