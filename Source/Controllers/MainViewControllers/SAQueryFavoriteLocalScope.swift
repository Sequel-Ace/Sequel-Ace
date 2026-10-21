//
//  SAQueryFavoriteLocalScope.swift
//  Sequel Ace
//
//  A window's local (non-global) query favourites, wherever they live (SAConnectionQueryFavoriteStore.swift): the
//  saved connection's list for an untitled window connected through a connection favourite, else the window's
//  file-URL list in SPQueryController, exactly as before. Every place that lists or writes the window's local
//  favourites goes through this — the Query Favorites manager, the Favorites menu (and its card), the Save Query
//  Favorite sheet and the editor's tab triggers — so they agree on the list and on its heading (the connection's name,
//  e.g. "Localhost", instead of "Untitled 1").
//
//  App target only (touches SPDatabaseDocument / SPQueryController / SPFavoritesController).
//

import Foundation

@objc final class SAQueryFavoriteLocalScope: NSObject {

    let kind: SAQueryFavoriteLocalScopeKind

    /// The window's file URL (an "Untitled N" URL for an unsaved window); the key of the file-URL list.
    @objc let fileURL: URL?

    /// The connection's name for a connection-scoped window — the saved favourite's current name, so a rename shows —
    /// else nil (callers keep their file-name heading).
    @objc let connectionName: String?

    private let documentIsUntitled: Bool
    private let store: SAConnectionQueryFavoriteStore

    init(kind: SAQueryFavoriteLocalScopeKind, fileURL: URL?, connectionName: String?, documentIsUntitled: Bool,
         store: SAConnectionQueryFavoriteStore = SAConnectionQueryFavoriteStore()) {
        self.kind = kind
        self.fileURL = fileURL
        self.connectionName = connectionName
        self.documentIsUntitled = documentIsUntitled
        self.store = store
        super.init()
    }

    /// The local scope of `document`'s window, resolved now (call it when a list opens or a save happens).
    @objc(scopeForDocument:)
    static func scope(for document: SPDatabaseDocument?) -> SAQueryFavoriteLocalScope {
        guard let document else {
            return SAQueryFavoriteLocalScope(kind: .document, fileURL: nil, connectionName: nil, documentIsUntitled: true)
        }
        let isUntitled = document.isUntitled()
        let connectionController = document.connectionController()
        let kind = SAQueryFavoriteLocalScopeKind.resolve(isUntitled: isUntitled,
                                                         connectionID: connectionController.connectionKeychainID)
        var name: String?
        if case .connection(let id) = kind {
            name = favoriteName(forID: id) ?? nonEmpty(connectionController.name)
                ?? NSLocalizedString("ClaudeQueryFavoritesThisConnection", value: "This connection",
                                     comment: "Query favorites: heading of the section saved for the window's connection when its name is unknown")
        }
        return SAQueryFavoriteLocalScope(kind: kind, fileURL: document.fileURL(), connectionName: name,
                                         documentIsUntitled: isUntitled)
    }

    /// True when the local favourites are stored against the window's saved connection.
    @objc var isConnectionScoped: Bool {
        if case .connection = kind { return true }
        return false
    }

    /// Whether the manager may hide this section while it is empty (SAManagerDocumentSection): only an untitled
    /// quick-connect window's — a connection's section is a real place, shown even when empty.
    @objc var hidesEmptySection: Bool {
        documentIsUntitled && !isConnectionScoped
    }

    /// The local favourites, in order. A connection's are read fresh from the defaults (another window's saves show).
    @objc func favorites() -> [Any] {
        switch kind {
        case .connection(let id):
            return store.favorites(forConnectionID: id)
        case .document:
            guard let fileURL, let favorites = SPQueryController.shared().favorites(forFileURL: fileURL) else { return [] }
            return favorites.map { $0 }
        }
    }

    /// Replaces the local favourites with `favorites` (the manager's Save, the save sheet).
    @objc(replaceFavorites:)
    func replaceFavorites(_ favorites: [Any]) {
        switch kind {
        case .connection(let id):
            store.setFavorites(favorites, forConnectionID: id)
        case .document:
            guard let fileURL else { return }
            SPQueryController.shared().replaceFavorites(by: favorites, forFileURL: fileURL)
        }
    }

    /// The favourites the editor expands for `trigger`: the local ones with it, then the first global one.
    @objc(favoritesForTabTrigger:)
    func favorites(forTabTrigger trigger: String) -> [Any] {
        switch kind {
        case .connection:
            let global = UserDefaults.standard.array(forKey: SPQueryFavorites) ?? []
            return SAQueryFavoriteTabTrigger.matches(trigger: trigger, local: favorites(), global: global)
        case .document:
            guard let fileURL else { return [] }
            return SPQueryController.shared().queryFavorites(forFileURL: fileURL, andTabTrigger: trigger,
                                                             includeGlobals: true) ?? []
        }
    }

    /// The local section header's tooltip for a connection ("Saved for ‘Localhost’ only"); nil for a file section.
    @objc var connectionHeaderToolTip: String? {
        connectionName.map(Self.savedOnlyText)
    }

    /// "Saved for <connection> only" — the save sheet's note under the scope switch and the section tooltip.
    static func savedOnlyText(_ connectionName: String) -> String {
        String(format: NSLocalizedString("ClaudeQueryFavoritesSavedForConnectionOnly", value: "Saved for %@ only",
                                         comment: "Query favorites: note that a favorite is kept only for this saved connection (arg is the connection's name)"),
               connectionName)
    }

    // MARK: - Connection name

    private static func favoriteName(forID id: String) -> String? {
        guard let root = SPFavoritesController.shared().favoritesTree else { return nil }
        for case let node as SPTreeNode in root.allChildLeafs() {
            guard let favorite = (node.representedObject as? SPFavoriteNode)?.nodeFavorite,
                  SPMCPFavorite.idString(favorite[SPFavoriteIDKey]) == id else { continue }
            return nonEmpty(favorite[SPFavoriteNameKey] as? String)
        }
        return nil
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return string
    }
}
