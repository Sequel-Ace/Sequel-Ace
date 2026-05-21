//
//  SAFavoriteItem+Tree.swift
//  Sequel Ace
//
//  Phase C1b: bridges the AppKit favorites tree (`SPTreeNode` of
//  `SPGroupNode` / `SPFavoriteNode`) into the value-type
//  `SAFavoriteItem` model that the SwiftUI list consumes.
//
//  Kept separate from `SAFavoriteItem.swift` because it touches
//  project-specific ObjC types and the `SPFavorite*Key` extern
//  constants (bridging-header dependency) — so this file is
//  app-target only, while the pure model + filter stays testable.
//

import AppKit

extension SAFavoriteItem {

    /// Build the SwiftUI model forest from the live favorites tree.
    ///
    /// - Parameters:
    ///   - root: the favorites tree root (`SPFavoritesController.favoritesTree`).
    ///   - includeQuickConnect: when `true` (default), a virtual
    ///     Quick Connect item is prepended, mirroring
    ///     `SAFavoritesListDataSource`.
    static func tree(from root: SPTreeNode, includeQuickConnect: Bool = true) -> [SAFavoriteItem] {
        var items: [SAFavoriteItem] = []

        if includeQuickConnect {
            items.append(SAFavoriteItem(
                id: "quickConnect",
                kind: .quickConnect,
                name: NSLocalizedString("Quick Connect", comment: "Quick connect item label").uppercased()
            ))
        }

        let topLevel = (root.children ?? []).compactMap { $0 as? SPTreeNode }
        for node in topLevel {
            items.append(build(node))
        }
        return items
    }

    /// Recursively convert one `SPTreeNode`.
    ///
    /// Identity comes from the underlying `SPTreeNode` instance, not a
    /// positional index path: the favorites tree owns persistent
    /// `SPTreeNode` objects for the lifetime of the session, so the
    /// address is stable across model rebuilds *and* unique per node —
    /// reordering, inserting, or removing siblings doesn't change a
    /// surviving node's id, so SwiftUI `List(selection:)` keeps the
    /// right row selected. (Favorites still prefer their persistent
    /// `favoriteID`, which is nicer for resolving a selection back to
    /// the favorite dictionary; the node-address id is the fallback.)
    private static func build(_ node: SPTreeNode) -> SAFavoriteItem {
        let nodeAddress = UInt(bitPattern: Unmanaged.passUnretained(node).toOpaque())

        if node.isGroup {
            let group = node.representedObject as? SPGroupNode
            let children = (node.children ?? [])
                .compactMap { $0 as? SPTreeNode }
                .map { build($0) }
            return SAFavoriteItem(
                id: "grp:\(nodeAddress)",
                kind: .group,
                name: group?.nodeName ?? "",
                children: children
            )
        }

        let favorite = (node.representedObject as? SPFavoriteNode)?.nodeFavorite
        let favoriteID = Self.string(favorite?[SPFavoriteIDKey])
        let name = favorite?[SPFavoriteNameKey] as? String ?? ""
        let host = favorite?[SPFavoriteHostKey] as? String ?? ""
        let colorIndex = favorite?[SPFavoriteColorIndexKey] as? Int

        return SAFavoriteItem(
            id: favoriteID.map { "fav:\($0)" } ?? "node:\(nodeAddress)",
            kind: .favorite,
            name: name,
            host: host,
            colorIndex: colorIndex,
            favoriteID: favoriteID
        )
    }

    /// Normalize a favorite-dictionary value (often an `NSNumber`)
    /// to a string ID.
    private static func string(_ value: Any?) -> String? {
        switch value {
        case let number as NSNumber: return number.stringValue
        case let string as String where !string.isEmpty: return string
        default: return nil
        }
    }
}
