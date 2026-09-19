//
//  SASearchAllTables.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.09.19.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

// Pure building blocks for "Search in All Tables" (issue #152): which columns
// are searched, the SQL that is sent, how result rows are read back, and the
// content filter shown when a result is opened. Nothing here touches a
// connection, so it is shared with the Unit Tests target.

/// How the search text is compared with column values.
enum SASearchAllTablesMatchMode: Int, CaseIterable {
    /// The value contains the search text (`LIKE '%text%'`).
    case contains
    /// The whole value equals the search text (`LIKE 'text'`, no wildcards).
    case exact
}

/// Rule-filter family of a searched column, derived from
/// `information_schema.COLUMNS.DATA_TYPE`. Mirrors the `typegrouping` →
/// filter group mapping in `SPTableData` / `SACellFilterOperator`.
enum SASearchAllTablesColumnKind: Equatable {
    /// Character and text types, ENUM, SET and JSON — the "text columns".
    case text
    /// Other types the content filter treats as strings (BINARY, BLOB, UUID, INET…).
    case otherString
    /// Integer and fixed/floating point types.
    case numeric
    /// DATE, TIME, DATETIME, TIMESTAMP and YEAR.
    case temporal
}

/// One column that will be searched.
struct SASearchAllTablesColumn: Equatable {
    let name: String
    let kind: SASearchAllTablesColumnKind
}

/// One table (or view) with the columns that will be searched in it.
struct SASearchAllTablesTable: Equatable {
    let name: String
    let isView: Bool
    var columns: [SASearchAllTablesColumn]
}

/// What to search for and where.
struct SASearchAllTablesOptions: Equatable {
    var searchText: String
    var matchMode: SASearchAllTablesMatchMode = .contains
    /// Only search character/text columns (the default); otherwise also
    /// numeric, date/time, binary and other string-like columns.
    var textColumnsOnly = true
    /// Also search views. Off by default: a view can be expensive to scan and
    /// its rows usually also live in a base table.
    var includeViews = false
    /// Only search tables whose name contains this text (case-insensitive).
    var tableNameFilter = ""
}

/// Matches found in one table.
struct SASearchAllTablesMatch: Equatable {
    let table: String
    /// Rows matching in at least one column.
    let matchingRows: Int
    /// Matching rows per column, only for columns with at least one match,
    /// in column order.
    let columnMatches: [(column: String, rows: Int)]

    static func == (lhs: SASearchAllTablesMatch, rhs: SASearchAllTablesMatch) -> Bool {
        lhs.table == rhs.table
            && lhs.matchingRows == rhs.matchingRows
            && lhs.columnMatches.map(\.column) == rhs.columnMatches.map(\.column)
            && lhs.columnMatches.map(\.rows) == rhs.columnMatches.map(\.rows)
    }
}

enum SASearchAllTablesQueryBuilder {

    // MARK: - Column selection

    private static let textTypes: Set<String> = [
        "char", "varchar", "tinytext", "text", "mediumtext", "longtext", "enum", "set", "json",
    ]
    private static let numericTypes: Set<String> = [
        "tinyint", "smallint", "mediumint", "int", "integer", "bigint",
        "decimal", "numeric", "float", "double", "real",
    ]
    private static let temporalTypes: Set<String> = ["date", "time", "datetime", "timestamp", "year"]
    /// Never searched: a LIKE on a spatial value compares its internal binary
    /// form, and on a BIT value its raw bytes rather than the digits shown.
    private static let unsearchableTypes: Set<String> = [
        "bit", "geometry", "point", "linestring", "polygon", "multipoint", "multilinestring",
        "multipolygon", "geometrycollection", "geomcollection",
    ]

    /// Kind of a column, or `nil` when the column is not searched with the given scope.
    ///
    /// - Parameters:
    ///   - dataType: `information_schema.COLUMNS.DATA_TYPE`, in any case.
    ///   - textColumnsOnly: Restrict the search to text columns.
    static func columnKind(forDataType dataType: String, textColumnsOnly: Bool) -> SASearchAllTablesColumnKind? {
        let type = dataType.lowercased()
        if textTypes.contains(type) { return .text }
        if textColumnsOnly || unsearchableTypes.contains(type) { return nil }
        if numericTypes.contains(type) { return .numeric }
        if temporalTypes.contains(type) { return .temporal }
        return .otherString
    }

    /// Lists every column of every table and view in `quotedDatabase`, in
    /// table and column order. Result columns: table, column, data type, table type.
    ///
    /// - Parameter quotedDatabase: The database name as a quoted SQL string literal.
    static func columnsQuery(quotedDatabase: String) -> String {
        "SELECT c.TABLE_NAME, c.COLUMN_NAME, c.DATA_TYPE, t.TABLE_TYPE"
            + " FROM information_schema.COLUMNS c"
            + " JOIN information_schema.TABLES t ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME"
            + " WHERE c.TABLE_SCHEMA = \(quotedDatabase)"
            + " ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION"
    }

    /// Groups the rows of `columnsQuery` into the tables to search, dropping
    /// columns outside the scope and tables left without searchable columns.
    ///
    /// - Parameters:
    ///   - rows: `(table, column, dataType, tableType)` rows in query order.
    ///   - options: The search options (scope, views, table-name filter).
    static func tables(fromColumnRows rows: [(table: String, column: String, dataType: String, tableType: String)],
                       options: SASearchAllTablesOptions) -> [SASearchAllTablesTable] {
        let nameFilter = options.tableNameFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        var tables: [SASearchAllTablesTable] = []
        for row in rows {
            let tableType = row.tableType.uppercased()
            // MariaDB reports system-versioned tables separately; sequences and
            // temporary/system views are never searched.
            let isView = tableType == "VIEW"
            guard tableType == "BASE TABLE" || tableType == "SYSTEM VERSIONED" || (isView && options.includeViews) else { continue }
            if !nameFilter.isEmpty && row.table.range(of: nameFilter, options: .caseInsensitive) == nil { continue }
            guard let kind = columnKind(forDataType: row.dataType, textColumnsOnly: options.textColumnsOnly) else { continue }

            let column = SASearchAllTablesColumn(name: row.column, kind: kind)
            if let last = tables.last, last.name == row.table {
                tables[tables.count - 1].columns.append(column)
            } else {
                tables.append(SASearchAllTablesTable(name: row.table, isView: isView, columns: [column]))
            }
        }
        return tables
    }

    // MARK: - SQL

    /// Doubles backticks so a name can go inside a backtick-quoted identifier.
    static func quoteIdentifier(_ name: String) -> String {
        "`" + name.replacingOccurrences(of: "`", with: "``") + "`"
    }

    /// Escapes the LIKE metacharacters `\`, `%` and `_` so they match literally
    /// (MySQL's default LIKE escape character is `\`).
    static func likeEscaped(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    /// The LIKE pattern for the search text, before SQL string quoting.
    static func likePattern(for text: String, mode: SASearchAllTablesMatchMode) -> String {
        switch mode {
        case .contains: return "%" + likeEscaped(text) + "%"
        case .exact: return likeEscaped(text)
        }
    }

    /// One query per table: the number of rows matching in any column plus the
    /// number of matching rows per column, reading the table only once.
    ///
    ///     SELECT COUNT(*), SUM(`a` LIKE p), SUM(`b` LIKE p)
    ///     FROM `db`.`t` WHERE `a` LIKE p OR `b` LIKE p
    ///
    /// LIKE is used for every column type: MySQL compares non-string values by
    /// their string form, so `5` never equals `'abc'` the way `5 = 'abc'`
    /// would coerce the text to a number.
    ///
    /// - Parameters:
    ///   - database: Database name, unquoted.
    ///   - table: Table with at least one column.
    ///   - quotedPattern: The LIKE pattern as a quoted SQL string literal
    ///     (quoted by the connection, so it follows its escaping rules).
    static func countQuery(database: String, table: SASearchAllTablesTable, quotedPattern: String) -> String {
        let conditions = table.columns.map { "\(quoteIdentifier($0.name)) LIKE \(quotedPattern)" }
        let sums = conditions.map { "SUM(\($0))" }
        return "SELECT COUNT(*), " + sums.joined(separator: ", ")
            + " FROM \(quoteIdentifier(database)).\(quoteIdentifier(table.name))"
            + " WHERE " + conditions.joined(separator: " OR ")
    }

    /// Reads the single row returned by `countQuery`.
    ///
    /// - Returns: The match, or `nil` when no row matched.
    static func match(fromCountRow row: [Any?], table: SASearchAllTablesTable) -> SASearchAllTablesMatch? {
        let matchingRows = row.first.flatMap(integer(from:)) ?? 0
        guard matchingRows > 0 else { return nil }
        var columnMatches: [(column: String, rows: Int)] = []
        for (index, column) in table.columns.enumerated() {
            let valueIndex = index + 1
            // SUM() is NULL when the column is NULL in every matching row.
            let rows = valueIndex < row.count ? (row[valueIndex].flatMap(integer(from:)) ?? 0) : 0
            if rows > 0 { columnMatches.append((column.name, rows)) }
        }
        return SASearchAllTablesMatch(table: table.name, matchingRows: matchingRows, columnMatches: columnMatches)
    }

    /// Converts a result value (string, number or bytes, as returned by the
    /// MySQL client) to an integer.
    static func integer(from value: Any) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string) ?? Double(string).map { Int($0) }
        case let data as Data: return String(data: data, encoding: .utf8).flatMap { integer(from: $0) }
        default: return nil
        }
    }

    /// Converts a result value to a string (information_schema values can come
    /// back as bytes depending on the server's charset).
    static func string(from value: Any?) -> String? {
        switch value {
        case let string as String: return string
        case let data as Data: return String(data: data, encoding: .utf8)
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}

// MARK: - Content filter for an opened result

/// Builds the content (rule) filter applied when a result is opened, in the
/// serialized form `SPRuleFilterController -restoreSerializedFilters:` reads.
///
/// Serialized keys and operator names are inlined as private literals – keep
/// in sync with `SPRuleFilterController.m` and `ContentFilters.plist`.
enum SASearchAllTablesFilterBuilder {
    private static let filterClassKey = "filterClass"
    private static let expressionClass = "expressionNode"
    private static let columnKey = "column"
    private static let comparisonKey = "filterComparison"
    private static let valuesKey = "filterValues"
    private static let enabledKey = "enabled"

    /// One filter row (column, operator, value) for a matched column, or `nil`
    /// when the content filter has no operator that reproduces the search.
    ///
    /// The rule filter escapes its argument itself (`SPTableFilterParser`):
    /// inside its `contains` clause a lone backslash already matches literally
    /// while `\%` and `\_` are kept as LIKE escapes, so only `%` and `_` are
    /// escaped here; its `LIKE` clause passes the argument through as the
    /// pattern, so the text is escaped exactly as in the search query.
    ///
    /// The parser leaves a backslash before `n`, `r` or `t` alone so it reads
    /// as a newline, carriage return or tab; a search for a literal `\t` (a
    /// Windows path, say) cannot be expressed and gets no filter.
    static func filterRow(column: SASearchAllTablesColumn, text: String,
                          mode: SASearchAllTablesMatchMode) -> [String: Any]? {
        if text.range(of: #"\\[nrt]"#, options: .regularExpression) != nil { return nil }
        let comparison: String
        let value: String
        switch (column.kind, mode) {
        case (.text, .contains), (.otherString, .contains):
            comparison = "contains"
            value = text.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        case (.text, .exact), (.otherString, .exact), (.numeric, .exact):
            comparison = "LIKE"
            value = SASearchAllTablesQueryBuilder.likePattern(for: text, mode: .exact)
        case (.numeric, .contains):
            comparison = "LIKE"
            value = SASearchAllTablesQueryBuilder.likePattern(for: text, mode: .contains)
        case (.temporal, .exact):
            comparison = "="
            value = text
        case (.temporal, .contains):
            // Date filters offer no LIKE/contains operator.
            return nil
        }
        return [
            filterClassKey: expressionClass,
            columnKey: column.name,
            comparisonKey: comparison,
            valuesKey: [value],
            enabledKey: true,
        ]
    }

    /// The filter for a result: the matched columns combined with OR, or `nil`
    /// when any of them cannot be expressed (the table then opens unfiltered
    /// rather than showing a subset of the matching rows).
    static func serializedFilter(for match: SASearchAllTablesMatch, table: SASearchAllTablesTable,
                                 text: String, mode: SASearchAllTablesMatchMode) -> [String: Any]? {
        var rows: [[String: Any]] = []
        for columnMatch in match.columnMatches {
            guard let column = table.columns.first(where: { $0.name == columnMatch.column }),
                  let row = filterRow(column: column, text: text, mode: mode) else { return nil }
            rows.append(row)
        }
        guard !rows.isEmpty else { return nil }
        // A lone row under the default AND stays a plain expression; several
        // rows get the OR root the rule editor shows in its AND/OR popup.
        return SARuleFilterRootConjunction.serializedRoot(items: rows, isConjunction: rows.count == 1)
    }
}
