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
        })

        XCTAssertFalse(outcome.finished)
        XCTAssertTrue(outcome.wasAbandoned)
        XCTAssertNil(outcome.result)

        XCTAssertEqual(workStarted.wait(timeout: .now() + 2), .success)
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
        let stuckWorkMayFinish = DispatchSemaphore(value: 0)

        _ = run({
            stuckWorkMayFinish.wait()
            return nil
        })

        let outcome = run({ "next" }, whenSlow: Self.waitingForTheWork)

        XCTAssertTrue(outcome.finished)
        XCTAssertEqual(outcome.result as? String, "next")

        stuckWorkMayFinish.signal()
    }

    /// Work the user stops never counts as finished, even when it returns before the waiting ends.
    func testWorkStoppedByTheUserNeverCountsAsFinished() {
        let workReturned = DispatchSemaphore(value: 0)
        var waitEndedAtOnce = false
        let outcome = run({
            // Stands in for work that notices the stop and returns early without saying why.
            while !Thread.current.isCancelled {
                usleep(1_000)
            }
            workReturned.signal()
            return "stopped early"
        }, whenSlow: { isFinished in
            coordinator.abandonWorkForUserStop()
            waitEndedAtOnce = isFinished()

            // The work returns before the interface is done with its wait.
            XCTAssertEqual(workReturned.wait(timeout: .now() + 2), .success)
        })

        XCTAssertTrue(waitEndedAtOnce)
        XCTAssertFalse(outcome.finished)
        XCTAssertTrue(outcome.wasAbandoned)
        XCTAssertNil(outcome.result)
    }

    /// Work the user stopped knows it, once it looks: the lease turns its thread away.
    func testWorkTheUserStoppedKnowsItHasBeenAbandoned() {
        let noticed = DispatchSemaphore(value: 0)
        var abandonedWhenItLooked = false
        _ = run({
            while !Thread.current.isCancelled {
                usleep(1_000)
            }
            abandonedWhenItLooked = SAConnectionWorkCoordinator.currentWorkHasBeenAbandoned
            noticed.signal()
            return nil
        }, whenSlow: { _ in
            coordinator.abandonWorkForUserStop()
        })

        XCTAssertEqual(noticed.wait(timeout: .now() + 2), .success)
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

    /// Work from another thread during the wait is not nested work, and is handed over as usual.
    func testWorkFromAnotherThreadDuringTheWaitIsNotRefused() {
        let host = SAScriptedWorkHost()
        host.delegateShowsTheWait = false
        var otherResult: Any?
        let otherReturned = DispatchSemaphore(value: 0)
        let watcher = SAScriptedWorkHost()
        watcher.whileWaiting = { [coordinator] isFinished in
            Thread.detachNewThread {
                otherResult = coordinator.run({ "other" }, on: host)
                otherReturned.signal()
            }
            while !isFinished() {
                usleep(1_000)
            }
        }

        _ = coordinator.run({
            Thread.sleep(forTimeInterval: 0.3)
            return "outer"
        }, on: watcher)

        XCTAssertEqual(otherReturned.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(otherResult as? String, "other")
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

        wait(for: [looked], timeout: 5)
        XCTAssertEqual(connection.handshakes, 1, "the handshake came up")
        XCTAssertEqual(connection.restoresAttempted, 0, "nobody set the session up")
        XCTAssertEqual(reconnected, false, "so the reconnect did not succeed")
        XCTAssertEqual(stateAfterwards, Int(SPMySQLConnectionLostInBackground.rawValue),
                       "and the session is retired, for the next use to reconnect and restore")
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

        @objc(connection:waitForConnectionWorkUntilFinished:)
        func connection(_ connection: Any, waitForConnectionWorkUntilFinished isFinished: @escaping () -> Bool) {
            while !isFinished() {
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
