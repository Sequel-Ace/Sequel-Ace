//
//  SAConnectionViewCoordinator.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  Encapsulates the view swap logic that was previously inlined in
//  SPConnectionController, enabling different hosts (document vs standalone)
//  to provide their own view coordination strategy.
//

import AppKit

/// Coordinates the swap between the connection view and the database content view.
///
/// In the embedded (document) case, this hides the `contentViewSplitter`, shows
/// the connection view in its place, and reverses the swap on successful connection.
/// A standalone connection window can provide its own coordinator that simply
/// manages a single view.
@objc class SAConnectionViewCoordinator: NSObject {

    /// The main content view that gets hidden when the connection UI is shown.
    @objc private(set) weak var databaseContentView: NSSplitView?

    /// The container view that hosts either the connection view or the database content.
    @objc private(set) weak var containerView: NSView?

    @objc init(databaseContentView: NSSplitView, containerView: NSView) {
        self.databaseContentView = databaseContentView
        self.containerView = containerView
        super.init()
    }

    /// Hides the database content view and shows the connection view in its place.
    @objc func showConnectionView(_ connectionView: NSView) {
        guard let databaseContentView = databaseContentView else { return }
        databaseContentView.isHidden = true
        connectionView.frame = databaseContentView.frame
        containerView?.addSubview(connectionView)
    }

    /// Removes the connection view and restores the database content view.
    @objc(restoreDatabaseViewRemovingConnectionView:)
    func restoreDatabaseView(removingConnectionView connectionView: NSView) {
        connectionView.removeFromSuperviewWithoutNeedingDisplay()
        databaseContentView?.isHidden = false
    }
}
