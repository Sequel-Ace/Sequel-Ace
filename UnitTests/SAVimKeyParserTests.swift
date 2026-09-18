//
//  SAVimKeyParserTests.swift
//  Unit Tests
//
//  Created by Sequel Ace on September 17, 2026.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAVimKeyParserTests: XCTestCase {

    private var parser = SAVimKeyParser()

    override func setUp() {
        super.setUp()
        parser = SAVimKeyParser()
    }

    // MARK: - Helpers

    @discardableResult
    private func type(_ keys: String) -> SAVimParseResult {
        var result = SAVimParseResult.passthrough
        for key in keys {
            result = parser.handle(SAVimKeyStroke(character: key, keyCode: 0, shift: key.isUppercase))
        }
        return result
    }

    private func press(keyCode: UInt16, character: Character? = nil, control: Bool = false) -> SAVimParseResult {
        parser.handle(SAVimKeyStroke(character: character, keyCode: keyCode, control: control))
    }

    // MARK: - Motions

    func testBareMotionsCarryACountOfOne() {
        XCTAssertEqual(type("h"), .command(.move(.charLeft, count: 1)))
        XCTAssertEqual(type("w"), .command(.move(.wordForward(big: false), count: 1)))
        XCTAssertEqual(type("W"), .command(.move(.wordForward(big: true), count: 1)))
        XCTAssertEqual(type("$"), .command(.move(.lineEnd, count: 1)))
    }

    func testCountPrefixesAMotion() {
        XCTAssertEqual(type("12j"), .command(.move(.lineDown, count: 12)))
    }

    func testZeroIsAMotionButContinuesACountAlreadyStarted() {
        XCTAssertEqual(type("0"), .command(.move(.lineStart, count: 1)))
        XCTAssertEqual(type("10l"), .command(.move(.charRight, count: 10)))
    }

    func testGGRequiresBothKeys() {
        XCTAssertEqual(type("g"), .pending(display: "g"))
        XCTAssertEqual(type("g"), .command(.move(.fileStart, count: 1)))
    }

    func testGWithACountGoesToThatLine() {
        XCTAssertEqual(type("G"), .command(.move(.fileEnd, count: 1)))
        XCTAssertEqual(type("42G"), .command(.move(.goToLine(42), count: 1)))
    }

    func testFindCharWaitsForItsArgument() {
        XCTAssertEqual(type("f"), .pending(display: "f"))
        XCTAssertEqual(type(","), .command(.move(.findChar(",", forward: true, till: false), count: 1)))
    }

    func testSemicolonRepeatsTheLastFindAndCommaReversesIt() {
        type("fx")
        XCTAssertEqual(type(";"), .command(.move(.findChar("x", forward: true, till: false), count: 1)))
        XCTAssertEqual(type(","), .command(.move(.findChar("x", forward: false, till: false), count: 1)))
    }

    func testSemicolonWithoutAPriorFindIsRejected() {
        XCTAssertEqual(type(";"), .rejected)
    }

    // MARK: - Operators

    func testDoubledOperatorsActOnWholeLines() {
        XCTAssertEqual(type("dd"), .command(.operate(.delete, .wholeLines, count: 1)))
        XCTAssertEqual(type("yy"), .command(.operate(.yank, .wholeLines, count: 1)))
        XCTAssertEqual(type(">>"), .command(.operate(.shiftRight, .wholeLines, count: 1)))
    }

    func testOperatorCountAndMotionCountMultiply() {
        // vim: 2d3w deletes six words
        XCTAssertEqual(type("2d3w"), .command(.operate(.delete, .motion(.wordForward(big: false)), count: 6)))
        XCTAssertEqual(type("3dd"), .command(.operate(.delete, .wholeLines, count: 3)))
    }

    func testACountIsBoundedSoAHeldDigitCannotOverflowIt() {
        let digits = String(repeating: "9", count: 40)
        XCTAssertEqual(type(digits + "j"), .command(.move(.lineDown, count: SAVimKeyParser.maximumCount)))
    }

    func testTheProductOfTheTwoCountsIsBoundedToo() {
        XCTAssertEqual(type("9999d9999w"),
                       .command(.operate(.delete, .motion(.wordForward(big: false)), count: SAVimKeyParser.maximumCount)))
    }

    func testOperatorFollowedByADifferentOperatorIsRejected() {
        XCTAssertEqual(type("d"), .pending(display: "d"))
        XCTAssertEqual(type("y"), .rejected)
    }

    func testOperatorAcceptsATextObject() {
        XCTAssertEqual(type("ciw"), .command(.operate(.change, .textObject(.word(big: false, around: false)), count: 1)))
        // `c` left the parser in insert mode, where keys pass through.
        parser.setMode(.normal)
        XCTAssertEqual(type("da\""), .command(.operate(.delete, .textObject(.quoted("\"", around: true)), count: 1)))
        XCTAssertEqual(type("dib"), .command(.operate(.delete, .textObject(.bracketed(open: "(", around: false)), count: 1)))
        XCTAssertEqual(type("yiB"), .command(.operate(.yank, .textObject(.bracketed(open: "{", around: false)), count: 1)))
    }

    func testOperatorAcceptsAMultiKeyMotion() {
        XCTAssertEqual(type("dgg"), .command(.operate(.delete, .motion(.fileStart), count: 1)))
        XCTAssertEqual(type("d5G"), .command(.operate(.delete, .motion(.goToLine(5)), count: 1)))
        XCTAssertEqual(type("dfx"), .command(.operate(.delete, .motion(.findChar("x", forward: true, till: false)), count: 1)))
    }

    func testOperatorShorthands() {
        XCTAssertEqual(type("D"), .command(.operate(.delete, .motion(.lineEnd), count: 1)))
        XCTAssertEqual(type("C"), .command(.operate(.change, .motion(.lineEnd), count: 1)))
        parser.setMode(.normal)
        XCTAssertEqual(type("Y"), .command(.operate(.yank, .wholeLines, count: 1)))
    }

    func testAnUnknownTextObjectIsRejectedAndClearsTheOperator() {
        XCTAssertEqual(type("diz"), .rejected)
        XCTAssertEqual(type("x"), .command(.deleteChar(forward: true, count: 1)))
    }

    func testAGuardedRejectionClearsThePendingOperator() {
        // A mistyped key after an operator must not leave `d` armed: the motion
        // that follows it would delete instead of moving.
        for rejected in ["v", "V", "r", "u", ".", "/", "?"] {
            parser.reset()
            XCTAssertEqual(type("d"), .pending(display: "d"))
            XCTAssertEqual(type(rejected), .rejected, "\(rejected) after an operator")
            XCTAssertFalse(parser.hasPendingSequence, "\(rejected) left a pending sequence")
            XCTAssertEqual(type("w"), .command(.move(.wordForward(big: false), count: 1)),
                           "the motion after a rejected \(rejected)")
        }
    }

    func testARejectedRepeatFindClearsThePendingOperatorAndCount() {
        XCTAssertEqual(type("2d"), .pending(display: "2d"))
        XCTAssertEqual(type(";"), .rejected)
        XCTAssertFalse(parser.hasPendingSequence)
        XCTAssertEqual(type("w"), .command(.move(.wordForward(big: false), count: 1)))
    }

    // MARK: - Mode changes

    func testInsertKeysEnterInsertMode() {
        XCTAssertEqual(type("i"), .command(.enterInsert(.beforeCursor, count: 1)))
        XCTAssertEqual(parser.mode, .insert)
    }

    func testAEntersInsertModeWhenNoOperatorIsPending() {
        XCTAssertEqual(type("a"), .command(.enterInsert(.afterCursor, count: 1)))
        XCTAssertEqual(parser.mode, .insert)
    }

    func testInsertModePassesEverythingButEscapeThrough() {
        type("i")
        XCTAssertEqual(parser.handle(SAVimKeyStroke(character: "d", keyCode: 2)), .passthrough)
        XCTAssertEqual(parser.handle(SAVimKeyStroke(character: "3", keyCode: 20)), .passthrough)
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.escapeKeyCode), .command(.exitToNormal))
        XCTAssertEqual(parser.mode, .normal)
    }

    func testControlEscapeStaysWithTheEditorsFuzzyCompletion() {
        type("i")
        // ⌃ESC opens fuzzy completion; it must not be read as vim's Escape.
        XCTAssertEqual(parser.handle(SAVimKeyStroke(character: nil,
                                                    keyCode: SAVimKeyStroke.escapeKeyCode,
                                                    control: true)), .passthrough)
        XCTAssertEqual(parser.mode, .insert)

        parser.setMode(.normal)
        XCTAssertEqual(parser.handle(SAVimKeyStroke(character: nil,
                                                    keyCode: SAVimKeyStroke.escapeKeyCode,
                                                    control: true)), .passthrough)
        XCTAssertEqual(parser.mode, .normal)
    }

    func testControlBracketAlsoLeavesInsertMode() {
        type("i")
        XCTAssertEqual(parser.handle(SAVimKeyStroke(character: "[", keyCode: 33, control: true)), .command(.exitToNormal))
        XCTAssertEqual(parser.mode, .normal)
    }

    func testChangeOperatorLeavesTheParserInInsertMode() {
        type("cw")
        XCTAssertEqual(parser.mode, .insert)
    }

    func testVisualModeTogglesAndOperatorsActOnTheSelection() {
        XCTAssertEqual(type("v"), .command(.enterVisual(line: false)))
        XCTAssertEqual(parser.mode, .visual)
        XCTAssertEqual(type("j"), .command(.move(.lineDown, count: 1)))
        XCTAssertEqual(type("d"), .command(.operateSelection(.delete)))
        XCTAssertEqual(parser.mode, .normal)
    }

    func testVisualLineMode() {
        XCTAssertEqual(type("V"), .command(.enterVisual(line: true)))
        XCTAssertEqual(type("V"), .command(.exitToNormal))
        XCTAssertEqual(parser.mode, .normal)
    }

    func testTextObjectInVisualModeBecomesASelection() {
        type("v")
        XCTAssertEqual(type("iw"), .command(.selectTextObject(.word(big: false, around: false))))
    }

    // MARK: - Single-key edits

    func testSingleKeyEdits() {
        XCTAssertEqual(type("x"), .command(.deleteChar(forward: true, count: 1)))
        XCTAssertEqual(type("3X"), .command(.deleteChar(forward: false, count: 3)))
        XCTAssertEqual(type("p"), .command(.paste(after: true, count: 1)))
        XCTAssertEqual(type("2P"), .command(.paste(after: false, count: 2)))
        XCTAssertEqual(type("J"), .command(.joinLines(count: 1)))
        XCTAssertEqual(type("~"), .command(.toggleCase(count: 1)))
        XCTAssertEqual(type("u"), .command(.undo(count: 1)))
        XCTAssertEqual(type("."), .command(.repeatLastChange(count: 1)))
    }

    func testReplaceCharWaitsForItsArgument() {
        XCTAssertEqual(type("2r"), .pending(display: "2r"))
        XCTAssertEqual(type("z"), .command(.replaceChar("z", count: 2)))
    }

    func testControlRIsRedoAndOtherControlKeysPassThrough() {
        XCTAssertEqual(parser.handle(SAVimKeyStroke(character: "r", keyCode: 15, control: true)), .command(.redo(count: 1)))
        XCTAssertEqual(parser.handle(SAVimKeyStroke(character: "a", keyCode: 0, control: true)), .passthrough)
    }

    func testCommandKeyEventsAlwaysPassThrough() {
        XCTAssertEqual(parser.handle(SAVimKeyStroke(character: "d", keyCode: 2, command: true)), .passthrough)
    }

    func testArrowAndPageKeysStillPassThrough() {
        for keyCode: UInt16 in [123, 124, 125, 126, 115, 116, 119, 121] {
            XCTAssertEqual(parser.handle(SAVimKeyStroke(character: nil, keyCode: keyCode)), .passthrough)
        }
    }

    // MARK: - Keys that would otherwise edit the text
    //
    // Return, Tab, Backspace and forward delete carry no character. Letting
    // them through in normal mode would insert a line break, expand a tab
    // trigger or delete text.

    func testReturnMovesToTheNextLineInsteadOfInsertingOne() {
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.returnKeyCode), .command(.move(.nextLineFirstNonBlank, count: 1)))
        XCTAssertEqual(type("3"), .pending(display: "3"))
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.returnKeyCode), .command(.move(.nextLineFirstNonBlank, count: 3)))
    }

    func testPlusAndMinusMoveByWholeLines() {
        XCTAssertEqual(type("+"), .command(.move(.nextLineFirstNonBlank, count: 1)))
        XCTAssertEqual(type("2-"), .command(.move(.previousLineFirstNonBlank, count: 2)))
    }

    func testBackspaceMovesLeftInNormalMode() {
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.backspaceKeyCode), .command(.move(.charLeft, count: 1)))
    }

    func testForwardDeleteRemovesACharacter() {
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.forwardDeleteKeyCode), .command(.deleteChar(forward: true, count: 1)))
    }

    func testTabIsSwallowedRatherThanExpandingATabTrigger() {
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.tabKeyCode), .rejected)
    }

    func testKeypadEnterAndControlReturnStillRunTheQuery() {
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.keypadEnterKeyCode), .passthrough)
        XCTAssertEqual(parser.handle(SAVimKeyStroke(character: nil,
                                                    keyCode: SAVimKeyStroke.returnKeyCode,
                                                    control: true)), .passthrough)
    }

    func testReturnAfterAnOperatorIsALinewiseTarget() {
        XCTAssertEqual(type("d"), .pending(display: "d"))
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.returnKeyCode),
                       .command(.operate(.delete, .motion(.nextLineFirstNonBlank), count: 1)))
    }

    func testColonIsReportedAsUnsupported() {
        XCTAssertEqual(type(":"), .command(.unsupported(":")))
    }

    // MARK: - Pending state

    func testEscapeCancelsAHalfTypedSequenceWithoutLeavingACount() {
        XCTAssertEqual(type("2"), .pending(display: "2"))
        XCTAssertEqual(type("d"), .pending(display: "2d"))
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.escapeKeyCode), .cancelled)
        XCTAssertFalse(parser.hasPendingSequence)
        // The abandoned "2d" must not colour the next command.
        XCTAssertEqual(type("dd"), .command(.operate(.delete, .wholeLines, count: 1)))
    }

    func testAbortedGSequenceDoesNotLeaveDeleteArmed() {
        XCTAssertEqual(type("dg"), .pending(display: "dg"))
        XCTAssertEqual(type("z"), .rejected)
        XCTAssertEqual(type("w"), .command(.move(.wordForward(big: false), count: 1)))
    }

    func testPendingDisplayShowsTheSequenceSoFar() {
        type("2d")
        XCTAssertEqual(parser.pendingDisplay, "2d")
    }

    // MARK: - Search entry

    func testSearchCollectsAPatternAndCommitsOnReturn() {
        XCTAssertEqual(type("/"), .pending(display: "/"))
        XCTAssertEqual(type("us"), .pending(display: "/us"))
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.returnKeyCode), .command(.search(pattern: "us", forward: true)))
    }

    func testBackwardSearchUsesItsOwnPrompt() {
        type("?ab")
        XCTAssertEqual(parser.pendingDisplay, "?ab")
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.returnKeyCode), .command(.search(pattern: "ab", forward: false)))
    }

    func testBackspaceShortensThePatternAndEmptyingItCancels() {
        type("/ab")
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.backspaceKeyCode), .pending(display: "/a"))
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.backspaceKeyCode), .pending(display: "/"))
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.backspaceKeyCode), .cancelled)
    }

    func testEscapeAbandonsASearch() {
        type("/abc")
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.escapeKeyCode), .cancelled)
        XCTAssertEqual(type("x"), .command(.deleteChar(forward: true, count: 1)))
    }

    func testSearchDigitsAreTextNotACount() {
        type("/t1")
        XCTAssertEqual(press(keyCode: SAVimKeyStroke.returnKeyCode), .command(.search(pattern: "t1", forward: true)))
    }

    func testRepeatSearchKeys() {
        XCTAssertEqual(type("n"), .command(.repeatSearch(reverse: false, count: 1)))
        XCTAssertEqual(type("2N"), .command(.repeatSearch(reverse: true, count: 2)))
    }

    // MARK: - Keyboard layouts

    func testALayoutThatProducesASCIIKeepsItsOwnCharacter() {
        // Turkish Q and F both print ASCII letters, so vim keys land normally.
        XCTAssertEqual(SAVimKeyStroke(characters: "d", keyCode: 2).character, "d")
        XCTAssertEqual(SAVimKeyStroke(characters: "$", keyCode: 21, shift: true).character, "$")
    }

    func testANonLatinLayoutFallsBackToTheUSKeyPosition() {
        // Cyrillic "в" sits on the US "d" key.
        XCTAssertEqual(SAVimKeyStroke(characters: "в", keyCode: 2).character, "d")
        XCTAssertEqual(SAVimKeyStroke(characters: "В", keyCode: 2, shift: true).character, "D")
    }

    func testControlCharactersDoNotCountAsTypedText() {
        // Ctrl-[ reports ESC as its character; the key position must win.
        XCTAssertEqual(SAVimKeyStroke(characters: "\u{1B}", keyCode: 33, control: true).character, "[")
    }

    func testSetModeClearsAnyPendingSequence() {
        type("2d")
        parser.setMode(.normal)
        XCTAssertFalse(parser.hasPendingSequence)
        XCTAssertEqual(parser.pendingDisplay, "")
    }
}
