//
//  SACellFilterOperator.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// One operator advertised by the cell-filter context menu.
///
/// The serialized name must match `ContentFilters.plist` exactly because the
/// descriptor is later restored through `SPRuleFilterController`.
@objcMembers public final class SACellFilterOperator: NSObject {
    /// Menu title shown in the "Filter by Selected Value" submenu.
    public let menuTitle: String

    /// Operator name stored in the serialized rule-filter dictionary.
    public let serializedName: String

    /// Number of argument values this operator expects.
    ///
    /// `IS NULL` and `IS NOT NULL` use zero; value-bearing operators use one.
    public let valueCount: Int

    /// Type groupings for which this operator is valid.
    public let typeGroupings: Set<String>

    /// Creates an operator catalog entry.
    ///
    /// - Parameters:
    ///   - menuTitle: Visible menu title.
    ///   - serializedName: Rule-filter operator name.
    ///   - valueCount: Number of argument values the operator requires.
    ///   - typeGroupings: Supported Sequel Ace column type groupings.
    public init(menuTitle: String, serializedName: String, valueCount: Int, typeGroupings: Set<String>) {
        self.menuTitle = menuTitle
        self.serializedName = serializedName
        self.valueCount = valueCount
        self.typeGroupings = typeGroupings
        super.init()
    }

    /// Returns all operators supported for a type grouping.
    ///
    /// Unknown, nil, or empty type groupings intentionally return no operators
    /// so the context menu does not offer a filter it cannot restore.
    ///
    /// - Parameter typeGrouping: Type grouping from the table-content column definition.
    /// - Returns: Catalog entries valid for that grouping.
    @objc(operatorsForTypeGrouping:)
    public static func operators(for typeGrouping: String?) -> [SACellFilterOperator] {
        guard let typeGrouping, typeGrouping.isNotEmpty else {
            return []
        }

        return catalog.filter { $0.typeGroupings.contains(typeGrouping) }
    }

    /// Returns operators appropriate for the selected cell value.
    ///
    /// NULL cells can only use zero-argument NULL operators. Non-NULL cells use
    /// value-bearing operators so the selected value can become the rule argument.
    ///
    /// - Parameters:
    ///   - typeGrouping: Type grouping from the table-content column definition.
    ///   - cellIsNull: Whether the selected raw cell value is SQL NULL.
    /// - Returns: Operators suitable for the current value state.
    @objc(operatorsForTypeGrouping:cellIsNull:)
    public static func operators(for typeGrouping: String?, cellIsNull: Bool) -> [SACellFilterOperator] {
        let operators = operators(for: typeGrouping)
        if cellIsNull {
            // NULL cell: only the zero-argument NULL operators make sense.
            return operators.filter { $0.valueCount == 0 }
        }

        // Non-NULL cell: keep value operators AND zero-argument NULL operators.
        // Dropping NULL operators here would make the Filter submenu disappear
        // entirely for type groupings whose catalog is NULL-only
        // (binary / blobdata / geometry) — even though `IS NOT NULL` is a
        // valid and useful filter on a non-NULL cell of those types. For
        // value-bearing types (string / number / date) the user also gets
        // `IS NULL` / `IS NOT NULL` alongside the value operators, letting
        // them pivot to "find other rows where this column is empty/non-empty"
        // from the same context menu without re-clicking the rule editor.
        return operators
    }

    /// Every `ContentFilters.plist` group holding built-in operator definitions.
    @objc public static let filterDefinitionGroups = ["number", "date", "string", "spatial", "bit"]

    /// Maps a column type grouping to its rule-filter type: the key saved as
    /// `filterType` in serialized filters (`.spf`, `contentFilterV2`) and under
    /// which user-defined content filters are stored.
    ///
    /// `bit` columns keep the `number` type, so filters saved by older
    /// versions restore unchanged and existing custom number filters stay
    /// available on them; only their built-in definitions differ (see
    /// `filterDefinitionGroup(forTypeGrouping:)`).
    ///
    /// - Parameter typeGrouping: Type grouping from the column definition.
    /// - Returns: The filter type, or an empty string for an unknown grouping.
    @objc(ruleFilterGroupForTypeGrouping:)
    public static func ruleFilterGroup(forTypeGrouping typeGrouping: String?) -> String {
        switch typeGrouping {
        case "date":
            return "date"
        case "string", "binary", "textdata", "blobdata", "enum":
            return "string"
        case "bit", "integer", "float":
            return "number"
        case "geometry":
            return "spatial"
        default:
            return ""
        }
    }

    /// Maps a column type grouping to the `ContentFilters.plist` group whose
    /// built-in operator definitions the rule filter offers for it.
    ///
    /// `bit` columns use the `bit` definitions: the same operators as
    /// `number`, but value comparisons go through
    /// `CAST('<value>' AS DECIMAL(65,30))`. A quoted comparison finds no row on
    /// an indexed `BIT` column and compares values above 2^53 as floating
    /// point; the decimal cast is exact up to 2^64 and keeps negative and
    /// fractional bounds intact.
    ///
    /// - Parameter typeGrouping: Type grouping from the column definition.
    /// - Returns: The definition group, or an empty string for an unknown grouping.
    @objc(filterDefinitionGroupForTypeGrouping:)
    public static func filterDefinitionGroup(forTypeGrouping typeGrouping: String?) -> String {
        typeGrouping == "bit" ? "bit" : ruleFilterGroup(forTypeGrouping: typeGrouping)
    }

    /// Enumerates every advertised `(typeGrouping, operator)` pair for tests.
    ///
    /// Round-trip tests use this to verify each advertised operator exists in
    /// `ContentFilters.plist` and survives restore/serialize through the real
    /// rule-filter controller.
    ///
    /// - Returns: All supported type/operator combinations.
    public static func allAdvertisedPairs() -> [SACellFilterOperatorPair] {
        var pairs: [SACellFilterOperatorPair] = []
        for typeGrouping in supportedTypeGroupings {
            for op in operators(for: typeGrouping) {
                pairs.append(SACellFilterOperatorPair(typeGrouping: typeGrouping, op: op))
            }
        }
        return pairs
    }

    private static let numberTypeGroupings: Set<String> = ["bit", "integer", "float"]
    private static let stringTypeGroupings: Set<String> = ["string", "textdata", "enum"]

    private static let supportedTypeGroupings = [
        "bit",
        "integer",
        "float",
        "date",
        "string",
        "textdata",
        "binary",
        "blobdata",
        "enum",
        "geometry",
    ]

    private static let nullOperators = [
        SACellFilterOperator(menuTitle: "IS NULL", serializedName: "IS NULL", valueCount: 0, typeGroupings: Set(supportedTypeGroupings)),
        SACellFilterOperator(menuTitle: "IS NOT NULL", serializedName: "IS NOT NULL", valueCount: 0, typeGroupings: Set(supportedTypeGroupings)),
    ]

    private static let catalog: [SACellFilterOperator] = [
        SACellFilterOperator(menuTitle: "=", serializedName: "=", valueCount: 1, typeGroupings: numberTypeGroupings),
        SACellFilterOperator(menuTitle: "≠", serializedName: "≠", valueCount: 1, typeGroupings: numberTypeGroupings),
        SACellFilterOperator(menuTitle: ">", serializedName: ">", valueCount: 1, typeGroupings: numberTypeGroupings),
        SACellFilterOperator(menuTitle: "<", serializedName: "<", valueCount: 1, typeGroupings: numberTypeGroupings),
        SACellFilterOperator(menuTitle: "≥", serializedName: "≥", valueCount: 1, typeGroupings: numberTypeGroupings),
        SACellFilterOperator(menuTitle: "≤", serializedName: "≤", valueCount: 1, typeGroupings: numberTypeGroupings),

        SACellFilterOperator(menuTitle: "=", serializedName: "=", valueCount: 1, typeGroupings: ["date"]),
        SACellFilterOperator(menuTitle: "≠", serializedName: "≠", valueCount: 1, typeGroupings: ["date"]),
        SACellFilterOperator(menuTitle: "is after", serializedName: "is after", valueCount: 1, typeGroupings: ["date"]),
        SACellFilterOperator(menuTitle: "is before", serializedName: "is before", valueCount: 1, typeGroupings: ["date"]),
        SACellFilterOperator(menuTitle: "is after or equal to", serializedName: "is after or equal to", valueCount: 1, typeGroupings: ["date"]),
        SACellFilterOperator(menuTitle: "is before or equal to", serializedName: "is before or equal to", valueCount: 1, typeGroupings: ["date"]),

        SACellFilterOperator(menuTitle: "=", serializedName: "=", valueCount: 1, typeGroupings: stringTypeGroupings),
        SACellFilterOperator(menuTitle: "≠", serializedName: "≠", valueCount: 1, typeGroupings: stringTypeGroupings),
        SACellFilterOperator(menuTitle: "LIKE", serializedName: "LIKE", valueCount: 1, typeGroupings: stringTypeGroupings),
        SACellFilterOperator(menuTitle: "NOT LIKE", serializedName: "NOT LIKE", valueCount: 1, typeGroupings: stringTypeGroupings),
        SACellFilterOperator(menuTitle: "contains", serializedName: "contains", valueCount: 1, typeGroupings: stringTypeGroupings),
        SACellFilterOperator(menuTitle: "does not contain", serializedName: "does not contain", valueCount: 1, typeGroupings: stringTypeGroupings),
    ] + nullOperators
}

/// Test-only pairing of a type grouping with one advertised operator.
public struct SACellFilterOperatorPair {
    /// Type grouping used to select a rule-filter operator list.
    public let typeGrouping: String

    /// Operator advertised for the type grouping.
    public let op: SACellFilterOperator
}
