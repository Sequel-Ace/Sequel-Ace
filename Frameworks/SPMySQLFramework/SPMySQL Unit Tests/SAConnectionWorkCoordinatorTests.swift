//
//  SAConnectionWorkCoordinatorTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// A connection as the coordinator sees it: scripted readings, a wait that runs the test's own
/// script, and a record of what was asked of it.
private final class SAScriptedWorkHost: NSObject, SAConnectionWorkHost {
    let sessionAccess = SAConnectionSessionAccess()
    var delegateShowsTheWait = true
    var currentThreadIsSettingUpTheSession = false
    /// What the delegate does while it waits; by default it waits for the work.
    var whileWaiting: ((_ isFinished: @escaping () -> Bool) -> Void)?
    private(set) var timesAskedToWait = 0
    private(set) var cancelledWorkRecorded = 0
    private(set) var unsettledWorkRecorded = 0
    private(set) var cancelledAfterSendRecorded = 0

    func waitForWork(untilFinished isFinished: @escaping () -> Bool) {
        timesAskedToWait += 1
        if let whileWaiting {
            whileWaiting(isFinished)
        } else {
            while !isFinished() {
                usleep(1_000)
            }
        }
    }

    func recordWorkAsCancelled() {
        cancelledWorkRecorded += 1
    }

    func recordWorkAsCarriedOutButUnsettled() {
        unsettledWorkRecorded += 1
    }

    func recordWorkAsCancelledAfterTheSend() {
        cancelledAfterSendRecorded += 1
    }
}

/// A connection as the statement call sees it: hands a statement's work to its coordinator the way
/// the connection does from a thread outside any work, and runs it where it is from inside work -
/// a statement the connection runs for itself on the worker - and keeps the last outcome to look at.
private final class SAScriptedStatementHost: NSObject, SAStatementCallHost {
    let sessionAccess = SAConnectionSessionAccess()
    let coordinator = SAConnectionWorkCoordinator()
    private(set) var lastOutcome: SAConnectionWorkOutcome?
    var insertIDCarried: UInt64 = 0
    var reportFromTheConnectionsFields: SAStatementReport {
        SAStatementReport(errorMessage: nil, errorID: 0, sqlState: nil, affectedRows: 0, insertID: 0, wasCancelled: false)
    }

    func forgetAnExplicitStop() {}

    func runConnectionWorkKeepingInterfaceAlive(_ work: @escaping () -> Bool) -> Bool {
        work()
    }

    func runWorkKeepingInterfaceAlive(_ work: @escaping () -> Any?) -> Any? {
        if SAConnectionWorkCoordinator.tokenOfWorkOnThisThread != nil {
            return work()
        }
        let outcome = coordinator.run(work, whenSlow: { isFinished in
            while !isFinished() {
                usleep(1_000)
            }
        })
        lastOutcome = outcome
        return outcome.result
    }
}

/// Hands work over the way the connection does, through its private method.
@objc private protocol SAWorkHandOff {
    @objc(_runWorkKeepingInterfaceAlive:)
    func runWorkKeepingInterfaceAlive(_ work: @escaping () -> Any?) -> Any?
}

/// Reconnects the way the connection does, through its private method.
@objc private protocol SAReconnectHandOff {
    @objc(_reconnectAllowingRetries:)
    func reconnect(allowingRetries: Bool) -> Bool
}

/// A connection whose thread is given up on while its handshake is under way - which does not
/// interrupt the handshake: it comes up all the same - and that sets no session up.
private final class SALateHandshakeConnection: SPMySQLConnection {
    private(set) var handshakes = 0
    private(set) var restoresAttempted = 0

    @objc(_connectUsingConnectTimeout:) func handshake(_ connectTimeoutOrZero: UInt) -> Bool {
        handshakes += 1
        // The user stops waiting while the handshake is under way.
        Thread.current.cancel()
        setValue(SPMySQLConnected.rawValue, forKey: "state")
        return true
    }

    @objc(_waitForNetworkConnectionWithTimeout:) func waitForNetwork(_ timeout: Double) -> Bool {
        true
    }

    @objc(_disconnectPreservingProxyReconnect:) func closeSession(_ preserveProxy: Bool) {
        setValue(SPMySQLDisconnected.rawValue, forKey: "state")
    }

    @objc(_restoreSessionStateAfterReconnectWithDatabase:encoding:encodingUsesLatin1Transport:timeZoneIdentifier:)
    func restore(_ database: String?, encoding: String?, encodingUsesLatin1Transport: Bool, timeZoneIdentifier: String?) -> Bool {
        restoresAttempted += 1
        return true
    }
}

/// A connection whose reconnect comes up and whose thread is given up on during the restore - the
/// user stops waiting while the database is being selected, which the restore's statements, turned
/// away, cannot report; the restore itself reports success.
private final class SAStoppedDuringRestoreConnection: SPMySQLConnection {
    private(set) var databasesAskedToRestore: [String] = []
    private var pair: [Int32] = [-1, -1]

    deinit {
        pair.filter { $0 >= 0 }.forEach { Darwin.close($0) }
    }

    @objc(_connectUsingConnectTimeout:) func handshake(_ connectTimeoutOrZero: UInt) -> Bool {
        setValue(SPMySQLConnected.rawValue, forKey: "state")
        return true
    }

    @objc(_waitForNetworkConnectionWithTimeout:) func waitForNetwork(_ timeout: Double) -> Bool {
        true
    }

    @objc(_disconnectPreservingProxyReconnect:) func closeSession(_ preserveProxy: Bool) {
        setValue(SPMySQLDisconnected.rawValue, forKey: "state")
    }

    /// A socket of the test's own for the restore's deadline to be armed on, there being no session.
    @objc(_socketForSetupDeadline) func socketForSetupDeadline() -> Int32 {
        if pair[0] < 0 {
            _ = socketpair(AF_UNIX, SOCK_STREAM, 0, &pair)
        }
        return pair[0]
    }

    @objc(_restoreSessionStateAfterReconnectWithDatabase:encoding:encodingUsesLatin1Transport:timeZoneIdentifier:)
    func restore(_ database: String?, encoding: String?, encodingUsesLatin1Transport: Bool, timeZoneIdentifier: String?) -> Bool {
        databasesAskedToRestore.append(database ?? "")
        // The user stops waiting while the database is being selected: the statement is turned
        // away, which the restore does not notice.
        Thread.current.cancel()
        return true
    }
}

/// A connection whose reconnect's thread is given up on while the new session is being set up: the
/// setup fails as an attempt that never came up and closes the session, as the connection's does.
private final class SAStoppedDuringSetupConnection: SPMySQLConnection {
    @objc(_connectUsingConnectTimeout:) func handshakeThenSetupGivenUpOn(_ connectTimeoutOrZero: UInt) -> Bool {
        // The user stops waiting during the setup statements; the setup fails and closes the session.
        Thread.current.cancel()
        setValue(SPMySQLDisconnected.rawValue, forKey: "state")
        return false
    }

    @objc(_waitForNetworkConnectionWithTimeout:) func waitForNetwork(_ timeout: Double) -> Bool {
        true
    }

    @objc(_disconnectPreservingProxyReconnect:) func closeSession(_ preserveProxy: Bool) {
        setValue(SPMySQLDisconnected.rawValue, forKey: "state")
    }
}

/// Where connection work runs, who waits for it, and what a stop makes of it.
final class SAConnectionWorkCoordinatorTests: XCTestCase {
    private let coordinator = SAConnectionWorkCoordinator()

    /// Waits for the work the way the application's wait sheet does.
    ///
    /// The coordinator gives up on work that is still running when the interface's wait returns,
    /// and that is only 0.15 s after the hand-off. Trivial work can exceed it on a loaded machine -
    /// starting the worker thread alone can - so a test that asks for the work's result says here
    /// that it waits for it. A test about work being given up on keeps the default instead.
    private static let waitingForTheWork: (_ isFinished: @escaping () -> Bool) -> Void = { isFinished in
        while !isFinished() {
            usleep(1_000)
        }
    }

    /// Runs work with an interface that never waits unless told to.
    private func run(_ work: @escaping () -> Any?,
                     whenSlow: (_ isFinished: @escaping () -> Bool) -> Void = { _ in }) -> SAConnectionWorkOutcome {
        coordinator.run(work, whenSlow: whenSlow)
    }

    // MARK: - The worker and the wait

    /// Quick work is never handed to the interface. Quick is measured against the coordinator's
    /// quiet wait, which is given room here: on a loaded machine starting the worker thread alone
    /// can take longer than the default, and the test is about the rule, not the machine.
    func testQuickWorkIsNeverHandedToTheInterface() {
        coordinator.quietWait = 5
        var interfaceWasAsked = false
        let outcome = run({ "done" }, whenSlow: { _ in interfaceWasAsked = true })

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? String, "done")
        XCTAssertFalse(interfaceWasAsked)
    }

    /// Work runs away from the calling thread.
    func testWorkRunsAwayFromTheCallingThread() {
        let callingThread = Thread.current
        let outcome = run({ Thread.current == callingThread }, whenSlow: Self.waitingForTheWork)

        XCTAssertEqual(outcome.result as? Bool, false)
    }

    /// Slow work is waited for by the interface, and still answers.
    func testSlowWorkIsWaitedForByTheInterface() {
        var interfaceWasAsked = false
        let outcome = run({
            Thread.sleep(forTimeInterval: 0.4)
            return "late"
        }, whenSlow: { isFinished in
            interfaceWasAsked = true
            while !isFinished() {
                usleep(5_000)
            }
        })

        XCTAssertTrue(interfaceWasAsked)
        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? String, "late")
    }

    /// An interface that stops waiting gets no result - not even once the work has returned.
    func testAnInterfaceThatStopsWaitingGetsNoResult() {
        let workStarted = DispatchSemaphore(value: 0)
        let workMayFinish = DispatchSemaphore(value: 0)
        let workReturned = DispatchSemaphore(value: 0)

        let outcome = run({
            workStarted.signal()
            workMayFinish.wait()
            workReturned.signal()
            return "too late"
        }, whenSlow: { _ in
            // The interface stops waiting only once the work is running: a worker thread that is
            // let go before it has begun never runs what was queued for it.
            XCTAssertEqual(workStarted.wait(timeout: .now() + 5), .success, "the work has started")
        })

        XCTAssertFalse(outcome.finished)
        XCTAssertTrue(outcome.wasAbandoned)
        XCTAssertNil(outcome.result)

        workMayFinish.signal()
        XCTAssertEqual(workReturned.wait(timeout: .now() + 2), .success)
        XCTAssertNil(outcome.result, "what the work returns afterwards is nobody's answer")
    }

    /// Work is not abandoned on the caller's thread.
    func testWorkIsNotAbandonedOnTheCallersThread() {
        XCTAssertFalse(SAConnectionWorkCoordinator.currentWorkHasBeenAbandoned)
    }

    /// Work that was abandoned does not hold up what follows: the next piece gets a thread of its own.
    func testWorkThatWasAbandonedDoesNotHoldUpWhatFollows() {
        let stuckWorkBegan = DispatchSemaphore(value: 0)
        let stuckWorkMayFinish = DispatchSemaphore(value: 0)
        defer { stuckWorkMayFinish.signal() }

        _ = run({
            stuckWorkBegan.signal()
            stuckWorkMayFinish.wait()
            return nil
        }, whenSlow: { _ in
            // The user stops waiting once the work is stuck on its thread - not before it began,
            // when a stop would discard it unrun and prove nothing about the thread.
            XCTAssertEqual(stuckWorkBegan.wait(timeout: .now() + 2), .success)
        })

        let outcome = run({ "next" }, whenSlow: { isFinished in
            let deadline = Date(timeIntervalSinceNow: 5)
            while !isFinished() && Date() < deadline {
                usleep(1_000)
            }
            XCTAssertTrue(isFinished(), "the next piece of work got a thread of its own")
        })

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? String, "next")
    }

    /// Work the user stops never counts as finished, even when it returns before the waiting ends.
    func testWorkStoppedByTheUserNeverCountsAsFinished() {
        let workStarted = DispatchSemaphore(value: 0)
        let workReturned = DispatchSemaphore(value: 0)
        var waitEndedAtOnce = false
        let outcome = run({
            workStarted.signal()
            // Stands in for work that notices the stop and returns early without saying why.
            while !Thread.current.isCancelled {
                usleep(1_000)
            }
            workReturned.signal()
            return "stopped early"
        }, whenSlow: { isFinished in
            XCTAssertEqual(workStarted.wait(timeout: .now() + 5), .success, "the work has started")
            coordinator.abandonWorkForUserStop()
            waitEndedAtOnce = isFinished()

            // The work returns before the interface is done with its wait.
            XCTAssertEqual(workReturned.wait(timeout: .now() + 2), .success)
        })

        XCTAssertTrue(waitEndedAtOnce)
        XCTAssertFalse(outcome.finished)
        XCTAssertTrue(outcome.wasAbandoned)
        // The late result is read only once the worker has stored it: a result exposed during
        // publication would otherwise slip past this.
        let published = Date(timeIntervalSinceNow: 2)
        while !outcome.hasFinishedItsWork && Date() < published {
            usleep(1_000)
        }
        XCTAssertTrue(outcome.hasFinishedItsWork, "the worker stored the late result")
        XCTAssertNil(outcome.result, "which stays nobody's")
    }

    /// Work the user stopped knows it, once it looks: the lease turns its thread away.
    func testWorkTheUserStoppedKnowsItHasBeenAbandoned() {
        let workStarted = DispatchSemaphore(value: 0)
        let noticed = DispatchSemaphore(value: 0)
        var abandonedWhenItLooked = false
        _ = run({
            workStarted.signal()
            while !Thread.current.isCancelled {
                usleep(1_000)
            }
            abandonedWhenItLooked = SAConnectionWorkCoordinator.currentWorkHasBeenAbandoned
            noticed.signal()
            return nil
        }, whenSlow: { _ in
            XCTAssertEqual(workStarted.wait(timeout: .now() + 5), .success, "the work has started")
            coordinator.abandonWorkForUserStop()
        })

        guard noticed.wait(timeout: .now() + 2) == .success else {
            XCTFail("the work did not look in time")
            return
        }
        XCTAssertTrue(abandonedWhenItLooked)
    }

    /// The next piece of work still runs after a cancellation.
    func testTheNextPieceOfWorkStillRunsAfterACancellation() {
        coordinator.cancel()

        let outcome = run({ 42 }, whenSlow: Self.waitingForTheWork)

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? Int, 42)
    }

    // MARK: - Whether work is handed over at all

    /// Work asked for away from the main thread runs where it was asked for.
    func testWorkAwayFromTheMainThreadIsNotHandedOver() {
        XCTAssertFalse(SAConnectionWorkCoordinator.workShouldRunOffMainThread(
            isMainThread: false, delegateShowsTheWait: true, threadIsSettingUpTheSession: false))
    }

    /// Without a delegate there is nobody to show the wait, so there is nothing to gain.
    func testWorkIsNotHandedOverWithNobodyToShowTheWait() {
        XCTAssertFalse(SAConnectionWorkCoordinator.workShouldRunOffMainThread(
            isMainThread: true, delegateShowsTheWait: false, threadIsSettingUpTheSession: false))
    }

    /// Main-thread work that would wait for a server is handed over.
    func testMainThreadWorkIsHandedOver() {
        XCTAssertTrue(SAConnectionWorkCoordinator.workShouldRunOffMainThread(
            isMainThread: true, delegateShowsTheWait: true, threadIsSettingUpTheSession: false))
    }

    /// The thread setting the new session up keeps its own queries.
    ///
    /// It holds the session until its setup is done, so a setup query handed to another thread
    /// would wait there for a session held by the thread waiting for that query.
    func testTheThreadSettingUpTheSessionKeepsItsOwnQueries() {
        XCTAssertFalse(SAConnectionWorkCoordinator.workShouldRunOffMainThread(
            isMainThread: true, delegateShowsTheWait: true, threadIsSettingUpTheSession: true),
                       "a main-thread reconnect's setup query must not be handed over")
        XCTAssertFalse(SAConnectionWorkCoordinator.workShouldRunOffMainThread(
            isMainThread: false, delegateShowsTheWait: true, threadIsSettingUpTheSession: true))
    }

    /// Only the thread that answers is turned away, and only while a question is out.
    func testOnlyTheAnsweringThreadIsTurnedAwayAndOnlyWhileAQuestionIsOut() {
        XCTAssertTrue(SAConnectionWorkCoordinator.mainThreadWorkMustBeRefused(
            isMainThread: true, aQuestionAwaitsTheMainThread: true))
        XCTAssertFalse(SAConnectionWorkCoordinator.mainThreadWorkMustBeRefused(
            isMainThread: true, aQuestionAwaitsTheMainThread: false),
            "with no question out the main thread hands its work over as before")
        XCTAssertFalse(SAConnectionWorkCoordinator.mainThreadWorkMustBeRefused(
            isMainThread: false, aQuestionAwaitsTheMainThread: true),
            "a worker does not answer the question, so it may wait for the session")
    }

    // MARK: - The work for a host

    /// Work for a host runs on the worker, with the host's delegate waiting, and answers.
    func testWorkForAHostRunsOnTheWorkerAndAnswers() {
        let host = SAScriptedWorkHost()
        let callingThread = Thread.current

        let result = coordinator.run({
            Thread.sleep(forTimeInterval: 0.3)
            return Thread.current == callingThread ? "here" : "elsewhere"
        }, on: host)

        XCTAssertEqual(result as? String, "elsewhere")
        XCTAssertEqual(host.timesAskedToWait, 1)
        XCTAssertEqual(host.cancelledWorkRecorded, 0)
    }

    /// Without a delegate to show the wait the work runs where it was asked for, and nobody waits.
    func testWorkRunsWhereItWasAskedForWithNobodyToShowTheWait() {
        let host = SAScriptedWorkHost()
        host.delegateShowsTheWait = false
        let callingThread = Thread.current

        let result = coordinator.run({ Thread.current == callingThread ? "here" : "elsewhere" }, on: host)

        XCTAssertEqual(result as? String, "here")
        XCTAssertEqual(host.timesAskedToWait, 0)
    }

    /// The thread setting the session up keeps its own work, delegate or not.
    func testTheReconnectingThreadKeepsItsOwnWork() {
        let host = SAScriptedWorkHost()
        host.currentThreadIsSettingUpTheSession = true
        let callingThread = Thread.current

        let result = coordinator.run({ Thread.current == callingThread ? "here" : "elsewhere" }, on: host)

        XCTAssertEqual(result as? String, "here")
        XCTAssertEqual(host.timesAskedToWait, 0)
    }

    /// Work the user stopped waiting for is recorded as cancelled, and nothing is returned for it.
    func testWorkTheUserStoppedWaitingForIsRecordedAsCancelled() {
        let host = SAScriptedWorkHost()
        host.whileWaiting = { [coordinator] _ in
            coordinator.abandonWorkForUserStop()
        }

        let result = coordinator.run({
            while !Thread.current.isCancelled {
                usleep(1_000)
            }
            return "stopped early"
        }, on: host)

        XCTAssertNil(result)
        XCTAssertEqual(host.cancelledWorkRecorded, 1)
    }

    /// A stop that comes once the work has finished - in the moment before the interface notices -
    /// gives nothing up: the work's caller gets its result, and nothing of the work's is there to
    /// be stopped on the server.
    func testAStopAfterTheWorkFinishedGivesNothingUp() {
        let host = SAScriptedWorkHost()
        var abandoned: [UInt64]?
        host.whileWaiting = { [coordinator] isFinished in
            while !isFinished() {
                usleep(1_000)
            }
            abandoned = coordinator.abandonWorkForUserStopReturningAbandonedTokens()
        }

        let result = coordinator.run({
            usleep(300_000)
            return "answered"
        }, on: host)

        XCTAssertEqual(result as? String, "answered")
        XCTAssertEqual(abandoned, [])
        XCTAssertEqual(host.cancelledWorkRecorded, 0)
    }

    /// Work the main thread would hand over while a question is out to it is refused before
    /// anything is enqueued, and marked as refused, so the statement path reports it as not sent.
    func testMainThreadWorkIsRefusedAndMarkedWhileAQuestionIsOut() {
        let host = SAScriptedWorkHost()
        host.sessionAccess.noteAQuestionWentToTheMainThread()
        defer { host.sessionAccess.noteTheQuestionWasAnswered() }
        var theWorkRan = false

        let result = coordinator.run({
            theWorkRan = true
            return "answered"
        }, on: host)

        XCTAssertNil(result)
        XCTAssertFalse(theWorkRan)
        XCTAssertTrue(host.sessionAccess.takeTheRefusalOfThisThreadsLastCall(), "marked as refused, for the statement path")
        XCTAssertEqual(host.timesAskedToWait, 0)
        XCTAssertEqual(host.cancelledWorkRecorded, 0, "a refusal is not a stop")
    }

    /// Once the question is answered the main thread hands its work over again.
    func testMainThreadWorkIsHandedOverAgainOnceTheQuestionIsAnswered() {
        let host = SAScriptedWorkHost()
        host.sessionAccess.noteAQuestionWentToTheMainThread()
        host.sessionAccess.noteTheQuestionWasAnswered()

        let result = coordinator.run({ "answered" }, on: host)

        XCTAssertEqual(result as? String, "answered")
        XCTAssertFalse(host.sessionAccess.takeTheRefusalOfThisThreadsLastCall())
    }

    /// Work asked for during this thread's own wait - by an event the wait delivered - is refused
    /// rather than queued, and the refusal says so: queued behind a statement whose result keeps
    /// the session until the waiting caller reads it, it would wait for that caller.
    func testWorkAskedForDuringThisThreadsOwnWaitIsRefused() {
        let host = SAScriptedWorkHost()
        var nestedResult: Any? = "unset"
        var nestedWasRefusedForEarlierWork: Bool?
        var nestedWasMarkedRefused: Bool?
        host.whileWaiting = { [coordinator] isFinished in
            nestedResult = coordinator.run({ "nested" }, on: host)
            nestedWasRefusedForEarlierWork = host.sessionAccess.thisThreadsLastCallWasRefusedWhileWaitingForEarlierWork
            nestedWasMarkedRefused = host.sessionAccess.takeTheRefusalOfThisThreadsLastCall()
            while !isFinished() {
                usleep(1_000)
            }
        }

        let outerResult = coordinator.run({
            Thread.sleep(forTimeInterval: 0.3)
            return "outer"
        }, on: host)

        XCTAssertNil(nestedResult, "the nested work was refused")
        XCTAssertEqual(nestedWasMarkedRefused, true, "and marked refused for the statement path")
        XCTAssertEqual(nestedWasRefusedForEarlierWork, true, "with its reason")
        XCTAssertEqual(outerResult as? String, "outer", "the work being waited for answered")
        XCTAssertEqual(host.cancelledWorkRecorded, 0)
    }

    /// Work asked for on the main thread while another thread is waiting for work is not nested
    /// work: it is handed over as usual - to the worker, the delegate waiting - and answers.
    func testWorkFromAnotherThreadDuringTheWaitIsHandedOverAsUsual() {
        let outerWaitIsOn = DispatchSemaphore(value: 0)
        let letTheOuterWorkEnd = DispatchSemaphore(value: 0)
        let outerReturned = DispatchSemaphore(value: 0)
        defer { letTheOuterWorkEnd.signal() }
        var outerResult: Any?

        // Another thread asks for work and waits for it.
        Thread.detachNewThread { [coordinator] in
            outerResult = coordinator.run({
                _ = letTheOuterWorkEnd.wait(timeout: .now() + 10)
                return "outer"
            }, whenSlow: { isFinished in
                outerWaitIsOn.signal()
                let deadline = Date(timeIntervalSinceNow: 10)
                while !isFinished() && Date() < deadline {
                    usleep(1_000)
                }
                XCTAssertTrue(isFinished(), "the outer work finished")
            }).result
            outerReturned.signal()
        }
        XCTAssertEqual(outerWaitIsOn.wait(timeout: .now() + 5), .success, "the other thread is waiting for its work")

        // This thread's work, with a delegate to show the wait, goes through the hand-off: it is
        // queued behind the outer work on the worker, and this thread's wait lets that work end.
        let host = SAScriptedWorkHost()
        host.whileWaiting = { isFinished in
            letTheOuterWorkEnd.signal()
            let deadline = Date(timeIntervalSinceNow: 10)
            while !isFinished() && Date() < deadline {
                usleep(1_000)
            }
        }
        let result = coordinator.run({ "this thread's" }, on: host)

        XCTAssertEqual(result as? String, "this thread's", "handed over and answered, not refused")
        XCTAssertEqual(host.timesAskedToWait, 1, "through the hand-off, waited for")
        XCTAssertEqual(host.cancelledWorkRecorded, 0)
        guard outerReturned.wait(timeout: .now() + 5) == .success else {
            XCTFail("the other thread's work did not return in time")
            return
        }
        XCTAssertEqual(outerResult as? String, "outer")
    }

    /// A session that comes up after its reconnect was given up on is retired, not kept half set
    /// up: the thread the user stopped waiting for does not set the new session up, and a
    /// statement would otherwise run on the server's default database and time zone.
    func testASessionThatComesUpAfterItsReconnectWasGivenUpOnIsRetired() {
        let connection = SALateHandshakeConnection()
        connection.useKeepAlive = false
        connection.setValue(SPMySQLConnectionLostInBackground.rawValue, forKey: "state")
        defer {
            connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
            connection.disconnect()
        }
        let looked = expectation(description: "the given-up thread reconnected")
        var reconnected: Bool?
        var stateAfterwards: Int?

        Thread.detachNewThread {
            // The thread is given up on inside the handshake, which still comes up.
            reconnected = unsafeBitCast(connection, to: SAReconnectHandOff.self).reconnect(allowingRetries: true)
            stateAfterwards = connection.value(forKey: "state") as? Int
            looked.fulfill()
        }

        guard XCTWaiter.wait(for: [looked], timeout: 5) == .completed else {
            XCTFail("the reconnect did not return in time; its worker may still be using the connection")
            return
        }
        XCTAssertEqual(connection.handshakes, 1, "the handshake came up")
        XCTAssertEqual(connection.restoresAttempted, 0, "nobody set the session up")
        XCTAssertEqual(reconnected, false, "so the reconnect did not succeed")
        XCTAssertEqual(stateAfterwards, Int(SPMySQLConnectionLostInBackground.rawValue),
                       "and the session is retired, for the next use to reconnect and restore")
    }

    /// A reconnect whose thread is given up on during the restore - the user stops waiting while
    /// the database is being selected - does not count as restored, whatever the restore reported:
    /// its statements were turned away. The session is retired with the saved state kept, for the
    /// next use to reconnect and restore.
    func testAReconnectGivenUpOnDuringTheRestoreIsRetiredWithItsSavedState() {
        let connection = SAStoppedDuringRestoreConnection()
        connection.useKeepAlive = false
        connection.setValue(SPMySQLConnectionLostInBackground.rawValue, forKey: "state")
        // The session being reconnected had a database selected, which the reconnect saves to restore.
        connection.setValue("sa_restore_me", forKey: "database")
        defer {
            connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
            connection.disconnect()
        }
        let looked = expectation(description: "the reconnect returned")
        var reconnected: Bool?
        var stateAfterwards: Int?
        var databaseKept: String?

        Thread.detachNewThread {
            reconnected = unsafeBitCast(connection, to: SAReconnectHandOff.self).reconnect(allowingRetries: true)
            stateAfterwards = connection.value(forKey: "state") as? Int
            databaseKept = connection.value(forKey: "databaseToRestore") as? String
            looked.fulfill()
        }

        guard XCTWaiter.wait(for: [looked], timeout: 5) == .completed else {
            XCTFail("the reconnect did not return in time; its worker may still be using the connection")
            return
        }
        XCTAssertEqual(connection.databasesAskedToRestore, ["sa_restore_me"], "the restore ran, and was stopped during it")
        XCTAssertEqual(reconnected, false, "a restore by a thread given up on does not count")
        XCTAssertEqual(stateAfterwards, Int(SPMySQLConnectionLostInBackground.rawValue), "the session is retired")
        XCTAssertEqual(databaseKept, "sa_restore_me", "with the saved state kept for the next reconnect")
    }

    /// A reconnect given up on while its session was being set up - the setup failed and closed
    /// the session - leaves the connection recoverable: the next use reconnects and restores, with
    /// the saved state still there, rather than finding a disconnected connection nobody reconnects.
    func testAReconnectGivenUpOnDuringTheSetupStaysRecoverable() {
        let connection = SAStoppedDuringSetupConnection()
        connection.useKeepAlive = false
        connection.setValue(SPMySQLConnectionLostInBackground.rawValue, forKey: "state")
        connection.setValue("sa_restore_me", forKey: "database")
        defer {
            connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
            connection.disconnect()
        }
        let looked = expectation(description: "the reconnect returned")
        var reconnected: Bool?
        var stateAfterwards: Int?
        var databaseKept: String?

        Thread.detachNewThread {
            reconnected = unsafeBitCast(connection, to: SAReconnectHandOff.self).reconnect(allowingRetries: true)
            stateAfterwards = connection.value(forKey: "state") as? Int
            databaseKept = connection.value(forKey: "databaseToRestore") as? String
            looked.fulfill()
        }

        guard XCTWaiter.wait(for: [looked], timeout: 5) == .completed else {
            XCTFail("the reconnect did not return in time; its worker may still be using the connection")
            return
        }
        XCTAssertEqual(reconnected, false, "the reconnect did not succeed")
        XCTAssertEqual(stateAfterwards, Int(SPMySQLConnectionLostInBackground.rawValue),
                       "but the connection is left for the next use to reconnect and restore")
        XCTAssertEqual(databaseKept, "sa_restore_me", "with the saved state kept")
    }

    /// Work whose statement the server has answered, with nothing left to fetch, is settling: the
    /// user's stop leaves it the moment it still needs, and its result - a write the server applied -
    /// reaches its caller rather than a stop.
    func testWorkSettlingItsStatementIsWaitedOutRatherThanGivenUpOn() {
        let host = SAScriptedWorkHost()
        let theWorkIsSettling = DispatchSemaphore(value: 0)
        let letTheWorkEnd = DispatchSemaphore(value: 0)
        host.whileWaiting = { _ in
            // The user stops waiting as soon as the sheet is up - with the statement answered already;
            // the statement takes a moment longer to settle.
            XCTAssertEqual(theWorkIsSettling.wait(timeout: .now() + 2), .success)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { letTheWorkEnd.signal() }
        }

        let result = coordinator.run({
            // The server answered the write; the statement takes a moment longer to settle.
            SAConnectionWorkCoordinator.noteStatementOfCurrentWorkAnswered()
            theWorkIsSettling.signal()
            letTheWorkEnd.wait()
            return "applied"
        }, on: host)

        XCTAssertEqual(result as? String, "applied", "the result reached its caller")
        XCTAssertEqual(host.cancelledWorkRecorded, 0, "and nothing was recorded as cancelled")
        XCTAssertEqual(host.unsettledWorkRecorded, 0)
        XCTAssertEqual(host.timesAskedToWait, 1)
    }

    /// Settling work that outlives the grace is not given up on either: its caller is told the
    /// statement was carried out and its result not read - not a stop, since the write stands.
    func testWorkSettlingItsStatementPastTheGraceIsRecordedAsCarriedOutNotCancelled() {
        let host = SAScriptedWorkHost()
        let theWorkIsSettling = DispatchSemaphore(value: 0)
        let letTheWorkEnd = DispatchSemaphore(value: 0)
        defer { letTheWorkEnd.signal() }
        host.whileWaiting = { _ in
            XCTAssertEqual(theWorkIsSettling.wait(timeout: .now() + 2), .success)
        }

        let started = Date()
        let result = coordinator.run({
            SAConnectionWorkCoordinator.noteStatementOfCurrentWorkAnswered()
            theWorkIsSettling.signal()
            letTheWorkEnd.wait()
            return "applied"
        }, on: host)

        XCTAssertNil(result, "nothing was read in time")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), SAConnectionWorkCoordinator.settlingGrace, "the grace was waited out")
        XCTAssertEqual(host.unsettledWorkRecorded, 1, "the statement is recorded as carried out, its result unread")
        XCTAssertEqual(host.cancelledWorkRecorded, 0, "not as a stop")
    }

    /// The server's answer is noted on the work's outcome for the statement the work is for alone:
    /// not for a statement the connection runs for itself nested inside it - a reconnect's setup -
    /// and not for work that is no statement, such as a check. Either would mark as settling work
    /// whose own statement was never sent, and a stop could then neither give it up nor kill it.
    func testOnlyTheStatementTheWorkIsForNotesItsAnswer() {
        let callHost = SAScriptedStatementHost()
        /// A statement call that notes its answer and its send, as the connection does for a write.
        func answeredStatement() -> SAStatementRun? {
            _ = SAStatementCall.admitStatementSend(on: callHost)
            SAStatementCall.noteStatementAnswered(on: callHost)
            return SAStatementRun(result: "ok", report: callHost.reportFromTheConnectionsFields)
        }

        // The work's own statement: asked for outside any work, run on the worker.
        _ = SAStatementCall.run(answeredStatement, on: callHost)
        let own = callHost.lastOutcome
        XCTAssertEqual(own?.statementWasSentToTheServer, true, "the work's own statement is noted")
        XCTAssertEqual(own?.statementWasAnsweredByTheServer, true)

        // A check whose setup statement is answered: work that is no statement at all.
        let check = callHost.coordinator.run({
            _ = SAStatementCall.run(answeredStatement, on: callHost)
            return nil
        }, whenSlow: Self.waitingForTheWork)
        XCTAssertFalse(check.statementWasSentToTheServer, "a check's statement is not the work's own")
        XCTAssertFalse(check.statementWasAnsweredByTheServer)

        // A reconnect's setup statement, answered inside the statement whose session was lost,
        // before that statement itself is sent.
        _ = SAStatementCall.run({
            _ = SAStatementCall.run(answeredStatement, on: callHost)
            return SAStatementRun(result: "outer", report: callHost.reportFromTheConnectionsFields)
        }, on: callHost)
        let nested = callHost.lastOutcome
        XCTAssertEqual(nested?.statementWasAnsweredByTheServer, false, "a setup statement nested in the work's own is not the work's own")
        XCTAssertEqual(nested?.statementWasSentToTheServer, false)

        // And the outer statement's own notes still count once the nested one has returned.
        _ = SAStatementCall.run({
            _ = SAStatementCall.run(answeredStatement, on: callHost)
            return answeredStatement()
        }, on: callHost)
        XCTAssertEqual(callHost.lastOutcome?.statementWasAnsweredByTheServer, true, "the work's own statement is noted after a nested one")
    }

    /// A stop that lands after the work's statement was sent to the server is reported as a stop
    /// that may have reached the server: the kill can come too late for a write, and nobody is
    /// told it certainly did not run. A stop before the send is a plain cancellation.
    func testAStopAfterTheSendIsReportedAsOneThatMayHaveReachedTheServer() {
        let host = SAScriptedWorkHost()
        let theStatementWasSent = DispatchSemaphore(value: 0)
        let theStopWasAccepted = DispatchSemaphore(value: 0)
        host.whileWaiting = { [coordinator] _ in
            XCTAssertEqual(theStatementWasSent.wait(timeout: .now() + 2), .success)
            coordinator.abandonWorkForUserStop()
            theStopWasAccepted.signal()
        }

        let result = coordinator.run({
            XCTAssertTrue(SAConnectionWorkCoordinator.admitSendOfCurrentWorksStatement(), "nothing stopped the send")
            theStatementWasSent.signal()
            _ = theStopWasAccepted.wait(timeout: .now() + 2)
            return nil
        }, on: host)

        XCTAssertNil(result)
        XCTAssertEqual(host.cancelledAfterSendRecorded, 1, "a stop after the send says the server may have carried the statement out")
        XCTAssertEqual(host.cancelledWorkRecorded, 0)
        XCTAssertEqual(host.unsettledWorkRecorded, 0)
    }

    /// The send of the work's statement is admitted as one decision with the user's stop: given up
    /// on first, nothing is sent and the caller reads a plain stop; admitted first, the send is
    /// noted and a stop from here on is one that may have reached the server.
    func testTheSendIsAdmittedOnlyWhileTheWorkIsNotGivenUp() {
        let admitted = SAConnectionWorkOutcome()
        XCTAssertTrue(admitted.admitStatementSend())
        XCTAssertTrue(admitted.statementWasSentToTheServer)
        XCTAssertTrue(admitted.abandon(), "given up on after the send: a stop that may have reached the server")
        XCTAssertTrue(admitted.statementWasSentToTheServer, "which the caller is told")

        let stopped = SAConnectionWorkOutcome()
        XCTAssertTrue(stopped.abandon())
        XCTAssertFalse(stopped.admitStatementSend(), "given up on first: the statement is not sent")
        XCTAssertFalse(stopped.statementWasSentToTheServer)
    }

    /// Settling work that outlives the grace keeps its thread uncancelled - the statement's
    /// clean-up may still send on it, and a cancelled thread is refused the session - and the
    /// thread goes once the work is done; the next piece of work gets a thread of its own.
    func testSettlingWorkPastTheGraceKeepsItsThreadUncancelledAndTheNextWorkGetsAnother() {
        let host = SAScriptedWorkHost()
        let theWorkIsSettling = DispatchSemaphore(value: 0)
        let letTheWorkEnd = DispatchSemaphore(value: 0)
        let theWorkEnded = DispatchSemaphore(value: 0)
        var settlingThread: Thread?
        var theThreadWasCancelledAfterTheGrace: Bool?
        host.whileWaiting = { _ in
            XCTAssertEqual(theWorkIsSettling.wait(timeout: .now() + 2), .success)
        }

        let result = coordinator.run({
            settlingThread = Thread.current
            SAConnectionWorkCoordinator.noteStatementOfCurrentWorkAnswered()
            theWorkIsSettling.signal()
            // The clean-up outlasts the grace; the caller has been told by the time this returns.
            _ = letTheWorkEnd.wait(timeout: .now() + 10)
            theThreadWasCancelledAfterTheGrace = Thread.current.isCancelled
            theWorkEnded.signal()
            return "late"
        }, on: host)
        XCTAssertNil(result, "the grace ran out")
        XCTAssertEqual(host.unsettledWorkRecorded, 1)

        let nextThread = run({ Thread.current }, whenSlow: Self.waitingForTheWork).result as? Thread
        XCTAssertNotNil(nextThread)
        XCTAssertFalse(nextThread === settlingThread, "the next piece of work got a thread of its own")

        letTheWorkEnd.signal()
        guard theWorkEnded.wait(timeout: .now() + 2) == .success else {
            XCTFail("the settling work did not end in time")
            return
        }
        XCTAssertEqual(theThreadWasCancelledAfterTheGrace, false, "the settling work's thread was left uncancelled for its clean-up")
    }

    /// An answer that comes once the user's stop has been accepted is nobody's: the stop was
    /// first, and is what the caller was told - a cancellation, not a statement carried out.
    func testAnAnswerThatComesAfterTheStopWasAcceptedIsNobodys() {
        let host = SAScriptedWorkHost()
        let workStarted = DispatchSemaphore(value: 0)
        let theStopWasAccepted = DispatchSemaphore(value: 0)
        let theAnswerWasNoted = DispatchSemaphore(value: 0)
        host.whileWaiting = { [coordinator] _ in
            XCTAssertEqual(workStarted.wait(timeout: .now() + 2), .success)
            coordinator.abandonWorkForUserStop()
            theStopWasAccepted.signal()
            // The wait ends only once the late answer has been noted, so the caller's report is
            // decided with the answer in: the ordering this test is about.
            XCTAssertEqual(theAnswerWasNoted.wait(timeout: .now() + 2), .success)
        }

        let result = coordinator.run({
            workStarted.signal()
            XCTAssertEqual(theStopWasAccepted.wait(timeout: .now() + 2), .success)
            // The server answers the statement after all - the kill came too late for it.
            SAConnectionWorkCoordinator.noteStatementOfCurrentWorkAnswered()
            theAnswerWasNoted.signal()
            return "answered late"
        }, on: host)

        XCTAssertNil(result)
        XCTAssertEqual(host.cancelledWorkRecorded, 1, "the stop is what the caller is told")
        XCTAssertEqual(host.unsettledWorkRecorded, 0, "not a statement carried out")
    }

    /// The waiting side's one decision when its wait ends before the work was seen to finish:
    /// finished when the worker stored the result meanwhile, settling when the server has
    /// answered the statement, and given up on otherwise - only then.
    func testTheWaitsEndIsOneDecision() {
        let finished = SAConnectionWorkOutcome()
        finished.storeResult("done")
        XCTAssertEqual(finished.endWaiting(), .finished)
        XCTAssertFalse(finished.wasAbandoned)

        let settling = SAConnectionWorkOutcome()
        settling.noteStatementAnswered()
        XCTAssertEqual(settling.endWaiting(), .settling)
        XCTAssertFalse(settling.wasAbandoned, "settling work is not given up on")

        let abandoned = SAConnectionWorkOutcome()
        XCTAssertEqual(abandoned.endWaiting(), .abandoned)
        XCTAssertTrue(abandoned.wasAbandoned)
        abandoned.noteStatementAnswered()
        XCTAssertFalse(abandoned.statementWasAnsweredByTheServer, "an answer after the stop is nobody's")

        // Given up on first, by the user's stop; the worker stores a result afterwards.
        let stoppedThenStored = SAConnectionWorkOutcome()
        XCTAssertTrue(stoppedThenStored.abandon())
        stoppedThenStored.storeResult("late")
        XCTAssertEqual(stoppedThenStored.endWaiting(), .abandoned, "given up on first counts as given up on")
        XCTAssertNil(stoppedThenStored.result)
    }

    /// Work handed over forgets a refusal that was not about it: the mark is read by the statement
    /// path alone, and the connection's other work passes the same gate without reading it.
    func testWorkHandedOverForgetsARefusalThatWasNotAboutIt() {
        let host = SAScriptedWorkHost()
        host.delegateShowsTheWait = false
        host.sessionAccess.noteThisThreadsCallWasRefused()

        var theWorkRan = false
        _ = coordinator.run({
            theWorkRan = true
            return nil
        }, on: host)

        XCTAssertTrue(theWorkRan)
        XCTAssertFalse(host.sessionAccess.takeTheRefusalOfThisThreadsLastCall(),
                       "the mark from before is gone, so it cannot be read as this work's")
    }

    // MARK: - Through the connection

    /// Stands in for the application: answers the lost-connection question on the main thread,
    /// runs the test's own work while being asked, and shows the wait for connection work, which
    /// is what makes the connection hand a main-thread query to its worker at all.
    private final class SAWaitingDelegate: NSObject {
        var whileBeingAsked: (() -> Void)?
        private(set) var timesAsked = 0

        @objc func connectionLost(_ connection: Any) -> SPMySQLConnectionLostDecision {
            timesAsked += 1
            whileBeingAsked?()
            return SPMySQLConnectionLostDisconnect
        }

        /// How long the wait for connection work may take before the test fails rather than hangs:
        /// a regression that leaves the two threads waiting for each other is reported, not waited out.
        static let waitDeadline: TimeInterval = 20

        @objc(connection:waitForConnectionWorkUntilFinished:)
        func connection(_ connection: Any, waitForConnectionWorkUntilFinished isFinished: @escaping () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: Self.waitDeadline)
            while !isFinished() {
                if Date() >= deadline {
                    XCTFail("the connection work was not finished after \(Self.waitDeadline) s; the wait returns so that the test can end")
                    return
                }
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        }
    }

    /// Verifies a main-thread query is refused before it is handed to the worker while a question
    /// about the connection is still out to the main thread.
    ///
    /// The lease turns a main-thread caller away, but the hand-off happens first and the session
    /// is then asked for on the worker, where that refusal no longer recognises the caller. This
    /// drives the whole chain through the public `queryString:`.
    ///
    /// The thread that asks holds the session while it asks, as a reconnect does - which is what
    /// makes the two sides cross. Without the refusal the worker waits in the lease for a session
    /// the asking thread is holding, the main thread waits for the worker inside the delegate's
    /// own wait, and the answer that would release the session cannot arrive until the main thread
    /// returns from being asked. Neither side moves, and the test hangs rather than failing an
    /// assertion. Holding the session is therefore not decoration here: without it the worker
    /// would take the free lease at once and nothing would be reproduced.
    func testAMainThreadQueryIsRefusedBeforeItIsHandedToTheWorkerWhileTheQuestionIsOpen() throws {
        let connection = SPMySQLConnection()
        connection.useKeepAlive = false
        defer {
            connection.setValue(SPMySQLDisconnected.rawValue, forKey: "state")
            connection.disconnect()
        }
        let delegate = SAWaitingDelegate()
        connection.perform(NSSelectorFromString("setDelegate:"), with: delegate)
        XCTAssertTrue(connection.value(forKey: "delegateSupportsConnectionCheckProgress") as? Bool ?? false,
                      "the connection only hands work over when the delegate shows the wait")

        // What the main thread finds when it comes back in while the question is open.
        var theQueryCameBackEmpty: Bool?
        var theConnectionReportedAnError: Bool?
        var itWasNotTakenForAUserStop: Bool?
        delegate.whileBeingAsked = {
            theQueryCameBackEmpty = connection.queryString("UPDATE t SET a = 1") == nil
            theConnectionReportedAnError = connection.queryErrored()
            itWasNotTakenForAUserStop = !connection.lastQueryWasCancelled
        }

        // The question goes out the way the connection puts it, from a worker.
        let theQuestionCameBack = expectation(description: "the question was answered")
        let theDecision = NSSelectorFromString("_delegateDecisionForLostConnection")
        XCTAssertTrue(connection.responds(to: theDecision))
        let access = try XCTUnwrap(connection.value(forKey: "sessionAccess") as? SAConnectionSessionAccess,
                                   "the lease is what the two sides contend for")
        Thread.detachNewThread {
            // Asked while holding the session, the way the reconnect that asks this question does.
            _ = access.performQuery {
                connection.perform(theDecision)
                return nil
            }
            theQuestionCameBack.fulfill()
        }

        // The hand-off waits on this thread's run loop, so it has to be run for the question to
        // arrive - which is what the application's modal loop does.
        let giveUp = Date(timeIntervalSinceNow: 20)
        while delegate.timesAsked == 0 && Date() < giveUp {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        XCTAssertEqual(delegate.timesAsked, 1, "the question reached the delegate")
        XCTAssertEqual(theQueryCameBackEmpty, true, "the query was turned away")
        XCTAssertEqual(theConnectionReportedAnError, true,
                       "and said so, rather than looking like a statement that changed nothing")
        XCTAssertEqual(itWasNotTakenForAUserStop, true,
                       "a refusal is not a query the user stopped, which callers stay quiet about")

        wait(for: [theQuestionCameBack], timeout: 20)
    }

    /// Verifies the connection's own hand-off runs where it was asked for when nobody shows the
    /// wait, and forgets a refusal that was not about this work.
    func testTheConnectionRunsWorkWhereItWasAskedForWithoutADelegate() throws {
        let connection = SPMySQLConnection()
        connection.useKeepAlive = false
        defer { connection.disconnect() }
        let access = try XCTUnwrap(connection.value(forKey: "sessionAccess") as? SAConnectionSessionAccess)
        access.noteThisThreadsCallWasRefused()

        let callingThread = Thread.current
        var ranOn: Thread?
        _ = unsafeBitCast(connection, to: SAWorkHandOff.self).runWorkKeepingInterfaceAlive {
            ranOn = Thread.current
            return nil
        }

        XCTAssertTrue(ranOn === callingThread, "with nobody to show the wait the work runs where it was asked for")
        XCTAssertFalse(access.takeTheRefusalOfThisThreadsLastCall(), "and the mark from before is gone")
    }
}
