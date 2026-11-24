//
//  SAConnectionUpdateOriginLookup.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Answers `SAUpdateOriginLookup` on a live connection.
///
/// App target only: the test target has no bridging header, so SPMySQL is out of its reach, and
/// `SAUpdateCopyOriginResolver` is tested against canned rows instead.
@objc final class SAConnectionUpdateOriginLookup: NSObject, SAUpdateOriginLookup {

    private let connection: SPMySQLConnection

    @objc init(connection: SPMySQLConnection) {
        self.connection = connection
        super.init()
    }

    func rows(forQuery query: String, database: String) -> [[Any]]? {
        let result = connection.queryString(query, assertingDatabaseContext: database)
        if connection.queryErrored() { return nil }

        var rows: [[Any]] = []
        while let row = result?.getRowAsArray() as? [Any] {
            rows.append(row)
        }
        return rows
    }

    func quotedString(_ value: String) -> String? {
        connection.escapeAndQuoteString(value)
    }
}
