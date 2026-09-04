//
//  SAFieldEditorCommitPolicyTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAFieldEditorCommitPolicyTests: XCTestCase {

    func testChangedValueIsCommittedWhenFieldEditorIsPreferred() {
        XCTAssertFalse(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            proposedValue: "published" as NSString,
            currentValue: "draft" as NSString
        ))
    }

    func testUnchangedValueIsIgnoredDuringFieldEditorHandoff() {
        XCTAssertTrue(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: true,
            proposedValue: "draft" as NSString,
            currentValue: "draft" as NSString
        ))
    }

    func testUnchangedValueIsAcceptedWhenFieldEditorIsNotRequired() {
        XCTAssertFalse(SAFieldEditorCommitPolicy.shouldIgnoreInlineCommit(
            fieldEditorRequired: false,
            proposedValue: "draft" as NSString,
            currentValue: "draft" as NSString
        ))
    }
}
