//
//  SAClaudeTabBarLayout.swift
//  Sequel Ace
//
//  The table tabs' bottom strip as numbers: which Claude glyph each bar
//  control draws (from its action) and where buttons sit. Shared with the
//  unit tests.
//

import AppKit

enum SAClaudeTabBarLayout {
    static let stripHeight: CGFloat = 32
    static let buttonSize: CGFloat = 28
    static let buttonGap: CGFloat = 2
    static let sideInset: CGFloat = 10
    static let groupGap: CGFloat = 8
    static let searchFieldWidth: CGFloat = 150
    static let searchFieldHeight: CGFloat = 24

    // Keep in sync with the bar buttons' actions in DBView.xib.
    private static let glyphByAction: [String: SAClaudeGlyph] = [
        "addRow:": .add, "addField:": .add, "addIndex:": .add, "addRelation:": .add, "addTrigger:": .add,
        "removeRow:": .remove, "removeField:": .remove, "removeIndex:": .remove, "removeRelation:": .remove, "removeTrigger:": .remove,
        "duplicateRow:": .duplicate, "duplicateField:": .duplicate,
        "reloadTable:": .refresh, "refreshRelations:": .refresh, "refreshTriggers:": .refresh,
        "multipleLineEditingButtonClicked:": .editMode, "toggleRuleEditorVisible:": .filter,
        "togglePagination:": .pageOptions, "unhideIndexesView:": .indexes, "viewStatus:": .info, "toggleColumnView:": .columns,
    ]

    static func glyphs(forActions actions: [String]) -> [SAClaudeGlyph?] {
        var seenNavigate = false
        return actions.map { action in
            if action == "navigatePaginationFromButton:" {
                defer { seenNavigate = true }
                return seenNavigate ? .chevronRight : .chevronLeft
            }
            return glyphByAction[action]
        }
    }

    static func leftXs(count: Int) -> [CGFloat] {
        (0..<max(count, 0)).map { sideInset + CGFloat($0) * (buttonSize + buttonGap) }
    }

    static func rightXs(count: Int, width: CGFloat) -> [CGFloat] {
        let lastX = width - sideInset - buttonSize
        return (0..<max(count, 0)).map { lastX - CGFloat(count - 1 - $0) * (buttonSize + buttonGap) }
    }

    static func centredY(height: CGFloat) -> CGFloat {
        ((stripHeight - height) / 2).rounded(.down)
    }
}
