//
//  SAConnectionWorkCoordinator.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// What running connection work off the main thread asks of the connection, without handing over
/// its internals: the readings that decide whether work is handed over at all, the delegate's wait,
/// and how work the user stopped waiting for is recorded - a step each, nothing decided in them.
@objc(SAConnectionWorkHost)
public protocol SAConnectionWorkHost: AnyObject {

    /// The lease, which knows whether a question about the connection is out to the main thread,
    /// and records a call that was turned away.
    @objc var sessionAccess: SAConnectionSessionAccess { get }

    /// Whether a delegate is there to show the wait and let the user end it.
    @objc var delegateShowsTheWait: Bool { get }

    /// Whether the current thread is the one reconnecting, which sets the new session up itself.
    @objc var currentThreadIsSettingUpTheSession: Bool { get }

    /// Asks the delegate to wait for the work in a way that keeps the interface answering.
    /// - Parameter isFinished: Reports whether the work has finished; asked as often as the
    ///   delegate likes, and `true` from the moment the work is done or was given up on.
    @objc(waitForConnectionWorkUntilFinished:) func waitForWork(untilFinished isFinished: @escaping () -> Bool)

    /// Records that work was given up on, the way a cancelled query is recorded.
    @objc(recordWorkAsCancelled) func recordWorkAsCancelled()
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
    private var workWasGivenUp = false

    /// Whether the work finished before the waiting ended.
    @objc public var finished = false

    /// What the work returned, or nil if it was given up on.
    @objc public var result: Any? {
        lock.lock()
        defer { lock.unlock() }
        return workWasGivenUp ? nil : storedResult
    }

    /// Whether the waiting ended before the work did, so that its answer is nobody's any more.
    @objc public var wasAbandoned: Bool {
        lock.lock()
        defer { lock.unlock() }
        return workWasGivenUp
    }

    /// Records what the work returned. Called by the worker once the work is done.
    /// - Parameter result: What the work returned.
    func storeResult(_ result: Any?) {
        lock.lock()
        defer { lock.unlock() }
        storedResult = result
        workHasFinished = true
    }

    /// Gives the work up, unless it has already finished.
    /// - Returns: Whether the work was given up on; false if it had finished after all.
    func abandon() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !workHasFinished else {
            return false
        }
        workWasGivenUp = true
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

    private var workerThread: Thread?

    /// The work being waited for right now. Guarded by `inFlightLock`; more than one when waits are nested.
    private var inFlight: [SAConnectionWorkOutcome] = []
    private let inFlightLock = NSLock()

    /// Whether the work running on the current thread is work that nobody is waiting for any more.
    ///
    /// Work is given up on while it can still be queued, or waiting for the connection. By the
    /// time it gets the connection its caller has long been told it was cancelled, and the lease
    /// turns a cancelled thread away rather than hand it the session.
    @objc public static var currentWorkHasBeenAbandoned: Bool {
        let thread = Thread.current
        return thread.threadDictionary[workerThreadMarker] != nil && thread.isCancelled
    }

    /// Whether connection work asked for on this thread should be handed to a worker thread.
    ///
    /// Work that has to wait for a server is handed over so the interface keeps drawing while it
    /// waits, and the delegate shows the wait and lets the user end it. Two things rule that out.
    /// Away from the main thread there is nothing to keep drawing, and without a delegate there is
    /// nothing to show the wait - the work then runs where it was asked for.
    ///
    /// And a thread that is setting the new session up keeps its own queries, whichever thread it
    /// is. It holds the session while it does, and will not let go of it until its setup is done;
    /// work handed to another thread would wait there for a session that is waiting for it.
    /// - Parameters:
    ///   - isMainThread: Whether the work was asked for on the main thread.
    ///   - delegateShowsTheWait: Whether a delegate is there to show the wait and end it.
    ///   - threadIsSettingUpTheSession: Whether this thread is the one reconnecting.
    /// - Returns: Whether handing the work over would move it off the main thread, usefully.
    @objc(workShouldRunOffMainThread:delegateShowsTheWait:threadIsSettingUpTheSession:)
    public static func workShouldRunOffMainThread(isMainThread: Bool,
                                                  delegateShowsTheWait: Bool,
                                                  threadIsSettingUpTheSession: Bool) -> Bool {
        guard !threadIsSettingUpTheSession else {
            return false
        }
        return isMainThread && delegateShowsTheWait
    }

    /// Whether work the main thread would hand to the worker has to be refused instead.
    ///
    /// A question about the connection is answered on the main thread, and the thread that asked
    /// keeps the session until it has an answer. Handing the main thread's work to the worker
    /// does not get around that. The worker runs one item at a time, so the work queues behind
    /// whatever is already waiting for that answer, and the main thread then waits for the
    /// worker - while the answer cannot arrive until the main thread returns. Both wait for each
    /// other. ``SAConnectionSessionAccess`` turns a main-thread caller away for the same reason;
    /// this is that refusal one step earlier, before anything is enqueued, because by the time
    /// the session is asked for the caller is the worker and no longer looks like the main thread.
    /// - Parameters:
    ///   - isMainThread: Whether the caller is the thread the question is answered on.
    ///   - aQuestionAwaitsTheMainThread: Whether a question is out to it and still unanswered.
    /// - Returns: Whether to refuse the work rather than hand it over.
    @objc(mainThreadWorkMustBeRefused:aQuestionAwaitsTheMainThread:)
    public static func mainThreadWorkMustBeRefused(isMainThread: Bool,
                                                   aQuestionAwaitsTheMainThread: Bool) -> Bool {
        return isMainThread && aQuestionAwaitsTheMainThread
    }

    /// Runs connection work for its host: where it was asked for, or - on the main thread, with a
    /// delegate to show the wait - on the worker, with the delegate waiting for it.
    ///
    /// Whatever this thread was told about an earlier refusal is not about this work, and is
    /// forgotten first: only the statement path reads that mark, and the connection's other work -
    /// a check, a session replacement - comes through here too and reads nothing; a mark one of
    /// those left standing would be read by the next statement and reported as that statement's
    /// own. Work the main thread would hand over while a question is out to it is refused before
    /// anything is enqueued, and marked as refused, so the statement path reports it as never
    /// sent. Work the user stopped waiting for is recorded as cancelled, and nothing is returned
    /// for it: whatever it returns afterwards is not an answer.
    /// - Parameters:
    ///   - work: The work to run. It must not expect to be on the thread that asked for it.
    ///   - host: The connection the work is for.
    /// - Returns: What the work returned, or nil if it was refused or the waiting ended before it finished.
    @objc(runWork:onHost:)
    public func run(_ work: @escaping () -> Any?, on host: SAConnectionWorkHost) -> Any? {
        let lease = host.sessionAccess
        lease.forgetAnyRefusalOfThisThread()

        guard Self.workShouldRunOffMainThread(isMainThread: Thread.isMainThread,
                                              delegateShowsTheWait: host.delegateShowsTheWait,
                                              threadIsSettingUpTheSession: host.currentThreadIsSettingUpTheSession) else {
            return work()
        }

        if Self.mainThreadWorkMustBeRefused(isMainThread: Thread.isMainThread,
                                            aQuestionAwaitsTheMainThread: lease.aQuestionAwaitsTheMainThread) {
            lease.noteThisThreadsCallWasRefused()
            return nil
        }

        let outcome = run(work, whenSlow: { isFinished in
            host.waitForWork(untilFinished: isFinished)
        })
        guard outcome.finished else {
            host.recordWorkAsCancelled()
            return nil
        }
        return outcome.result
    }

    /// Runs work off the calling thread, waiting for it quietly first and visibly afterwards.
    /// - Parameters:
    ///   - work: The work to run. It runs on the coordinator's thread, never on the caller's.
    ///   - waitForFinish: Called only when the work outlasts the quiet wait. It receives a block
    ///     that reports whether the work has finished, and is expected to keep the interface
    ///     answering until that block says yes - or to return earlier, ending the wait.
    /// - Returns: What the work returned, and whether it finished before the waiting ended.
    @objc(runWork:whenSlow:)
    public func run(_ work: @escaping () -> Any?,
                    whenSlow waitForFinish: (_ isFinished: @escaping () -> Bool) -> Void) -> SAConnectionWorkOutcome {
        let outcome = SAConnectionWorkOutcome()
        let workFinished = DispatchSemaphore(value: 0)
        let item = SAConnectionWorkItem {
            outcome.storeResult(work())
            workFinished.signal()
        }

        inFlightLock.lock()
        inFlight.append(outcome)
        inFlightLock.unlock()
        defer {
            inFlightLock.lock()
            inFlight.removeAll { $0 === outcome }
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
            if outcome.abandon() {
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

        for outcome in waitedFor {
            _ = outcome.abandon()
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
