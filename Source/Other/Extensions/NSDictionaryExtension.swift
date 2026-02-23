//
//  NSDictionaryExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 21.10.2022.
//  Copyright © 2022 Sequel-Ace. All rights reserved.
//

import Foundation

@objc extension NSDictionary {
    var tableContentColumnHeaderAttributedString: NSAttributedString {
        return tableContentColumnHeaderAttributedString(columnTypesVisible: true)
    }

    @objc(tableContentColumnHeaderAttributedStringWithColumnTypesVisible:)
    func tableContentColumnHeaderAttributedString(columnTypesVisible: Bool) -> NSAttributedString {
        guard let columnName: String = value(forKey: "name") as? String else {
            return NSAttributedString(string: "")
        }
        let columnType = value(forKey: "type") as? String
        let tableFont = UserDefaults.getFont()
        let headerFont = NSFontManager.shared.convert(tableFont, toSize: Swift.max(tableFont.pointSize * 0.75, 11.0))
        let headerString = NSString.tableContentColumnHeaderString(columnName: columnName, columnType: columnType, columnTypesVisible: columnTypesVisible)

        guard columnTypesVisible, let columnType, !columnType.isEmpty else {
            return NSAttributedString(string: headerString, attributes: [.font: headerFont])
        }

        let attributedString = NSMutableAttributedString(string: columnName, attributes: [.font: headerFont])
        attributedString.append(NSAttributedString(string: NSString.columnHeaderSplittingSpace as String))

        let smallerHeaderFont = NSFontManager.shared.convert(headerFont, toSize: headerFont.pointSize * 0.75)
        attributedString.append(NSAttributedString(string: columnType, attributes: [.font: smallerHeaderFont, .foregroundColor: NSColor.gray]))
        return attributedString
    }
}

extension SPProcessListController {
    @objc(_serializedProcessRow:includeProgress:)
    class func serializedProcessRow(_ process: NSDictionary, includeProgress: Bool) -> String {
        return SPProcessListRowSerializer.serializedProcessRow(process, includeProgress: includeProgress)
    }
}
