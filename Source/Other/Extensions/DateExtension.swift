//
//  DateExtention.swift
//  Sequel Ace
//
//  Created by James on 3/11/2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation

extension Date {

	/// Formats the date with an explicit format string.
	///
	/// Uses a formatter of its own: the shared `DateFormatter` instances are
	/// configured once for their style and used from several places (e.g.
	/// `mediumStyleFormatter` for the Create/Update time in Table
	/// Information), so setting `dateFormat` on one of them would change what
	/// every other caller shows until the app restarts.
	///
	/// - Parameters:
	///   - format: A Unicode date format pattern such as `yyyy-MM-dd`.
	///   - locale: The locale to format in; defaults to the current one.
	///   - timeZone: The time zone to format in; defaults to the current one.
	/// - Returns: The formatted date.
	public func string(format: String, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
		let formatter = DateFormatter()

		formatter.dateFormat = format
		formatter.locale = locale
		formatter.timeZone = timeZone

		return formatter.string(from: self)
	}
}

@objc extension NSDate {
		
	public func string(format: NSString, locale: NSLocale, timeZone: NSTimeZone) -> String {
		return (self as Date).string(format: format as String, locale: locale as Locale, timeZone: timeZone as TimeZone)
	}
}

