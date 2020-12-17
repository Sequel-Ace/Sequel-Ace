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
    
    @objc static func saveBookmarkData(_ bookmarkData: Data, key: String) {
        let defaults = UserDefaults.standard
        defaults.set(NSKeyedArchiver.archivedData(withRootObject: bookmarkData), forKey: key)
    }
    
    @objc static func getBookmarkData(key: String) -> Data {
        let defaults = UserDefaults.standard
        guard
            let bookmarkData = defaults.data(forKey: key),
            let unarchivedBookmarkData = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(bookmarkData) as? Data
            
        else {
            return Data()
        }
        return unarchivedBookmarkData
    }
    
    @objc static func saveBookmarks(_ bookmarks: [Dictionary<String, Data>]) {
        let defaults = UserDefaults.standard
        
        var bmCopy = bookmarks
        bmCopy.removeAll()
        for (_, bookmarkDict) in bookmarks.enumerated(){
            for (key, bookmarkData) in bookmarkDict {
                let encData = NSKeyedArchiver.archivedData(withRootObject: bookmarkData)
                let newDict = [key : encData]
                bmCopy.append(newDict)
            }
        }
        defaults.set(bmCopy, forKey: SPSecureBookmarks)
        
    }
    
//    @objc static func getBookmarks() -> NSArray {
//        let defaults = UserDefaults.standard
//
//        let bookmarks = defaults.object(forKey: SPSecureBookmarks) as! Array<Dictionary<String, Data>>
//
//        var bmCopy : [Dictionary<String, Data>] = []
//
//        for (_, bookmarkDict) in bookmarks.enumerated(){
//            for (key, bookmarkData) in bookmarkDict {
//                guard
//                    let unarchivedBookmarkData = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(bookmarkData) as? Data,
//                    let newDict = [key : unarchivedBookmarkData],
//                    bmCopy.append(newDict)
//                else {
//                    return Data()
//                }
//            }
//        }
//
//
////        var bmCopy = bookmarks
////        bmCopy.removeAll()
////        for (_, bookmarkDict) in bookmarks.enumerated(){
////
////            for (key, bookmarkData) in bookmarkDict {
////                let encData = NSKeyedArchiver.archivedData(withRootObject: bookmarkData)
////                let newDict = [key : encData]
////                bmCopy.append(newDict)
////            }
////        }
////        defaults.set(bmCopy, forKey: SPSecureBookmarks)
//
//    }
}
