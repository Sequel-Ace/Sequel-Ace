//
//  SACellFilterColumnIdentifier.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.05.23.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

@objcMembers public final class SACellFilterColumnIdentifier: NSObject {

    @objc(storageIndexFromIdentifier:)
    public static func storageIndex(from identifier: Any?) -> NSNumber? {
        guard let rawValue = rawValue(from: identifier),
              rawValue.isNotEmpty,
              rawValue.allSatisfy(\.isNumber),
              let index = Int(rawValue) else {
            return nil
        }

        return NSNumber(value: index)
    }

    private static func rawValue(from identifier: Any?) -> String? {
        switch identifier {
        case let identifier as NSUserInterfaceItemIdentifier:
            return identifier.rawValue
        case let identifier as String:
            return identifier
        case let identifier as NSNumber:
            return identifier.stringValue
        default:
            return identifier.map { String(describing: $0) }
        }
    }
}
