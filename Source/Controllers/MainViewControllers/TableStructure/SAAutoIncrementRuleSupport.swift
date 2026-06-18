import Foundation

@objc final class SAAutoIncrementRuleSupport: NSObject {
    private static let autoIncrementExtraValue = "AUTO_INCREMENT"
    private static let mysql84RestrictedExtraValues: Set<String> = [
        "AUTO_INCREMENT",
        "SERIAL DEFAULT VALUE"
    ]

    private static let integerFieldTypes: Set<String> = [
        "TINYINT",
        "SMALLINT",
        "MEDIUMINT",
        "INT",
        "INTEGER",
        "BIGINT",
        "BOOL",
        "BOOLEAN"
    ]

    @objc static func isAutoIncrementExtraValue(_ value: Any?) -> Bool {
        guard let value = value as? String else { return false }

        return normalizedExtraValue(value) == autoIncrementExtraValue
    }

    @objc(isMySQL84AutoIncrementRuleExtraValue:)
    static func isMySQL84AutoIncrementRuleExtraValue(_ value: Any?) -> Bool {
        guard let value = value as? String else { return false }

        return mysql84RestrictedExtraValues.contains(normalizedExtraValue(value))
    }

    @objc static func fieldTypeAllowsAutoIncrement(_ fieldType: String?) -> Bool {
        return integerFieldTypes.contains(normalizedFieldType(fieldType))
    }

    private static func normalizedExtraValue(_ value: String) -> String {
        return value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func normalizedFieldType(_ fieldType: String?) -> String {
        guard var type = fieldType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !type.isEmpty else {
            return ""
        }

        if let lengthStart = type.firstIndex(of: "(") {
            type = String(type[..<lengthStart])
        }

        return type.components(separatedBy: .whitespacesAndNewlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
