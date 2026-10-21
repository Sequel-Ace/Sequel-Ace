//
//  SAConnectionQueryFavoriteStore.swift
//  Sequel Ace
//
//  Query favourites per saved connection (walkthrough item 8, design note 2026-10-21-connection-favorites-design).
//
//  A favourite saved with "Save for all connections" off goes to the window's own ("local") list. Where that list
//  lives depends on the window:
//    - a window that was never saved as an .spf file and connected through a saved connection favourite keeps it
//      against that connection's id, in the defaults (this store) — kept across windows, tabs and restarts, and
//      shared by every window on that connection;
//    - any other window (quick connect, a window opened from or saved to an .spf file) keeps today's list of the
//      window's file URL in SPQueryController (in the .spf file, or in memory for an untitled quick connect).
//
//  The store is keyed by the connection favourite's id, never its name, so renaming the connection keeps its
//  favourites; deleting the connection leaves them stored (they come back with a connection of that id).
//  Favourites keep the global list's shape (dictionaries with name, query, optional tabtrigger).
//
//  Compiled into BOTH the app and Unit Tests targets (no project ObjC types here).
//

import Foundation

/// Where a window's local (non-global) query favourites live.
enum SAQueryFavoriteLocalScopeKind: Equatable {
    /// Stored against the saved connection favourite with this id.
    case connection(id: String)
    /// The window's file-URL list in SPQueryController (today's behaviour).
    case document

    /// A window connected through a saved connection favourite (`connectionID`, the favourite id the connection
    /// controller recorded) that isn't a saved .spf file stores against the connection; every other window keeps the
    /// file-URL list — including a window restored from (or saved into) a session bundle (.spfs): it counts as untitled
    /// but its favourites live in the bundle, and they must never be hidden.
    static func resolve(isUntitled: Bool, isSavedInBundle: Bool, connectionID: String?) -> SAQueryFavoriteLocalScopeKind {
        guard isUntitled, !isSavedInBundle,
              let id = connectionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else { return .document }
        return .connection(id: id)
    }
}

/// The per-connection query favourites in a defaults domain: one dictionary, connection favourite id → array of
/// favourites. Each write replaces only the given connection's entry; every other entry is kept as stored.
struct SAConnectionQueryFavoriteStore {

    /// The defaults key: a dictionary of connection favourite id (string) → array of favourite dictionaries.
    static let defaultsKey = "ClaudeConnectionQueryFavorites"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The favourites stored for `connectionID`, in order; empty when there are none (or the stored value isn't a
    /// list). Read fresh each time, so a window sees another window's saves the next time it asks.
    func favorites(forConnectionID connectionID: String) -> [Any] {
        guard let all = defaults.dictionary(forKey: Self.defaultsKey),
              let favorites = all[connectionID] as? [Any] else { return [] }
        return favorites
    }

    /// Replaces the favourites stored for `connectionID` with `favorites` (an empty list removes its entry). Other
    /// connections' entries are untouched.
    func setFavorites(_ favorites: [Any], forConnectionID connectionID: String) {
        var all = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
        if favorites.isEmpty {
            all.removeValue(forKey: connectionID)
        } else {
            all[connectionID] = favorites
        }
        defaults.set(all, forKey: Self.defaultsKey)
    }
}

/// The Query Favorites manager's Save for a connection's list, which other windows may have changed while the manager
/// was open (the list is shared). A three-way merge by identity:
///   - `base`: the list as read when the manager opened;
///   - `opened`: the manager's own copy of each `base` item (same order), which it edits in place;
///   - `mine`: the manager's section at Save (its copies, edited, reordered, deleted, plus new items);
///   - `theirs`: the list as stored now.
/// Returns nil when `mine` is unchanged from `base` (nothing to write — another window's newer saves stay as stored).
/// Otherwise the result is `mine` (this manager's adds, edits, deletes and order) with other windows' changes kept:
/// an item another window removed or replaced that this manager left untouched follows that window (replaced in place
/// by the other window's same-named item, else dropped), and items other windows added are appended in their order.
/// Where both changed the same item, this manager's edit stays in place and the other window's version is appended
/// (nothing is dropped silently).
enum SAQueryFavoriteMerge {
    static func merge(base: [Any], opened: [AnyObject], mine: [Any], theirs: [Any]) -> [Any]? {
        func same(_ a: Any, _ b: Any) -> Bool { (a as AnyObject).isEqual(b) }

        // Which base item each of mine came from: the manager's own copy (identity), else an equal unused base item
        // (a dragged row is re-created as a new dictionary).
        var claimed = Set<Int>()
        var mineBase: [Int?] = mine.map { item in
            let object = item as AnyObject
            if let index = opened.firstIndex(where: { $0 === object }), index < base.count, !claimed.contains(index) {
                claimed.insert(index)
                return index
            }
            return nil
        }
        for (position, item) in mine.enumerated() where mineBase[position] == nil {
            if let index = base.indices.first(where: { !claimed.contains($0) && same(base[$0], item) }) {
                claimed.insert(index)
                mineBase[position] = index
            }
        }

        let unchanged = mine.count == base.count
            && mine.indices.allSatisfy { mineBase[$0] == $0 && same(mine[$0], base[$0]) }
        if unchanged { return nil }

        // Theirs against base: base items still stored, and items other windows added or replaced.
        var stillStored = Set<Int>()
        var theirsOnly: [Any] = []
        for item in theirs {
            if let index = base.indices.first(where: { !stillStored.contains($0) && same(base[$0], item) }) {
                stillStored.insert(index)
            } else {
                theirsOnly.append(item)
            }
        }
        var usedTheirs = Set<Int>()
        func name(_ item: Any) -> String? { (item as? NSDictionary)?["name"] as? String }

        var result: [Any] = []
        for (position, item) in mine.enumerated() {
            guard let index = mineBase[position], !stillStored.contains(index), same(item, base[index]) else {
                result.append(item)   // new, edited by this manager, or still stored: this manager's version
                continue
            }
            // Untouched here, removed or replaced elsewhere: follow the other window.
            if let itemName = name(item),
               let replacement = theirsOnly.indices.first(where: { !usedTheirs.contains($0) && name(theirsOnly[$0]) == itemName }) {
                usedTheirs.insert(replacement)
                result.append(theirsOnly[replacement])
            }
        }
        for (index, item) in theirsOnly.enumerated() where !usedTheirs.contains(index) {
            result.append(item)
        }
        return result
    }
}

/// Tab-trigger lookup over a window's local and the global favourites, as SPQueryController's
/// -queryFavoritesForFileURL:andTabTrigger:includeGlobals: does it: every local favourite with the trigger, in order,
/// then the first global one with it. An empty trigger matches nothing.
enum SAQueryFavoriteTabTrigger {
    static func matches(trigger: String, local: [Any], global: [Any], includeGlobals: Bool = true) -> [NSDictionary] {
        guard !trigger.isEmpty else { return [] }
        func hasTrigger(_ raw: Any) -> NSDictionary? {
            guard let favorite = raw as? NSDictionary,
                  let value = favorite["tabtrigger"] as? String, value == trigger else { return nil }
            return favorite
        }
        var result = local.compactMap(hasTrigger)
        if includeGlobals, let first = global.lazy.compactMap(hasTrigger).first {
            result.append(first)
        }
        return result
    }
}
