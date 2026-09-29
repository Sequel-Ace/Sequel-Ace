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
