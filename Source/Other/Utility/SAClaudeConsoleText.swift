//
//  SAClaudeConsoleText.swift
//  Sequel Ace
//
//  Cell text for the Query Console in the Claude look: General font with
//  tabular digits, muted meta columns, SQL colouring for queries, soft clay
//  for errors. Shared with the Unit Tests target.
//

import AppKit

enum SAClaudeConsoleColumn: Equatable {
    case time, connection, database, query

    /// Keep in sync with SPTableViewDateColumnID / SPTableViewConnectionColumnID /
    /// SPTableViewDatabaseColumnID in SPQueryController.m.
    init(identifier: String) {
        switch identifier {
        case "messageDate": self = .time
        case "messageConnection": self = .connection
        case "messageDatabase": self = .database
        default: self = .query
        }
    }
}

struct SAClaudeConsoleTextStyle {
    var font: NSFont
    var text, muted, error, keyword, string, backtick, number, comment: NSColor

    static func from(defaults: UserDefaults, font: NSFont) -> SAClaudeConsoleTextStyle {
        func colour(_ key: String, _ fallback: NSColor) -> NSColor { SAArchiving.color(from: defaults.data(forKey: key)) ?? fallback }
        let text = colour(SAEditorThemeLoader.textColourKey, .textColor)
        let background = colour(SAEditorThemeLoader.backgroundColourKey, .textBackgroundColor)
        let clay = NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)
        return SAClaudeConsoleTextStyle(font: SAClaudeGridChrome.valueFont(font),
                                        text: text,
                                        muted: SAClaudeEditorChrome.derivedColour(text: text, background: background, ratio: 0.55),
                                        error: SAClaudeEditorChrome.derivedColour(text: text, background: clay, ratio: 0.35),
                                        keyword: colour(SAEditorThemeLoader.keywordColourKey, text),
                                        string: colour(SAEditorThemeLoader.quoteColourKey, text),
                                        backtick: colour(SAEditorThemeLoader.backtickColourKey, text),
                                        number: colour(SAEditorThemeLoader.numericColourKey, text),
                                        comment: colour(SAEditorThemeLoader.commentColourKey, text))
    }
}

enum SAClaudeConsoleText {
    static func attributed(_ value: String, column: SAClaudeConsoleColumn, isError: Bool, style: SAClaudeConsoleTextStyle) -> NSAttributedString {
        let base: NSColor = isError ? style.error : (column == .query ? style.text : style.muted)
        // Tabular digits whatever font the style carries (valueFont is idempotent).
        let font = SAClaudeGridChrome.valueFont(style.font)
        let result = NSMutableAttributedString(string: value, attributes: [.font: font, .foregroundColor: base])
        guard column == .query, !isError else { return result }
        for token in SAClaudeSQLColouring.tokens(in: value) {
            let colour: NSColor
            switch token.kind {
            case .keyword: colour = style.keyword
            case .string: colour = style.string
            case .backtick: colour = style.backtick
            case .number: colour = style.number
            case .comment: colour = style.comment
            }
            result.addAttribute(.foregroundColor, value: colour, range: token.range)
        }
        return result
    }
}
