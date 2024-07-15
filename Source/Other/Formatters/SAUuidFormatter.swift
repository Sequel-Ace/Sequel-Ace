//
//  Created by Luis Aguiniga on 2024.07.07
//  Copyright © 2024 Sequel-Ace. All rights reserved.
//

import Foundation



@objc final class SAUuidFormatter: SABaseFormatter {
    static let REGEX_PAIRS = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
    static let REGEX_VALID_CHARS = try! NSRegularExpression(pattern: "[^0-9a-f\\-]", options: .caseInsensitive)
    static var nullStr: String? { UserDefaults.standard.string(forKey: SPNullValue) }

    static func invalidCharactersInUuid(in str: String) -> NSString {
        return String(format: NSLocalizedString("Invalid UUID Character in: %@", comment: "Invalid UUID Character"), str) as NSString
    }

    static func invalidUuid(_ str: String) -> NSString {
        return String(format: NSLocalizedString("Invalid UUID: %@", comment: "Invalid UUID"), str) as NSString
    }

    // MARK: - SABaseFormatter Overrides

    override var maxLengthOverride: UInt { 36 } // 32 + 4 hyphens

    override var label: String { NSLocalizedString("UUID Display Override", comment: "Field Editor Label") }

    // MARK: - Formatter Overrides

    override func string(for obj: Any?) -> String? {
        guard let data = obj as? Data else {
            return nil
        }

        return convertToUuidString(data)
    }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        guard !isNullValue(string) && string != "" else {
            obj?.pointee = NSNull()
            return true
        }

        guard containsOnlyValidUuidCharacters(string) else {
            error?.pointee = Self.invalidCharactersInUuid(in: string)
            return false
        }

        guard let data = hexToData(string) else {
            error?.pointee = Self.invalidUuid(string)
            return false
        }
        obj?.pointee = data as NSData

        return true
    }

    override func isPartialStringValid(_ partialString: String, newEditingString
                                       newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                       errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        guard containsOnlyValidUuidCharacters(partialString) else {
            error?.pointee = Self.invalidCharactersInUuid(in: partialString)
            return false
        }

        return true
    }

    override func isPartialStringValid(_ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
                                       proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
                                       originalString origString: String,
                                       originalSelectedRange origSelRange: NSRange,
                                       errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        let newString = partialStringPtr.pointee as String

        if isPartialMatchForNullValue(newString) {
            return true
        }

        guard containsOnlyValidUuidCharacters(newString) else {
            error?.pointee = Self.invalidCharactersInUuid(in: newString)
            return false
        }

        guard removeHyphens(newString).lengthOfBytes(using: .utf8) <= 32 else {
            error?.pointee = Self.invalidUuid(newString)
            return false
        }

        return true
    }

    // MARK: - Helper Methods

    func isPartialMatchForNullValue(_ s: String) -> Bool {
        if let nul = Self.nullStr, nul.contains(s) {
            // not valid characters but user could be trying null the value out.
            return true
        }
        return false
    }

    func isNullValue(_ s: String) -> Bool {
        if let NUL = Self.nullStr, NUL == s {
            // not valid characters but user could be trying null the value out.
            return true
        }
        return false
    }

    func containsOnlyValidUuidCharacters(_ s: String) -> Bool {
        if isPartialMatchForNullValue(s) {
            return true
        }

        let range = NSRange(s.startIndex..., in: s)
        return Self.REGEX_VALID_CHARS.matches(in: s, range: range).isEmpty
    }

    func hexToData(_ s: String) -> Data? {
        let hex = removeHyphens(s)
        let len = hex.lengthOfBytes(using: .utf8)
        guard len == 32 || len == 0 else {
            return nil
        }

        var data = Data(capacity: 16)
        let range = NSRange(hex.startIndex..., in: hex)

        Self.REGEX_PAIRS.enumerateMatches(in: hex, range: range) { match, _, _ in
            let pair = (hex as NSString).substring(with: match!.range)
            let byte = UInt8(pair, radix: 16)!
            data.append(byte)
        }

        return data
    }

    func removeHyphens(_ s: String) -> String {
        if s.contains("-") {
            return s.replacingOccurrences(of: "-", with: "").trimmedString
        }

        return s.trimmedString
    }

    // https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Strings/Articles/formatSpecifiers.html
    func convertToUuidString(_ data: Data) -> String? {
        guard data.count == 16 else {
            return nil
        }

        var str = data.map({ byte in String(format: "%02hhX", byte)}).joined()
        str.insert("-", at: str.index(str.startIndex, offsetBy: 8))
        str.insert("-", at: str.index(str.startIndex, offsetBy: 13))
        str.insert("-", at: str.index(str.startIndex, offsetBy: 18))
        str.insert("-", at: str.index(str.startIndex, offsetBy: 23))

        return str
    }
}
