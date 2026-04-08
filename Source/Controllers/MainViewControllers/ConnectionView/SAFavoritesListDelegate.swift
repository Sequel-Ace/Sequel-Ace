//
//  SAFavoritesListDelegate.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  Defines the callback protocol for the favorites list data source,
//  allowing SPConnectionController to react to selection changes without
//  the data source needing to know about connection forms.
//

import AppKit

/// Callbacks from the favorites list to its owner (e.g. SPConnectionController).
@objc protocol SAFavoritesListDelegate: AnyObject {

    /// The user selected a favorite (or Quick Connect). The owner should update
    /// the connection form fields.
    @objc func favoritesListSelectionDidChange(_ selectedNode: SPTreeNode?)

    /// The user double-clicked a favorite. The owner should initiate a connection.
    @objc func favoritesListNodeDoubleClicked(_ node: SPTreeNode)

    /// The user renamed a favorite. The owner should persist the new name.
    @objc func favoritesListDidRenameNode(_ node: SPTreeNode, to newName: String)

    /// The user reordered favorites via drag & drop. The owner should reset
    /// sort state and post change notifications.
    @objc optional func favoritesListDidReorderNodes()

    /// The user started or stopped editing a connection (for UI state sync).
    @objc optional func favoritesListEditingStateChanged(isEditing: Bool)
}
