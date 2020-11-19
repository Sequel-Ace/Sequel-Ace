//
//  DateFormatterExtension.swift
//  Sequel Ace
//
//  Created by James on 3/11/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

extension DateFormatter {
	
	@objc public static var mediumStyleFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .medium
		return formatter
	}()
	
	@objc public static var mediumStyleNoDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .medium
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
		
}
	
	
	

