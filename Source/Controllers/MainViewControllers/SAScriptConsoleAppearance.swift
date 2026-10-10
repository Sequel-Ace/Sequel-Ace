//
//  SAScriptConsoleAppearance.swift
//  Sequel Ace
//
//  Font and colours of the "Run All as Script" console. By default the
//  console follows the Query Editor's font, text colour and background
//  colour; Preferences → Query Editor → Script Output can switch it to its
//  own values. Pure Foundation/AppKit (plus SAArchiving) so it is shared with
//  the Unit Tests target.
//

import AppKit
import Foundation

struct SAScriptConsoleAppearance: Equatable {

    let font: NSFont
    let textColor: NSColor
    let backgroundColor: NSColor

    // MARK: - Defaults keys

    static let useCustomKey = "ScriptConsoleUseCustomAppearance"
    static let customFontKey = "ScriptConsoleFont"
    static let customTextColorKey = "ScriptConsoleTextColor"
    static let customBackgroundColorKey = "ScriptConsoleBackgroundColor"

    // Query Editor keys — keep in sync with SPCustomQueryEditorFont,
    // SPCustomQueryEditorTextColor and SPCustomQueryEditorBackgroundColor in
    // SPConstants.m (inlined because this file is also built into Unit Tests).
    static let editorFontKey = "CustomQueryEditorFont"
    static let editorTextColorKey = "CustomQueryEditorTextColor"
    static let editorBackgroundColorKey = "CustomQueryEditorBackgroundColor"

    // MARK: - Fallbacks

    static var fallback: SAScriptConsoleAppearance {
        SAScriptConsoleAppearance(font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                                  textColor: .textColor,
                                  backgroundColor: .textBackgroundColor)
    }

    // MARK: - Resolving

    /// The console's current look: the custom values when the override is on
    /// (each missing or unreadable one falling back to the editor's), otherwise
    /// the editor's values; anything unreadable falls back to `fallback`.
    static func resolve(from defaults: UserDefaults) -> SAScriptConsoleAppearance {
        let editor = editorAppearance(from: defaults)
        guard defaults.bool(forKey: useCustomKey) else { return editor }
        return SAScriptConsoleAppearance(
            font: SAArchiving.font(from: defaults.data(forKey: customFontKey)) ?? editor.font,
            textColor: SAArchiving.color(from: defaults.data(forKey: customTextColorKey)) ?? editor.textColor,
            backgroundColor: SAArchiving.color(from: defaults.data(forKey: customBackgroundColorKey)) ?? editor.backgroundColor
        )
    }

    /// The Query Editor's current values, with per-value fallbacks.
    static func editorAppearance(from defaults: UserDefaults) -> SAScriptConsoleAppearance {
        let base = fallback
        return SAScriptConsoleAppearance(
            font: SAArchiving.font(from: defaults.data(forKey: editorFontKey)) ?? base.font,
            textColor: SAArchiving.color(from: defaults.data(forKey: editorTextColorKey)) ?? base.textColor,
            backgroundColor: SAArchiving.color(from: defaults.data(forKey: editorBackgroundColorKey)) ?? base.backgroundColor
        )
    }

    // MARK: - Writing

    /// Turns the override on or off. Turning it on seeds any absent custom
    /// value from the editor's current one, so the console does not visibly
    /// change; existing custom values are kept.
    static func setUseCustom(_ on: Bool, in defaults: UserDefaults) {
        if on {
            let editor = editorAppearance(from: defaults)
            if defaults.object(forKey: customFontKey) == nil {
                defaults.set(SAArchiving.archivedData(forFont: editor.font), forKey: customFontKey)
            }
            if defaults.object(forKey: customTextColorKey) == nil {
                defaults.set(SAArchiving.archivedData(forColor: editor.textColor), forKey: customTextColorKey)
            }
            if defaults.object(forKey: customBackgroundColorKey) == nil {
                defaults.set(SAArchiving.archivedData(forColor: editor.backgroundColor), forKey: customBackgroundColorKey)
            }
        }
        defaults.set(on, forKey: useCustomKey)
    }

    /// Overwrites the custom values with the editor's current ones ("Reset to Editor").
    static func copyEditorValuesToCustom(in defaults: UserDefaults) {
        let editor = editorAppearance(from: defaults)
        defaults.set(SAArchiving.archivedData(forFont: editor.font), forKey: customFontKey)
        defaults.set(SAArchiving.archivedData(forColor: editor.textColor), forKey: customTextColorKey)
        defaults.set(SAArchiving.archivedData(forColor: editor.backgroundColor), forKey: customBackgroundColorKey)
    }
}

/// ObjC-facing font-panel hooks for the script console's custom font, used by
/// SPEditorPreferencePane (opening the panel) and SPPreferenceController
/// (`-changeDefaultFont:` with SPPrefFontChangeTargetScriptConsole).
@objc final class SAScriptConsoleFontPanel: NSObject {

    /// The font the panel should start from: the console's current font.
    @objc static func currentFont() -> NSFont {
        SAScriptConsoleAppearance.resolve(from: .standard).font
    }

    /// Converts the console's current font with the shared font panel (`-panelConvertFont:`) and
    /// stores it as the custom script console font.
    @objc static func applyFontPanelChange() {
        applyFontChange(in: .standard) { NSFontPanel.shared.convert($0) }
    }

    /// No-op while the override is off: a font panel left open after the
    /// checkbox was unticked must not overwrite the stored custom font with a
    /// converted editor font.
    static func applyFontChange(in defaults: UserDefaults, convert: (NSFont) -> NSFont) {
        guard defaults.bool(forKey: SAScriptConsoleAppearance.useCustomKey) else { return }
        let font = convert(SAScriptConsoleAppearance.resolve(from: defaults).font)
        defaults.set(SAArchiving.archivedData(forFont: font), forKey: SAScriptConsoleAppearance.customFontKey)
    }
}
