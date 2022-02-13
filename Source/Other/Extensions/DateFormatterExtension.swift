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
		
}
	
	
	

