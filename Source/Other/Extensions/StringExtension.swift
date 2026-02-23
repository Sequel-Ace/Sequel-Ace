//
//  StringExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kaspar on 22.07.2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation

extension String {

    subscript(_ range: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
        let end = index(start, offsetBy: min(self.count - range.lowerBound,
                                             range.upperBound - range.lowerBound))
        return String(self[start..<end])
    }

    subscript(_ range: CountablePartialRangeFrom<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
        return String(self[start...])
    }

    func slice(from: String, to: String) -> String? {

        return (range(of: from)?.upperBound).flatMap { substringFrom in
            (range(of: to, range: substringFrom..<endIndex)?.lowerBound).map { substringTo in
                String(self[substringFrom..<substringTo])
            }
        }
    }

    static func rawByteString(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined().uppercased()
    }


    func dropPrefix(_ prefix: String) -> String {
		guard self.hasPrefix(prefix) else {
			return self
		}
		return String(self.dropFirst(prefix.count))
	}

    /// Return a copy of this string that does not end with the specified suffix
    /// - Parameter suffix: the suffix to trim from the end of the string
    func dropSuffix(_ suffix: String) -> String {
		guard self.hasSuffix(suffix) else {
			return self
		}
		return String(self.dropLast(suffix.count))
	}

	func hasPrefix(_ prefix: String, caseSensitive: Bool = true) -> Bool {
		switch caseSensitive {
			case true:
				return self.hasPrefix(prefix)
			case false:
				return self.lowercased().hasPrefix(prefix.lowercased())
		}
	}

	func hasSuffix(_ suffix: String, caseSensitive: Bool = true) -> Bool {
		switch caseSensitive {
			case true:
				return self.hasSuffix(suffix)
			case false:
				return self.lowercased().hasSuffix(suffix.lowercased())
		}
	}

    func separatedIntoLines() -> [String] {
        var lines: [String] = []
        let wholeString = self.startIndex..<self.endIndex
        self.enumerateSubstrings(in: wholeString, options: .byLines) {
            (substring, range, enclosingRange, stopPointer) in
            if let line = substring {
                lines.append(line)
            }
        }
        return lines
    }

    func separatedIntoLinesByCharset() -> [String] {

        var semiChar = CharacterSet()
        semiChar.insert(charactersIn: ";")

        let lines = (self as NSString).components(separatedBy: semiChar as CharacterSet).filter({ x in x.isNotEmpty})

        return lines
    }

    func format(_ arguments: CVarArg...) -> String {
            let args = arguments.map {
                if let arg = $0 as? Int { return String(arg) }
                if let arg = $0 as? Float { return String(arg) }
                if let arg = $0 as? Double { return String(arg) }
                if let arg = $0 as? Int64 { return String(arg) }
                if let arg = $0 as? String { return String(arg) }

                return "(null)"
            } as [CVarArg]

        return String.init(format: self, arguments: args)
    }
  
    var isNumeric: Bool {
        return !(self.isEmpty) && self.allSatisfy { $0.isNumber }
    }
    
	
	// stringByReplacingPercentEscapesUsingEncoding is deprecated
	// Use -stringByRemovingPercentEncoding
	// however: per https://developer.apple.com/documentation/foundation/nsstring/1409569-stringbyremovingpercentencoding?language=objc
	// You must call this method only on strings that you know to be percent-encoded
	// Generally, removingPercentEncoding fails when the original String contains non-escaped percent symbols
	// so before we replace stringByReplacingPercentEscapesUsingEncoding all over
	// we should check the string first
	var isPercentEncoded: Bool {
		
		guard let decoded = self.removingPercentEncoding else {
			return false
		}
		
		return self != decoded
		
	}

    // use new FileManager.userHomeDirectoryPath func
    var stringByExpandingTildeAsIfNotInSandbox: String {
        // str will be something like ~/.ssh/known_hosts
        let path = FileManager.default.userHomeDirectoryPath
        // fallback on the, er, dodgy method if path is empty
        if path.isEmpty {
            return self.stringByExpandingTildeAsIfNotInSandboxBackup
        }
        else {
            return path + self.dropPrefix("~")
        }
    }

    
    // returns the home dir of the user, as if we were not in a sandbox
    var stringByExpandingTildeAsIfNotInSandboxBackup: String {

        let str = NSString(string: self).expandingTildeInPath as String

        var prefix = "file://"
        // will be something like
        // file:///Users/james/Library/Containers/com.sequel-ace.sequel-ace/Data/.ssh/known_hosts
        // or /Users/james/Library/Containers/com.sequel-ace.sequel-ace/Data/.ssh/known_hosts

        var restOfString = ""
        var homedir = ""
        var suffix = ""

        let hasPrefix = str.hasPrefix(prefix)

        if hasPrefix == true {
            restOfString = String(str.dropFirst(prefix.count))
        }
        else {
            restOfString = str
            prefix = ""
        }

        // should now be something like
        // /Users/james/Library/Containers/com.sequel-ace.sequel-ace/Data/.ssh
        // users = get string between first two / /
        // username = get string between second two /Users/ and /Library/
        // get suffix or last path component
        guard
            let users    = restOfString.slice(from: "/", to: "/"),
            let username = restOfString.slice(from: "/Users/", to: "/Library/")
        else {
            return self
        }

        if let homedirTmp = NSHomeDirectory() as String? {
            homedir = homedirTmp
        }

        if let suffixTmp = restOfString.dropPrefix(homedir) as String? {
            suffix = suffixTmp
        }

        return prefix + "/" + users + "/" + username + suffix
    }
	
	// the string with new lines and spaces trimmed from BOTH ends
	var trimmedString: String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // the string with spaces trimmed from BOTH ends
    var whitespacesTrimmedString: String {
        return self.trimmingCharacters(in: .whitespaces)
    }
}

@objc(SPProcessListRowSerializer)
@objcMembers
public class SPProcessListRowSerializer: NSObject {
    private enum ProcessListColumnKey: String {
        case id = "Id"
        case user = "User"
        case host = "Host"
        case database = "db"
        case command = "Command"
        case time = "Time"
        case state = "State"
        case info = "Info"
        case progress = "Progress"
    }

    @objc(serializedProcessRow:includeProgress:)
    public class func serializedProcessRow(_ process: NSDictionary, includeProgress: Bool) -> String {
        let typedProcess = process as? [AnyHashable: Any] ?? [:]

        var rowValues = [
            ProcessListColumnKey.id,
            .user,
            .host,
            .database,
            .command,
            .time,
            .state,
            .info
        ].map { processValue(for: $0, in: typedProcess) }

        if includeProgress {
            let progressValue = processValue(for: .progress, in: typedProcess)
            if !progressValue.isEmpty {
                rowValues.append(progressValue)
            }
        }

        return rowValues.joined(separator: " ")
    }

    private class func processValue(
        for key: ProcessListColumnKey,
        in process: [AnyHashable: Any]
    ) -> String {
        guard let rawValue = process[key.rawValue], !(rawValue is NSNull) else {
            return ""
        }

        return String(describing: rawValue)
    }
}

@objc extension NSString {
    //Special space-character used to separate the column name and column type
    @objc static let columnHeaderSplittingSpace: String = " "

    @objc(tableContentColumnHeaderStringForColumnName:columnType:columnTypesVisible:)
    static func tableContentColumnHeaderString(columnName: String, columnType: String?, columnTypesVisible: Bool) -> String {
        guard columnTypesVisible, let columnType, !columnType.isEmpty else {
            return columnName
        }

        return "\(columnName)\(columnHeaderSplittingSpace)\(columnType)"
    }

    static func rawByteString(data: NSData) -> NSString {
        return String.rawByteString(data as Data) as NSString
    }

	public func dropPrefix(prefix: NSString) -> NSString {
		return (self as String).dropPrefix(prefix as String) as NSString
	}


    public func characterCount() -> Int {
        return (self as String).count;
    }

    /// Return a string that does not end with the specfied suffix.
    ///  The a copy of the string is returned if the suffix needs to be removed
    ///  - Parameter suffix - the suffix that should not terminate the returned string
	public func dropSuffix(suffix: NSString) -> NSString {
		return (self as String).dropSuffix(suffix as String) as NSString
	}

	public func hasPrefix(prefix: NSString, caseSensitive: Bool = true) -> Bool {
		return (self as String).hasPrefix(prefix as String, caseSensitive: caseSensitive)
	}

	public func hasSuffix(suffix: NSString, caseSensitive: Bool = true) -> Bool {
		return (self as String).hasSuffix(suffix as String, caseSensitive: caseSensitive)
	}

    public func separatedIntoLinesByCharsetObjC() -> [NSString] {
        return (self as String).separatedIntoLinesByCharset() as [NSString]
    }

	public func trimWhitespacesAndNewlines() -> NSString {
		return (self as String).trimmedString as NSString
	}

    public func trimWhitespaces() -> NSString {
        return (self as String).whitespacesTrimmedString as NSString
    }

    public func stringByExpandingTildeAsIfNotInSandboxObjC() -> NSString {
        return (self as String).stringByExpandingTildeAsIfNotInSandbox as NSString
    }

    public func isNumeric() -> Bool {
        return (self as String).isNumeric
    }

	public func isPercentEncoded() -> Bool {
		return (self as String).isPercentEncoded
	}

    public func separatedIntoLinesObjC() -> [NSString] {
        return (self as String).separatedIntoLines() as [NSString]
    }

    public func dateStringFromUnixTimestamp() -> NSString? {

        guard
            self.length < 12, // 2121-02-17 is 4769274709 - 10 chars. 3121 is 11 chars. 1921-02-17 = 1542050682, 10 chars
            self.length > 9,
            !(self as String).isEmpty,
            (self as String).dropPrefix("-").isNumeric,
            let timeInterval = self.doubleValue as Double?,
            timeInterval != 0.0
        else{
            return nil
        }

        let now = Int(Date().timeIntervalSince1970)

        let oneYear: Int = 31_536_000
        let numberOfYears: Int = 100
        let upperBound = now + (oneYear * numberOfYears)
        let lowerBound = now - (oneYear * numberOfYears)

        if Int(timeInterval) > lowerBound && Int(timeInterval) < upperBound {
            let date = Date(timeIntervalSince1970: timeInterval)
            let formatter = DateFormatter.iso8601DateFormatter
            return formatter.string(from: date) as NSString
        }
        return nil
    }
}

@objcMembers public final class SPFieldTypeClassifier: NSObject {
    private enum FieldTypeGroup: String {
        case bit
        case integer
        case float
    }

    private static let unquotedFieldTypes: Set<String> = [
        "BIT",
        "TINYINT",
        "SMALLINT",
        "MEDIUMINT",
        "INT",
        "INTEGER",
        "BIGINT",
        "FLOAT",
        "DOUBLE",
        "REAL",
        "DECIMAL",
        "DEC",
        "NUMERIC",
        "FIXED"
    ]

    @objc(shouldBeUnquotedWithFieldTypeGroup:fieldType:)
    public class func shouldBeUnquoted(fieldTypeGroup: String?, fieldType: String?) -> Bool {
        if let normalizedGroup = fieldTypeGroup?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           FieldTypeGroup(rawValue: normalizedGroup) != nil {
            return true
        }

        guard let fieldType else { return false }

        let normalizedFieldType = fieldType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFieldType.isEmpty else { return false }

        let baseType = normalizedFieldType.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        guard let typeToken = baseType.split(whereSeparator: \.isWhitespace).first else { return false }

        return unquotedFieldTypes.contains(typeToken.uppercased())
    }
}

@objcMembers public final class SPTableLoadFailure: NSObject {
    public let tableName: String
    public let databaseName: String
    public let loadTableType: Int

    private init(tableName: String, databaseName: String, tableType: Int) {
        self.tableName = tableName
        self.databaseName = databaseName
        self.loadTableType = tableType
        super.init()
    }

    @objc(failureWithTableName:database:tableType:)
    public class func failure(withTableName tableName: String?, database: String?, tableType: Int) -> SPTableLoadFailure {
        return SPTableLoadFailure(
            tableName: tableName ?? "",
            databaseName: database ?? "",
            tableType: tableType
        )
    }

    @objc(matchesTableName:database:tableType:)
    public func matches(tableName: String?, database: String?, tableType: Int) -> Bool {
        return self.loadTableType == tableType
            && self.tableName == (tableName ?? "")
            && self.databaseName == (database ?? "")
    }
}

@objcMembers public final class SPCharacterSetMetadataNormalizer: NSObject {
    private static let charsetNameKeys = ["CHARACTER_SET_NAME", "character_set_name", "Charset", "charset"]
    private static let descriptionKeys = ["DESCRIPTION", "Description", "description"]
    private static let defaultCollationKeys = ["DEFAULT_COLLATE_NAME", "default_collate_name", "Default collation", "Default Collation"]
    private static let maxLengthKeys = ["MAXLEN", "Maxlen", "maxlen"]

    @objc(normalizedCharacterSetEncodingsFromRows:)
    public class func normalizedCharacterSetEncodings(fromRows rows: [NSDictionary]) -> [NSDictionary] {
        guard !rows.isEmpty else { return [] }

        var normalizedRows: [NSDictionary] = []
        var seenCharsetNames = Set<String>()

        for row in rows {
            guard let charsetName = firstNonEmptyString(in: row, keys: charsetNameKeys),
                  !seenCharsetNames.contains(charsetName) else {
                continue
            }

            let description = firstNonEmptyString(in: row, keys: descriptionKeys) ?? ""
            let defaultCollationName = firstNonEmptyString(in: row, keys: defaultCollationKeys)
            let maxLength = firstNonEmptyString(in: row, keys: maxLengthKeys)

            var normalizedRow: [String: String] = [
                "CHARACTER_SET_NAME": charsetName,
                "DESCRIPTION": description
            ]

            if let defaultCollationName {
                normalizedRow["DEFAULT_COLLATE_NAME"] = defaultCollationName
            }
            if let maxLength {
                normalizedRow["MAXLEN"] = maxLength
            }

            seenCharsetNames.insert(charsetName)
            normalizedRows.append(normalizedRow as NSDictionary)
        }

        return normalizedRows
    }

    @objc(fallbackCharacterSetEncodings)
    public class func fallbackCharacterSetEncodings() -> [NSDictionary] {
        return [
            ["CHARACTER_SET_NAME": "utf8mb4", "DESCRIPTION": "UTF-8 Unicode", "DEFAULT_COLLATE_NAME": "utf8mb4_general_ci", "MAXLEN": "4"],
            ["CHARACTER_SET_NAME": "utf8", "DESCRIPTION": "UTF-8 Unicode (BMP only)", "DEFAULT_COLLATE_NAME": "utf8_general_ci", "MAXLEN": "3"],
            ["CHARACTER_SET_NAME": "latin1", "DESCRIPTION": "cp1252 West European", "DEFAULT_COLLATE_NAME": "latin1_swedish_ci", "MAXLEN": "1"]
        ] as [NSDictionary]
    }

    private class func firstNonEmptyString(in row: NSDictionary, keys: [String]) -> String? {
        for key in keys {
            guard let value = row[key] else { continue }
            let stringValue = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !stringValue.isEmpty {
                return stringValue
            }
        }
        return nil
    }
}
