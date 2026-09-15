//
//  DateFormatterExtension.swift
//  Sequel Ace
//
//  Created by James on 3/11/2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation

/// Shared, preconfigured formatters. Each is set up once for its style and
/// read from several places, so callers must not change `dateFormat`,
/// `locale` or `timeZone` on them; use `Date.string(format:locale:timeZone:)`
/// for one-off formats instead.
extension DateFormatter {

	@objc public static let mediumStyleFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .medium
		return formatter
	}()

    @objc public static let iso8601DateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
	
	@objc public static let mediumStyleNoDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .medium
		return formatter
	}()

    @objc public static let shortStyleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
	
	@objc public static let shortStyleNoTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .none
		return formatter
	}()
	
	@objc public static let shortStyleNoDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short
		return formatter
	}()

	/// 2020-06-30 14:14:11 is  example
	@objc public static let naturalLanguageFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
		return formatter
	}()
		
}
	
	
	

