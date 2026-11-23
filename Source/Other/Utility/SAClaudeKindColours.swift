//
//  SAClaudeKindColours.swift
//  Sequel Ace
//
//  The vivid palette by kind: the colour chip behind a tables-list icon (by object type), a Settings pane's icon,
//  and a Process List status group. A chip is the colour's tint with its glyph in the colour's ink. Pure, shared
//  with the Unit Tests target.
//

import AppKit

enum SAClaudeKindColours {

    /// The tables-list chips (tables-list icon canvas) and the Settings sidebar chips are 20pt squares.
    static let sidebarChipSize: CGFloat = 20
    static let settingsChipSize: CGFloat = 20
    static let chipRadius: CGFloat = 6

    /// The colour of a tables-list row's chip.
    ///
    /// - Parameter type: An `SPTableType` value (SPConstants.h): -1 none, 0 table, 1 view, 2 procedure, 3 function,
    ///   4 event, 5 table in a new database.
    /// - Returns: The colour, or nil for a header row (-1) or an unknown type.
    static func colour(forTableType type: Int) -> SAVividColour? {
        switch type {
        case 0, 5: return .sky
        case 1: return .violet
        case 2: return .amber
        case 3: return .emerald
        case 4: return .orange
        default: return nil
        }
    }

    /// The colour of a Settings pane's sidebar chip; every pane has its own.
    static func colour(for pane: SAClaudeSettingsPaneID) -> SAVividColour {
        switch pane {
        case .appearance: return .pink
        case .startup: return .sky
        case .tablesData: return .emerald
        case .queryEditor: return .violet
        case .safety: return .rose
        case .queryConsole: return .teal
        case .sshSecurity: return .amber
        case .mcp: return .blue
        case .updatesPrivacy: return .slate
        }
    }

    /// The colour of a Process List status group (its chip, row stripe and detail tone); alerts keep their own colours.
    static func colour(for group: SAClaudeProcessGroup) -> SAVividColour {
        switch group {
        case .needsAttention: return .rose
        case .running: return .amber
        case .idle: return .slate
        }
    }
}
