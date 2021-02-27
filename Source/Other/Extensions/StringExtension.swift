//
//  StringExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kaspar on 22.07.2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
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

    // returns the home dir of the user, as if we were not in a sandbox
    var stringByExpandingTildeAsIfNotInSandbox: String {

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
