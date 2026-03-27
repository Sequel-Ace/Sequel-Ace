//
//  SAFavoritesProviding.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  Abstracts access to connection favorites, decoupling consumers
//  from the SPFavoritesController singleton.
//

import Foundation

/// Protocol abstracting access to the connection favorites store.
///
/// Currently `SPFavoritesController` is a global singleton accessed directly throughout the codebase.
/// This protocol allows consumers to depend on an abstraction instead, enabling
/// testability and future replacement of the backing store.
@objc protocol SAFavoritesProviding: AnyObject {

    /// The root node of the favorites tree.
    @objc var favoritesTree: SPTreeNode { get }

    /// Save the current favorites to persistent storage.
    @objc func saveFavorites()

    /// Reload favorites from persistent storage.
    /// - Parameter save: Whether to save current state before reloading.
    @objc func reloadFavorites(save: Bool)

    /// Add a group node to the favorites tree.
    /// - Parameters:
    ///   - name: The display name for the group.
    ///   - parent: The parent node to add under, or nil for root.
    /// - Returns: The newly created group node.
    @objc func addGroupNode(withName name: String, parent: SPTreeNode?) -> SPTreeNode

    /// Add a favorite node to the favorites tree.
    /// - Parameters:
    ///   - data: The favorite's data dictionary.
    ///   - parent: The parent node to add under, or nil for root.
    /// - Returns: The newly created favorite node.
    @objc func addFavoriteNode(withData data: NSMutableDictionary, parent: SPTreeNode?) -> SPTreeNode

    /// Remove a favorite node from the tree.
    /// - Parameter node: The node to remove.
    @objc func removeFavoriteNode(_ node: SPTreeNode)
}

// MARK: - Default Implementation Wrapping the Singleton

/// Concrete implementation that delegates to `SPFavoritesController.sharedFavoritesController()`.
/// Use this as the default; inject a mock conforming to `SAFavoritesProviding` for tests.
@objc class SAFavoritesStore: NSObject, SAFavoritesProviding {

    @objc static let shared = SAFavoritesStore()

    private var controller: SPFavoritesController {
        SPFavoritesController.shared()
    }

    @objc var favoritesTree: SPTreeNode {
        controller.favoritesTree
    }

    @objc func saveFavorites() {
        controller.saveFavorites()
    }

    @objc func reloadFavorites(save: Bool) {
        controller.reloadFavorites(withSave: save)
    }

    @objc func addGroupNode(withName name: String, parent: SPTreeNode?) -> SPTreeNode {
        controller.addGroupNode(withName: name, asChildOf: parent)
    }

    @objc func addFavoriteNode(withData data: NSMutableDictionary, parent: SPTreeNode?) -> SPTreeNode {
        controller.addFavoriteNode(withData: data, asChildOf: parent)
    }

    @objc func removeFavoriteNode(_ node: SPTreeNode) {
        controller.removeFavoriteNode(node)
    }
}
