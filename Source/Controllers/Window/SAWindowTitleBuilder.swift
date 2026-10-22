//
//  SAWindowTitleBuilder.swift
//  Sequel Ace
//
//  Pure title-string composition for the document window and its tab.
//  Extracted from -[SPDatabaseDocument updateWindowTitle:] and
//  -[SPDatabaseDocument displayName] as Phase A4 of the modernization
//  follow-up plan. No AppKit or ObjC dependencies — kept in this form so
//  the file can be compiled into the Unit Tests target without a
//  bridging header (same pattern as SAViewMode and SADatabaseListManager).
//

import Foundation

/// Result of composing window and tab titles. Two strings because they
/// can diverge (e.g. the window prepends a path component or MySQL
/// version, while the tab stays compact).
@objc final class SAWindowTitleResult: NSObject {
    @objc let windowTitle: String
    @objc let tabTitle: String

    @objc init(windowTitle: String, tabTitle: String) {
        self.windowTitle = windowTitle
        self.tabTitle = tabTitle
        super.init()
    }
}

/// The window title around the connection's name pill (see `SAWindowTitleBuilder.namePillParts`).
struct SAWindowNamePillParts: Equatable {
    /// The `.spf` file's `"<fileName> — "`, or "".
    let prefix: String
    /// The connection's name, shown in the pill.
    let name: String
    /// "db/table" (or "db"), "" when no database is selected.
    let rest: String
}

/// Three-state classification used by the title composer. Mirrors the
/// branching in the original `-updateWindowTitle:`.
@objc enum SAWindowConnectionState: Int {
    case connecting
    case disconnected
    case connected
}

@objc final class SAWindowTitleBuilder: NSObject {

    /// Compose the window and tab titles for the document.
    ///
    /// Branches:
    ///   - `.connecting` — both strings are "Connecting…", no path prefix.
    ///   - `.disconnected` — `<path — >?<bundleName>`, both strings equal.
    ///   - `.connected` — `<path — >?<(MySQL X) >?<connectionName>[/db[/table]]`
    ///     for the window; same minus the path-and-version preamble for
    ///     the tab.
    ///
    /// The path prefix (`"<fileName> — "`) is included only when there's
    /// a file URL and the document has been given a name (i.e. is not
    /// "Untitled"). The (MySQL X) chunk only appears when the user has
    /// toggled the corresponding preference.
    @objc static func buildTitle(
        connectionState: SAWindowConnectionState,
        filePath: String?,
        isUntitled: Bool,
        bundleName: String,
        connectionName: String,
        database: String?,
        table: String?,
        mySQLVersion: String?,
        showServerVersionInTitle: Bool
    ) -> SAWindowTitleResult {
        let pathName = pathPrefix(filePath: filePath, isUntitled: isUntitled)

        switch connectionState {
        case .connecting:
            let title = NSLocalizedString("Connecting…",
                                          comment: "window title string indicating that sp is connecting")
            return SAWindowTitleResult(windowTitle: title, tabTitle: title)

        case .disconnected:
            let title = pathName + bundleName
            return SAWindowTitleResult(windowTitle: title, tabTitle: title)

        case .connected:
            var windowTitle = pathName
            if showServerVersionInTitle, let version = mySQLVersion, !version.isEmpty {
                windowTitle += "(MySQL \(version)) "
            }
            windowTitle += connectionName
            var tabTitle = connectionName

            if let database = database, !database.isEmpty {
                windowTitle += "/\(database)"
                tabTitle += "/\(database)"
            }
            if let table = table, !table.isEmpty {
                windowTitle += "/\(table)"
                tabTitle += "/\(table)"
            }
            return SAWindowTitleResult(windowTitle: windowTitle, tabTitle: tabTitle)
        }
    }

    /// The `displayName` returned to `NSDocument` for save panels and
    /// the proxy icon. Behaves the same as the original method:
    ///   - Disconnected: `<path — >?<bundleName>` (same as the title).
    ///   - Connected: just the file's last path component (may be empty
    ///     if there is no file URL — the original returned the same).
    @objc static func displayName(
        isConnected: Bool,
        filePath: String?,
        isUntitled: Bool,
        bundleName: String
    ) -> String {
        if !isConnected {
            return pathPrefix(filePath: filePath, isUntitled: isUntitled) + bundleName
        }
        guard let filePath = filePath, !filePath.isEmpty else { return "" }
        return (filePath as NSString).lastPathComponent
    }

    /// The window's subtitle: the server version, when the user shows it, now that the title itself no longer carries it.
    @objc static func subtitle(connectionState: SAWindowConnectionState, mySQLVersion: String?, showServerVersionInTitle: Bool) -> String {
        guard connectionState == .connected, showServerVersionInTitle, let version = mySQLVersion, !version.isEmpty else { return "" }
        return "MySQL \(version)"
    }

    /// The window title split for the connection's name pill: what comes before the pill (the `.spf` file's
    /// `"<fileName> — "`, else ""), the connection's name in the pill, and the "db/table" after it.
    ///
    /// `nil` when the title is not a connected one for `connectionName` (connecting, disconnected, no name), so
    /// the window keeps its plain title. The name is matched as a whole against the tab title, which starts with
    /// it, so a "/" inside the name stays in the pill.
    static func namePillParts(windowTitle: String, tabTitle: String, connectionName: String) -> SAWindowNamePillParts? {
        guard !connectionName.isEmpty, tabTitle.hasPrefix(connectionName), windowTitle.hasSuffix(tabTitle) else { return nil }
        var rest = tabTitle.dropFirst(connectionName.count)
        // The name must be the whole first component: "Local" is not the name of a "Localhost/shop" title.
        guard rest.isEmpty || rest.hasPrefix("/") else { return nil }
        if rest.hasPrefix("/") { rest = rest.dropFirst() }
        return SAWindowNamePillParts(prefix: String(windowTitle.dropLast(tabTitle.count)), name: connectionName, rest: String(rest))
    }

    /// `<fileName> — ` when there is a real file URL and the document has
    /// been given a name; empty string otherwise. The em dash and spaces
    /// match the format used by the original method so the assembled
    /// title matches byte-for-byte.
    private static func pathPrefix(filePath: String?, isUntitled: Bool) -> String {
        guard let filePath = filePath, !filePath.isEmpty, !isUntitled else { return "" }
        return "\((filePath as NSString).lastPathComponent) — "
    }
}
