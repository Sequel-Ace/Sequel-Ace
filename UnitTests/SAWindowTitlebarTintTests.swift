//
//  SAWindowTitlebarTintTests.swift
//  Unit Tests
//
//  Pins the chrome decision behind "Show the connection colour as": no mode
//  fills the title bar (always the Claude bar colour over a transparent title
//  bar), Underline draws a 2pt line at the very bottom of the window chrome
//  (in the tab bar when it shows, else in a line accessory under the
//  toolbar, replacing the hairline), Name pill draws no line, and Tab
//  underline lines each chip - falling back to Underline with one tab.
//
//  The reset path is load-bearing: a window that loses its colour must end up
//  exactly as Off, with no stale line or pill.
//
//  Whether the chrome *looks* right is not testable here (no window server in
//  the test bundle) and is covered by the harness - same split as
//  SAWindowTitleBuilder, which pins the strings and not its ObjC caller.
//

import XCTest
import AppKit

final class SAWindowTitlebarTintTests: XCTestCase {

    private let rose = SAWindowTitlebarTintTests.srgb(0xF43F5E)

    private let dynamicColour = NSColor(name: NSColor.Name("testDynamic")) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
    }

    private static func srgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    private func tint(_ style: SAConnectionColourStyle, _ colour: NSColor?, tabs: Bool) -> SAWindowTitlebarTint {
        SAWindowTitlebarTint(style: style, favoriteColor: colour, tabBarVisible: tabs)
    }

    // MARK: - The title bar is never filled

    func testNoModeFillsTheTitleBar() {
        for style in SAConnectionColourStyle.allCases {
            for colour in [rose, nil] {
                for tabs in [true, false] {
                    let t = tint(style, colour, tabs: tabs)
                    let label = "\(style) colour \(colour != nil) tabs \(tabs)"
                    XCTAssertIdentical(t.backgroundColor, SAClaudeStyle.toolbarBackground, label)
                    XCTAssertTrue(t.titlebarAppearsTransparent, label)
                }
            }
        }
    }

    // MARK: - Off

    func testOffShowsNoColour() {
        for tabs in [true, false] {
            let t = tint(.off, rose, tabs: tabs)
            XCTAssertNil(t.bottomLine, "tabs \(tabs)")
            XCTAssertFalse(t.showsNamePill, "tabs \(tabs)")
            XCTAssertEqual(t.separatorStyle, .line, "tabs \(tabs)")
            XCTAssertEqual(t.tabLines, .accent, "tabs \(tabs)")
        }
    }

    // MARK: - Underline

    func testUnderlineWithOneTabUsesTheAccessoryLine() {
        let t = tint(.underline, rose, tabs: false)
        XCTAssertIdentical(t.bottomLine, rose)
        XCTAssertFalse(t.bottomLineInTabBar)
        XCTAssertEqual(t.separatorStyle, .none)
        XCTAssertFalse(t.showsNamePill)
        XCTAssertEqual(t.tabLines, .accent)
    }

    func testUnderlineDrawsInTheTabBarWhenItShows() {
        let t = tint(.underline, rose, tabs: true)
        XCTAssertIdentical(t.bottomLine, rose)
        XCTAssertTrue(t.bottomLineInTabBar)
        XCTAssertEqual(t.separatorStyle, .none)
        XCTAssertEqual(t.tabLines, .accent)
    }

    // MARK: - Name pill

    func testNamePillNeedsAColour() {
        for tabs in [true, false] {
            let coloured = tint(.namePill, rose, tabs: tabs)
            XCTAssertTrue(coloured.showsNamePill, "tabs \(tabs)")
            XCTAssertNil(coloured.bottomLine, "tabs \(tabs)")
            XCTAssertEqual(coloured.separatorStyle, .line, "tabs \(tabs)")
            XCTAssertEqual(coloured.tabLines, .accent, "tabs \(tabs)")

            XCTAssertFalse(tint(.namePill, nil, tabs: tabs).showsNamePill, "tabs \(tabs)")
        }
    }

    // MARK: - Tab underline

    func testTabUnderlineWithTabsLinesEachChip() {
        let t = tint(.tabUnderline, rose, tabs: true)
        XCTAssertNil(t.bottomLine)
        XCTAssertFalse(t.bottomLineInTabBar)
        XCTAssertEqual(t.separatorStyle, .line)
        XCTAssertFalse(t.showsNamePill)
        XCTAssertEqual(t.tabLines, .connection)
    }

    /// With one tab the tab bar is hidden, so there are no chips to line: the
    /// window shows the Underline line instead, until a second tab appears.
    func testTabUnderlineWithOneTabFallsBackToUnderline() {
        let tabUnderline = tint(.tabUnderline, rose, tabs: false)
        let underline = tint(.underline, rose, tabs: false)
        XCTAssertIdentical(tabUnderline.bottomLine, underline.bottomLine)
        XCTAssertEqual(tabUnderline.bottomLineInTabBar, underline.bottomLineInTabBar)
        XCTAssertEqual(tabUnderline.separatorStyle, underline.separatorStyle)
        XCTAssertEqual(tabUnderline.showsNamePill, underline.showsNamePill)
    }

    // MARK: - Losing the colour

    /// A window that loses its colour (disconnected, back to the connection
    /// screen, or a favourite without one) must look exactly like Off. Tab
    /// lines are left out: they only say how chips would be lined, and with
    /// one tab there are no chips.
    func testNoColourMatchesOffWithOneTab() {
        let off = tint(.off, nil, tabs: false)
        for style in [SAConnectionColourStyle.underline, .namePill, .tabUnderline] {
            let t = tint(style, nil, tabs: false)
            XCTAssertIdentical(t.backgroundColor, off.backgroundColor, "\(style)")
            XCTAssertEqual(t.titlebarAppearsTransparent, off.titlebarAppearsTransparent, "\(style)")
            XCTAssertEqual(t.separatorStyle, off.separatorStyle, "\(style)")
            XCTAssertNil(t.bottomLine, "\(style)")
            XCTAssertEqual(t.bottomLineInTabBar, off.bottomLineInTabBar, "\(style)")
            XCTAssertEqual(t.showsNamePill, off.showsNamePill, "\(style)")
        }
    }

    // MARK: - Chip lines

    func testChipLines() {
        typealias Tint = SAWindowTitlebarTint
        XCTAssertEqual(Tint.tabLines(for: .off), .accent)
        XCTAssertEqual(Tint.tabLines(for: .underline), .accent)
        XCTAssertEqual(Tint.tabLines(for: .namePill), .accent)
        XCTAssertEqual(Tint.tabLines(for: .tabUnderline), .connection)

        // Accent tab lines: only the selected chip, always in the accent.
        XCTAssertEqual(Tint.chipLine(isSelected: true, colour: rose, tabLines: .accent), .accent)
        XCTAssertEqual(Tint.chipLine(isSelected: true, colour: nil, tabLines: .accent), .accent)
        XCTAssertEqual(Tint.chipLine(isSelected: false, colour: rose, tabLines: .accent), .none)
        XCTAssertEqual(Tint.chipLine(isSelected: false, colour: nil, tabLines: .accent), .none)

        // Connection tab lines: every coloured chip in its colour; the selected
        // one falls back to the accent, the others to no line.
        XCTAssertEqual(Tint.chipLine(isSelected: true, colour: rose, tabLines: .connection), .colour(rose))
        XCTAssertEqual(Tint.chipLine(isSelected: true, colour: nil, tabLines: .connection), .accent)
        XCTAssertEqual(Tint.chipLine(isSelected: false, colour: rose, tabLines: .connection), .colour(rose))
        XCTAssertEqual(Tint.chipLine(isSelected: false, colour: nil, tabLines: .connection), .none)
    }

    /// The favourite colours are asset colours carrying a light/dark pair, so
    /// they have to reach the line unresolved or it would keep whichever
    /// appearance happened to be active when the window connected.
    func testLineColourIsPassedThroughUnresolved() {
        for (style, tabs) in [(SAConnectionColourStyle.underline, false), (.underline, true), (.tabUnderline, false)] {
            XCTAssertIdentical(tint(style, dynamicColour, tabs: tabs).bottomLine, dynamicColour, "\(style) tabs \(tabs)")
        }
        guard case .colour(let chip) = SAWindowTitlebarTint.chipLine(isSelected: false, colour: dynamicColour, tabLines: .connection) else {
            return XCTFail("a coloured chip gets a colour line")
        }
        XCTAssertIdentical(chip, dynamicColour)
    }
}

// MARK: - Show the connection colour as

/// The "Show the connection colour as" choice and its one-time migration from
/// the old "Colour the window" switch. Each test uses its own suite-named
/// `UserDefaults`, never the real domain.
final class SAConnectionColourStyleTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SAConnectionColourStyleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testResolveMigratesTheOldSwitch() {
        XCTAssertEqual(SAConnectionColourStyle.resolve(stored: nil, legacyEnabled: true), .underline)
        XCTAssertEqual(SAConnectionColourStyle.resolve(stored: nil, legacyEnabled: false), .off)
    }

    func testResolveKeepsAStoredChoice() {
        XCTAssertEqual(SAConnectionColourStyle.resolve(stored: NSNumber(value: 2), legacyEnabled: true), .namePill)
        XCTAssertEqual(SAConnectionColourStyle.resolve(stored: NSNumber(value: 3), legacyEnabled: false), .tabUnderline)
        XCTAssertEqual(SAConnectionColourStyle.resolve(stored: NSNumber(value: 0), legacyEnabled: true), .off)
    }

    func testResolveUnknownStoredValueIsOff() {
        XCTAssertEqual(SAConnectionColourStyle.resolve(stored: NSNumber(value: 7), legacyEnabled: true), .off)
        XCTAssertEqual(SAConnectionColourStyle.resolve(stored: "x", legacyEnabled: true), .off)
    }

    func testMigrateWritesOnce() {
        defaults.set(true, forKey: SAConnectionColourStyle.legacyKey)
        SAConnectionColourStyle.migrateIfNeeded(defaults)
        XCTAssertEqual(defaults.integer(forKey: SAConnectionColourStyle.defaultsKey), 1)

        defaults.set(false, forKey: SAConnectionColourStyle.legacyKey)
        SAConnectionColourStyle.migrateIfNeeded(defaults)
        XCTAssertEqual(defaults.integer(forKey: SAConnectionColourStyle.defaultsKey), 1)
        XCTAssertEqual(defaults.object(forKey: SAConnectionColourStyle.legacyKey) as? Bool, false,
                       "the legacy key is left alone")

        defaults.set(3, forKey: SAConnectionColourStyle.defaultsKey)
        SAConnectionColourStyle.migrateIfNeeded(defaults)
        XCTAssertEqual(defaults.integer(forKey: SAConnectionColourStyle.defaultsKey), 3)
        XCTAssertEqual(SAConnectionColourStyle.current(defaults), .tabUnderline)
    }

    func testMigrateWithoutLegacyWritesOff() {
        SAConnectionColourStyle.migrateIfNeeded(defaults)
        XCTAssertNotNil(defaults.object(forKey: SAConnectionColourStyle.defaultsKey))
        XCTAssertEqual(defaults.integer(forKey: SAConnectionColourStyle.defaultsKey), 0)
    }

    func testCurrentNeverWrites() {
        defaults.set(true, forKey: SAConnectionColourStyle.legacyKey)
        XCTAssertEqual(SAConnectionColourStyle.current(defaults), .underline)
        XCTAssertNil(defaults.object(forKey: SAConnectionColourStyle.defaultsKey))
    }
}
