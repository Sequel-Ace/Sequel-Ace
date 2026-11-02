import Foundation

/// One row of SHOW FULL PROCESSLIST, typed. `init?(row:)` accepts the dictionaries
/// `SPProcessListController` holds (`Id`/`Time` as NSNumber, text columns as String or NSNull).
struct SAClaudeProcess: Equatable {
    var id: Int64
    var user: String
    var host: String
    var db: String?
    var command: String
    var time: Int
    var state: String?
    var info: String?

    init(id: Int64, user: String, host: String, db: String?, command: String, time: Int, state: String?, info: String?) {
        self.id = id
        self.user = user
        self.host = host
        self.db = db
        self.command = command
        self.time = time
        self.state = state
        self.info = info
    }

    /// Column names match case-insensitively; NSNull and missing text columns become nil (`db`, `state`, `info`)
    /// or "" (`user`, `host`, `command`); a missing or negative `Time` is 0. A row without a readable `Id` is nil.
    init?(row: [String: Any]) {
        var lowered: [String: Any] = [:]
        for (key, value) in row { lowered[key.lowercased()] = value }

        func number(_ key: String) -> Int64? {
            guard let value = lowered[key], !(value is NSNull) else { return nil }
            if let n = value as? NSNumber {
                let d = n.doubleValue
                guard d.isFinite else { return nil }
                return n.int64Value
            }
            if let s = value as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if let i = Int64(t) { return i }
                if let d = Double(t), d.isFinite, abs(d) < 9e18 { return Int64(d) }
            }
            return nil
        }
        func text(_ key: String) -> String? {
            guard let value = lowered[key], !(value is NSNull) else { return nil }
            if let s = value as? String { return s }
            return String(describing: value)
        }

        guard let id = number("id") else { return nil }
        self.init(id: id,
                  user: text("user") ?? "",
                  host: text("host") ?? "",
                  db: text("db"),
                  command: text("command") ?? "",
                  time: Int(clamping: max(0, number("time") ?? 0)),
                  state: text("state"),
                  info: text("info"))
    }
}

enum SAClaudeProcessGroup { case needsAttention, running, idle }

/// Pure triage rules for the Process List. Precedence: Sleep or a background (replication/system) thread is idle
/// and never red; then a lock wait (the word "lock" starts a word in the state: "metadata lock", "Locked", but not
/// "block"/"clock") needs attention at any time; then a command running longer than the threshold needs attention
/// (this includes other "Waiting for …" states such as handler commit or semi-sync ACK, which are normally brief);
/// anything else is running.
enum SAClaudeProcessClassifier {
    static let thresholds: [Int] = [10, 30, 60, 300]
    static let defaultThreshold = 30
    static let thresholdKey = "ClaudeProcessListAttentionSeconds"

    private static let backgroundCommands = ["binlog dump", "daemon", "delayed insert"]   // prefix match covers "Binlog Dump GTID"
    private static let backgroundUsers = ["system user", "event_scheduler"]
    private static let backgroundStatePrefixes = ["waiting for source", "waiting for an event from coordinator", "waiting for master"]

    static func isBackground(_ p: SAClaudeProcess) -> Bool {
        let command = p.command.lowercased()
        if backgroundCommands.contains(where: { command.hasPrefix($0) }) { return true }
        if backgroundUsers.contains(p.user.lowercased()) { return true }
        let state = (p.state ?? "").lowercased()
        return backgroundStatePrefixes.contains { state.hasPrefix($0) }
    }

    private static func isSleeping(_ p: SAClaudeProcess) -> Bool {
        p.command.caseInsensitiveCompare("Sleep") == .orderedSame
    }

    private static func isLockWait(_ p: SAClaudeProcess) -> Bool {
        return (p.state ?? "").range(of: "\\block", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func group(_ p: SAClaudeProcess, threshold: Int) -> SAClaudeProcessGroup {
        if isSleeping(p) || isBackground(p) { return .idle }
        if isLockWait(p) { return .needsAttention }
        return p.time > threshold ? .needsAttention : .running
    }

    /// "2s", "6m 41s", "1h 02m".
    static func timeText(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m " + pad(s % 60) + "s" }
        return "\(s / 3600)h " + pad((s % 3600) / 60) + "m"
    }

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// Case-insensitive substring match over id, user, host, database, state and query text.
    /// An empty (or whitespace-only) search matches everything.
    static func matches(_ p: SAClaudeProcess, search: String) -> Bool {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return true }
        let fields: [String?] = [String(p.id), p.user, p.host, p.db, p.state, p.info]
        return fields.contains { $0?.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// The connection's user is the window's connection user (host ignored; MySQL user names are case-sensitive).
    static func isMine(_ p: SAClaudeProcess, user: String) -> Bool {
        !user.isEmpty && p.user == user
    }

    /// Needs attention, then running, then idle (sleeping clients before background threads); longest time first
    /// within a group; ties by id.
    static func sorted(_ ps: [SAClaudeProcess], threshold: Int) -> [SAClaudeProcess] {
        func rank(_ g: SAClaudeProcessGroup) -> Int {
            switch g { case .needsAttention: return 0; case .running: return 1; case .idle: return 2 }
        }
        // Real sleeping clients come before background threads (whose times are huge) inside the idle group.
        let keyed = ps.map { (process: $0, rank: rank(group($0, threshold: threshold)) * 2 + (isBackground($0) ? 1 : 0)) }
        return keyed.sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.process.time != b.process.time { return a.process.time > b.process.time }
            return a.process.id < b.process.id
        }.map(\.process)
    }
}
