//
//  SAConnectionLostQuestionTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// Who asks about a lost connection, who waits, and how long the question holds off.
final class SAConnectionLostQuestionTests: XCTestCase {

    /// Stands in for the connection: records what was asked of it and answers as told.
    private final class Host: NSObject, SAConnectionLostQuestionHost {
        private let lock = NSLock()
        private var modalAnswers: [Bool]
        private var _modalChecks = 0
        private var _timesAsked = 0
        var answer = 0
        /// Runs while the question is "on screen", for the nested and shared cases.
        var whileAsking: (() -> Void)?

        init(modalAnswers: [Bool] = [false]) {
            self.modalAnswers = modalAnswers
        }

        func aModalWindowIsShowingOnTheMainThread() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            _modalChecks += 1
            return modalAnswers.isEmpty ? false : modalAnswers.removeFirst()
        }

        func askTheDelegateOnTheMainThread() {
            lock.lock(); _timesAsked += 1; lock.unlock()
            whileAsking?()
        }

        func theAnswerThatWasKept() -> Int { answer }

        var modalChecks: Int { lock.lock(); defer { lock.unlock() }; return _modalChecks }
        var timesAsked: Int { lock.lock(); defer { lock.unlock() }; return _timesAsked }
    }

    // MARK: - From a worker thread

    /// The question is put and its answer returned.
    func testAWorkerThreadGetsTheAnswer() {
        let host = Host()
        host.answer = 2
        let decision = SAConnectionLostQuestion.decision(throughGate: SAConnectionLostDecisionGate(),
                                                         isMainThread: false, host: host)
        XCTAssertEqual(decision, 2)
        XCTAssertEqual(host.timesAsked, 1)
    }

    /// It holds off while something else is modal, and asks once that window has gone.
    func testItWaitsWhileSomethingElseIsModal() {
        let host = Host(modalAnswers: [true, true, false])
        let decision = SAConnectionLostQuestion.decision(throughGate: SAConnectionLostDecisionGate(),
                                                         isMainThread: false, host: host)
        XCTAssertEqual(host.modalChecks, 3, "it looks again until the window has gone")
        XCTAssertEqual(host.timesAsked, 1)
        XCTAssertEqual(decision, 0)
    }

    /// It does not wait for ever: a question that never comes is worse than one that comes while
    /// something else is open.
    func testItGivesUpWaitingAndAsksAnyway() {
        let host = Host(modalAnswers: Array(repeating: true, count: SAConnectionLostQuestion.modalWindowChecks + 5))
        _ = SAConnectionLostQuestion.decision(throughGate: SAConnectionLostDecisionGate(),
                                              isMainThread: false, host: host)
        XCTAssertEqual(host.modalChecks, SAConnectionLostQuestion.modalWindowChecks)
        XCTAssertEqual(host.timesAsked, 1, "the question is put even though the window is still up")
    }

    /// The wait is the one it always was: five seconds' worth of looks.
    func testTheWaitIsFiveSeconds() {
        XCTAssertEqual(Double(SAConnectionLostQuestion.modalWindowChecks)
                        * SAConnectionLostQuestion.modalWindowCheckInterval, 5.0, accuracy: 0.001)
    }

    // MARK: - From the thread the question is shown on

    /// It asks without waiting, and without looking for a modal window - it is the thread that
    /// would be showing one, and it cannot wait for itself.
    func testTheMainThreadAsksWithoutWaiting() {
        let host = Host(modalAnswers: [true, true, true])
        host.answer = 1
        let decision = SAConnectionLostQuestion.decision(throughGate: SAConnectionLostDecisionGate(),
                                                         isMainThread: true, host: host)
        XCTAssertEqual(decision, 1)
        XCTAssertEqual(host.timesAsked, 1)
        XCTAssertEqual(host.modalChecks, 0, "it must not wait on a window it would be showing itself")
    }

    /// Its question still goes through the gate: a worker that loses the connection while it is
    /// open shares that answer rather than queueing a dialog behind it.
    func testAWorkerArrivingDuringThatQuestionSharesItsAnswer() {
        let gate = SAConnectionLostDecisionGate()
        let host = Host()
        host.answer = 3
        let joined = expectation(description: "the worker took the answer")
        var shared = -1
        let questionIsOpen = DispatchSemaphore(value: 0)

        host.whileAsking = {
            DispatchQueue.global().async {
                shared = SAConnectionLostQuestion.decision(throughGate: gate, isMainThread: false,
                                                           host: Host(modalAnswers: [false]))
                joined.fulfill()
            }
            questionIsOpen.signal()
            while gate.threadsWaitingForAnswer < 1 {
                usleep(1000)
            }
        }

        let answered = SAConnectionLostQuestion.decision(throughGate: gate, isMainThread: true, host: host)
        questionIsOpen.wait()
        wait(for: [joined], timeout: 5)
        XCTAssertEqual(answered, 3)
        XCTAssertEqual(shared, 3, "the worker takes the answer to the question it joined")
        XCTAssertEqual(host.timesAsked, 1, "only one question reaches the user")
    }

    /// A second loss on that same thread while its question is open is not put again - that
    /// would wait for an answer only this thread can give.
    func testANestedLossOnThatThreadIsNotAskedAgain() {
        let gate = SAConnectionLostDecisionGate()
        let nestedHost = Host()
        let host = Host()
        host.answer = 1
        host.whileAsking = {
            let nested = SAConnectionLostQuestion.decision(throughGate: gate, isMainThread: true, host: nestedHost)
            XCTAssertEqual(nested, SAConnectionLostDecisionGate.questionPendingAnswer)
        }

        _ = SAConnectionLostQuestion.decision(throughGate: gate, isMainThread: true, host: host)
        XCTAssertEqual(nestedHost.timesAsked, 0, "no second dialog may stack on the first")
    }
}
