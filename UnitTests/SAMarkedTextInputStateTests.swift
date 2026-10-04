//
//  SAMarkedTextInputStateTests.swift
//  Unit Tests
//
//  Created by Sequel Ace on August 24, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAMarkedTextInputStateTests: XCTestCase {

    func testMarkedTextTracksInputMethodSelection() {
        let state = SAMarkedTextInputState()

        state.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertEqual(state.text, "かな")
        XCTAssertEqual(state.markedRange, NSRange(location: 0, length: 2))
        XCTAssertEqual(state.selectedRange, NSRange(location: 1, length: 0))
    }

    func testDeleteBackwardEditsMarkedText() {
        let state = SAMarkedTextInputState()
        state.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertTrue(state.performCommand(NSSelectorFromString("deleteBackward:")))

        XCTAssertEqual(state.text, "か")
        XCTAssertEqual(state.selectedRange, NSRange(location: 1, length: 0))
    }

    func testMoveLeftChangesOnlyTheMarkedTextSelection() {
        let state = SAMarkedTextInputState()
        state.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertTrue(state.performCommand(NSSelectorFromString("moveLeft:")))

        XCTAssertEqual(state.text, "かな")
        XCTAssertEqual(state.selectedRange, NSRange(location: 1, length: 0))
    }

    func testDeletingTheWholeCompositionClearsMarkedRange() {
        let state = SAMarkedTextInputState()
        state.setMarkedText(
            "é",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertTrue(state.performCommand(NSSelectorFromString("deleteBackward:")))

        XCTAssertFalse(state.hasMarkedText)
        XCTAssertEqual(state.markedRange, NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(state.selectedRange, NSRange(location: 0, length: 0))
    }

    func testReplacementRangeAndRelativeSelectionAreApplied() {
        let state = SAMarkedTextInputState()
        state.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        state.setMarkedText(
            "に",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 1, length: 1)
        )

        XCTAssertEqual(state.text, "かに")
        XCTAssertEqual(state.selectedRange, NSRange(location: 2, length: 0))
    }

    func testCommandWithoutCompositionIsNotConsumed() {
        let state = SAMarkedTextInputState()

        XCTAssertFalse(state.performCommand(NSSelectorFromString("moveLeft:")))
    }

    func testCancelOperationFallsThroughWithoutChangingComposition() {
        let state = SAMarkedTextInputState()
        state.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertFalse(state.performCommand(NSSelectorFromString("cancelOperation:")))
        XCTAssertEqual(state.text, "かな")
        XCTAssertTrue(state.hasMarkedText)
    }
}
