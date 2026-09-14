//
//  DateFormatterExtension.swift
//  Sequel Ace
//
//  Created by James on 3/11/2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation

extension DateFormatter {
	
	@objc public static var mediumStyleFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .medium
		return formatter
	}()

    @objc public static var iso8601DateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
	
	@objc public static var mediumStyleNoDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .medium
		return formatter
	}()

    @objc public static var shortStyleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
	
	@objc public static var shortStyleNoTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .none
		return formatter
	}()
	
	@objc public static var shortStyleNoDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short
		return formatter
	}()

	/// 2020-06-30 14:14:11 is  example
	@objc public static var naturalLanguageFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
		return formatter
	}()

    /// Formats a date-time the way MySQL prints it (`yyyy-MM-dd HH:mm:ss`,
    /// as in the `Create_time` of `SHOW TABLE STATUS`) in the user's date and
    /// time styles, showing the wall time as printed.
    ///
    /// The value is parsed by `mysqlDateTimeParser`, which is pinned to the
    /// Gregorian calendar, the POSIX locale and UTC: read with the system's
    /// calendar, a Buddhist or Japanese setting turns 2020 into another year,
    /// and read in the local time zone, a time inside a DST gap does not
    /// exist and parses to nothing. The result is shown in the same fixed
    /// zone, so nothing is converted: MySQL prints the time in the session's
    /// time zone, and that is what the user compares it with.
    ///
    /// - Parameters:
    ///   - value: The MySQL date-time as a string; `nil` or `NSNull` (a view
    ///     has no creation time) yields an empty string.
    ///   - dateStyle: The date style to show.
    ///   - timeStyle: The time style to show.
    /// - Returns: The formatted date-time, or an empty string when there is
    ///   none or it cannot be read.
    @objc(mysqlDateTimeString:dateStyle:timeStyle:)
    public static func mysqlDateTimeString(_ value: Any?, dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) -> String {
        guard let string = value as? String, let date = mysqlDateTimeParser.date(from: string) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatter.timeZone = mysqlDateTimeParser.timeZone
        return formatter.string(from: date)
    }

    /// The parser behind `mysqlDateTimeString(_:dateStyle:timeStyle:)`: the
    /// MySQL date-time format, Gregorian, POSIX and UTC, so that a value
    /// reads the same on every Mac.
    static let mysqlDateTimeParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

}
	
	
	

