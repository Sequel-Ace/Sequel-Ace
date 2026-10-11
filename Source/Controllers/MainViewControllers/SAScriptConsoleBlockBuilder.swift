//
//  SAScriptConsoleBlockBuilder.swift
//  Sequel Ace
//
//  Turns Run All console events into statement blocks: the SQL (coloured,
//  at most 6 lines), its rows, and a quiet status line; failed blocks are
//  reported so the console can tint them. Shared with the Unit Tests target.
//

import AppKit

enum SAClaudeSQLTokenKind { case keyword, string, backtick, number, comment }

enum SAClaudeSQLColouring {
    static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "IS", "NULL", "AS", "ON", "JOIN", "LEFT", "RIGHT", "INNER",
        "OUTER", "CROSS", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "INSERT",
        "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "ALTER", "DROP", "TABLE", "VIEW", "INDEX", "DATABASE",
        "SCHEMA", "IF", "EXISTS", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "DEFAULT", "CONSTRAINT", "UNIQUE", "USE",
        "SHOW", "DESCRIBE", "EXPLAIN", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "CASE", "WHEN", "THEN", "ELSE",
        "END", "LIKE", "BETWEEN", "ASC", "DESC", "WITH", "REPLACE", "TRUNCATE", "RENAME", "ADD", "COLUMN", "MODIFY",
        "CHANGE", "GRANT", "REVOKE", "CALL", "PROCEDURE", "FUNCTION", "TRIGGER", "RETURNS", "DECLARE", "TRUE", "FALSE",
    ]

    static func tokens(in sql: String) -> [(range: NSRange, kind: SAClaudeSQLTokenKind)] {
        let s = sql as NSString
        let n = s.length
        var result: [(NSRange, SAClaudeSQLTokenKind)] = []
        var i = 0
        func ch(_ k: Int) -> unichar { k < n ? s.character(at: k) : 0 }
        func isWord(_ c: unichar) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 }
        while i < n {
            let c = ch(i)
            if (c == 45 && ch(i + 1) == 45) || c == 35 {                         // -- or # comment
                var j = i
                while j < n && ch(j) != 10 { j += 1 }
                result.append((NSRange(location: i, length: j - i), .comment)); i = j
            } else if c == 47 && ch(i + 1) == 42 {                               // /* comment */
                var j = i + 2
                while j < n && !(ch(j) == 42 && ch(j + 1) == 47) { j += 1 }
                j = min(n, j + 2)
                result.append((NSRange(location: i, length: j - i), .comment)); i = j
            } else if c == 39 || c == 34 || c == 96 {                           // ' " `
                var j = i + 1
                while j < n {
                    if ch(j) == 92 && c != 96 { j += 2; continue }               // backslash escape
                    if ch(j) == c { if ch(j + 1) == c { j += 2; continue }; j += 1; break }
                    j += 1
                }
                j = min(n, j)
                result.append((NSRange(location: i, length: j - i), c == 96 ? .backtick : .string)); i = j
            } else if c >= 48 && c <= 57 && !isWord(ch(i - 1 < 0 ? n : i - 1)) {
                var j = i
                while j < n && (isWord(ch(j)) || ch(j) == 46) { j += 1 }
                result.append((NSRange(location: i, length: j - i), .number)); i = j
            } else if isWord(c) {
                var j = i
                while j < n && isWord(ch(j)) { j += 1 }
                let word = s.substring(with: NSRange(location: i, length: j - i)).uppercased()
                if keywords.contains(word) { result.append((NSRange(location: i, length: j - i), .keyword)) }
                i = j
            } else {
                i += 1
            }
        }
        return result
    }
}

struct SAScriptConsoleStyle {
    var font: NSFont
    var statusFont: NSFont
    var text, keyword, string, backtick, number, comment, muted, errorText: NSColor

    static func from(defaults: UserDefaults, font: NSFont) -> SAScriptConsoleStyle {
        func colour(_ key: String, _ fallback: NSColor) -> NSColor { SAArchiving.color(from: defaults.data(forKey: key)) ?? fallback }
        let text = colour(SAEditorThemeLoader.textColourKey, .textColor)
        let background = colour(SAEditorThemeLoader.backgroundColourKey, .textBackgroundColor)
        let clay = NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)
        return SAScriptConsoleStyle(font: font, statusFont: .systemFont(ofSize: 11),
                                    text: text,
                                    keyword: colour(SAEditorThemeLoader.keywordColourKey, text),
                                    string: colour(SAEditorThemeLoader.quoteColourKey, text),
                                    backtick: colour(SAEditorThemeLoader.backtickColourKey, text),
                                    number: colour(SAEditorThemeLoader.numericColourKey, text),
                                    comment: colour(SAEditorThemeLoader.commentColourKey, text),
                                    muted: SAClaudeEditorChrome.derivedColour(text: text, background: background, ratio: 0.36),
                                    errorText: SAClaudeEditorChrome.derivedColour(text: text, background: clay, ratio: 0.35))
    }
}

extension NSAttributedString.Key {
    /// Bool: the first character of a statement block (the console draws a separator above it).
    static let saConsoleBlockStart = NSAttributedString.Key("SAConsoleBlockStart")
    /// Bool: text of a failed statement's block (the console tints it and draws the clay edge).
    static let saConsoleBlockError = NSAttributedString.Key("SAConsoleBlockError")
}

final class SAScriptConsoleBlockBuilder {

    static let maxSQLLines = 6

    private let style: SAScriptConsoleStyle
    /// Length (UTF-16 units) of everything built so far, to compute absolute ranges.
    private(set) var length = 0
    private var blockStart = 0
    private var rows: UInt64?
    private var affected: UInt64?
    private var failed = false
    private var cancelled = false
    /// Every block ends with exactly one status line; set once it has been written.
    private var statusWritten = false

    init(style: SAScriptConsoleStyle) { self.style = style }

    func append(_ events: [SAScriptConsoleEvent]) -> (text: NSAttributedString, errorRanges: [NSRange]) {
        let out = NSMutableAttributedString()
        var errorRanges: [NSRange] = []
        let base = length
        func add(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
            out.append(NSAttributedString(string: string, attributes: attributes))
        }
        let plain: [NSAttributedString.Key: Any] = [.font: style.font, .foregroundColor: style.text]
        let status: [NSAttributedString.Key: Any] = [.font: style.statusFont, .foregroundColor: style.muted]

        for event in events {
            switch event {
            case .statementStarted(let sql):
                blockStart = base + out.length
                rows = nil; affected = nil; failed = false; cancelled = false; statusWritten = false
                let lines = sql.components(separatedBy: "\n")
                let shown = lines.prefix(Self.maxSQLLines).joined(separator: "\n")
                let sqlText = NSMutableAttributedString(string: shown + "\n", attributes: plain)
                for token in SAClaudeSQLColouring.tokens(in: shown) {
                    let colour: NSColor
                    switch token.kind {
                    case .keyword: colour = style.keyword
                    case .string: colour = style.string
                    case .backtick: colour = style.backtick
                    case .number: colour = style.number
                    case .comment: colour = style.comment
                    }
                    sqlText.addAttribute(.foregroundColor, value: colour, range: token.range)
                }
                sqlText.addAttribute(.saConsoleBlockStart, value: true, range: NSRange(location: 0, length: 1))
                out.append(sqlText)
                if lines.count > Self.maxSQLLines {
                    let more = String(format: NSLocalizedString("… %ld more lines", comment: "Run All console: a long statement is cut after 6 lines; this many lines are not shown"), lines.count - Self.maxSQLLines)
                    add(more + "\n", [.font: style.statusFont, .foregroundColor: style.muted])
                }
            case .resultHeader(let line), .row(let line):
                add(line, plain)
            case .rowsInSet(let count):
                rows = count
            case .queryOK(let count):
                affected = count
            case .failed(let message):
                failed = true
                add(message + "\n", [.font: style.font, .foregroundColor: style.errorText])
            case .cancelled:
                // Stop can arrive with no statementFinished (before the statement ran), so end the block now.
                // A failed block keeps its "failed" status line, which statementFinished writes. A statement
                // that completed as Stop raced it keeps its rows/affected count ("1 row affected · cancelled").
                cancelled = true
                if !failed && !statusWritten {
                    add(Self.statusText(rows: rows, affected: affected, failed: false, cancelled: true, continuing: false, time: 0) + "\n", status)
                    statusWritten = true
                }
            case .statementFinished(let time, let continuing):
                if !statusWritten {
                    add(Self.statusText(rows: rows, affected: affected, failed: failed, cancelled: cancelled, continuing: continuing, time: time) + "\n", status)
                    statusWritten = true
                }
                if failed {
                    let end = base + out.length
                    errorRanges.append(NSRange(location: blockStart, length: end - blockStart))
                }
            }
        }
        length += out.length
        if !errorRanges.isEmpty {
            // Ranges inside this chunk get the attribute here; earlier text is marked by the console.
            for range in errorRanges {
                let local = NSIntersectionRange(range, NSRange(location: base, length: out.length))
                if local.length > 0 { out.addAttribute(.saConsoleBlockError, value: true, range: NSRange(location: local.location - base, length: local.length)) }
            }
        }
        return (out, errorRanges)
    }

    static func statusText(rows: UInt64?, affected: UInt64?, failed: Bool, cancelled: Bool, continuing: Bool, time: Double) -> String {
        if failed {
            return continuing ? NSLocalizedString("failed · continued", comment: "Run All console: a statement failed and the script went on")
                              : NSLocalizedString("failed · stopped", comment: "Run All console: a statement failed and the script stopped")
        }
        if cancelled {
            let word = NSLocalizedString("cancelled", comment: "Run All console: the statement was stopped by the user")
            // Stop raced a statement that still completed (e.g. an UPDATE committed): keep what it did.
            guard rows != nil || affected != nil else { return word }
            return "\(whatText(rows: rows, affected: affected)) · \(word)"
        }
        return "\(whatText(rows: rows, affected: affected)) · \(timeText(time))"
    }

    private static func whatText(rows: UInt64?, affected: UInt64?) -> String {
        if let rows {
            return rows == 0 ? NSLocalizedString("Empty set", comment: "Run All console: a query returned no rows")
                : rows == 1 ? NSLocalizedString("1 row", comment: "Run All console: a query returned one row")
                : String(format: NSLocalizedString("%llu rows", comment: "Run All console: a query returned this many rows"), rows)
        }
        let count = affected ?? 0
        return count == 1 ? NSLocalizedString("1 row affected", comment: "Run All console: a statement changed one row")
            : String(format: NSLocalizedString("%llu rows affected", comment: "Run All console: a statement changed this many rows"), count)
    }

    static func timeText(_ seconds: Double) -> String {
        seconds < 1 ? String(format: "%.1f ms", seconds * 1000) : String(format: "%.2f s", seconds)
    }
}
