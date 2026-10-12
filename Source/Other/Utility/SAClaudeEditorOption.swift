//
//  SAClaudeEditorOption.swift
//  Sequel Ace
//
//  The query editor's options (the ⋯ menu) as the Claude popover lists them:
//  sections, titles, the settings the switches show, and how to recognise each
//  menu item. Shared with the unit tests.
//

import Foundation

enum SAClaudeEditorOption: CaseIterable, Equatable {
    case previousHistory, nextHistory, historyReplacesContent, favoriteReplacesContent
    case shiftRight, shiftLeft, commentLine, commentQuery
    case completionList, completeDatabases, completeTables, completeFields
    case autoIndent, autoPair, autoUppercase, autoComplete, autoHelp, editorFont

    var title: String {
        switch self {
        case .previousHistory: return NSLocalizedString("ClaudeEditorOptionsPrevious", value: "Previous", comment: "Editor options popover: button that inserts the previous query from history")
        case .nextHistory: return NSLocalizedString("ClaudeEditorOptionsNext", value: "Next", comment: "Editor options popover: button that inserts the next query from history")
        case .historyReplacesContent: return NSLocalizedString("ClaudeEditorOptionsHistoryReplaces", value: "History replaces editor content", comment: "Editor options popover switch: choosing a history item replaces the editor text")
        case .favoriteReplacesContent: return NSLocalizedString("ClaudeEditorOptionsFavoriteReplaces", value: "Favorite replaces editor content", comment: "Editor options popover switch: choosing a favorite replaces the editor text")
        case .shiftRight: return NSLocalizedString("ClaudeEditorOptionsShiftRight", value: "Shift right", comment: "Editor options popover: indent the selection")
        case .shiftLeft: return NSLocalizedString("ClaudeEditorOptionsShiftLeft", value: "Shift left", comment: "Editor options popover: un-indent the selection")
        case .commentLine: return NSLocalizedString("ClaudeEditorOptionsCommentLine", value: "Comment line", comment: "Editor options popover: comment out the line or selection")
        case .commentQuery: return NSLocalizedString("ClaudeEditorOptionsCommentQuery", value: "Comment query", comment: "Editor options popover: comment out the current query (shown while Option is held)")
        case .completionList: return NSLocalizedString("ClaudeEditorOptionsShowList", value: "Show list", comment: "Editor options popover: open the completion list")
        case .completeDatabases: return NSLocalizedString("ClaudeEditorOptionsDatabases", value: "Databases", comment: "Editor options popover chip: complete from all database names")
        case .completeTables: return NSLocalizedString("ClaudeEditorOptionsTables", value: "Tables", comment: "Editor options popover chip: complete from all table and view names")
        case .completeFields: return NSLocalizedString("ClaudeEditorOptionsFields", value: "Fields", comment: "Editor options popover chip: complete from the current table's field names")
        case .autoIndent: return NSLocalizedString("ClaudeEditorOptionsIndent", value: "Indent new lines", comment: "Editor options popover switch")
        case .autoPair: return NSLocalizedString("ClaudeEditorOptionsAutoPair", value: "Auto-pair characters", comment: "Editor options popover switch")
        case .autoUppercase: return NSLocalizedString("ClaudeEditorOptionsUppercase", value: "Auto-uppercase keywords", comment: "Editor options popover switch")
        case .autoComplete: return NSLocalizedString("ClaudeEditorOptionsAutoComplete", value: "Auto-completion", comment: "Editor options popover switch")
        case .autoHelp: return NSLocalizedString("ClaudeEditorOptionsAutoHelp", value: "Update help while typing", comment: "Editor options popover switch")
        case .editorFont: return NSLocalizedString("ClaudeEditorOptionsEditorFont", value: "Editor font", comment: "Editor options popover row that opens the font panel")
        }
    }

    /// The setting a switch shows. Keep in sync with SPConstants.m.
    var defaultsKey: String? {
        switch self {
        case .historyReplacesContent: return "QueryHistoryReplacesContent"
        case .favoriteReplacesContent: return "QueryFavoriteReplacesContent"
        case .autoIndent: return "CustomQueryAutoIndent"
        case .autoPair: return "CustomQueryAutoPairCharacters"
        case .autoUppercase: return "CustomQueryAutoUppercaseKeywords"
        case .autoComplete: return "CustomQueryAutoComplete"
        case .autoHelp: return "CustomQueryUpdateAutoHelp"
        default: return nil
        }
    }

    var isSwitch: Bool { defaultsKey != nil }
    var closesPopover: Bool { !isSwitch }

    private static let tags: [Int: SAClaudeEditorOption] = [
        3: .previousHistory, 4: .nextHistory, 6: .shiftRight, 7: .shiftLeft, 11: .commentLine, 12: .commentQuery,
        8: .completionList, 8000: .completeDatabases, 8001: .completeTables, 8002: .completeFields, 9: .autoIndent, 10: .autoPair,
    ]

    static func option(tag: Int, boundDefaultsKey: String?, hasAction: Bool) -> SAClaudeEditorOption? {
        if let option = tags[tag] { return option }
        if let key = boundDefaultsKey { return allCases.first { $0.defaultsKey == key } }
        // The only untagged, unbound item with an action is "Editor Font…".
        return tag == 0 && hasAction ? .editorFont : nil
    }
}

struct SAClaudeEditorOptionSection: Equatable {
    let title: String
    let options: [SAClaudeEditorOption]

    static var all: [SAClaudeEditorOptionSection] {
        [
            SAClaudeEditorOptionSection(title: NSLocalizedString("ClaudeEditorOptionsSectionHistory", value: "History", comment: "Editor options popover section header"),
                                        options: [.previousHistory, .nextHistory, .historyReplacesContent, .favoriteReplacesContent]),
            SAClaudeEditorOptionSection(title: NSLocalizedString("ClaudeEditorOptionsSectionEditing", value: "Editing", comment: "Editor options popover section header"),
                                        options: [.shiftRight, .shiftLeft, .commentLine, .commentQuery]),
            SAClaudeEditorOptionSection(title: NSLocalizedString("ClaudeEditorOptionsSectionCompletion", value: "Completion", comment: "Editor options popover section header"),
                                        options: [.completionList, .completeDatabases, .completeTables, .completeFields]),
            SAClaudeEditorOptionSection(title: NSLocalizedString("ClaudeEditorOptionsSectionTyping", value: "Typing", comment: "Editor options popover section header"),
                                        options: [.autoIndent, .autoPair, .autoUppercase, .autoComplete, .autoHelp, .editorFont]),
        ]
    }
}
