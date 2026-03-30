//
//  SADatabaseDocumentProviding.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  Captures the interface that SPConnectionController needs from SPDatabaseDocument,
//  enabling the connection controller to work with any conforming host — not just
//  the concrete SPDatabaseDocument class.
//

import AppKit

/// Protocol capturing what the connection controller needs from its host document/window.
///
/// SPConnectionController currently depends on SPDatabaseDocument via a concrete pointer
/// and even accesses its ivars directly. This protocol defines the minimal surface area
/// needed, allowing the connection controller to accept any conforming object.
@objc protocol SADatabaseDocumentProviding: AnyObject {

    /// The main split view that the connection controller hides when showing the connection UI
    /// and restores when a connection is established.
    @objc var contentViewSplitter: SPSplitView { get }

    /// The parent view where the connection view is embedded.
    @objc func databaseView() -> NSView

    /// The window associated with this document, used for toolbar and sheet operations.
    @objc func parentWindowControllerWindow() -> NSWindow?

    /// Called when a connection is successfully established, to hand off the connection
    /// to the document for distributing to sub-controllers.
    @objc func setConnection(_ connection: SPMySQLConnection)

    /// Toggles the processing state indicator for this document's tab.
    /// Note: SPDatabaseDocument satisfies this via its synthesized `isProcessing` property setter.
    /// Standalone hosts (SAConnectionWindowController) implement this as a no-op.
    @objc var isProcessing: Bool { get set }

    /// Updates the window title to reflect connection state.
    @objc func updateWindowTitle(_ sender: Any)
}
