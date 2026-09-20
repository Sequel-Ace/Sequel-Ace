//
//  SASQLStatementBuilder.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.09.20.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Assembles the SQL text behind the result table's "Copy as SQL …" commands.
///
/// The caller reads the cells and turns each one into a finished SQL literal — quoting and
/// escaping need the connection's character set, so they stay in `SPCopyTable`. This type only
/// decides the shape of the statements around those literals, which keeps the part worth testing
/// free of a live server.
///
/// A literal is passed in exactly as it will appear in the statement: `42`, `'O''Hara'`,
/// `X'0a1b'`, `b'1010'`. The one value given meaning here is `NULL`, because MySQL matches it with
/// `IS NULL` rather than `=` and a `WHERE` clause built the naive way would silently match no rows.
@objcMembers public final class SASQLStatementBuilder: NSObject {

    /// Stands in for the table name when the rows did not come from one, as with a join in the
    /// custom query editor. The result is not runnable as it is, which is the point: it is a
    /// template for the user to finish.
    public static let placeholderTableName = "<table>"

    /// Roughly how much of a `VALUES` list to accumulate before starting a new `INSERT`.
    ///
    /// Servers reject a statement longer than `max_allowed_packet`, which defaults to 64 MB but is
    /// often far smaller, and editors are happier with several medium statements than one huge
    /// one. The limit is checked after appending a row, so a single oversized row still gets a
    /// statement of its own rather than being split.
    private static let insertBatchThreshold = 250_000

    // MARK: - INSERT

    /// Builds `INSERT` statements covering every row.
    ///
    /// - Parameters:
    ///   - table: Table to insert into, or `nil` to use `placeholderTableName`.
    ///   - columns: Column names, in the order the literals of each row appear.
    ///   - rows: One array of SQL literals per row, each the same length as `columns`.
    /// - Returns: The statements, or `nil` if there is nothing to insert or a row is the wrong
    ///   width.
    @objc(insertStatementsForTable:columns:rows:)
    public class func insertStatements(table: String?, columns: [String], rows: [[String]]) -> String? {
        guard !columns.isEmpty, !rows.isEmpty else { return nil }
        guard rows.allSatisfy({ $0.count == columns.count }) else { return nil }

        let header = "INSERT INTO \(quotedTableName(table)) (\(joinBacktickQuoted(columns)))\nVALUES\n"

        var result = header
        var batch = ""

        for (index, row) in rows.enumerated() {
            batch += "\t(" + row.joined(separator: ", ")

            let isLastRow = index == rows.count - 1
            if !isLastRow, batch.utf16.count > insertBatchThreshold {
                // Close this statement off and start the next one, so that the row just appended
                // ends the batch rather than opening the next.
                result += batch + ");\n\n" + header
                batch = ""
            } else {
                batch += "),\n"
                if isLastRow {
                    result += batch
                }
            }
        }

        return result.droppingTrailingRowSeparator() + ";\n"
    }

    // MARK: - UPDATE

    /// Builds one `UPDATE` statement per row, each identified by the row's key columns.
    ///
    /// Key columns are left out of `SET`: they are what the statement matches on, and assigning
    /// them their own value again is noise at best and a different row's identity at worst.
    ///
    /// - Parameters:
    ///   - table: Table to update, or `nil` to use `placeholderTableName`.
    ///   - columns: Column names, in the order the literals of each row appear.
    ///   - keyColumnIndexes: Indexes into `columns` of the columns identifying a row, usually its
    ///     primary key.
    ///   - rows: One array of SQL literals per row, each the same length as `columns`.
    /// - Returns: The statements, or `nil` if the rows cannot be identified, if every column is a
    ///   key column and so nothing is left to set, or if a row is the wrong width.
    @objc(updateStatementsForTable:columns:keyColumnIndexes:rows:)
    public class func updateStatements(table: String?, columns: [String], keyColumnIndexes: IndexSet, rows: [[String]]) -> String? {
        guard !columns.isEmpty, !rows.isEmpty else { return nil }
        guard rows.allSatisfy({ $0.count == columns.count }) else { return nil }

        let keyIndexes = keyColumnIndexes.filter { columns.indices.contains($0) }
        let settableIndexes = columns.indices.filter { !keyColumnIndexes.contains($0) }
        guard !keyIndexes.isEmpty, !settableIndexes.isEmpty else { return nil }

        let quotedTable = quotedTableName(table)

        return rows.map { row -> String in
            let assignments = settableIndexes
                .map { "\(backtickQuoted(columns[$0])) = \(row[$0])" }
                .joined(separator: ", ")
            let conditions = keyIndexes
                .map { comparison(column: columns[$0], literal: row[$0]) }
                .joined(separator: " AND ")

            return "UPDATE \(quotedTable) SET \(assignments)\nWHERE \(conditions);\n"
        }.joined()
    }

    // MARK: - Helpers

    /// Compares a column against a literal, using `IS NULL` where `= NULL` would match nothing.
    private class func comparison(column: String, literal: String) -> String {
        literal == "NULL"
            ? "\(backtickQuoted(column)) IS NULL"
            : "\(backtickQuoted(column)) = \(literal)"
    }

    private class func quotedTableName(_ table: String?) -> String {
        guard let table, !table.isEmpty else { return backtickQuoted(placeholderTableName) }
        return backtickQuoted(table)
    }

    private class func joinBacktickQuoted(_ names: [String]) -> String {
        names.map { backtickQuoted($0) }.joined(separator: ", ")
    }

    /// Quotes an identifier the way MySQL wants it.
    ///
    /// Keep in sync with `-[NSString backtickQuotedString]` in `SPStringAdditions.m`; the test
    /// target has no bridging header, so the category is out of reach here.
    private class func backtickQuoted(_ identifier: String) -> String {
        "`" + identifier.replacingOccurrences(of: "`", with: "``") + "`"
    }
}

private extension String {

    /// Drops the `,\n` that every appended row leaves behind.
    func droppingTrailingRowSeparator() -> String {
        hasSuffix(",\n") ? String(dropLast(2)) : self
    }
}
