//
//  SAQueryAdmission.swift
//  Sequel Ace
//
//  Coordinates a task's Stop request with the queries its worker starts, so a
//  cancellation can never fall into the gap between "is the task cancelled?"
//  and "submit the next query". Kept free of project ObjC types so it also
//  builds in the Unit Tests target.
//

import Foundation

/// A task-cancellation callback object that wants the connection-level cancel
/// routed through it (SATaskController checks for this after invoking the
/// callback selector), so the cancel can be retried until the query that was
/// admitted before Stop has actually started and been interrupted.
@objc protocol SAQueryCancellationRequesting: AnyObject {
    @objc(requestQueryCancellation:)
    func requestQueryCancellation(_ cancellation: @escaping () -> Void)
}

/// Admission and retrying-cancellation state shared by long-running query
/// tasks (`SAFieldRemovalTask`, `SAScriptCancellationToken`).
///
/// A query is *admitted* only while cancellation has not been requested; the
/// check and the admission happen under one lock, so once `requestCancellation()`
/// returns no further query is admitted. A query admitted just before Stop may
/// not have reached the connection yet, when a connection-level cancel would be
/// lost, so `requestQueryCancellation(_:)` keeps retrying the cancel (off the
/// main queue, with backoff) for as long as an admitted query remains active.
final class SAQueryAdmission {

    private static let initialCancellationRetryDelay: TimeInterval = 0.025
    private static let maximumCancellationRetryDelay: TimeInterval = 1

    private let stateLock = NSLock()
    private let cancellationQueue: DispatchQueue
    private var cancellationRequested = false
    private var queryIsAdmitted = false

    init(cancellationQueueLabel: String) {
        cancellationQueue = DispatchQueue(label: cancellationQueueLabel, qos: .userInitiated)
    }

    var isCancellationRequested: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancellationRequested
    }

    func requestCancellation() {
        stateLock.lock()
        cancellationRequested = true
        stateLock.unlock()
    }

    /// Runs `operation` (which starts one query) only if cancellation has not
    /// been requested; returns nil without running it otherwise.
    func admit<T>(_ operation: () -> T) -> T? {
        stateLock.lock()
        guard !cancellationRequested else {
            stateLock.unlock()
            return nil
        }
        queryIsAdmitted = true
        stateLock.unlock()

        defer {
            stateLock.lock()
            queryIsAdmitted = false
            stateLock.unlock()
        }
        return operation()
    }

    /// Keeps cancellation attempts off the main queue and backs them off while
    /// an admitted query remains active.
    func requestQueryCancellation(_ cancellation: @escaping () -> Void) {
        scheduleCancellationAttempt(
            after: 0,
            nextRetryDelay: Self.initialCancellationRetryDelay,
            cancellation: cancellation
        )
    }

    /// Cancels an admitted query while preventing it from completing its
    /// transition to subsequent connection work. The cancellation closure
    /// must not call back into this object.
    private func cancelAdmittedQuery(_ cancellation: () -> Void) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard cancellationRequested, queryIsAdmitted else {
            return false
        }
        cancellation()
        return true
    }

    private func scheduleCancellationAttempt(
        after delay: TimeInterval,
        nextRetryDelay: TimeInterval,
        cancellation: @escaping () -> Void
    ) {
        cancellationQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, cancelAdmittedQuery(cancellation) else {
                return
            }

            scheduleCancellationAttempt(
                after: nextRetryDelay,
                nextRetryDelay: min(nextRetryDelay * 2, Self.maximumCancellationRetryDelay),
                cancellation: cancellation
            )
        }
    }
}
