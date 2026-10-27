//
//  SADesignEditorChrome.swift
//  Sequel Ace
//
//  Pure values for the design system's editor and menu chrome: the shortcut
//  hint shown next to a command. Shared with the Unit Tests target.
//

import AppKit

@objc final class SADesignEditorChrome: NSObject {

    // MARK: - Shortcut hint

    /// For single printable key equivalents; special keys such as "\r" are not mapped to symbols.
    static func shortcutString(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> String {
        guard !keyEquivalent.isEmpty else { return "" }
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + keyEquivalent.uppercased()
    }
}
