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
        for (index, node) in topLevel.enumerated() {
            items.append(build(node, path: "\(index)"))
        }
        return items
    }

    /// Recursively convert one `SPTreeNode`. `path` is the dotted
    /// index-path from the root, used as a stable fallback id for
    /// groups (which have no persistent identifier) and for favorites
    /// missing an ID.
    private static func build(_ node: SPTreeNode, path: String) -> SAFavoriteItem {
        if node.isGroup {
            let group = node.representedObject as? SPGroupNode
            let children = (node.children ?? [])
                .compactMap { $0 as? SPTreeNode }
                .enumerated()
                .map { offset, child in
                    build(child, path: "\(path).\(offset)")
                }
            return SAFavoriteItem(
                id: "grp:\(path)",
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
            id: favoriteID.map { "fav:\($0)" } ?? "fav:\(path)",
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
