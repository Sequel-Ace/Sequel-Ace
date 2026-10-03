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

/// Where one column of a result came from, as the server reports it.
///
/// `name` is the origin column — the one the server actually read — not the alias the SELECT may
/// have given it; `table` and `database` are where that column lives. Fields with no origin, such
/// as expressions, carry empty strings here, and the UPDATE eligibility checks refuse them.
@objcMembers public final class SAFieldOrigin: NSObject {

    /// The origin column name, or the empty string when the field reports none.
    public var name: String = ""

    /// The origin table name, or the empty string when the field reports none.
    public var table: String = ""

    /// The origin database name, or the empty string when the field reports none.
    public var database: String = ""

    /// Whether the server flagged the field as part of its table's key (`PRI_KEY_FLAG` in query
    /// results, `isprimarykey` in table metadata).
    public var primaryKeyFlagged: Bool = false
}

/// What an UPDATE copy should update, once the rows have been established safe to update.
@objcMembers public final class SAUpdateCopyOrigin: NSObject {

    /// The single origin table every projected column came from.
    public let table: String

    /// The origin name of every projected column, in projection order.
    public let columns: [String]

    /// The indexes, into `columns`, of the columns forming the origin table's complete key.
    public let keyColumnIndexes: IndexSet

    fileprivate init(table: String, columns: [String], keyColumnIndexes: IndexSet) {
        self.table = table
        self.columns = columns
        self.keyColumnIndexes = keyColumnIndexes
    }
}

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

    // MARK: - UPDATE origin eligibility

    /// Builds the origin facts an UPDATE copy needs from the field metadata the rows came with.
    ///
    /// Each field dictionary is used as-is: query results carry the server's `org_name`,
    /// `org_table`, `db` and `PRI_KEY_FLAG`; table metadata instead carries `name` and
    /// `isprimarykey`, with `table` and `database` standing in for the origin the metadata
    /// is about. A field that reports no origin at all — an expression such as
    /// `SELECT COUNT(*)` — extracts an empty name, which the eligibility checks refuse.
    ///
    /// The order of the returned origins matches the order of the field definitions given.
    @objc(fieldOriginsFromFieldDefinitions:table:database:)
    public class func fieldOrigins(fromFieldDefinitions fieldDefinitions: [Any]?, table: String?, database: String?) -> [SAFieldOrigin] {

        guard let fieldDefinitions else { return [] }

        return fieldDefinitions.map { rawField in

            let field = rawField as? [String: Any] ?? [:]

            // Query-result metadata wins where present: org_name is the column the server
            // actually read, where `name` would only be the alias the SELECT gave it.
            let orgName = field["org_name"] as? String
            let name = orgName ?? (field["name"] as? String) ?? ""
            let originTable = (field["org_table"] as? String) ?? table ?? ""
            let originDatabase = (field["db"] as? String) ?? database ?? ""

            let keyFlag = field["PRI_KEY_FLAG"] ?? field["isprimarykey"]
            let primaryKeyFlagged = (keyFlag as? NSNumber)?.boolValue
                ?? (keyFlag as? NSString)?.boolValue
                ?? false

            let origin = SAFieldOrigin()
            origin.name = name
            origin.table = originTable
            origin.database = originDatabase
            origin.primaryKeyFlagged = primaryKeyFlagged
            return origin
        }
    }

    /// Decides whether rows can be safely emitted as UPDATE statements, and if so what to
    /// update: the one origin table they came from, the origin (never aliased) name of each
    /// projected column, and the indexes of the columns to match rows on.
    ///
    /// "Safely" means the projection is tied to a single origin table and carries that
    /// table's **complete** primary key, as given by `tableKeyColumns` — the origin table's
    /// key column names from table metadata or `information_schema`, never a guess from the
    /// projection's own flags. A partially-projected composite key would match more rows
    /// than the one it was built from, an alias is not the name of any column to assign or
    /// match, and a projection spanning tables or carrying expressions cannot be tied to
    /// one row source at all. Any of those returns `nil`, and the UPDATE copy must not be
    /// offered then.
    ///
    /// - Returns: The origin, or `nil` if the rows cannot be updated safely.
    @objc(updateOriginForFields:tableKeyColumns:)
    public class func updateOrigin(forFields fields: [SAFieldOrigin], tableKeyColumns: [String]) -> SAUpdateCopyOrigin? {

        guard !fields.isEmpty, !tableKeyColumns.isEmpty else { return nil }

        // Every projected field must name a real column of one real table.
        guard fields.allSatisfy({ !$0.name.isEmpty && !$0.table.isEmpty && !$0.database.isEmpty }) else { return nil }

        // And they must all come from the same table of the same database — otherwise the
        // rows have no single origin to update.
        let originTable = fields[0].table
        let originDatabase = fields[0].database
        guard fields.allSatisfy({ $0.table == originTable && $0.database == originDatabase }) else { return nil }

        // A repeated origin column would produce `SET x = …, x = …`, which the server rejects.
        let names = fields.map(\.name)
        guard Set(names).count == names.count else { return nil }

        // The table's complete key must be present, each part on a field the server itself
        // flagged as key — a flagless field that merely shares the name means the two
        // metadata sources disagree, which is not something to copy statements over.
        var keyColumnIndexes = IndexSet()
        for keyColumn in tableKeyColumns {
            guard let index = names.firstIndex(of: keyColumn) else { return nil }
            guard fields[index].primaryKeyFlagged else { return nil }
            keyColumnIndexes.insert(index)
        }

        // With nothing outside the key, there is nothing to assign.
        guard keyColumnIndexes.count < fields.count else { return nil }

        return SAUpdateCopyOrigin(table: originTable, columns: names, keyColumnIndexes: keyColumnIndexes)
    }

    /// The cheaper question menu validation asks: could these fields plausibly support an
    /// UPDATE copy, judged only from the projection's own metadata?
    ///
    /// Menu items validate on every display and must not talk to the server, so this cannot
    /// require the origin table's complete key — establishing that in the query editor takes
    /// an `information_schema` lookup, which `-updateOriginForFields:tableKeyColumns:` does
    /// at copy time instead. An item that passes here can still be refused there; an item
    /// that fails here can never succeed.
    @objc(updateCopyPlausibleForFields:)
    public class func updateCopyPlausible(forFields fields: [SAFieldOrigin]) -> Bool {

        guard !fields.isEmpty else { return false }

        guard fields.allSatisfy({ !$0.name.isEmpty && !$0.table.isEmpty && !$0.database.isEmpty }) else { return false }

        let originTable = fields[0].table
        let originDatabase = fields[0].database
        guard fields.allSatisfy({ $0.table == originTable && $0.database == originDatabase }) else { return false }

        let names = fields.map(\.name)
        guard Set(names).count == names.count else { return false }

        let flaggedCount = fields.filter(\.primaryKeyFlagged).count
        return flaggedCount > 0 && flaggedCount < fields.count
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
