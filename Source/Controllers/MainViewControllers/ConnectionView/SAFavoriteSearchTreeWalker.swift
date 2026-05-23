//
//  SAFavoriteSearchTreeWalker.swift
//  Sequel Ace
//
//  Tree-visibility computation for the favorites sidebar's search
//  filter. Lifted out of SAFavoritesListDataSource so the tree walk
//  is testable independently of the data source.
//
//  The matching rule itself lives in SAFavoriteSearchMatcher — this
//  walker only handles the recursion and the leaf/group bookkeeping.
//
//  Tests for this walker need the SPTreeNode / SPFavoriteNode /
//  SPGroupNode ObjC types visible to the Unit Tests target. That
//  requires either a test-target bridging header (which collides
//  with the auto-generated Swift→ObjC interface header for the
//  test target) or compiling the test in ObjC with the .m files
//  textually included. Both approaches are deferred — the existing
//  SAFavoriteSearchMatcher tests cover the per-leaf matching rule
//  end-to-end, and this walker is a thin recursion around it.
//

import AppKit

enum SAFavoriteSearchTreeWalker {

    /// Return the set of nodes the outline view should keep visible
    /// when the matcher is active.
    ///
    /// Membership:
    ///   - Every leaf whose name OR host matches all tokens
    ///     (see SAFavoriteSearchMatcher for the exact rule).
    ///   - Every group with at least one matching descendant —
    ///     otherwise the matching leaf becomes unreachable in the
    ///     outline view.
    static func visibleNodes(in root: SPTreeNode,
                             matcher: SAFavoriteSearchMatcher) -> Set<SPTreeNode> {
        var matched: Set<SPTreeNode> = []
        _ = visit(root, matcher: matcher, into: &matched)
        return matched
    }

    @discardableResult
    private static func visit(_ node: SPTreeNode,
                              matcher: SAFavoriteSearchMatcher,
                              into matched: inout Set<SPTreeNode>) -> Bool {
        if node.isGroup {
            var anyDescendantMatched = false
            for child in (node.children ?? []).compactMap({ $0 as? SPTreeNode }) {
                if visit(child, matcher: matcher, into: &matched) {
                    anyDescendantMatched = true
                }
            }
            if anyDescendantMatched {
                matched.insert(node)
            }
            return anyDescendantMatched
        }
        let fav = (node.representedObject as? SPFavoriteNode)?.nodeFavorite
        let name = (fav?[SPFavoriteNameKey] as? String) ?? ""
        let host = (fav?[SPFavoriteHostKey] as? String) ?? ""
        if matcher.matches(name: name, host: host) {
            matched.insert(node)
            return true
        }
        return false
    }
}
