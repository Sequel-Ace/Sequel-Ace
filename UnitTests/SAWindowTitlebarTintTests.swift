//
//  SAWindowTitlebarTintTests.swift
//  Unit Tests
//
//  Pins the chrome decision behind the connection-colour title bar (#1856).
//  The reset path is the load-bearing part: a tinted window has three
//  properties changed, and clearing the colour has to restore all three to
//  the Claude bar - a transparent title bar over
//  `SAClaudeStyle.toolbarBackground` with a line separator (no longer the
//  stock title bar).
//
//  The preference gate is pinned too: off is the default, and a window then
//  shows the Claude bar whatever colour the connection carries.
//
//  Whether the tint *looks* right, and whether it follows the selected tab,
//  is not testable here (no window server in the test bundle) and stays a
//  manual check - same split as SAWindowTitleBuilder, which pins the strings
//  and not its ObjC caller.
//

import XCTest
import AppKit

final class SAWindowTitlebarTintTests: XCTestCase {

    private let favoriteRed = NSColor(srgbRed: 0.894, green: 0.455, blue: 0.400, alpha: 1)

    // MARK: - A favourite colour tints the whole window top

    func testFavoriteColorMakesTheTitlebarTransparent() {
        let tint = SAWindowTitlebarTint(favoriteColor: favoriteRed, isEnabled: true)

        XCTAssertTrue(tint.titlebarAppearsTransparent)
    }

    func testFavoriteColorBecomesTheWindowBackground() {
        let tint = SAWindowTitlebarTint(favoriteColor: favoriteRed, isEnabled: true)

        XCTAssertEqual(tint.backgroundColor, favoriteRed)
    }

    func testFavoriteColorDropsTheTitlebarSeparator() {
        let tint = SAWindowTitlebarTint(favoriteColor: favoriteRed, isEnabled: true)

        XCTAssertEqual(tint.separatorStyle, .none)
    }

    /// The favourite colours are asset colours carrying a light/dark pair, so
    /// the colour has to reach the window unresolved or a tinted window would
    /// keep whichever appearance happened to be active when it connected.
    func testColorIsPassedThroughUnresolved() {
        let dynamic = NSColor(name: NSColor.Name("testDynamic")) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
        }

        let tint = SAWindowTitlebarTint(favoriteColor: dynamic, isEnabled: true)

        XCTAssertIdentical(tint.backgroundColor, dynamic)
    }

    // MARK: - No colour restores the Claude bar

    func testNilColorKeepsTheTitlebarTransparent() {
        let tint = SAWindowTitlebarTint(favoriteColor: nil, isEnabled: true)

        XCTAssertTrue(tint.titlebarAppearsTransparent)
    }

    func testNilColorUsesTheClaudeBarColour() {
        let tint = SAWindowTitlebarTint(favoriteColor: nil, isEnabled: true)

        XCTAssertIdentical(tint.backgroundColor, SAClaudeStyle.toolbarBackground)
    }

    func testNilColorDrawsALineSeparator() {
        let tint = SAWindowTitlebarTint(favoriteColor: nil, isEnabled: true)

        XCTAssertEqual(tint.separatorStyle, .line)
    }

    // MARK: - The preference gates the whole thing

    func testDisabledKeepsTheTitlebarTransparentEvenWithAFavoriteColor() {
        let tint = SAWindowTitlebarTint(favoriteColor: favoriteRed, isEnabled: false)

        XCTAssertTrue(tint.titlebarAppearsTransparent)
    }

    func testDisabledUsesTheClaudeBarEvenWithAFavoriteColor() {
        let tint = SAWindowTitlebarTint(favoriteColor: favoriteRed, isEnabled: false)

        XCTAssertIdentical(tint.backgroundColor, SAClaudeStyle.toolbarBackground)
    }

    func testDisabledDrawsALineSeparatorEvenWithAFavoriteColor() {
        let tint = SAWindowTitlebarTint(favoriteColor: favoriteRed, isEnabled: false)

        XCTAssertEqual(tint.separatorStyle, .line)
    }

    /// Off is the shipped default, so this is what an untouched install gets:
    /// identical chrome whether or not the connection has a colour.
    func testDisabledMatchesTheNoColorCaseExactly() {
        let colored = SAWindowTitlebarTint(favoriteColor: favoriteRed, isEnabled: false)
        let uncolored = SAWindowTitlebarTint(favoriteColor: nil, isEnabled: false)

        XCTAssertEqual(colored.titlebarAppearsTransparent, uncolored.titlebarAppearsTransparent)
        XCTAssertEqual(colored.backgroundColor, uncolored.backgroundColor)
        XCTAssertEqual(colored.separatorStyle, uncolored.separatorStyle)
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
