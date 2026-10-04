//
//  SAAsyncResultBox.swift
//  Sequel Ace
//
//  Created as part of the Swift 6 readiness work.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Thread-safe container handing the outcome of an async call back to a thread
/// that is blocking on a semaphore.
///
/// The synchronous-wrapper pattern used by the AWS clients (`DispatchSemaphore`
/// + `Task`) cannot write its outcome into captured `var`s: mutating them from
/// the concurrently-executing task is a warning today and an error in the Swift 6
/// language mode. Writing into a reference type instead takes the mutation out of
/// the closure.
///
/// The lock is not ceremony: the waiter gives up after a timeout, and the task
/// keeps running — and writing — after that.
final class SAAsyncResultBox<Success>: @unchecked Sendable {

    private let lock = NSLock()
    private var storedResult: Result<Success, Error>?

    /// The recorded outcome, or nil when nothing has completed yet (the waiter
    /// timed out, or the task never ran).
    var result: Result<Success, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    /// Records an outcome. One box carries one call, so this is expected to be
    /// written exactly once; a later write replaces an earlier one.
    func complete(with result: Result<Success, Error>) {
        lock.lock()
        defer { lock.unlock() }
        storedResult = result
    }

    func succeed(_ value: Success) {
        complete(with: .success(value))
    }

    func fail(_ error: Error) {
        complete(with: .failure(error))
    }
}
