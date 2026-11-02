//
//  SAScriptOutputFormatter.swift
//  Sequel Ace
//
//  Formats "Run All as Script" output the way the mysql command-line client
//  prints it in batch mode with -vv (`mysql -vv < file.sql`). Pure Swift so
//  the exact bytes can be unit-tested; SPMySQL values are converted to
//  SAScriptCell by SAScriptRunner before they reach this type.
//

import Foundation

/// One cell of a script result row.
enum SAScriptCell: Equatable {
    case null
    case text(String)
    /// Binary and geometry columns; printed as hex rather than raw bytes so
    /// the console never receives invalid text.
    case binary(Data)
}

enum SAScriptOutputFormatter {

    static let separator = "--------------"

    static let cancelled = "Query cancelled.\n"

    /// Echo of the statement, as `mysql -v` prints it before running it.
    static func statementHeader(_ statement: String) -> String {
        "\(separator)\n\(statement)\n\(separator)\n\n"
    }

    /// Text to echo for `statement`: the mysql client strips comments before
    /// echoing, so do the same (the SQL sent to the server is unchanged). A
    /// statement that is nothing but comments is echoed as written.
    static func echoText(for statement: String) -> String {
        let stripped = SPCustomQuerySQLClassifier.stripSQLComments(statement)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? statement : stripped
    }

    /// Column-name line printed before the first row of a non-empty result.
    static func resultHeader(columns: [String]) -> String {
        columns.map(escape).joined(separator: "\t") + "\n"
    }

    static func row(_ cells: [SAScriptCell]) -> String {
        cells.map(render).joined(separator: "\t") + "\n"
    }

    /// mysql prints `Empty set` (and no column header) for a result with no rows.
    static func rowsInSetFooter(count: UInt64) -> String {
        count == 0 ? "Empty set\n\n" : "\(rowCount(count)) in set\n\n"
    }

    static func queryOK(affectedRows: UInt64) -> String {
        "Query OK, \(rowCount(affectedRows)) affected\n\n"
    }

    static func error(code: Int, sqlState: String, line: Int, message: String) -> String {
        "ERROR \(code) (\(sqlState)) at line \(line): \(message)\n\n"
    }

    static func render(_ cell: SAScriptCell) -> String {
        switch cell {
        case .null:
            return "NULL"
        case .text(let value):
            return escape(value)
        case .binary(let data):
            guard !data.isEmpty else { return "" }
            return "0x" + data.map { String(format: "%02X", $0) }.joined()
        }
    }

    /// mysql batch-mode escaping: backslash, TAB, LF and NUL become `\\`,
    /// `\t`, `\n` and `\0` so every row stays on one tab-separated line.
    static func escape(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0 == "\\" || $0 == "\t" || $0 == "\n" || $0 == "\u{0}" }) else {
            return value
        }
        var escaped = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped.append(contentsOf: "\\\\".unicodeScalars)
            case "\t": escaped.append(contentsOf: "\\t".unicodeScalars)
            case "\n": escaped.append(contentsOf: "\\n".unicodeScalars)
            case "\u{0}": escaped.append(contentsOf: "\\0".unicodeScalars)
            default: escaped.append(scalar)
            }
        }
        return String(escaped)
    }

    private static func rowCount(_ count: UInt64) -> String {
        count == 1 ? "1 row" : "\(count) rows"
    }
}
