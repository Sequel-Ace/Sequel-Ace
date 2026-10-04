//
//  SAContentFilterLengthTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.09.14.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Cocoa
import XCTest

/// The `sqlWhereExpressionWithBinary:error:` signature of `SPRuleFilterController`, which `perform(_:)`
/// cannot call because it takes a `BOOL` and an `NSError **`.
@objc private protocol SARuleFilterSQLGenerating {
    @objc(sqlWhereExpressionWithBinary:error:)
    func sqlWhereExpression(withBinary isBinary: Bool, error: NSErrorPointer) -> String?
}

/// Covers the "length" string filters from issue #1844 in ContentFilters.plist.
final class SAContentFilterLengthTests: XCTestCase {

    /// Verifies string fields offer the three length filters, each taking one argument.
    func testLengthFiltersAreDefinedForStringFields() throws {
        let filters = try lengthFilters()

        XCTAssertEqual(filters.compactMap { $0["MenuLabel"] as? String }, ["length =", "length >", "length <"])

        for filter in filters {
            let label = filter["MenuLabel"] as? String ?? ""
            XCTAssertEqual(filter["NumberOfArguments"] as? Int, 1, "\(label) takes one argument")
            XCTAssertEqual(filter["SuppressLeadingFieldPlaceholder"] as? Bool, true, "\(label) suppresses the leading field")
        }
    }

    /// Verifies the controller turns each length filter into a CHAR_LENGTH comparison. CHAR_LENGTH counts characters
    /// in the column's character set where LENGTH would count bytes, and without SuppressLeadingFieldPlaceholder the
    /// field would be emitted twice (`` `name` CHAR_LENGTH(`name`) > 5 ``).
    func testLengthFiltersProduceCharLengthComparison() throws {
        let expected = [
            "length =": "CHAR_LENGTH(`name`) = 5",
            "length >": "CHAR_LENGTH(`name`) > 5",
            "length <": "CHAR_LENGTH(`name`) < 5",
        ]

        for (comparison, clause) in expected {
            let controller = try makeController(columns: ["name"])
            controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: [
                "filterClass": "expressionNode",
                "column": "name",
                "filterComparison": comparison,
                "filterValues": ["5"],
            ])

            var error: NSError?
            let sql = unsafeBitCast(controller, to: SARuleFilterSQLGenerating.self).sqlWhereExpression(withBinary: false, error: &error)

            XCTAssertNil(error, comparison)
            XCTAssertEqual(sql, clause, comparison)
        }
    }

    // MARK: - Helpers

    /// The `length` entries from the `string` section of the shipping ContentFilters.plist.
    private func lengthFilters() throws -> [[String: Any]] {
        let candidateBundles = [Bundle.main, Bundle(for: Self.self)] + Bundle.allBundles
        for bundle in candidateBundles {
            guard let path = bundle.path(forResource: "ContentFilters", ofType: "plist"),
                  let filters = NSDictionary(contentsOfFile: path)?["string"] as? [[String: Any]] else {
                continue
            }
            return filters.filter { ($0["MenuLabel"] as? String)?.hasPrefix("length ") == true }
        }

        XCTFail("Could not find string filters in ContentFilters.plist in any loaded bundle")
        return []
    }

    /// Creates an `SPRuleFilterController` with a bare rule editor and the given string columns, via KVC/selectors
    /// because the test target has no bridging header for the Objective-C class.
    private func makeController(columns: [String]) throws -> NSObject {
        let controllerClass = try XCTUnwrap(NSClassFromString("SPRuleFilterController") as? NSObject.Type)
        let controller = controllerClass.init()
        let ruleEditor = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        ruleEditor.delegate = controller as? NSRuleEditorDelegate
        controller.setValue(ruleEditor, forKey: "filterRuleEditor")
        controller.perform(NSSelectorFromString("setColumns:"), with: columns.map { ["name": $0, "typegrouping": "string"] })
        return controller
    }
}
