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
