import Foundation

@objc final class SAForeignKeyReferenceRuleSupport: NSObject {
    @objc(requiresStandardForeignKeyReferencesWithMariaDB:serverVersionIsAtLeast84:restrictionQueryErrored:restrictionValue:)
    static func requiresStandardForeignKeyReferences(isMariaDB: Bool, serverVersionIsAtLeast84: Bool, restrictionQueryErrored: Bool, restrictionValue: Any?) -> Bool {
        guard !isMariaDB, serverVersionIsAtLeast84 else { return false }
        guard !restrictionQueryErrored else { return true }

        return restrictionEnforcesStandardReferences(restrictionValue)
    }

    @objc(singleColumnUniqueReferenceColumns:)
    static func singleColumnUniqueReferenceColumns(_ indexRows: NSArray) -> NSSet {
        var uniqueIndexRows: [String: [NSDictionary]] = [:]

        for case let indexRow as NSDictionary in indexRows {
            guard integerValue(indexRow["Non_unique"]) == 0 else { continue }
            guard let keyName = stringValue(indexRow["Key_name"]), !keyName.isEmpty else { continue }

            uniqueIndexRows[keyName, default: []].append(indexRow)
        }

        var columnNames = Set<String>()
        for indexRows in uniqueIndexRows.values {
            guard indexRows.count == 1, let indexRow = indexRows.first else { continue }

            if let subPart = indexRow["Sub_part"], !(subPart is NSNull), !String(describing: subPart).isEmpty {
                continue
            }

            guard let columnName = stringValue(indexRow["Column_name"]), !columnName.isEmpty else { continue }

            columnNames.insert(columnName)
        }

        return columnNames as NSSet
    }

    static func restrictionEnforcesStandardReferences(_ restrictionValue: Any?) -> Bool {
        guard let normalized = stringValue(restrictionValue)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !normalized.isEmpty else {
            return true
        }

        return !["0", "OFF", "FALSE"].contains(normalized)
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }

        return String(describing: value)
    }

    private static func integerValue(_ value: Any?) -> Int {
        guard let value, !(value is NSNull) else { return 0 }

        if let number = value as? NSNumber {
            return number.intValue
        }

        return Int(String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}
