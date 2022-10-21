//
//  NSDictionaryExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 21.10.2022.
//  Copyright © 2022 Sequel-Ace. All rights reserved.
//

import Foundation

@objc extension NSDictionary {
    var tableContentHeaderAttributedString: NSAttributedString {
        guard let columnName: String = value(forKey: "name") as? String else {
            return NSAttributedString(string: "")
        }
        let font = UserDefaults.getFont()
        let attributedString = NSMutableAttributedString(string: columnName, attributes: [.font: font])
        if let columnType: String = value(forKey: "type") as? String {
            attributedString.append(NSAttributedString(string: " "))
            attributedString.append(NSAttributedString(string: columnType, attributes: [.font: NSFontManager.shared.convert(font, toSize: 8), .foregroundColor: NSColor.gray]))
        }
        return attributedString
    }
}
