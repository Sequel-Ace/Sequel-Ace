//
//  SAClaudeInlineNameCommandTests.swift
//  Unit Tests
//
//  Pins the keys the connection page's inline name fields take for themselves: Return / Enter (and ⌥/⌃ Return)
//  save, Escape cancels, everything else stays with the field.
//

import XCTest

final class SAClaudeInlineNameCommandTests: XCTestCase {

    func testReturnAndItsVariantsCommit() {
        XCTAssertEqual(SAClaudeInlineNameCommand(NSSelectorFromString("insertNewline:")), .commit)
        XCTAssertEqual(SAClaudeInlineNameCommand(NSSelectorFromString("insertNewlineIgnoringFieldEditor:")), .commit)
        XCTAssertEqual(SAClaudeInlineNameCommand(NSSelectorFromString("insertLineBreak:")), .commit)
    }

    func testEscapeCancels() {
        XCTAssertEqual(SAClaudeInlineNameCommand(NSSelectorFromString("cancelOperation:")), .cancel)
    }

    func testOtherCommandsStayWithTheField() {
        for name in ["insertTab:", "insertBacktab:", "moveDown:", "moveUp:", "deleteBackward:", "complete:", "selectAll:"] {
            XCTAssertNil(SAClaudeInlineNameCommand(NSSelectorFromString(name)), name)
        }
    }
}
