//
//  SAWindowTitlebarTintTests.swift
//  Unit Tests
//
//  Pins the chrome decision behind the connection-colour title bar (#1856).
//  The reset path is the load-bearing part: a tinted window has three
//  properties changed, and clearing the colour has to restore all three -
//  leaving `titlebarAppearsTransparent` on over `windowBackgroundColor`
//  produces a flat, non-standard title bar instead of the stock one.
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
        let tint = SAWindowTitlebarTint(favoriteColor: favoriteRed)

        XCTAssertTrue(tint.titlebarAppearsTransparent)
    }

    func testFavoriteColorBecomesTheWindowBackground() {
        let tint = SAWindowTitlebarTint(favoriteColor: favoriteRed)

        XCTAssertEqual(tint.backgroundColor, favoriteRed)
    }

    func testFavoriteColorDropsTheTitlebarSeparator() {
        let tint = SAWindowTitlebarTint(favoriteColor: favoriteRed)

        XCTAssertEqual(tint.separatorStyle, .none)
    }

    /// The favourite colours are asset colours carrying a light/dark pair, so
    /// the colour has to reach the window unresolved or a tinted window would
    /// keep whichever appearance happened to be active when it connected.
    func testColorIsPassedThroughUnresolved() {
        let dynamic = NSColor(name: NSColor.Name("testDynamic")) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
        }

        let tint = SAWindowTitlebarTint(favoriteColor: dynamic)

        XCTAssertIdentical(tint.backgroundColor, dynamic)
    }

    // MARK: - No colour restores the stock title bar

    func testNilColorRestoresAnOpaqueTitlebar() {
        let tint = SAWindowTitlebarTint(favoriteColor: nil)

        XCTAssertFalse(tint.titlebarAppearsTransparent)
    }

    func testNilColorRestoresTheWindowBackgroundColor() {
        let tint = SAWindowTitlebarTint(favoriteColor: nil)

        XCTAssertEqual(tint.backgroundColor, .windowBackgroundColor)
    }

    func testNilColorRestoresTheAutomaticSeparator() {
        let tint = SAWindowTitlebarTint(favoriteColor: nil)

        XCTAssertEqual(tint.separatorStyle, .automatic)
    }
}
