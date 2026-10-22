//
//  SAWindowTitlebarTint.swift
//  Sequel Ace
//
//  The window chrome appearance for a connection's favourite colour.
//  Split out of SPWindowController so it can be compiled into the Unit
//  Tests target: AppKit only, no project ObjC types, so the test target
//  needs no bridging header (same pattern as SAWindowTitleBuilder).
//

import AppKit

/// How the document window's chrome should look for a given connection colour.
///
/// Applying a favourite colour means painting the whole window top - title
/// bar, unified toolbar and the native tab bar - rather than only the 5pt line
/// on the tab accessory, which is hidden along with the tab bar (#1856).
/// `titlebarAppearsTransparent` is what makes that work: it stops the title bar
/// drawing its own background, so the window background shows through the
/// entire strip.
///
/// The `nil` case is the Claude bar: a transparent title bar over
/// `SAClaudeStyle.toolbarBackground` with a hairline separator, no longer the
/// stock title bar. All three properties are set explicitly so clearing a
/// favourite colour restores them together.
struct SAWindowTitlebarTint {

    /// Colour for `NSWindow.backgroundColor`. Kept as the caller's `NSColor`
    /// rather than a resolved value, so an asset colour with a light/dark pair
    /// keeps following the effective appearance.
    let backgroundColor: NSColor

    /// Whether the title bar should stop drawing its own background, letting
    /// `backgroundColor` show through the title bar, toolbar and tab bar.
    let titlebarAppearsTransparent: Bool

    /// Whether the hairline below the title bar is drawn. A separator reads as
    /// a stray line across a coloured strip, so a tinted window drops it; the
    /// Claude bar keeps a hairline.
    let separatorStyle: NSTitlebarSeparatorStyle

    /// Derive the chrome for a connection's favourite colour.
    ///
    /// - Parameters:
    ///   - favoriteColor: the connection's favourite colour, or `nil` when it
    ///     has none or the document is not connected.
    ///   - isEnabled: the user's `DisplayConnectionColorInTitlebar` preference.
    ///     Off is the default, and always yields the Claude bar, however the
    ///     connection is coloured.
    init(favoriteColor: NSColor?, isEnabled: Bool) {
        if isEnabled, let favoriteColor = favoriteColor {
            backgroundColor = favoriteColor
            titlebarAppearsTransparent = true
            separatorStyle = .none
        } else {
            backgroundColor = SAClaudeStyle.toolbarBackground
            titlebarAppearsTransparent = true
            separatorStyle = .line
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
