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
		formatter.formatterBehavior = Behavior.behavior10_4
		formatter.dateStyle = Style.medium
		formatter.timeStyle = Style.medium
		return formatter
	}()
		
}
	
	
	

