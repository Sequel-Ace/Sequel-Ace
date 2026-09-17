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

	/// Whether the string starts with the specified prefix
	/// - Parameters:
	///   - prefix: the prefix to look for at the start of the string
	///   - caseSensitive: false to compare both strings lowercased
	func hasPrefix(_ prefix: String, caseSensitive: Bool = true) -> Bool {
		switch caseSensitive {
			case true:
				return self.hasPrefix(prefix)
			case false:
				return self.lowercased().hasPrefix(prefix.lowercased())
		}
	}

	/// Whether the string ends with the specified suffix
	/// - Parameters:
	///   - suffix: the suffix to look for at the end of the string
	///   - caseSensitive: false to compare both strings lowercased
	func hasSuffix(_ suffix: String, caseSensitive: Bool = true) -> Bool {
		switch caseSensitive {
			case true:
				return self.hasSuffix(suffix)
			case false:
				return self.lowercased().hasSuffix(suffix.lowercased())
		}
	}

    /// The string's lines, split on every line break Unicode recognises and
    /// with the breaks themselves dropped.
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

    /// The string split on every semicolon, with the empty parts dropped.
    func separatedIntoLinesByCharset() -> [String] {

        var semiChar = CharacterSet()
        semiChar.insert(charactersIn: ";")

        let lines = (self as NSString).components(separatedBy: semiChar as CharacterSet).filter({ x in x.isNotEmpty})

        return lines
    }

    /// The string taken as a format string, with the arguments substituted.
    ///
    /// Int, Float, Double, Int64 and String arguments are described first, so
    /// that a placeholder is filled whichever of them is passed; an argument
    /// of any other type becomes "(null)".
    /// - Parameter arguments: the values to substitute into the format
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

    /// One row of the process list as a single line of text, its columns
    /// separated by spaces.
    ///
    /// - Parameters:
    ///   - process: One row of `SHOW PROCESSLIST`.
    ///   - includeProgress: Whether to append the Progress column, which is
    ///     left off when the row carries no value for it.
    /// - Returns: The row's values joined by single spaces.
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

    /// The text one column of a process list row serializes to.
    ///
    /// - Parameters:
    ///   - key: The `SHOW PROCESSLIST` column to read.
    ///   - process: One row of the process list.
    /// - Returns: The value described as a string, or an empty string when the
    ///   row carries no such column or holds `NSNull` for it.
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

/// What a length-limited table cell does with the text an edit would leave
/// in it. `SPDataCellFormatter` asks for it while a value is typed or pasted,
/// then shows the matching tooltip and applies the cut; the limit is the
/// column's length in code points, as MySQL counts it.
@objc public enum SATextLimitDecision: Int {
    /// No length rule applies - no limit is set, or the text is the NULL
    /// placeholder itself. Accept it without the formatter's other checks.
    case exempt
    /// The text fits the limit. Accept it, subject to the formatter's other
    /// checks (a BIT column's 0/1 rule).
    case withinLimit
    /// One code point too many, most likely typed. Refuse the change.
    case refuse
    /// Further over the limit, most likely pasted. Accept the text cut to the
    /// limit with `prefix(codePoints:)`.
    case truncate
}

/// What the field editor sheet does with an edit to its text, which is
/// limited to a column's length in code points, as MySQL counts it.
/// `SPFieldEditorController` asks for it before a typed or pasted change is
/// made and applies it.
@objcMembers public final class SAFieldEditorEditLimit: NSObject {
    /// Whether the edit can go ahead as it is.
    public let allowsEdit: Bool

    /// The start of the inserted text that still fits, to put in place of the
    /// replaced range instead of the whole insertion. `nil` when the edit is
    /// allowed or when nothing more fits.
    public let fittingInsertion: String?

    /// Creates a decision. Only
    /// `evaluate(text:replacing:with:limit:fieldType:)` makes these; callers
    /// read the two properties.
    ///
    /// - Parameters:
    ///   - allowsEdit: Whether the edit can go ahead as it is.
    ///   - fittingInsertion: The start of the insertion that still fits, or
    ///     `nil` when the edit is allowed or nothing more fits.
    private init(allowsEdit: Bool, fittingInsertion: String?) {
        self.allowsEdit = allowsEdit
        self.fittingInsertion = fittingInsertion
        super.init()
    }

    /// Decides how the sheet treats replacing `range` of `text` with
    /// `replacement` when the text may hold `limit` code points.
    ///
    /// Every length is counted in code points: the text, the part of it the
    /// edit replaces and the insertion. `range` is an `NSRange` in UTF-16
    /// units and only locates the replaced part; subtracting its length from
    /// code point counts would let a paste over selected emoji through
    /// uncut.
    ///
    /// A FLOAT value's decimal point does not count against the limit, judged
    /// on the text the edit leaves behind: typing "." into "123" at a limit of
    /// 3 is allowed, and replacing the "." of "1.23" with a digit is measured
    /// without the allowance. A cut insertion keeps one code point more only
    /// when the kept text or the part of the insertion that is kept holds the
    /// point.
    ///
    /// - Parameters:
    ///   - text: The sheet's text before the edit.
    ///   - range: The range of `text` the edit replaces, in UTF-16 units.
    ///   - replacement: The text the edit inserts.
    ///   - limit: The column's length in code points; greater than 0.
    ///   - fieldType: The column's type, such as "FLOAT"; the decimal point
    ///     allowance applies to FLOAT only.
    /// - Returns: An allowed edit, or a refused one with the part of
    ///   `replacement` that still fits, if any.
    @objc(evaluateEditOfText:replacingRange:withString:limit:fieldType:)
    public static func evaluate(text: NSString, replacing range: NSRange, with replacement: NSString, limit: Int, fieldType: String?) -> SAFieldEditorEditLimit {
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), text.length - location)
        let replacedRange = NSRange(location: location, length: length)
        let keptText = text.replacingCharacters(in: replacedRange, with: "") as NSString
        let keptCount = keptText.characterCount()
        let newLength = keptCount + replacement.characterCount()

        let isFloat = fieldType?.uppercased() == "FLOAT"
        let keptHoldsPoint = keptText.range(of: ".").location != NSNotFound
        /// The number of code points the FLOAT decimal point adds to `limit`
        /// for an edit inserting `insertion`: 1 when the text the edit leaves
        /// behind would hold a point, 0 for every other column type.
        func decimalPointAllowance(inserting insertion: NSString) -> Int {
            guard isFloat else { return 0 }
            return keptHoldsPoint || insertion.range(of: ".").location != NSNotFound ? 1 : 0
        }

        guard newLength > limit + decimalPointAllowance(inserting: replacement) else {
            return SAFieldEditorEditLimit(allowsEdit: true, fittingInsertion: nil)
        }

        var insertableCount = limit + decimalPointAllowance(inserting: replacement) - keptCount
        if insertableCount > 0, decimalPointAllowance(inserting: replacement.prefix(codePoints: insertableCount)) < decimalPointAllowance(inserting: replacement) {
            // The point that granted the allowance is not in the kept part.
            insertableCount -= 1
        }
        guard insertableCount > 0 else {
            return SAFieldEditorEditLimit(allowsEdit: false, fittingInsertion: nil)
        }
        return SAFieldEditorEditLimit(allowsEdit: false, fittingInsertion: replacement.prefix(codePoints: insertableCount) as String)
    }

    /// Whether replacing `range` of `text` with `replacement` leaves the NULL
    /// placeholder, or its start while it is typed. The sheet lets such an edit
    /// past its length rules, as the table cells do, so NULL can be entered
    /// into a column shorter than the placeholder - typed, or pasted over a
    /// selection.
    ///
    /// - Parameters:
    ///   - text: The sheet's text before the edit.
    ///   - range: The range of `text` the edit replaces, in UTF-16 units.
    ///   - replacement: The text the edit inserts.
    ///   - nullValue: The NULL placeholder from the preferences, if any.
    /// - Returns: `false` as well when `range` does not lie within `text`.
    @objc(isNullPlaceholderEditOfText:replacingRange:withString:nullValue:)
    public static func isNullPlaceholderEdit(text: NSString, replacing range: NSRange, with replacement: NSString, nullValue: String?) -> Bool {
        guard range.location != NSNotFound, NSMaxRange(range) <= text.length else {
            return false
        }
        let proposed = text.replacingCharacters(in: range, with: replacement as String) as NSString
        return proposed.isNullPlaceholderOrItsStart(nullValue)
    }
}

/// What a length-limited table cell does with an edit, judged on the text, the
/// part of it the edit replaces and the insertion - not on the prospective
/// string as a whole. Cutting that string to the limit would drop text behind
/// the insertion point: replacing the "c" of "abcde" with "XYZ" in a
/// `VARCHAR(5)` cell would leave "abXYZ" and lose the "de".
@objcMembers public final class SACellEditLimit: NSObject {
    /// Whether the edit can go ahead as it is.
    public let allowsEdit: Bool

    /// Whether no length rule applies at all - no limit is set, or the text is
    /// the NULL placeholder being typed. The cell's other checks, such as a BIT
    /// column's 0/1 rule, are skipped then, so a value can always be nulled.
    public let isExempt: Bool

    /// The text the cell should hold instead, with only the insertion cut to
    /// what fits. `nil` when the edit is allowed, or when nothing of the
    /// insertion fits and the edit is refused.
    public let replacementText: String?

    /// Where the insertion point belongs in `replacementText`, in UTF-16
    /// units: right behind the part of the insertion that was kept.
    public let selectionLocation: Int

    /// Creates a decision. Only
    /// `evaluate(text:replacing:with:limit:fieldType:nullValue:)` makes these.
    ///
    /// - Parameters:
    ///   - allowsEdit: Whether the edit can go ahead as it is.
    ///   - isExempt: Whether no length rule applies at all.
    ///   - replacementText: The text to put in the cell instead, if any.
    ///   - selectionLocation: Where the insertion point belongs in it.
    private init(allowsEdit: Bool, isExempt: Bool = false, replacementText: String?, selectionLocation: Int) {
        self.allowsEdit = allowsEdit
        self.isExempt = isExempt
        self.replacementText = replacementText
        self.selectionLocation = selectionLocation
        super.init()
    }

    /// Decides how a cell treats replacing `range` of `text` with
    /// `replacement` when the column holds `limit` code points.
    ///
    /// Lengths count code points, as MySQL counts a column's length. The NULL
    /// placeholder is exempt while it is being typed, so a short limit cannot
    /// stop a user from nulling the value.
    ///
    /// - Parameters:
    ///   - text: The cell's text before the edit.
    ///   - range: The range of `text` the edit replaces, in UTF-16 units.
    ///   - replacement: The text the edit inserts.
    ///   - limit: The column's length in code points; 0 means no limit.
    ///   - fieldType: The column's type, such as "FLOAT".
    ///   - nullValue: The NULL placeholder from the preferences, if any.
    /// - Returns: An allowed edit, or a refused one with the text the cell
    ///   should hold instead, if anything of the insertion fits.
    @objc(evaluateCellEditOfText:replacingRange:withString:limit:fieldType:nullValue:)
    public static func evaluate(text: NSString, replacing range: NSRange, with replacement: NSString, limit: Int, fieldType: String?, nullValue: String?) -> SACellEditLimit {
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), text.length - location)
        let replacedRange = NSRange(location: location, length: length)
        let proposed = text.replacingCharacters(in: replacedRange, with: replacement as String)

        let isNullPlaceholder = nullValue.map { $0 == proposed || $0.hasPrefix(proposed) } ?? false
        guard limit > 0, !isNullPlaceholder else {
            return SACellEditLimit(allowsEdit: true, isExempt: true, replacementText: nil, selectionLocation: 0)
        }

        let decision = SAFieldEditorEditLimit.evaluate(text: text, replacing: replacedRange, with: replacement, limit: limit, fieldType: fieldType)
        guard !decision.allowsEdit else {
            return SACellEditLimit(allowsEdit: true, replacementText: nil, selectionLocation: 0)
        }
        guard let fitting = decision.fittingInsertion else {
            return SACellEditLimit(allowsEdit: false, replacementText: nil, selectionLocation: 0)
        }
        let cut = text.replacingCharacters(in: replacedRange, with: fitting)
        return SACellEditLimit(allowsEdit: false,
                               replacementText: cut,
                               selectionLocation: replacedRange.location + (fitting as NSString).length)
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

    /// The bytes of `data` as an uppercase hexadecimal string. The `NSString`
    /// counterpart of `String.rawByteString(_:)`, for Objective-C callers.
    ///
    /// - Parameter data: The bytes to describe.
    static func rawByteString(data: NSData) -> NSString {
        return String.rawByteString(data as Data) as NSString
    }

	/// A copy of this string without `prefix` at its start, or the string
	/// itself when it does not start with it. The `NSString` counterpart of
	/// `String.dropPrefix(_:)`, for Objective-C callers.
	///
	/// - Parameter prefix: The prefix to trim from the start of the string.
	public func dropPrefix(prefix: NSString) -> NSString {
		return (self as String).dropPrefix(prefix as String) as NSString
	}


    /// The number of characters as MySQL counts them against a column's
    /// length: Unicode code points, not the grapheme clusters Swift's `count`
    /// yields. A flag or family emoji and a decomposed `é` are one grapheme
    /// but several code points, and a `VARCHAR(n)` column holds `n` of the
    /// latter.
    public func characterCount() -> Int {
        return (self as String).unicodeScalars.count
    }

    /// The UTF-16 length of the prefix that holds the first `count` code
    /// points - where the surplus of an over-long text starts, as an
    /// `NSRange` location. Counting the limit in UTF-16 units instead would
    /// land inside a surrogate pair.
    ///
    /// - Parameter count: The number of code points to keep.
    /// - Returns: The UTF-16 length of that prefix, or the whole length when
    ///   the string has no more code points than that.
    @objc(utf16LengthOfFirstCodePoints:)
    public func utf16Length(ofFirstCodePoints count: Int) -> Int {
        guard count >= 0 else { return 0 }
        return (self as String).unicodeScalars.prefix(count).reduce(0) { $0 + UTF16.width($1) }
    }

    /// The prefix holding the first `count` code points, cut between code
    /// points so no surrogate pair is split into U+FFFD.
    ///
    /// - Parameter count: The number of code points to keep.
    @objc(prefixOfCodePoints:)
    public func prefix(codePoints count: Int) -> NSString {
        return substring(to: utf16Length(ofFirstCodePoints: count)) as NSString
    }

    /// Whether this text is the NULL placeholder or the start of it - what a
    /// cell holds while the user types NULL. The comparison is exact, as the
    /// placeholder is typed; an empty text or a missing placeholder is neither.
    /// The cell formatter's whole-string rules use it to let typing NULL past
    /// the BIT rule, as `SACellEditLimit` does for an edit it can locate.
    ///
    /// - Parameter nullValue: The NULL placeholder from the preferences, if any.
    @objc(isNullPlaceholderOrItsStart:)
    public func isNullPlaceholderOrItsStart(_ nullValue: String?) -> Bool {
        guard let nullValue, length > 0 else { return false }
        return nullValue.hasPrefix(self as String)
    }

    /// Decides how a table cell limited to `limit` code points treats this
    /// text, the text an edit would leave in it.
    ///
    /// The NULL placeholder itself is exempt, and while the text is still the
    /// start of the placeholder ("N", "NU", "NUL" for "NULL") it is accepted
    /// however short the column is, so NULL can be typed into it. Any other
    /// text one code point over the limit is refused as a typo, and text
    /// further over the limit is cut to it.
    ///
    /// Only the start of the placeholder is let through, not any part of it:
    /// typing NULL passes through its prefixes only, while a fragment such as
    /// "UL" is not on that way and would otherwise slip past a one-character
    /// limit. The placeholder is compared as the formatter always did, with
    /// `range(of:)`, now anchored to its start.
    ///
    /// - Parameters:
    ///   - limit: The column's length in code points; 0 means no limit.
    ///   - nullValue: The NULL placeholder the user types, if any.
    /// - Returns: `.exempt` without a limit or for the placeholder itself,
    ///   `.refuse`, `.truncate` or `.withinLimit` otherwise.
    @objc(textLimitDecisionForLimit:nullValue:)
    public func textLimitDecision(limit: Int, nullValue: String?) -> SATextLimitDecision {
        if limit == 0 || (nullValue.map { isEqual(to: $0) } ?? false) {
            return .exempt
        }

        let count = characterCount()
        let startsNullValue = nullValue.map { ($0 as NSString).range(of: self as String, options: .anchored).location != NSNotFound } ?? false
        if count == limit + 1 && !startsNullValue {
            return .refuse
        }

        if count > limit && !startsNullValue {
            return .truncate
        }

        return .withinLimit
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

@objcMembers final class SPOptimizedFieldTypeEstimator: NSObject {

    private static let integerFieldTypes: Set<String> = [
        "TINYINT", "SMALLINT", "MEDIUMINT", "INT", "INTEGER", "BIGINT"
    ]
    private static let binaryFieldTypes: Set<String> = [
        "BINARY", "VARBINARY", "TINYBLOB", "BLOB", "MEDIUMBLOB", "LONGBLOB"
    ]
    private static let stringFieldTypes: Set<String> = [
        "CHAR", "VARCHAR", "NCHAR", "NVARCHAR", "TINYTEXT", "TEXT", "MEDIUMTEXT", "LONGTEXT"
    ]

    @objc(normalizedFieldTypeFromDefinition:)
    static func normalizedFieldType(fromDefinition fieldDefinition: NSDictionary) -> String {
        guard let rawType = fieldDefinition["type"], !(rawType is NSNull) else { return "" }
        let fieldType = String(describing: rawType).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fieldType.isEmpty else { return "" }
        let uppercasedType = fieldType.uppercased()
        if let suffixStart = uppercasedType.firstIndex(of: "(") {
            return String(uppercasedType[..<suffixStart]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return uppercasedType.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc(isIntegerFieldType:)
    static func isIntegerFieldType(_ fieldType: String?) -> Bool {
        guard let fieldType = fieldType else { return false }
        return integerFieldTypes.contains(fieldType)
    }

    @objc(isBinaryFieldType:)
    static func isBinaryFieldType(_ fieldType: String?) -> Bool {
        guard let fieldType = fieldType else { return false }
        return binaryFieldTypes.contains(fieldType)
    }

    @objc(isStringFieldType:)
    static func isStringFieldType(_ fieldType: String?) -> Bool {
        guard let fieldType = fieldType else { return false }
        return stringFieldTypes.contains(fieldType)
    }

    @objc(decimalNumberFromStatValue:)
    static func decimalNumber(fromStatValue value: Any?) -> NSDecimalNumber? {
        guard let value = value, !(value is NSNull) else { return nil }
        let numberString = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !numberString.isEmpty else { return nil }
        let number = NSDecimalNumber(string: numberString)
        if number == NSDecimalNumber.notANumber {
            return nil
        }
        return number
    }

    @objc(unsignedIntegerValueFromStatValue:)
    static func unsignedIntegerValue(fromStatValue value: Any?) -> UInt {
        guard let value = value, !(value is NSNull) else { return 0 }
        let numberString = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !numberString.isEmpty else { return 0 }
        let parsedValue = max(Int64(numberString) ?? 0, 0)
        return UInt(parsedValue)
    }

    @objc(maxBytesPerCharacterForFieldDefinition:tableEncoding:availableEncodings:)
    static func maxBytesPerCharacter(
        forFieldDefinition fieldDefinition: NSDictionary,
        tableEncoding: String?,
        availableEncodings: [NSDictionary]
    ) -> UInt {
        var encodingName = (fieldDefinition["encodingName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if encodingName.isEmpty {
            encodingName = (fieldDefinition["encoding"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if encodingName.isEmpty {
            encodingName = tableEncoding?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard !encodingName.isEmpty else { return 1 }

        for encoding in availableEncodings {
            var characterSetName = (encoding["CHARACTER_SET_NAME"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if characterSetName.isEmpty {
                characterSetName = (encoding["Charset"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            guard !characterSetName.isEmpty else { continue }
            guard characterSetName.caseInsensitiveCompare(encodingName) == .orderedSame else { continue }

            var maxBytes = unsignedIntegerValue(fromStatValue: encoding["MAXLEN"])
            if maxBytes == 0 {
                maxBytes = unsignedIntegerValue(fromStatValue: encoding["Maxlen"])
            }
            return max(maxBytes, 1)
        }

        let lowercaseEncoding = encodingName.lowercased()
        if lowercaseEncoding.hasPrefix("utf8mb4") || lowercaseEncoding.hasPrefix("utf16") || lowercaseEncoding.hasPrefix("utf32") {
            return 4
        }
        if lowercaseEncoding.hasPrefix("utf8") {
            return 3
        }
        if lowercaseEncoding.hasPrefix("ucs2") {
            return 2
        }
        return 1
    }

    @objc(estimatedIntegerTypeForMinimum:maximum:)
    static func estimatedIntegerType(forMinimum minimum: NSDecimalNumber, maximum: NSDecimalNumber) -> String {
        struct IntegerRange {
            let type: String
            let signedMin: String
            let signedMax: String
            let unsignedMax: String
        }

        let ranges: [IntegerRange] = [
            IntegerRange(type: "TINYINT", signedMin: "-128", signedMax: "127", unsignedMax: "255"),
            IntegerRange(type: "SMALLINT", signedMin: "-32768", signedMax: "32767", unsignedMax: "65535"),
            IntegerRange(type: "MEDIUMINT", signedMin: "-8388608", signedMax: "8388607", unsignedMax: "16777215"),
            IntegerRange(type: "INT", signedMin: "-2147483648", signedMax: "2147483647", unsignedMax: "4294967295"),
            IntegerRange(type: "BIGINT", signedMin: "-9223372036854775808", signedMax: "9223372036854775807", unsignedMax: "18446744073709551615")
        ]

        let canUseUnsigned = minimum.compare(NSDecimalNumber.zero) != .orderedAscending

        for range in ranges {
            if canUseUnsigned {
                let unsignedMax = NSDecimalNumber(string: range.unsignedMax)
                if maximum.compare(unsignedMax) != .orderedDescending {
                    return "\(range.type) UNSIGNED"
                }
            } else {
                let signedMin = NSDecimalNumber(string: range.signedMin)
                let signedMax = NSDecimalNumber(string: range.signedMax)
                if minimum.compare(signedMin) != .orderedAscending && maximum.compare(signedMax) != .orderedDescending {
                    return range.type
                }
            }
        }

        return canUseUnsigned ? "BIGINT UNSIGNED" : "BIGINT"
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

    /// Returns whether values of a column go into SQL unquoted - numeric types
    /// and `BIT` - judged by the type grouping or, when that is missing or
    /// wrong, by the declared field type.
    ///
    /// - Parameters:
    ///   - fieldTypeGroup: Sequel Ace type grouping of the column.
    ///   - fieldType: Declared column type, e.g. `INT(10) UNSIGNED`.
    /// - Returns: `true` when the value must not be wrapped in quotes.
    @objc(shouldBeUnquotedWithFieldTypeGroup:fieldType:)
    public class func shouldBeUnquoted(fieldTypeGroup: String?, fieldType: String?) -> Bool {
        if let normalizedGroup = fieldTypeGroup?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           FieldTypeGroup(rawValue: normalizedGroup) != nil {
            return true
        }

        guard let typeToken = baseTypeToken(of: fieldType) else { return false }

        return unquotedFieldTypes.contains(typeToken)
    }

    /// Returns whether a column holds MySQL `BIT` values, judged by the type
    /// grouping or, when that is missing or wrong, by the declared field type.
    ///
    /// - Parameters:
    ///   - fieldTypeGroup: Sequel Ace type grouping of the column.
    ///   - fieldType: Declared column type, e.g. `BIT(8)`.
    /// - Returns: `true` for `BIT` columns.
    @objc(isBitFieldWithFieldTypeGroup:fieldType:)
    public class func isBitField(fieldTypeGroup: String?, fieldType: String?) -> Bool {
        if fieldTypeGroup?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == FieldTypeGroup.bit.rawValue {
            return true
        }
        return baseTypeToken(of: fieldType) == "BIT"
    }

    /// Returns the SQL literal for a value of a column that
    /// `shouldBeUnquoted(fieldTypeGroup:fieldType:)` classifies as unquoted.
    ///
    /// SPMySQL delivers `BIT` values as strings of `0`/`1` digits. Written
    /// verbatim, MySQL would read `00000101` back as the decimal number 101,
    /// so `BIT` values become binary literals (`b'00000101'`); every other
    /// value is written verbatim.
    ///
    /// - Parameters:
    ///   - value: The cell value.
    ///   - fieldTypeGroup: Sequel Ace type grouping of the column.
    ///   - fieldType: Declared column type.
    /// - Returns: The literal, or `nil` for a `BIT` value that is not a bit string.
    @objc(unquotedSQLLiteralForValue:fieldTypeGroup:fieldType:)
    public class func unquotedSQLLiteral(for value: Any, fieldTypeGroup: String?, fieldType: String?) -> String? {
        if isBitField(fieldTypeGroup: fieldTypeGroup, fieldType: fieldType) {
            return bitLiteral(for: value)
        }
        return String(describing: value)
    }

    /// Formats a `BIT` cell value as a MySQL binary literal (`b'0101'`).
    ///
    /// - Parameter value: The cell value, a string of `0`/`1` digits.
    /// - Returns: The literal, or `nil` when the value is not a bit string.
    @objc(bitLiteralForValue:)
    public class func bitLiteral(for value: Any) -> String? {
        guard let bits = validatedBitString(from: value) else { return nil }
        return "b'\(bits)'"
    }

    /// Converts a `BIT` display value into its decimal value, the argument the
    /// `bit` filter definitions compare via `CAST('<value>' AS DECIMAL(65,30))` -
    /// passing the display string would compare with 101 for `00000101`.
    ///
    /// - Parameter bitString: Display value of the cell, a string of `0`/`1` digits.
    /// - Returns: The decimal string, or `nil` when the value is not a bit
    ///   string or does not fit into 64 bits.
    @objc(decimalStringForBitString:)
    public class func decimalString(forBitString bitString: String) -> String? {
        guard let bits = validatedBitString(from: bitString),
              let number = UInt64(bits, radix: 2) else {
            return nil
        }
        return String(number)
    }

    /// Returns the value a rule filter needs for a raw cell value compared
    /// against a column of the given type grouping, as used when following a
    /// foreign key: a `BIT` value (a string of `0`/`1` digits) becomes its
    /// decimal value, every other value is returned unchanged.
    ///
    /// - Parameters:
    ///   - value: The raw cell value of the source column.
    ///   - targetTypeGrouping: Sequel Ace type grouping of the filtered column.
    /// - Returns: The value to filter by.
    @objc(filterValueForValue:targetTypeGrouping:)
    public class func filterValue(for value: Any?, targetTypeGrouping: String?) -> Any? {
        guard isBitField(fieldTypeGroup: targetTypeGrouping, fieldType: nil),
              let bits = value as? String,
              let decimal = decimalString(forBitString: bits) else {
            return value
        }
        return decimal
    }

    /// Returns the value as a non-empty string of `0`/`1` digits, or `nil`.
    private class func validatedBitString(from value: Any) -> String? {
        let bits = String(describing: value)
        guard !bits.isEmpty, bits.allSatisfy({ $0 == "0" || $0 == "1" }) else { return nil }
        return bits
    }

    /// Returns the upper-cased base type of a declared column type
    /// (`int(10) unsigned` becomes `INT`), or `nil` when there is none.
    private class func baseTypeToken(of fieldType: String?) -> String? {
        guard let fieldType else { return nil }

        let normalizedFieldType = fieldType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFieldType.isEmpty else { return nil }

        let baseType = normalizedFieldType.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        guard let typeToken = baseType.split(whereSeparator: \.isWhitespace).first else { return nil }

        return typeToken.uppercased()
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
