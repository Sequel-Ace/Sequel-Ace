//
//  SAEditorThemeLoader.swift
//  Sequel Ace
//
//  Reads Sequel Ace color themes (.spTheme, and TextMate .tmTheme) into the
//  query editor's 11 color settings, with the same parsing rules and the
//  same stored bytes as the Query Editor preference pane's theme loading,
//  so it can load a theme outside that pane. Pure Foundation/AppKit, shared
//  with the Unit Tests target.
//

import AppKit

@objc final class SAEditorThemeLoader: NSObject {

    // Keep in sync with SPCustomQueryEditor*Color and SPCustomQueryEditorThemeName in SPConstants.m.
    static let backgroundColorKey = "CustomQueryEditorBackgroundColor"
    static let textColorKey = "CustomQueryEditorTextColor"
    static let caretColorKey = "CustomQueryEditorCaretColor"
    static let highlightColorKey = "CustomQueryEditorHighlightQueryColor"
    static let selectionColorKey = "CustomQueryEditorSelectionColor"
    static let commentColorKey = "CustomQueryEditorCommentColor"
    static let quoteColorKey = "CustomQueryEditorQuoteColor"
    static let keywordColorKey = "CustomQueryEditorSQLKeywordColor"
    static let backtickColorKey = "CustomQueryEditorBacktickColor"
    static let numericColorKey = "CustomQueryEditorNumericColor"
    static let variableColorKey = "CustomQueryEditorVariableColor"
    static let themeNameKey = "CustomQueryEditorThemeName"
    /// The built-in scheme's name (SPDefaultColorSchemeName in SPEditorPreferencePane.m); not a file.
    static let defaultSchemeName = "Default"

    /// settings[0].settings keys → color settings.
    static let mainPairs: [String: String] = [
        "background": backgroundColorKey,
        "caret": caretColorKey,
        "foreground": textColorKey,
        "lineHighlight": highlightColorKey,
        "selection": selectionColorKey,
    ]

    /// Scope names (settings[n].name) → color settings, read from settings[n].settings.foreground.
    static let scopePairs: [String: String] = [
        "Comment": commentColorKey,
        "String": quoteColorKey,
        "Keyword": keywordColorKey,
        "User-defined constant": backtickColorKey,
        "Number": numericColorKey,
        "Variable": variableColorKey,
    ]

    /// The 11 editor color settings.
    static var colorKeys: [String] { Array(mainPairs.values) + Array(scopePairs.values) }

    /// Parses a hex color exactly as +[NSColor colorWithRGBHexString:] (SPColorAdditions.m) does: an optional
    /// leading '#', then the leading run of hex digits; 8 digits = RGBA, 6 = RGB,
    /// 3 = short RGB; calibrated RGB. Anything else is nil.
    static func color(fromHex string: String) -> NSColor? {
        var body = Substring(string)
        if body.hasPrefix("#") { body = body.dropFirst() }
        // Leading whitespace/newlines are skipped after the '#' check on the raw string, as NSScanner does there.
        body = body.drop(while: { $0.isWhitespace || $0.isNewline })
        let hexDigits = "0123456789abcdefABCDEF"
        let code = String(body.prefix { hexDigits.contains($0) })
        guard [3, 6, 8].contains(code.count), let value = UInt32(code, radix: 16) else { return nil }
        // Divide in 32-bit float (`/ 255.f` there) and widen, so the archived data is byte-identical to the pane's.
        func byte(_ v: UInt32) -> CGFloat { CGFloat(Float(v & 0xFF) / 255) }
        switch code.count {
        case 8:
            return NSColor(calibratedRed: byte(value >> 24), green: byte(value >> 16), blue: byte(value >> 8), alpha: byte(value))
        case 6:
            return NSColor(calibratedRed: byte(value >> 16), green: byte(value >> 8), blue: byte(value), alpha: 1)
        default:
            let r = (value >> 8) & 0xF, g = (value >> 4) & 0xF, b = value & 0xF
            return NSColor(calibratedRed: CGFloat(Float(r << 4 | r) / 255), green: CGFloat(Float(g << 4 | g) / 255),
                           blue: CGFloat(Float(b << 4 | b) / 255), alpha: 1)
        }
    }

    /// The colors a theme property list defines, by setting key. Same rules as
    /// the preference pane: settings[0].settings holds the five main colors; each
    /// later entry maps by "name" to its settings.foreground; non-dictionary
    /// entries, unknown names and unparsable hex are skipped; a later duplicate wins.
    static func colors(fromThemePlist plist: Any) -> [String: NSColor] {
        guard let root = plist as? [String: Any],
              let elements = root["settings"] as? [Any], !elements.isEmpty else { return [:] }
        var result: [String: NSColor] = [:]
        for (index, element) in elements.enumerated() {
            guard let entry = element as? [String: Any] else { continue }
            if index == 0 {
                guard let main = entry["settings"] as? [String: Any] else { continue }
                for (themeKey, settingKey) in mainPairs {
                    if let hex = main[themeKey] as? String, let color = color(fromHex: hex) {
                        result[settingKey] = color
                    }
                }
            } else if let name = entry["name"] as? String,
                      let scope = entry["settings"] as? [String: Any],
                      let settingKey = scopePairs[name],
                      let hex = scope["foreground"] as? String,
                      let color = color(fromHex: hex) {
                result[settingKey] = color
            }
        }
        return result
    }

    /// Writes a parsed theme's colors into `defaults`; returns how many were written.
    @objc(writeColorsFromThemePlist:intoDefaults:)
    static func writeColors(fromThemePlist plist: Any, into defaults: UserDefaults) -> Int {
        var written = 0
        for (key, color) in colors(fromThemePlist: plist) {
            if let data = SAArchiving.archivedData(forColor: color) {
                defaults.set(data, forKey: key)
                written += 1
            }
        }
        return written
    }

    /// Loads a theme file into `defaults`.
    /// - Returns: -1 when the file can't be read as a property list, 0 when it
    ///   holds no usable colors (nothing written), otherwise the number written.
    @discardableResult
    static func loadTheme(atPath path: String, into defaults: UserDefaults) -> Int {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .uncached),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return -1
        }
        return writeColors(fromThemePlist: plist, into: defaults)
    }

    /// Resets the 11 colors to their registered defaults (the "Default" scheme),
    /// as -[SPEditorPreferencePane setDefaultColors:] does.
    static func loadDefaultColors(into defaults: UserDefaults) {
        let registered = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        for key in colorKeys {
            if let value = registered[key] { defaults.set(value, forKey: key) }
        }
    }
}
