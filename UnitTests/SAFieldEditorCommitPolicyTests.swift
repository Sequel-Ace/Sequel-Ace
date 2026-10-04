//
//  SAFieldEditorCommitPolicyTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest

final class SAFieldEditorCommitPolicyTests: XCTestCase {

    private func selectionState(
        from tracker: SAComboBoxSelectionTracker,
        matching value: NSObject?,
        tableColumn: NSTableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status")),
        row: Int = 0
    ) -> SAComboBoxSelectionState {
        tracker.consumeSelection(matching: value, tableColumn: tableColumn, row: row)
    }

    func testChangedComboValueIsCommittedWhenFieldEditorIsPreferred() {
        XCTAssertFalse(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "published" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionState: .current
        ))
    }

    func testChangedComboValueWithoutCurrentPopupSelectionIsIgnored() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "published" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionState: .notTracked
        ))
    }

    func testUnchangedComboValueIsIgnoredDuringFieldEditorHandoff() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "draft" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionState: .current
        ))
    }

    func testLongUnchangedComboValueIsIgnoredDuringFieldEditorHandoff() {
        let value = String(repeating: "a", count: 151) as NSString
        let truncatedPreview = String(repeating: "a", count: 150) as NSString

        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: value,
            storedValue: value,
            displayValue: truncatedPreview,
            popupSelectionState: .current
        ))
    }

    func testNullDisplayValueIsIgnoredDuringFieldEditorHandoff() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "NULL" as NSString,
            storedValue: NSNull(),
            displayValue: "NULL" as NSString,
            popupSelectionState: .current
        ))
    }

    func testFormatterDisplayValueIsIgnoredDuringFieldEditorHandoff() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "formatted" as NSString,
            storedValue: Data([0x01, 0x02]) as NSData,
            displayValue: "formatted" as NSString,
            popupSelectionState: .current
        ))
    }

    func testFormatterRawObjectValueIsIgnoredDuringFieldEditorHandoff() {
        let value = Data([0x01, 0x02]) as NSData

        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: value,
            storedValue: value,
            displayValue: "formatted" as NSString,
            popupSelectionState: .current
        ))
    }

    func testChangedTextValueIsIgnoredDuringFieldEditorHandoff() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSTextFieldCell(textCell: ""),
            proposedValue: "edited" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionState: .notTracked
        ))
    }

    func testUnchangedValueIsAcceptedWhenFieldEditorIsNotRequired() {
        XCTAssertFalse(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: false,
            cell: NSTextFieldCell(textCell: ""),
            proposedValue: "draft" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionState: .notTracked
        ))
    }

    func testInvalidatedPopupSelectionIsIgnoredWhenFieldEditorIsNotRequired() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.tableDataReloadWillBegin()
        tracker.tableDataWillChange()
        tracker.comboBoxDidClose(with: "published" as NSString)
        tracker.tableDataReloadDidFinish()

        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: false,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "published" as NSString,
            storedValue: "replacement-row" as NSString,
            displayValue: "replacement-row" as NSString,
            popupSelectionState: selectionState(from: tracker, matching: "published" as NSString)
        ))
    }

    func testReloadAfterCancelledHighlightedSelectionDoesNotInvalidateNextInlineEdit() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.tableDataReloadWillBegin()
        tracker.tableDataWillChange()
        tracker.comboBoxDidClose(with: "draft" as NSString)
        tracker.tableDataReloadDidFinish()

        XCTAssertFalse(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: false,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "published" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionState: selectionState(from: tracker, matching: "published" as NSString)
        ))
    }

    func testUntrackedComboValueIsAcceptedWhenFieldEditorIsNotRequired() {
        XCTAssertFalse(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: false,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "published" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionState: .notTracked
        ))
    }

    func testCurrentPopupSelectionCanOnlyBeConsumedOnce() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)

        XCTAssertEqual(selectionState(from: tracker, matching: "published" as NSString), .current)
        XCTAssertEqual(selectionState(from: tracker, matching: "published" as NSString), .notTracked)
    }

    func testReloadInvalidatesPopupSelectionWhenDimensionsCouldStayTheSame() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)

        tracker.tableDataReloadWillBegin()
        tracker.tableDataWillChange()
        tracker.tableDataReloadDidFinish()

        XCTAssertEqual(selectionState(from: tracker, matching: "published" as NSString), .invalidated)
    }

    func testReloadWithoutDataMutationKeepsPopupSelectionCurrent() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)

        tracker.tableDataReloadWillBegin()
        XCTAssertFalse(tracker.tableDataReloadDidFinish())

        XCTAssertEqual(selectionState(from: tracker, matching: "published" as NSString), .current)
    }

    func testPendingReloadDefersPopupSelectionUntilUnchangedOutcome() {
        let tracker = SAComboBoxSelectionTracker()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)

        tracker.tableDataReloadWillBegin()

        XCTAssertEqual(
            selectionState(from: tracker, matching: "published" as NSString, tableColumn: column, row: 4),
            .deferred
        )
        XCTAssertTrue(tracker.tableDataReloadDidFinish())

        let deferredEdit = tracker.takeDeferredEditIfReady()
        XCTAssertEqual(deferredEdit?.proposedValue, "published" as NSString)
        XCTAssertTrue(deferredEdit?.tableColumn === column)
        XCTAssertEqual(deferredEdit?.row, 4)
        XCTAssertEqual(
            selectionState(from: tracker, matching: deferredEdit?.proposedValue, tableColumn: column, row: 4),
            .current
        )
    }

    func testScheduledReloadReservationClosesDetachedWorkerGap() {
        let tracker = SAComboBoxSelectionTracker()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)

        // The outer load schedules a full reload before it finishes. The task
        // reservation begins synchronously; its nested load starts later.
        tracker.tableDataReloadWillBegin()
        tracker.tableDataReloadWillBegin()
        XCTAssertFalse(tracker.tableDataReloadDidFinish())

        XCTAssertEqual(
            selectionState(from: tracker, matching: "published" as NSString, tableColumn: column),
            .deferred
        )

        tracker.tableDataReloadWillBegin()
        XCTAssertFalse(tracker.tableDataReloadDidFinish())
        XCTAssertTrue(tracker.tableDataReloadDidFinish())

        let deferredEdit = tracker.takeDeferredEditIfReady()
        XCTAssertNotNil(deferredEdit)
        XCTAssertEqual(
            selectionState(from: tracker, matching: deferredEdit?.proposedValue, tableColumn: column),
            .current
        )
    }

    func testDataMutationDiscardsDeferredPopupSelection() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)
        tracker.tableDataReloadWillBegin()

        XCTAssertEqual(selectionState(from: tracker, matching: "published" as NSString), .deferred)
        tracker.tableDataWillChange()

        XCTAssertFalse(tracker.tableDataReloadDidFinish())
        XCTAssertNil(tracker.takeDeferredEditIfReady())
        XCTAssertEqual(selectionState(from: tracker, matching: "published" as NSString), .notTracked)
    }

    func testColumnModelRebuildDiscardsDeferredPopupSelection() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)
        tracker.tableDataReloadWillBegin()

        XCTAssertEqual(selectionState(from: tracker, matching: "published" as NSString), .deferred)
        tracker.tableColumnModelWillChange()

        XCTAssertFalse(tracker.tableDataReloadDidFinish())
        XCTAssertNil(tracker.takeDeferredEditIfReady())
        XCTAssertEqual(selectionState(from: tracker, matching: "published" as NSString), .notTracked)
    }

    func testReloadBeginningBeforeDeferredRetryKeepsSelectionQueued() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)
        tracker.tableDataReloadWillBegin()
        XCTAssertEqual(selectionState(from: tracker, matching: "published" as NSString), .deferred)
        XCTAssertTrue(tracker.tableDataReloadDidFinish())

        tracker.tableDataReloadWillBegin()
        XCTAssertNil(tracker.takeDeferredEditIfReady())
        XCTAssertTrue(tracker.tableDataReloadDidFinish())
        XCTAssertNotNil(tracker.takeDeferredEditIfReady())
    }

    func testNewPopupDiscardsAnOlderDeferredEdit() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)
        tracker.tableDataReloadWillBegin()
        XCTAssertEqual(selectionState(from: tracker, matching: "published" as NSString), .deferred)
        XCTAssertTrue(tracker.tableDataReloadDidFinish())

        tracker.comboBoxWillOpen(with: "queued" as NSString)

        XCTAssertNil(tracker.takeDeferredEditIfReady())
    }

    func testDeferredPopupStateIsIgnoredByCommitPolicy() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: false,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "published" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionState: .deferred
        ))
    }
}
