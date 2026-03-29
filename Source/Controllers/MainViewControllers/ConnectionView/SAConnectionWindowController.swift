//
//  SAConnectionWindowController.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  A standalone window controller that hosts the connection screen
//  independently from SPDatabaseDocument, enabling the connection
//  UI to be presented without creating a full document first.
//

import AppKit

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
@objc class SAConnectionWindowController: NSWindowController, SAConnectionDelegate {

    // MARK: - Properties

    /// The connection controller managing the favorites list and connection logic.
    private var connectionController: SPConnectionController?

    /// The connection service for direct (non-UI-controller) connection attempts.
    private let connectionService = SAConnectionService()

    /// Coordinator managing the view swap between connection and content views.
    /// In standalone mode, the content view is just an empty placeholder.
    private var viewCoordinator: SAConnectionViewCoordinator?

    /// The placeholder split view that stands in for the document's contentViewSplitter.
    /// The connection controller expects to hide this when showing the connection UI.
    private let placeholderSplitView = SPSplitView(frame: .zero)

    /// The container view hosting the connection UI.
    private let containerView = NSView(frame: .zero)

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
        setupConnectionController()
    }

    @objc override func showWindow(_ sender: Any?) {
        if connectionController == nil {
            setupConnectionController()
        }
        super.showWindow(sender)
    }

    // MARK: - Connection Controller Setup

    private func setupConnectionController() {
        guard connectionController == nil else { return }

        let controller = SPConnectionController(document: self)
        controller?.connectionDelegate = self
        connectionController = controller
    }

    // MARK: - SAConnectionDelegate

    func connectionDidEstablish(_ connection: SPMySQLConnection, info: SAConnectionInfoObjC) {
        // 1. Create a new document tab via TabManager
        guard let appDelegate = NSApp.delegate as? SPAppController else { return }
        let tabManager = appDelegate.tabManager
        let windowController = tabManager?.newWindowForTab()

        guard let document = windowController?.databaseDocument else { return }

        // 2. Hand off the established connection to the new document
        document.setConnection(connection)

        // 3. Close the standalone connection window
        close()
    }

    func connectionDidFail(withError error: String, detail: String?) {
        // The connection controller already shows error UI inline,
        // so we don't need to do anything extra here.
        NSLog("Standalone connection failed: %@", error)
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

            if result.isSuccess, let connection = result.connection {
                let wrappedInfo = SAConnectionInfoObjC(info: info.info)
                self.connectionDidEstablish(connection, info: wrappedInfo)
            } else {
                self.connectionDidFail(
                    withError: result.errorTitle ?? "Connection failed",
                    detail: result.errorDetail
                )
            }
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

    @objc func setIsProcessing(_ value: Bool) {
        // No tab progress indicator in standalone mode.
    }

    @objc func updateWindowTitle(_ sender: Any) {
        // Could update the window title with connection status if desired.
    }
}
