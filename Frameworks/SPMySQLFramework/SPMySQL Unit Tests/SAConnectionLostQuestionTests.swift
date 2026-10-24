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

    // MARK: - Through the connection's own hand-off

    /// Stands in for the application's delegate: answers the question on the main thread and
    /// runs the test's own work while it is being asked, which is where the reentry happens.
    private final class AskingDelegate: NSObject {
        var answer: SPMySQLConnectionLostDecision = SPMySQLConnectionLostDisconnect
        var whileBeingAsked: (() -> Void)?
        private(set) var wasAskedOnTheMainThread = false
        private(set) var timesAsked = 0

        @objc func connectionLost(_ connection: Any) -> SPMySQLConnectionLostDecision {
            wasAskedOnTheMainThread = Thread.isMainThread
            timesAsked += 1
            whileBeingAsked?()
            return answer
        }
    }

    /// Verifies the connection's own hand-off brackets the question, so a main-thread caller that
    /// reaches the connection while a background owner waits for the answer is turned away rather
    /// than made to wait.
    ///
    /// This drives `askTheDelegateOnTheMainThread` on a real connection instead of a stand-in, and
    /// never touches `noteAQuestionWentToTheMainThread` itself: a bracket left off the production
    /// path is exactly what a test that called those would still pass without. The ordering is the
    /// one that deadlocks - a background owner holds the session, the question is already open, and
    /// then the main thread comes back in.
    func testTheConnectionsOwnHandOffTurnsAwayAMainThreadCallerWhileTheQuestionIsOpen() throws {
        let connection = SPMySQLConnection()
        connection.useKeepAlive = false
        defer {
            connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
            connection.disconnect()
        }
        let access = try XCTUnwrap(connection.value(forKey: "sessionAccess") as? SAConnectionSessionAccess)
        // Called by selector rather than through the protocol: the connection's conformance is
        // declared in a category that has no implementation of its own, so it is known to the
        // compiler at the ObjC call site but not to the runtime. The selector still reaches the
        // one production method, which is the point of this test.
        let theHandOff = NSSelectorFromString("askTheDelegateOnTheMainThread")
        XCTAssertTrue(connection.responds(to: theHandOff),
                      "the connection still carries out the question's hand-off under this name")

        let delegate = AskingDelegate()
        connection.perform(NSSelectorFromString("setDelegate:"), with: delegate)

        // What the main thread finds when it comes back in while the question is open.
        var theMainThreadWasTurnedAway: Bool?
        var theMainThreadWasRefusedExplicitly: Bool?
        delegate.whileBeingAsked = {
            theMainThreadWasTurnedAway = access.performQuery { "this must not be sent" } == nil
            theMainThreadWasRefusedExplicitly = access.takeTheRefusalOfThisThreadsLastCall()
        }

        // A background owner holds the session, as a thread that lost the connection does.
        let theOwnerHasIt = DispatchSemaphore(value: 0)
        let theOwnerMayGo = DispatchSemaphore(value: 0)
        let theOwnerLetGo = expectation(description: "the owner let the session go")
        Thread.detachNewThread {
            _ = access.reconnect(allowingRetries: true) {
                theOwnerHasIt.signal()
                _ = theOwnerMayGo.wait(timeout: .now() + 10)
                return true
            }
            theOwnerLetGo.fulfill()
        }
        XCTAssertEqual(theOwnerHasIt.wait(timeout: .now() + 10), .success)

        // The question goes out through the connection's own hand-off, from a worker.
        let theQuestionCameBack = expectation(description: "the hand-off returned")
        Thread.detachNewThread {
            connection.perform(theHandOff)
            theQuestionCameBack.fulfill()
        }

        // The hand-off waits on this thread's run loop, so it has to be run for the question to
        // arrive at all - which is what the application's modal loop does.
        let giveUp = Date(timeIntervalSinceNow: 10)
        while delegate.timesAsked == 0 && Date() < giveUp {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        XCTAssertEqual(delegate.timesAsked, 1, "the question reached the delegate")
        XCTAssertTrue(delegate.wasAskedOnTheMainThread, "and it was asked there")
        XCTAssertEqual(theMainThreadWasTurnedAway, true,
                       "the main thread was turned away instead of waiting behind the owner")
        XCTAssertEqual(theMainThreadWasRefusedExplicitly, true,
                       "and it was told so, rather than left to read nothing as a result")

        wait(for: [theQuestionCameBack], timeout: 10)
        XCTAssertEqual(connection.value(forKey: "lastDelegateDecisionForLostConnection") as? Int,
                       Int(SPMySQLConnectionLostDisconnect.rawValue),
                       "the answer was kept for whoever waits on it")

        // Once the question is closed the gate opens again: the refusal was the question's, not
        // a permanent state of the connection.
        theOwnerMayGo.signal()
        wait(for: [theOwnerLetGo], timeout: 5)
        XCTAssertNotNil(access.performQuery { "sent" },
                        "with no question open the main thread gets in again")
    }
}
