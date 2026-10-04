//
//  SAHelpViewerWindowController.swift
//  Sequel Ace
//
//  Created as part of the WebView to WKWebView migration.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Combine
import SwiftUI
import WebKit

/// Window controller of the MySQL Help Viewer panel, replacing the legacy
/// SPHelpViewerController and its HelpViewer.xib.
///
/// See SPHelpViewerClient for the class that provides the data for this controller
/// and which can be instantiated from within an XIB.
///
/// - Do NOT instantiate this class from within an XIB.
/// - None of the methods in this class are thread-safe — always use the UI thread!
@objc(SAHelpViewerWindowController)
final class SAHelpViewerWindowController: NSWindowController, NSWindowDelegate {

    @objc weak var dataSource: (any SPHelpViewerDataSource)?

    private let model = SAHelpViewerModel()
    private let webViewModel = SAWebViewModel()
    private var titleSubscription: AnyCancellable?
    private var appearanceObservation: NSKeyValueObservation?

    /// Name of the message handler the injected selection listener posts to.
    private static let selectionMessageHandlerName = "saHelpViewerSelection"

    // MARK: - Init

    @objc init() {
        // Frame, style and autosave name are ported from HelpViewer.xib.
        let panel = SAHelpViewerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 505, height: 308),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 351, height: 120)
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.title = SAHelpViewerModel.windowTitle(pageTitle: nil)

        super.init(window: panel)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(Self.makeSelectionUserScript())
        configuration.userContentController.add(
            SAHelpViewerSelectionHandler(model: model),
            name: Self.selectionMessageHandlerName
        )

        webViewModel.decideNavigationPolicy = { [weak self] navigationAction in
            self?.decidePolicy(for: navigationAction)
        }
        webViewModel.customizeContextMenu = { [weak self] menu in
            self?.customizeContextMenu(menu)
        }

        panel.contentView = NSHostingView(
            rootView: SAHelpViewerView(
                model: model,
                webViewModel: webViewModel,
                webViewConfiguration: configuration,
                onSubmitSearch: { [weak self] in self?.submitSearch() },
                onNavigate: { [weak self] navigation in self?.navigate(navigation) }
            )
        )
        panel.setFrameAutosaveName("MYSQL_HELP_WINDOW")
        panel.delegate = self
        panel.keyEquivalentHandler = { [weak self] event in
            self?.handleKeyEquivalent(event) ?? false
        }

        titleSubscription = webViewModel.$pageTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pageTitle in
                self?.window?.title = SAHelpViewerModel.windowTitle(pageTitle: pageTitle)
            }

        // The help template re-themes itself through a JS hook rather than by
        // being re-rendered (the legacy controller did the same via KVO).
        appearanceObservation = panel.observe(\.effectiveAppearance) { [weak self] _, _ in
            // Apple advises against doing slow work in the change handler, as it
            // may interrupt animations.
            DispatchQueue.main.async {
                self?.themeChanged()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported; use init()")
    }

    deinit {
        // The handler retains the model; drop it so the controller can be released.
        webViewModel.webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.selectionMessageHandlerName)
    }

    // MARK: - MySQL help (ObjC API)

    /// Shows the data for "HELP 'searchString'".
    @objc(showHelpFor:addToHistory:calledByAutoHelp:)
    func showHelp(for searchString: String?, addToHistory: Bool, calledByAutoHelp autoHelp: Bool) {
        var term = searchString ?? ""

        // If there's no search string, ignore if called by autohelp, show the index otherwise
        if term.isEmpty {
            if autoHelp { return }
            term = SPHelpViewerSearchTOC
        }

        let helpString = dataSource?.htmlHelpContents(forSearchString: term, autoHelp: autoHelp) ?? ""

        // init the Help window if not visible
        if window?.isVisible != true {
            // set default to search in MySQL help
            model.target = .mysql
            window?.orderFront(nil)
            model.focusSearchField()
        }

        guard !helpString.isEmpty else { return }

        if addToHistory {
            model.visit(term)
        }

        // The selection belongs to the document being replaced.
        model.clearSelection()

        webViewModel.loadHTMLString(helpString, baseURL: SAHelpViewerModel.internalHelpBaseURL)
    }

    // MARK: - Actions

    /// Shows the data for "HELP 'search word'" according to the selected target.
    private func submitSearch() {
        let searchString = model.searchString.trimmingCharacters(in: .whitespacesAndNewlines)

        switch model.target {
        case .page:
            findInPage(searchString, forward: true, beepWhenEmpty: false)
        case .web:
            guard !searchString.isEmpty else { return }
            dataSource?.openOnlineHelp(forTopic: searchString)
        case .mysql:
            showHelp(for: searchString, addToHistory: true, calledByAutoHelp: false)
        }
    }

    private func navigate(_ navigation: SAHelpViewerNavigation) {
        switch navigation {
        case .back:
            guard let term = model.goBack() else { return }
            showHelp(for: term, addToHistory: false, calledByAutoHelp: false)
        case .tableOfContents:
            showHelp(for: SPHelpViewerSearchTOC, addToHistory: true, calledByAutoHelp: false)
        case .forward:
            guard let term = model.goForward() else { return }
            showHelp(for: term, addToHistory: false, calledByAutoHelp: false)
        }
    }

    /// Find Next/Previous in the current page. Only the page target searches the
    /// rendered document, matching the legacy behaviour.
    private func findInPage(_ searchString: String, forward: Bool, beepWhenEmpty: Bool) {
        guard !searchString.isEmpty else {
            if beepWhenEmpty { NSSound.beep() }
            return
        }
        webViewModel.find(searchString, forward: forward) { found in
            if !found { NSSound.beep() }
        }
    }

    /// Shows the help for the text selected in the web view.
    @objc private func showHelpForWebViewSelection(_ sender: Any?) {
        // Trimmed like the online-docs action: the selection goes into a
        // `HELP '<term>'` query, where stray whitespace changes the result.
        let searchString = model.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        showHelp(for: searchString, addToHistory: true, calledByAutoHelp: false)
    }

    /// Shows MySQL's online documentation for the text selected in the web view.
    @objc private func searchInDocForWebViewSelection(_ sender: Any?) {
        let searchString = model.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchString.isEmpty else {
            NSSound.beep()
            return
        }
        dataSource?.openOnlineHelp(forTopic: searchString)
    }

    // MARK: - Keyboard shortcuts

    /// Ports the key equivalents the legacy XIB implemented with off-screen buttons.
    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard let command = SAHelpViewerModel.keyCommand(
            characters: event.charactersIgnoringModifiers ?? "",
            hasCommand: modifiers.contains(.command),
            hasShift: modifiers.contains(.shift)
        ) else {
            return false
        }

        switch command {
        case .findNextInPage:
            guard model.target == .page else { return true }
            findInPage(model.searchString.trimmingCharacters(in: .whitespacesAndNewlines), forward: true, beepWhenEmpty: true)
        case .findPreviousInPage:
            guard model.target == .page else { return true }
            findInPage(model.searchString.trimmingCharacters(in: .whitespacesAndNewlines), forward: false, beepWhenEmpty: true)
        case .focusSearchField:
            model.focusSearchField()
        case .selectTarget(let target):
            model.target = target
        case .makeTextLarger:
            webViewModel.makeTextLarger()
        case .makeTextSmaller:
            webViewModel.makeTextSmaller()
        }

        return true
    }

    // MARK: - Navigation policy

    private func decidePolicy(for navigationAction: WKNavigationAction) -> WKNavigationActionPolicy? {
        let decision = SAHelpViewerModel.policy(
            for: navigationAction.request.url,
            kind: SAHelpViewerModel.NavigationKind(navigationAction.navigationType)
        )

        switch decision {
        case .lookupTerm(let term):
            showHelp(for: term, addToHistory: true, calledByAutoHelp: false)
            return .cancel
        case .openExternally(let url):
            NSWorkspace.shared.open(url)
            return .cancel
        case .allow:
            return .allow
        case .deny:
            return .cancel
        }
    }

    // MARK: - Context menu

    /// Prunes the default WebKit items that don't apply to the help viewer and adds
    /// the two "Search in …" items for a selection, as the legacy
    /// `-webView:contextMenuItemsForElement:defaultMenuItems:` did.
    private func customizeContextMenu(_ menu: NSMenu) {
        let identifiers = menu.items.compactMap { $0.identifier?.rawValue }

        let prunedItems = menu.items.filter { item in
            guard let identifier = item.identifier?.rawValue else { return false }
            return SAHelpViewerModel.prunedContextMenuIdentifiers.contains(identifier)
        }
        for item in prunedItems {
            menu.removeItem(item)
        }

        guard SAHelpViewerModel.offersSelectionSearchItems(
            selectedText: model.selectedText,
            menuItemIdentifiers: identifiers
        ) else {
            return
        }

        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }

        let searchInDoc = NSMenuItem(
            title: NSLocalizedString("Search in MySQL Documentation", comment: "Search in MySQL Documentation"),
            action: #selector(searchInDocForWebViewSelection(_:)),
            keyEquivalent: ""
        )
        searchInDoc.target = self
        menu.insertItem(searchInDoc, at: 0)

        let searchInHelp = NSMenuItem(
            title: NSLocalizedString("Search in MySQL Help", comment: "Search in MySQL Help"),
            action: #selector(showHelpForWebViewSelection(_:)),
            keyEquivalent: ""
        )
        searchInHelp.target = self
        menu.insertItem(searchInHelp, at: 0)
    }

    // MARK: - Theme

    private func themeChanged() {
        guard let appearance = window?.effectiveAppearance else { return }

        let match = appearance.bestMatch(from: [.aqua, .darkAqua])
        guard let match else { return }

        webViewModel.evaluateJavaScript(
            SAHelpViewerModel.themeChangeScript(isDarkAppearance: match == .darkAqua)
        )
    }

    // MARK: - Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // -windowShouldClose: is the only method that will ONLY be invoked when the
        // user closes the window (or by -performClose:).
        NotificationCenter.default.post(name: .SPUserClosedHelpViewer, object: self)
        return true
    }

    // MARK: - Selection bridge

    /// Mirrors the document's selection into the model. WKWebView has no synchronous
    /// selection accessor, but the context menu has to be built synchronously.
    private static func makeSelectionUserScript() -> WKUserScript {
        let source = """
        document.addEventListener('selectionchange', function() {
            window.webkit.messageHandlers.\(selectionMessageHandlerName).postMessage(String(window.getSelection()));
        });
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }
}

/// Receives the selection messages. Holds the model weakly so the user content
/// controller's strong reference to the handler doesn't retain the window controller.
private final class SAHelpViewerSelectionHandler: NSObject, WKScriptMessageHandler {

    private weak var model: SAHelpViewerModel?

    init(model: SAHelpViewerModel) {
        self.model = model
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        model?.selectedText = message.body as? String ?? ""
    }
}

/// Panel that offers the window's key equivalents before the responder chain sees
/// them, so they work regardless of whether the search field or the page has focus.
private final class SAHelpViewerPanel: NSPanel {

    var keyEquivalentHandler: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private extension SAHelpViewerModel.NavigationKind {

    init(_ navigationType: WKNavigationType) {
        switch navigationType {
        case .linkActivated: self = .linkActivated
        case .backForward: self = .backForward
        case .reload: self = .reload
        case .formSubmitted: self = .formSubmitted
        case .formResubmitted: self = .formResubmitted
        default: self = .other
        }
    }
}
