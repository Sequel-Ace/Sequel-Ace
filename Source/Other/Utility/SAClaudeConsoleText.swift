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

/// Equatable so the console can tell a syntax-colour-only theme change (or a font change) apart from no change.
struct SAClaudeConsoleTextStyle: Equatable {
    var font: NSFont
    var text, muted, error, keyword, string, backtick, number, comment: NSColor

    static func from(defaults: UserDefaults, font: NSFont) -> SAClaudeConsoleTextStyle {
        func colour(_ key: String, _ fallback: NSColor) -> NSColor { SAArchiving.color(from: defaults.data(forKey: key)) ?? fallback }
        let text = colour(SAEditorThemeLoader.textColourKey, .textColor)
        let background = colour(SAEditorThemeLoader.backgroundColourKey, .textBackgroundColor)
        let clay = SAClaudeStatusChrome.errorClay
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
    /// Marks an error message as the continuation of the failed query in the row above.
    static let errorPrefix = "↳ "

    /// An error row reads as part of the failed query above it: its Time, Connection and Database cells are
    /// empty and its message is prefixed with "↳ ", all in soft clay. Display only; the logged text is unchanged.
    static func attributed(_ value: String, column: SAClaudeConsoleColumn, isError: Bool, style: SAClaudeConsoleTextStyle) -> NSAttributedString {
        if isError {
            let text = column == .query ? errorPrefix + value : ""
            return NSAttributedString(string: text, attributes: [.font: style.font, .foregroundColor: style.error])
        }
        let base: NSColor = column == .query ? style.text : style.muted
        // The style's font already has tabular digits (SAClaudeConsoleTextStyle.from applies valueFont).
        let result = NSMutableAttributedString(string: value, attributes: [.font: style.font, .foregroundColor: base])
        guard column == .query else { return result }
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
