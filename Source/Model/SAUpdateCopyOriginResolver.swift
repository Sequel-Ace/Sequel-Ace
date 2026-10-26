//
//  SAUpdateCopyOriginResolver.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// The server lookups an UPDATE copy of a query result needs, answered on the connection the rows
/// came from. `SAConnectionUpdateOriginLookup` answers them in the app; tests answer with canned
/// rows.
@objc public protocol SAUpdateOriginLookup {

    /// The rows `query` returns when run against `database`, each an array of column values, or
    /// `nil` if the server could not answer.
    @objc(rowsForQuery:database:)
    func rows(forQuery query: String, database: String) -> [[Any]]?

    /// `value` as an escaped, quoted SQL string literal for this connection, or `nil` if it
    /// cannot be made one.
    @objc(quotedString:)
    func quotedString(_ value: String) -> String?
}

/// Establishes what an UPDATE copy of some rows may target, from the field metadata the rows came
/// with — asking the server whatever that metadata cannot say — and hands the decision to
/// `SASQLStatementBuilder.updateOrigin(forFields:tableKeyColumns:generatedColumns:)`.
@objcMembers public final class SAUpdateCopyOriginResolver: NSObject {

    /// The origin an UPDATE of these rows can safely target, or `nil` — and the UPDATE copy must
    /// be refused — whenever that cannot be established: see
    /// `SASQLStatementBuilder.updateOrigin(forFields:tableKeyColumns:generatedColumns:)`, and
    /// also whenever a server lookup it needs fails.
    ///
    /// Which metadata the rows carry decides where the origin table's complete key comes from. A
    /// query result may project only part of the table, and its metadata does not mark every key
    /// part, so the key has to be asked of the server. Table content metadata covers the whole
    /// table, so its column definitions give the key.
    ///
    /// The generated columns are asked of the server either way. A query result's metadata marks
    /// none of them, and table content metadata marks only those its definition parser
    /// recognizes: MariaDB before 10.2 writes `AS (…) VIRTUAL` and `AS (…) PERSISTENT`, with no
    /// `GENERATED ALWAYS`, so on those servers its generated columns reach `fieldDefinitions`
    /// unmarked.
    ///
    /// - Parameters:
    ///   - fieldDefinitions: The field metadata of the columns the statement includes, in
    ///     projection order.
    ///   - table: The table being shown, for table content metadata, which names no origin.
    ///   - database: The database being shown, likewise.
    ///   - tableColumnDefinitions: Every column definition of the table being shown, for table
    ///     content metadata, whose key parts may lie outside the projection.
    ///   - lookup: The server to ask; `nil` refuses the rows.
    @objc(originForFieldDefinitions:table:database:tableColumnDefinitions:lookup:)
    public class func origin(fieldDefinitions: [Any],
                             table: String?,
                             database: String?,
                             tableColumnDefinitions: [Any]?,
                             lookup: SAUpdateOriginLookup?) -> SAUpdateCopyOrigin? {

        let fields = SASQLStatementBuilder.fieldOrigins(fromFieldDefinitions: fieldDefinitions, table: table, database: database)
        guard let first = fields.first else { return nil }

        guard let lookup else { return nil }

        let tableKeyColumns: [String]?
        if let firstField = fieldDefinitions.first as? [String: Any], firstField["org_name"] != nil {
            tableKeyColumns = primaryKeyColumns(ofTable: first.table, database: first.database, lookup: lookup)
        } else {
            tableKeyColumns = primaryKeyColumnNames(ofColumnDefinitions: tableColumnDefinitions)
        }

        guard let tableKeyColumns, !tableKeyColumns.isEmpty else { return nil }
        guard let generatedColumns = self.generatedColumns(ofTable: first.table, database: first.database, lookup: lookup) else { return nil }

        return SASQLStatementBuilder.updateOrigin(forFields: fields, tableKeyColumns: tableKeyColumns, generatedColumns: generatedColumns)
    }

    /// Whether a column whose `information_schema.COLUMNS.EXTRA` reads `extra` is generated.
    ///
    /// MySQL reports `VIRTUAL GENERATED` or `STORED GENERATED`; MariaDB reports those too, and
    /// `VIRTUAL` or `PERSISTENT` before 10.2. MySQL 8.0.13 and later also report
    /// `DEFAULT_GENERATED` for a column whose default is an expression — `TIMESTAMP DEFAULT
    /// CURRENT_TIMESTAMP` among them — which is an ordinary, assignable column, so the test is
    /// made on whole words rather than on the text containing `GENERATED`.
    ///
    /// EXTRA is used because every supported server version has it. GENERATION_EXPRESSION would
    /// read better but does not exist before MySQL 5.7, and referring to it would turn the lookup
    /// into an error — and so every UPDATE copy into a refusal — on the older servers that cannot
    /// have generated columns in the first place.
    @objc(isGeneratedColumnExtra:)
    public class func isGeneratedColumn(extra: String) -> Bool {
        let words = extra.uppercased().split(separator: " ")
        return words.contains("GENERATED") || words.contains("VIRTUAL") || words.contains("PERSISTENT")
    }

    // MARK: - Private

    /// The names of every primary key column of the table whose metadata `columnDefinitions`
    /// holds, in the order the table defines them. Returns an empty array for a table with no
    /// key, and `nil` for a key column without a name.
    private class func primaryKeyColumnNames(ofColumnDefinitions columnDefinitions: [Any]?) -> [String]? {
        var keyColumns: [String] = []

        for case let field as [String: Any] in columnDefinitions ?? [] {
            let keyFlag = field["isprimarykey"]
            let isKey = (keyFlag as? NSNumber)?.boolValue ?? (keyFlag as? NSString)?.boolValue ?? false
            guard isKey else { continue }
            guard let name = field["name"] as? String, !name.isEmpty else { return nil }
            keyColumns.append(name)
        }

        return keyColumns
    }

    /// The names of the primary key columns of a table on the server, in the order the key
    /// defines them. Returns `nil` if the server cannot answer, which leaves any UPDATE copy that
    /// depends on it refused.
    private class func primaryKeyColumns(ofTable table: String, database: String, lookup: SAUpdateOriginLookup) -> [String]? {
        guard !table.isEmpty, !database.isEmpty,
              let quotedDatabase = lookup.quotedString(database),
              let quotedTable = lookup.quotedString(table) else { return nil }

        let query = "SELECT COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE "
            + "WHERE TABLE_SCHEMA = \(quotedDatabase) AND TABLE_NAME = \(quotedTable) AND CONSTRAINT_NAME = 'PRIMARY' "
            + "ORDER BY ORDINAL_POSITION"

        guard let rows = lookup.rows(forQuery: query, database: database) else { return nil }

        var keyColumns: [String] = []
        for row in rows {
            guard let name = row.first as? String, !name.isEmpty else { return nil }
            keyColumns.append(name)
        }
        return keyColumns
    }

    /// The names of the generated columns of a table on the server. Returns an empty array for a
    /// table that generates none, and `nil` if the server cannot answer, which leaves any UPDATE
    /// copy that depends on it refused: a statement assigning a generated column would only be
    /// rejected by the server anyway.
    private class func generatedColumns(ofTable table: String, database: String, lookup: SAUpdateOriginLookup) -> [String]? {
        guard !table.isEmpty, !database.isEmpty,
              let quotedDatabase = lookup.quotedString(database),
              let quotedTable = lookup.quotedString(table) else { return nil }

        let query = "SELECT COLUMN_NAME, EXTRA FROM information_schema.COLUMNS "
            + "WHERE TABLE_SCHEMA = \(quotedDatabase) AND TABLE_NAME = \(quotedTable)"

        guard let rows = lookup.rows(forQuery: query, database: database) else { return nil }

        var generatedColumns: [String] = []
        for row in rows {
            guard let name = row.first as? String, !name.isEmpty else { return nil }
            let extra = row.count > 1 ? (row[1] as? String ?? "") : ""
            if isGeneratedColumn(extra: extra) {
                generatedColumns.append(name)
            }
        }
        return generatedColumns
    }
}
