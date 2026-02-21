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
