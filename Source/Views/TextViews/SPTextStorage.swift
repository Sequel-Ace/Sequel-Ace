//
//  SPTextStorage.swift
//  Sequel Ace
//
//  Created by Jakub Kaspar on 04.12.2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

@objc final class SPTextStorage: NSTextStorage {

	private var storage = NSTextStorage()

	// MARK: - Required overrides for NSTextStorage

	override var string: String {
		return storage.string
	}

	override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
		return storage.attributes(at: location, effectiveRange: range)
	}

	override func replaceCharacters(in range: NSRange, with str: String) {
		beginEditing()
		storage.replaceCharacters(in: range, with: str)
		edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
		endEditing()
	}

	override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
		beginEditing()
		storage.setAttributes(attrs, range: range)
		edited(.editedAttributes, range: range, changeInLength: 0)
		endEditing()
	}

	// MARK: - DOuble click functionality

	override func doubleClick(at location: Int) -> NSRange {

		// Call super to get location of the double click
		var range = super.doubleClick(at: location)
		let stringCopy = self.string

		// If the user double-clicked a period, just return the range of the period
		let locationIndex = stringCopy.index(stringCopy.startIndex, offsetBy: location)
		guard stringCopy[locationIndex] != "." else {
			return NSMakeRange(location, 1)
		}

		// The case where super's behavior is wrong involves the dot operator; x.y should not be considered a word.
		// So we check for a period before or after the anchor position, and trim away the periods and everything
		// past them on both sides. This will correctly handle longer sequences like foo.bar.baz.is.a.test.
		let candidateRangeBeforeLocation = NSMakeRange(range.location, location - range.location)
		let candidateRangeAfterLocation = NSMakeRange(location + 1, NSMaxRange(range) - (location + 1))
		let periodBeforeRange = (stringCopy as NSString).range(of: ".", options: .backwards, range: candidateRangeBeforeLocation)
		let periodAfterRange = (stringCopy as NSString).range(of: ".", options: [], range: candidateRangeAfterLocation)

		if periodBeforeRange.location != NSNotFound {
			// Change range to start after the preceding period; fix its length so its end remains unchanged
			range.length -= (periodBeforeRange.location + 1 - range.location)
			range.location = periodBeforeRange.location + 1
		}
		if periodAfterRange.location != NSNotFound {
			// Change range to end before the following period
			range.length -= (NSMaxRange(range) - periodAfterRange.location);
		}

		return range
	}
}
