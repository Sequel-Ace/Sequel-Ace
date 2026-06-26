//
//  SPMCPHTTP.swift
//  Sequel Ace
//
//  HTTP request parsing and the loopback Origin allow-list used by the MCP
//  server. Kept free of app dependencies so it can be unit-tested in isolation.
//

import Foundation

enum SPMCPHTTP {

    /// `true` if `origin` points at a loopback host.
    static func isLoopbackOrigin(_ origin: String) -> Bool {
        guard var host = URLComponents(string: origin)?.host else { return false }
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        host = host.lowercased()   // hostnames are case-insensitive
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}

/// Decides whether a statement is safe to run while the MCP server is in
/// read-only mode. This is a security boundary, not a UI hint, so it is
/// deliberately conservative: anything it is unsure about is rejected.
enum SPMCPReadOnlyGuard {

    /// `true` only when `sql` is a single, non-destructive read statement.
    static func isReadOnly(_ sql: String) -> Bool {
        // Reject MySQL executable comments (/*! ... */ and /*!12345 ... */): their
        // contents are run by the server, so a normal comment strip would hide a
        // write or a statement separator from the checks below.
        if sql.contains("/*!") { return false }

        // Strip comments first so they cannot hide a statement separator or verb.
        // Use a quote-aware stripper: a quote-unaware one treats a `#` or `--` inside
        // a string literal as a comment and drops the rest of the line, which would
        // hide a trailing OUTFILE / `;` / LOAD_FILE from the checks below while the
        // raw SQL still runs (e.g. `SELECT '#' INTO OUTFILE '/tmp/x'`).
        let stripped = stripCommentsQuoteAware(sql)

        var core = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        while core.hasSuffix(";") {
            core = String(core.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if core.isEmpty { return false }

        // Reject stacked statements (e.g. `SELECT 1; DROP TABLE x`). A leftover
        // semicolon means a second statement, so refuse rather than guess.
        if core.contains(";") { return false }

        // Reject server-side file access: writes (`SELECT ... INTO OUTFILE/DUMPFILE`)
        // and reads (`SELECT LOAD_FILE('/etc/passwd')`), which are syntactically
        // SELECTs but touch the server filesystem.
        let upper = core.uppercased()
        if upper.contains("OUTFILE") || upper.contains("DUMPFILE") || upper.contains("LOAD_FILE") { return false }

        // Leading keyword must be a known read. isQuerySafeWithoutDestructiveWarning
        // also rejects `EXPLAIN ANALYZE <write>`, which MySQL would execute.
        return SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(core)
    }

    /// `true` if running `EXPLAIN <sql>` would execute the statement rather than just
    /// plan it. EXPLAIN ANALYZE runs its target, and the ANALYZE/FORMAT modifiers may
    /// appear in any order (e.g. `FORMAT=TREE ANALYZE UPDATE ...`), so scan the whole
    /// modifier region - not just the prefix - for ANALYZE. An executable /*! */
    /// comment is also treated as unsafe.
    static func explainWouldExecute(_ sql: String) -> Bool {
        if sql.contains("/*!") { return true }
        let stripped = stripCommentsQuoteAware(sql)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // The statement body starts at one of these keywords; ANALYZE/FORMAT before
        // it are EXPLAIN modifiers.
        let statementStarters: Set<String> = ["SELECT", "WITH", "INSERT", "UPDATE", "DELETE",
                                              "REPLACE", "VALUES", "TABLE", "CALL", "DO", "HANDLER"]
        for raw in stripped.uppercased().split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }) {
            let head = String(raw.split(separator: "=").first ?? raw)   // "FORMAT=TREE" -> "FORMAT"
            if statementStarters.contains(head) { return false }
            if head == "ANALYZE" { return true }
        }
        return false
    }

    /// Strips SQL comments (`-- ` and `#` to end of line, and `/* ... */`) while
    /// respecting string literals ('...', "...") and backtick identifiers, so a
    /// comment marker inside a quoted string is left intact. A quote-unaware strip
    /// would treat such a marker as a real comment and drop everything after it,
    /// which a request could exploit to hide OUTFILE/LOAD_FILE/`;` from the
    /// read-only checks. (`/*! ... */` executable comments are rejected before this.)
    static func stripCommentsQuoteAware(_ sql: String) -> String {
        var out = ""
        let chars: [Character] = Array(sql)
        let n = chars.count
        var i = 0
        var quote: Character?
        while i < n {
            let c = chars[i]
            if let q = quote {
                out.append(c)
                if c == "\\" && q != "`" {                       // backslash escape in '...'/"..."
                    if i + 1 < n { out.append(chars[i + 1]); i += 2; continue }
                } else if c == q {
                    if i + 1 < n && chars[i + 1] == q {          // doubled-quote escape ('' "" ``)
                        out.append(q); i += 2; continue
                    }
                    quote = nil
                }
                i += 1
                continue
            }
            if c == "'" || c == "\"" || c == "`" { quote = c; out.append(c); i += 1; continue }
            if c == "#" {                                        // # comment to end of line
                while i < n && chars[i] != "\n" { i += 1 }
                continue
            }
            // -- comment: the second dash must be followed by whitespace/control or EOL
            if c == "-" && i + 1 < n && chars[i + 1] == "-" {
                let next = i + 2 < n ? chars[i + 2] : " "
                if i + 2 >= n || next == " " || next == "\t" || next == "\n" || next == "\r" {
                    while i < n && chars[i] != "\n" { i += 1 }
                    continue
                }
            }
            if c == "/" && i + 1 < n && chars[i + 1] == "*" {    // /* ... */ block comment
                i += 2
                while i + 1 < n && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(i + 2, n)
                continue
            }
            out.append(c)
            i += 1
        }
        return out
    }
}

/// JSON serialisation for tool output. JSONSerialization throws an uncatchable
/// Objective-C exception on non-JSON values (NSData, NSDate, etc.) that MySQL can
/// return, so values are sanitised before serialising.
enum SPMCPJSON {

    /// Serialises `value` to a pretty-printed JSON string, or nil if it cannot be
    /// represented even after sanitising.
    static func string(from value: Any?) -> String? {
        guard let value else { return nil }
        let safe = sanitize(value)
        guard JSONSerialization.isValidJSONObject(safe),
              let data = try? JSONSerialization.data(withJSONObject: safe, options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Recursively converts a value into JSON-safe types: dictionaries/arrays are
    /// walked, Data is decoded as UTF-8 (else base64), Date is ISO-8601, and any
    /// other non-JSON value falls back to its string description.
    static func sanitize(_ value: Any) -> Any {
        switch value {
        case is NSNull, is String:
            return value
        case let dict as [String: Any]:
            var out = [String: Any](minimumCapacity: dict.count)
            for (k, v) in dict { out[k] = sanitize(v) }
            return out
        case let arr as [Any]:
            return arr.map { sanitize($0) }
        case let data as Data:
            return String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let num as NSNumber:
            return num
        default:
            return String(describing: value)
        }
    }
}

struct HTTPRequest {
    let method:  String
    let path:    String
    let headers: [String: String]
    let body:    Data?

    /// Returns a parsed request if `data` contains a complete HTTP/1.1 request,
    /// or `nil` if more data is needed.
    init?(data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil   // Incomplete headers.
        }

        let headerData = data[data.startIndex..<headerEnd.lowerBound]
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        method = parts[0]

        // Split path and query string.
        let fullPath = parts[1]
        path = fullPath.components(separatedBy: "?").first ?? fullPath

        var hdrs = [String: String]()
        for line in lines.dropFirst() {
            // Split on the first colon; the space after it is optional in HTTP.
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { hdrs[name] = value }
        }
        headers = hdrs

        // Parse query string from the full path.
        if fullPath.contains("?") {
            let qs = fullPath.components(separatedBy: "?").dropFirst().joined(separator: "?")
            queryString = qs
        } else {
            queryString = nil
        }

        let bodyStart = data.index(headerEnd.upperBound, offsetBy: 0)
        let expectedLength = Int(hdrs["content-length"] ?? "0") ?? 0
        let remaining = data.distance(from: bodyStart, to: data.endIndex)

        if expectedLength > 0 {
            if remaining < expectedLength { return nil }   // Body not fully arrived.
            body = Data(data[bodyStart..<data.index(bodyStart, offsetBy: expectedLength)])
        } else {
            body = nil
        }
    }

    private let queryString: String?

    /// Returns the decoded value of a query-string parameter, or nil.
    func queryParam(_ key: String) -> String? {
        guard let qs = queryString else { return nil }
        for pair in qs.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2, kv[0] == key {
                return kv[1].removingPercentEncoding
            }
        }
        return nil
    }
}
