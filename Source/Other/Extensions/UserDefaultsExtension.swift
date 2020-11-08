//
//  UserDefaultsExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 01.11.2020.
//  Copyright © 2020 Sequel-Ace. All rights reserved.
//

import AppKit
import Foundation

extension UserDefaults {
	@objc static func saveFont(_ font: NSFont) {
		let defaults = UserDefaults.standard
		defaults.set(NSKeyedArchiver.archivedData(withRootObject: font.fontDescriptor), forKey: "fontSettings")
	}

	@objc static func getFont() -> NSFont {
		let defaults = UserDefaults.standard
		guard
			let fontPreferences = defaults.data(forKey: "fontSettings"),
			let fontDescriptor = NSKeyedUnarchiver.unarchiveObject(with: fontPreferences) as? NSFontDescriptor,
			let savedFont = NSFont(descriptor: fontDescriptor, size: 0)
		else {
			let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
			Self .saveFont(font)
			return font
		}
		return savedFont
	}
}
