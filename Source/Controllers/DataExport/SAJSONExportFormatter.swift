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
/// - Strings in numeric columns → unquoted number, but only if the text is a canonical JSON
///   number; anything else keeps its exact spelling as a JSON string. The digits are never
///   rewritten in either direction: padding is neither added nor stripped.
/// - `ZEROFILL` columns → always JSON strings. Their values are display text padded to the
///   column's width, so the column keeps one type whether or not a value happens to fill its
///   width — `123` in an `INT(3) ZEROFILL` column is exported as `"123"`, next to a padded
///   `007`. The padding the server sent is preserved exactly as is.
/// - Strings in text columns, and strings whose column types are unknown → JSON string. A value's
///   database type is never guessed from its text: a VARCHAR `1e3` must not become a JSON number.
/// - Everything else → JSON string.
///
/// Inherits NSObject only to expose `columnDefinitionsInExportOrder(_:identifierIndexes:)` to the
/// app's ObjC sources; otherwise kept free of project ObjC types so the Unit Tests target can
/// compile it.
final class SAJSONExportFormatter: NSObject {

    private let columnKeys: [String]
    private let numericColumns: [Bool]?
    private let tableKey: String?
    private let prettyPrint: Bool

    /// - Parameters:
    ///   - columnNames: The result's column names, used as object keys. Repeated names (a query
    ///     selecting `a.id, b.id`) get a `_2`, `_3`, ... suffix so no key is overwritten.
    ///   - numericColumns: Per column, whether it holds numbers (see `numericColumnFlags(_:)`).
    ///     Pass `nil` when the column types are unknown; strings are then written as strings —
    ///     a cell's database type is never guessed from its text.
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

    // MARK: - Column metadata

    /// Whether a column whose field definition carries this `typegrouping` holds a number.
    /// BIT is excluded: its values are bit strings such as "0101".
    static func isNumericTypeGrouping(_ grouping: String?) -> Bool {
        grouping == "integer" || grouping == "float"
    }

    /// Per-column numeric flags from a result's field definitions — a streaming result's
    /// `fieldDefinitions()`, a custom-query result store's, or the table metadata's `columns`,
    /// all of which carry `typegrouping`. A `ZEROFILL` column is never numeric: its values are
    /// display text and keep the same JSON type whether or not a value fills its width.
    /// Missing or empty definitions yield all `false`, so strings keep their string type.
    static func numericColumnFlags(_ definitions: [[String: Any]]) -> [Bool] {
        definitions.map {
            SAJSONExportFormatter.isNumericTypeGrouping($0["typegrouping"] as? String)
                && !SAJSONExportFormatter.isZeroFillColumn($0)
        }
    }

    /// Whether a field definition marks its column ZEROFILL. Result field definitions carry
    /// `ZEROFILL_FLAG` (parsed from the server's field flags); the table metadata's columns
    /// carry `zerofill` (parsed from the column definition text).
    static func isZeroFillColumn(_ definition: [String: Any]) -> Bool {
        let flag = definition["ZEROFILL_FLAG"] ?? definition["zerofill"]
        return (flag as? NSNumber)?.boolValue == true
    }

    /// Reorders a result's column definitions into export order.
    ///
    /// Query and filtered exports build each row in their table view's column order: every
    /// table column's identifier is the storage index of its cells — and of its definition —
    /// so dragging a column reorders headers and cells together. The definitions must follow
    /// that same identifier order or each column's type flag lands on its neighbour's cells
    /// (a VARCHAR `1e3` dragged before an INT `7` would export the text as a number and the
    /// number as a string). Columns are addressed by index only — never matched by name — so
    /// duplicate column aliases cannot be crossed.
    ///
    /// An identifier addressing no definition yields an empty entry, which flags the column
    /// as text. `nil` or empty definitions return `nil` so the caller keeps the
    /// string-preserving default.
    @objc static func columnDefinitionsInExportOrder(_ definitions: [[String: Any]]?, identifierIndexes: [Int]) -> [[String: Any]]? {
        guard let definitions, !definitions.isEmpty, !identifierIndexes.isEmpty else { return nil }
        return identifierIndexes.map { definitions.indices.contains($0) ? definitions[$0] : [:] }
    }

    // MARK: - Values

    private func value(_ cell: Any, column: Int) -> String {
        switch cell {
        case is NSNull:
            return "null"
        case let data as Data:
            return SAJSONExportFormatter.quoted(data.base64EncodedString())
        case let string as String:
            let columnIsNumeric = numericColumns.map { column < $0.count && $0[column] } ?? false
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
