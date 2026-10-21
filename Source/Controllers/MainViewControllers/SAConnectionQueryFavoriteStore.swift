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
    /// file-URL list.
    static func resolve(isUntitled: Bool, connectionID: String?) -> SAQueryFavoriteLocalScopeKind {
        guard isUntitled,
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
