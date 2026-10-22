//
//  SAClaudeSettingsCatalog.swift
//  Sequel Ace
//
//  The Settings window as data: nine panes grouped by outcome, their
//  sections, and one row per setting with its defaults key(s), control,
//  dependency and copy keys. Every view of the window renders from this
//  table, and the unit tests check it against the 2026-10-18 settings
//  inventory (every setting exactly once).
//
//  Pure Swift (app + Unit Tests targets): the defaults keys are the raw
//  strings of their constants — keep in sync with SPConstants.m,
//  SAClaudeAccent.defaultsKey, SAEditorColourMode,
//  SAEditorAppearanceThemeSwitcher.matchesAppearanceKey and
//  SPFilterRuleEditor's drop-zone key.
//

import Foundation

// MARK: - Panes

enum SAClaudeSettingsPaneID: String, CaseIterable {
    case appearance, startup, tablesData, queryEditor, safety, queryConsole, sshSecurity, mcp, updatesPrivacy

    /// SF Symbol shown beside the pane name in the sidebar (all available on macOS 13).
    var symbol: String {
        switch self {
        case .appearance: return "paintbrush"
        case .startup: return "power"
        case .tablesData: return "tablecells"
        case .queryEditor: return "chevron.left.forwardslash.chevron.right"
        case .safety: return "exclamationmark.shield"
        case .queryConsole: return "terminal"
        case .sshSecurity: return "lock.shield"
        case .mcp: return "network"
        case .updatesPrivacy: return "arrow.triangle.2.circlepath"
        }
    }

    var titleKey: String { "ClaudeSettings.pane.\(rawValue)" }
}

// MARK: - Controls

enum SAClaudeSettingUnit { case none, seconds, rows, characters, spaces, queries }

enum SAClaudeSettingChoiceSource: Equatable {
    /// (title localization key, tag written to the defaults key).
    case fixed([(String, Int)])
    /// A list the view builds at run time: "favorites", "encodings",
    /// "sshConfig", "knownHosts", "editorTheme".
    case dynamic(String)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.fixed(a), .fixed(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case let (.dynamic(a), .dynamic(b)):
            return a == b
        default:
            return false
        }
    }
}

/// Rows whose control is a bespoke view that calls the existing pane
/// controller code (fonts, colours, SSH choosers, lists, MCP).
enum SAClaudeSettingCustom: String, CaseIterable {
    case accent, colourMode, startFromTheme, colourRows, editorFont, resultsFont, reloadAfterSaving,
         sshProgram, cipherList, accessibleFiles, mcpStatus, mcpExportFolder, mcpAddress
}

enum SAClaudeSettingControl: Equatable {
    case toggle(key: String)
    /// A switch plus a number field; the field is disabled while the switch is off.
    case toggleNumber(toggleKey: String, numberKey: String, unit: SAClaudeSettingUnit, range: ClosedRange<Double>, step: Double)
    case number(key: String, unit: SAClaudeSettingUnit, range: ClosedRange<Double>, step: Double)
    case choice(key: String, source: SAClaudeSettingChoiceSource)
    case text(key: String)
    case custom(SAClaudeSettingCustom)

    /// The bool key a dependent row reads to decide whether it is enabled.
    var toggleKey: String? {
        switch self {
        case .toggle(let key): return key
        case .toggleNumber(let key, _, _, _, _): return key
        case .custom(.mcpStatus): return SAClaudeSettingsCatalog.mcpServerEnabledKey
        default: return nil
        }
    }
}

// MARK: - Rows, sections, panes

struct SAClaudeSettingRow: Identifiable, Equatable {
    let id: String
    let control: SAClaudeSettingControl
    /// The row this one is indented under.
    let parentID: String?
    /// Shown disabled while the parent's switch is off.
    let disabledWhenParentOff: Bool
    let hasDescription: Bool
    /// Has an (i) explanation. Every row has a "Was: …" line either way.
    let hasInfo: Bool

    var nameKey: String { "ClaudeSettings.\(id).name" }
    var descKey: String { "ClaudeSettings.\(id).desc" }
    var infoKey: String { "ClaudeSettings.\(id).info" }
    var wasKey: String { "ClaudeSettings.\(id).was" }
}

struct SAClaudeSettingsSection {
    let id: String
    let titleKey: String?
    let rows: [SAClaudeSettingRow]
}

struct SAClaudeSettingsPane {
    let id: SAClaudeSettingsPaneID
    let sections: [SAClaudeSettingsSection]
}

// MARK: - Catalog

enum SAClaudeSettingsCatalog {

    // Keys used in more than one place below.
    fileprivate static let mcpServerEnabledKey = "SPMCPServerEnabled"   // SPMCPServerEnabled
    private static let logMasterKey = "ConsoleEnableLogging"            // SPConsoleEnableLogging
    private static let confirmChangesKey = "ShowWarningBeforeExecuteQuery" // SPQueryWarningEnabled

    /// Keys a custom control writes (directly or through the pane
    /// controller it calls), for the inventory check and `allKeys`.
    static let customKeys: [SAClaudeSettingCustom: [String]] = [
        .accent: ["ClaudeAccentColour"],
        .colourMode: ["EditorThemeMatchesAppearance", "EditorCustomColours", "EditorCustomThemeName"],
        .startFromTheme: ["CustomQueryEditorThemeName"],
        .colourRows: [
            "CustomQueryEditorTextColor", "CustomQueryEditorBackgroundColor", "CustomQueryEditorCaretColor",
            "CustomQueryEditorCommentColor", "CustomQueryEditorSQLKeywordColor", "CustomQueryEditorNumericColor",
            "CustomQueryEditorQuoteColor", "CustomQueryEditorBacktickColor", "CustomQueryEditorVariableColor",
            "CustomQueryEditorHighlightQueryColor", "CustomQueryEditorSelectionColor",
        ],
        .editorFont: ["CustomQueryEditorFont"],
        .resultsFont: ["fontSettings"],
        .reloadAfterSaving: ["ReloadAfterAddingRow", "ReloadAfterEditingRow", "ReloadAfterRemovingRow"],
        .sshProgram: ["SSHClientPath"],
        .cipherList: ["SSLCipherList"],
        // "Show hidden files" lives in the open panels the file choosers
        // share (Add Files…, SSH program/config/known hosts "Other file…").
        .accessibleFiles: ["SPSecureBookmarks", "SPStaleSecureBookmarks", "SPKnownHostsBookmarks",
                           "KeySelectionHiddenFilesVisibility"],
        .mcpStatus: [mcpServerEnabledKey],
        .mcpExportFolder: ["SPMCPExportPath"],
        .mcpAddress: [],
    ]

    /// Extra keys a dynamic choice writes besides its own key.
    static let dynamicSourceKeys: [String: [String]] = [
        "favorites": ["SelectLastFavoriteUsed"],
        "knownHosts": ["SSHConfigContainsUserKnownHostsFile"],
    ]

    static let panes: [SAClaudeSettingsPane] = [
        SAClaudeSettingsPane(id: .appearance, sections: [
            section("look", [
                row("appAppearance", .choice(key: "Appearance", source: fixed("appAppearance", [
                    ("matchMacOS", 0), ("light", 1), ("dark", 2),
                ]))),
                row("accentColour", .custom(.accent)),
                row("connectionColour", .choice(key: "ClaudeConnectionColourStyle", source: fixed("connectionColour", [
                    ("off", 0), ("underline", 1), ("namePill", 2), ("tabUnderline", 3), ("tabUnderlineAndNamePill", 4),
                ]))),
            ]),
            section("editorGridColours", [
                row("editorColours", .custom(.colourMode)),
                row("startFromTheme", .custom(.startFromTheme)),
                row("colourList", .custom(.colourRows)),
            ]),
            section("fonts", [
                row("editorFont", .custom(.editorFont)),
                row("resultsFont", .custom(.resultsFont)),
            ]),
            section("grids", [
                row("columnTypes", .toggle(key: "DisplayTableViewColumnTypes")),
                row("printGridLines", .toggle(key: "DisplayTableViewVerticalGridlines")),
            ]),
        ]),
        SAClaudeSettingsPane(id: .startup, sections: [
            section("whenOpens", [
                row("defaultFavourite", .choice(key: "DefaultFavorite", source: .dynamic("favorites"))),
                // "Last used" still auto-connects (the last favourite), so the
                // pill has no off state: indented, never disabled.
                row("autoConnect", .toggle(key: "AutoConnectToDefault"), parent: "defaultFavourite"),
                row("tabToOpen", .choice(key: "DefaultViewMode", source: fixed("tabToOpen", [
                    ("lastUsed", 0), ("structure", 1), ("content", 2), ("relations", 3),
                    ("tableInfo", 4), ("query", 5), ("triggers", 6),
                ]))),
                row("askBeforeQuitting", .toggle(key: "ApplicationPromptOnQuit")),
            ]),
            section("connecting", [
                row("connectTimeout", .number(key: "ConnectionTimeoutValue", unit: .seconds, range: 0...10_000, step: 1)),
                row("keepAlive", .toggle(key: "UseKeepAlive")),
                row("characterSet", .choice(key: "DefaultEncodingTag", source: .dynamic("encodings"))),
                row("readConnectionStrings", .toggle(key: "AutoCheckClipboardForConnectionStrings")),
            ]),
        ]),
        SAClaudeSettingsPane(id: .tablesData, sections: [
            section("loading", [
                row("pageSize", .toggleNumber(toggleKey: "LimitResults", numberKey: "LimitResultsValue",
                                              unit: .rows, range: 1...1_000_000, step: 1)),
                row("countRows", .choice(key: "TableRowCountQueryLevel", source: fixed("countRows", [
                    ("never", 0), ("smallTables", 1), ("always", 2),
                ]))),
                row("lazyLoadBlobs", .toggle(key: "LoadBlobsAsNeeded")),
            ]),
            section("showing", [
                row("nullText", .text(key: "NullValue")),
                row("tableComments", .toggle(key: "DisplayCommentsInTablesList")),
                row("filterDropZone", .toggle(key: "RuleFilterShowDropZone")),
            ]),
            section("editing", [
                row("longValueSheet", .toggleNumber(toggleKey: "EditInSheetForLongText",
                                                    numberKey: "EditInSheetForLongTextLengthThreshold",
                                                    unit: .characters, range: 1...1_000_000, step: 1)),
                row("multiLineSheet", .toggle(key: "EditInSheetForMultiLineText")),
                row("reloadAfterSaving", .custom(.reloadAfterSaving)),
                row("newColumnsAllowNull", .toggle(key: "NewFieldsAllowNulls")),
            ]),
        ]),
        SAClaudeSettingsPane(id: .queryEditor, sections: [
            section("typing", [
                row("keepIndentation", .toggle(key: "CustomQueryAutoIndent"), desc: false),
                row("softIndent", .toggleNumber(toggleKey: "CustomQuerySoftIndent", numberKey: "CustomQuerySoftIndentWidth",
                                                unit: .spaces, range: 1...32, step: 1)),
                row("tabWidth", .number(key: "CustomQueryEditorTabStopWidth", unit: .spaces, range: 1...20, step: 1)),
                row("closeBrackets", .toggle(key: "CustomQueryAutoPairCharacters")),
                row("uppercaseKeywords", .toggle(key: "CustomQueryAutoUppercaseKeywords")),
                row("dashComments", .toggle(key: "UseDashStyleForBlockComment")),
            ]),
            section("highlighting", [
                row("syntaxColouring", .toggle(key: "CustomQueryEnableSyntaxHighlighting"), desc: false),
                row("highlightStatement", .toggle(key: "CustomQueryHighlightCurrentQuery")),
                row("matchBrackets", .toggle(key: "CustomQueryEnableBracketHighlighting"), desc: false),
            ]),
            section("suggestions", [
                row("autoComplete", .toggleNumber(toggleKey: "CustomQueryAutoComplete", numberKey: "CustomQueryAutoCompleteDelay",
                                                  unit: .seconds, range: 0...5, step: 0.1)),
                // Indented but enabled: they also apply when Esc opens the list.
                row("completeBackticks", .toggle(key: "SPCustomQueryEditorCompleteWithBackticks"), parent: "autoComplete"),
                row("insertArguments", .toggle(key: "CustomQueryFunctionCompletionInsertsArguments"),
                    parent: "autoComplete", desc: false),
                row("autoHelp", .toggleNumber(toggleKey: "CustomQueryUpdateAutoHelp", numberKey: "CustomQueryAutoHelpDelay",
                                              unit: .seconds, range: 0.1...5, step: 0.1)),
            ]),
            section("history", [
                row("historySize", .number(key: "CustomQueryMaxHistoryItems", unit: .queries, range: 0...100, step: 1)),
                row("historyPerStatement", .toggle(key: "CustomQuerySaveHistoryIndividually")),
            ]),
        ]),
        SAClaudeSettingsPane(id: .safety, sections: [
            section("beforeChanges", [
                row("confirmChanges", .toggle(key: confirmChangesKey)),
                // Its own row: the second confirmation works whether or not changes are confirmed.
                row("askTwiceDelete", .toggle(key: "ShowWarningBeforeDeleteQuery")),
            ]),
            section("warnings", [
                row("warnNoRowsAffected", .toggle(key: "ShowNoAffectedRowsError")),
                row("warnHiddenDatabases", .toggle(key: "ShowWarningSkipShowDatabase")),
            ]),
        ]),
        SAClaudeSettingsPane(id: .queryConsole, sections: [
            section("logging", [
                row("logQueries", .toggle(key: logMasterKey)),
                row("logInterface", .toggle(key: "ConsoleEnableInterfaceLogging"),
                    parent: "logQueries", disabledWhenParentOff: true, info: false),
                row("logCustomQueries", .toggle(key: "ConsoleEnableCustomQueryLogging"),
                    parent: "logQueries", disabledWhenParentOff: true, info: false),
                row("logImportExport", .toggle(key: "ConsoleEnableImportExportLogging"),
                    parent: "logQueries", disabledWhenParentOff: true, desc: false, info: false),
                row("logErrors", .toggle(key: "ConsoleEnableErrorLogging"),
                    parent: "logQueries", disabledWhenParentOff: true, desc: false, info: false),
            ]),
        ]),
        SAClaudeSettingsPane(id: .sshSecurity, sections: [
            section("sshTunnels", [
                row("sshProgram", .custom(.sshProgram), desc: false),
                row("sshConfig", .choice(key: "ssh_config", source: .dynamic("sshConfig")), desc: false),
                row("knownHosts", .choice(key: "known_hosts", source: .dynamic("knownHosts")), desc: false),
            ]),
            section("encryption", [
                row("cipherOrder", .custom(.cipherList)),
            ]),
            section("fileAccess", [
                row("accessibleFiles", .custom(.accessibleFiles)),
            ]),
        ]),
        SAClaudeSettingsPane(id: .mcp, sections: [
            section("mcpServer", [
                row("mcpServer", .custom(.mcpStatus)),
                // Indented but enabled: they can be set before the server is on.
                row("mcpReadOnly", .toggle(key: "SPMCPReadOnly"), parent: "mcpServer"),
                row("mcpPort", .number(key: "SPMCPServerPort", unit: .none, range: 1024...65535, step: 1),
                    parent: "mcpServer", info: false),
                row("mcpExportFolder", .custom(.mcpExportFolder), parent: "mcpServer", info: false),
                row("mcpAddress", .custom(.mcpAddress), parent: "mcpServer"),
            ]),
        ]),
        SAClaudeSettingsPane(id: .updatesPrivacy, sections: [
            SAClaudeSettingsSection(id: "updatesPrivacy", titleKey: nil, rows: [
                row("checkUpdates", .toggle(key: "ShowUpdateAvailable")),
                row("shareAnalytics", .toggle(key: "SaveApplicationUsageAnalytics")),
            ]),
        ]),
    ]

    static func row(_ id: String) -> SAClaudeSettingRow? {
        rowsByID[id]?.row
    }

    static func pane(containing rowID: String) -> SAClaudeSettingsPaneID? {
        rowsByID[rowID]?.pane
    }

    /// Every defaults key one row writes, in display order.
    static func keys(for row: SAClaudeSettingRow) -> [String] {
        switch row.control {
        case .toggle(let key), .text(let key), .number(let key, _, _, _):
            return [key]
        case let .toggleNumber(toggleKey, numberKey, _, _, _):
            return [toggleKey, numberKey]
        case let .choice(key, source):
            if case .dynamic(let id) = source { return [key] + (dynamicSourceKeys[id] ?? []) }
            return [key]
        case .custom(let custom):
            return customKeys[custom] ?? []
        }
    }

    /// Every defaults key any row writes (not de-duplicated, so a key in two
    /// rows would show twice).
    static var allKeys: [String] {
        panes.flatMap { $0.sections.flatMap { $0.rows.flatMap(keys(for:)) } }
    }

    /// A dependent row with `disabledWhenParentOff` is enabled only while
    /// its parent's switch is on; every other row is always enabled.
    static func isEnabled(_ row: SAClaudeSettingRow, bool: (String) -> Bool) -> Bool {
        guard row.disabledWhenParentOff,
              let parentID = row.parentID,
              let key = self.row(parentID)?.control.toggleKey else { return true }
        return bool(key)
    }

    // MARK: Routing

    /// Where the window opens: a pane, and the row to scroll to (nil: the top of the pane).
    struct Destination: Equatable {
        let pane: SAClaudeSettingsPaneID
        let rowID: String?
    }

    /// The old Preferences panes, by their toolbar identifiers (SPConstants.m `SPPreferenceToolbar*`; Shortcuts and
    /// Favorites were never shown). Their controllers stay loaded and own the code many rows call.
    enum LegacyPane: String, CaseIterable {
        case general = "SPPreferenceToolbarGeneral"
        case tables = "SPPreferenceToolbarTables"
        case notifications = "SPPreferenceToolbarNotifications"
        case editor = "SPPreferenceToolbarEditor"
        case network = "SPPreferenceToolbarNetwork"
        case file = "SPPreferenceToolbarFile"
        case mcp = "SPPreferenceToolbarMCP"
    }

    /// `show(pane:revealRowID:)`: the row decides the pane when it is known (it is the more specific request); an
    /// unknown row still opens a known pane; nil when neither is known.
    static func destination(pane paneID: String?, rowID: String?) -> Destination? {
        if let rowID, let pane = pane(containing: rowID) {
            return Destination(pane: pane, rowID: rowID)
        }
        guard let paneID, let pane = SAClaudeSettingsPaneID(rawValue: paneID) else { return nil }
        return Destination(pane: pane, rowID: nil)
    }

    /// Where `displayPreferencePane:` with an old toolbar item lands; no item, or one never shown, opens the first pane.
    static func destination(forLegacyPane identifier: String?) -> Destination {
        switch identifier.flatMap(LegacyPane.init(rawValue:)) {
        case .general?, nil: return Destination(pane: .appearance, rowID: nil)
        case .tables?: return Destination(pane: .tablesData, rowID: nil)
        case .notifications?: return Destination(pane: .safety, rowID: nil)
        case .editor?: return Destination(pane: .queryEditor, rowID: nil)
        case .network?: return Destination(pane: .sshSecurity, rowID: nil)
        case .file?: return Destination(pane: .sshSecurity, rowID: "accessibleFiles")
        case .mcp?: return Destination(pane: .mcp, rowID: nil)
        }
    }

    /// The old pane controllers whose `preferencePaneWillBeShown` refresh runs when `pane` is shown: the panes its
    /// rows came from. The Files pane's refresh only reloads its list (it no longer opens the re-select panel; that is
    /// `regrantsStaleFiles(_:requested:)`).
    static func legacyPanes(for pane: SAClaudeSettingsPaneID) -> [LegacyPane] {
        switch pane {
        case .appearance: return [.general, .editor]        // appearance, title bar, results font, grids; accent, colours, editor font
        case .startup: return [.general]                    // favourite, view, quit, encoding, clipboard (timeout, keep-alive are plain keys: no Network refresh)
        case .tablesData: return [.tables, .general]        // loading, editing; table comments
        case .queryEditor: return [.editor, .general]       // typing, highlighting, suggestions; history
        case .safety, .queryConsole: return [.notifications]
        case .sshSecurity: return [.network, .file]         // SSH, ciphers; accessible files
        case .mcp: return [.mcp]
        case .updatesPrivacy: return [.notifications, .general] // updates; analytics
        }
    }

    /// Whether a request opens the stale-file re-select panel: only when the caller asked for it (the launch alert and
    /// the file prompts, `SAClaudeSettingsPointer.regrantsStaleFiles`) and the request lands on the accessible-files
    /// list, which it discloses. Switching panes, the sidebar and every other pointer never open it.
    static func regrantsStaleFiles(_ destination: Destination, requested: Bool) -> Bool {
        requested && destination.pane == .sshSecurity && destination.rowID == accessibleFilesRowID
    }

    static let accessibleFilesRowID = "accessibleFiles"

    // MARK: Building

    private static let rowsByID: [String: (row: SAClaudeSettingRow, pane: SAClaudeSettingsPaneID)] = {
        var map: [String: (row: SAClaudeSettingRow, pane: SAClaudeSettingsPaneID)] = [:]
        for pane in panes {
            for row in pane.sections.flatMap(\.rows) where map[row.id] == nil {
                map[row.id] = (row, pane.id)
            }
        }
        return map
    }()

    private static func section(_ id: String, _ rows: [SAClaudeSettingRow]) -> SAClaudeSettingsSection {
        SAClaudeSettingsSection(id: id, titleKey: "ClaudeSettings.section.\(id)", rows: rows)
    }

    private static func row(_ id: String, _ control: SAClaudeSettingControl, parent: String? = nil,
                            disabledWhenParentOff: Bool = false, desc: Bool = true, info: Bool = true) -> SAClaudeSettingRow {
        SAClaudeSettingRow(id: id, control: control, parentID: parent, disabledWhenParentOff: disabledWhenParentOff,
                           hasDescription: desc, hasInfo: info)
    }

    private static func fixed(_ rowID: String, _ options: [(String, Int)]) -> SAClaudeSettingChoiceSource {
        .fixed(options.map { ("ClaudeSettings.\(rowID).option.\($0.0)", $0.1) })
    }
}

// MARK: - Pointers from elsewhere

/// Messages and buttons outside the window that send people to a setting. Each names its place in the new words
/// ("Settings ▸ <pane> ▸ <row>", the catalog's own pane and row names) and, where it has a button, opens that pane on
/// that row (`SPPreferenceController.showSettings(for:)`). Only the launch alert and the file prompts ask for the
/// stale-file re-select panel.
@objc enum SAClaudeSettingsPointer: Int, CaseIterable {
    /// SPAppController launch alert "App Sandbox Issue" (stale bookmarks): "Open Settings" (was "Open Files Preferences").
    case launchStaleFiles
    /// SPConnectionController `_validateSSHConfigFile`: "Open Settings" (was "Go to Network Settings") and its message.
    case connectionSSHConfigFile
    /// SPNetworkPreferencePane known hosts (ADVANCED) "App Sandbox Issue" (missing bookmarks): "Request Access".
    case networkMissingFiles
    /// SPAppController+MCP: the server could not start (text only).
    case mcpPortError
    /// SPSSHTunnel: the debug header when a custom SSH binary is set (text only).
    case customSSHBinary
    /// SAAnalyticsConsentPolicy: the consent dialog (text only).
    case analyticsConsent
    /// SPSSHTunnel: the known hosts file is not writable, invalid or has a quote (text only).
    case knownHostsFile
    /// SPTableContent / SPCustomQuery: a save changed no rows (text only).
    case noRowsAffected
    /// SPTableContent: the second "Double Check" before deleting rows (text only).
    case deleteDoubleCheck
    /// SPMCPServer / SPAppController+MCP: read-only refusals sent to AI clients (text only, not localized).
    case mcpReadOnly
}

/// Where a pointer goes and the strings that name it.
struct SAClaudeSettingsPointerTarget: Equatable {
    let pane: SAClaudeSettingsPaneID
    let rowID: String
    /// Opening Settings from this pointer opens the stale-file re-select panel (when there are stale files).
    let regrantStaleFiles: Bool
    /// The pointer's button title key, when it has a button that opens Settings.
    let buttonKey: String?
    /// The en keys of its message texts; each names "Settings ▸ <pane> ▸ <row>".
    let messageKeys: [String]
}

extension SAClaudeSettingsPointer {
    static let openSettingsButtonKey = "ClaudeSettings.pointer.openSettings"

    var target: SAClaudeSettingsPointerTarget {
        typealias T = SAClaudeSettingsPointerTarget
        let files = SAClaudeSettingsCatalog.accessibleFilesRowID
        switch self {
        case .launchStaleFiles:
            return T(pane: .sshSecurity, rowID: files, regrantStaleFiles: true, buttonKey: Self.openSettingsButtonKey,
                     messageKeys: ["ClaudeSettings.pointer.staleFiles.one", "ClaudeSettings.pointer.staleFiles.many"])
        case .connectionSSHConfigFile:
            return T(pane: .sshSecurity, rowID: files, regrantStaleFiles: true, buttonKey: Self.openSettingsButtonKey,
                     messageKeys: ["ClaudeSettings.pointer.sshConfigFile.message"])
        case .networkMissingFiles:
            return T(pane: .sshSecurity, rowID: files, regrantStaleFiles: true, buttonKey: nil,
                     messageKeys: ["ClaudeSettings.pointer.missingFiles.one", "ClaudeSettings.pointer.missingFiles.many"])
        case .mcpPortError:
            return T(pane: .mcp, rowID: "mcpPort", regrantStaleFiles: false, buttonKey: nil,
                     messageKeys: ["ClaudeSettings.pointer.mcpPortError.message"])
        case .customSSHBinary:
            return T(pane: .sshSecurity, rowID: "sshProgram", regrantStaleFiles: false, buttonKey: nil,
                     messageKeys: ["ClaudeSettings.pointer.customSSHBinary.message"])
        case .analyticsConsent:
            return T(pane: .updatesPrivacy, rowID: "shareAnalytics", regrantStaleFiles: false, buttonKey: nil,
                     messageKeys: ["ClaudeSettings.pointer.analyticsConsent.message"])
        case .knownHostsFile:
            return T(pane: .sshSecurity, rowID: "knownHosts", regrantStaleFiles: false, buttonKey: nil,
                     messageKeys: ["ClaudeSettings.pointer.knownHosts.notWritable", "ClaudeSettings.pointer.knownHosts.invalid",
                                   "ClaudeSettings.pointer.knownHosts.quote"])
        case .noRowsAffected:
            return T(pane: .safety, rowID: "warnNoRowsAffected", regrantStaleFiles: false, buttonKey: nil,
                     messageKeys: ["ClaudeSettings.pointer.noRowsAffected.message"])
        case .deleteDoubleCheck:
            return T(pane: .safety, rowID: "askTwiceDelete", regrantStaleFiles: false, buttonKey: nil,
                     messageKeys: ["ClaudeSettings.pointer.deleteDoubleCheck.message"])
        case .mcpReadOnly:
            return T(pane: .mcp, rowID: "mcpReadOnly", regrantStaleFiles: false, buttonKey: nil, messageKeys: [])
        }
    }

    /// The request Settings gets from this pointer.
    var destination: SAClaudeSettingsCatalog.Destination {
        SAClaudeSettingsCatalog.Destination(pane: target.pane, rowID: target.rowID)
    }
}

/// The pointer table for Objective-C callers.
@objc final class SAClaudeSettingsPointers: NSObject {
    @objc static func paneID(for pointer: SAClaudeSettingsPointer) -> String { pointer.target.pane.rawValue }
    @objc static func rowID(for pointer: SAClaudeSettingsPointer) -> String { pointer.target.rowID }
    @objc static func regrantsStaleFiles(for pointer: SAClaudeSettingsPointer) -> Bool { pointer.target.regrantStaleFiles }

    /// The read-only refusals the MCP server sends to AI clients are not localized; they name the setting in English.
    @objc static let mcpReadOnlyPlace = "Settings \u{25B8} MCP server \u{25B8} Read only"
}
