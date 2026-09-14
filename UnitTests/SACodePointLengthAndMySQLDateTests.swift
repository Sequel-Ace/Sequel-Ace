//
//  SACodePointLengthAndMySQLDateTests.swift
//  Unit Tests
//
//  Created by Sequel-Ace contributors on 2026.09.14.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SACodePointLengthTests: XCTestCase {

    /// Verifies the length is counted in code points, as MySQL counts a
    /// column's characters: a decomposed `é` is two, a family emoji five,
    /// and a supplementary-plane emoji one although it takes two UTF-16 units.
    func testCharacterCountCountsCodePoints() {
        XCTAssertEqual(("caf\u{E9}" as NSString).characterCount(), 4)
        XCTAssertEqual(("cafe\u{301}" as NSString).characterCount(), 5)
        XCTAssertEqual(("\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}" as NSString).characterCount(), 5)
        XCTAssertEqual(("\u{1F642}" as NSString).characterCount(), 1)
        XCTAssertEqual(("\u{1F642}" as NSString).length, 2, "one code point, two UTF-16 units")
        XCTAssertEqual(("" as NSString).characterCount(), 0)
    }

    /// Verifies the UTF-16 length of a code-point prefix stops between code
    /// points - two code points of `a🙂b` are three UTF-16 units - and that
    /// a count beyond the end, or below zero, is clamped.
    func testUTF16LengthOfCodePointPrefix() {
        let mixed = "a\u{1F642}b" as NSString
        XCTAssertEqual(mixed.utf16Length(ofFirstCodePoints: 0), 0)
        XCTAssertEqual(mixed.utf16Length(ofFirstCodePoints: 1), 1)
        XCTAssertEqual(mixed.utf16Length(ofFirstCodePoints: 2), 3)
        XCTAssertEqual(mixed.utf16Length(ofFirstCodePoints: 3), 4)
        XCTAssertEqual(mixed.utf16Length(ofFirstCodePoints: 10), 4)
        XCTAssertEqual(mixed.utf16Length(ofFirstCodePoints: -1), 0)
        XCTAssertEqual(("cafe\u{301}" as NSString).utf16Length(ofFirstCodePoints: 4), 4)
    }

    /// Verifies truncation keeps whole code points: cutting `a🙂b` to two
    /// code points yields `a🙂`, never a lone surrogate, and a decomposed
    /// accent is dropped with its base when the limit falls before it.
    func testPrefixOfCodePointsNeverSplitsASurrogatePair() {
        let mixed = "a\u{1F642}b" as NSString
        XCTAssertEqual(mixed.prefix(codePoints: 2) as String, "a\u{1F642}")
        XCTAssertEqual(mixed.prefix(codePoints: 1) as String, "a")
        XCTAssertEqual(mixed.prefix(codePoints: 3) as String, "a\u{1F642}b")
        XCTAssertEqual(mixed.prefix(codePoints: 99) as String, "a\u{1F642}b")
        XCTAssertFalse((mixed.prefix(codePoints: 2) as String).unicodeScalars.contains("\u{FFFD}"))
        XCTAssertEqual(("cafe\u{301}" as NSString).prefix(codePoints: 4) as String, "cafe")
        XCTAssertEqual(("\u{1F469}\u{200D}\u{1F469}" as NSString).prefix(codePoints: 2) as String, "\u{1F469}\u{200D}")
    }
}

/// The length rules a table cell applies while a value is typed or pasted,
/// decided by `textLimitDecision(limit:nullValue:)` and applied by
/// `SPDataCellFormatter`.
///
/// Not covered here: a BIT cell given a limit would also run the formatter's
/// 0/1-only check, which refuses "N", "NU" and "NUL" on the way to NULL. That
/// check lives in the Objective-C formatter, and it is why the table content
/// view gives BIT cells no limit.
final class SATextLimitDecisionTests: XCTestCase {

    private let nullValue = "NULL"

    /// Verifies five pasted emoji are cut to three whole code points, never
    /// half of a fourth surrogate pair.
    func testPastedEmojiAreCutAfterTheLimit() {
        let pasted = "\u{1F642}\u{1F642}\u{1F642}\u{1F642}\u{1F642}" as NSString
        XCTAssertEqual(pasted.textLimitDecision(limit: 3, nullValue: nullValue), .truncate)

        let cut = pasted.prefix(codePoints: 3)
        XCTAssertEqual(cut as String, "\u{1F642}\u{1F642}\u{1F642}")
        XCTAssertEqual(cut.length, 6, "three whole surrogate pairs, no half of a fourth")
    }

    /// Verifies a family emoji - one grapheme, five code points - counts as
    /// five and is cut between code points.
    func testAZeroWidthJoinerSequenceIsCutBetweenCodePoints() {
        let family = "\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}" as NSString
        XCTAssertEqual(family.textLimitDecision(limit: 3, nullValue: nullValue), .truncate)

        let cut = family.prefix(codePoints: 3)
        XCTAssertEqual(cut as String, "\u{1F469}\u{200D}\u{1F469}")
        XCTAssertFalse(UTF16.isLeadSurrogate(cut.character(at: cut.length - 1)))
    }

    /// Verifies one code point over the limit is refused, also when the
    /// graphemes would still fit (`e` + U+0301 + `ab`).
    func testOneCodePointOverTheLimitIsRefused() {
        XCTAssertEqual(("abcd" as NSString).textLimitDecision(limit: 3, nullValue: nullValue), .refuse)
        XCTAssertEqual(("e\u{301}ab" as NSString).textLimitDecision(limit: 3, nullValue: nullValue), .refuse)
    }

    /// Verifies text within the limit is accepted subject to the formatter's
    /// other checks, and the complete NULL placeholder is exempt.
    func testTextWithinTheLimitAndTheCompleteNullPlaceholder() {
        XCTAssertEqual(("\u{1F642}\u{1F642}\u{1F642}" as NSString).textLimitDecision(limit: 3, nullValue: nullValue), .withinLimit)
        XCTAssertEqual(("e\u{301}a" as NSString).textLimitDecision(limit: 3, nullValue: nullValue), .withinLimit)
        XCTAssertEqual(("NULL" as NSString).textLimitDecision(limit: 3, nullValue: nullValue), .exempt)
    }

    /// Verifies every step on the way to NULL passes a one-character column,
    /// although each is past its length.
    func testNullCanBeTypedStepByStepIntoAShortColumn() {
        for step in ["N", "NU", "NUL"] {
            XCTAssertEqual((step as NSString).textLimitDecision(limit: 1, nullValue: nullValue), .withinLimit, step)
        }
        XCTAssertEqual(("NULL" as NSString).textLimitDecision(limit: 1, nullValue: nullValue), .exempt)
    }

    /// Verifies no limit means no length rule at all.
    func testNoLimitExemptsAnyLength() {
        let pasted = "\u{1F642}\u{1F642}\u{1F642}\u{1F642}\u{1F642}" as NSString
        XCTAssertEqual(pasted.textLimitDecision(limit: 0, nullValue: nullValue), .exempt)
    }

    /// Verifies the rules without a NULL placeholder, as when the preference
    /// is unset: nothing is exempt, over-long text is refused or cut.
    func testWithoutANullPlaceholder() {
        XCTAssertEqual(("abcd" as NSString).textLimitDecision(limit: 3, nullValue: nil), .refuse)
        XCTAssertEqual(("abcdef" as NSString).textLimitDecision(limit: 3, nullValue: nil), .truncate)
        XCTAssertEqual(("" as NSString).textLimitDecision(limit: 3, nullValue: nil), .withinLimit)
    }
}

final class SAMySQLDateTimeTests: XCTestCase {

    private func expected(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    /// Verifies the parser is pinned to what MySQL prints - Gregorian, POSIX,
    /// UTC - so the system's calendar or time zone cannot change the reading.
    func testParserIsPinnedToGregorianPOSIXAndUTC() throws {
        let parser = DateFormatter.mysqlDateTimeParser
        XCTAssertEqual(parser.calendar.identifier, .gregorian)
        XCTAssertEqual(parser.locale.identifier, "en_US_POSIX")
        XCTAssertEqual(parser.timeZone.secondsFromGMT(), 0)

        let date = try XCTUnwrap(parser.date(from: "2020-06-30 14:14:11"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual([components.year, components.month, components.day, components.hour, components.minute, components.second], [2020, 6, 30, 14, 14, 11])
    }

    /// Verifies a MySQL date-time is shown as the wall time MySQL printed, in
    /// the requested styles, whatever the user's time zone.
    func testShowsTheWallTimeAsPrinted() {
        XCTAssertEqual(
            DateFormatter.mysqlDateTimeString("2020-06-30 14:14:11", dateStyle: .medium, timeStyle: .medium),
            expected(year: 2020, month: 6, day: 30, hour: 14, minute: 14, second: 11, dateStyle: .medium, timeStyle: .medium)
        )
        XCTAssertEqual(
            DateFormatter.mysqlDateTimeString("2020-06-30 14:14:11", dateStyle: .short, timeStyle: .none),
            expected(year: 2020, month: 6, day: 30, hour: 14, minute: 14, second: 11, dateStyle: .short, timeStyle: .none)
        )
    }

    /// Verifies a time that does not exist locally - 02:30 on the night the
    /// clocks go forward in Europe - is still read and shown as printed.
    func testATimeInsideADSTGapIsStillRead() {
        XCTAssertEqual(
            DateFormatter.mysqlDateTimeString("2026-03-29 02:30:00", dateStyle: .medium, timeStyle: .medium),
            expected(year: 2026, month: 3, day: 29, hour: 2, minute: 30, second: 0, dateStyle: .medium, timeStyle: .medium)
        )
    }

    /// Verifies a missing value - `nil`, a NULL from the server, or text that
    /// is not a date-time - gives an empty string rather than nothing, so a
    /// dictionary built with it is not cut short.
    func testMissingOrUnreadableValueGivesAnEmptyString() {
        XCTAssertEqual(DateFormatter.mysqlDateTimeString(nil, dateStyle: .short, timeStyle: .none), "")
        XCTAssertEqual(DateFormatter.mysqlDateTimeString(NSNull(), dateStyle: .short, timeStyle: .none), "")
        XCTAssertEqual(DateFormatter.mysqlDateTimeString("", dateStyle: .short, timeStyle: .none), "")
        XCTAssertEqual(DateFormatter.mysqlDateTimeString("not a date", dateStyle: .short, timeStyle: .none), "")
        XCTAssertEqual(DateFormatter.mysqlDateTimeString(42, dateStyle: .short, timeStyle: .none), "")
    }
}
