//
//  SAConnectionWindowController.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  A standalone window controller that hosts the connection screen
//  independently from SPDatabaseDocument, enabling the connection
//  UI to be presented without creating a full document first.
//
//  Phase C3: the window now hosts the SwiftUI screen (SAFavoritesList +
//  SAConnectionFormView) rather than the XIB-backed SPConnectionController,
//  and connects through SAConnectionService directly. This is the first place
//  the C1b/C2 views actually run.
//

import AppKit
import SwiftUI

/// A standalone window controller that presents the connection screen.
///
/// When the user successfully connects, this controller creates a new
/// document tab (via TabManager) and hands off the established connection.
/// This decouples the "choose a server" flow from the document lifecycle.
///
/// Usage:
/// ```
/// let controller = SAConnectionWindowController()
/// controller.showWindow(nil)
/// ```
@objc class SAConnectionWindowController: NSWindowController, SAConnectionDelegate, NSWindowDelegate {

    // MARK: - Properties

    /// The connection service backing every attempt from this window.
    private let connectionService = SAConnectionService()

    /// The edited connection details, shared with the SwiftUI form.
    private let formModel = SAConnectionFormModel()

    /// The favorites tree, snapshotted for SwiftUI when the window opens.
    private var favorites: [SAFavoriteItem] = []

    /// The favorite currently selected in the sidebar.
    private var selection: SAFavoriteItem.ID?

    /// Set to true after a successful connection handoff to prevent
    /// windowWillClose from disconnecting the just-handed-off connection.
    private var connectionHandedOff = false

    /// Coordinator managing the view swap between connection and content views.
    /// In standalone mode, the content view is just an empty placeholder.
    private var viewCoordinator: SAConnectionViewCoordinator?

    /// The placeholder split view that stands in for the document's contentViewSplitter.
    /// The connection controller expects to hide this when showing the connection UI.
    private let placeholderSplitView = SPSplitView(frame: .zero)

    /// The container view hosting the connection UI.
    private let containerView = NSView(frame: .zero)

    /// The SwiftUI screen, once installed.
    private var hostingView: NSView?

    // MARK: - Lifecycle

    @objc convenience init() {
        self.init(window: nil)
        setupWindow()
    }

    private func setupWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = NSLocalizedString("Connect to Server", comment: "Standalone connection window title")
        window.center()
        window.minSize = NSSize(width: 700, height: 400)
        window.contentView = containerView

        // Add the placeholder split view so the coordinator can hide/show it
        placeholderSplitView.frame = containerView.bounds
        placeholderSplitView.autoresizingMask = [.width, .height]
        containerView.addSubview(placeholderSplitView)

        self.window = window
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        installConnectionScreen()
    }

    @objc override func showWindow(_ sender: Any?) {
        installConnectionScreen()
        super.showWindow(sender)
        window?.delegate = self
    }

    /// Cancel any in-progress connection when the window closes,
    /// unless we've already handed off a successful connection.
    func windowWillClose(_ notification: Notification) {
        guard !connectionHandedOff else { return }
        connectionService.cancel()
    }

    // MARK: - Connection screen

    /// Swaps the placeholder for the SwiftUI screen. Idempotent: `showWindow`
    /// can be called repeatedly on the same controller.
    private func installConnectionScreen() {
        guard hostingView == nil else { return }

        favorites = Self.loadFavorites()

        let screen = SAConnectionWindowView(
            favorites: favorites,
            model: formModel,
            onSelect: { [weak self] item in self?.applySelection(item) },
            onConnect: { [weak self] in self?.connectUsingForm() }
        )

        let hosting = NSHostingView(rootView: screen)
        hosting.frame = containerView.bounds
        hosting.autoresizingMask = [.width, .height]
        placeholderSplitView.isHidden = true
        containerView.addSubview(hosting)
        hostingView = hosting
    }

    /// Snapshot of the favorites tree as the pure SwiftUI model.
    private static func loadFavorites() -> [SAFavoriteItem] {
        guard let root = SPFavoritesController.shared().favoritesTree else { return [] }
        return SAFavoriteItem.tree(from: root)
    }

    /// Populates the form from the sidebar selection.
    private func applySelection(_ item: SAFavoriteItem) {
        selection = item.id

        switch item.kind {
        case .quickConnect:
            formModel.loadQuickConnect()
        case .group:
            // Groups are not connectable and carry no details to show.
            break
        case .favorite:
            formModel.load(favorite: Self.favoriteDictionary(withID: item.favoriteID))
        }
    }

    /// The favorite plist entry behind a sidebar row.
    ///
    /// Matched through `SAFavoriteItem.string(_:)`, the same normalization that
    /// produced the item's `favoriteID` — the stored value is usually an
    /// NSNumber, so comparing raw values would miss.
    private static func favoriteDictionary(withID favoriteID: String?) -> NSDictionary? {
        guard let favoriteID,
              let root = SPFavoritesController.shared().favoritesTree else { return nil }

        return allFavorites(under: root).first { favorite in
            SAFavoriteItem.string(favorite[SPFavoriteIDKey]) == favoriteID
        }
    }

    /// Every favorite dictionary in the tree, groups walked through.
    private static func allFavorites(under node: SPTreeNode) -> [NSDictionary] {
        if node.isGroup {
            return (node.children ?? [])
                .compactMap { $0 as? SPTreeNode }
                .flatMap { allFavorites(under: $0) }
        }

        guard let favorite = (node.representedObject as? SPFavoriteNode)?.nodeFavorite else { return [] }
        return [favorite as NSDictionary]
    }

    /// Validates and connects using whatever the form currently holds.
    private func connectUsingForm() {
        if let failure = formModel.validate() {
            showConnectionError(title: failure.alertTitle, detail: failure.alertMessage)
            return
        }

        let info = SAConnectionInfoObjC(info: formModel.info)

        // Passwords come from the form's own fields. Reading a saved favorite's
        // password out of the keychain is deliberately not wired here — the D1
        // decoder never carried passwords, and the keychain lookup needs the
        // account/service naming that still lives in SPConnectionController.
        connectDirectly(with: info,
                        password: formModel.info.password,
                        sshPassword: formModel.info.sshPassword)
    }

    // MARK: - SAConnectionDelegate

    func connectionDidEstablish(_ connection: SPMySQLConnection, info: SAConnectionInfoObjC) {
        // 1. Create a new document tab via TabManager
        guard let appDelegate = NSApp.delegate as? SPAppController else { return }
        let tabManager = appDelegate.tabManager
        let windowController = tabManager?.newWindowForTab()

        guard let document = windowController?.databaseDocument else { return }

        // 2. Hand off the established connection to the new document.
        // setConnection: transitions the document out of connection mode
        // into the database UI (same as the embedded flow's addConnectionToDocument).
        //
        // The document must become the connection's delegate first: neither
        // SAConnectionService nor -setConnection: assigns it, and without it the
        // framework falls back to its automatic retry with no query-error
        // logging, no no-connection alert, no keychain password prompt on
        // reconnect and no connection-loss decision UI (Codex, #2572).
        connection.setDelegate(document)
        document.setConnection(connection)

        // 3. Mark handoff complete so windowWillClose doesn't cancel the connection
        connectionHandedOff = true

        // 4. Close the standalone connection window
        close()
    }

    func connectionDidFail(withError error: String, detail: String?) {
        // The embedded SPConnectionController path shows its own error UI inline,
        // so this delegate method is a no-op for that flow.
        // The connectDirectly path shows its own alert below.
        NSLog("Standalone connection failed: %@", error)
    }

    /// Shows an error alert as a sheet on the standalone window.
    private func showConnectionError(title: String, detail: String?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail ?? ""
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        if let window = self.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Direct Connection via SAConnectionService

    /// Connects directly using SAConnectionService, bypassing SPConnectionController.
    /// Use this for programmatic connections (e.g. from a SwiftUI favorites list).
    @objc func connectDirectly(with info: SAConnectionInfoObjC, password: String, sshPassword: String) {
        connectionService.connect(
            with: info,
            preferences: .fromUserDefaults(),
            password: password,
            sshPassword: sshPassword,
            parentWindow: window
        ) { [weak self] result in
            guard let self = self else { return }

            if result.databaseSelectionFailed, let connection = result.connection {
                // Connected but couldn't select database — hand off anyway,
                // the document will show the database list.
                let wrappedInfo = SAConnectionInfoObjC(info: info.info)
                self.connectionDidEstablish(connection, info: wrappedInfo)
                return
            }

            if result.isSuccess, let connection = result.connection {
                let wrappedInfo = SAConnectionInfoObjC(info: info.info)
                self.connectionDidEstablish(connection, info: wrappedInfo)
            } else {
                // Build a meaningful error from all available fields
                let detail = [result.errorMessage, result.errorDetail]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                self.showConnectionError(
                    title: result.errorTitle ?? "Connection failed",
                    detail: detail.isEmpty ? nil : detail
                )
            }
        }
    }
}

// MARK: - The SwiftUI screen

/// The standalone window's content: the favorites sidebar beside the
/// connection form. This is the first place C1b's `SAFavoritesList` and C2's
/// `SAConnectionFormView` are actually hosted — until now both compiled but
/// nothing instantiated them.
private struct SAConnectionWindowView: View {

    let favorites: [SAFavoriteItem]
    @ObservedObject var model: SAConnectionFormModel

    /// Called when the sidebar selection changes, so the host can populate the
    /// form from the underlying favorite.
    var onSelect: (SAFavoriteItem) -> Void

    /// Called when the form's Connect button passes validation.
    var onConnect: () -> Void

    @State private var selection: SAFavoriteItem.ID?
    @State private var searchQuery = ""

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 360)

            SAConnectionFormView(model: model) { _ in onConnect() }
                .frame(minWidth: 420)
        }
        .onChange(of: selection) { newSelection in
            guard let newSelection,
                  let item = favorites.first(byID: newSelection) else { return }
            onSelect(item)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            SAFavoritesList(
                items: favorites,
                searchQuery: searchQuery,
                selection: $selection,
                // Double-clicking a favorite selects *and* connects, matching
                // -nodeDoubleClicked: in the AppKit list.
                onConnect: { item in
                    onSelect(item)
                    onConnect()
                }
            )

            Divider()

            TextField(text: $searchQuery, prompt: Text("Search", comment: "connection view : favorites search placeholder")) {
                Text("Search", comment: "connection view : favorites search placeholder")
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .padding(8)
        }
    }
}

// MARK: - SADatabaseDocumentProviding

/// Minimal conformance allowing SPConnectionController to function
/// without a full SPDatabaseDocument backing.
extension SAConnectionWindowController: SADatabaseDocumentProviding {

    @objc var contentViewSplitter: SPSplitView {
        return placeholderSplitView
    }

    @objc func databaseView() -> NSView {
        return containerView
    }

    @objc func parentWindowControllerWindow() -> NSWindow? {
        return window
    }

    @objc func setConnection(_ connection: SPMySQLConnection) {
        // In standalone mode, this path is not used — connection is
        // delivered via SAConnectionDelegate instead.
    }

    @objc var isProcessing: Bool {
        get { false }
        set { /* No tab progress indicator in standalone mode. */ }
    }

    @objc func updateWindowTitle(_ sender: Any) {
        // Could update the window title with connection status if desired.
    }
}
