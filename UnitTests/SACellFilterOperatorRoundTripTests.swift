//
//  SACellFilterOperatorRoundTripTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACellFilterOperatorRoundTripTests: XCTestCase {

    /// Verifies every advertised operator has a matching ContentFilters.plist definition.
    func testAllAdvertisedOperatorsExistInContentFiltersPlist() throws {
        let contentFilters = try loadContentFilters()

        for pair in SACellFilterOperator.allAdvertisedPairs() {
            let filterType = SACellFilterOperator.filterDefinitionGroup(forTypeGrouping: pair.typeGrouping)
            let definitions = try XCTUnwrap(contentFilters[filterType] as? [[String: Any]], "Missing filter definitions for \(filterType)")
            let definition = definitions.first { $0["MenuLabel"] as? String == pair.op.serializedName }

            XCTAssertNotNil(definition, "\(pair.op.serializedName) missing from ContentFilters.plist for typegrouping \(pair.typeGrouping)")
            XCTAssertEqual(definition?["MenuLabel"] as? String, pair.op.serializedName)
            XCTAssertEqual(definition?["NumberOfArguments"] as? Int, pair.op.valueCount)
        }
    }

    private func loadContentFilters() throws -> [String: Any] {
        let candidateBundles = [Bundle.main, Bundle(for: Self.self)] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in candidateBundles {
            guard let path = bundle.path(forResource: "ContentFilters", ofType: "plist"),
                  let filters = NSDictionary(contentsOfFile: path) as? [String: Any] else {
                continue
            }
            return filters
        }

        XCTFail("Could not find ContentFilters.plist in any loaded bundle")
        return [:]
    }

    /// Verifies the filter-type mapping keeps BIT on the persisted `number`
    /// type while only its built-in definitions come from the `bit` group.
    func testRuleFilterGroupMapping() {
        XCTAssertEqual(SACellFilterOperator.ruleFilterGroup(forTypeGrouping: "bit"), "number")
        XCTAssertEqual(SACellFilterOperator.ruleFilterGroup(forTypeGrouping: "integer"), "number")
        XCTAssertEqual(SACellFilterOperator.ruleFilterGroup(forTypeGrouping: "float"), "number")
        XCTAssertEqual(SACellFilterOperator.ruleFilterGroup(forTypeGrouping: "date"), "date")
        XCTAssertEqual(SACellFilterOperator.ruleFilterGroup(forTypeGrouping: "enum"), "string")
        XCTAssertEqual(SACellFilterOperator.ruleFilterGroup(forTypeGrouping: "geometry"), "spatial")
        XCTAssertEqual(SACellFilterOperator.ruleFilterGroup(forTypeGrouping: nil), "")
        XCTAssertEqual(SACellFilterOperator.ruleFilterGroup(forTypeGrouping: "unknown_type_group"), "")

        XCTAssertEqual(SACellFilterOperator.filterDefinitionGroup(forTypeGrouping: "bit"), "bit")
        XCTAssertEqual(SACellFilterOperator.filterDefinitionGroup(forTypeGrouping: "integer"), "number")
        XCTAssertEqual(SACellFilterOperator.filterDefinitionGroup(forTypeGrouping: "enum"), "string")
        XCTAssertEqual(SACellFilterOperator.filterDefinitionGroup(forTypeGrouping: nil), "")
    }

    /// Verifies every definition group the mapping can return is loaded from ContentFilters.plist.
    func testEveryMappedDefinitionGroupIsLoaded() throws {
        let contentFilters = try loadContentFilters()
        for typeGrouping in ["bit", "integer", "float", "date", "string", "binary", "textdata", "blobdata", "enum", "geometry"] {
            let group = SACellFilterOperator.filterDefinitionGroup(forTypeGrouping: typeGrouping)
            XCTAssertTrue(SACellFilterOperator.filterDefinitionGroups.contains(group), "\(group) is not in filterDefinitionGroups")
            XCTAssertNotNil(contentFilters[group] as? [[String: Any]], "ContentFilters.plist has no \(group) group")
        }
    }

    /// Legacy fixture: BIT rules saved by earlier versions (`.spf`,
    /// contentFilterV2) carry `filterType = number`. They must restore through
    /// the real rule-filter controller and re-serialize unchanged - the
    /// controller drops a rule whose saved filter type differs from the
    /// operator's, which would silently remove the predicate.
    func testLegacyNumberTypedBitRulesRestoreUnchanged() throws {
        let controllerClass = try XCTUnwrap(NSClassFromString("SPRuleFilterController") as? NSObject.Type)
        let controller = controllerClass.init()
        let ruleEditor = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 600, height: 120))
        ruleEditor.delegate = controller as? NSRuleEditorDelegate
        controller.setValue(ruleEditor, forKey: "filterRuleEditor")
        controller.perform(NSSelectorFromString("setColumns:"), with: [["name": "flags", "typegrouping": "bit"]])

        let legacyRules: [[String: Any]] = [
            ["filterClass": "expressionNode", "column": "flags", "filterType": "number", "filterComparison": "=", "filterValues": ["5"], "enabled": true],
            ["filterClass": "expressionNode", "column": "flags", "filterType": "number", "filterComparison": "IS NULL", "filterValues": [String](), "enabled": true],
            ["filterClass": "expressionNode", "column": "flags", "filterType": "number", "filterComparison": "BETWEEN", "filterValues": ["1", "3"], "enabled": true]
        ]

        for legacyRule in legacyRules {
            let comparison = try XCTUnwrap(legacyRule["filterComparison"] as? String)
            controller.perform(NSSelectorFromString("restoreSerializedFilters:"), with: legacyRule)
            let restored = try XCTUnwrap(
                controller.perform(NSSelectorFromString("serializedFilter"))?.takeUnretainedValue() as? [String: Any],
                "\(comparison) did not restore"
            )

            XCTAssertEqual(restored["filterClass"] as? String, "expressionNode", "\(comparison) did not restore as an expression")
            XCTAssertEqual(restored["column"] as? String, "flags", "\(comparison) changed its column")
            XCTAssertEqual(restored["filterType"] as? String, "number", "\(comparison) changed its persisted filter type")
            XCTAssertEqual(restored["filterComparison"] as? String, comparison)
            XCTAssertEqual(restored["filterValues"] as? [String], legacyRule["filterValues"] as? [String], "\(comparison) changed its values")
        }
    }

    /// Verifies the BIT definitions offer the same operators as the number
    /// definitions, so saved BIT filters keep restoring, and that their value
    /// comparisons go through CAST('<value>' AS DECIMAL(65,30)): a quoted
    /// comparison finds no row on an indexed BIT column and compares values
    /// above 2^53 as floating point, while the decimal cast is exact up to 2^64
    /// and keeps negative and fractional bounds intact.
    func testBitFilterDefinitionsCompareExactDecimalValues() throws {
        let contentFilters = try loadContentFilters()
        let bitDefinitions = try XCTUnwrap(contentFilters["bit"] as? [[String: Any]])
        let numberDefinitions = try XCTUnwrap(contentFilters["number"] as? [[String: Any]])

        XCTAssertEqual(
            bitDefinitions.compactMap { $0["MenuLabel"] as? String },
            numberDefinitions.compactMap { $0["MenuLabel"] as? String }
        )

        let valueComparisons: Set<String> = ["=", "≠", ">", "<", "≥", "≤", "BETWEEN"]
        for definition in bitDefinitions {
            guard let label = definition["MenuLabel"] as? String, valueComparisons.contains(label) else { continue }
            let clause = try XCTUnwrap(definition["Clause"] as? String)
            let argumentCount = try XCTUnwrap(definition["NumberOfArguments"] as? Int)
            let castArguments = clause.components(separatedBy: "CAST('${}' AS DECIMAL(65,30))").count - 1
            XCTAssertEqual(castArguments, argumentCount, "\(label) must compare every argument as CAST('${}' AS DECIMAL(65,30))")
        }
    }
}
