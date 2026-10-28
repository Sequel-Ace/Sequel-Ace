//
//  SASidebarObjectGlyph.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// The SF Symbol shown next to each object in the tables list.
///
/// The images are templates without a symbol configuration: a cell view in a
/// source-list table sizes them from the row size style and AppKit tints them
/// (accent color, white on an emphasized selection, gray when inactive).
///
/// Types are passed as `SPTableType` raw values so this file stays free of
/// project Objective-C types (keep in sync with SPConstants.h):
/// None -1, Table 0, View 1, Proc 2, Func 3, Event 4.
@objc(SASidebarObjectGlyph) final class SASidebarObjectGlyph: NSObject {

    @objc static func symbolName(forTableTypeRawValue rawValue: Int) -> String? {
        switch rawValue {
        case 0: return "tablecells"
        case 1: return "eye"
        case 2: return "curlybraces"
        case 3: return "function"
        case 4: return "clock"
        default: return nil
        }
    }

    @objc static func image(forTableTypeRawValue rawValue: Int) -> NSImage? {
        guard let name = symbolName(forTableTypeRawValue: rawValue),
              let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityName(forTableTypeRawValue: rawValue)) else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    private static func accessibilityName(forTableTypeRawValue rawValue: Int) -> String? {
        switch rawValue {
        case 0: return NSLocalizedString("Table", comment: "Accessibility name of a table's icon in the tables list")
        case 1: return NSLocalizedString("View", comment: "Accessibility name of a view's icon in the tables list")
        case 2: return NSLocalizedString("Procedure", comment: "Accessibility name of a stored procedure's icon in the tables list")
        case 3: return NSLocalizedString("Function", comment: "Accessibility name of a stored function's icon in the tables list")
        case 4: return NSLocalizedString("Event", comment: "Accessibility name of an event's icon in the tables list")
        default: return nil
        }
    }
}
