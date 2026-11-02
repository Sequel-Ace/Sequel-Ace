//
//  SAEditorThemeLoader.swift
//  Sequel Ace
//
//  Reads Sequel Ace colour themes (.spTheme, and TextMate .tmTheme) into the
//  query editor's 11 colour settings. Ported unchanged from
//  -[SPEditorPreferencePane _loadColorSchemeFromFile:] so the appearance
//  switcher can use it outside the preference pane. Pure Foundation/AppKit,
//  shared with the Unit Tests target.
//

import AppKit

@objc final class SAEditorThemeLoader: NSObject {

    // Keep in sync with SPCustomQueryEditor*Color and SPCustomQueryEditorThemeName in SPConstants.m.
    @objc static let backgroundColourKey = "CustomQueryEditorBackgroundColor"
    @objc static let textColourKey = "CustomQueryEditorTextColor"
    static let caretColourKey = "CustomQueryEditorCaretColor"
    static let highlightColourKey = "CustomQueryEditorHighlightQueryColor"
    static let selectionColourKey = "CustomQueryEditorSelectionColor"
    static let commentColourKey = "CustomQueryEditorCommentColor"
    static let quoteColourKey = "CustomQueryEditorQuoteColor"
    static let keywordColourKey = "CustomQueryEditorSQLKeywordColor"
    static let backtickColourKey = "CustomQueryEditorBacktickColor"
    static let numericColourKey = "CustomQueryEditorNumericColor"
    static let variableColourKey = "CustomQueryEditorVariableColor"
    @objc static let themeNameKey = "CustomQueryEditorThemeName"
    /// The built-in scheme's name (SPDefaultColorSchemeName in SPEditorPreferencePane.m); not a file.
    @objc static let defaultSchemeName = "Default"

    /// settings[0].settings keys → colour settings.
    static let mainPairs: [String: String] = [
        "background": backgroundColourKey,
        "caret": caretColourKey,
        "foreground": textColourKey,
        "lineHighlight": highlightColourKey,
        "selection": selectionColourKey,
    ]

    /// Scope names (settings[n].name) → colour settings, read from settings[n].settings.foreground.
    static let scopePairs: [String: String] = [
        "Comment": commentColourKey,
        "String": quoteColourKey,
        "Keyword": keywordColourKey,
        "User-defined constant": backtickColourKey,
        "Number": numericColourKey,
        "Variable": variableColourKey,
    ]

    /// The 11 editor colour settings.
    static var colourKeys: [String] { Array(mainPairs.values) + Array(scopePairs.values) }

    /// Port of +[NSColor colorWithRGBHexString:] (SPColorAdditions.m): an optional
    /// leading '#', then the leading run of hex digits; 8 digits = RGBA, 6 = RGB,
    /// 3 = short RGB; calibrated RGB. Anything else is nil.
    static func colour(fromHex string: String) -> NSColor? {
        var body = Substring(string)
        if body.hasPrefix("#") { body = body.dropFirst() }
        // The old NSScanner skipped leading whitespace/newlines, after the '#' check on the raw string.
        body = body.drop(while: { $0.isWhitespace || $0.isNewline })
        let hexDigits = "0123456789abcdefABCDEF"
        let code = String(body.prefix { hexDigits.contains($0) })
        guard [3, 6, 8].contains(code.count), let value = UInt32(code, radix: 16) else { return nil }
        // The old parser divided in 32-bit float (`/ 255.f`) and widened; keep that so archived data is byte-identical.
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

    /// The colours a theme property list defines, by setting key. Same rules as
    /// the old parser: settings[0].settings holds the five main colours; each
    /// later entry maps by "name" to its settings.foreground; non-dictionary
    /// entries, unknown names and unparsable hex are skipped; a later duplicate wins.
    static func colours(fromThemePlist plist: Any) -> [String: NSColor] {
        guard let root = plist as? [String: Any],
              let elements = root["settings"] as? [Any], !elements.isEmpty else { return [:] }
        var result: [String: NSColor] = [:]
        for (index, element) in elements.enumerated() {
            guard let entry = element as? [String: Any] else { continue }
            if index == 0 {
                guard let main = entry["settings"] as? [String: Any] else { continue }
                for (themeKey, settingKey) in mainPairs {
                    if let hex = main[themeKey] as? String, let colour = colour(fromHex: hex) {
                        result[settingKey] = colour
                    }
                }
            } else if let name = entry["name"] as? String,
                      let scope = entry["settings"] as? [String: Any],
                      let settingKey = scopePairs[name],
                      let hex = scope["foreground"] as? String,
                      let colour = colour(fromHex: hex) {
                result[settingKey] = colour
            }
        }
        return result
    }

    /// Writes a parsed theme's colours into `defaults`; returns how many were written.
    @objc(writeColoursFromThemePlist:intoDefaults:)
    static func writeColours(fromThemePlist plist: Any, into defaults: UserDefaults) -> Int {
        var written = 0
        for (key, colour) in colours(fromThemePlist: plist) {
            if let data = SAArchiving.archivedData(forColor: colour) {
                defaults.set(data, forKey: key)
                written += 1
            }
        }
        return written
    }

    /// Loads a theme file into `defaults`.
    /// - Returns: -1 when the file can't be read as a property list, 0 when it
    ///   holds no usable colours (nothing written), otherwise the number written.
    @discardableResult
    @objc(loadThemeAtPath:intoDefaults:)
    static func loadTheme(atPath path: String, into defaults: UserDefaults) -> Int {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .uncached),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return -1
        }
        return writeColours(fromThemePlist: plist, into: defaults)
    }

    /// Resets the 11 colours to their registered defaults (the "Default" scheme),
    /// as -[SPEditorPreferencePane setDefaultColors:] does.
    @objc(loadDefaultColoursIntoDefaults:)
    static func loadDefaultColours(into defaults: UserDefaults) {
        let registered = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        for key in colourKeys {
            if let value = registered[key] { defaults.set(value, forKey: key) }
        }
    }
}
