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
    private var reloadsInProgress = 0
    private var popupGeneration: UInt?
    private var openingValue: NSObject?
    private var hasOpeningValue = false
    private var pendingSelection: NSObject?
    private var hasPendingSelection = false

    @objc func tableDataWillChange() {
        lock.lock()
        defer { lock.unlock() }

        dataGeneration &+= 1
    }

    @objc func tableDataReloadWillBegin() {
        lock.lock()
        defer { lock.unlock() }
        // A query can fail without changing the current snapshot. Block popup
        // callbacks while its outcome is unknown without advancing the revision.
        reloadsInProgress += 1
    }

    @objc func tableDataReloadDidFinish() {
        lock.lock()
        defer { lock.unlock() }
        guard reloadsInProgress > 0 else {
            return
        }
        reloadsInProgress -= 1
    }

    @objc(comboBoxWillOpenWithValue:)
    func comboBoxWillOpen(with value: NSObject?) {
        lock.lock()
        defer { lock.unlock() }

        popupGeneration = dataGeneration
        openingValue = value
        hasOpeningValue = true
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

    @objc(comboBoxDidCloseWithValue:)
    func comboBoxDidClose(with value: NSObject?) {
        lock.lock()
        defer { lock.unlock() }

        // Selection-change notifications describe the highlighted popup row,
        // even when Escape later restores the opening value. Retain provenance
        // only when a changed candidate became the cell's final object value.
        guard popupGeneration != nil,
              hasOpeningValue,
              hasPendingSelection,
              valuesMatch(pendingSelection, value),
              !valuesMatch(openingValue, pendingSelection) else {
            clearPendingSelection()
            return
        }
    }

    @objc(consumeSelectionMatching:)
    func consumeSelection(matching proposedValue: NSObject?) -> SAComboBoxSelectionState {
        lock.lock()
        defer {
            clearPendingSelection()
            lock.unlock()
        }

        guard let popupGeneration, hasPendingSelection else {
            return .notTracked
        }
        // Never write while a reload could still replace the indexed row.
        guard reloadsInProgress == 0 else {
            return .invalidated
        }
        guard popupGeneration == dataGeneration else {
            return .invalidated
        }
        return valuesMatch(pendingSelection, proposedValue) ? .current : .notTracked
    }

    @objc func discardPendingSelection() {
        lock.lock()
        defer { lock.unlock() }
        clearPendingSelection()
    }

    private func clearPendingSelection() {
        popupGeneration = nil
        openingValue = nil
        hasOpeningValue = false
        pendingSelection = nil
        hasPendingSelection = false
    }

    private func valuesMatch(_ lhs: NSObject?, _ rhs: NSObject?) -> Bool {
        guard let lhs else {
            return rhs == nil
        }
        return lhs.isEqual(rhs)
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
