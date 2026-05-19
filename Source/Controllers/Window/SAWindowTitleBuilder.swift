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

    /// `<fileName> — ` when there is a real file URL and the document has
    /// been given a name; empty string otherwise. The em dash and spaces
    /// match the format used by the original method so the assembled
    /// title matches byte-for-byte.
    private static func pathPrefix(filePath: String?, isUntitled: Bool) -> String {
        guard let filePath = filePath, !filePath.isEmpty, !isUntitled else { return "" }
        return "\((filePath as NSString).lastPathComponent) — "
    }
}
