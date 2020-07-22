//
//  StringExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kaspar on 22.07.2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

extension String {
	func drop(prefix: String) -> String {
		guard self.hasPrefix(prefix) else {
			return self
		}
		return String(self.dropFirst(prefix.count))
	}

	func drop(suffix: String) -> String {
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
}

@objc extension NSString {
	func drop(prefix: NSString) -> NSString {
		return (self as String).drop(prefix: prefix)
	}

	func drop(suffix: NSString) -> NSString {
		return (self as String).drop(suffix: suffix)
	}

	func hasPrefix(_ prefix: NSString, caseSensitive: Bool = true) -> Bool {
		return (self as String).hasPrefix(prefix, caseSensitive: caseSensitive)
	}

	func hasSuffix(_ suffix: NSString, caseSensitive: Bool = true) -> Bool {
		return (self as String).hasSuffix(suffix, caseSensitive: caseSensitive)
	}
}
