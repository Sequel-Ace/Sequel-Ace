//
//  SAFieldEditorCommitPolicyTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAFieldEditorCommitPolicyTests: XCTestCase {

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
            popupSelectionState: tracker.consumeSelection(matching: "published" as NSString)
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
            popupSelectionState: tracker.consumeSelection(matching: "published" as NSString)
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

        XCTAssertEqual(tracker.consumeSelection(matching: "published" as NSString), .current)
        XCTAssertEqual(tracker.consumeSelection(matching: "published" as NSString), .notTracked)
    }

    func testReloadInvalidatesPopupSelectionWhenDimensionsCouldStayTheSame() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)

        tracker.tableDataReloadWillBegin()
        tracker.tableDataWillChange()
        tracker.tableDataReloadDidFinish()

        XCTAssertEqual(tracker.consumeSelection(matching: "published" as NSString), .invalidated)
    }

    func testReloadWithoutDataMutationKeepsPopupSelectionCurrent() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)

        tracker.tableDataReloadWillBegin()
        tracker.tableDataReloadDidFinish()

        XCTAssertEqual(tracker.consumeSelection(matching: "published" as NSString), .current)
    }

    func testPendingReloadConservativelyInvalidatesPopupSelection() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)

        tracker.tableDataReloadWillBegin()

        XCTAssertEqual(tracker.consumeSelection(matching: "published" as NSString), .invalidated)
        tracker.tableDataReloadDidFinish()
    }

    func testNestedReloadsRemainPendingUntilEveryLoadFinishes() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.tableDataReloadWillBegin()
        tracker.tableDataReloadWillBegin()
        tracker.tableDataReloadDidFinish()

        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)

        XCTAssertEqual(tracker.consumeSelection(matching: "published" as NSString), .invalidated)
        tracker.tableDataReloadDidFinish()

        tracker.comboBoxWillOpen(with: "draft" as NSString)
        tracker.comboBoxSelectionDidChange("published" as NSString)
        tracker.comboBoxDidClose(with: "published" as NSString)

        XCTAssertEqual(tracker.consumeSelection(matching: "published" as NSString), .current)
    }
}
