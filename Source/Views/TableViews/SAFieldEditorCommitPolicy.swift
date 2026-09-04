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
    case deferred
    case invalidated
}

/// The table coordinates AppKit supplied for a popup selection whose reload
/// outcome is not known yet. The tracker releases this only while the same
/// table snapshot is still current.
@objc final class SADeferredComboBoxEdit: NSObject {

    @objc let proposedValue: NSObject?
    @objc let tableColumn: NSTableColumn
    @objc let row: Int

    init(proposedValue: NSObject?, tableColumn: NSTableColumn, row: Int) {
        self.proposedValue = proposedValue
        self.tableColumn = tableColumn
        self.row = row
    }
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
    private var deferredEdit: SADeferredComboBoxEdit?

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

    /// Returns whether a deferred edit may now be retried. The caller still
    /// obtains it through `takeDeferredEditIfReady()` so a reload beginning
    /// before the main-thread retry keeps the edit deferred.
    @objc func tableDataReloadDidFinish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard reloadsInProgress > 0 else {
            return false
        }
        reloadsInProgress -= 1
        if reloadsInProgress == 0,
           deferredEdit != nil,
           popupGeneration != dataGeneration {
            clearPendingSelection()
            return false
        }
        return reloadsInProgress == 0 && deferredEdit != nil
    }

    @objc(comboBoxWillOpenWithValue:)
    func comboBoxWillOpen(with value: NSObject?) {
        lock.lock()
        defer { lock.unlock() }

        clearPendingSelection()
        popupGeneration = dataGeneration
        openingValue = value
        hasOpeningValue = true
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

    @objc(consumeSelectionMatching:tableColumn:row:)
    func consumeSelection(
        matching proposedValue: NSObject?,
        tableColumn: NSTableColumn,
        row: Int
    ) -> SAComboBoxSelectionState {
        lock.lock()
        defer { lock.unlock() }

        guard let popupGeneration, hasPendingSelection else {
            return .notTracked
        }
        guard popupGeneration == dataGeneration else {
            clearPendingSelection()
            return .invalidated
        }
        guard valuesMatch(pendingSelection, proposedValue) else {
            clearPendingSelection()
            return reloadsInProgress == 0 ? .notTracked : .invalidated
        }

        // AppKit does not repeat this callback if an in-flight reload later
        // fails. Retain both its authenticated value and coordinates until the
        // reload either changes the snapshot or finishes unchanged.
        guard reloadsInProgress == 0 else {
            deferredEdit = SADeferredComboBoxEdit(
                proposedValue: proposedValue,
                tableColumn: tableColumn,
                row: row
            )
            return .deferred
        }

        clearPendingSelection()
        return .current
    }

    /// Atomically takes a deferred edit only after every overlapping reload
    /// has finished and only if no table-data mutation has occurred.
    @objc func takeDeferredEditIfReady() -> SADeferredComboBoxEdit? {
        lock.lock()
        defer { lock.unlock() }

        guard reloadsInProgress == 0, let deferredEdit else {
            return nil
        }
        guard popupGeneration == dataGeneration else {
            clearPendingSelection()
            return nil
        }

        self.deferredEdit = nil
        return deferredEdit
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
        deferredEdit = nil
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
        if popupSelectionState == .deferred || popupSelectionState == .invalidated {
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
