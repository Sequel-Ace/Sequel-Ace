import XCTest

/// The Settings window's catalog: nine panes by outcome, every inventoried
/// setting exactly once, the dependency rules, the copy and today's ranges.
final class SAClaudeSettingsCatalogTests: XCTestCase {

    // MARK: - Panes

    func testPaneOrderAndTitles() {
        XCTAssertEqual(SAClaudeSettingsCatalog.panes.map(\.id), [
            .appearance, .startup, .tablesData, .queryEditor, .safety,
            .queryConsole, .sshSecurity, .mcp, .updatesPrivacy,
        ])
        XCTAssertEqual(SAClaudeSettingsPaneID.allCases, SAClaudeSettingsCatalog.panes.map(\.id))

        let titles = Self.strings
        let expected: [SAClaudeSettingsPaneID: String] = [
            .appearance: "Appearance",
            .startup: "Startup and connections",
            .tablesData: "Tables and data",
            .queryEditor: "Query editor",
            .safety: "Safety and alerts",
            .queryConsole: "Query console",
            .sshSecurity: "SSH and security",
            .mcp: "MCP server",
            .updatesPrivacy: "Updates and privacy",
        ]
        for pane in SAClaudeSettingsPaneID.allCases {
            XCTAssertEqual(pane.titleKey, "ClaudeSettings.pane.\(pane.rawValue)")
            XCTAssertEqual(titles[pane.titleKey], expected[pane], pane.rawValue)
            XCTAssertFalse(pane.symbol.isEmpty, pane.rawValue)
            XCTAssertNotNil(NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil),
                            "\(pane.rawValue): \(pane.symbol) is not an SF Symbol on this macOS")
        }
        XCTAssertEqual(Set(SAClaudeSettingsPaneID.allCases.map(\.symbol)).count, 9, "each pane has its own symbol")
    }

    // MARK: - Routing (the window shell)

    /// Every custom, dynamic and pane-code row lands on its pane, so a pointer or a builder keyed by it finds it.
    func testCustomAndDynamicRowsRouteToTheirPanes() throws {
        let custom: [SAClaudeSettingCustom: (row: String, pane: SAClaudeSettingsPaneID)] = [
            .accent: ("accentColour", .appearance),
            .colourMode: ("editorColours", .appearance),
            .startFromTheme: ("startFromTheme", .appearance),
            .colourRows: ("colourList", .appearance),
            .editorFont: ("editorFont", .appearance),
            .resultsFont: ("resultsFont", .appearance),
            .reloadAfterSaving: ("reloadAfterSaving", .tablesData),
            .sshProgram: ("sshProgram", .sshSecurity),
            .cipherList: ("cipherOrder", .sshSecurity),
            .accessibleFiles: ("accessibleFiles", .sshSecurity),
            .mcpStatus: ("mcpServer", .mcp),
            .mcpExportFolder: ("mcpExportFolder", .mcp),
            .mcpAddress: ("mcpAddress", .mcp),
        ]
        XCTAssertEqual(Set(custom.keys), Set(SAClaudeSettingCustom.allCases), "every custom control is routed")
        for (control, want) in custom {
            let row = try XCTUnwrap(SAClaudeSettingsCatalog.row(want.row), want.row)
            XCTAssertEqual(row.control, .custom(control), want.row)
            XCTAssertEqual(SAClaudeSettingsCatalog.pane(containing: want.row), want.pane, want.row)
            XCTAssertEqual(SAClaudeSettingsCatalog.destination(pane: nil, rowID: want.row),
                           SAClaudeSettingsCatalog.Destination(pane: want.pane, rowID: want.row), want.row)
        }
        let dynamic: [String: (row: String, pane: SAClaudeSettingsPaneID)] = [
            "favorites": ("defaultFavourite", .startup),
            "encodings": ("characterSet", .startup),
            "sshConfig": ("sshConfig", .sshSecurity),
            "knownHosts": ("knownHosts", .sshSecurity),
        ]
        var seen: Set<String> = []
        for row in SAClaudeSettingsCatalog.panes.flatMap({ $0.sections.flatMap(\.rows) }) {
            if case .choice(_, .dynamic(let source)) = row.control { seen.insert(source) }
        }
        XCTAssertEqual(seen, Set(dynamic.keys), "every dynamic source is routed")
        for (source, want) in dynamic {
            let row = try XCTUnwrap(SAClaudeSettingsCatalog.row(want.row), want.row)
            guard case .choice(_, .dynamic(let got)) = row.control else { XCTFail("\(want.row) is dynamic"); continue }
            XCTAssertEqual(got, source)
            XCTAssertEqual(SAClaudeSettingsCatalog.pane(containing: want.row), want.pane, want.row)
        }
        // Plain-looking rows whose control calls pane code.
        XCTAssertEqual(SAClaudeSettingsCatalog.pane(containing: "mcpPort"), .mcp)
    }

    func testDestinationForPaneAndRow() {
        typealias D = SAClaudeSettingsCatalog.Destination
        let resolve = SAClaudeSettingsCatalog.destination(pane:rowID:)
        XCTAssertEqual(resolve("mcp", nil), D(pane: .mcp, rowID: nil))
        XCTAssertEqual(resolve("sshSecurity", "accessibleFiles"), D(pane: .sshSecurity, rowID: "accessibleFiles"))
        XCTAssertEqual(resolve(nil, "accessibleFiles"), D(pane: .sshSecurity, rowID: "accessibleFiles"))
        XCTAssertEqual(resolve("", "accessibleFiles"), D(pane: .sshSecurity, rowID: "accessibleFiles"))
        XCTAssertEqual(resolve("noSuchPane", "historySize"), D(pane: .queryEditor, rowID: "historySize"))
        // The row is the more specific request: a row in another pane wins.
        XCTAssertEqual(resolve("appearance", "mcpPort"), D(pane: .mcp, rowID: "mcpPort"))
        // An unknown row still opens the pane.
        XCTAssertEqual(resolve("tablesData", "noSuchRow"), D(pane: .tablesData, rowID: nil))
        XCTAssertEqual(resolve("tablesData", ""), D(pane: .tablesData, rowID: nil))
        XCTAssertNil(resolve(nil, nil))
        XCTAssertNil(resolve("noSuchPane", nil))
        XCTAssertNil(resolve("noSuchPane", "noSuchRow"))
        for pane in SAClaudeSettingsPaneID.allCases {
            XCTAssertEqual(resolve(pane.rawValue, nil), D(pane: pane, rowID: nil), pane.rawValue)
        }
    }

    /// `displayPreferencePane:` callers pass the old toolbar items; each lands on the pane that now holds its settings.
    func testLegacyPaneIdentifiersRoute() {
        typealias L = SAClaudeSettingsCatalog.LegacyPane
        typealias D = SAClaudeSettingsCatalog.Destination
        // SPConstants.m SPPreferenceToolbar*.
        XCTAssertEqual(L.allCases.map(\.rawValue), [
            "SPPreferenceToolbarGeneral", "SPPreferenceToolbarTables", "SPPreferenceToolbarNotifications",
            "SPPreferenceToolbarEditor", "SPPreferenceToolbarNetwork", "SPPreferenceToolbarFile", "SPPreferenceToolbarMCP",
        ])
        let expected: [String: D] = [
            "SPPreferenceToolbarGeneral": D(pane: .appearance, rowID: nil),
            "SPPreferenceToolbarTables": D(pane: .tablesData, rowID: nil),
            "SPPreferenceToolbarNotifications": D(pane: .safety, rowID: nil),
            "SPPreferenceToolbarEditor": D(pane: .queryEditor, rowID: nil),
            "SPPreferenceToolbarNetwork": D(pane: .sshSecurity, rowID: nil),
            "SPPreferenceToolbarFile": D(pane: .sshSecurity, rowID: "accessibleFiles"),
            "SPPreferenceToolbarMCP": D(pane: .mcp, rowID: nil),
        ]
        for (identifier, want) in expected {
            XCTAssertEqual(SAClaudeSettingsCatalog.destination(forLegacyPane: identifier), want, identifier)
        }
        // No sender (the old default), the never-shown Shortcuts/Favorites items, or anything else: the first pane.
        for identifier in [nil, "", "SPPreferenceToolbarShortcuts", "SPPreferenceToolbarFavorites", "nonsense"] as [String?] {
            XCTAssertEqual(SAClaudeSettingsCatalog.destination(forLegacyPane: identifier), D(pane: .appearance, rowID: nil),
                           identifier ?? "nil")
        }
    }

    /// The old pane controllers asked to refresh (`preferencePaneWillBeShown`) when a pane is shown: the ones whose
    /// settings it holds — every old pane is refreshed by some pane, and the Files pane only by SSH and security. That
    /// refresh only reloads the accessible-files list now: the re-select panel is never part of a pane switch
    /// (`testStaleFileRegrantOnlyWhenAskedForTheFilesList`).
    func testLegacyPanesRefreshedWithEachPane() {
        typealias L = SAClaudeSettingsCatalog.LegacyPane
        let expected: [SAClaudeSettingsPaneID: [L]] = [
            .appearance: [.general, .editor],
            .startup: [.general, .network],
            .tablesData: [.tables, .general],
            .queryEditor: [.editor, .general],
            .safety: [.notifications],
            .queryConsole: [.notifications],
            .sshSecurity: [.network, .file],
            .mcp: [.mcp],
            .updatesPrivacy: [.notifications, .general],
        ]
        for pane in SAClaudeSettingsPaneID.allCases {
            XCTAssertEqual(SAClaudeSettingsCatalog.legacyPanes(for: pane), expected[pane], pane.rawValue)
        }
        let all = SAClaudeSettingsPaneID.allCases.flatMap(SAClaudeSettingsCatalog.legacyPanes(for:))
        XCTAssertEqual(Set(all), Set(L.allCases))
        XCTAssertEqual(SAClaudeSettingsPaneID.allCases.filter { SAClaudeSettingsCatalog.legacyPanes(for: $0).contains(.file) },
                       [.sshSecurity])
    }

    /// The stale-file re-select panel opens by itself only when a caller asks for it and the request lands on the
    /// accessible-files list; the sidebar, a pane switch, `displayPreferencePane:` and other rows never open it.
    func testStaleFileRegrantOnlyWhenAskedForTheFilesList() {
        typealias D = SAClaudeSettingsCatalog.Destination
        let files = D(pane: .sshSecurity, rowID: "accessibleFiles")
        XCTAssertTrue(SAClaudeSettingsCatalog.regrantsStaleFiles(files, requested: true))
        XCTAssertFalse(SAClaudeSettingsCatalog.regrantsStaleFiles(files, requested: false))
        for pane in SAClaudeSettingsPaneID.allCases {
            for requested in [false, true] {
                XCTAssertFalse(SAClaudeSettingsCatalog.regrantsStaleFiles(D(pane: pane, rowID: nil), requested: requested),
                               "\(pane.rawValue) top, requested \(requested)")
            }
        }
        for rowID in ["sshConfig", "knownHosts", "cipherOrder", "sshProgram"] {
            XCTAssertFalse(SAClaudeSettingsCatalog.regrantsStaleFiles(D(pane: .sshSecurity, rowID: rowID), requested: true), rowID)
        }
        // The old Files toolbar item still lands on the list, but `displayPreferencePane:` never asks for the panel.
        let legacy = SAClaudeSettingsCatalog.destination(forLegacyPane: SAClaudeSettingsCatalog.LegacyPane.file.rawValue)
        XCTAssertEqual(legacy, files)
        XCTAssertFalse(SAClaudeSettingsCatalog.regrantsStaleFiles(legacy, requested: false))
    }

    // MARK: - Pointers from elsewhere

    /// Each message or button outside the window that points to a setting: its pane, row and whether it opens the
    /// re-select panel (only the launch alert and the file prompts).
    func testPointersRouteToTheirPaneRowAndRegrant() {
        typealias P = SAClaudeSettingsPointer
        let expected: [(P, SAClaudeSettingsPaneID, String, Bool, Bool)] = [   // pointer, pane, row, re-grant, has button
            (.launchStaleFiles, .sshSecurity, "accessibleFiles", true, true),
            (.connectionSSHConfigFile, .sshSecurity, "accessibleFiles", true, true),
            (.networkMissingFiles, .sshSecurity, "accessibleFiles", true, false),
            (.mcpPortError, .mcp, "mcpPort", false, false),
            (.customSSHBinary, .sshSecurity, "sshProgram", false, false),
            (.analyticsConsent, .updatesPrivacy, "shareAnalytics", false, false),
            (.knownHostsFile, .sshSecurity, "knownHosts", false, false),
            (.noRowsAffected, .safety, "warnNoRowsAffected", false, false),
            (.deleteDoubleCheck, .safety, "askTwiceDelete", false, false),
            (.mcpReadOnly, .mcp, "mcpReadOnly", false, false),
        ]
        XCTAssertEqual(expected.map(\.0), P.allCases)
        for (pointer, pane, rowID, regrant, hasButton) in expected {
            let name = "\(pointer)"
            let target = pointer.target
            XCTAssertEqual(target.pane, pane, name)
            XCTAssertEqual(target.rowID, rowID, name)
            XCTAssertEqual(target.regrantStaleFiles, regrant, name)
            XCTAssertEqual(target.buttonKey, hasButton ? P.openSettingsButtonKey : nil, name)
            // The row is in that pane: the window resolves the request to the same place.
            XCTAssertEqual(SAClaudeSettingsCatalog.destination(pane: pane.rawValue, rowID: rowID), pointer.destination, name)
            XCTAssertEqual(SAClaudeSettingsCatalog.pane(containing: rowID), pane, name)
            // What the window does with it: the panel only for the pointers that ask.
            XCTAssertEqual(SAClaudeSettingsCatalog.regrantsStaleFiles(pointer.destination, requested: target.regrantStaleFiles),
                           regrant, name)
            // The Objective-C view of the table.
            XCTAssertEqual(SAClaudeSettingsPointers.paneID(for: pointer), pane.rawValue, name)
            XCTAssertEqual(SAClaudeSettingsPointers.rowID(for: pointer), rowID, name)
            XCTAssertEqual(SAClaudeSettingsPointers.regrantsStaleFiles(for: pointer), regrant, name)
        }
    }

    /// Every pointer's text names its place in the new words — "Settings ▸ <pane> ▸ <row>" with the window's own pane
    /// and row names — and none still says Preferences or an old pane.
    func testPointerTextsNameTheNewPlace() {
        let strings = Self.strings
        func place(_ pointer: SAClaudeSettingsPointer) -> String {
            let target = pointer.target
            let rowName = SAClaudeSettingsCatalog.row(target.rowID).flatMap { strings[$0.nameKey] } ?? "?"
            return "Settings \u{25B8} \(strings[target.pane.titleKey] ?? "?") \u{25B8} \(rowName)"
        }
        XCTAssertEqual(strings[SAClaudeSettingsPointer.openSettingsButtonKey], "Open Settings")
        for pointer in SAClaudeSettingsPointer.allCases {
            let target = pointer.target
            if pointer == .mcpReadOnly {
                XCTAssertTrue(target.messageKeys.isEmpty)
                XCTAssertEqual(SAClaudeSettingsPointers.mcpReadOnlyPlace, place(pointer))
                continue
            }
            XCTAssertFalse(target.messageKeys.isEmpty, "\(pointer)")
            for key in target.messageKeys {
                guard let text = strings[key] else { XCTFail("missing \(key)"); continue }
                XCTAssertTrue(text.contains(place(pointer)), "\(key): \(text) should name \(place(pointer))")
                for old in ["Preferences", "preferences", "Network tab", "Files tab", "Network Settings"] {
                    XCTAssertFalse(text.contains(old), "\(key) still says \(old)")
                }
            }
        }
        // The SSH config prompt also names the row for choosing a different file.
        XCTAssertTrue(strings["ClaudeSettings.pointer.sshConfigFile.message"]?
            .contains("Settings \u{25B8} SSH and security \u{25B8} \(strings["ClaudeSettings.sshConfig.name"] ?? "?")") ?? false)
        // Format specifiers are those of the texts they replace.
        let specifiers: [String: [String]] = [
            "ClaudeSettings.pointer.staleFiles.many": ["%d"], "ClaudeSettings.pointer.missingFiles.many": ["%d"],
            "ClaudeSettings.pointer.sshConfigFile.message": ["%@"], "ClaudeSettings.pointer.mcpPortError.message": ["%ld", "%@"],
            "ClaudeSettings.pointer.knownHosts.notWritable": ["%@"], "ClaudeSettings.pointer.knownHosts.quote": ["%@"],
        ]
        for pointer in SAClaudeSettingsPointer.allCases {
            for key in pointer.target.messageKeys {
                let text = strings[key] ?? ""
                let regex = try! NSRegularExpression(pattern: "%(ld|d|@)")
                let found = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    .map { (text as NSString).substring(with: $0.range) }
                XCTAssertEqual(found, specifiers[key] ?? [], key)
            }
        }
    }

    /// The bookmark alert texts carry their en value in code (the strings table isn't in every bundle); it is the
    /// table's text.
    func testBookmarkAlertTextsMatchTheStringsTable() {
        let strings = Self.strings
        XCTAssertEqual(SABookmarkAlertContent.staleBookmarksMessage(count: 1), strings["ClaudeSettings.pointer.staleFiles.one"])
        XCTAssertEqual(SABookmarkAlertContent.staleBookmarksMessage(count: 7),
                       strings["ClaudeSettings.pointer.staleFiles.many"].map { String(format: $0, 7) })
        XCTAssertEqual(SABookmarkAlertContent.missingBookmarksMessage(count: 1), strings["ClaudeSettings.pointer.missingFiles.one"])
        XCTAssertEqual(SABookmarkAlertContent.missingBookmarksMessage(count: 3),
                       strings["ClaudeSettings.pointer.missingFiles.many"].map { String(format: $0, 3) })
    }

    func testWindowAndMenuTitles() {
        XCTAssertEqual(Self.strings["ClaudeSettings.ui.windowTitle"], "Settings")
        XCTAssertEqual(Self.strings["ClaudeSettings.ui.menuItem"], "Settings\u{2026}")
    }

    func testRowAndSectionIDsAreUniqueAndFindable() {
        let rows = SAClaudeSettingsCatalog.panes.flatMap { $0.sections.flatMap(\.rows) }
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "row ids are unique")
        let sections = SAClaudeSettingsCatalog.panes.flatMap(\.sections)
        XCTAssertEqual(Set(sections.map(\.id)).count, sections.count, "section ids are unique")

        for pane in SAClaudeSettingsCatalog.panes {
            for row in pane.sections.flatMap(\.rows) {
                XCTAssertEqual(SAClaudeSettingsCatalog.row(row.id), row)
                XCTAssertEqual(SAClaudeSettingsCatalog.pane(containing: row.id), pane.id)
                XCTAssertEqual(row.nameKey, "ClaudeSettings.\(row.id).name")
                XCTAssertEqual(row.descKey, "ClaudeSettings.\(row.id).desc")
                XCTAssertEqual(row.infoKey, "ClaudeSettings.\(row.id).info")
                XCTAssertEqual(row.wasKey, "ClaudeSettings.\(row.id).was")
                if let parent = row.parentID {
                    let parentRow = SAClaudeSettingsCatalog.row(parent)
                    XCTAssertNotNil(parentRow, "\(row.id)'s parent \(parent) exists")
                    XCTAssertEqual(SAClaudeSettingsCatalog.pane(containing: parent), pane.id, "\(row.id) sits in its parent's pane")
                }
            }
        }
        XCTAssertNil(SAClaudeSettingsCatalog.row("noSuchRow"))
        XCTAssertNil(SAClaudeSettingsCatalog.pane(containing: "noSuchRow"))
        XCTAssertEqual(SAClaudeSettingsCatalog.pane(containing: "logInterface"), .queryConsole)
        XCTAssertEqual(SAClaudeSettingsCatalog.pane(containing: "accentColour"), .appearance)
        XCTAssertEqual(SAClaudeSettingsCatalog.pane(containing: "accessibleFiles"), .sshSecurity)
    }

    // MARK: - Coverage (Review Focus 3)

    /// Every defaults key in the 2026-10-18 settings inventory (rows G, T, A,
    /// E, E-m, E-s, E-c, E-a, N, F, M), as the raw strings of their constants.
    /// Left out: the dead/hidden rows E-x1…E-x9 and G12, and the pure text
    /// rows with no setting (E-h1, E-h2, N8, M2 status text, M5, M8, F4 hint).
    /// The stray misspelled `CustomQueryEnableBracketHighliting` binding is not
    /// a setting either. Action-only rows (E2, E-a2, E-menu1…4, N7, F2–F4, M7)
    /// are covered by the custom control that hosts them (see below).
    private static let inventoriedKeys: [String] = [
        // General
        "ApplicationPromptOnQuit",                    // G1
        "DefaultFavorite", "SelectLastFavoriteUsed",  // G2
        "AutoConnectToDefault",                       // G3
        "DefaultViewMode",                            // G4
        "DefaultEncodingTag",                         // G5
        "DisplayTableViewVerticalGridlines",          // G6
        "DisplayCommentsInTablesList",                // G7
        "CustomQuerySaveHistoryIndividually",         // G8
        "DisplayTableViewColumnTypes",                // G9
        "CustomQueryMaxHistoryItems",                 // G10
        "Appearance",                                 // G11
        "DisplayConnectionColorInTitlebar",           // G13
        "fontSettings",                               // G14
        "SaveApplicationUsageAnalytics",              // G15
        "AutoCheckClipboardForConnectionStrings",     // G16
        // Tables
        "ReloadAfterAddingRow",                       // T1
        "ReloadAfterEditingRow",                      // T2
        "ReloadAfterRemovingRow",                     // T3
        "LoadBlobsAsNeeded",                          // T4
        "RuleFilterShowDropZone",                     // T5
        "NewFieldsAllowNulls",                        // T6
        "LimitResults",                               // T7
        "LimitResultsValue",                          // T8
        "NullValue",                                  // T9
        "TableRowCountQueryLevel",                    // T10
        "EditInSheetForLongText",                     // T11
        "EditInSheetForLongTextLengthThreshold",      // T12
        "EditInSheetForMultiLineText",                // T13
        // Alerts & Logs
        "ShowNoAffectedRowsError",                    // A1
        "ShowWarningBeforeExecuteQuery",              // A2
        "ShowWarningBeforeDeleteQuery",               // A3
        "ShowUpdateAvailable",                        // A4
        "ShowWarningSkipShowDatabase",                // A5
        "ConsoleEnableLogging",                       // A6
        "ConsoleEnableInterfaceLogging",              // A7
        "ConsoleEnableCustomQueryLogging",            // A8
        "ConsoleEnableImportExportLogging",           // A9
        "ConsoleEnableErrorLogging",                  // A10
        // Query Editor
        "CustomQueryEditorFont",                      // E1 (+ E2 Reset)
        "CustomQueryAutoIndent",                      // E3
        "CustomQuerySoftIndent",                      // E4
        "CustomQuerySoftIndentWidth",                 // E5
        "CustomQueryAutoPairCharacters",              // E6
        "CustomQueryAutoUppercaseKeywords",           // E7
        "CustomQueryUpdateAutoHelp",                  // E8
        "CustomQueryAutoHelpDelay",                   // E9
        "CustomQueryHighlightCurrentQuery",           // E10
        "CustomQueryEnableSyntaxHighlighting",        // E11
        "CustomQueryEnableBracketHighlighting",       // E12
        "CustomQueryAutoComplete",                    // E13
        "CustomQueryAutoCompleteDelay",               // E14
        "SPCustomQueryEditorCompleteWithBackticks",   // E15
        "CustomQueryFunctionCompletionInsertsArguments", // E16
        "CustomQueryEditorTabStopWidth",              // E17
        "UseDashStyleForBlockComment",                // E18
        "EditorThemeMatchesAppearance", "EditorCustomColours", "EditorCustomThemeName", // E-m
        "CustomQueryEditorThemeName",                 // E-s (+ E-menu1…4)
        "CustomQueryEditorTextColor",                 // E-c1
        "CustomQueryEditorBackgroundColor",           // E-c2
        "CustomQueryEditorCaretColor",                // E-c3
        "CustomQueryEditorCommentColor",              // E-c4
        "CustomQueryEditorSQLKeywordColor",           // E-c5
        "CustomQueryEditorNumericColor",              // E-c6
        "CustomQueryEditorQuoteColor",                // E-c7
        "CustomQueryEditorBacktickColor",             // E-c8
        "CustomQueryEditorVariableColor",             // E-c9
        "CustomQueryEditorHighlightQueryColor",       // E-c10
        "CustomQueryEditorSelectionColor",            // E-c11
        "ClaudeAccentColour",                         // E-a (+ E-a2 Reset)
        // Network
        "ConnectionTimeoutValue",                     // N1
        "UseKeepAlive",                               // N2
        "SSHClientPath",                              // N3
        "ssh_config",                                 // N4
        "known_hosts", "SSHConfigContainsUserKnownHostsFile", // N5
        "SSLCipherList",                              // N6 (+ N7 Reset)
        "KeySelectionHiddenFilesVisibility",          // N9
        // Files
        "SPSecureBookmarks", "SPStaleSecureBookmarks", "SPKnownHostsBookmarks", // F1 (+ F2–F4)
        // MCP Server
        "SPMCPServerEnabled",                         // M1 (+ M2 status)
        "SPMCPReadOnly",                              // M3
        "SPMCPServerPort",                            // M4
        "SPMCPExportPath",                            // M6
    ]

    /// The custom controls, each standing for inventory rows (including the
    /// action-only ones): accent = E-a/E-a2, colourMode = E-m, startFromTheme
    /// = E-s/E-menu1…4, colourRows = E-c1…11, editorFont = E1/E2, resultsFont
    /// = G14, reloadAfterSaving = T1–T3, sshProgram = N3, cipherList = N6/N7,
    /// accessibleFiles = F1–F4, mcpStatus = M1/M2, mcpExportFolder = M6,
    /// mcpAddress = M7 (action only, derived from M4).
    private static let inventoriedCustomIDs: [String] = [
        "accent", "colourMode", "startFromTheme", "colourRows", "editorFont",
        "resultsFont", "reloadAfterSaving", "sshProgram", "cipherList",
        "accessibleFiles", "mcpStatus", "mcpExportFolder", "mcpAddress",
    ]

    func testCatalogCoversInventoryExactlyOnce() {
        let keys = SAClaudeSettingsCatalog.allKeys
        for key in Self.inventoriedKeys {
            XCTAssertEqual(keys.filter { $0 == key }.count, 1, "\(key) appears exactly once")
        }
        XCTAssertEqual(Set(keys).subtracting(Self.inventoriedKeys), [], "no key outside the inventory")
        XCTAssertEqual(Set(Self.inventoriedKeys).count, Self.inventoriedKeys.count, "the embedded list has no repeats")

        let rows = SAClaudeSettingsCatalog.panes.flatMap { $0.sections.flatMap(\.rows) }
        let customIDs = rows.compactMap { row -> String? in
            if case .custom(let custom) = row.control { return custom.rawValue }
            return nil
        }
        for id in Self.inventoriedCustomIDs {
            XCTAssertEqual(customIDs.filter { $0 == id }.count, 1, "custom \(id) appears exactly once")
        }
        XCTAssertEqual(Set(customIDs).subtracting(Self.inventoriedCustomIDs), [], "no custom control outside the inventory")
        XCTAssertEqual(Set(SAClaudeSettingCustom.allCases.map(\.rawValue)), Set(Self.inventoriedCustomIDs))

        // The one row with three keys.
        XCTAssertEqual(SAClaudeSettingsCatalog.keys(for: try XCTUnwrap(SAClaudeSettingsCatalog.row("reloadAfterSaving"))),
                       ["ReloadAfterAddingRow", "ReloadAfterEditingRow", "ReloadAfterRemovingRow"])
    }

    func testRowKeysAndControls() throws {
        func control(_ id: String) throws -> SAClaudeSettingControl {
            try XCTUnwrap(SAClaudeSettingsCatalog.row(id), id).control
        }
        XCTAssertEqual(try control("appAppearance"),
                       .choice(key: "Appearance", source: .fixed([
                        ("ClaudeSettings.appAppearance.option.matchMacOS", 0),
                        ("ClaudeSettings.appAppearance.option.light", 1),
                        ("ClaudeSettings.appAppearance.option.dark", 2),
                       ])))
        XCTAssertEqual(try control("tabToOpen"),
                       .choice(key: "DefaultViewMode", source: .fixed([
                        ("ClaudeSettings.tabToOpen.option.lastUsed", 0),
                        ("ClaudeSettings.tabToOpen.option.structure", 1),
                        ("ClaudeSettings.tabToOpen.option.content", 2),
                        ("ClaudeSettings.tabToOpen.option.relations", 3),
                        ("ClaudeSettings.tabToOpen.option.tableInfo", 4),
                        ("ClaudeSettings.tabToOpen.option.query", 5),
                        ("ClaudeSettings.tabToOpen.option.triggers", 6),
                       ])))
        XCTAssertEqual(try control("countRows"),
                       .choice(key: "TableRowCountQueryLevel", source: .fixed([
                        ("ClaudeSettings.countRows.option.never", 0),
                        ("ClaudeSettings.countRows.option.smallTables", 1),
                        ("ClaudeSettings.countRows.option.always", 2),
                       ])))
        XCTAssertEqual(try control("defaultFavourite"), .choice(key: "DefaultFavorite", source: .dynamic("favorites")))
        XCTAssertEqual(try control("characterSet"), .choice(key: "DefaultEncodingTag", source: .dynamic("encodings")))
        XCTAssertEqual(try control("sshConfig"), .choice(key: "ssh_config", source: .dynamic("sshConfig")))
        XCTAssertEqual(try control("knownHosts"), .choice(key: "known_hosts", source: .dynamic("knownHosts")))
        XCTAssertEqual(try control("nullText"), .text(key: "NullValue"))
        XCTAssertEqual(try control("titleBarColour"), .toggle(key: "DisplayConnectionColorInTitlebar"))
        XCTAssertEqual(try control("printGridLines"), .toggle(key: "DisplayTableViewVerticalGridlines"))
        XCTAssertEqual(try control("accentColour"), .custom(.accent))
        XCTAssertEqual(try control("reloadAfterSaving"), .custom(.reloadAfterSaving))
        XCTAssertEqual(try control("mcpServer"), .custom(.mcpStatus))
        XCTAssertNotEqual(SAClaudeSettingChoiceSource.fixed([("a", 0)]), .fixed([("a", 1)]))
        XCTAssertNotEqual(SAClaudeSettingChoiceSource.fixed([("a", 0)]), .dynamic("a"))
    }

    // MARK: - Dependencies

    func testDependentRowsAndEnablement() throws {
        func row(_ id: String) throws -> SAClaudeSettingRow { try XCTUnwrap(SAClaudeSettingsCatalog.row(id), id) }
        func enabled(_ id: String, _ on: [String: Bool]) throws -> Bool {
            SAClaudeSettingsCatalog.isEnabled(try row(id)) { on[$0] ?? false }
        }

        // Disabled while the parent is off.
        let disabledDependents: [String: (parent: String, key: String)] = [
            "logInterface": ("logQueries", "ConsoleEnableLogging"),
            "logCustomQueries": ("logQueries", "ConsoleEnableLogging"),
            "logImportExport": ("logQueries", "ConsoleEnableLogging"),
            "logErrors": ("logQueries", "ConsoleEnableLogging"),
            "askTwiceDelete": ("confirmChanges", "ShowWarningBeforeExecuteQuery"),
        ]
        for (id, dep) in disabledDependents {
            XCTAssertEqual(try row(id).parentID, dep.parent, id)
            XCTAssertTrue(try row(id).disabledWhenParentOff, id)
            XCTAssertFalse(try enabled(id, [:]), "\(id) off while \(dep.parent) is off")
            XCTAssertTrue(try enabled(id, [dep.key: true]), "\(id) on while \(dep.parent) is on")
        }

        // Indented under a parent but never disabled. "Connect to it
        // automatically" hangs off a pill with no off state ("Last used"
        // still auto-connects the last favourite), so it stays enabled.
        let enabledDependents: [String: String] = [
            "autoConnect": "defaultFavourite",
            "completeBackticks": "autoComplete",
            "insertArguments": "autoComplete",
            "mcpReadOnly": "mcpServer",
            "mcpPort": "mcpServer",
            "mcpExportFolder": "mcpServer",
            "mcpAddress": "mcpServer",
        ]
        for (id, parent) in enabledDependents {
            XCTAssertEqual(try row(id).parentID, parent, id)
            XCTAssertFalse(try row(id).disabledWhenParentOff, id)
            XCTAssertTrue(try enabled(id, [:]), "\(id) stays enabled with everything off")
        }

        // Nothing else is a dependent; top-level rows are always enabled.
        let rows = SAClaudeSettingsCatalog.panes.flatMap { $0.sections.flatMap(\.rows) }
        let dependents = Set(rows.filter { $0.parentID != nil }.map(\.id))
        XCTAssertEqual(dependents, Set(disabledDependents.keys).union(enabledDependents.keys))
        for row in rows where row.parentID == nil {
            XCTAssertFalse(row.disabledWhenParentOff, row.id)
            XCTAssertTrue(SAClaudeSettingsCatalog.isEnabled(row) { _ in false }, row.id)
        }
        // A dependent follows straight after its parent (or a sibling dependent).
        for section in SAClaudeSettingsCatalog.panes.flatMap(\.sections) {
            var currentParent: String?
            for row in section.rows {
                if let parent = row.parentID {
                    XCTAssertEqual(parent, currentParent, "\(row.id) sits under \(parent)")
                } else {
                    currentParent = row.id
                }
            }
        }
    }

    // MARK: - Copy

    private static let strings: [String: String] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localization/en.lproj/Localizable.strings")
        return (NSDictionary(contentsOf: url) as? [String: String]) ?? [:]
    }()

    private func assertCopy(_ key: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let value = Self.strings[key] else {
            return XCTFail("missing \(key)", file: file, line: line)
        }
        XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(key) is empty", file: file, line: line)
        XCTAssertNotEqual(value, key, file: file, line: line)
    }

    func testEveryRowHasLocalizedCopy() {
        XCTAssertGreaterThan(Self.strings.count, 1000, "the app's strings file loaded")
        for pane in SAClaudeSettingsCatalog.panes {
            assertCopy(pane.id.titleKey)
            for section in pane.sections {
                if let title = section.titleKey {
                    XCTAssertEqual(title, "ClaudeSettings.section.\(section.id)")
                    assertCopy(title)
                }
                for row in section.rows {
                    assertCopy(row.nameKey)
                    assertCopy(row.wasKey)
                    XCTAssertTrue(Self.strings[row.wasKey]?.hasPrefix("Was: ") ?? false, row.id)
                    if row.hasDescription { assertCopy(row.descKey) } else { XCTAssertNil(Self.strings[row.descKey], row.descKey) }
                    if row.hasInfo { assertCopy(row.infoKey) } else { XCTAssertNil(Self.strings[row.infoKey], row.infoKey) }
                    if case .choice(_, .fixed(let options)) = row.control {
                        options.forEach { assertCopy($0.0) }
                    }
                }
            }
        }
        // Spot-check the copy against the spec, including the three corrected (i) texts.
        XCTAssertEqual(Self.strings["ClaudeSettings.appAppearance.name"], "App appearance")
        XCTAssertEqual(Self.strings["ClaudeSettings.appAppearance.was"], "Was: Appearance (General)")
        XCTAssertEqual(Self.strings["ClaudeSettings.characterSet.info"],
                       "The text encoding for the connection. Autodetect switches to utf8mb4 when a table loads.")
        XCTAssertEqual(Self.strings["ClaudeSettings.readConnectionStrings.info"],
                       "If the clipboard holds a mysql:// address, Import offers to save it as a new favourite instead of asking for a file.")
        XCTAssertEqual(Self.strings["ClaudeSettings.confirmChanges.info"],
                       "Asks first before a query that changes data, before Run All as Script, before every row save in Content, and before renaming a table or editing its comment.")
        XCTAssertEqual(Self.strings["ClaudeSettings.askBeforeQuitting.info"], "Shows a \"Close the app?\" check before quitting.")
        XCTAssertEqual(Self.strings["ClaudeSettings.logInterface.name"], "Queries the app runs for you")
        XCTAssertEqual(Self.strings["ClaudeSettings.logInterface.was"], "Was: Interface (Alerts & Logs)")
    }

    // MARK: - Ranges

    func testNumberRangesMatchToday() throws {
        func numeric(_ id: String) throws -> (key: String, unit: SAClaudeSettingUnit, range: ClosedRange<Double>, step: Double) {
            switch try XCTUnwrap(SAClaudeSettingsCatalog.row(id), id).control {
            case let .number(key, unit, range, step): return (key, unit, range, step)
            case let .toggleNumber(_, key, unit, range, step): return (key, unit, range, step)
            default: XCTFail("\(id) is not numeric"); return ("", .none, 0...0, 0)
            }
        }
        // Formatter / stepper bounds in Preferences.xib and SPMCPPreferencePane.
        let expected: [String: (String, SAClaudeSettingUnit, ClosedRange<Double>, Double)] = [
            "historySize": ("CustomQueryMaxHistoryItems", .queries, 0...100, 1),        // formatter 0–100
            "tabWidth": ("CustomQueryEditorTabStopWidth", .spaces, 1...20, 1),          // formatter + stepper 1–20
            "softIndent": ("CustomQuerySoftIndentWidth", .spaces, 1...32, 1),           // formatter + stepper 1–32
            "autoHelp": ("CustomQueryAutoHelpDelay", .seconds, 0.1...5, 0.1),           // formatter + stepper 0.1–5
            "autoComplete": ("CustomQueryAutoCompleteDelay", .seconds, 0...5, 0.1),     // stepper 0–5
            "mcpPort": ("SPMCPServerPort", .none, 1024...65535, 1),                     // updatePort: validation
            "pageSize": ("LimitResultsValue", .rows, 1...1_000_000, 1),                 // stepper 1–1,000,000
            "longValueSheet": ("EditInSheetForLongTextLengthThreshold", .characters, 1...1_000_000, 1),
            "connectTimeout": ("ConnectionTimeoutValue", .seconds, 0...10_000, 1),      // formatter 0–10000
        ]
        for (id, want) in expected {
            let got = try numeric(id)
            XCTAssertEqual(got.key, want.0, id)
            XCTAssertEqual(got.unit, want.1, id)
            XCTAssertEqual(got.range, want.2, id)
            XCTAssertEqual(got.step, want.3, accuracy: 1e-9, id)
        }
        XCTAssertGreaterThanOrEqual(try numeric("pageSize").range.lowerBound, 1)
        XCTAssertGreaterThanOrEqual(try numeric("longValueSheet").range.lowerBound, 1)

        // Toggle halves of the switch-plus-field rows.
        let toggles: [String: String] = [
            "pageSize": "LimitResults", "longValueSheet": "EditInSheetForLongText",
            "softIndent": "CustomQuerySoftIndent", "autoComplete": "CustomQueryAutoComplete",
            "autoHelp": "CustomQueryUpdateAutoHelp",
        ]
        for (id, toggleKey) in toggles {
            guard case .toggleNumber(let key, _, _, _, _) = try XCTUnwrap(SAClaudeSettingsCatalog.row(id)).control else {
                XCTFail("\(id) is a switch plus field"); continue
            }
            XCTAssertEqual(key, toggleKey, id)
        }
    }
}
