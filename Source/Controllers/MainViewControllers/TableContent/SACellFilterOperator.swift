//
//  SACellFilterOperator.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

@objcMembers public final class SACellFilterOperator: NSObject {
    public let menuTitle: String
    public let serializedName: String
    public let valueCount: Int
    public let typeGroupings: Set<String>

    public init(menuTitle: String, serializedName: String, valueCount: Int, typeGroupings: Set<String>) {
        self.menuTitle = menuTitle
        self.serializedName = serializedName
        self.valueCount = valueCount
        self.typeGroupings = typeGroupings
        super.init()
    }

    @objc(operatorsForTypeGrouping:)
    public static func operators(for typeGrouping: String?) -> [SACellFilterOperator] {
        guard let typeGrouping, typeGrouping.isNotEmpty else {
            return []
        }

        return catalog.filter { $0.typeGroupings.contains(typeGrouping) }
    }

    @objc(operatorsForTypeGrouping:cellIsNull:)
    public static func operators(for typeGrouping: String?, cellIsNull: Bool) -> [SACellFilterOperator] {
        let operators = operators(for: typeGrouping)
        if cellIsNull {
            return operators.filter { $0.valueCount == 0 }
        }

        return operators.filter { $0.valueCount > 0 }
    }

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

public struct SACellFilterOperatorPair {
    public let typeGrouping: String
    public let op: SACellFilterOperator
}
