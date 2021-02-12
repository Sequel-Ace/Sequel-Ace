//
//  StringExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kaspar on 22.07.2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation
import os.log

extension String {
	func dropPrefix(_ prefix: String) -> String {
		guard self.hasPrefix(prefix) else {
			return self
		}
		return String(self.dropFirst(prefix.count))
	}

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
	
	// the string with new lines and spaces trimmed from BOTH ends
	var trimmedString: String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@objc extension NSString {
	public func dropPrefix(prefix: NSString) -> NSString {
		return (self as String).dropPrefix(prefix as String) as NSString
	}

	public func dropSuffix(suffix: NSString) -> NSString {
		return (self as String).dropSuffix(suffix as String) as NSString
	}

	public func hasPrefix(prefix: NSString, caseSensitive: Bool = true) -> Bool {
		return (self as String).hasPrefix(prefix as String, caseSensitive: caseSensitive)
	}

	public func hasSuffix(suffix: NSString, caseSensitive: Bool = true) -> Bool {
		return (self as String).hasSuffix(suffix as String, caseSensitive: caseSensitive)
	}
	
	public func trimWhitespacesAndNewlines() -> NSString {
		return (self as String).trimmedString as NSString
	}
	
	public func isPercentEncoded() -> Bool {
		return (self as String).isPercentEncoded
	}

    public func separatedIntoLinesObjc() -> [NSString] {
        return (self as String).separatedIntoLines() as [NSString]
    }

    public func dateStringFromUnixTimestamp() -> NSString? {
        os_log("string [%@]", log: OSLog.default, type: .error, self)

        guard
            let timeInterval = self.doubleValue as Double?,
            timeInterval != 0.0
        else{
            os_log("string [%@] cannot be represented as a double", log: OSLog.default, type: .error, self)
            return nil
        }

        let now = Int(Date().timeIntervalSince1970)
        os_log("unix timestamp for now: %i", log: OSLog.default, type: .debug, now)

        let oneHundredYears: Int = 3153600000
        let upperBound = now + oneHundredYears
        let lowerBound = now - oneHundredYears

        if Int(timeInterval) > lowerBound && Int(timeInterval) < upperBound {
            os_log("unix timestamp within +/- oneHundredYears", log: OSLog.default, type: .debug)
            let date = Date(timeIntervalSince1970: timeInterval)
            let formatter = DateFormatter.iso8601DateFormatter
            return formatter.string(from: date) as NSString
        }
        os_log("unix timestamp NOT within +/- oneHundredYears", log: OSLog.default, type: .debug)
        return nil
    }


}
