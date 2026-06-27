//
//  SPAppController+MCP.swift
//  Sequel Ace
//
//  Created for Sequel Ace by contributors.
//  See https://github.com/Sequel-Ace/Sequel-Ace/issues/2314
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
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

import AppKit
import Foundation
import ObjectiveC
import OSLog

private let mcpDefaultPort: Int   = 8765
private let mcpMaxResultRows: Int  = 10000   // Safety cap for run_query.

private let mcpLog = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "MCP")

// Serial background queue used for all MCP database operations.
private let mcpDBQueue = DispatchQueue(label: "com.sequel-ace.mcp.db")

// Last MCP configuration we acted on, so we ignore the frequent
// NSUserDefaultsDidChangeNotification callbacks that do not touch our keys.
private final class MCPDesiredState {
    static let shared = MCPDesiredState()
    var known = false
    var enabled = false
    var port: UInt16 = 0
}

// Stable id attached to each open document for its lifetime, so the agent can
// target a specific tab. (processID is not reliably populated.)
private var mcpDocIDKey: UInt8 = 0

private func mcpDocumentID(_ doc: SPDatabaseDocument?) -> String {
    guard let doc = doc else { return "" }
    if let existing = objc_getAssociatedObject(doc, &mcpDocIDKey) as? String {
        return existing
    }
    let newID = UUID().uuidString
    objc_setAssociatedObject(doc, &mcpDocIDKey, newID, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return newID
}

private func mcpClampedPort(_ prefs: UserDefaults) -> UInt16 {
    var port = prefs.integer(forKey: SPMCPServerPort)
    if port < 1024 || port > 65535 { port = mcpDefaultPort }
    return UInt16(port)
}

// Escape an identifier (database/table/routine name) for use inside backticks.
private func mcpQuoteIdentifier(_ name: String) -> String {
    return name.replacingOccurrences(of: "`", with: "``")
}

// -escapeAndQuoteString: imports as an implicitly-unwrapped optional (String!);
// binding or interpolating it directly yields "Optional('value')" in the SQL.
// This wrapper pins the result to a plain String.
private func mcpEscapeQuoted(_ value: String, _ conn: SPMySQLConnection) -> String {
    if let quoted = conn.escapeAndQuoteString(value) { return quoted }
    // escapeAndQuoteString can return nil (e.g. when the connection is unavailable).
    // Fall back to basic SQL-literal quoting so we never force-unwrap into a crash.
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "'", with: "''")
    return "'\(escaped)'"
}

// Path split into components, dropping the leading "/" element. Inputs are already
// symlink-resolved and standardized, so there are no "." or ".." elements.
private func mcpPathComponents(_ path: String) -> [String] {
    return (path as NSString).pathComponents.filter { $0 != "/" && !$0.isEmpty }
}

// Open an export file by walking the directory chain from `base` one component at a
// time with O_NOFOLLOW, so no component (not just the final one) can be swapped for a
// symlink to redirect the write outside the export folder. Creates intermediate dirs.
// Returns an open fd (caller closes), or (-1, error).
private func mcpOpenExportFile(base: String, relativeDirs: [String], filename: String) -> (fd: Int32, error: String?) {
    var fd = open(base, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    if fd < 0 { return (-1, "Could not open export folder (\(String(cString: strerror(errno))))") }
    for dir in relativeDirs {
        mkdirat(fd, dir, 0o700)   // ignore result; an existing dir (EEXIST) is fine
        let next = openat(fd, dir, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        let openErr = errno
        close(fd)
        if next < 0 {
            return (-1, "Could not open export subdirectory '\(dir)' (\(String(cString: strerror(openErr))))")
        }
        fd = next
    }
    let fileFD = openat(fd, filename, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0o600)
    let fileErr = errno
    close(fd)
    if fileFD < 0 { return (-1, "Could not open export file (\(String(cString: strerror(fileErr))))") }
    return (fileFD, nil)
}

// MySQL can return text columns as NSData; decode to a string so values are
// usable directly (not just at JSON-serialisation time). Non-data values pass through.
// Genuinely binary data (BLOB/VARBINARY, non-UTF-8 bytes) is base64-encoded rather
// than rendered as NSData's description (`{length = N, bytes = 0x...}`), which is junk.
private func mcpDecode(_ value: Any?) -> Any {
    if let data = value as? Data {
        return String(data: data, encoding: .utf8) ?? data.base64EncodedString()
    }
    return value ?? NSNull()
}

// A resolved, live connection plus the document metadata the tools report back.
private struct MCPResolvedConnection {
    let conn: SPMySQLConnection
    let id: String
    let database: String
    let host: String
}

extension SPAppController: SPMCPDataSource {

    // MARK: - Lifecycle

    /// Start the MCP server if enabled in preferences. Called from applicationDidFinishLaunching.
    @objc func setupMCPServer() {
        SPMCPServer.shared.dataSource = self

        // Observe preference changes to start/stop the server dynamically.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(mcpDefaultsChanged(_:)),
                                               name: UserDefaults.didChangeNotification,
                                               object: nil)

        let prefs = UserDefaults.standard
        let state = MCPDesiredState.shared
        state.known = true
        state.enabled = prefs.bool(forKey: SPMCPServerEnabled)
        state.port = mcpClampedPort(prefs)
        if state.enabled {
            startMCPServer(with: prefs)
        }
    }

    /// Respond to preference changes (NSUserDefaultsDidChangeNotification).
    @objc func mcpDefaultsChanged(_ notification: Notification) {
        let prefs = UserDefaults.standard
        let shouldRun = prefs.bool(forKey: SPMCPServerEnabled)
        let desiredPort = mcpClampedPort(prefs)

        // NSUserDefaultsDidChangeNotification fires for any pref change in the app;
        // only react when the MCP enable flag or port actually changed, otherwise a
        // failed start would be retried (and re-alert) on every unrelated change.
        let state = MCPDesiredState.shared
        if state.known && shouldRun == state.enabled && desiredPort == state.port {
            return
        }
        state.known = true
        state.enabled = shouldRun
        state.port = desiredPort

        if shouldRun {
            // startMCPServer(with:) stops any existing listener first, so this covers
            // both a fresh enable and a port change.
            startMCPServer(with: prefs)
        } else if SPMCPServer.shared.isRunning {
            SPMCPServer.shared.stop()
            os_log(.info, log: mcpLog, "MCP server stopped.")
        }
    }

    private func startMCPServer(with prefs: UserDefaults) {
        let port = mcpClampedPort(prefs)
        SPMCPServer.shared.start(port: port) { success, errorMsg in
            if success {
                os_log(.info, log: mcpLog, "MCP server started on port %u", port)
            } else {
                os_log(.error, log: mcpLog, "MCP server failed to start: %{public}@", errorMsg ?? "unknown error")
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = NSLocalizedString("MCP Server Error", comment: "MCP start error title")
                    alert.informativeText = String(format: NSLocalizedString(
                        "The MCP server could not start on port %ld: %@\n\nYou can change the port in Preferences > MCP Server.",
                        comment: "MCP start error message"),
                        Int(port), errorMsg ?? "unknown error")
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Connection resolution

    // Resolve a connection id (nil/empty -> front document) to its live connection.
    // Returns nil if not connected. Reads document state on the main thread.
    private func mcpResolveConnection(_ connID: String) -> MCPResolvedConnection? {
        var info: MCPResolvedConnection?
        let resolve = {
            let wcs = self.tabManager.windowControllers
            var doc: SPDatabaseDocument?
            if !connID.isEmpty {
                for wc in wcs where mcpDocumentID(wc.databaseDocument) == connID {
                    doc = wc.databaseDocument
                    break
                }
            } else {
                doc = self.frontDocument()
                // frontDocument is nil when the app is not frontmost (it relies on the
                // active window), so fall back to the first connected tab.
                if !(doc != nil && doc!.isProcessing == false && (doc!.getConnection()?.isConnected() ?? false)) {
                    doc = nil
                    for wc in wcs {
                        let d = wc.databaseDocument
                        if !d.isProcessing, let c = d.getConnection(), c.isConnected() { doc = d; break }
                    }
                }
            }
            if let doc = doc, !doc.isProcessing, let c = doc.getConnection(), c.isConnected() {
                info = MCPResolvedConnection(conn: c, id: mcpDocumentID(doc),
                                             database: doc.database() ?? "", host: doc.host() ?? "")
            }
        }
        if Thread.isMainThread { resolve() } else { DispatchQueue.main.sync(execute: resolve) }
        return info
    }

    private func mcpNoConnectionError() -> [String: Any] {
        return ["error": "No matching database connection. Connect in Sequel Ace, or pass a valid connection id from list_connections."]
    }

    // Runs `block` on the serial DB queue and returns its result dictionary.
    private func mcpDBSync(_ block: () -> [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        mcpDBQueue.sync { result = block() }
        return result
    }

    // MARK: - SPMCPDataSource: connections

    public func mcpListConnections() -> [[String: Any]] {
        var result: [[String: Any]] = []
        let collect = {
            let front = self.frontDocument()
            for wc in self.tabManager.windowControllers {
                let doc = wc.databaseDocument
                let c = doc.isProcessing ? nil : doc.getConnection()
                guard let conn = c, conn.isConnected() else { continue }
                var info: [String: Any] = [:]
                info["id"] = mcpDocumentID(doc)
                let displayName = doc.displayName() ?? ""
                info["name"] = displayName.isEmpty ? (doc.host() ?? "") : displayName
                if let host = doc.host(), !host.isEmpty { info["host"] = host }
                if let db = doc.database(), !db.isEmpty { info["database"] = db }
                info["active"] = (front != nil && doc == front)
                result.append(info)
            }
        }
        if Thread.isMainThread { collect() } else { DispatchQueue.main.sync(execute: collect) }
        return result
    }

    // MARK: - SPMCPDataSource: schema

    public func mcpListDatabases(onConnection connID: String) -> [String: Any] {
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        return mcpDBSync {
            let res = conn.queryString("SHOW DATABASES")
            if conn.queryErrored() { return ["error": conn.lastErrorMessage() ?? "Query error"] }
            res?.defaultRowReturnType = SPMySQLResultRowAsArray
            var dbs: [Any] = []
            while let row = res?.getRowAsArray() as? [Any] {
                if let first = row.first, !(first is NSNull) { dbs.append(mcpDecode(first)) }
            }
            return ["databases": dbs, "connection": ci.id]
        }
    }

    public func mcpListTables(inDatabase database: String, connection connID: String) -> [String: Any] {
        if database.isEmpty { return ["error": "database argument is required"] }
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        return mcpDBSync {
            let res = conn.queryString("SHOW FULL TABLES IN `\(mcpQuoteIdentifier(database))`")
            if conn.queryErrored() { return ["error": conn.lastErrorMessage() ?? "Query error"] }
            res?.defaultRowReturnType = SPMySQLResultRowAsArray
            var tables: [[String: Any]] = []
            while let row = res?.getRowAsArray() as? [Any] {
                guard let first = row.first, !(first is NSNull) else { continue }
                var entry: [String: Any] = ["name": mcpDecode(first)]
                if row.count > 1, !(row[1] is NSNull) { entry["type"] = mcpDecode(row[1]) }
                tables.append(entry)
            }
            return ["tables": tables, "connection": ci.id]
        }
    }

    public func mcpDescribeTable(_ table: String, inDatabase database: String, connection connID: String) -> [String: Any] {
        if table.isEmpty || database.isEmpty { return ["error": "Both database and table arguments are required"] }
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        return mcpDBSync {
            let qualified = "`\(mcpQuoteIdentifier(database))`.`\(mcpQuoteIdentifier(table))`"

            var columns: [[String: Any]] = []
            let colRes = conn.queryString("SHOW FULL COLUMNS FROM \(qualified)")
            if conn.queryErrored() { return ["error": conn.lastErrorMessage() ?? "Could not describe table"] }
            while let row = colRes?.getRowAsDictionary() as? [String: Any] {
                var col: [String: Any] = [:]
                for k in ["Field", "Type", "Null", "Key", "Default", "Extra", "Comment"] {
                    if let v = row[k], !(v is NSNull) { col[k] = mcpDecode(v) }
                }
                columns.append(col)
            }

            var indexes: [[String: Any]] = []
            let idxRes = conn.queryString("SHOW INDEX FROM \(qualified)")
            if !conn.queryErrored() {
                while let row = idxRes?.getRowAsDictionary() as? [String: Any] {
                    var idx: [String: Any] = [:]
                    for k in ["Key_name", "Column_name", "Non_unique", "Index_type"] {
                        if let v = row[k], !(v is NSNull) { idx[k] = mcpDecode(v) }
                    }
                    indexes.append(idx)
                }
            }

            var foreignKeys: [[String: Any]] = []
            let fkSQL = "SELECT COLUMN_NAME, CONSTRAINT_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME "
                + "FROM information_schema.KEY_COLUMN_USAGE "
                + "WHERE TABLE_SCHEMA = \(mcpEscapeQuoted(database, conn)) "
                + "AND TABLE_NAME = \(mcpEscapeQuoted(table, conn)) AND REFERENCED_TABLE_NAME IS NOT NULL"
            let fkRes = conn.queryString(fkSQL)
            if !conn.queryErrored() {
                while let row = fkRes?.getRowAsDictionary() as? [String: Any] {
                    var fk: [String: Any] = [:]
                    for k in ["COLUMN_NAME", "CONSTRAINT_NAME", "REFERENCED_TABLE_NAME", "REFERENCED_COLUMN_NAME"] {
                        if let v = row[k], !(v is NSNull) { fk[k] = mcpDecode(v) }
                    }
                    foreignKeys.append(fk)
                }
            }

            return ["columns": columns, "indexes": indexes,
                    "foreignKeys": foreignKeys, "connection": ci.id]
        }
    }

    public func mcpTableDDL(_ table: String, inDatabase database: String, connection connID: String) -> [String: Any] {
        if table.isEmpty || database.isEmpty { return ["error": "Both database and table arguments are required"] }
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        return mcpDBSync {
            let qualified = "`\(mcpQuoteIdentifier(database))`.`\(mcpQuoteIdentifier(table))`"
            let res = conn.queryString("SHOW CREATE TABLE \(qualified)")
            if conn.queryErrored() || res == nil { return ["error": conn.lastErrorMessage() ?? "Could not read table DDL"] }
            var ddl = ""
            if let row = res?.getRowAsDictionary() as? [String: Any] {
                // SPMySQL may return the DDL column as NSData; decode it (a plain
                // `as? String` cast would fail and leave the DDL empty).
                if let raw = row["Create Table"] ?? row["Create View"], !(raw is NSNull) {
                    ddl = "\(mcpDecode(raw))"
                }
            }
            return ["ddl": ddl, "connection": ci.id]
        }
    }

    // type: "view" | "procedure" | "function" | "trigger" | "event"
    public func mcpListRoutines(ofType type: String, inDatabase database: String, connection connID: String) -> [String: Any] {
        if database.isEmpty { return ["error": "database argument is required"] }
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        let t = type.lowercased()
        return mcpDBSync {
            let db = mcpEscapeQuoted(database, conn)
            let sql: String
            switch t {
            case "view":
                sql = "SELECT TABLE_NAME AS name FROM information_schema.VIEWS WHERE TABLE_SCHEMA = \(db) ORDER BY TABLE_NAME"
            case "procedure", "function":
                let routineType = (t == "procedure") ? "PROCEDURE" : "FUNCTION"
                sql = "SELECT ROUTINE_NAME AS name FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = \(db) AND ROUTINE_TYPE = '\(routineType)' ORDER BY ROUTINE_NAME"
            case "trigger":
                sql = "SELECT TRIGGER_NAME AS name, EVENT_OBJECT_TABLE AS table_name, EVENT_MANIPULATION AS event, ACTION_TIMING AS timing FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = \(db) ORDER BY TRIGGER_NAME"
            case "event":
                sql = "SELECT EVENT_NAME AS name, STATUS AS status FROM information_schema.EVENTS WHERE EVENT_SCHEMA = \(db) ORDER BY EVENT_NAME"
            default:
                return ["error": "type must be one of: view, procedure, function, trigger, event"]
            }
            let res = conn.queryString(sql)
            if conn.queryErrored() { return ["error": conn.lastErrorMessage() ?? "Query error"] }
            var items: [[String: Any]] = []
            while let row = res?.getRowAsDictionary() as? [String: Any] {
                var entry: [String: Any] = [:]
                for (k, v) in row where !(v is NSNull) { entry[k] = mcpDecode(v) }
                items.append(entry)
            }
            return ["items": items, "connection": ci.id]
        }
    }

    public func mcpRoutineDefinition(ofType type: String, name: String, inDatabase database: String, connection connID: String) -> [String: Any] {
        if type.isEmpty || name.isEmpty || database.isEmpty { return ["error": "type, name and database arguments are required"] }
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        let t = type.uppercased()
        let allowed = ["PROCEDURE", "FUNCTION", "TRIGGER", "VIEW", "EVENT"]
        if !allowed.contains(t) { return ["error": "type must be one of: procedure, function, trigger, view, event"] }

        return mcpDBSync {
            // SHOW CREATE TRIGGER does not accept a schema-qualified name and uses the
            // connection's current database. Rather than mutate the shared connection's
            // default DB, reconstruct the trigger from information_schema (schema-scoped).
            if t == "TRIGGER" {
                let sql = "SELECT ACTION_TIMING, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_STATEMENT "
                    + "FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = \(mcpEscapeQuoted(database, conn)) "
                    + "AND TRIGGER_NAME = \(mcpEscapeQuoted(name, conn))"
                let res = conn.queryString(sql)
                if conn.queryErrored() || res == nil { return ["error": conn.lastErrorMessage() ?? "Could not read definition"] }
                guard let row = res?.getRowAsDictionary() as? [String: Any] else { return ["error": "Trigger not found"] }
                let timing = "\(mcpDecode(row["ACTION_TIMING"]))"
                let event = "\(mcpDecode(row["EVENT_MANIPULATION"]))"
                let onTable = mcpQuoteIdentifier("\(mcpDecode(row["EVENT_OBJECT_TABLE"]))")
                let statement = "\(mcpDecode(row["ACTION_STATEMENT"]))"
                let def = "CREATE TRIGGER `\(mcpQuoteIdentifier(name))` \(timing) \(event) ON `\(onTable)` FOR EACH ROW \(statement)"
                return ["definition": def, "connection": ci.id]
            }

            let qualified = "`\(mcpQuoteIdentifier(database))`.`\(mcpQuoteIdentifier(name))`"
            let res = conn.queryString("SHOW CREATE \(t) \(qualified)")
            if conn.queryErrored() || res == nil { return ["error": conn.lastErrorMessage() ?? "Could not read definition"] }
            var def = ""
            if let row = res?.getRowAsDictionary() as? [String: Any] {
                for (k, v) in row where (k.hasPrefix("Create ") || k == "SQL Original Statement") {
                    // SPMySQL may return the definition column as NSData; decode it so
                    // we emit the SQL text, not the NSData byte/length description.
                    if !(v is NSNull) { def = "\(mcpDecode(v))"; break }
                }
            }
            return ["definition": def, "connection": ci.id]
        }
    }

    // MARK: - SPMCPDataSource: queries

    public func mcpRunQuery(_ sql: String, params: [Any], limit: Int, offset: Int, connection connID: String) -> [String: Any] {
        if sql.isEmpty { return ["error": "sql argument is required"] }
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn

        // Bind ? placeholders to escaped literals (injection-safe).
        var bound = sql
        if !params.isEmpty {
            let (result, err) = mcpBindParams(params, intoSQL: sql, connection: conn)
            guard let boundSQL = result else { return ["error": err ?? "Parameter binding failed"] }
            bound = boundSQL
            // The dispatcher validated the UNBOUND sql; a placeholder inside a comment
            // (e.g. `SELECT 1 /* ? */`) lets a param close the comment and smuggle
            // INTO OUTFILE etc. past that check. Re-validate the BOUND sql - what
            // actually runs - so the read-only boundary holds.
            if UserDefaults.standard.bool(forKey: SPMCPReadOnly), !SPMCPReadOnlyGuard.isReadOnly(bound) {
                return ["error": "Read-only mode is enabled. Only single, non-destructive read statements (SELECT, SHOW, DESCRIBE, EXPLAIN) are allowed. Turn off read-only mode in Sequel Ace Preferences > MCP Server to run write queries."]
            }
        }

        // Cap how many rows the query may return so the database does not materialise a
        // huge result. The analysis runs on a COMMENT-STRIPPED copy (and that stripped
        // copy is what we execute for capped SELECTs): otherwise a leading comment
        // (`/* x */ SELECT ...`) hides the SELECT prefix and skips the cap, and a
        // trailing line comment (`... -- LIMIT 1`) looks like a real LIMIT that MySQL
        // actually ignores. Appending LIMIT (rather than wrapping in a derived table)
        // keeps SELECT * joins with duplicate column names working. Only plain SELECTs
        // (or a parenthesised SELECT/UNION) are capped: a CTE can precede a data-changing
        // statement (WITH ... UPDATE/DELETE), so capping a WITH query could limit a write.
        let cap = mcpMaxResultRows
        var finalSQL = bound
        var maxRows = cap
        // Executable comments (/*! ... */, MariaDB /*M! ... */) change semantics, so
        // don't rewrite those; fall back to the read-side cap (in read-only mode the
        // guard already rejects them).
        if !SPMCPReadOnlyGuard.hasExecutableComment(bound) {
            var t = SPMCPReadOnlyGuard.stripCommentsQuoteAware(bound).trimmingCharacters(in: .whitespacesAndNewlines)
            while t.hasSuffix(";") { t = String(t.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
            let up = t.uppercased()
            if up.hasPrefix("SELECT") || up.hasPrefix("(") {
                if let clamp = mcpClampTrailingLimit(t, cap: cap) {
                    // Has its own trailing LIMIT. Execute the stripped query; if the
                    // limit exceeds the cap, shrink it so the DB stops at the cap.
                    finalSQL = clamp.count > cap ? clamp.clamped : t
                    maxRows = min(clamp.count, cap)
                } else {
                    // No trailing LIMIT: append one so the database stops at the cap.
                    // The +1 lets us detect that more rows existed (truncation).
                    let effectiveLimit = limit > 0 ? min(limit, cap) : cap
                    maxRows = effectiveLimit
                    let off = max(0, offset)
                    finalSQL = off > 0 ? "\(t) LIMIT \(effectiveLimit + 1) OFFSET \(off)" : "\(t) LIMIT \(effectiveLimit + 1)"
                }
            }
        }

        return mcpDBSync {
            mcpExecuteResultQuery(finalSQL, onConnection: conn, connectionID: ci.id, maxRows: maxRows)
        }
    }

    /// Parses a trailing `LIMIT` clause and returns its row count plus a copy of the
    /// query with that count clamped to `cap + 1` (preserving any offset form), or nil
    /// if there is no trailing LIMIT. Lets run_query enforce the row cap even when the
    /// caller supplied an explicit LIMIT larger than the cap.
    private func mcpClampTrailingLimit(_ sql: String, cap: Int) -> (count: Int, clamped: String)? {
        let pattern = "(?i)\\blimit\\s+([0-9]+)(?:\\s*,\\s*([0-9]+)|\\s+offset\\s+([0-9]+))?\\s*$"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = sql as NSString
        guard let m = re.firstMatch(in: sql, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        let first = group(1) ?? "0"      // `LIMIT first` or, in the comma form, the offset
        let commaCount = group(2)        // `LIMIT offset, count`
        let offsetValue = group(3)       // `LIMIT count OFFSET value`
        let count = Int(commaCount ?? first) ?? 0
        let newCount = min(count, cap + 1)
        let clause: String
        if commaCount != nil {
            clause = "LIMIT \(first), \(newCount)"
        } else if let offsetValue = offsetValue {
            clause = "LIMIT \(newCount) OFFSET \(offsetValue)"
        } else {
            clause = "LIMIT \(newCount)"
        }
        return (count, ns.replacingCharacters(in: m.range, with: clause))
    }

    /// Substitutes each unquoted ? in `sql` with the next param as an escaped SQL
    /// literal. Returns (nil, error) if the placeholder and param counts differ.
    /// Quote- and comment-aware: a `?` inside a string literal or a comment is NOT a
    /// placeholder and is copied verbatim, so a `?` parked in a comment cannot turn
    /// param data into executable SQL (it just fails the placeholder/param count check).
    private func mcpBindParams(_ params: [Any], intoSQL sql: String, connection conn: SPMySQLConnection) -> (String?, String?) {
        var out = ""
        var pIndex = 0
        var quote: Character?
        let chars: [Character] = Array(sql)
        let n = chars.count
        var i = 0
        while i < n {
            let c = chars[i]
            if let q = quote {
                out.append(c)
                if c == "\\" && q != "`" {                       // backslash escape in a string literal
                    if i + 1 < n { out.append(chars[i + 1]); i += 1 }
                } else if c == q {
                    if i + 1 < n && chars[i + 1] == q {           // doubled-quote escape
                        out.append(q); i += 1
                    } else {
                        quote = nil
                    }
                }
                i += 1
                continue
            }
            // Comments are copied verbatim; a `?` inside one is not a placeholder.
            if c == "#" {                                        // # to end of line
                while i < n && chars[i] != "\n" { out.append(chars[i]); i += 1 }
                continue
            }
            if c == "-" && i + 1 < n && chars[i + 1] == "-" {    // -- (needs whitespace/EOL after)
                let next = i + 2 < n ? chars[i + 2] : " "
                if i + 2 >= n || next == " " || next == "\t" || next == "\n" || next == "\r" {
                    while i < n && chars[i] != "\n" { out.append(chars[i]); i += 1 }
                    continue
                }
            }
            if c == "/" && i + 1 < n && chars[i + 1] == "*" {    // /* ... */ block comment
                out.append("/"); out.append("*"); i += 2
                while i < n {
                    if i + 1 < n && chars[i] == "*" && chars[i + 1] == "/" {
                        out.append("*"); out.append("/"); i += 2; break
                    }
                    out.append(chars[i]); i += 1
                }
                continue
            }
            if c == "'" || c == "\"" || c == "`" { quote = c; out.append(c); i += 1; continue }
            if c == "?" {
                if pIndex >= params.count { return (nil, "More ? placeholders than params provided") }
                out.append(mcpSQLLiteral(for: params[pIndex], connection: conn))
                pIndex += 1
                i += 1
                continue
            }
            out.append(c)
            i += 1
        }
        if pIndex != params.count { return (nil, "More params than ? placeholders provided") }
        return (out, nil)
    }

    private func mcpSQLLiteral(for value: Any, connection conn: SPMySQLConnection) -> String {
        if value is NSNull { return "NULL" }
        if let num = value as? NSNumber { return num.stringValue }
        if let str = value as? String { return mcpEscapeQuoted(str, conn) }
        return mcpEscapeQuoted("\(value)", conn)
    }

    public func mcpKillProcessID(_ processID: String, connection connID: String) -> [String: Any] {
        let pid = Int64(processID) ?? 0
        if pid <= 0 { return ["error": "a positive numeric process id is required"] }
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        return mcpDBSync {
            _ = conn.queryString("KILL \(pid)")
            if conn.queryErrored() { return ["error": conn.lastErrorMessage() ?? "Could not kill process"] }
            return ["killed": pid, "connection": ci.id]
        }
    }

    // Runs a result-returning query and packages rows/columns, reading at most
    // `maxRows`. If a further row exists beyond that, the result is marked truncated.
    // Callers that can bound the query at the SQL level should also push a
    // `LIMIT maxRows + 1` so the database does not materialise an unbounded result.
    // Caller holds mcpDBQueue.
    private func mcpExecuteResultQuery(_ sql: String, onConnection conn: SPMySQLConnection, connectionID connID: String, maxRows: Int = mcpMaxResultRows) -> [String: Any] {
        let result = conn.queryString(sql)
        if conn.queryErrored() { return ["error": conn.lastErrorMessage() ?? "Query error"] }

        // Non-result statements (INSERT, UPDATE, DELETE, ...) come back as nil or an
        // SPMySQLEmptyResult (a successful write, not a result set). Report the affected
        // row count so a successful write is distinguishable from an empty SELECT.
        guard let res = result, !(res is SPMySQLEmptyResult) else {
            return ["columns": [], "rows": [],
                    "rowsAffected": conn.rowsAffectedByLastQuery(),
                    "connection": connID]
        }

        let fieldNames = (res.fieldNames() as? [String]) ?? []
        // Disambiguate duplicate column names (e.g. SELECT * across joined tables that
        // both have `id`). Rows are read as ordered arrays and packaged as objects, so
        // without this a later duplicate would overwrite an earlier one and a value
        // would be lost; suffixing keeps every value and keeps CSV headers aligned.
        // The suffix is bumped until it is actually unused, so it cannot collide with a
        // name that already exists (["id","id_2","id"] -> ["id","id_2","id_3"]).
        var usedNames = Set<String>()
        let columns: [String] = fieldNames.map { name in
            var candidate = name
            var suffix = 1
            while usedNames.contains(candidate) {
                suffix += 1
                candidate = "\(name)_\(suffix)"
            }
            usedNames.insert(candidate)
            return candidate
        }
        var rows: [[String: Any]] = []
        var truncated = false
        while let row = res.getRowAsArray() as? [Any] {
            if rows.count >= maxRows { truncated = true; break }   // a further row exists beyond the cap
            var safeRow: [String: Any] = [:]
            for (i, key) in columns.enumerated() {
                let val: Any = i < row.count ? row[i] : NSNull()
                if val is NSNull {
                    safeRow[key] = NSNull()
                } else if val is String || val is NSNumber {
                    safeRow[key] = val
                } else if let data = val as? Data {
                    // Text decodes as UTF-8; genuinely binary data is base64-encoded
                    // rather than NSData's "{length = N, bytes = 0x...}" description.
                    safeRow[key] = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
                } else {
                    safeRow[key] = "\(val)"
                }
            }
            rows.append(safeRow)
        }

        var r: [String: Any] = [:]
        r["columns"] = columns
        r["rows"] = rows
        r["rowCount"] = rows.count
        r["connection"] = connID
        if truncated {
            r["truncated"] = true
            r["truncatedAt"] = maxRows
        }
        return r
    }

    public func mcpExplainQuery(_ sql: String, connection connID: String) -> [String: Any] {
        if sql.isEmpty { return ["error": "sql argument is required"] }
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        // Plain EXPLAIN never executes the statement, but EXPLAIN ANALYZE does. The
        // dispatcher already blocks this; guard here too (defense in depth). ANALYZE
        // may follow other EXPLAIN modifiers (FORMAT=TREE ANALYZE ...) or hide behind
        // a /*! */ comment, so scan the whole modifier region rather than the prefix.
        if SPMCPReadOnlyGuard.explainWouldExecute(sql) {
            return ["error": "ANALYZE is not allowed; it would execute the statement"]
        }
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        return mcpDBSync {
            mcpExecuteResultQuery("EXPLAIN \(trimmed)", onConnection: conn, connectionID: ci.id)
        }
    }

    public func mcpSampleTable(_ table: String, inDatabase database: String, limit: Int, offset: Int, connection connID: String) -> [String: Any] {
        if table.isEmpty || database.isEmpty { return ["error": "Both database and table arguments are required"] }
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        var n = limit
        if n < 1 { n = 10 }
        if n > 1000 { n = 1000 }
        let off = max(0, offset)
        return mcpDBSync {
            let sql = "SELECT * FROM `\(mcpQuoteIdentifier(database))`.`\(mcpQuoteIdentifier(table))` LIMIT \(n) OFFSET \(off)"
            return mcpExecuteResultQuery(sql, onConnection: conn, connectionID: ci.id)
        }
    }

    public func mcpCountRows(inTable table: String, inDatabase database: String, connection connID: String) -> [String: Any] {
        if table.isEmpty || database.isEmpty { return ["error": "Both database and table arguments are required"] }
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        return mcpDBSync {
            let sql = "SELECT COUNT(*) AS count FROM `\(mcpQuoteIdentifier(database))`.`\(mcpQuoteIdentifier(table))`"
            let res = conn.queryString(sql)
            if conn.queryErrored() || res == nil { return ["error": conn.lastErrorMessage() ?? "Query error"] }
            res?.defaultRowReturnType = SPMySQLResultRowAsArray
            var count: Int64 = 0
            if let row = res?.getRowAsArray() as? [Any], let first = row.first {
                count = Int64("\(mcpDecode(first))") ?? 0
            }
            return ["count": count, "connection": ci.id]
        }
    }

    public func mcpExportResults(_ sql: String, format: String, path: String, connection connID: String) -> [String: Any] {
        if sql.isEmpty { return ["error": "sql argument is required"] }

        // Normalise and validate the format up front so an unsupported value is
        // rejected rather than silently written as JSON but reported as that value.
        let exportFormat = format.isEmpty ? "json" : format.lowercased()
        guard exportFormat == "json" || exportFormat == "csv" else {
            return ["error": "format must be one of: json, csv"]
        }

        // Confine writes to the configured export folder. An MCP tool path is
        // attacker-influencable (prompt injection), so never write to an arbitrary path.
        // Resolve symlinks so a link inside the folder cannot redirect writes outside it.
        let configuredBase = UserDefaults.standard.string(forKey: SPMCPExportPath) ?? ""
        var base = configuredBase
        if base.isEmpty {
            base = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first
                ?? NSTemporaryDirectory()
        }
        let realBase = (((base as NSString).standardizingPath as NSString).resolvingSymlinksInPath as NSString).standardizingPath

        // In a sandboxed build, a custom export folder (outside the default Downloads
        // entitlement) is only writable while its security-scoped bookmark is active.
        // The bookmark is keyed by the chosen folder URL; start access for the write
        // and stop it after. Best-effort: when there is no bookmark (default folder,
        // or a non-sandboxed build) this is nil and the write proceeds normally.
        var scopedURL: URL?
        if !configuredBase.isEmpty {
            let folderKey = URL(fileURLWithPath: configuredBase, isDirectory: true).absoluteString
            scopedURL = SecureBookmarkManager.sharedInstance.bookmarkFor(filename: folderKey)
        }
        defer { scopedURL?.stopAccessingSecurityScopedResource() }

        let filename = (path as NSString).lastPathComponent
        if filename.isEmpty || filename == "." || filename == ".." {
            return ["error": "Export path must include a filename"]
        }
        let parent = ((path as NSString).standardizingPath as NSString).deletingLastPathComponent
        let realParent = (((parent as NSString).resolvingSymlinksInPath as NSString).standardizingPath)
        let baseWithSlash = realBase.hasSuffix("/") ? realBase : realBase + "/"
        let inside = realParent == realBase || (realParent + "/").hasPrefix(baseWithSlash)
        if !inside {
            return ["error": "Export path must be inside the configured export folder: \(realBase)"]
        }
        let finalPath = (realParent as NSString).appendingPathComponent(filename)

        let queryResult = mcpRunQuery(sql, params: [], limit: 0, offset: 0, connection: connID)
        if queryResult["error"] != nil { return queryResult }
        // Report the resolved connection id (mcpRunQuery filled it in), so an empty
        // "active tab" request still returns the specific connection used.
        let resolvedConn = (queryResult["connection"] as? String) ?? connID
        // The query may have been capped (kMCPMaxResultRows); carry the signal through
        // so an agent does not treat a partial export as the complete result set.
        let truncated = queryResult["truncated"] as? Bool ?? false
        let truncatedAt = queryResult["truncatedAt"]

        let columns = (queryResult["columns"] as? [String]) ?? []
        let rows = (queryResult["rows"] as? [[String: Any]]) ?? []

        let content: String
        if exportFormat == "csv" {
            content = csvString(fromColumns: columns, rows: rows)
        } else {
            guard JSONSerialization.isValidJSONObject(queryResult) else {
                return ["error": "Result is not JSON-serializable"]
            }
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: queryResult, options: .prettyPrinted)
                content = String(data: jsonData, encoding: .utf8) ?? ""
            } catch {
                return ["error": error.localizedDescription]
            }
        }

        // Walk the directory chain from the (resolved, confined) export folder with
        // O_NOFOLLOW at every component, so no parent component can be swapped for a
        // symlink to redirect the write outside the folder - O_NOFOLLOW on the final
        // open alone would only guard the last component. realParent is inside realBase
        // (checked above), so the relative dirs are exactly the components between them.
        let relativeDirs = Array(mcpPathComponents(realParent).dropFirst(mcpPathComponents(realBase).count))
        let outData = content.data(using: .utf8) ?? Data()
        let opened = mcpOpenExportFile(base: realBase, relativeDirs: relativeDirs, filename: filename)
        guard opened.fd >= 0 else { return ["error": opened.error ?? "Could not open export file"] }
        let fd = opened.fd
        // 0600: exported rows can contain sensitive data, so keep them owner-only.
        // Re-apply the mode in case the file already existed (O_CREAT does not change
        // an existing file's permissions).
        if fchmod(fd, 0o600) != 0 {
            let err = String(cString: strerror(errno))
            close(fd)
            return ["error": "Could not secure export file permissions (\(err))"]
        }
        var ok = true
        outData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let basePtr = raw.baseAddress else { return }
            var total = 0
            while total < outData.count {
                let w = write(fd, basePtr.advanced(by: total), outData.count - total)
                if w <= 0 { ok = false; break }
                total += w
            }
        }
        close(fd)
        if !ok { return ["error": "Could not write export file"] }

        var response: [String: Any] = ["path": finalPath, "rowCount": rows.count,
                                       "format": exportFormat, "connection": resolvedConn]
        if truncated {
            response["truncated"] = true
            response["truncatedAt"] = truncatedAt ?? mcpMaxResultRows
        }
        return response
    }

    // MARK: - SPMCPDataSource: diagnostics

    public func mcpServerInfo(onConnection connID: String) -> [String: Any] {
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        return mcpDBSync {
            var info: [String: Any] = [:]
            let res = conn.queryString(
                "SHOW VARIABLES WHERE Variable_name IN "
                + "('version','version_comment','version_compile_os','protocol_version','max_connections','sql_mode','time_zone','character_set_server')")
            if !conn.queryErrored() {
                res?.defaultRowReturnType = SPMySQLResultRowAsArray
                while let row = res?.getRowAsArray() as? [Any] {
                    if row.count >= 2, !(row[0] is NSNull) {
                        let key = "\(mcpDecode(row[0]))"
                        info[key] = (row[1] is NSNull) ? "" : "\(mcpDecode(row[1]))"
                    }
                }
            }
            return ["variables": info, "connection": ci.id, "database": ci.database, "host": ci.host]
        }
    }

    public func mcpTableSizes(inDatabase database: String, connection connID: String) -> [String: Any] {
        if database.isEmpty { return ["error": "database argument is required"] }
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        return mcpDBSync {
            let sql = "SELECT TABLE_NAME AS name, TABLE_ROWS AS row_estimate, DATA_LENGTH AS data_bytes, INDEX_LENGTH AS index_bytes "
                + "FROM information_schema.TABLES WHERE TABLE_SCHEMA = \(mcpEscapeQuoted(database, conn)) "
                + "ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC"
            let res = conn.queryString(sql)
            if conn.queryErrored() { return ["error": conn.lastErrorMessage() ?? "Query error"] }
            var tables: [[String: Any]] = []
            while let row = res?.getRowAsDictionary() as? [String: Any] {
                var entry: [String: Any] = [:]
                for (k, v) in row where !(v is NSNull) { entry[k] = mcpDecode(v) }
                tables.append(entry)
            }
            return ["tables": tables, "connection": ci.id]
        }
    }

    public func mcpProcessList(onConnection connID: String) -> [String: Any] {
        guard let ci = mcpResolveConnection(connID) else { return mcpNoConnectionError() }
        let conn = ci.conn
        return mcpDBSync {
            let res = conn.queryString("SHOW FULL PROCESSLIST")
            if conn.queryErrored() || res == nil { return ["error": conn.lastErrorMessage() ?? "Query error"] }
            var procs: [[String: Any]] = []
            while let row = res?.getRowAsDictionary() as? [String: Any] {
                var entry: [String: Any] = [:]
                for (k, v) in row { entry[k] = (v is NSNull) ? NSNull() : mcpDecode(v) }
                procs.append(entry)
            }
            return ["processes": procs, "connection": ci.id]
        }
    }

    // MARK: - CSV helpers

    private func csvString(fromColumns columns: [String], rows: [[String: Any]]) -> String {
        var csv = ""
        csv += columns.map { csvEscape($0) }.joined(separator: ",") + "\n"
        for row in rows {
            var vals: [String] = []
            for col in columns {
                let val = row[col]
                let strVal: String
                if val == nil || val is NSNull {
                    strVal = ""
                } else if let s = val as? String {
                    strVal = s
                } else {
                    strVal = "\(val!)"
                }
                vals.append(csvEscape(strVal))
            }
            csv += vals.joined(separator: ",") + "\n"
        }
        return csv
    }

    private func csvEscape(_ value: String) -> String {
        var v = value
        // Guard against CSV/formula injection: spreadsheet apps treat a cell that
        // starts with = + - @ (or a leading tab/CR) as a formula. Prefix such cells
        // with a single quote so they are read as literal text. The export data can
        // be attacker-influenced (prompt injection), so neutralise it here.
        if let first = v.first, "=+-@\t\r".contains(first) {
            v = "'" + v
        }
        if v.contains(",") || v.contains("\"") || v.contains("\n") || v.contains("\r") {
            let escaped = v.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return v
    }
}
