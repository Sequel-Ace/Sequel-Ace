//
//  SAWindowTitlebarTint.swift
//  Sequel Ace
//
//  How the window chrome shows a connection's favourite colour.
//  Split out of SPWindowController so it can be compiled into the Unit
//  Tests target: AppKit only, no project ObjC types, so the test target
//  needs no bridging header (same pattern as SAWindowTitleBuilder).
//

import AppKit

/// How the document window's chrome shows a connection's favourite colour,
/// for the "Show the connection colour as" choice.
///
/// No mode fills the title bar: it is always the Claude bar - a transparent
/// title bar over `SAClaudeStyle.toolbarBackground`. The colour shows as one of:
/// - Underline: a 2pt line at the very bottom of the window chrome, in place
///   of the hairline there - drawn by the tab bar when it shows, otherwise by
///   a 2pt overlay right under the toolbar.
/// - Name pill: a pill with the connection's name in the window title (drawn
///   elsewhere); no line, the hairline stays.
/// - Tab underline: each tab chip is underlined in its connection's colour.
///   With one tab the tab bar is hidden, so the window falls back to the
///   Underline line until a second tab appears.
///
/// A window without a colour looks exactly like Off, whatever the choice, so
/// losing the colour (disconnect, a favourite without one) leaves nothing
/// stale behind.
struct SAWindowTitlebarTint {

    /// Which chips of the tab bar draw a line along their bottom.
    enum TabLines: Equatable {
        /// Only the selected chip, in the accent (Off, Underline, Name pill).
        case accent
        /// Every chip with a colour, in that colour; the selected chip in the
        /// accent when it has none (Tab underline).
        case connection
    }

    /// The line along one chip's bottom.
    enum ChipLine: Equatable {
        case none
        case accent
        case colour(NSColor)
    }

    /// Colour for `NSWindow.backgroundColor`: always the Claude bar colour.
    let backgroundColor: NSColor

    /// Whether the title bar stops drawing its own background, letting
    /// `backgroundColor` show through the title bar, toolbar and tab bar.
    let titlebarAppearsTransparent: Bool

    /// The hairline below the title bar. Dropped while the colour line is
    /// drawn, which takes its place.
    let separatorStyle: NSTitlebarSeparatorStyle

    /// The 2pt line along the bottom of the window chrome, `nil` for none. The
    /// caller's colour, unresolved, so an asset colour with a light/dark pair
    /// keeps following the effective appearance.
    let bottomLine: NSColor?

    /// Whether `bottomLine` is drawn by the tab bar (it is the bottom of the
    /// chrome while it shows) rather than by the overlay under the toolbar.
    let bottomLineInTabBar: Bool

    /// Whether the window title shows the connection's name pill.
    let showsNamePill: Bool

    /// Which tab chips draw a line.
    let tabLines: TabLines

    /// Derive the chrome.
    ///
    /// - Parameters:
    ///   - style: the user's "Show the connection colour as" choice.
    ///   - favoriteColor: the connection's favourite colour, or `nil` when it
    ///     has none or the document is not connected.
    ///   - tabBarVisible: whether the window's tab bar shows (two tabs or more).
    init(style: SAConnectionColourStyle, favoriteColor: NSColor?, tabBarVisible: Bool) {
        backgroundColor = SAClaudeStyle.toolbarBackground
        titlebarAppearsTransparent = true
        tabLines = Self.tabLines(for: style)

        let drawsLine = style == .underline || (style == .tabUnderline && !tabBarVisible)
        if drawsLine, let favoriteColor = favoriteColor {
            bottomLine = favoriteColor
            bottomLineInTabBar = tabBarVisible
            separatorStyle = .none
            showsNamePill = false
        } else {
            bottomLine = nil
            bottomLineInTabBar = false
            separatorStyle = .line
            showsNamePill = style == .namePill && favoriteColor != nil
        }
    }

    /// Tab underline lines the chips in their connection colours; every other
    /// choice keeps the selected chip's accent line.
    static func tabLines(for style: SAConnectionColourStyle) -> TabLines {
        style == .tabUnderline ? .connection : .accent
    }

    /// The line of one chip, given its connection colour (`nil` for none).
    static func chipLine(isSelected: Bool, colour: NSColor?, tabLines: TabLines) -> ChipLine {
        switch tabLines {
        case .accent:
            return isSelected ? .accent : .none
        case .connection:
            if let colour = colour { return .colour(colour) }
            return isSelected ? .accent : .none
        }
    }
}

/// How a saved connection's colour marks its window ("Show the connection
/// colour as" in Settings). Replaces the old on/off "Colour the window with
/// the connection colour" switch.
enum SAConnectionColourStyle: Int, CaseIterable {
    case off = 0
    case underline
    case namePill
    case tabUnderline

    /// Where the choice is stored. Not registered in PreferenceDefaults.plist:
    /// "no value yet" is what tells the migration to run.
    static let defaultsKey = "ClaudeConnectionColourStyle"

    /// The old switch (`SPDisplayConnectionColorInTitlebar`). Never rewritten,
    /// so older builds keep reading it.
    static let legacyKey = "DisplayConnectionColorInTitlebar"

    /// A stored number picks its case (an unknown one is `.off`), anything else
    /// stored is `.off`, and no stored value follows the old switch: on is
    /// `.underline`, off is `.off`.
    static func resolve(stored: Any?, legacyEnabled: Bool) -> SAConnectionColourStyle {
        guard let stored = stored else {
            return legacyEnabled ? .underline : .off
        }
        guard let number = stored as? NSNumber else {
            return .off
        }
        return SAConnectionColourStyle(rawValue: number.intValue) ?? .off
    }

    /// The style in effect. Never writes, so a window is right even before the
    /// migration has run.
    static func current(_ defaults: UserDefaults) -> SAConnectionColourStyle {
        resolve(stored: defaults.object(forKey: defaultsKey),
                legacyEnabled: defaults.bool(forKey: legacyKey))
    }

    /// Stores `current(defaults)` when nothing is stored yet. The legacy key is
    /// left untouched.
    static func migrateIfNeeded(_ defaults: UserDefaults) {
        guard defaults.object(forKey: defaultsKey) == nil else {
            return
        }
        defaults.set(current(defaults).rawValue, forKey: defaultsKey)
    }
}

/// Objective-C entry point for the one-time migration at launch.
@objc(SAConnectionColourStyleMigration)
final class SAConnectionColourStyleMigration: NSObject {
    @objc static func migrateStandardDefaults() {
        SAConnectionColourStyle.migrateIfNeeded(.standard)
    }
}
