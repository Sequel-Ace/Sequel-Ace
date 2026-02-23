//
//  SPTableContentColumnFilterTests.swift
//  Unit Tests
//
//  Created for Sequel-Ace column filter feature.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import XCTest

/// Tests for the column filter functionality in SPTableContent.
/// Tests the comma-separated filter term parsing and column name matching logic.
final class SPTableContentColumnFilterTests: XCTestCase {

    // MARK: - Filter Term Parsing Tests

    /// Test parsing comma-separated terms with whitespace handling
    func testParseFilterTerms() {
        // Single term
        XCTAssertEqual(parseFilterTerms("id"), ["id"])

        // Multiple comma-separated terms
        XCTAssertEqual(parseFilterTerms("id, name, created"), ["id", "name", "created"])

        // Whitespace is trimmed
        XCTAssertEqual(parseFilterTerms("  id  ,  name  "), ["id", "name"])

        // Empty terms are ignored
        XCTAssertEqual(parseFilterTerms("id,,name,,,created"), ["id", "name", "created"])

        // Empty/whitespace-only returns empty array
        XCTAssertEqual(parseFilterTerms(""), [])
        XCTAssertEqual(parseFilterTerms("   "), [])
    }

    // MARK: - Column Matching Tests

    /// Test column name matching with single and multiple terms
    func testColumnMatching() {
        // Single term matching (substring, case-insensitive)
        XCTAssertTrue(columnMatches("user_id", terms: ["user"]))
        XCTAssertTrue(columnMatches("USER_ID", terms: ["user"]))
        XCTAssertFalse(columnMatches("created_at", terms: ["user"]))

        // Multiple terms use OR logic - matches if ANY term matches
        let terms = ["id", "name"]
        XCTAssertTrue(columnMatches("user_id", terms: terms))
        XCTAssertTrue(columnMatches("first_name", terms: terms))
        XCTAssertFalse(columnMatches("created_at", terms: terms))
    }

    // MARK: - Regression Guardrails

    /// Ensure the app defaults include the autofill heuristic workaround used for Tahoe lag regressions.
    func testAutoFillHeuristicControllerDisabledByDefault() {
        guard let defaults = preferenceDefaultsDictionary() else {
            XCTFail("Could not find PreferenceDefaults.plist in any loaded bundle")
            return
        }

        let value = defaults["NSAutoFillHeuristicControllerEnabled"] as? Bool
        XCTAssertEqual(value, false)
    }

    // MARK: - Helper Functions (mirrors SPTableContent logic)

    /// Parse comma-separated filter string into array of lowercase trimmed terms
    private func parseFilterTerms(_ filterString: String) -> [String] {
        let lowercased = filterString.lowercased().trimmingCharacters(in: .whitespaces)
        if lowercased.isEmpty {
            return []
        }

        let rawTerms = lowercased.components(separatedBy: ",")
        var trimmedTerms: [String] = []

        for term in rawTerms {
            let trimmed = term.trimmingCharacters(in: .whitespaces)
            if trimmed.isNotEmpty {
                trimmedTerms.append(trimmed)
            }
        }

        return trimmedTerms
    }

    /// Check if column name matches any of the filter terms
    private func columnMatches(_ columnName: String, terms: [String]) -> Bool {
        let lowercaseName = columnName.lowercased()
        for term in terms where lowercaseName.contains(term) {
            return true
        }
        return false
    }

    private func preferenceDefaultsDictionary() -> [String: Any]? {
        let candidateBundles = [Bundle.main, Bundle(for: Self.self)] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in candidateBundles {
            guard let path = bundle.path(forResource: "PreferenceDefaults", ofType: "plist") else {
                continue
            }

            if let defaults = NSDictionary(contentsOfFile: path) as? [String: Any] {
                return defaults
            }
        }

        return nil
    }
}

final class PinnedTableMigrationPlannerTests: XCTestCase {

    func testPinnedTableMigrationTokenGeneration() {
        let token = PinnedTableMigrationPlanner.migrationToken(legacyHostName: "", connectionIdentifier: "user@localhost:3306", databaseName: "db_name")
        XCTAssertEqual(token, "|user@localhost:3306|db_name")
    }

    func testPinnedTableMigrationTokenRejectsInvalidInputs() {
        XCTAssertNil(PinnedTableMigrationPlanner.migrationToken(legacyHostName: "legacy", connectionIdentifier: "", databaseName: "db_name"))
        XCTAssertNil(PinnedTableMigrationPlanner.migrationToken(legacyHostName: "legacy", connectionIdentifier: "user@localhost:3306", databaseName: ""))
        XCTAssertNil(PinnedTableMigrationPlanner.migrationToken(legacyHostName: "same_key", connectionIdentifier: "same_key", databaseName: "db_name"))
    }

    func testPinnedTableMigrationTableMerge() {
        let tablesToMigrate = PinnedTableMigrationPlanner.tablesToMigrate(
            legacyPinnedTables: ["users", "orders", "users", "", "products", "orders"],
            existingPinnedTables: ["orders", "existing"]
        )

        XCTAssertEqual(tablesToMigrate, ["users", "products"])
    }
}

final class SPOptimizedFieldTypeEstimatorTests: XCTestCase {

    func testNormalizedFieldType() {
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": " varchar(255) "] as NSDictionary),
            "VARCHAR"
        )
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": " mediumint unsigned "] as NSDictionary),
            "MEDIUMINT UNSIGNED"
        )
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": NSNull()] as NSDictionary),
            ""
        )
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: [:] as NSDictionary),
            ""
        )
    }

    func testFieldTypeClassification() {
        let intType = SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": "int(11)"] as NSDictionary)
        let binaryType = SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": "varbinary(64)"] as NSDictionary)
        let stringType = SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": "varchar(64)"] as NSDictionary)
        let unknownType = SPOptimizedFieldTypeEstimator.normalizedFieldType(fromDefinition: ["type": "json"] as NSDictionary)

        XCTAssertTrue(SPOptimizedFieldTypeEstimator.isIntegerFieldType(intType))
        XCTAssertTrue(SPOptimizedFieldTypeEstimator.isBinaryFieldType(binaryType))
        XCTAssertTrue(SPOptimizedFieldTypeEstimator.isStringFieldType(stringType))
        XCTAssertFalse(SPOptimizedFieldTypeEstimator.isIntegerFieldType(unknownType))
        XCTAssertFalse(SPOptimizedFieldTypeEstimator.isBinaryFieldType(nil))
        XCTAssertFalse(SPOptimizedFieldTypeEstimator.isStringFieldType(nil))
    }

    func testDecimalNumberParsingFromStats() {
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: " 42.5 "),
            NSDecimalNumber(string: "42.5")
        )
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: 12),
            NSDecimalNumber(string: "12")
        )
        XCTAssertNil(SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: nil))
        XCTAssertNil(SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: NSNull()))
        XCTAssertNil(SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: ""))
        XCTAssertNil(SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: "not a number"))
    }

    func testUnsignedIntegerParsingFromStats() {
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: " 17 "), 17)
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: 9), 9)
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: "-3"), 0)
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: nil), 0)
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: NSNull()), 0)
        XCTAssertEqual(SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: "abc"), 0)
    }

    func testMaxBytesPerCharacterResolution() {
        let utf8mb4Bytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: ["encodingName": "utf8mb4"] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: [["CHARACTER_SET_NAME": "utf8mb4", "MAXLEN": 4] as NSDictionary]
        )
        XCTAssertEqual(utf8mb4Bytes, 4)

        let latinBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: [:] as NSDictionary,
            tableEncoding: "latin1",
            availableEncodings: [["Charset": "LATIN1", "Maxlen": 1] as NSDictionary]
        )
        XCTAssertEqual(latinBytes, 1)

        let utf8HeuristicBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: ["encoding": "utf8_general_ci"] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: []
        )
        XCTAssertEqual(utf8HeuristicBytes, 3)

        let utf16HeuristicBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: ["encoding": "utf16le"] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: []
        )
        XCTAssertEqual(utf16HeuristicBytes, 4)

        let ucs2HeuristicBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: ["encoding": "ucs2"] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: []
        )
        XCTAssertEqual(ucs2HeuristicBytes, 2)

        let unknownEncodingBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: ["encoding": "latin1"] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: [["CHARACTER_SET_NAME": "latin1", "MAXLEN": 0] as NSDictionary]
        )
        XCTAssertEqual(unknownEncodingBytes, 1)

        let defaultBytes = SPOptimizedFieldTypeEstimator.maxBytesPerCharacter(
            forFieldDefinition: [:] as NSDictionary,
            tableEncoding: nil,
            availableEncodings: []
        )
        XCTAssertEqual(defaultBytes, 1)
    }

    func testEstimatedIntegerTypeBoundaries() {
        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.estimatedIntegerType(
                forMinimum: NSDecimalNumber(string: "0"),
                maximum: NSDecimalNumber(string: "255")
            ),
            "TINYINT UNSIGNED"
        )

        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.estimatedIntegerType(
                forMinimum: NSDecimalNumber(string: "-128"),
                maximum: NSDecimalNumber(string: "127")
            ),
            "TINYINT"
        )

        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.estimatedIntegerType(
                forMinimum: NSDecimalNumber(string: "-129"),
                maximum: NSDecimalNumber(string: "127")
            ),
            "SMALLINT"
        )

        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.estimatedIntegerType(
                forMinimum: NSDecimalNumber(string: "0"),
                maximum: NSDecimalNumber(string: "18446744073709551615")
            ),
            "BIGINT UNSIGNED"
        )

        XCTAssertEqual(
            SPOptimizedFieldTypeEstimator.estimatedIntegerType(
                forMinimum: NSDecimalNumber(string: "0"),
                maximum: NSDecimalNumber(string: "18446744073709551616")
            ),
            "BIGINT UNSIGNED"
        )
    }
}
