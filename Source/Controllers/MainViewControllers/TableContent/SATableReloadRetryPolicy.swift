//
//  SATableReloadRetryPolicy.swift
//  Sequel Ace
//
//  Copyright (c) 2026 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>

import Foundation

/// Bounds the full table reloads the content view queues for itself.
///
/// A content load compares the table's column list against the fields the server
/// actually returned and queues a full reload when the two disagree, so that a
/// table altered under a running load is picked up. While a connection keeps
/// dropping, the column list can stay empty round after round, and the reload
/// queues another reload forever. This policy caps how often a table may reload
/// itself without the user asking; a load whose columns match clears the count.
@objc(SATableReloadRetryPolicy)
final class SATableReloadRetryPolicy: NSObject {

    /// How often one table may reload itself before the policy gives up.
    @objc static let defaultLimit = 3

    private let limit: Int
    private let lock = NSLock()
    private var attemptsByTable: [String: Int] = [:]

    /// Creates a policy that allows `limit` self-triggered reloads per table.
    ///
    /// - Parameter limit: The number of automatic reloads to allow. Values below
    ///   zero are treated as zero, which refuses every automatic reload.
    @objc init(limit: Int) {
        self.limit = max(0, limit)
        super.init()
    }

    /// Creates a policy with ``defaultLimit``.
    @objc override convenience init() {
        self.init(limit: SATableReloadRetryPolicy.defaultLimit)
    }

    /// Records one automatic reload for a table and reports whether it may run.
    ///
    /// - Parameter table: The table about to reload itself. A table without a
    ///   name shares one counter, so an unnamed load cannot reload endlessly
    ///   either.
    /// - Returns: `true` while the table is still below the limit.
    @objc func shouldReload(forTable table: String?) -> Bool {
        let key = table ?? ""
        lock.lock()
        defer { lock.unlock() }

        let used = attemptsByTable[key] ?? 0
        guard used < limit else { return false }

        attemptsByTable[key] = used + 1
        return true
    }

    /// Reports how many automatic reloads a table has used so far.
    ///
    /// - Parameter table: The table to report on.
    /// - Returns: The number of reloads recorded since the last reset.
    @objc func attemptCount(forTable table: String?) -> Int {
        lock.lock()
        defer { lock.unlock() }

        return attemptsByTable[table ?? ""] ?? 0
    }

    /// Forgets the reloads recorded for one table, after a load that matched.
    ///
    /// - Parameter table: The table whose count is cleared.
    @objc func reset(forTable table: String?) {
        lock.lock()
        defer { lock.unlock() }

        attemptsByTable.removeValue(forKey: table ?? "")
    }

    /// Forgets every recorded reload, for example when the document reconnects.
    @objc func resetAll() {
        lock.lock()
        defer { lock.unlock() }

        attemptsByTable.removeAll()
    }
}


/// Decides when a table load may reload the table again, and when that reload
/// is allowed to start.
///
/// A load that finds the column list disagreeing with the result asks for a
/// full reload. Starting it from inside the load that asked would run one load
/// inside the next without end, and starting it while the enclosing document
/// task is still closing would hand the new query a Stop button that the old
/// task then switches off. The load therefore only leaves a note here, and the
/// reload task, or the end of the document's task, takes the note once nothing
/// else is loading.
@objc(SATableReloadCoordinator)
final class SATableReloadCoordinator: NSObject {

    private let policy: SATableReloadRetryPolicy
    private let lock = NSLock()
    private var loadDepth = 0
    private var reloadTaskIsRunning = false
    private var reloadIsNoted = false

    /// Creates a coordinator that bounds self-triggered reloads with `policy`.
    ///
    /// - Parameter policy: The budget to spend on automatic reloads.
    @objc init(policy: SATableReloadRetryPolicy) {
        self.policy = policy
        super.init()
    }

    /// Creates a coordinator with a policy of the default size.
    @objc override convenience init() {
        self.init(policy: SATableReloadRetryPolicy())
    }

    /// Records that a table load has started.
    @objc func loadDidBegin() {
        lock.lock()
        loadDepth += 1
        lock.unlock()
    }

    /// Records that a table load has finished.
    @objc func loadDidEnd() {
        lock.lock()
        if loadDepth > 0 { loadDepth -= 1 }
        lock.unlock()
    }

    /// Records that the reload task has begun running its rounds.
    @objc func reloadTaskDidBegin() {
        lock.lock()
        reloadTaskIsRunning = true
        reloadIsNoted = false
        lock.unlock()
    }

    /// Records that the reload task is through, dropping a note it did not use.
    @objc func reloadTaskDidEnd() {
        lock.lock()
        reloadTaskIsRunning = false
        reloadIsNoted = false
        lock.unlock()
    }

    /// Notes that a table wants a full reload of itself.
    ///
    /// - Parameter table: The table asking to be reloaded.
    /// - Returns: `true` while the table's budget lasts. `false` means the
    ///   reloads have not settled anything and the caller should stop and say so.
    @objc func noteFullReload(forTable table: String?) -> Bool {
        guard policy.shouldReload(forTable: table) else { return false }

        lock.lock()
        reloadIsNoted = true
        lock.unlock()
        return true
    }

    /// Takes a note for the reload task's next round.
    ///
    /// - Returns: `true` when the task should load once more.
    @objc func takeNoteForReloadTask() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard reloadIsNoted else { return false }
        reloadIsNoted = false
        return true
    }

    /// Takes a note when no load and no reload task is still running.
    ///
    /// - Returns: `true` when a reload worker should be started now.
    @objc func takeNoteWhenIdle() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard reloadIsNoted, !reloadTaskIsRunning, loadDepth == 0 else { return false }
        reloadIsNoted = false
        return true
    }

    /// Forgets the reloads recorded for one table, after a load that matched.
    ///
    /// - Parameter table: The table whose budget is refilled.
    @objc func reset(forTable table: String?) {
        policy.reset(forTable: table)
    }

    /// Forgets every recorded reload and any note not taken yet.
    @objc func resetAll() {
        policy.resetAll()
        lock.lock()
        reloadIsNoted = false
        lock.unlock()
    }

    /// How many automatic reloads a table has used, for the message that reports
    /// giving up.
    ///
    /// - Parameter table: The table to report on.
    /// - Returns: The number of reloads recorded since the last reset.
    @objc func attemptCount(forTable table: String?) -> Int {
        policy.attemptCount(forTable: table)
    }
}
