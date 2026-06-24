//
//  UserDefaultsExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 01.11.2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import AppKit
import Foundation

extension UserDefaults {
	@objc static func saveFont(_ font: NSFont) {
		let defaults = UserDefaults.standard
		defaults.set(SAArchiving.archivedData(forFont: font), forKey: "fontSettings")
	}

	@objc static func getFont() -> NSFont {
		let defaults = UserDefaults.standard
		guard let fontPreferences = defaults.data(forKey: "fontSettings") else {
			return saveAndReturnDefaultFont()
		}
		// Current format: a whole NSFont archived via SAArchiving.
		if let savedFont = SAArchiving.font(from: fontPreferences) {
			return savedFont
		}
		// Legacy format: an archived NSFontDescriptor. Read it with the secure
		// keyed API (which also reads non-secure keyed archives) so existing
		// preferences survive; the next saveFont() rewrites it as a whole font.
		if let fontDescriptor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFontDescriptor.self, from: fontPreferences),
		   let savedFont = NSFont(descriptor: fontDescriptor, size: 0) {
			return savedFont
		}
		return saveAndReturnDefaultFont()
	}

	private static func saveAndReturnDefaultFont() -> NSFont {
		let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
		Self.saveFont(font)
		return font
	}
  
  @objc static func getSystemFont() -> NSFont {
    return NSFont.systemFont(ofSize: NSFont.systemFontSize)
  }

    // needs to be objc for KVO
    @objc var SPSecureBookmarks: [Dictionary<String, Data>] {
        return array(forKey: SASecureBookmarks) as? [Dictionary<String, Data>] ?? []
    }

}
