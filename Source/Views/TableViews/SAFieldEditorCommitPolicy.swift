//
//  SAFieldEditorCommitPolicy.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

@objc final class SAFieldEditorCommitPolicy: NSObject {

    /// Inline editing is aborted before the field editor sheet opens. Ignore
    /// callbacks from that handoff unless a combo box supplied a changed value.
    @objc(shouldIgnoreInlineCommitWithFieldEditorRequired:cell:proposedValue:storedValue:displayValue:)
    static func shouldIgnoreInlineCommit(
        fieldEditorRequired: Bool,
        cell: NSCell,
        proposedValue: NSObject?,
        storedValue: NSObject?,
        displayValue: NSObject?
    ) -> Bool {
        guard fieldEditorRequired else { return false }
        guard cell is NSComboBoxCell else { return true }

        let proposedValueMatches: (NSObject?) -> Bool = { currentValue in
            guard let proposedValue else { return currentValue == nil }
            return proposedValue.isEqual(currentValue)
        }
        return proposedValueMatches(storedValue) || proposedValueMatches(displayValue)
    }
}
