//
//  SAClaudeSettingsRulesTests.swift
//  Unit Tests
//

import AppKit
import XCTest

/// The Settings window's bespoke rows: the favourite pill's menu and writes, the encoding pill's selection, the updates
/// switch in App Store builds, the auto-complete delay warning, the colour rows shown, the font label, the SSH file pills'
/// selection, the accessible files count and the MCP port, address and status.
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

    // MARK: - SSH config and known hosts

    private let advanced = "Use known hosts from ssh config (ADVANCED)"
    private let configMenu: [String?] = ["Sequel Ace default", nil, "/Users/k/.ssh/config", "/Users/k/My Keys/b", nil, "Other file..."]
    private let knownHostsMenu: [String?] = ["Sequel Ace default", nil, "Use known hosts from ssh config (ADVANCED)", nil,
                                             "/Users/k/.ssh/known_hosts", nil, "Other file..."]
    private let emptyConfigMenu: [String?] = ["Sequel Ace default", nil, nil, "Other file..."]

    func testSSHConfigSelectionMirrorsTheOldPopUp() {
        func select(_ stored: String?, _ titles: [String?] = configMenu) -> Rules.SSHFileSelection {
            Rules.sshFileSelection(titles: titles, knownHosts: false, stored: stored, defaultValue: "/App/ssh_config",
                                   advancedTitle: advanced)
        }
        XCTAssertEqual(select("/Users/k/.ssh/config"), .index(2))
        // Paths are stored percent-encoded when they came from a bookmark's URL; the menu shows them decoded.
        XCTAssertEqual(select("/Users/k/My%20Keys/b"), .index(3))
        // The default path, a number (the tag the old pop-up's binding wrote) and no value: "Sequel Ace default".
        XCTAssertEqual(select("/App/ssh_config"), .index(0))
        XCTAssertEqual(select("0"), .index(0))
        XCTAssertEqual(select(nil), .index(0))
        XCTAssertEqual(select(""), .index(0))
        // A path no granted file has is shown as it is.
        XCTAssertEqual(select("/Users/k/revoked"), .missing("/Users/k/revoked"))
        // No granted files: always "Sequel Ace default", as the old pop-up.
        XCTAssertEqual(select("/Users/k/.ssh/config", emptyConfigMenu), .index(0))
        XCTAssertEqual(select("x", []), .index(0))
    }

    func testKnownHostsSelectionMirrorsTheOldPopUp() {
        func select(_ stored: String?, _ titles: [String?]) -> Rules.SSHFileSelection {
            Rules.sshFileSelection(titles: titles, knownHosts: true, stored: stored, defaultValue: nil, advancedTitle: advanced)
        }
        XCTAssertEqual(select("/Users/k/.ssh/known_hosts", knownHostsMenu), .index(4))
        XCTAssertEqual(select(advanced, knownHostsMenu), .index(2))
        XCTAssertEqual(select("0", knownHostsMenu), .index(0))
        XCTAssertEqual(select(nil, knownHostsMenu), .index(0))
        // The ADVANCED item isn't a granted file: with no files the pop-up showed the default even for ADVANCED.
        let noFiles: [String?] = ["Sequel Ace default", nil, advanced, nil, nil, "Other file..."]
        XCTAssertEqual(select(advanced, noFiles), .index(0))
    }

    // MARK: - Accessible files

    func testAccessibleFilesCountKey() {
        XCTAssertEqual(Rules.accessibleFilesCountKey(1), "ClaudeSettings.accessibleFiles.oneFile")
        XCTAssertEqual(Rules.accessibleFilesCountKey(0), "ClaudeSettings.accessibleFiles.files")
        XCTAssertEqual(Rules.accessibleFilesCountKey(7), "ClaudeSettings.accessibleFiles.files")
    }

    // MARK: - MCP server

    /// SPMCPPreferencePane -updatePort:'s rules (Review Focus 2: today's validation).
    func testMCPPortValidation() {
        XCTAssertEqual(Rules.mcpPort(fromText: "8765"), 8765)
        XCTAssertEqual(Rules.mcpPort(fromText: "1024"), 1024)
        XCTAssertEqual(Rules.mcpPort(fromText: "65535"), 65535)
        // Spaces anywhere were stripped.
        XCTAssertEqual(Rules.mcpPort(fromText: " 87 65 "), 8765)
        for refused in ["1023", "65536", "0", "", " ", "8765abc", "-8765", "8,765", "87.65", "99999999999999999999999", "٨٧٦٥"] {
            XCTAssertNil(Rules.mcpPort(fromText: refused), refused)
        }
    }

    func testMCPEffectivePortEndpointAndStatus() {
        XCTAssertEqual(Rules.mcpEffectivePort(stored: 9000), 9000)
        XCTAssertEqual(Rules.mcpEffectivePort(stored: 0), 8765)
        XCTAssertEqual(Rules.mcpEffectivePort(stored: 80), 8765)
        XCTAssertEqual(Rules.mcpEffectivePort(stored: 70000), 8765)
        XCTAssertEqual(Rules.mcpEndpoint(port: 8765), "http://127.0.0.1:8765/mcp")
        XCTAssertEqual(Rules.mcpStatus(enabled: false, running: true, port: 1), .disabled)
        XCTAssertEqual(Rules.mcpStatus(enabled: true, running: true, port: 9000), .running(port: 9000))
        XCTAssertEqual(Rules.mcpStatus(enabled: true, running: false, port: 9000), .stopped)
    }
}
