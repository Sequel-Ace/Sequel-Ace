//
//  SAFieldEditorCommitPolicy.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// Authenticates combo-box callbacks against the table snapshot in which the
/// popup selection occurred. AppKit otherwise supplies only row/column indexes.
@objc final class SAComboBoxSelectionTracker: NSObject {

    private let lock = NSLock()
    private var dataGeneration: UInt = 0
    private var popupGeneration: UInt?
    private var pendingSelection: NSObject?
    private var hasPendingSelection = false

    @objc func tableDataWillReload() {
        lock.lock()
        defer { lock.unlock() }

        dataGeneration &+= 1
        clearPendingSelection()
    }

    @objc func comboBoxWillOpen() {
        lock.lock()
        defer { lock.unlock() }

        popupGeneration = dataGeneration
        pendingSelection = nil
        hasPendingSelection = false
    }

    @objc(comboBoxSelectionDidChange:)
    func comboBoxSelectionDidChange(_ value: NSObject?) {
        lock.lock()
        defer { lock.unlock() }

        guard popupGeneration != nil else { return }
        pendingSelection = value
        hasPendingSelection = true
    }

    @objc(consumeCurrentSelectionMatching:)
    func consumeCurrentSelection(matching proposedValue: NSObject?) -> Bool {
        lock.lock()
        defer {
            clearPendingSelection()
            lock.unlock()
        }

        guard hasPendingSelection, popupGeneration == dataGeneration else { return false }
        guard let pendingSelection else { return proposedValue == nil }
        return pendingSelection.isEqual(proposedValue)
    }

    @objc func discardPendingSelection() {
        lock.lock()
        defer { lock.unlock() }
        clearPendingSelection()
    }

    private func clearPendingSelection() {
        popupGeneration = nil
        pendingSelection = nil
        hasPendingSelection = false
    }
}

@objc final class SAFieldEditorCommitPolicy: NSObject {

    /// Inline editing is aborted before the field editor sheet opens. Ignore
    /// callbacks from that handoff unless a combo box supplied a changed value.
    @objc(shouldIgnoreInlineCommitWithFieldEditorRequired:cell:proposedValue:storedValue:displayValue:popupSelectionIsCurrent:)
    static func shouldIgnoreInlineCommit(
        fieldEditorRequired: Bool,
        cell: NSCell,
        proposedValue: NSObject?,
        storedValue: NSObject?,
        displayValue: NSObject?,
        popupSelectionIsCurrent: Bool
    ) -> Bool {
        guard fieldEditorRequired else { return false }
        guard cell is NSComboBoxCell, popupSelectionIsCurrent else { return true }

        let proposedValueMatches: (NSObject?) -> Bool = { currentValue in
            guard let proposedValue else { return currentValue == nil }
            return proposedValue.isEqual(currentValue)
        }
        return proposedValueMatches(storedValue) || proposedValueMatches(displayValue)
    }
}
