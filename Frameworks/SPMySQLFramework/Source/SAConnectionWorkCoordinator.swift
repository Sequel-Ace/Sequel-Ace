//
//  SAConnectionWorkCoordinator.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// How a piece of connection work has used the connection's session, as far as stopping it is
/// concerned.
@objc(SAWorkSessionUse)
public enum SAWorkSessionUse: Int {
    /// The work has sent nothing, so the session is as the work found it.
    case untouched
    /// The work started sending while the session had no transaction open.
    case outsideTransaction
    /// The work started sending while the session had a transaction open - one the work did not
    /// open itself.
    case insideTransaction
}

/// What came of a piece of connection work, and whether it was still being waited for.
///
/// Two threads decide this together: the worker, when the work finishes, and the waiting side,
/// when it stops waiting. Both happen under one lock, so exactly one of them is first - work that
/// finished just as the waiting ended counts as finished, and work given up on first counts as
/// given up on, however the two moments fall.
@objc(SAConnectionWorkOutcome)
public final class SAConnectionWorkOutcome: NSObject {

    private let lock = NSLock()
    private var storedResult: Any?
    private var workHasFinished = false
    private var abandonedAtStamp: UInt?
    private var storedSessionUse = SAWorkSessionUse.untouched

    /// Whether the work finished before the waiting ended.
    @objc public var finished = false

    /// What the work returned, or nil if it was given up on.
    @objc public var result: Any? {
        lock.lock()
        defer { lock.unlock() }
        return abandonedAtStamp == nil ? storedResult : nil
    }

    /// Whether the waiting ended before the work did, so that its answer is nobody's any more.
    @objc public var wasAbandoned: Bool {
        lock.lock()
        defer { lock.unlock() }
        return abandonedAtStamp != nil
    }

    /// How the work has used the session. Once the work has been given up on, this no longer changes.
    @objc public var sessionUse: SAWorkSessionUse {
        lock.lock()
        defer { lock.unlock() }
        return storedSessionUse
    }

    /// Lets the work send something to the session, unless it has been given up on. Called by the
    /// worker while it holds the connection, before each statement.
    ///
    /// The first call records whether the session had a transaction open before the work sent
    /// anything. A statement the work sends can open a transaction and report it before the work
    /// is given up on; what counts for the stop is the transaction that was there before.
    /// - Parameter sessionHasOpenTransaction: Whether the session has a transaction open right now.
    /// - Returns: Whether the work may send; false once it has been given up on.
    func beginSessionUse(sessionHasOpenTransaction: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard abandonedAtStamp == nil else {
            return false
        }
        if storedSessionUse == .untouched {
            storedSessionUse = sessionHasOpenTransaction ? .insideTransaction : .outsideTransaction
        }
        return true
    }

    /// Records what the work returned. Called by the worker once the work is done.
    /// - Parameter result: What the work returned.
    /// - Returns: The operation the connection was on when the work was given up on, if it was.
    func storeResult(_ result: Any?) -> UInt? {
        lock.lock()
        defer { lock.unlock() }
        storedResult = result
        workHasFinished = true
        return abandonedAtStamp
    }

    /// Gives the work up, unless it has already finished.
    /// - Parameter stamp: The operation the connection is on right now.
    /// - Returns: Whether the work was given up on; false if it had finished after all.
    func abandon(atStamp stamp: UInt) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !workHasFinished else {
            return false
        }
        abandonedAtStamp = stamp
        return true
    }
}

/// Runs the small block of work handed to it on another thread.
private final class SAConnectionWorkItem: NSObject {
    private let work: () -> Void

    /// Keeps the work until a thread runs it.
    init(_ work: @escaping () -> Void) {
        self.work = work
    }

    /// Runs the work it was created with.
    func run() {
        work()
    }
}

/// Where a connection's work runs when the main thread must not be the one waiting for it.
///
/// A query waits for a server, and on a route that has gone away it waits for a timeout. Waiting
/// for that on the main thread leaves the window unable to draw and the system drawing its own
/// waiting cursor over the application, so the work runs on a thread of the connection's own.
///
/// Work that answers quickly - which is nearly all of it - is simply waited for, without letting
/// anything else happen in between, so ordinary use behaves exactly as it did. Only work that
/// lasts longer than that hands the waiting to the interface, which can then say what is being
/// waited for and offer to stop.
@objc(SAConnectionWorkCoordinator)
public final class SAConnectionWorkCoordinator: NSObject {

    /// How long work may take before the interface is told about it, in seconds.
    public static let quietWait: TimeInterval = 0.15

    /// How long the worker's run loop waits for the next piece of work before looking around, in seconds.
    private static let workerIdleInterval: TimeInterval = 1

    /// The key that marks a thread as one of the coordinators' workers.
    private static let workerThreadMarker = "SAConnectionWorkCoordinatorWorker"

    /// The key under which a worker keeps the outcome of the work it is running.
    private static let runningWorkOutcomeKey = "SAConnectionWorkCoordinatorRunningWork"

    private var workerThread: Thread?

    /// The work being waited for right now, and how to tell which operation the connection is on.
    /// Guarded by `inFlightLock`; more than one when waits are nested.
    private var inFlight: [(outcome: SAConnectionWorkOutcome, operationStamp: () -> UInt)] = []
    private let inFlightLock = NSLock()

    /// Whether the work running on the current thread is work that nobody is waiting for any more.
    ///
    /// Work is given up on while it can still be queued, or waiting for the connection. By the
    /// time it gets the connection its caller has long been told it was cancelled, and a statement
    /// that changes data must not run after all. Work asks this once it holds the connection, and
    /// before it sends anything.
    @objc public static var currentWorkHasBeenAbandoned: Bool {
        let thread = Thread.current
        return thread.threadDictionary[workerThreadMarker] != nil && thread.isCancelled
    }

    /// Whether the work running on the current thread may send a statement now. Asked while the
    /// connection is held, before the work first touches the session in a query.
    ///
    /// Work a coordinator runs also records here whether a transaction was open before it first
    /// used the session. Work that runs where it was asked for is never given up on.
    /// - Parameter sessionHasOpenTransaction: Whether the session has a transaction open right now.
    /// - Returns: Whether the work may send; false for work that has been given up on.
    @objc(currentWorkMaySendWithOpenTransaction:)
    public static func currentWorkMaySend(sessionHasOpenTransaction: Bool) -> Bool {
        guard !currentWorkHasBeenAbandoned else {
            return false
        }
        guard let outcome = Thread.current.threadDictionary[runningWorkOutcomeKey] as? SAConnectionWorkOutcome else {
            return true
        }
        return outcome.beginSessionUse(sessionHasOpenTransaction: sessionHasOpenTransaction)
    }

    /// How the work running on the current thread has used the session; untouched for work that
    /// no coordinator runs.
    @objc public static var currentWorkSessionUse: SAWorkSessionUse {
        let outcome = Thread.current.threadDictionary[runningWorkOutcomeKey] as? SAConnectionWorkOutcome
        return outcome?.sessionUse ?? .untouched
    }

    /// Runs work off the main thread, waiting for it quietly first and visibly afterwards.
    /// - Parameters:
    ///   - work: The work to run. It runs on the coordinator's thread, never on the caller's.
    ///   - waitForFinish: Called only when the work outlasts the quiet wait. It receives a block
    ///     that reports whether the work has finished, and is expected to keep the interface
    ///     answering until that block says yes - or to return earlier, ending the wait.
    ///   - operationStamp: Identifies the operation the connection is on, and changes whenever a
    ///     new one starts. A late completion only speaks for the operation it belonged to.
    ///   - lateCompletion: Called on the worker's thread if the work finishes after the waiting
    ///     ended - and only while no other operation has started since - so that what was reported
    ///     to the caller in the meantime can be kept without touching anybody else's result. It is
    ///     given the operation the waiting ended on, to check again under its own lock.
    /// - Returns: What the work returned, and whether it finished before the waiting ended.
    @objc(runWork:operationStamp:whenSlow:whenAbandonedWorkFinishes:)
    public func run(_ work: @escaping () -> Any?,
                    operationStamp: @escaping () -> UInt,
                    whenSlow waitForFinish: (_ isFinished: @escaping () -> Bool) -> Void,
                    whenAbandonedWorkFinishes lateCompletion: @escaping (_ abandonedAtStamp: UInt) -> Void) -> SAConnectionWorkOutcome {
        let outcome = SAConnectionWorkOutcome()
        let workFinished = DispatchSemaphore(value: 0)

        // Statements from outside the application stay marked as such on the worker.
        let comesFromOutside = SAOutsideStatements.areRunningOnCurrentThread
        let item = SAConnectionWorkItem {
            // The work and what settles it afterwards can tell how the work has used the session.
            let threadDictionary = Thread.current.threadDictionary
            threadDictionary[Self.runningWorkOutcomeKey] = outcome
            defer {
                threadDictionary.removeObject(forKey: Self.runningWorkOutcomeKey)
            }

            var result: Any?
            if comesFromOutside {
                SAOutsideStatements.run { result = work() }
            } else {
                result = work()
            }

            // Nobody is waiting for this any more, and what the caller was told instead has to
            // stand - unless the connection has moved on to other work since, whose result is
            // that work's own.
            if let abandonedAtStamp = outcome.storeResult(result), operationStamp() == abandonedAtStamp {
                lateCompletion(abandonedAtStamp)
            }

            workFinished.signal()
        }

        inFlightLock.lock()
        inFlight.append((outcome: outcome, operationStamp: operationStamp))
        inFlightLock.unlock()
        defer {
            inFlightLock.lock()
            inFlight.removeAll { $0.outcome === outcome }
            inFlightLock.unlock()
        }

        perform(#selector(runWorkItem(_:)), on: startedWorkerThread(), with: item, waitUntilDone: false)

        if workFinished.wait(timeout: .now() + Self.quietWait) == .success {
            outcome.finished = true
            return outcome
        }

        // From here the interface owns the waiting, and asks as often as it likes. Work the user
        // stopped is over for the interface at once, however long it takes to notice.
        waitForFinish {
            if outcome.wasAbandoned {
                return true
            }
            if !outcome.finished, workFinished.wait(timeout: .now()) == .success {
                outcome.finished = true
            }
            return outcome.finished
        }

        // The user stopped this work while the interface was waiting for it. Whatever it returns
        // afterwards - early, because it was stopped - is not an answer.
        if outcome.wasAbandoned {
            outcome.finished = false
            return outcome
        }

        // Work nobody waited for to the end keeps running, and what it returns is nobody's
        // answer any more - unless it finished in the very moment the waiting ended.
        if !outcome.finished {
            if outcome.abandon(atStamp: operationStamp()) {
                // That work can hold this thread for as long as the server takes to answer, or
                // for as long as the network takes to give up on it. The next piece of work gets
                // a thread of its own rather than a place in the queue behind it.
                cancel()
            } else {
                outcome.finished = true
            }
        }

        return outcome
    }

    /// Stops the work that is being waited for, because the user asked for that.
    ///
    /// The work is given up on before its thread is asked to stop. Work that notices the request
    /// returns early without saying why, and would otherwise count as having finished - a statement
    /// that never ran would then look as if it had. Work that finished before this counts as
    /// finished; so does work queued behind it on the same thread, which is given up on too.
    @objc public func abandonWorkForUserStop() {
        inFlightLock.lock()
        let waitedFor = inFlight
        inFlightLock.unlock()

        for entry in waitedFor {
            _ = entry.outcome.abandon(atStamp: entry.operationStamp())
        }
        cancel()
    }

    /// The thread the coordinator's work runs on now, if it has one.
    var currentWorkerThread: Thread? {
        return workerThread
    }

    /// Asks the work to stop and gives up the thread it runs on.
    ///
    /// The thread is not used again: what it is doing may take a while yet to notice that it has
    /// been asked to stop, and the next piece of work should not have to wait behind it.
    @objc public func cancel() {
        workerThread?.cancel()
        workerThread = nil
    }

    /// The thread this coordinator runs work on, started if it does not have one.
    /// - Returns: A running thread whose run loop is ready for work.
    private func startedWorkerThread() -> Thread {
        if let workerThread, !workerThread.isCancelled {
            return workerThread
        }

        // The thread holds no more than a weak reference to the coordinator: a thread that runs
        // for a connection's lifetime would otherwise keep it alive for the application's.
        let thread = Thread { [weak self] in
            let thisThread = Thread.current
            thisThread.threadDictionary[Self.workerThreadMarker] = true
            let runLoop = RunLoop.current

            // A run loop with nothing in it returns at once, so it is given something that
            // never fires and keeps it waiting for work instead of spinning.
            let keepAlive = Timer(timeInterval: .greatestFiniteMagnitude, repeats: false) { _ in }
            runLoop.add(keepAlive, forMode: .default)

            while !thisThread.isCancelled && self != nil {
                autoreleasepool {
                    _ = runLoop.run(mode: .default, before: Date().addingTimeInterval(Self.workerIdleInterval))
                }
            }

            keepAlive.invalidate()
        }
        thread.name = "SPMySQL connection work"
        thread.start()
        workerThread = thread

        return thread
    }

    /// Runs one piece of work on the worker thread.
    /// - Parameter item: The work handed over by ``run(_:whenSlow:)``.
    @objc private func runWorkItem(_ item: SAConnectionWorkItem) {
        autoreleasepool {
            item.run()
        }
    }
}
