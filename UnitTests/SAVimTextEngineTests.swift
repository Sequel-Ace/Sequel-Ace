//
//  SAVimTextEngineTests.swift
//  Unit Tests
//
//  Created by Sequel Ace on September 17, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAVimTextEngineTests: XCTestCase {

    // Three lines, so linewise motions have somewhere to go.
    private let sql = "SELECT id, name\nFROM users\nWHERE id = 3;"

    // MARK: - Helpers

    private func run(_ command: SAVimCommand,
                     _ text: String,
                     caret: Int,
                     mode: SAVimMode = .normal,
                     selection: NSRange? = nil,
                     register: SAVimRegister? = nil,
                     lastSearch: (pattern: String, forward: Bool)? = nil,
                     desiredColumn: Int? = nil,
                     visualAnchor: Int? = nil) -> SAVimOutcome {
        SAVimTextEngine.run(command, context: SAVimContext(text: text as NSString,
                                                           caret: caret,
                                                           selection: selection,
                                                           mode: mode,
                                                           register: register,
                                                           lastSearch: lastSearch,
                                                           desiredColumn: desiredColumn,
                                                           visualAnchor: visualAnchor))
    }

    /// Applies an outcome's edit the way the text view does.
    private func applied(_ outcome: SAVimOutcome, to text: String) -> String {
        guard let edit = outcome.edit else { return text }
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: edit.range, with: edit.text)
        return mutable as String
    }

    // MARK: - Motion kinds
    //
    // Whether a motion is linewise, inclusive or exclusive is the difference
    // between vim and a keymap that only looks like vim.

    func testDeleteToEndOfLineIsInclusiveButKeepsTheLineBreak() {
        let outcome = run(.operate(.delete, .motion(.lineEnd), count: 1), sql, caret: 7)
        XCTAssertEqual(applied(outcome, to: sql), "SELECT \nFROM users\nWHERE id = 3;")
    }

    func testDeleteDownIsLinewiseAndTakesBothLinesWhole() {
        let outcome = run(.operate(.delete, .motion(.lineDown), count: 1), sql, caret: 3)
        XCTAssertEqual(applied(outcome, to: sql), "WHERE id = 3;")
        XCTAssertEqual(outcome.register?.isLinewise, true)
    }

    func testDeleteWordIsExclusive() {
        let outcome = run(.operate(.delete, .motion(.wordForward(big: false)), count: 1), sql, caret: 0)
        XCTAssertEqual(applied(outcome, to: sql), "id, name\nFROM users\nWHERE id = 3;")
    }

    func testDeleteWordStopsAtTheEndOfTheLine() {
        // vim: dw on the last word of a line does not join it with the next.
        let outcome = run(.operate(.delete, .motion(.wordForward(big: false)), count: 1), sql, caret: 11)
        XCTAssertEqual(applied(outcome, to: sql), "SELECT id, \nFROM users\nWHERE id = 3;")
    }

    func testDeleteWordEndIsInclusive() {
        let outcome = run(.operate(.delete, .motion(.wordEnd(big: false)), count: 1), sql, caret: 7)
        XCTAssertEqual(applied(outcome, to: sql), "SELECT , name\nFROM users\nWHERE id = 3;")
    }

    // MARK: - Line operators

    func testDeleteLine() {
        let outcome = run(.operate(.delete, .wholeLines, count: 1), sql, caret: 17)
        XCTAssertEqual(applied(outcome, to: sql), "SELECT id, name\nWHERE id = 3;")
        XCTAssertEqual(outcome.register?.text, "FROM users\n")
        XCTAssertEqual(outcome.register?.isLinewise, true)
    }

    func testDeleteSeveralLines() {
        let outcome = run(.operate(.delete, .wholeLines, count: 2), sql, caret: 17)
        XCTAssertEqual(applied(outcome, to: sql), "SELECT id, name\n")
    }

    func testDeleteLineCountBeyondTheBufferStopsAtTheEnd() {
        let outcome = run(.operate(.delete, .wholeLines, count: 99), sql, caret: 17)
        XCTAssertEqual(applied(outcome, to: sql), "SELECT id, name\n")
    }

    func testDeletingTheLastLinePutsTheCaretOnThePreviousOne() {
        let outcome = run(.operate(.delete, .wholeLines, count: 1), sql, caret: 30)
        XCTAssertEqual(applied(outcome, to: sql), "SELECT id, name\nFROM users\n")
        XCTAssertEqual(outcome.caret, 16)
    }

    func testChangeLineKeepsTheIndentationAndTheLine() {
        let indented = "SELECT 1\n    FROM t\nWHERE x"
        let outcome = run(.operate(.change, .wholeLines, count: 1), indented, caret: 12)
        XCTAssertEqual(applied(outcome, to: indented), "SELECT 1\n    \nWHERE x")
        XCTAssertEqual(outcome.caret, 13)
        XCTAssertEqual(outcome.mode, .insert)
    }

    func testYankDoesNotChangeTheText() {
        let outcome = run(.operate(.yank, .wholeLines, count: 1), sql, caret: 17)
        XCTAssertNil(outcome.edit)
        XCTAssertEqual(outcome.register?.text, "FROM users\n")
    }

    func testShiftIsDelegatedToTheTextViewWithTheLineSpan() {
        let outcome = run(.operate(.shiftRight, .wholeLines, count: 2), sql, caret: 0)
        XCTAssertNil(outcome.edit)
        XCTAssertEqual(outcome.shiftLines?.range, NSRange(location: 0, length: 27))
        XCTAssertEqual(outcome.shiftLines?.right, true)
    }

    // MARK: - Text objects

    func testInnerWord() {
        let outcome = run(.operate(.change, .textObject(.word(big: false, around: false)), count: 1), sql, caret: 12)
        XCTAssertEqual(applied(outcome, to: sql), "SELECT id, \nFROM users\nWHERE id = 3;")
        XCTAssertEqual(outcome.mode, .insert)
    }

    func testAroundWordTakesTheTrailingSpace() {
        let outcome = run(.operate(.delete, .textObject(.word(big: false, around: true)), count: 1), sql, caret: 0)
        XCTAssertEqual(applied(outcome, to: sql), "id, name\nFROM users\nWHERE id = 3;")
    }

    func testAroundWordTakesTheLeadingSpaceForTheLastWordOnALine() {
        let outcome = run(.operate(.delete, .textObject(.word(big: false, around: true)), count: 1), sql, caret: 12)
        XCTAssertEqual(applied(outcome, to: sql), "SELECT id,\nFROM users\nWHERE id = 3;")
    }

    func testInnerQuotes() {
        let quoted = "WHERE name = 'ali veli' AND x = 1"
        let outcome = run(.operate(.change, .textObject(.quoted("'", around: false)), count: 1), quoted, caret: 17)
        XCTAssertEqual(applied(outcome, to: quoted), "WHERE name = '' AND x = 1")
    }

    func testQuoteObjectPicksThePairTheCaretIsIn() {
        let two = "a 'first' b 'second' c"
        let outcome = run(.operate(.delete, .textObject(.quoted("'", around: true)), count: 1), two, caret: 15)
        XCTAssertEqual(applied(two: outcome, to: two), "a 'first' b  c")
    }

    private func applied(two outcome: SAVimOutcome, to text: String) -> String {
        applied(outcome, to: text)
    }

    func testInnerAndAroundBrackets() {
        let parens = "SELECT COUNT(id, name) FROM t"
        XCTAssertEqual(applied(run(.operate(.delete, .textObject(.bracketed(open: "(", around: false)), count: 1), parens, caret: 15), to: parens),
                       "SELECT COUNT() FROM t")
        XCTAssertEqual(applied(run(.operate(.delete, .textObject(.bracketed(open: "(", around: true)), count: 1), parens, caret: 15), to: parens),
                       "SELECT COUNT FROM t")
    }

    func testBracketObjectSpansLines() {
        let block = "IF (x) THEN {\n  SELECT 1;\n}"
        let outcome = run(.operate(.delete, .textObject(.bracketed(open: "{", around: false)), count: 1), block, caret: 18)
        XCTAssertEqual(applied(outcome, to: block), "IF (x) THEN {}")
    }

    func testTextObjectWithoutAMatchFails() {
        let outcome = run(.operate(.delete, .textObject(.quoted("'", around: false)), count: 1), sql, caret: 0)
        XCTAssertTrue(outcome.beep)
        XCTAssertNil(outcome.edit)
    }

    // MARK: - Paste

    func testLinewisePasteGoesBelowTheCurrentLine() {
        let register = SAVimRegister(text: "FROM users\n", isLinewise: true)
        let outcome = run(.paste(after: true, count: 1), sql, caret: 17, register: register)
        XCTAssertEqual(applied(outcome, to: sql), "SELECT id, name\nFROM users\nFROM users\nWHERE id = 3;")
        XCTAssertEqual(outcome.caret, 27)
    }

    func testLinewisePasteAboveWithACount() {
        let register = SAVimRegister(text: "x\n", isLinewise: true)
        let outcome = run(.paste(after: false, count: 2), sql, caret: 0, register: register)
        XCTAssertEqual(applied(outcome, to: sql), "x\nx\nSELECT id, name\nFROM users\nWHERE id = 3;")
    }

    func testLinewisePasteBelowTheLastLineAddsTheMissingNewline() {
        let register = SAVimRegister(text: "tail\n", isLinewise: true)
        let outcome = run(.paste(after: true, count: 1), sql, caret: 30, register: register)
        XCTAssertEqual(applied(outcome, to: sql), "SELECT id, name\nFROM users\nWHERE id = 3;\ntail")
    }

    func testCharwisePasteLandsAfterTheCaret() {
        let register = SAVimRegister(text: "XY", isLinewise: false)
        let outcome = run(.paste(after: true, count: 1), sql, caret: 0, register: register)
        XCTAssertEqual(applied(outcome, to: sql), "SXYELECT id, name\nFROM users\nWHERE id = 3;")
    }

    func testPasteRefusesToGenerateAnAbsurdAmountOfText() {
        // The count is capped, but the register it repeats is not.
        let big = SAVimRegister(text: String(repeating: "x", count: 5_000), isLinewise: false)
        XCTAssertTrue(run(.paste(after: true, count: 10_000), sql, caret: 0, register: big).beep)
        XCTAssertFalse(run(.paste(after: true, count: 10), sql, caret: 0, register: big).beep)
    }

    func testToggleCaseReportsItsCaretInPostEditCoordinates() {
        // "İ" lowercases to i + a combining dot, one character but two UTF-16
        // units, so the caret cannot be measured against the old text.
        let outcome = run(.toggleCase(count: 1), "İx", caret: 0)
        XCTAssertEqual(applied(outcome, to: "İx"), "i\u{0307}x")
        XCTAssertEqual(outcome.caret, 2)
    }

    func testPasteWithAnEmptyRegisterFails() {
        XCTAssertTrue(run(.paste(after: true, count: 1), sql, caret: 0).beep)
    }

    // MARK: - Single-key edits

    func testDeleteCharStopsAtTheEndOfTheLine() {
        let short = "ab\ncd"
        XCTAssertEqual(applied(run(.deleteChar(forward: true, count: 5), short, caret: 1), to: short), "a\ncd")
    }

    func testDeleteCharBackwardsStopsAtTheStartOfTheLine() {
        let short = "ab\ncd"
        XCTAssertEqual(applied(run(.deleteChar(forward: false, count: 5), short, caret: 4), to: short), "ab\nd")
    }

    func testReplaceCharRefusesWhenTheLineIsTooShort() {
        XCTAssertTrue(run(.replaceChar("X", count: 99), sql, caret: 0).beep)
        XCTAssertEqual(applied(run(.replaceChar("X", count: 2), sql, caret: 0), to: sql),
                       "XXLECT id, name\nFROM users\nWHERE id = 3;")
    }

    func testSubstituteCharDeletesAndEntersInsert() {
        let outcome = run(.substituteChar(count: 1), sql, caret: 0)
        XCTAssertEqual(applied(outcome, to: sql), "ELECT id, name\nFROM users\nWHERE id = 3;")
        XCTAssertEqual(outcome.mode, .insert)
    }

    func testToggleCase() {
        let outcome = run(.toggleCase(count: 6), sql, caret: 0)
        XCTAssertEqual(applied(outcome, to: sql), "select id, name\nFROM users\nWHERE id = 3;")
    }

    func testToggleCaseLeavesCharactersThatDoNotMapOneToOne() {
        // "ß" uppercases to "SS" and "ﬁ" to "FI" — two characters each. vim
        // leaves them alone, and building a Character from them would trap.
        let tricky = "ß ﬁ x"
        XCTAssertEqual(applied(run(.toggleCase(count: 5), tricky, caret: 0), to: tricky), "ß ﬁ X")
    }

    func testToggleCaseHandlesTurkishLetters() {
        XCTAssertEqual(applied(run(.toggleCase(count: 2), "ıi", caret: 0), to: "ıi"), "II")
        XCTAssertFalse(run(.toggleCase(count: 1), "İ", caret: 0).beep)
    }

    func testJoinUsesOneSpaceAndDropsIndentation() {
        let indented = "SELECT 1\n    FROM t\nWHERE x"
        let outcome = run(.joinLines(count: 1), indented, caret: 0)
        XCTAssertEqual(applied(outcome, to: indented), "SELECT 1 FROM t\nWHERE x")
        XCTAssertEqual(outcome.caret, 8)
    }

    func testJoinWithACountJoinsSeveralLines() {
        let indented = "SELECT 1\n    FROM t\nWHERE x"
        XCTAssertEqual(applied(run(.joinLines(count: 3), indented, caret: 0), to: indented), "SELECT 1 FROM t WHERE x")
    }

    func testJoinOnTheLastLineFails() {
        XCTAssertTrue(run(.joinLines(count: 1), sql, caret: 30).beep)
    }

    func testOpenBelowKeepsTheIndentation() {
        let indented = "SELECT 1\n    FROM t\nWHERE x"
        let outcome = run(.enterInsert(.openBelow, count: 1), indented, caret: 12)
        XCTAssertEqual(applied(outcome, to: indented), "SELECT 1\n    FROM t\n    \nWHERE x")
        XCTAssertEqual(outcome.mode, .insert)
    }

    func testOpenAboveKeepsTheIndentation() {
        let indented = "SELECT 1\n    FROM t\nWHERE x"
        let outcome = run(.enterInsert(.openAbove, count: 1), indented, caret: 12)
        XCTAssertEqual(applied(outcome, to: indented), "SELECT 1\n    \n    FROM t\nWHERE x")
        XCTAssertEqual(outcome.caret, 13)
    }

    func testAppendMovesPastTheCaretButNotPastTheLineBreak() {
        XCTAssertEqual(run(.enterInsert(.afterCursor, count: 1), sql, caret: 0).caret, 1)
        XCTAssertEqual(run(.enterInsert(.afterCursor, count: 1), sql, caret: 15).caret, 15)
        XCTAssertEqual(run(.enterInsert(.endOfLine, count: 1), sql, caret: 0).caret, 15)
    }

    // MARK: - Cursor movement

    func testNormalModeCaretNeverSitsOnTheLineBreak() {
        XCTAssertEqual(run(.move(.lineEnd, count: 1), sql, caret: 0).caret, 14)
        XCTAssertEqual(run(.move(.charRight, count: 99), sql, caret: 0).caret, 14)
    }

    func testVerticalMovementUsesBufferLinesAndRemembersTheColumn() {
        // A soft-wrapped line is still one buffer line: j must not move by a
        // screen row.
        let ragged = "SELECT abcdef\nOK\nSELECT abcdef"
        let down = run(.move(.lineDown, count: 1), ragged, caret: 10)
        XCTAssertEqual(down.caret, 15)
        XCTAssertEqual(down.desiredColumn, 10)

        let further = run(.move(.lineDown, count: 1), ragged, caret: 15, desiredColumn: 10)
        XCTAssertEqual(further.caret, 27)
    }

    func testVerticalMovementStopsAtTheEndsOfTheBuffer() {
        XCTAssertEqual(run(.move(.lineUp, count: 5), sql, caret: 3).caret, 3)
        XCTAssertEqual(run(.move(.lineDown, count: 5), sql, caret: 3).caret, 30)
    }

    func testWordMotions() {
        XCTAssertEqual(run(.move(.wordForward(big: false), count: 1), sql, caret: 0).caret, 7)
        XCTAssertEqual(run(.move(.wordForward(big: false), count: 2), sql, caret: 0).caret, 9)
        XCTAssertEqual(run(.move(.wordBackward(big: false), count: 1), sql, caret: 11).caret, 9)
        XCTAssertEqual(run(.move(.wordEnd(big: false), count: 1), sql, caret: 0).caret, 5)
    }

    func testBigWordMotionsSkipPunctuation() {
        let dotted = "db.table.field next"
        XCTAssertEqual(run(.move(.wordForward(big: true), count: 1), dotted, caret: 0).caret, 15)
        XCTAssertEqual(run(.move(.wordForward(big: false), count: 1), dotted, caret: 0).caret, 2)
    }

    func testFileStartAndEndLandOnTheFirstNonBlank() {
        let indented = "  SELECT 1\nFROM t\n   WHERE x"
        XCTAssertEqual(run(.move(.fileStart, count: 1), indented, caret: 20).caret, 2)
        XCTAssertEqual(run(.move(.fileEnd, count: 1), indented, caret: 0).caret, 21)
    }

    func testReturnAndPlusLandOnTheFirstNonBlankOfTheNextLine() {
        let indented = "SELECT 1\n    FROM t\nWHERE x"
        XCTAssertEqual(run(.move(.nextLineFirstNonBlank, count: 1), indented, caret: 2).caret, 13)
        XCTAssertEqual(run(.move(.nextLineFirstNonBlank, count: 2), indented, caret: 2).caret, 20)
        XCTAssertEqual(run(.move(.previousLineFirstNonBlank, count: 1), indented, caret: 22).caret, 13)
        // Already on the last line: the caret stays put.
        XCTAssertEqual(run(.move(.nextLineFirstNonBlank, count: 1), indented, caret: 22).caret, 20)
    }

    func testReturnIsALinewiseOperatorTarget() {
        let outcome = run(.operate(.delete, .motion(.nextLineFirstNonBlank), count: 1), sql, caret: 3)
        XCTAssertEqual(applied(outcome, to: sql), "WHERE id = 3;")
        XCTAssertEqual(outcome.register?.isLinewise, true)
    }

    func testLinewiseOperatorIncludesTheLineTheMotionLandsOn() {
        // The target of `2G` is the first character of line 2, and that line
        // must still be deleted whole.
        let outcome = run(.operate(.delete, .motion(.goToLine(2)), count: 1), sql, caret: 3)
        XCTAssertEqual(applied(outcome, to: sql), "WHERE id = 3;")
    }

    func testGoToLine() {
        XCTAssertEqual(run(.move(.goToLine(2), count: 1), sql, caret: 0).caret, 16)
        XCTAssertTrue(run(.move(.goToLine(99), count: 1), sql, caret: 0).beep)
    }

    func testFindCharacterStaysOnTheLine() {
        XCTAssertEqual(run(.move(.findChar(",", forward: true, till: false), count: 1), sql, caret: 0).caret, 9)
        XCTAssertEqual(run(.move(.findChar(",", forward: true, till: true), count: 1), sql, caret: 0).caret, 8)
        XCTAssertTrue(run(.move(.findChar("z", forward: true, till: false), count: 1), sql, caret: 0).beep)
        // "F" must not reach back into the previous line.
        XCTAssertTrue(run(.move(.findChar("S", forward: false, till: false), count: 1), sql, caret: 20).beep)
    }

    func testMatchingBracket() {
        let parens = "SELECT COUNT(id, name) FROM t"
        XCTAssertEqual(run(.move(.matchingBracket, count: 1), parens, caret: 12).caret, 21)
        XCTAssertEqual(run(.move(.matchingBracket, count: 1), parens, caret: 21).caret, 12)
        XCTAssertEqual(run(.move(.matchingBracket, count: 1), parens, caret: 0).caret, 21)
    }

    func testNestedBracketsMatchTheRightOne() {
        let nested = "f(g(x), y)"
        XCTAssertEqual(run(.move(.matchingBracket, count: 1), nested, caret: 1).caret, 9)
        XCTAssertEqual(run(.move(.matchingBracket, count: 1), nested, caret: 3).caret, 5)
    }

    func testParagraphMotions() {
        let paragraphs = "one\ntwo\n\nthree\nfour\n\nfive"
        XCTAssertEqual(run(.move(.paragraphForward, count: 1), paragraphs, caret: 0).caret, 8)
        XCTAssertEqual(run(.move(.paragraphForward, count: 2), paragraphs, caret: 0).caret, 20)
        XCTAssertEqual(run(.move(.paragraphBackward, count: 1), paragraphs, caret: 22).caret, 20)
    }

    // MARK: - Search

    func testSearchMovesToTheNextMatchAndWrapsAround() {
        XCTAssertEqual(run(.search(pattern: "id", forward: true), sql, caret: 0).caret, 7)
        XCTAssertEqual(run(.search(pattern: "id", forward: true), sql, caret: 7).caret, 33)
        // Past the last match, the search starts over at the top.
        XCTAssertEqual(run(.search(pattern: "id", forward: true), sql, caret: 34).caret, 7)
    }

    func testBackwardSearch() {
        // The caret sits inside the "id" at 33; that match starts before the
        // caret, so it is the one a backward search lands on.
        XCTAssertEqual(run(.search(pattern: "id", forward: false), sql, caret: 34).caret, 33)
        XCTAssertEqual(run(.search(pattern: "id", forward: false), sql, caret: 33).caret, 7)
    }

    func testRepeatSearchUsesTheStoredDirection() {
        let forward = run(.repeatSearch(reverse: false, count: 1), sql, caret: 0, lastSearch: ("users", true))
        XCTAssertEqual(forward.caret, 21)
        let reversed = run(.repeatSearch(reverse: true, count: 1), sql, caret: 30, lastSearch: ("id", true))
        XCTAssertEqual(reversed.caret, 7)
    }

    func testRepeatSearchWithoutAPreviousSearchFails() {
        XCTAssertTrue(run(.repeatSearch(reverse: false, count: 1), sql, caret: 0).beep)
    }

    func testSearchThatFindsNothingFails() {
        XCTAssertTrue(run(.search(pattern: "zzz", forward: true), sql, caret: 0).beep)
    }

    // MARK: - Visual mode

    func testVisualModeStartsWithASingleCharacterSelected() {
        let outcome = run(.enterVisual(line: false), sql, caret: 3)
        XCTAssertEqual(outcome.selection, NSRange(location: 3, length: 1))
        XCTAssertEqual(outcome.mode, .visual)
    }

    func testVisualLineModeSelectsTheWholeLine() {
        let outcome = run(.enterVisual(line: true), sql, caret: 17)
        XCTAssertEqual(outcome.selection, NSRange(location: 16, length: 11))
    }

    func testMotionInVisualModeExtendsTheSelection() {
        let outcome = run(.move(.wordForward(big: false), count: 1), sql,
                          caret: 0, mode: .visual, selection: NSRange(location: 0, length: 1))
        XCTAssertEqual(outcome.selection, NSRange(location: 0, length: 8))
    }

    func testVisualLineSelectionIncludesTheLineTheCaretMovesTo() {
        // The caret lands on the first character of line 2, which must be part
        // of the selection rather than just its boundary.
        let outcome = run(.move(.lineDown, count: 1), sql,
                          caret: 0, mode: .visualLine, selection: NSRange(location: 0, length: 16))
        XCTAssertEqual(outcome.selection, NSRange(location: 0, length: 27))
    }

    func testRepeatedMotionsKeepExtendingTheVisualSelection() {
        // The caret in visual mode is the moving end of the selection, so a
        // second `w` starts from where the first one stopped.
        let first = run(.move(.wordForward(big: false), count: 1), sql,
                        caret: 0, mode: .visual, selection: NSRange(location: 0, length: 1))
        XCTAssertEqual(first.selection, NSRange(location: 0, length: 8))
        XCTAssertEqual(first.caret, 7)

        let second = run(.move(.wordForward(big: false), count: 1), sql,
                         caret: 7, mode: .visual, selection: NSRange(location: 0, length: 8), visualAnchor: 0)
        XCTAssertEqual(second.selection, NSRange(location: 0, length: 10))
        XCTAssertEqual(second.caret, 9)
    }

    func testVisualSelectionCanBeExtendedBackwardsPastTheAnchor() {
        let outcome = run(.move(.wordBackward(big: false), count: 1), sql,
                          caret: 11, mode: .visual, selection: NSRange(location: 11, length: 1), visualAnchor: 11)
        XCTAssertEqual(outcome.selection, NSRange(location: 9, length: 3))
        XCTAssertEqual(outcome.caret, 9)
    }

    func testEnteringVisualModeReportsItsAnchorAndHead() {
        let outcome = run(.enterVisual(line: false), sql, caret: 3)
        XCTAssertEqual(outcome.visualAnchor, 3)
        XCTAssertEqual(outcome.caret, 3)
    }

    func testOperatorInVisualModeUsesTheSelection() {
        let outcome = run(.operateSelection(.delete), sql,
                          caret: 0, mode: .visual, selection: NSRange(location: 0, length: 7))
        XCTAssertEqual(applied(outcome, to: sql), "id, name\nFROM users\nWHERE id = 3;")
        XCTAssertEqual(outcome.mode, .normal)
    }

    func testOperatorInVisualLineModeGrowsToWholeLines() {
        let outcome = run(.operateSelection(.delete), sql,
                          caret: 18, mode: .visualLine, selection: NSRange(location: 18, length: 3))
        XCTAssertEqual(applied(outcome, to: sql), "SELECT id, name\nWHERE id = 3;")
        XCTAssertEqual(outcome.register?.isLinewise, true)
    }

    // MARK: - Non-ASCII text
    //
    // NSTextView works in UTF-16, so a command must never split a surrogate
    // pair or land inside a multi-unit character.

    func testCommandsKeepUTF16OffsetsValidWithTurkishTextAndEmoji() {
        let turkish = "SELECT çğüşiöİ, 'emoji 🎉 burada'\nFROM tablo"

        let quoted = run(.operate(.delete, .textObject(.quoted("'", around: true)), count: 1), turkish, caret: 20)
        XCTAssertEqual(applied(quoted, to: turkish), "SELECT çğüşiöİ, \nFROM tablo")

        // The emoji is two UTF-16 units; x must take both.
        let emoji = run(.deleteChar(forward: true, count: 1), turkish, caret: 23)
        XCTAssertEqual(applied(emoji, to: turkish), "SELECT çğüşiöİ, 'emoji  burada'\nFROM tablo")

        let word = run(.operate(.change, .textObject(.word(big: false, around: false)), count: 1), turkish, caret: 8)
        XCTAssertEqual(applied(word, to: turkish), "SELECT , 'emoji 🎉 burada'\nFROM tablo")
    }

    func testEndOfLineMotionLandsOnTheStartOfAComposedCharacter() {
        let trailing = "SELECT 🎉"
        let outcome = run(.move(.lineEnd, count: 1), trailing, caret: 0)
        XCTAssertEqual(outcome.caret, 7)
        XCTAssertEqual(applied(run(.operate(.delete, .motion(.lineEnd), count: 1), trailing, caret: 7), to: trailing), "SELECT ")
    }

    func testHorizontalMotionsStepOverWholeCharacters() {
        let emoji = "😀x😀y"

        // `l` from the start clears the whole surrogate pair, not half of it.
        XCTAssertEqual(run(.move(.charRight, count: 1), emoji, caret: 0).caret, 2)
        XCTAssertEqual(run(.move(.charRight, count: 2), emoji, caret: 0).caret, 3)
        XCTAssertEqual(run(.move(.charLeft, count: 1), emoji, caret: 3).caret, 2)
        XCTAssertEqual(run(.move(.charLeft, count: 2), emoji, caret: 3).caret, 0)
    }

    func testDeleteRightTakesTheWholeCharacter() {
        let emoji = "😀x"
        XCTAssertEqual(applied(run(.operate(.delete, .motion(.charRight), count: 1), emoji, caret: 0), to: emoji), "x")
        XCTAssertEqual(applied(run(.operate(.delete, .motion(.charLeft), count: 1), emoji, caret: 2), to: emoji), "x")
    }

    func testVisualModeStartsOnAWholeCharacter() {
        let emoji = "😀x"
        XCTAssertEqual(run(.enterVisual(line: false), emoji, caret: 0).selection, NSRange(location: 0, length: 2))
        // And the selection the operator then sees covers the pair.
        XCTAssertEqual(applied(run(.operateSelection(.delete), emoji, caret: 0,
                                   mode: .visual, selection: NSRange(location: 0, length: 2)), to: emoji), "x")
    }

    func testVerticalMotionNeverLandsInsideACharacter() {
        // The remembered column is a UTF-16 offset, so it can point at the
        // second half of the emoji on the line below.
        let lines = "abc\n😀x"
        XCTAssertEqual(run(.move(.lineDown, count: 1), lines, caret: 1).caret, 4)
    }

    func testPasteAndReplaceLeaveTheCaretOnACharacterBoundary() {
        let pasted = run(.paste(after: false, count: 1), "ab", caret: 1,
                         register: SAVimRegister(text: "😀", isLinewise: false))
        XCTAssertEqual(applied(pasted, to: "ab"), "a😀b")
        XCTAssertEqual(pasted.caret, 1)

        let replaced = run(.replaceChar("😀", count: 1), "ab", caret: 0)
        XCTAssertEqual(applied(replaced, to: "ab"), "😀b")
        XCTAssertEqual(replaced.caret, 0)
    }

    // MARK: - Edge cases

    func testCommandsOnAnEmptyBufferDoNotCrash() {
        XCTAssertTrue(run(.operate(.delete, .motion(.wordForward(big: false)), count: 1), "", caret: 0).beep
                      || run(.operate(.delete, .motion(.wordForward(big: false)), count: 1), "", caret: 0).edit?.range.length == 0)
        XCTAssertEqual(run(.move(.lineDown, count: 1), "", caret: 0).caret, 0)
        XCTAssertTrue(run(.deleteChar(forward: true, count: 1), "", caret: 0).beep)
    }

    func testUndoAndRedoAreLeftToTheTextView() {
        XCTAssertNil(run(.undo(count: 1), sql, caret: 0).edit)
        XCTAssertNil(run(.redo(count: 1), sql, caret: 0).edit)
        XCTAssertFalse(run(.repeatLastChange(count: 1), sql, caret: 0).beep)
    }
}
