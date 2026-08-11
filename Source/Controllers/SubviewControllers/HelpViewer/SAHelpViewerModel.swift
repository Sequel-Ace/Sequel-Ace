//
//  SAHelpViewerModel.swift
//  Sequel Ace
//
//  Created as part of the WebView to WKWebView migration.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Combine
import Foundation

/// Search target of the help viewer's search field (legacy `HelpTarget`).
/// Raw values match the segment indexes of the target selector.
enum SAHelpTarget: Int, CaseIterable {

    case mysql = 0
    case page = 1
    case web = 2

    /// Ports the legacy `-helpTargetValidation`: searching the MySQL help is
    /// incremental (the search field sends an action per keystroke), while page
    /// and web searches are only submitted with Return.
    var sendsWholeSearchString: Bool {
        self != .mysql
    }
}

/// The decision the navigation policy makes for a single navigation action. The
/// `WKNavigationDelegate` only executes what this describes, which keeps the
/// routing matrix a pure, unit-testable function.
enum SAHelpNavigationDecision: Equatable {

    /// An internal help link was clicked; look the term up via the data source.
    case lookupTerm(String)
    /// A real web link was clicked; hand it to the system browser.
    case openExternally(URL)
    /// Let WebKit proceed (the `loadHTMLString` navigation itself).
    case allow
    /// Cancel the navigation without further action.
    case deny
}

/// State and pure decision logic of the MySQL help viewer window.
///
/// Deliberately free of AppKit, WebKit and project Objective-C types: the file is
/// a member of both the app and the "Unit Tests" target (which has no bridging
/// header), so everything in here must compile standalone.
final class SAHelpViewerModel: ObservableObject {

    /// Legacy parity: the old controller capped the WebView's back/forward list
    /// with `[[helpWebView backForwardList] setCapacity:20]`. Without a cap the
    /// term history grows unbounded — MySQL-target searches push an entry per
    /// keystroke, because that target searches incrementally.
    static let historyCapacity = 20

    /// Scheme of the base URL the generated help HTML is loaded with. Topic links in
    /// that HTML are relative (`<a href='SELECT'>`), so they resolve against this base
    /// and a clicked link arrives as `sequelace-help://help/SELECT` — which is how the
    /// policy recognises an internal lookup.
    ///
    /// The base URL must be explicit: the legacy `applewebdata://` URLs came from
    /// WebView's synthetic base and from hand-made `WebHistoryItem`s, whereas WKWebView
    /// loads a nil-base document as `about:blank`, against which a relative href
    /// resolves to a scheme-less relative URL that no policy could route.
    /// Nothing ever loads this scheme — the policy always cancels the navigation.
    static let internalHelpScheme = "sequelace-help"

    /// Base URL the help HTML is rendered with. See `internalHelpScheme`.
    static let internalHelpBaseURL = URL(string: "\(internalHelpScheme)://help/")

    /// Schemes a clicked link may be opened with in the user's browser. The help HTML
    /// is generated from server-supplied text, so anything else (`file:`, `javascript:`,
    /// custom app schemes) is dropped rather than handed to the system.
    static let externallyOpenableSchemes: Set<String> = ["http", "https", "ftp"]

    // MARK: - Search field state

    @Published var searchString: String = ""
    @Published var target: SAHelpTarget = .mysql

    /// Bumped to move the keyboard focus into the search field (⌘F, window opening).
    @Published private(set) var focusSearchFieldRequest: Int = 0

    /// Text currently selected in the web view, kept up to date by the injected
    /// `selectionchange` listener. Replaces the legacy `selectedDOMRange.text`,
    /// which has no WKWebView equivalent that could be read synchronously while
    /// the context menu is being built.
    var selectedText: String = ""

    func focusSearchField() {
        focusSearchFieldRequest += 1
    }

    // MARK: - Term history

    /// Visited help terms, oldest first. The legacy controller kept synthetic
    /// `WebHistoryItem`s in the WebView's back/forward list; every render was a
    /// `loadHTMLString`, so a plain term stack reproduces it exactly.
    @Published private(set) var history: [String] = []

    /// Index of the currently displayed term in `history`, or -1 when empty.
    @Published private(set) var historyIndex: Int = -1

    var currentTerm: String? {
        history.indices.contains(historyIndex) ? history[historyIndex] : nil
    }

    var canGoBack: Bool { historyIndex > 0 }

    var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }

    /// Records a newly displayed term: drops the forward entries, appends, and
    /// evicts the oldest entries beyond `historyCapacity`.
    ///
    /// Re-visiting the term that is already displayed is not recorded, so that
    /// incremental searches and repeated clicks on the same link don't fill the
    /// history with adjacent duplicates.
    @discardableResult
    func visit(_ term: String) -> Bool {
        guard !term.isEmpty, term != currentTerm else { return false }

        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(term)
        historyIndex = history.count - 1

        let overflow = history.count - Self.historyCapacity
        if overflow > 0 {
            history.removeFirst(overflow)
            historyIndex -= overflow
        }

        return true
    }

    /// Steps back one term and returns it, or nil when there is nothing to go back to.
    func goBack() -> String? {
        guard canGoBack else { return nil }
        historyIndex -= 1
        return history[historyIndex]
    }

    /// Steps forward one term and returns it, or nil when there is nothing to go forward to.
    func goForward() -> String? {
        guard canGoForward else { return nil }
        historyIndex += 1
        return history[historyIndex]
    }

    // MARK: - Navigation policy (pure)

    /// The navigation types the policy distinguishes; mirrors the `WKNavigationType`
    /// cases the delegate maps onto, without importing WebKit here.
    enum NavigationKind {
        case linkActivated
        case backForward
        case reload
        case formSubmitted
        case formResubmitted
        case other
    }

    /// Ports the legacy `-webView:decidePolicyForNavigationAction:…` matrix:
    /// an internal link goes to the help lookup, a web link opens in the browser,
    /// the `loadHTMLString` navigation itself is allowed, everything else is dropped.
    static func policy(for url: URL?, kind: NavigationKind) -> SAHelpNavigationDecision {
        // `.other` covers the loadHTMLString navigation that renders every page.
        guard kind != .other else { return .allow }

        guard let url, kind == .linkActivated else { return .deny }

        if url.scheme == internalHelpScheme {
            // `lastPathComponent` is percent-decoded, so topics with spaces
            // ("ALTER TABLE") arrive as typed in the help HTML.
            let term = url.absoluteURL.lastPathComponent
            // "/" is what the bare base URL yields (an empty or root-relative href).
            guard !term.isEmpty, term != "/" else { return .deny }
            return .lookupTerm(term)
        }

        guard let scheme = url.scheme?.lowercased(), Self.externallyOpenableSchemes.contains(scheme) else {
            return .deny
        }

        return .openExternally(url)
    }

    // MARK: - Window title

    /// "MySQL Help" with the rendered page's title in parentheses, matching the
    /// legacy `mainFrameTitle` observer.
    static func windowTitle(pageTitle: String?) -> String {
        let title = NSLocalizedString("MySQL Help", comment: "mysql help")
        guard let pageTitle, !pageTitle.isEmpty else { return title }
        return "\(title) (\(pageTitle))"
    }

    // MARK: - Theme

    /// JavaScript calling the help template's theme hook, as the legacy
    /// `-themeChanged` did on `effectiveAppearance` changes.
    static func themeChangeScript(isDarkAppearance: Bool) -> String {
        "window.onThemeChange('\(isDarkAppearance ? "dark" : "light")')"
    }

    // MARK: - Context menu (pure)

    /// WebKit's identifiers for the default context-menu items that make no sense
    /// in the help viewer: link/image/media handling, page reloads, editing, and
    /// WebKit's own back/forward (this window navigates its own term history).
    ///
    /// The `WKMenuItemIdentifier…` constants are not declared in the public SDK
    /// headers, so the identifier strings are compared literally rather than
    /// linked against; unknown items are left in place.
    static let prunedContextMenuIdentifiers: Set<String> = [
        "WKMenuItemIdentifierCopyImage",
        "WKMenuItemIdentifierCopyLink",
        "WKMenuItemIdentifierCopyMediaLink",
        "WKMenuItemIdentifierDownloadImage",
        "WKMenuItemIdentifierDownloadLinkedFile",
        "WKMenuItemIdentifierDownloadMedia",
        "WKMenuItemIdentifierGoBack",
        "WKMenuItemIdentifierGoForward",
        "WKMenuItemIdentifierOpenFrameInNewWindow",
        "WKMenuItemIdentifierOpenImageInNewWindow",
        "WKMenuItemIdentifierOpenLink",
        "WKMenuItemIdentifierOpenLinkInNewWindow",
        "WKMenuItemIdentifierOpenMediaInNewWindow",
        "WKMenuItemIdentifierPaste",
        "WKMenuItemIdentifierReload"
    ]

    /// Menu items WebKit only offers when the click was on a live link; their
    /// presence stands in for the legacy `WebElementLinkIsLive` flag.
    private static let linkContextMenuIdentifiers: Set<String> = [
        "WKMenuItemIdentifierCopyLink",
        "WKMenuItemIdentifierDownloadLinkedFile",
        "WKMenuItemIdentifierOpenLink",
        "WKMenuItemIdentifierOpenLinkInNewWindow"
    ]

    /// Legacy parity: the two "Search in …" items are offered for a selection,
    /// but not when the click was on a link.
    static func offersSelectionSearchItems(selectedText: String, menuItemIdentifiers: [String]) -> Bool {
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !menuItemIdentifiers.contains { linkContextMenuIdentifiers.contains($0) }
    }

    // MARK: - Keyboard shortcuts (pure)

    /// The window's key equivalents, which the legacy XIB implemented with a row of
    /// off-screen buttons.
    enum KeyCommand: Equatable {
        case findNextInPage
        case findPreviousInPage
        case focusSearchField
        case selectTarget(SAHelpTarget)
        case makeTextLarger
        case makeTextSmaller
    }

    /// Maps a key event to a command. `characters` is expected to be
    /// `charactersIgnoringModifiers`; its case is irrelevant, `hasShift` decides.
    static func keyCommand(characters: String, hasCommand: Bool, hasShift: Bool) -> KeyCommand? {
        guard hasCommand else { return nil }

        switch characters.lowercased() {
        case "+", "=": return .makeTextLarger
        case "-": return .makeTextSmaller
        case "f": return hasShift ? nil : .focusSearchField
        case "g": return hasShift ? .findPreviousInPage : .findNextInPage
        case "m": return hasShift ? .selectTarget(.mysql) : nil
        case "p": return hasShift ? .selectTarget(.page) : nil
        case "w": return hasShift ? .selectTarget(.web) : nil
        default: return nil
        }
    }
}
