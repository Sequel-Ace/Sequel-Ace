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
            popupSelectionIsCurrent: true
        ))
    }

    func testChangedComboValueWithoutCurrentPopupSelectionIsIgnored() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "published" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionIsCurrent: false
        ))
    }

    func testUnchangedComboValueIsIgnoredDuringFieldEditorHandoff() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "draft" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionIsCurrent: true
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
            popupSelectionIsCurrent: true
        ))
    }

    func testNullDisplayValueIsIgnoredDuringFieldEditorHandoff() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "NULL" as NSString,
            storedValue: NSNull(),
            displayValue: "NULL" as NSString,
            popupSelectionIsCurrent: true
        ))
    }

    func testFormatterDisplayValueIsIgnoredDuringFieldEditorHandoff() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: ""),
            proposedValue: "formatted" as NSString,
            storedValue: Data([0x01, 0x02]) as NSData,
            displayValue: "formatted" as NSString,
            popupSelectionIsCurrent: true
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
            popupSelectionIsCurrent: true
        ))
    }

    func testChangedTextValueIsIgnoredDuringFieldEditorHandoff() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSTextFieldCell(textCell: ""),
            proposedValue: "edited" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionIsCurrent: false
        ))
    }

    func testUnchangedValueIsAcceptedWhenFieldEditorIsNotRequired() {
        XCTAssertFalse(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: false,
            cell: NSTextFieldCell(textCell: ""),
            proposedValue: "draft" as NSString,
            storedValue: "draft" as NSString,
            displayValue: "draft" as NSString,
            popupSelectionIsCurrent: false
        ))
    }

    func testCurrentPopupSelectionCanOnlyBeConsumedOnce() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen()
        tracker.comboBoxSelectionDidChange("published" as NSString)

        XCTAssertTrue(tracker.consumeCurrentSelection(matching: "published" as NSString))
        XCTAssertFalse(tracker.consumeCurrentSelection(matching: "published" as NSString))
    }

    func testReloadInvalidatesPopupSelectionWhenDimensionsCouldStayTheSame() {
        let tracker = SAComboBoxSelectionTracker()
        tracker.comboBoxWillOpen()
        tracker.comboBoxSelectionDidChange("published" as NSString)

        tracker.tableDataWillReload()

        XCTAssertFalse(tracker.consumeCurrentSelection(matching: "published" as NSString))
    }
}
