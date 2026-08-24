//
//  SAQueryFavoriteStore.swift
//  Sequel Ace
//
//  Pure favorite-list mutation used by the SwiftUI query-favorite save sheet.
//  Compiled into BOTH the app and Unit Tests targets.
//


import Foundation

enum SAQueryFavoriteScope: Int {
    case document
    case global
}

/// A snapshot of one favorite shown in the replacement picker.
///
/// Query favorites have no persistent identifier. The original position and
/// full dictionary are therefore retained so a save can revalidate the choice
/// against the latest list instead of trusting a stale array index.
struct SAQueryFavoriteSelection: Identifiable {
    let scope: SAQueryFavoriteScope
    let originalIndex: Int
    let favorite: NSDictionary
    let name: String

    var id: String {
        "\(scope.rawValue):\(originalIndex)"
    }
}

enum SAQueryFavoriteSaveError: Error, Equatable {
    case nameRequired
    case selectedFavoriteChanged
}

struct SAQueryFavoriteMutation {
    let scope: SAQueryFavoriteScope
    let favorites: [Any]
}

enum SAQueryFavoriteStore {

    /// Builds picker choices while retaining each item's real source index.
    /// Malformed entries remain in storage but are not offered for replacement.
    static func selections(documentFavorites: [Any], globalFavorites: [Any]) -> [SAQueryFavoriteSelection] {
        selections(in: documentFavorites, scope: .document)
            + selections(in: globalFavorites, scope: .global)
    }

    /// Creates a favorite or replaces the selected favorite's query.
    ///
    /// Replacement keeps the existing dictionary intact — including its name,
    /// tab trigger and any future metadata — and changes only `query`. Before
    /// writing, the captured favorite is resolved against the current list. If
    /// concurrent edits make that resolution missing or ambiguous, the save
    /// fails rather than overwriting a different favorite.
    static func save(query: String,
                     name: String,
                     saveGlobally: Bool,
                     replacing selection: SAQueryFavoriteSelection?,
                     documentFavorites: [Any],
                     globalFavorites: [Any]) throws -> SAQueryFavoriteMutation {
        guard let selection else {
            guard !name.isEmpty else { throw SAQueryFavoriteSaveError.nameRequired }

            let scope: SAQueryFavoriteScope = saveGlobally ? .global : .document
            var favorites = scope == .global ? globalFavorites : documentFavorites
            favorites.append(["name": name, "query": query] as NSDictionary)
            return SAQueryFavoriteMutation(scope: scope, favorites: favorites)
        }

        var favorites = selection.scope == .global ? globalFavorites : documentFavorites
        guard let index = resolvedIndex(for: selection, in: favorites),
              let currentFavorite = favorites[index] as? NSDictionary else {
            throw SAQueryFavoriteSaveError.selectedFavoriteChanged
        }

        let replacement = NSMutableDictionary(dictionary: currentFavorite)
        replacement["query"] = query
        favorites[index] = replacement
        return SAQueryFavoriteMutation(scope: selection.scope, favorites: favorites)
    }

    private static func selections(in favorites: [Any],
                                   scope: SAQueryFavoriteScope) -> [SAQueryFavoriteSelection] {
        favorites.enumerated().compactMap { index, rawFavorite in
            guard let favorite = rawFavorite as? NSDictionary,
                  let name = favorite["name"] as? String else {
                return nil
            }

            return SAQueryFavoriteSelection(
                scope: scope,
                originalIndex: index,
                favorite: NSDictionary(dictionary: favorite),
                name: name
            )
        }
    }

    private static func resolvedIndex(for selection: SAQueryFavoriteSelection,
                                      in favorites: [Any]) -> Int? {
        if favorites.indices.contains(selection.originalIndex),
           let favorite = favorites[selection.originalIndex] as? NSDictionary,
           favorite.isEqual(selection.favorite) {
            return selection.originalIndex
        }

        let matchingIndexes = favorites.indices.filter { index in
            guard let favorite = favorites[index] as? NSDictionary else { return false }
            return favorite.isEqual(selection.favorite)
        }
        return matchingIndexes.count == 1 ? matchingIndexes[0] : nil
    }
}
