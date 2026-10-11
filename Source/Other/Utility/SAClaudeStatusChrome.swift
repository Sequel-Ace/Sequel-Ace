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

    static func from(defaults: UserDefaults) -> SAClaudeThemeColours {
        func colour(_ key: String, _ fallback: NSColor) -> NSColor { SAArchiving.color(from: defaults.data(forKey: key)) ?? fallback }
        let text = colour(SAEditorThemeLoader.textColourKey, .textColor)
        return SAClaudeThemeColours(background: colour(SAEditorThemeLoader.backgroundColourKey, .textBackgroundColor),
                                    text: text,
                                    keyword: colour(SAEditorThemeLoader.keywordColourKey, text),
                                    variable: colour(SAEditorThemeLoader.variableColourKey, text),
                                    caret: colour(SAEditorThemeLoader.caretColourKey, text),
                                    quote: colour(SAEditorThemeLoader.quoteColourKey, text),
                                    backtick: colour(SAEditorThemeLoader.backtickColourKey, text),
                                    selection: colour(SAEditorThemeLoader.selectionColourKey, .selectedTextBackgroundColor))
    }
}

enum SAClaudeStatusChrome {
    static let clay = NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)

    private static func mix(_ theme: SAClaudeThemeColours, _ ratio: CGFloat) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: theme.text, background: theme.background, ratio: ratio)
    }

    static func muted(theme: SAClaudeThemeColours) -> NSColor { mix(theme, 0.55) }
    static func typeText(theme: SAClaudeThemeColours) -> NSColor { mix(theme, 0.36) }
    static func hairline(theme: SAClaudeThemeColours) -> NSColor { mix(theme, 0.12) }
    static func errorText(theme: SAClaudeThemeColours) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: theme.text, background: clay, ratio: 0.35)
    }
    static func errorFill(theme: SAClaudeThemeColours) -> NSColor {
        SAClaudeEditorChrome.derivedColour(text: clay, background: theme.background, ratio: 0.06)
    }
    static func statusDot(isError: Bool, theme: SAClaudeThemeColours) -> NSColor { isError ? clay : theme.quote }
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
