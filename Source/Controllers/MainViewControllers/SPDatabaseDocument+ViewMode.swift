//
//  SPDatabaseDocument+ViewMode.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  Provides a Swift-native view mode enum and toolbar item configuration
//  that can be used by both ObjC and future SwiftUI code.
//

import AppKit

/// Represents the six main content views in the database document.
/// This replaces the scattered C enum SPViewMode and the repetitive
/// toolbar item configuration with a single data-driven type.
@objc enum SAViewMode: Int, CaseIterable {
    case structure = 0
    case content = 1
    case query = 2
    case status = 3
    case relations = 4
    case triggers = 5

    /// The tab view index for this mode.
    var tabIndex: Int { rawValue }

    /// The toolbar item identifier for this mode.
    var toolbarIdentifier: NSToolbarItem.Identifier {
        switch self {
        case .structure:  return NSToolbarItem.Identifier(SPMainToolbarTableStructure)
        case .content:    return NSToolbarItem.Identifier(SPMainToolbarTableContent)
        case .query:      return NSToolbarItem.Identifier(SPMainToolbarCustomQuery)
        case .status:     return NSToolbarItem.Identifier(SPMainToolbarTableInfo)
        case .relations:  return NSToolbarItem.Identifier(SPMainToolbarTableRelations)
        case .triggers:   return NSToolbarItem.Identifier(SPMainToolbarTableTriggers)
        }
    }

    /// The legacy SPViewMode preferences value.
    var preferencesValue: Int {
        switch self {
        case .structure:  return 1 // SPStructureViewMode
        case .content:    return 2 // SPContentViewMode
        case .query:      return 5 // SPQueryEditorViewMode
        case .status:     return 4 // SPTableInfoViewMode
        case .relations:  return 3 // SPRelationsViewMode
        case .triggers:   return 6 // SPTriggersViewMode
        }
    }

    /// Creates from a legacy SPViewMode preferences integer value.
    static func fromPreferences(_ value: Int) -> SAViewMode {
        switch value {
        case 1: return .structure
        case 2: return .content
        case 5: return .query
        case 4: return .status
        case 3: return .relations
        case 6: return .triggers
        default: return .structure
        }
    }

    /// Localized label for the toolbar item.
    var toolbarLabel: String {
        switch self {
        case .structure:  return NSLocalizedString("Structure", comment: "toolbar label")
        case .content:    return NSLocalizedString("Content", comment: "toolbar label")
        case .query:      return NSLocalizedString("Query", comment: "toolbar label")
        case .status:     return NSLocalizedString("Table Info", comment: "toolbar label")
        case .relations:  return NSLocalizedString("Relations", comment: "toolbar label")
        case .triggers:   return NSLocalizedString("Triggers", comment: "toolbar label")
        }
    }

    /// Localized tooltip for the toolbar item.
    var toolbarTooltip: String {
        switch self {
        case .structure:  return NSLocalizedString("Switch to the Table Structure tab", comment: "toolbar tooltip")
        case .content:    return NSLocalizedString("Switch to the Table Content tab", comment: "toolbar tooltip")
        case .query:      return NSLocalizedString("Switch to the Run Query tab", comment: "toolbar tooltip")
        case .status:     return NSLocalizedString("Switch to the Table Info tab", comment: "toolbar tooltip")
        case .relations:  return NSLocalizedString("Switch to the Table Relations tab", comment: "toolbar tooltip")
        case .triggers:   return NSLocalizedString("Switch to the Table Triggers tab", comment: "toolbar tooltip")
        }
    }

    /// The image for this view mode's toolbar item.
    var toolbarImage: NSImage? {
        if #available(macOS 11.0, *) {
            let name: String
            switch self {
            case .structure:  name = "scale.3d"
            case .content:    name = "text.justify"
            case .query:      name = "terminal"
            case .status:     name = "info.circle"
            case .relations:  name = "arrow.2.squarepath"
            case .triggers:   name = "bolt.circle"
            }
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        } else {
            let name: String
            switch self {
            case .structure:  name = "toolbar-switch-to-structure"
            case .content:    name = "toolbar-switch-to-browse"
            case .query:      name = "toolbar-switch-to-sql"
            case .status:     name = NSImage.infoName
            case .relations:  name = "toolbar-switch-to-table-relations"
            case .triggers:   name = "toolbar-switch-to-table-triggers"
            }
            return NSImage(named: name)
        }
    }

    /// The ObjC selector name to call when this toolbar item is clicked.
    var actionSelectorName: String {
        switch self {
        case .structure:  return "viewStructure"
        case .content:    return "viewContent"
        case .query:      return "viewQuery"
        case .status:     return "viewStatus"
        case .relations:  return "viewRelations"
        case .triggers:   return "viewTriggers"
        }
    }

    /// Creates a configured NSToolbarItem for this view mode.
    func makeToolbarItem(target: AnyObject) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: toolbarIdentifier)
        item.label = toolbarLabel
        item.paletteLabel = toolbarLabel
        item.toolTip = toolbarTooltip
        item.image = toolbarImage
        item.target = target
        item.action = NSSelectorFromString(actionSelectorName)
        return item
    }
}

// MARK: - ObjC Helper

/// Helper class for accessing SAViewMode from ObjC code.
@objc class SAViewModeHelper: NSObject {

    /// Returns the toolbar item identifier string for the given SPViewMode preferences value.
    @objc static func toolbarIdentifier(forPreferencesValue value: Int) -> String {
        return SAViewMode.fromPreferences(value).toolbarIdentifier.rawValue
    }

    /// Creates a toolbar item for the given view mode, fully configured.
    @objc static func makeToolbarItem(for mode: SAViewMode, target: AnyObject) -> NSToolbarItem {
        return mode.makeToolbarItem(target: target)
    }

    /// Returns all view mode toolbar identifiers as an array of strings.
    @objc static var allToolbarIdentifiers: [String] {
        SAViewMode.allCases.map { $0.toolbarIdentifier.rawValue }
    }
}
