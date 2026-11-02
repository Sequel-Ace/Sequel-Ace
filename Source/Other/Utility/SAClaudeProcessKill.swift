import Foundation

/// What a Process List kill acts on.
enum SAClaudeProcessKillKind: Equatable {
    case query, connection
}

/// How a kill request ended. `.changed` means nothing was killed: the connection is now running something other than
/// the query the caller showed, so the caller must confirm and ask again with `current.info` as the expected query.
enum SAClaudeProcessKillOutcome: Equatable {
    case killed
    case changed(current: SAClaudeProcess)
    case ended
    case failed(message: String)
}

/// The result of one statement run by a Process List backend.
enum SAClaudeProcessStatementResult: Equatable {
    case ok
    case error(id: UInt, message: String)
}

/// Pure kill rules for the Process List. Kills always name a connection id the caller captured from the row it showed
/// (the detail panel's connection, or the row the context menu was opened on) — never a row index — so a refresh that
/// reorders or replaces rows cannot retarget them.
enum SAClaudeProcessKillDecision {
    /// MySQL's ER_NO_SUCH_THREAD ("Unknown thread id"): the connection ended before the kill reached it.
    static let unknownThreadErrorID: UInt = 1094

    enum Preflight: Equatable {
        case proceed
        case changed(current: SAClaudeProcess)
        case ended
    }

    /// The id a kill acts on: the shown connection's id while it is still in the latest list; nil once it has ended
    /// (which disables both kill buttons).
    static func killTarget(shownId: Int64?, in current: [SAClaudeProcess]) -> Int64? {
        guard let shownId, current.contains(where: { $0.id == shownId }) else { return nil }
        return shownId
    }

    static func canKill(shownId: Int64?, in current: [SAClaudeProcess]) -> Bool {
        killTarget(shownId: shownId, in: current) != nil
    }

    /// Whether the connection's current query differs from the query the caller showed. Compared exactly (the server
    /// reports a query as it was sent); a connection that went idle (no query) differs from any shown query.
    static func queryChanged(shown: String?, current: String?) -> Bool {
        normalized(shown) != normalized(current)
    }

    /// Decides a kill against a fresh re-read of the process list. Kill query proceeds only while the connection still
    /// runs the shown query; kill connection only needs the connection to exist.
    static func preflight(kind: SAClaudeProcessKillKind, id: Int64, expectedQuery: String?, current: [SAClaudeProcess]) -> Preflight {
        guard let process = current.first(where: { $0.id == id }) else { return .ended }
        if kind == .query, queryChanged(shown: expectedQuery, current: process.info) { return .changed(current: process) }
        return .proceed
    }

    /// The statement for a kill; TiDB spells it `KILL TIDB …` (as SPMySQL's `killQueryOnThreadID:` does).
    static func statement(kind: SAClaudeProcessKillKind, id: Int64, isTiDB: Bool) -> String {
        "KILL" + (isTiDB ? " TIDB" : "") + (kind == .query ? " QUERY " : " CONNECTION ") + String(id)
    }

    static func isTiDB(serverVersion: String?) -> Bool {
        (serverVersion ?? "").contains("TiDB")
    }

    static func outcome(of result: SAClaudeProcessStatementResult) -> SAClaudeProcessKillOutcome {
        switch result {
        case .ok: return .killed
        case let .error(id, message): return id == unknownThreadErrorID ? .ended : .failed(message: message)
        }
    }

    /// Today's row shape (what `SPProcessListController` keeps, serializes and saves): SPMySQL returns every column as
    /// a string, so `Id` becomes a 64-bit NSNumber and `Time` a 32-bit NSNumber; everything else is untouched.
    static func normalizedRow(_ row: [String: Any]) -> [String: Any] {
        var fixed = row
        if let id = row["Id"] as? String { fixed["Id"] = NSNumber(value: (id as NSString).longLongValue) }
        if let time = row["Time"] as? String { fixed["Time"] = NSNumber(value: (time as NSString).intValue) }
        return fixed
    }

    /// A query clipped for an alert: at most `limit` characters, with "…" when clipped.
    static func alertExcerpt(_ query: String, limit: Int = 600) -> String {
        guard query.count > limit else { return query }
        return String(query.prefix(limit)) + "…"
    }

    private static func normalized(_ query: String?) -> String? {
        guard let query, !query.isEmpty else { return nil }
        return query
    }
}
