//
//  SAFieldEditorCommitPolicyTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAFieldEditorCommitPolicyTests: XCTestCase {

    func testPopupSelectionIsCommittedWhenFieldEditorIsPreferred() {
        XCTAssertFalse(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSComboBoxCell(textCell: "")
        ))
    }

    func testTextCommitIsIgnoredDuringFieldEditorHandoff() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            cell: NSTextFieldCell(textCell: "")
        ))
    }

    func testInlineCommitIsAcceptedWhenFieldEditorIsNotRequired() {
        XCTAssertFalse(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: false,
            cell: NSTextFieldCell(textCell: "")
        ))
    }
}
