//
//  SAFavoriteSearchMatcher.swift
//  Sequel Ace
//
//  Pure search-token matching for the favorites sidebar filter.
//  Extracted from SAFavoritesListDataSource so the matching rule can be
//  pinned by unit tests without standing up an NSOutlineView, SPTreeNode
//  tree, and SPFavoritesController.
//
//  No AppKit / ObjC dependencies — the file is compiled into both the
//  app and the Unit Tests target (same pattern as SAViewMode and
//  SADatabaseListManager).
//

import Foundation

/// Holds the tokenized form of a favorites-search query and decides
/// whether a single favorite (identified by its name and host) matches.
///
/// Rule: the user's query is split into whitespace-separated tokens,
/// lowercased once at construction time. A candidate matches when
/// **every** token is found (substring, case-insensitive) in either
/// the name **or** the host. This lets the user narrow down with
/// e.g. `"staging maja"` to match `"[Staging] Majapahit"`.
struct SAFavoriteSearchMatcher {

    /// Whitespace-separated, lowercased tokens parsed from the query.
    /// Empty when the query was nil / blank — in that case `isActive`
    /// returns false and the caller should bypass filtering entirely.
    let tokens: [String]

    init(query: String) {
        tokens = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// `true` when the query yielded at least one non-whitespace token.
    /// Callers should treat `false` as "no filter" — show everything.
    var isActive: Bool { !tokens.isEmpty }

    /// Whether the given (name, host) pair matches every token.
    ///
    /// Both arguments are lowercased here, so callers don't need to
    /// pre-normalize. Returns `true` when `isActive` is `false`, since
    /// "no filter" means "everything matches".
    func matches(name: String, host: String) -> Bool {
        guard isActive else { return true }
        let lowerName = name.lowercased()
        let lowerHost = host.lowercased()
        return tokens.allSatisfy { token in
            lowerName.contains(token) || lowerHost.contains(token)
        }
    }
}
