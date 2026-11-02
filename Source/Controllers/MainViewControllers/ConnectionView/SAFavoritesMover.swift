//
//  SAFavoritesMover.swift
//  Sequel Ace
//
//  Moves favourites-tree nodes between positions and groups. Shared by the favourites outline's
//  drop handler and the connection screen's favourite-card grid so both persist a reorder the same
//  way. The index rules are mirrored (on ID arrays) by `SAClaudeFavoriteReorder.apply`.
//
//  App target only: `SPTreeNode` and `SPFavoritesController` are not part of the unit-test target.
//

import AppKit

@objc final class SAFavoritesMover: NSObject {

    /// Moves `nodes` into `target` (a group node; the favourites root's first child for the top level)
    /// at `index`, in order. `NSOutlineViewDropOnItemIndex` means "at the start of `target`".
    ///
    /// Each node is first removed from its old position: from `target` itself when it already lives
    /// there (the insertion index is then shifted down by one when the node preceded it), or from its
    /// other parent. Then favourites are saved and `delegate.favoritesListDidReorderNodes` is called.
    ///
    /// Reloading, expanding and selection are the caller's concern (outline or card grid).
    ///
    /// - Returns: `false` when there was nothing to move; no save or notification happens then.
    @objc static func move(_ nodes: [SPTreeNode],
                           into target: SPTreeNode,
                           at index: Int,
                           controller: SPFavoritesController,
                           delegate: SAFavoritesListDelegate?) -> Bool {
        guard !nodes.isEmpty else { return false }

        var insertIndex = index == NSOutlineViewDropOnItemIndex ? 0 : index
        let childArray = target.mutableChildren

        for node in nodes {
            let oldIndex = childArray.index(of: node)
            var newIndex = insertIndex

            if oldIndex != NSNotFound {
                childArray.removeObject(at: oldIndex)
                if insertIndex > oldIndex { newIndex -= 1 }
            } else {
                (node.parent as? SPTreeNode)?.mutableChildren.remove(node)
            }

            childArray.insert(node, at: newIndex)
            insertIndex = newIndex + 1
        }

        controller.saveFavorites()

        // Lets the owner reset sort state and post change notifications.
        delegate?.favoritesListDidReorderNodes?()

        return true
    }
}
