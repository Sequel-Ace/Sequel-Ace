//
//  StringRegexExtension.swift
//  sequel-ace
//
//  Created by James on 22/12/2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation


extension String {

    /// Returns the first string group matching the regex. A replacement for RegexLite's stringByMatching:(NSString *)regex capture:(NSInteger)capture
    /// It's a bit slower than RegexLite but not called often and means we can exclude RegexLite from the tunnel assistant and get some logging into RegexLite.
    /// - Parameters:
    ///   - regex: The regular expression - must contain group captures. e.g. "^\\s*Enter passphrase for key \\'(.*)\\':\\s*$"
    /// - Returns: The string matching the first group, or an empty string
    func captureGroup(regex: String) -> String {
        guard
            let regexValid = try? NSRegularExpression(pattern: regex, options: []),
            let match = regexValid.firstMatch(in: self, options: [], range: NSRange(self.startIndex..<self.endIndex, in: self)),
            let groupRange = Range(match.range(at: 1), in: self)
        else{
            return ""
        }

        return String(self[groupRange])
    }
}


@objc extension NSString {

    public func captureGroupFor(regex: NSString) -> NSString {
        return (self as String).captureGroup(regex: regex as String) as NSString
    }
}
