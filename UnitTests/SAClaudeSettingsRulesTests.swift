//
//  SAClaudeSettingsRulesTests.swift
//  Unit Tests
//

import AppKit
import XCTest

/// The Settings window's bespoke rows: the favourite pill's menu and writes, the encoding pill's selection, the updates
/// switch in App Store builds, the auto-complete delay warning, the colour rows shown, the font label.
final class SAClaudeSettingsRulesTests: XCTestCase {

    private typealias Rules = SAClaudeSettingsRules

    // MARK: - Favourite to select

    private let tree: [Rules.FavouriteNode] = [
        .favourite(name: "Local", id: 11),
        .group(name: "Work", children: [
            .favourite(name: "Staging", id: 22),
            .group(name: "Prod", children: [.favourite(name: "Primary", id: 33)]),
        ]),
        .favourite(name: "Local", id: 44),
    ]

    func testFavouriteMenuMirrorsTheOldPopUp() {
        let items = Rules.favouriteMenu(tree, lastUsedTitle: "Last used", noneTitle: "No favourites")
        XCTAssertEqual(items.map(\.title), ["Last used", "", "Local", "Work", "Staging", "Prod", "Primary", "Local"])
        XCTAssertEqual(items.map(\.indentation), [0, 0, 0, 0, 1, 1, 2, 0])
        XCTAssertEqual(items.map(\.kind), [.lastUsed, .separator, .favourite(id: 11), .heading, .favourite(id: 22), .heading,
                                           .favourite(id: 33), .favourite(id: 44)])
        XCTAssertEqual(items.map(\.isEnabled), [true, false, true, false, true, false, true, true], "groups are disabled headings")
    }

    func testFavouriteMenuWithNoFavourites() {
        let items = Rules.favouriteMenu([], lastUsedTitle: "Last used", noneTitle: "No favourites")
        XCTAssertEqual(items.map(\.title), ["Last used", "", "No favourites"])
        XCTAssertEqual(items.map(\.isEnabled), [true, false, false])
    }

    func testFavouriteSelectionFollowsTheTwoKeys() {
        let items = Rules.favouriteMenu(tree, lastUsedTitle: "Last used", noneTitle: "None")
        XCTAssertEqual(Rules.favouriteSelectedIndex(items, selectLastUsed: true, defaultFavorite: 33), 0, "Last used wins")
        XCTAssertEqual(Rules.favouriteSelectedIndex(items, selectLastUsed: false, defaultFavorite: 33), 6)
        XCTAssertEqual(Rules.favouriteSelectedIndex(items, selectLastUsed: false, defaultFavorite: 44), 7, "by id, not name")
        XCTAssertEqual(Rules.favouriteSelectedIndex(items, selectLastUsed: false, defaultFavorite: 99), 0,
                       "a deleted favourite shows Last used, as the rebuilt pop-up did")
        XCTAssertEqual(Rules.favouriteSelectedIndex(items, selectLastUsed: false, defaultFavorite: 0), 0)
    }

    func testFavouriteChoiceWritesWhatUpdateDefaultFavoriteWrote() {
        let items = Rules.favouriteMenu(tree, lastUsedTitle: "Last used", noneTitle: "None")
        let lastUsed = Rules.favouriteChoice(items, at: 0)
        XCTAssertEqual(lastUsed?.selectLastUsed, true)
        XCTAssertEqual(lastUsed?.defaultFavorite, 0)
        let primary = Rules.favouriteChoice(items, at: 6)
        XCTAssertEqual(primary?.selectLastUsed, false)
        XCTAssertEqual(primary?.defaultFavorite, 33)
        XCTAssertNil(Rules.favouriteChoice(items, at: 1), "separator")
        XCTAssertNil(Rules.favouriteChoice(items, at: 3), "group heading")
        XCTAssertNil(Rules.favouriteChoice(items, at: 99))
    }

    // MARK: - Character set

    func testTagSelection() {
        // Autodetect, separator, ucs2, utf8, utf8mb4 (Preferences.xib's first items).
        let tags: [Int?] = [0, nil, 10, 20, 190]
        XCTAssertEqual(Rules.selectedIndex(tags: tags, stored: 0), 0)
        XCTAssertEqual(Rules.selectedIndex(tags: tags, stored: 190), 4)
        XCTAssertNil(Rules.selectedIndex(tags: tags, stored: 77))
    }

    // MARK: - Updates

    func testUpdatesSwitchIsGatedInAppStoreBuilds() {
        XCTAssertEqual(Rules.updatesSwitch(isAppStore: true, stored: true),
                       .init(isEnabled: false, isOn: false, showsNote: true), "disabled, shown off, with the note")
        XCTAssertEqual(Rules.updatesSwitch(isAppStore: true, stored: false),
                       .init(isEnabled: false, isOn: false, showsNote: true))
        XCTAssertEqual(Rules.updatesSwitch(isAppStore: false, stored: true), .init(isEnabled: true, isOn: true, showsNote: false))
        XCTAssertEqual(Rules.updatesSwitch(isAppStore: false, stored: false), .init(isEnabled: true, isOn: false, showsNote: false))
    }

    // MARK: - Auto-complete delay

    func testDelayWarningAtZeroOnly() {
        XCTAssertTrue(Rules.showsAutoCompleteDelayWarning(0))
        XCTAssertTrue(Rules.showsAutoCompleteDelayWarning(0.05))
        XCTAssertFalse(Rules.showsAutoCompleteDelayWarning(0.1))
        XCTAssertFalse(Rules.showsAutoCompleteDelayWarning(1.5))
    }

    // MARK: - Colours

    func testColourRowsShownOnlyWhileCustom() {
        let section = try? XCTUnwrap(SAClaudeSettingsCatalog.panes.first { $0.id == .appearance }?
            .sections.first { $0.id == "editorGridColours" })
        let ids = section?.rows.map(\.id) ?? []
        XCTAssertEqual(ids, ["editorColours", "startFromTheme", "colourList"])
        XCTAssertEqual(Rules.colourSectionRowIDs(ids, followsAppearance: true), ["editorColours"])
        XCTAssertEqual(Rules.colourSectionRowIDs(ids, followsAppearance: false), ids)
    }

    // MARK: - Fonts

    func testFontNameHidesSystemFontNames() {
        XCTAssertEqual(Rules.fontName(postScriptName: ".AppleSystemUIFontMonospaced-Regular", displayName: ".SF NS Mono Light Regular",
                                      isFixedPitch: true), "SF Mono")
        XCTAssertEqual(Rules.fontName(postScriptName: ".AppleSystemUIFont", displayName: "System Font Regular", isFixedPitch: false), "SF Pro")
        XCTAssertEqual(Rules.fontName(postScriptName: "Menlo-Regular", displayName: "Menlo Regular", isFixedPitch: true), "Menlo Regular")
        XCTAssertEqual(Rules.fontName(postScriptName: "Helvetica", displayName: nil, isFixedPitch: false), "Helvetica")
        let claude = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        XCTAssertEqual(Rules.fontLabel(name: Rules.fontName(postScriptName: claude.fontName, displayName: claude.displayName,
                                                            isFixedPitch: claude.isFixedPitch), pointSize: Double(claude.pointSize)),
                       "SF Mono 13")
    }

    func testFontLabel() {
        XCTAssertEqual(Rules.fontLabel(name: "SF Mono", pointSize: 13), "SF Mono 13")
        XCTAssertEqual(Rules.fontLabel(name: "Helvetica", pointSize: 12.5), "Helvetica 12.5")
        XCTAssertEqual(Rules.fontLabel(name: "Menlo", pointSize: 11.04), "Menlo 11")
    }
}
