//
//  SAClaudeQueryInsertionTests.swift
//  Unit Tests
//

import XCTest

final class SAClaudeQueryInsertionTests: XCTestCase {

    private func insertion(_ query: String, into text: String, selected: NSRange? = nil) -> SAClaudeQueryInsertion {
        SAClaudeQueryInsertion.insertion(of: query, into: text, selectedRange: selected ?? NSRange(location: (text as NSString).length, length: 0))
    }

    /// The editor's text after the insertion, and where the caret goes (end of the query, before an added newline).
    private func apply(_ insertion: SAClaudeQueryInsertion, to text: String) -> (text: String, caret: Int) {
        let result = (text as NSString).replacingCharacters(in: insertion.range, with: insertion.text)
        return (result, insertion.range.location + (insertion.text as NSString).length - insertion.trailingNewlineLength)
    }

    func testEmptyEditorGetsTheQueryAlone() {
        let i = insertion("Q", into: "")
        XCTAssertEqual(i.text, "Q")
        XCTAssertEqual(i.range, NSRange(location: 0, length: 0))
        XCTAssertEqual(i.trailingNewlineLength, 0)
    }

    func testTextNotEndingInANewlineGetsOneBeforeTheQuery() {
        let i = insertion("Q", into: "A")
        XCTAssertEqual(i.text, "\nQ")
        XCTAssertEqual(i.range, NSRange(location: 1, length: 0))
        XCTAssertEqual(i.trailingNewlineLength, 0)
    }

    func testTextEndingInANewlineGetsNoExtraOne() {
        let i = insertion("Q", into: "A\n")
        XCTAssertEqual(i.text, "Q")
        XCTAssertEqual(i.range, NSRange(location: 2, length: 0))
    }

    func testSelectionInTheMiddleOfALineGoesOnItsOwnLine() {
        let i = insertion("Q", into: "ABCD", selected: NSRange(location: 1, length: 2))
        XCTAssertEqual(i.text, "\nQ\n")
        XCTAssertEqual(i.range, NSRange(location: 1, length: 2))
        XCTAssertEqual(i.trailingNewlineLength, 1)
        XCTAssertEqual(apply(i, to: "ABCD").text, "A\nQ\nD")
        XCTAssertEqual(apply(i, to: "ABCD").caret, 3)
    }

    /// The walkthrough's case: a whole line selected with its newline (a triple-click, or the line of a syntax error)
    /// replaced by a pick used to glue the query onto the next line: "\nQLINE2".
    func testSelectedWholeLineWithItsNewlineKeepsTheNextLineSeparate() {
        let text = "SELECT 0;\nSELECT id, userid FROM t;"
        let i = insertion("SELECT a LIMIT 5", into: text, selected: NSRange(location: 0, length: 10))
        XCTAssertEqual(i.text, "SELECT a LIMIT 5\n")
        XCTAssertEqual(apply(i, to: text).text, "SELECT a LIMIT 5\nSELECT id, userid FROM t;")
        XCTAssertEqual(apply(i, to: text).caret, 16)
    }

    func testSelectionBetweenNewlinesAddsNothing() {
        let text = "A\nB\nC"
        let i = insertion("Q", into: text, selected: NSRange(location: 2, length: 1))
        XCTAssertEqual(i.text, "Q")
        XCTAssertEqual(apply(i, to: text).text, "A\nQ\nC")
    }

    func testSelectionAtTheStartOfTheTextWithTextAfterIt() {
        let i = insertion("Q", into: "AB", selected: NSRange(location: 0, length: 1))
        XCTAssertEqual(i.text, "Q\n")
        XCTAssertEqual(apply(i, to: "AB").text, "Q\nB")
    }

    func testSelectionRunningToTheEndOfTheText() {
        let i = insertion("Q", into: "AB", selected: NSRange(location: 1, length: 1))
        XCTAssertEqual(i.text, "\nQ")
        XCTAssertEqual(apply(i, to: "AB").text, "A\nQ")
    }

    func testWholeTextSelectedIsReplacedByTheQueryAlone() {
        let i = insertion("Q", into: "AB", selected: NSRange(location: 0, length: 2))
        XCTAssertEqual(i.text, "Q")
        XCTAssertEqual(i.range, NSRange(location: 0, length: 2))
    }

    /// A caret without a selection doesn't choose the place: the query goes at the end of the text, as before.
    func testCaretWithoutSelectionAppendsAtTheEnd() {
        let i = insertion("Q", into: "AB\nCD", selected: NSRange(location: 1, length: 0))
        XCTAssertEqual(i.range, NSRange(location: 5, length: 0))
        XCTAssertEqual(i.text, "\nQ")
    }

    func testRepeatedPicksEachStartAnewLine() {
        var text = ""
        for query in ["SELECT 1 LIMIT 5", "SELECT id, userid", "SELECT 3"] {
            let i = insertion(query, into: text)
            text = apply(i, to: text).text
        }
        XCTAssertEqual(text, "SELECT 1 LIMIT 5\nSELECT id, userid\nSELECT 3")
    }

    func testRepeatedPicksIntoSelectionsEachStayOnTheirOwnLine() {
        var text = "one two three"
        var i = insertion("Q1", into: text, selected: NSRange(location: 4, length: 3))
        var applied = apply(i, to: text)
        text = applied.text
        XCTAssertEqual(text, "one \nQ1\n three")
        // The caret after the first pick has no length: the next pick goes at the end.
        i = insertion("Q2", into: text, selected: NSRange(location: applied.caret, length: 0))
        applied = apply(i, to: text)
        XCTAssertEqual(applied.text, "one \nQ1\n three\nQ2")
    }

    func testQueryWithItsOwnLeadingOrTrailingNewlineIsNotDoubled() {
        XCTAssertEqual(insertion("\nQ", into: "A").text, "\nQ")
        let i = insertion("Q\n", into: "ABCD", selected: NSRange(location: 1, length: 2))
        XCTAssertEqual(i.text, "\nQ\n")
        XCTAssertEqual(i.trailingNewlineLength, 0)
    }

    func testCarriageReturnsCountAsLineBreaks() {
        XCTAssertEqual(insertion("Q", into: "A\r\n").text, "Q")
        XCTAssertEqual(insertion("Q", into: "A\r\nB", selected: NSRange(location: 0, length: 1)).text, "Q")
    }

    func testRangesAreInUTF16Units() {
        let text = "😀"
        let i = insertion("Q", into: text)
        XCTAssertEqual(i.range, NSRange(location: 2, length: 0))
        XCTAssertEqual(i.text, "\nQ")
        let j = insertion("Q", into: "a😀b", selected: NSRange(location: 1, length: 2))
        XCTAssertEqual(apply(j, to: "a😀b").text, "a\nQ\nb")
    }

    func testSelectionPastTheEndIsClampedToTheText() {
        let i = insertion("Q", into: "AB", selected: NSRange(location: 1, length: 9))
        XCTAssertEqual(i.range, NSRange(location: 1, length: 1))
        let j = insertion("Q", into: "AB", selected: NSRange(location: 7, length: 2))
        XCTAssertEqual(j.range, NSRange(location: 2, length: 0))
        XCTAssertEqual(j.text, "\nQ")
        let k = insertion("Q", into: "AB", selected: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(k.range, NSRange(location: 2, length: 0))
    }

    func testEmptyQueryInsertsNothing() {
        let i = insertion("", into: "ABCD", selected: NSRange(location: 1, length: 2))
        XCTAssertEqual(i.text, "")
        XCTAssertEqual(i.trailingNewlineLength, 0)
    }
}
