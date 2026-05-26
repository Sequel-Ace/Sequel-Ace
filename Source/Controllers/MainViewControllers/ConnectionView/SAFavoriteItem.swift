//
//  SAFavoriteItem.swift
//  Sequel Ace
//
//  Phase C1b of the SwiftUI migration: a value-type model of the
//  favorites tree, suitable for a SwiftUI `List` / `OutlineGroup`.
//
//  This file is intentionally free of any project-specific ObjC type
//  (no `SPTreeNode`, no AppKit) so it compiles into the Unit Tests
//  target without a bridging header — the same constraint that keeps
//  `SAFavoriteSearchMatcher` testable. The bridge that builds this
//  model from the live `SPTreeNode` tree lives in
//  `SAFavoriteItem+Tree.swift` (app target only).
//

import Foundation

/// One node in the SwiftUI favorites list.
///
/// Reference identity (`SPTreeNode`) is replaced by a stable `id`
/// string so SwiftUI selection / diffing behaves. Favorites carry
/// their real `favoriteID` separately so a selection can be mapped
/// back to the underlying favorite.
struct SAFavoriteItem: Identifiable, Hashable {

    enum Kind: Hashable {
        /// The virtual "Quick Connect" row pinned to the top.
        case quickConnect
        /// A folder grouping other items.
        case group
        /// A leaf connection favorite.
        case favorite
    }

    /// Stable, unique identity for SwiftUI. Prefixed by kind so a
    /// group and a favorite can never collide.
    let id: String

    let kind: Kind
    let name: String

    /// Host string (favorites only; empty otherwise). Used by search.
    let host: String

    /// Favorite color tag index, if any (favorites only).
    let colorIndex: Int?

    /// The underlying favorite's ID (favorites only). Lets a selection
    /// be resolved back to the real favorite dictionary.
    let favoriteID: String?

    /// `nil` for leaves; an array (possibly empty) for groups.
    var children: [SAFavoriteItem]?

    init(id: String,
         kind: Kind,
         name: String,
         host: String = "",
         colorIndex: Int? = nil,
         favoriteID: String? = nil,
         children: [SAFavoriteItem]? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.host = host
        self.colorIndex = colorIndex
        self.favoriteID = favoriteID
        self.children = children
    }
}

// MARK: - Filtering

extension SAFavoriteItem {

    /// Returns a copy of this item pruned to the search results, or
    /// `nil` if it should be hidden entirely.
    ///
    /// Mirrors the AppKit filter semantics
    /// (`SAFavoriteSearchTreeWalker` + `SAFavoriteSearchMatcher`):
    ///   - Quick Connect is always kept.
    ///   - A favorite is kept iff its name/host matches every token.
    ///   - A group is kept iff at least one descendant favorite is
    ///     kept (the group's own name is *not* matched, matching the
    ///     original behavior), and its children are pruned to the
    ///     surviving set.
    func filtered(using matcher: SAFavoriteSearchMatcher) -> SAFavoriteItem? {
        guard matcher.isActive else { return self }

        switch kind {
        case .quickConnect:
            return self

        case .favorite:
            return matcher.matches(name: name, host: host) ? self : nil

        case .group:
            let keptChildren = (children ?? []).compactMap { $0.filtered(using: matcher) }
            guard !keptChildren.isEmpty else { return nil }
            var copy = self
            copy.children = keptChildren
            return copy
        }
    }
}

// MARK: - Convenience

extension Array where Element == SAFavoriteItem {

    /// Apply a search query, returning the visible top-level items.
    /// An inactive (empty/whitespace) query returns `self` unchanged.
    func filtered(query: String) -> [SAFavoriteItem] {
        let matcher = SAFavoriteSearchMatcher(query: query)
        guard matcher.isActive else { return self }
        return compactMap { $0.filtered(using: matcher) }
    }

    /// Depth-first flattening of the whole forest (groups included),
    /// handy for tests and for resolving a selection id to its item.
    func flattened() -> [SAFavoriteItem] {
        var out: [SAFavoriteItem] = []
        for item in self {
            out.append(item)
            if let kids = item.children {
                out.append(contentsOf: kids.flattened())
            }
        }
        return out
    }

    /// Find an item anywhere in the forest by its `id`.
    func first(byID id: SAFavoriteItem.ID) -> SAFavoriteItem? {
        flattened().first { $0.id == id }
    }
}
