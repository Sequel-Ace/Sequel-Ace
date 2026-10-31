//
//  SAConnectionQueryFavoriteStore.swift
//  Sequel Ace
//
//  Query favourites and content filters per saved connection (walkthrough items 8 and 18, design note
//  2026-10-21-connection-favorites-design).
//
//  A query favourite saved with "Save for all connections" off, or a content filter saved in the manager's local
//  section, goes to the window's own ("local") list. Where that list lives depends on the window:
//    - a window that was never saved as an .spf file and connected through a saved connection favourite keeps it
//      against that connection's id, in the defaults (these stores) — kept across windows, tabs and restarts, and
//      shared by every window on that connection;
//    - any other window (quick connect, a window opened from or saved to an .spf file, a window restored from a
//      session bundle) keeps today's list of the window's file URL in SPQueryController (in the .spf file, or in memory
//      for an untitled quick connect).
//
//  The stores are keyed by the connection favourite's id, never its name, so renaming the connection keeps its
//  lists; deleting the connection leaves them stored (they come back with a connection of that id). Items keep the
//  global lists' shapes: query favourites are dictionaries with name, query, optional tabtrigger; content filters are
//  dictionaries with MenuLabel, Clause, NumberOfArguments, optional ConjunctionLabels, … kept per field type
//  ("number", "string", "date", …) as the global ContentFilters preference is.
//
//  Compiled into BOTH the app and Unit Tests targets (no project ObjC types here).
//

import Foundation

/// Where a window's local (non-global) query favourites and content filters live.
enum SAConnectionLocalScopeKind: Equatable {
    /// Stored against the saved connection favourite with this id.
    case connection(id: String)
    /// The window's file-URL list in SPQueryController (today's behaviour).
    case document

    /// A window connected through a saved connection favourite (`connectionID`, the favourite id the connection
    /// controller recorded) that isn't a saved .spf file stores against the connection; every other window keeps the
    /// file-URL list — including a window restored from a session bundle (.spfs): it counts as untitled but its lists
    /// live in the bundle, and they must never be hidden. An open window that "Save Session" wrote into a bundle is not
    /// restored and keeps its connection's lists (its bundle copy of the lists is empty).
    static func resolve(isUntitled: Bool, isRestoredFromSessionBundle: Bool, connectionID: String?) -> SAConnectionLocalScopeKind {
        guard isUntitled, !isRestoredFromSessionBundle,
              let id = connectionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else { return .document }
        return .connection(id: id)
    }
}

/// Per-connection lists in a defaults domain under one key: a dictionary, connection favourite id → the connection's
/// entry. The entry is the list itself (`group` nil, query favourites) or a dictionary of group → list (content
/// filters, grouped by field type). Each write replaces only the given connection's list (and group); every other
/// entry and group is kept as stored.
struct SAConnectionListStore {

    let defaultsKey: String
    let defaults: UserDefaults

    init(defaultsKey: String, defaults: UserDefaults = .standard) {
        self.defaultsKey = defaultsKey
        self.defaults = defaults
    }

    /// The list stored for `connectionID` (in `group`), in order; empty when there is none (or the stored value isn't a
    /// list). Read fresh each time, so a window sees another window's saves the next time it asks.
    func list(forConnectionID connectionID: String, group: String? = nil) -> [Any] {
        guard let entry = defaults.dictionary(forKey: defaultsKey)?[connectionID] else { return [] }
        guard let group else { return entry as? [Any] ?? [] }
        return (entry as? [String: Any])?[group] as? [Any] ?? []
    }

    /// Replaces the list stored for `connectionID` (in `group`) with `list`. An empty list removes it (and a grouped
    /// entry left with no groups). Other connections' entries and the connection's other groups are untouched; a
    /// grouped entry that isn't a dictionary (unreadable) is replaced.
    func setList(_ list: [Any], forConnectionID connectionID: String, group: String? = nil) {
        var all = defaults.dictionary(forKey: defaultsKey) ?? [:]
        var entry: Any? = list
        if let group {
            var groups = all[connectionID] as? [String: Any] ?? [:]
            if list.isEmpty { groups.removeValue(forKey: group) } else { groups[group] = list }
            entry = groups.isEmpty ? nil : groups
        } else if list.isEmpty {
            entry = nil
        }
        if let entry { all[connectionID] = entry } else { all.removeValue(forKey: connectionID) }
        defaults.set(all, forKey: defaultsKey)
    }
}

/// The per-connection query favourites: connection favourite id → array of favourites (SAConnectionListStore).
struct SAConnectionQueryFavoriteStore {

    /// The defaults key: a dictionary of connection favourite id (string) → array of favourite dictionaries.
    static let defaultsKey = "ClaudeConnectionQueryFavorites"

    private let lists: SAConnectionListStore

    init(defaults: UserDefaults = .standard) {
        lists = SAConnectionListStore(defaultsKey: Self.defaultsKey, defaults: defaults)
    }

    /// The favourites stored for `connectionID`, in order; empty when there are none.
    func favorites(forConnectionID connectionID: String) -> [Any] {
        lists.list(forConnectionID: connectionID)
    }

    /// Replaces the favourites stored for `connectionID` with `favorites` (an empty list removes its entry). Other
    /// connections' entries are untouched.
    func setFavorites(_ favorites: [Any], forConnectionID connectionID: String) {
        lists.setList(favorites, forConnectionID: connectionID)
    }
}

/// The per-connection content filters: connection favourite id → field type → array of filters, the shape of the
/// global ContentFilters preference per connection (SAConnectionListStore).
struct SAConnectionContentFilterStore {

    /// The defaults key: a dictionary of connection favourite id (string) → dictionary of field type → array of filters.
    static let defaultsKey = "ClaudeConnectionContentFilters"

    private let lists: SAConnectionListStore

    init(defaults: UserDefaults = .standard) {
        lists = SAConnectionListStore(defaultsKey: Self.defaultsKey, defaults: defaults)
    }

    /// The `filterType` filters stored for `connectionID`, in order; empty when there are none.
    func filters(forConnectionID connectionID: String, filterType: String) -> [Any] {
        lists.list(forConnectionID: connectionID, group: filterType)
    }

    /// Replaces the `filterType` filters stored for `connectionID` with `filters` (an empty list removes them). Other
    /// field types and connections are untouched.
    func setFilters(_ filters: [Any], forConnectionID connectionID: String, filterType: String) {
        lists.setList(filters, forConnectionID: connectionID, group: filterType)
    }
}

/// A manager's Save for a connection's list (Query Favorites or Content Filters), which other windows may have changed
/// while the manager was open (the list is shared). A three-way merge by identity:
///   - `base`: the list as read when the manager opened;
///   - `opened`: the manager's own copy of each `base` item (same order), which it edits in place;
///   - `mine`: the manager's section at Save (its copies, edited, reordered, deleted, plus new items), in the stored
///     shape;
///   - `mineIdentities`: when the manager saves converted copies of its rows (the content filters manager does), the
///     rows themselves, one per `mine` item and in the same order, to match against `opened`; nil when `mine` is the
///     rows;
///   - `theirs`: the list as stored now.
/// Returns nil when `mine` is unchanged from `base` (nothing to write — another window's newer saves stay as stored).
/// Otherwise the result is `mine` (this manager's adds, edits, deletes and order) with other windows' changes kept:
/// an item another window removed or replaced that this manager left untouched follows that window (replaced in place
/// by the other window's item of the same name — `nameKey` — else dropped), and items other windows added are appended
/// in their order. Where both changed the same item, this manager's edit stays in place and the other window's version
/// is appended (nothing is dropped silently).
enum SAConnectionListMerge {
    static func merge(base: [Any], opened: [AnyObject], mine: [Any], mineIdentities: [AnyObject]? = nil,
                      theirs: [Any], nameKey: String = "name") -> [Any]? {
        func same(_ a: Any, _ b: Any) -> Bool { (a as AnyObject).isEqual(b) }
        let identities: [AnyObject] = mineIdentities.flatMap { $0.count == mine.count ? $0 : nil }
            ?? mine.map { $0 as AnyObject }

        // Which base item each of mine came from: the manager's own copy (identity), else an equal unused base item
        // (a dragged row is re-created as a new dictionary).
        var claimed = Set<Int>()
        var mineBase: [Int?] = identities.map { object in
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
        func name(_ item: Any) -> String? { (item as? NSDictionary)?[nameKey] as? String }

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
