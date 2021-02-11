//
//  DateExtention.swift
//  Sequel Ace
//
//  Created by James on 3/11/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

extension Date {
	
	public func string(format: String, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
		let formatter = DateFormatter.mediumStyleFormatter
		
		formatter.dateFormat = format
		formatter.locale = locale
		formatter.timeZone = timeZone
		
		return formatter.string(from: self)
	}

    func addDaysToDate(daysToAdd: Int) -> Date {

        guard let newDate = Calendar.current.date(
                byAdding: .day,
                value: daysToAdd,
                to: self)
        else {
            return Date()
        }

        return newDate
    }
}

@objc extension NSDate {
		
	public func string(format: NSString, locale: NSLocale, timeZone: NSTimeZone) -> String {
		return (self as Date).string(format: format as String, locale: locale as Locale, timeZone: timeZone as TimeZone)
	}
}

