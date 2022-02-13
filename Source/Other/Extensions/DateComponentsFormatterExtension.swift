//
//  DateComponentsFormatterExtension.swift
//  Sequel Ace
//
//  Created by James on 3/11/2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import Foundation

extension DateComponentsFormatter {
	
	@objc public static var hourMinSecFormatter: DateComponentsFormatter = {
			
		let formatter = DateComponentsFormatter()
		formatter.allowedUnits = [.hour, .minute, .second]
		formatter.zeroFormattingBehavior = .pad
		return formatter
	}()
		
}
