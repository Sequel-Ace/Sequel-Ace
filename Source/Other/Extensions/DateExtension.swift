//
//  DateExtention.swift
//  Sequel Ace
//
//  Created by James on 3/11/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

extension Date {
	
	public func format(_ format: String, locale: Locale, timeZone: TimeZone) -> String {
		let formatter = DateFormatter.mediumStyleFormatter
		
		formatter.dateFormat = format
		formatter.locale = locale
		formatter.timeZone = timeZone
		
		return formatter.string(from: self)
	}
	
	public func format(_ format: String, timeZone: TimeZone) -> String {
		return self.format(format, locale: .current, timeZone: timeZone)
	}
	
	public func format(_ format: String, locale: Locale) -> String {
		return self.format(format, locale: locale, timeZone: .current)
	}
	
	public func format(_ format: String) -> String {
		return self.format(format, locale: .current, timeZone: .current)
	}
}

@objc extension NSDate {
	
	public func format(format: NSString) -> String {
		return (self as Date).format(format as String)
	}
	
	public func format(format: NSString, locale: NSLocale) -> String {
		return (self as Date).format(format as String, locale: locale as Locale)
	}
	
	public func format(format: NSString, timeZone: NSTimeZone) -> String {
		return (self as Date).format(format as String, timeZone: timeZone as TimeZone)
	}
	
	public func format(format: NSString, locale: NSLocale, timeZone: NSTimeZone) -> String {
		return (self as Date).format(format as String, locale: locale as Locale, timeZone: timeZone as TimeZone)
	}
}

