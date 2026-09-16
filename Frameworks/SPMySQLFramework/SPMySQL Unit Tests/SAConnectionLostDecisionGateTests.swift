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

    func testALoneThreadGetsItsOwnAnswer() {
        XCTAssertEqual(gate.decision(askingWith: { 2 }), 2)
    }

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

        // The latecomers are waiting on the open question by now.
        Thread.sleep(forTimeInterval: 0.2)
        userMayAnswer.signal()

        XCTAssertEqual(answersCollected.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(questionsAsked, 1)
        XCTAssertEqual(answers, [1, 1, 1, 1])
    }

    func testALossAfterAnAnswerIsAskedAboutAgain() {
        XCTAssertEqual(gate.decision(askingWith: { 1 }), 1)
        XCTAssertEqual(gate.decision(askingWith: { 0 }), 0)
    }
}
