//
//  NumberFormatterExtention.swift
//  Sequel Ace
//
//  Created by James on 3/11/2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import Foundation

extension NumberFormatter {
	@objc public static var decimalStyleFormatter: NumberFormatter = {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		return formatter
	}

	@objc static func withFormat(_ format: String) -> NumberFormatter {
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.format = format
		return formatter
	}
}
