//
//  CollectionExtension.swift
//  sequel-ace
//
//  Created by Jakub Kaspar on 20.11.2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation

public extension Collection {

	/// Returns the element at the specified index if it is within bounds, otherwise nil.
	subscript (safe index: Index) -> Element? {
		return indices.contains(index) ? self[index] : nil
	}

	/// Returns second element from collection
	var second: Element? {
		return self.dropFirst().first
	}

	var isNotEmpty: Bool {
		return !isEmpty
	}
}

public extension Set {
	var isNotEmpty: Bool {
		return !isEmpty
	}
}

public extension RangeReplaceableCollection where Element: Equatable {
    mutating func appendIfNotContains(_ element: Element)  {
        if !contains(element) { append(element) }
    }
}

enum PinnedTableMigrationPlanner {
    static func migrationToken(legacyHostName: String, connectionIdentifier: String, databaseName: String) -> String? {
        let trimmedLegacyHostName = legacyHostName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConnectionIdentifier = connectionIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDatabaseName = databaseName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedConnectionIdentifier.isNotEmpty, trimmedDatabaseName.isNotEmpty else {
            return nil
        }

        guard trimmedLegacyHostName != trimmedConnectionIdentifier else {
            return nil
        }

        return "\(trimmedLegacyHostName)|\(trimmedConnectionIdentifier)|\(trimmedDatabaseName)"
    }

    static func tablesToMigrate(legacyPinnedTables: [String], existingPinnedTables: [String]) -> [String] {
        let existingPinnedTableSet = Set(existingPinnedTables.filter { $0.isNotEmpty })
        var seenPinnedTables = Set<String>()
        var tablesToMigrate: [String] = []

        for tableName in legacyPinnedTables where tableName.isNotEmpty {
            if existingPinnedTableSet.contains(tableName) || seenPinnedTables.contains(tableName) {
                continue
            }
            seenPinnedTables.insert(tableName)
            tablesToMigrate.append(tableName)
        }

        return tablesToMigrate
    }
}
