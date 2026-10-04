//
//  SPMCPHTTP.swift
//  Sequel Ace
//
//  HTTP request parsing and the loopback Origin allow-list used by the MCP
//  server. Kept free of app dependencies so it can be unit-tested in isolation.
//

import Foundation
import SPMySQL

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

    /// The endpoint a request maps to, independent of the connection (pure and testable).
    enum Route: Equatable {
        case streamableHTTP   // POST /mcp
        case sse              // GET /sse
        case message          // POST /message
        case health           // GET /health
        case methodNotAllowed // a known path reached with the wrong method, e.g. GET /mcp
        case notFound
    }

    /// Maps an HTTP method and path to a route.
    static func route(method: String, path: String) -> Route {
        switch (method, path) {
        case ("POST", "/mcp"):
            return .streamableHTTP
        case (_, "/mcp"):
            return .methodNotAllowed
        case ("GET", "/sse"):
            return .sse
        case ("POST", "/message"):
            return .message
        case ("GET", "/health"):
            return .health
        default:
            return .notFound
        }
    }
}

/// Decides whether a statement is safe to run while the MCP server is in
/// read-only mode. This is a security boundary, not a UI hint, so it is
/// deliberately conservative: anything it is unsure about is rejected.
enum SPMCPReadOnlyGuard {

    /// `true` only when `sql` is a single, non-destructive read statement.
    static func isReadOnly(_ sql: String) -> Bool {
        // Reject executable comments: their contents run on the server, so a normal
        // comment strip would hide a write or statement separator from the checks below.
        if hasExecutableComment(sql) { return false }

        // The guard does not know the connection's sql_mode. Under
        // NO_BACKSLASH_ESCAPES the quote after a backslash closes a string, which
        // moves the string boundaries and with them where a comment starts; a `#`
        // read as a comment here could then be literal text on the server, and
        // the `; DROP …` behind it would be stripped instead of rejected. Read
        // the statement both ways and allow it only when both readings pass.
        let backslashReadings = sql.contains("\\") ? [true, false] : [true]
        return backslashReadings.allSatisfy { isReadOnly(sql, backslashEscapes: $0) }
    }

    private static func isReadOnly(_ sql: String, backslashEscapes: Bool) -> Bool {
        // Strip comments first so they cannot hide a statement separator or verb.
        // Use a quote-aware stripper: a quote-unaware one treats a `#` or `--` inside
        // a string literal as a comment and drops the rest of the line, which would
        // hide a trailing OUTFILE / `;` / LOAD_FILE from the checks below while the
        // raw SQL still runs (e.g. `SELECT '#' INTO OUTFILE '/tmp/x'`).
        let stripped = stripCommentsQuoteAware(sql, backslashEscapes: backslashEscapes)

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
        // also rejects `EXPLAIN ANALYZE <write>`, which MySQL would execute. The
        // text was stripped under one reading of backslashes, so it is judged
        // under that same reading; mixing the two would reject valid reads.
        return SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(core, backslashEscapes: backslashEscapes)
    }

    /// `true` if running `EXPLAIN <sql>` would execute the statement rather than just
    /// plan it. EXPLAIN ANALYZE runs its target, and the ANALYZE/FORMAT modifiers may
    /// appear in any order (e.g. `FORMAT=TREE ANALYZE UPDATE ...`). ANALYZE is a
    /// reserved word in MySQL and MariaDB, so outside quotes it can only be that
    /// modifier: any unquoted ANALYZE word counts. An executable /*! */ comment is also
    /// treated as unsafe.
    static func explainWouldExecute(_ sql: String) -> Bool {
        if hasExecutableComment(sql) { return true }
        // As in isReadOnly, the statement is read with and without backslash
        // escapes; it counts as executing when either reading says so.
        let backslashReadings = sql.contains("\\") ? [true, false] : [true]
        return backslashReadings.contains { explainWouldExecute(sql, backslashEscapes: $0) }
    }

    /// Whether the statement holds an unquoted ANALYZE word under one reading of
    /// backslashes.
    ///
    /// The tokens come from the SQL classifier's tokenizer, which works on Unicode
    /// scalars and keeps every quoted operand - `'...'`, `"..."`, `` `...` ``,
    /// `@'...'` - in one token, so a quoted ANALYZE never counts. Every token is
    /// looked at, rather than stopping at the statement's first keyword: text the
    /// comment stripper leaves in but the server reads as a comment can then only
    /// cause a rejection, never hide the modifier. Words are split once more at
    /// characters that cannot be part of an unquoted identifier, so ANALYZE glued to
    /// punctuation is found too.
    ///
    /// - Parameters:
    ///   - sql: The statement after EXPLAIN.
    ///   - backslashEscapes: Whether a backslash escapes the next character in
    ///     quoted strings.
    /// - Returns: Whether EXPLAIN would execute the statement.
    private static func explainWouldExecute(_ sql: String, backslashEscapes: Bool) -> Bool {
        let stripped = stripCommentsQuoteAware(sql, backslashEscapes: backslashEscapes)
        let analyze = Array("ANALYZE".unicodeScalars)
        let tokens = SPCustomQuerySQLClassifier.sqlTokens(from: stripped.uppercased(), backslashEscapes: backslashEscapes)
        return tokens.contains { token in
            // Quoted operands and user variables are never the modifier.
            guard let first = token.unicodeScalars.first, !"'\"`@".unicodeScalars.contains(first) else {
                return false
            }
            return token.unicodeScalars
                .split(whereSeparator: { !isUnquotedIdentifierScalar($0) })
                .contains { Array($0) == analyze }
        }
    }

    /// Whether `scalar` continues a possibly qualified unquoted name: an ASCII
    /// letter or digit, `_`, `$`, any character beyond ASCII, or the `.` between
    /// qualifiers. The dot keeps `t.ANALYZE` whole: after a dot MySQL reads even a
    /// reserved word as an identifier.
    ///
    /// - Parameter scalar: The character to check.
    /// - Returns: Whether it continues the name.
    private static func isUnquotedIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x80 || scalar == "_" || scalar == "$" || scalar == "."
            || ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
    }

    /// `true` if `sql` contains an executable comment whose body the server runs:
    /// MySQL `/*! ... */` (and `/*!12345 ... */`) and MariaDB `/*M! ... */`. A normal
    /// comment strip would discard the body, hiding a write or file clause from the
    /// read-only checks, so these are rejected outright before stripping.
    static func hasExecutableComment(_ sql: String) -> Bool {
        let lower = sql.lowercased()
        return lower.contains("/*!") || lower.contains("/*m!")
    }

    /// Strips SQL comments (`-- ` and `#` to end of line, and `/* ... */`) while
    /// respecting string literals ('...', "...") and backtick identifiers, so a
    /// comment marker inside a quoted string is left intact. A quote-unaware strip
    /// would treat such a marker as a real comment and drop everything after it,
    /// which a request could exploit to hide OUTFILE/LOAD_FILE/`;` from the
    /// read-only checks. (`/*! ... */` executable comments are rejected before this.)
    ///
    /// Works on Unicode scalars, not Characters: a combining mark right after a
    /// quote would otherwise merge with it into one Character and hide the delimiter.
    ///
    /// - Parameter backslashEscapes: Whether a backslash escapes the next character
    ///   inside '...'/"..."; `false` reads the SQL the way a connection with
    ///   `NO_BACKSLASH_ESCAPES` does, where the quote after a backslash closes the string.
    static func stripCommentsQuoteAware(_ sql: String, backslashEscapes: Bool = true) -> String {
        var out = ""
        let chars = Array(sql.unicodeScalars)
        let n = chars.count
        var i = 0
        var quote: Unicode.Scalar?
        while i < n {
            let c = chars[i]
            if let q = quote {
                out.unicodeScalars.append(c)
                if c == "\\" && backslashEscapes && q != "`" {   // backslash escape in '...'/"..."
                    if i + 1 < n { out.unicodeScalars.append(chars[i + 1]); i += 2; continue }
                } else if c == q {
                    if i + 1 < n && chars[i + 1] == q {          // doubled-quote escape ('' "" ``)
                        out.unicodeScalars.append(q); i += 2; continue
                    }
                    quote = nil
                }
                i += 1
                continue
            }
            if c == "'" || c == "\"" || c == "`" { quote = c; out.unicodeScalars.append(c); i += 1; continue }
            // Replace each comment with a single space: MySQL treats a comment as
            // whitespace, so dropping it outright would merge adjacent tokens (e.g.
            // `FROM/**/t` -> `FROMt`), which matters because the stripped SQL is also
            // what run_query executes for capped reads.
            if c == "#" {                                        // # comment to end of line
                while i < n && !SASQLCommentSyntax.endsLineComment(chars[i]) { i += 1 }
                out.append(" ")
                continue
            }
            // -- comment: the second dash must be followed by whitespace, a control
            // character or the end, as MySQL's lexer requires (my_isspace or
            // my_iscntrl: 0x00-0x20 and 0x7F). Accepting fewer - a vertical tab or form
            // feed, say - would leave text in that the server skips as a comment.
            if c == "-" && i + 1 < n && chars[i + 1] == "-" {
                let next = i + 2 < n ? chars[i + 2] : " "
                if i + 2 >= n || SASQLCommentSyntax.isCommentWhitespace(next) {
                    while i < n && !SASQLCommentSyntax.endsLineComment(chars[i]) { i += 1 }
                    out.append(" ")
                    continue
                }
            }
            if c == "/" && i + 1 < n && chars[i + 1] == "*" {    // /* ... */ block comment
                i += 2
                while i + 1 < n && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(i + 2, n)
                out.append(" ")
                continue
            }
            out.unicodeScalars.append(c)
            i += 1
        }
        return out
    }

    /// A comment-stripped query that can be rewritten without knowing the
    /// connection's NO_BACKSLASH_ESCAPES mode. Otherwise keep the original SQL
    /// and enforce the result cap while reading it, as for executable comments.
    /// Validation accepting both readings does not mean their SQL text is the
    /// same: a comment marker can be inside a string under only one reading.
    static func sqlForResultLimiting(_ sql: String) -> String? {
        guard !hasExecutableComment(sql) else { return nil }
        let stripped = stripCommentsQuoteAware(sql)
        let withoutEscapes = stripCommentsQuoteAware(sql, backslashEscapes: false)
        guard stripped.utf8.elementsEqual(withoutEscapes.utf8) else { return nil }
        return stripped
    }

    /// Substitutes each unquoted `?` in `sql` with the literal that `literal`
    /// renders for the next element of `params`. Quote- and comment-aware: a `?`
    /// inside a string literal or a comment is not a placeholder and is copied
    /// verbatim, so a `?` parked in a comment cannot turn param data into
    /// executable SQL (it just fails the placeholder/param count check).
    ///
    /// The scan walks Unicode scalars, as `stripCommentsQuoteAware` does, so a
    /// combining mark right after a quote cannot hide the delimiter. Whether a
    /// backslash escapes the next character depends on the connection's
    /// `NO_BACKSLASH_ESCAPES`, which the binder does not know, so the
    /// placeholders are found under both readings; a query in which the two
    /// disagree is refused instead of being bound in a way the server may read
    /// differently.
    /// Returns `(nil, message)` when the placeholder and param counts differ or
    /// the placeholders depend on the backslash reading.
    static func bindPlaceholders(in sql: String, params: [Any], literal: (Any) -> String) -> (String?, String?) {
        let scalars = Array(sql.unicodeScalars)
        let placeholders = placeholderOffsets(in: scalars, backslashEscapes: true)
        guard placeholders == placeholderOffsets(in: scalars, backslashEscapes: false) else {
            return (nil, "The ? placeholders depend on whether a backslash escapes a quote (NO_BACKSLASH_ESCAPES); write the string literals without backslash escapes")
        }
        if placeholders.count > params.count { return (nil, "More ? placeholders than params provided") }
        if placeholders.count < params.count { return (nil, "More params than ? placeholders provided") }
        var out = String.UnicodeScalarView()
        var copied = 0
        for (offset, param) in zip(placeholders, params) {
            out.append(contentsOf: scalars[copied..<offset])
            out.append(contentsOf: literal(param).unicodeScalars)
            copied = offset + 1
        }
        out.append(contentsOf: scalars[copied...])
        return (String(out), nil)
    }

    /// The positions of the `?` placeholders in a query: outside string
    /// literals, quoted identifiers and comments.
    ///
    /// - Parameters:
    ///   - scalars: The query's Unicode scalars.
    ///   - backslashEscapes: Whether a backslash escapes the next character in
    ///     a `'…'` or `"…"` literal, as it does unless NO_BACKSLASH_ESCAPES is set.
    /// - Returns: The scalar offsets of the placeholders, in order.
    private static func placeholderOffsets(in scalars: [Unicode.Scalar], backslashEscapes: Bool) -> [Int] {
        var offsets: [Int] = []
        var quote: Unicode.Scalar?
        let n = scalars.count
        var i = 0
        while i < n {
            let c = scalars[i]
            if let q = quote {
                if c == "\\" && backslashEscapes && q != "`" {    // backslash escape in a string literal
                    i += 2
                    continue
                }
                if c == q {
                    if i + 1 < n && scalars[i + 1] == q {          // doubled-quote escape
                        i += 2
                        continue
                    }
                    quote = nil
                }
                i += 1
                continue
            }
            // A `?` inside a comment is not a placeholder.
            if c == "#" {                                         // # to end of line
                while i < n && !SASQLCommentSyntax.endsLineComment(scalars[i]) { i += 1 }
                continue
            }
            if c == "-" && i + 1 < n && scalars[i + 1] == "-"
                && (i + 2 >= n || SASQLCommentSyntax.isCommentWhitespace(scalars[i + 2])) {   // -- (needs whitespace/EOL after)
                while i < n && !SASQLCommentSyntax.endsLineComment(scalars[i]) { i += 1 }
                continue
            }
            if c == "/" && i + 1 < n && scalars[i + 1] == "*" {   // /* ... */ block comment
                i += 2
                while i < n && !(scalars[i] == "*" && i + 1 < n && scalars[i + 1] == "/") { i += 1 }
                i += 2
                continue
            }
            if c == "'" || c == "\"" || c == "`" {
                quote = c
            } else if c == "?" {
                offsets.append(i)
            }
            i += 1
        }
        return offsets
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

/// Formats the fields of the CSV files `export_results` writes.
enum SAMCPCSV {
    /// Escapes one CSV field.
    ///
    /// A spreadsheet reads a cell that starts with `=`, `+`, `-`, `@`, a tab or a
    /// carriage return as a formula, and the exported data can be
    /// attacker-influenced (prompt injection), so such a cell gets a leading single
    /// quote and is read as text. A plain number is left as it is: `-5` or
    /// `+1.5E3` cannot be a formula, and quoting it would turn every negative
    /// number in the export into text.
    ///
    /// - Parameter value: The field's text.
    /// - Returns: The field as it goes into the file, enclosed in double quotes
    ///   when it holds a comma, a double quote or a line break.
    static func escapedField(_ value: String) -> String {
        var field = value
        // Unicode scalars, not Characters: Swift folds "\r\n" into one Character,
        // which would hide a leading carriage return.
        if let first = field.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first), !isPlainNumber(field) {
            field = "'" + field
        }
        if field.containsAnyUnicodeScalar(of: ",\"\n\r") {
            // .literal: without it a quote followed by a combining mark is not
            // found, stays single and ends the field early.
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"", options: .literal) + "\""
        }
        return field
    }

    /// Whether `value` is a plain decimal number in ASCII digits - an optional
    /// sign, digits with an optional fraction, an optional exponent - as MySQL
    /// returns numeric columns.
    ///
    /// - Parameter value: The field's text.
    /// - Returns: Whether the whole value is such a number.
    private static func isPlainNumber(_ value: String) -> Bool {
        value.range(of: #"\A[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?\z"#, options: .regularExpression) != nil
    }
}


/// Pagination for a result that must be consumed without rewriting its SQL.
/// SQL-paginated callers pass zero offset so it is never applied twice.
enum SAMCPResultPage {
    static func rowLimit(requested: Int, cap: Int) -> Int {
        requested > 0 ? min(requested, cap) : cap
    }

    private static let trailingLimitPattern = #"(?i)\blimit\s+([0-9]+)(?:\s*,\s*([0-9]+)|\s+offset\s+([0-9]+))?\s*$"#

    static func hasTrailingLimit(_ sql: String) -> Bool {
        sql.range(of: trailingLimitPattern, options: .regularExpression) != nil
    }

    /// Apply tool pagination inside an existing SQL result window, fetching
    /// only the output page and one lookahead. Nil leaves oversized integers
    /// to MySQL rather than overflowing or silently changing their meaning.
    static func sqlPageWithinTrailingLimit(_ sql: String, requested: Int, offset: Int, cap: Int) -> (sql: String, maxRows: Int)? {
        guard let re = try? NSRegularExpression(pattern: trailingLimitPattern) else { return nil }
        let text = sql as NSString
        guard let match = re.firstMatch(in: sql, range: NSRange(location: 0, length: text.length)) else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : text.substring(with: range)
        }
        let commaCount = group(2)
        guard let count = Int(commaCount ?? group(1) ?? "0"),
              let sqlOffset = Int(commaCount == nil ? (group(3) ?? "0") : (group(1) ?? "0")) else { return nil }
        let toolOffset = max(0, offset)
        let combinedOffset = sqlOffset.addingReportingOverflow(toolOffset)
        guard !combinedOffset.overflow else { return nil }
        let remaining = max(0, count - toolOffset)
        let maxRows = min(remaining, rowLimit(requested: requested, cap: cap))
        let fetchRows = maxRows < remaining ? maxRows + 1 : maxRows
        let clause = "LIMIT \(fetchRows) OFFSET \(combinedOffset.partialValue)"
        return (text.replacingCharacters(in: match.range, with: clause), maxRows)
    }

    /// Returns whether one more row exists after the requested page. Skipped
    /// rows never enter the output, and only one lookahead row is consumed.
    static func consumeRows<Row>(maxRows: Int, offset: Int = 0,
                                 nextRow: () -> Row?, appendRow: (Row) -> Void) -> Bool {
        var toSkip = max(0, offset)
        var remaining = max(0, maxRows)
        while let row = nextRow() {
            if toSkip > 0 {
                toSkip -= 1
                continue
            }
            guard remaining > 0 else { return true }
            appendRow(row)
            remaining -= 1
        }
        return false
    }
}
