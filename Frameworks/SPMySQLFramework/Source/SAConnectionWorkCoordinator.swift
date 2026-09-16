//
//  SAConnectionWorkCoordinator.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// What came of a piece of connection work, and whether it was still being waited for.
@objc(SAConnectionWorkOutcome)
public final class SAConnectionWorkOutcome: NSObject {

    /// What the work returned, if it finished while it was still being waited for.
    @objc public var result: Any?

    /// Whether the work finished before the waiting ended.
    @objc public var finished = false

    /// Whether the waiting ended before the work did, so that its answer is nobody's any more.
    @objc public var wasAbandoned = false
}

/// Runs the small block of work handed to it on another thread.
private final class SAConnectionWorkItem: NSObject {
    private let work: () -> Void

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

    private var workerThread: Thread?

    /// Runs work off the main thread, waiting for it quietly first and visibly afterwards.
    /// - Parameters:
    ///   - work: The work to run. It runs on the coordinator's thread, never on the caller's.
    ///   - waitForFinish: Called only when the work outlasts the quiet wait. It receives a block
    ///     that reports whether the work has finished, and is expected to keep the interface
    ///     answering until that block says yes - or to return earlier, ending the wait.
    ///   - lateCompletion: Called on the worker's thread if the work finishes after the waiting
    ///     ended, so that what was reported to the caller in the meantime can be kept.
    /// - Returns: What the work returned, and whether it finished before the waiting ended.
    @objc(runWork:whenSlow:whenAbandonedWorkFinishes:)
    public func run(_ work: @escaping () -> Any?,
                    whenSlow waitForFinish: (_ isFinished: @escaping () -> Bool) -> Void,
                    whenAbandonedWorkFinishes lateCompletion: @escaping () -> Void) -> SAConnectionWorkOutcome {
        let outcome = SAConnectionWorkOutcome()
        let workFinished = DispatchSemaphore(value: 0)
        let item = SAConnectionWorkItem {
            let result = work()

            // Nobody is waiting for this any more, and what the caller was told instead has to
            // stand: it was told this work did not happen.
            if outcome.wasAbandoned {
                lateCompletion()
            }

            outcome.result = result
            workFinished.signal()
        }

        perform(#selector(runWorkItem(_:)), on: startedWorkerThread(), with: item, waitUntilDone: false)

        if workFinished.wait(timeout: .now() + Self.quietWait) == .success {
            outcome.finished = true
            return outcome
        }

        // From here the interface owns the waiting, and asks as often as it likes.
        waitForFinish {
            if !outcome.finished, workFinished.wait(timeout: .now()) == .success {
                outcome.finished = true
            }
            return outcome.finished
        }

        // Work nobody waited for to the end keeps running, and what it returns is nobody's
        // answer any more.
        if !outcome.finished {
            outcome.wasAbandoned = true
            outcome.result = nil

            // That work can hold this thread for as long as the server takes to answer, or for
            // as long as the network takes to give up on it. The next piece of work gets a
            // thread of its own rather than a place in the queue behind it.
            cancel()
        }

        return outcome
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
            let runLoop = RunLoop.current

            // A run loop with nothing in it returns at once, so it is given something that
            // never fires and keeps it waiting for work instead of spinning.
            let keepAlive = Timer(timeInterval: .greatestFiniteMagnitude, repeats: false) { _ in }
            runLoop.add(keepAlive, forMode: .default)

            while !thisThread.isCancelled && self != nil {
                autoreleasepool {
                    runLoop.run(mode: .default, before: Date().addingTimeInterval(Self.workerIdleInterval))
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
