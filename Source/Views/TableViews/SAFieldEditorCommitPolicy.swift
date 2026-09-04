//
//  SAFieldEditorCommitPolicy.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

@objc final class SAFieldEditorCommitPolicy: NSObject {

    /// Inline editing is aborted before the field editor sheet opens, and
    /// AppKit can send the unchanged cell value during that handoff. A changed
    /// value came from a completed inline control action and must be committed.
    @objc(shouldIgnoreInlineCommitWithFieldEditorRequired:proposedValue:currentValue:)
    static func shouldIgnoreInlineCommit(
        fieldEditorRequired: Bool,
        proposedValue: NSObject?,
        currentValue: NSObject?
    ) -> Bool {
        guard fieldEditorRequired else { return false }
        guard let proposedValue else { return currentValue == nil }
        return proposedValue.isEqual(currentValue)
    }
}
