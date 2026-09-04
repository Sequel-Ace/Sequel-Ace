//
//  SAFieldEditorCommitPolicy.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

@objc final class SAFieldEditorCommitPolicy: NSObject {

    /// Inline text editing is aborted before the field editor sheet opens, and
    /// AppKit can send the unchanged cell value during that handoff. Popup
    /// cells instead send the user's selected value and must be committed.
    @objc(shouldIgnoreInlineCommitWithFieldEditorRequired:cell:)
    static func shouldIgnoreInlineCommit(
        fieldEditorRequired: Bool,
        cell: NSCell
    ) -> Bool {
        fieldEditorRequired && !(cell is NSComboBoxCell)
    }
}
