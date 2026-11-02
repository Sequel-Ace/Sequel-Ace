//
//  SAClaudeStatusChrome.swift
//  Sequel Ace
//
//  Colour rules for the Query tab's status pane and bottom strip and for the
//  editor autocomplete popup in the Claude look. Shared with the Unit Tests target.
//

import AppKit

enum SAClaudeCompletionKind: Equatable {
    case table, view, database, field, function, procedure, keyword

    /// Keep in sync with the "image" names given to completion items in SPTextView.m.
    init?(imageName: String) {
        switch imageName {
        case "table-small-square": self = .table
        case "table-view-small-square": self = .view
        case "database-small": self = .database
        case "field-small-square": self = .field
        case "func-small": self = .function
        case "proc-small": self = .procedure
        case "dummy-small": self = .keyword
        default: return nil
        }
    }

    var glyph: SAClaudeGlyph {
        switch self {
        case .table: return .table
        case .view: return .view
        case .database: return .database
        case .field: return .field
        case .function: return .function
        case .procedure: return .procedure
        case .keyword: return .keyword
        }
    }
}

struct SAClaudeThemeColours: Equatable {
    var background, text, keyword, variable, caret, quote, backtick, selection: NSColor

    private static let keys = [SAEditorThemeLoader.textColourKey, SAEditorThemeLoader.backgroundColourKey,
                               SAEditorThemeLoader.keywordColourKey, SAEditorThemeLoader.variableColourKey,
                               SAEditorThemeLoader.caretColourKey, SAEditorThemeLoader.quoteColourKey,
                               SAEditorThemeLoader.backtickColourKey, SAEditorThemeLoader.selectionColourKey]
    private static let cacheLock = NSLock()
    /// The last decoded colours and the stored data they came from: unarchiving runs only when the data changed.
    /// The fallbacks are dynamic colours, so a cached value stays right in either appearance.
    private static var cache: (data: [Data?], colours: SAClaudeThemeColours)?

    /// The theme colours stored in `defaults`, decoded once per distinct theme data. Any thread.
    static func from(defaults: UserDefaults) -> SAClaudeThemeColours {
        let data = keys.map { defaults.data(forKey: $0) }
        cacheLock.lock()
        if let cache, cache.data == data {
            cacheLock.unlock()
            return cache.colours
        }
        cacheLock.unlock()
        let colours = decode(data)
        cacheLock.lock()
        cache = (data, colours)
        cacheLock.unlock()
        return colours
    }

    /// `data` in `keys` order.
    private static func decode(_ data: [Data?]) -> SAClaudeThemeColours {
        func colour(_ index: Int, _ fallback: NSColor) -> NSColor { SAArchiving.color(from: data[index]) ?? fallback }
        let text = colour(0, .textColor)
        return SAClaudeThemeColours(background: colour(1, .textBackgroundColor),
                                    text: text,
                                    keyword: colour(2, text),
                                    variable: colour(3, text),
                                    caret: colour(4, text),
                                    quote: colour(5, text),
                                    backtick: colour(6, text),
                                    selection: colour(7, .selectedTextBackgroundColor))
    }
}

enum SAClaudeStatusChrome {
    /// The accent colour (the user's choice, clay by default) for decorative uses.
    static var clay: NSColor { SAClaudeAccent.accent }
    /// Clay `#D97757`, fixed: error accents do not follow the accent colour.
    static let errorClay = NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)

    private static func mix(_ theme: SAClaudeThemeColours, _ ratio: CGFloat) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: theme.text, background: theme.background, ratio: ratio)
    }

    static func muted(theme: SAClaudeThemeColours) -> NSColor { mix(theme, 0.55) }
    static func typeText(theme: SAClaudeThemeColours) -> NSColor { mix(theme, 0.36) }
    static func hairline(theme: SAClaudeThemeColours) -> NSColor { mix(theme, 0.12) }
    static func errorText(theme: SAClaudeThemeColours) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: theme.text, background: errorClay, ratio: 0.35)
    }
    static func errorFill(theme: SAClaudeThemeColours) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: errorClay, background: theme.background, ratio: 0.06)
    }
    static func statusDot(isError: Bool, theme: SAClaudeThemeColours) -> NSColor { isError ? errorClay : theme.quote }
    static func messageText(isError: Bool, theme: SAClaudeThemeColours) -> NSColor { isError ? errorText(theme: theme) : muted(theme: theme) }

    static func popupSurface(theme: SAClaudeThemeColours) -> NSColor {
        SAClaudeGridChrome.isDark(theme.background) ? mix(theme, 0.035) : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    static func completionTint(_ kind: SAClaudeCompletionKind, theme: SAClaudeThemeColours) -> NSColor {
        switch kind {
        case .table: return theme.keyword
        case .view: return theme.variable
        case .database: return theme.caret
        case .function: return theme.quote
        case .procedure: return theme.backtick
        case .field, .keyword: return muted(theme: theme)
        }
    }
}
