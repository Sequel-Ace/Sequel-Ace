//
//  SAJSONExportFormatter.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Builds the text of a JSON export: one array of row objects per table, keyed by column name.
///
/// A single table (or a query / filtered result) is written as a bare array:
///
///     [
///       {"id": 1, "name": "Ann"},
///       ...
///     ]
///
/// When several tables go into one file, each table's array becomes a member of a top-level
/// object keyed by the table name (`{"users": [...], "orders": [...]}`), so the file stays one
/// valid JSON document.
///
/// Cell mapping:
/// - `NSNull` → `null`
/// - `Data` (BLOB / BINARY / VARBINARY columns, see `textCell`) → base64 string. JSON strings must be valid
///   Unicode, so arbitrary bytes cannot be embedded as text without loss.
/// - Strings in numeric columns → unquoted number, but only if the text is a valid JSON number
///   (a `ZEROFILL` value such as `007` stays a string so nothing is lost).
/// - Everything else → JSON string.
///
/// Kept free of project ObjC types so the Unit Tests target can compile it.
final class SAJSONExportFormatter {

    private let columnKeys: [String]
    private let numericColumns: [Bool]?
    private let tableKey: String?
    private let prettyPrint: Bool

    /// - Parameters:
    ///   - columnNames: The result's column names, used as object keys. Repeated names (a query
    ///     selecting `a.id, b.id`) get a `_2`, `_3`, ... suffix so no key is overwritten.
    ///   - numericColumns: Per column, whether it holds numbers. Pass `nil` when the column types are
    ///     unknown (query and filtered results); any cell that reads as a JSON number is then written
    ///     unquoted, as the CSV exporter does for the same sources.
    ///   - tableKey: The table name to key this table's array by when several tables share a file,
    ///     or `nil` to write a bare array.
    ///   - prettyPrint: Indent the output; otherwise each row is written compactly on its own line.
    init(columnNames: [String], numericColumns: [Bool]?, tableKey: String?, prettyPrint: Bool) {
        self.columnKeys = SAJSONExportFormatter.uniqueKeys(columnNames).map(SAJSONExportFormatter.quoted)
        self.numericColumns = numericColumns
        self.tableKey = tableKey
        self.prettyPrint = prettyPrint
    }

    // MARK: - Document structure

    private var newline: String { prettyPrint ? "\n" : "" }

    private func indent(_ level: Int) -> String {
        prettyPrint ? String(repeating: "  ", count: level) : ""
    }

    /// The nesting level of the row objects: one deeper when the array is a member of the table object.
    private var rowLevel: Int { tableKey == nil ? 1 : 2 }

    /// Text that opens this table's array.
    /// - Parameter isFirstInFile: Whether this is the first table written to the file (only used when keyed).
    func opening(isFirstInFile: Bool) -> String {
        guard let tableKey else { return "[" }
        let separator = prettyPrint ? ": " : ":"
        return (isFirstInFile ? "{" : ",") + "\n" + indent(1) + SAJSONExportFormatter.quoted(tableKey) + separator + "["
    }

    /// Text that closes this table's array.
    /// - Parameters:
    ///   - rowCount: The number of rows written.
    ///   - isLastInFile: Whether this is the last table written to the file (only used when keyed).
    func closing(rowCount: Int, isLastInFile: Bool) -> String {
        let close = (rowCount > 0 ? "\n" + indent(rowLevel - 1) : "") + "]"
        guard tableKey != nil else { return close + "\n" }
        return close + (isLastInFile ? "\n}\n" : "")
    }

    /// One row as a JSON object, preceded by the separator from the previous row.
    /// - Parameters:
    ///   - cells: The row's values, in column order.
    ///   - index: The row's position in the array, starting at 0.
    func row(_ cells: [Any], index: Int) -> String {
        let fieldSeparator = prettyPrint ? ": " : ":"
        var text = (index == 0 ? "\n" : ",\n") + indent(rowLevel) + "{"

        for (column, key) in columnKeys.enumerated() {
            text += (column == 0 ? "" : ",") + newline + indent(rowLevel + 1) + key + fieldSeparator
            text += value(column < cells.count ? cells[column] : NSNull(), column: column)
        }

        return text + newline + indent(rowLevel) + "}"
    }

    /// `names` with each repeat of an earlier name suffixed `_2`, `_3`, ... until it is unused.
    static func uniqueKeys(_ names: [String]) -> [String] {
        var used = Set<String>()
        return names.map { name in
            var candidate = name
            var suffix = 1
            while used.contains(candidate) {
                suffix += 1
                candidate = "\(name)_\(suffix)"
            }
            used.insert(candidate)
            return candidate
        }
    }

    // MARK: - Values

    private func value(_ cell: Any, column: Int) -> String {
        switch cell {
        case is NSNull:
            return "null"
        case let data as Data:
            return SAJSONExportFormatter.quoted(data.base64EncodedString())
        case let string as String:
            let columnIsNumeric = numericColumns.map { column < $0.count && $0[column] } ?? true
            return columnIsNumeric && SAJSONExportFormatter.isJSONNumber(string) ? string : SAJSONExportFormatter.quoted(string)
        default:
            return SAJSONExportFormatter.quoted(String(describing: cell))
        }
    }

    /// Turns the bytes SPMySQL returns for a column with the BINARY flag back into text unless the
    /// column really holds bytes. The flag is also set on text columns with a binary collation
    /// (`utf8mb4_bin`, and MariaDB's JSON type); only the `binary` character set holds raw bytes.
    /// - Parameters:
    ///   - cell: A value from the result set.
    ///   - characterSetNumber: The column's character set id (`charsetnr`); 63 is `binary`.
    ///   - encoding: The connection encoding the text arrived in.
    /// - Returns: The text for non-binary columns, otherwise `cell` unchanged.
    static func textCell(_ cell: Any, characterSetNumber: Int, encoding: String.Encoding) -> Any {
        guard let data = cell as? Data, characterSetNumber != 63,
              let text = String(data: data, encoding: encoding) else { return cell }
        return text
    }

    /// Whether `string` is a number as the JSON grammar (RFC 8259 §6) defines it:
    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`
    static func isJSONNumber(_ string: String) -> Bool {
        let bytes = Array(string.utf8)
        var i = 0

        func isDigit(_ index: Int) -> Bool { index < bytes.count && bytes[index] >= 0x30 && bytes[index] <= 0x39 }
        func skipDigits() -> Bool {
            let start = i
            while isDigit(i) { i += 1 }
            return i > start
        }

        if i < bytes.count && bytes[i] == UInt8(ascii: "-") { i += 1 }

        // Integer part: a lone zero, or digits without a leading zero
        if i < bytes.count && bytes[i] == UInt8(ascii: "0") {
            i += 1
        } else if !skipDigits() {
            return false
        }

        if i < bytes.count && bytes[i] == UInt8(ascii: ".") {
            i += 1
            if !skipDigits() { return false }
        }

        if i < bytes.count && (bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E")) {
            i += 1
            if i < bytes.count && (bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-")) { i += 1 }
            if !skipDigits() { return false }
        }

        return i == bytes.count
    }

    /// `string` as a JSON string literal. Quotes, backslashes and control characters are escaped;
    /// everything else, including non-ASCII text, is written as is (the file is UTF-8).
    static func quoted(_ string: String) -> String {
        var result = "\""
        result.unicodeScalars.reserveCapacity(string.unicodeScalars.count + 2)

        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            case _ where scalar.value < 0x20:
                result += String(format: "\\u%04x", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }

        return result + "\""
    }
}
