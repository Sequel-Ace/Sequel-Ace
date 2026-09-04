//
//  SAFieldEditorCommitPolicy.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

@objc enum SAComboBoxSelectionState: Int {
    case notTracked
    case current
    case invalidated
}

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

        // Retain the popup generation until its callback is consumed so an
        // invalidated popup remains distinguishable from ordinary inline input.
        dataGeneration &+= 1
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

        guard popupGeneration != nil else {
            return
        }
        pendingSelection = value
        hasPendingSelection = true
    }

    @objc(consumeSelectionMatching:)
    func consumeSelection(matching proposedValue: NSObject?) -> SAComboBoxSelectionState {
        lock.lock()
        defer {
            clearPendingSelection()
            lock.unlock()
        }

        guard let popupGeneration else {
            return .notTracked
        }
        guard popupGeneration == dataGeneration else {
            return .invalidated
        }
        guard hasPendingSelection else {
            return .notTracked
        }
        guard let pendingSelection else {
            return proposedValue == nil ? .current : .notTracked
        }
        return pendingSelection.isEqual(proposedValue) ? .current : .notTracked
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
    @objc(shouldIgnoreInlineCommitWithFieldEditorRequired:cell:proposedValue:storedValue:displayValue:popupSelectionState:)
    static func shouldIgnoreInlineCommit(
        fieldEditorRequired: Bool,
        cell: NSCell,
        proposedValue: NSObject?,
        storedValue: NSObject?,
        displayValue: NSObject?,
        popupSelectionState: SAComboBoxSelectionState
    ) -> Bool {
        if popupSelectionState == .invalidated {
            return true
        }
        guard fieldEditorRequired else {
            return false
        }
        guard cell is NSComboBoxCell, popupSelectionState == .current else {
            return true
        }

        let proposedValueMatches: (NSObject?) -> Bool = { currentValue in
            guard let proposedValue else {
                return currentValue == nil
            }
            return proposedValue.isEqual(currentValue)
        }
        return proposedValueMatches(storedValue) || proposedValueMatches(displayValue)
    }
}
