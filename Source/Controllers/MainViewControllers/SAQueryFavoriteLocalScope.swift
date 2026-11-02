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
//  SAConnectionLocalScopeContext (below) resolves a window's scope for this and for the content filters'
//  (SAContentFilterLocalScope), so both agree on which windows store against their connection and on its heading.
//
//  App target only (touches SPDatabaseDocument / SPQueryController / SPFavoritesController).
//

import Foundation

/// Where a document's window keeps its local query favourites and content filters, and the heading of that section —
/// resolved now (call it when a list opens or a save happens).
struct SAConnectionLocalScopeContext {
    let kind: SAConnectionLocalScopeKind
    /// The window's file URL (an "Untitled N" URL for an unsaved window); the key of the file-URL lists.
    let fileURL: URL?
    /// The connection's name for a connection-scoped window — the saved favourite's current name, so a rename shows —
    /// else nil (callers keep their file-name heading).
    let connectionName: String?
    let documentIsUntitled: Bool

    init(document: SPDatabaseDocument?) {
        guard let document else {
            self.init(kind: .document, fileURL: nil, connectionName: nil, documentIsUntitled: true)
            return
        }
        let isUntitled = document.isUntitled()
        let connectionController = document.connectionController()
        let kind = SAConnectionLocalScopeKind.resolve(isUntitled: isUntitled,
                                                      isRestoredFromSessionBundle: SASessionBundleRestoreMark.isMarked(document),
                                                      connectionID: connectionController.connectionKeychainID)
        var name: String?
        if case .connection(let id) = kind {
            name = Self.favoriteName(forID: id) ?? Self.nonEmpty(connectionController.name)
                ?? NSLocalizedString("ClaudeQueryFavoritesThisConnection", value: "This connection",
                                     comment: "Query favorites and content filters: heading of the section saved for the window's connection when its name is unknown")
        }
        self.init(kind: kind, fileURL: document.fileURL(), connectionName: name, documentIsUntitled: isUntitled)
    }

    init(kind: SAConnectionLocalScopeKind, fileURL: URL?, connectionName: String?, documentIsUntitled: Bool) {
        self.kind = kind
        self.fileURL = fileURL
        self.connectionName = connectionName
        self.documentIsUntitled = documentIsUntitled
    }

    /// "Saved for <connection> only" — the save sheet's note under the scope switch and the section tooltips.
    static func savedOnlyText(_ connectionName: String) -> String {
        String(format: NSLocalizedString("ClaudeQueryFavoritesSavedForConnectionOnly", value: "Saved for %@ only",
                                         comment: "Query favorites and content filters: note that a favorite or filter is kept only for this saved connection (arg is the connection's name)"),
               connectionName)
    }

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

/// Marks a window restored from a session bundle (.spfs), whose local lists live in the bundle (SPAppController's
/// restore sets it; "Save Session" doesn't, so it never moves an open window off its connection's lists).
@objc final class SASessionBundleRestoreMark: NSObject {
    private static var markKey: UInt8 = 0

    @objc(markDocument:)
    static func mark(_ document: SPDatabaseDocument) {
        objc_setAssociatedObject(document, &markKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func isMarked(_ document: SPDatabaseDocument) -> Bool {
        (objc_getAssociatedObject(document, &markKey) as? Bool) ?? false
    }
}

@objc final class SAQueryFavoriteLocalScope: NSObject {

    let kind: SAConnectionLocalScopeKind

    /// The window's file URL (an "Untitled N" URL for an unsaved window); the key of the file-URL list.
    @objc let fileURL: URL?

    /// The connection's name for a connection-scoped window — the saved favourite's current name, so a rename shows —
    /// else nil (callers keep their file-name heading).
    @objc let connectionName: String?

    private let documentIsUntitled: Bool
    private let store: SAConnectionQueryFavoriteStore

    init(context: SAConnectionLocalScopeContext, store: SAConnectionQueryFavoriteStore = SAConnectionQueryFavoriteStore()) {
        self.kind = context.kind
        self.fileURL = context.fileURL
        self.connectionName = context.connectionName
        self.documentIsUntitled = context.documentIsUntitled
        self.store = store
        super.init()
    }

    /// The local scope of `document`'s window, resolved now (call it when a list opens or a save happens).
    @objc(scopeForDocument:)
    static func scope(for document: SPDatabaseDocument?) -> SAQueryFavoriteLocalScope {
        SAQueryFavoriteLocalScope(context: SAConnectionLocalScopeContext(document: document))
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

    // MARK: - The manager's editing session

    /// The list as read when the manager opened, and the manager's mutable copy of each item (it edits them in place).
    private var editingBase: [Any] = []
    private var editingCopies: [AnyObject] = []

    /// The local favourites as mutable copies for the Query Favorites manager, remembered so its Save can merge
    /// (`saveEditedFavorites`).
    @objc func editableFavorites() -> [Any] {
        editingBase = favorites()
        editingCopies = editingBase.map { item -> AnyObject in
            if let favorite = item as? NSDictionary { return NSMutableDictionary(dictionary: favorite) }
            return item as AnyObject
        }
        return editingCopies
    }

    /// The manager's Save of its local section. A connection's list is shared by every window on it, so other
    /// windows' saves since the manager opened are kept (SAConnectionListMerge), and nothing is written when the
    /// section is unchanged. A file's list is replaced as before.
    @objc(saveEditedFavorites:)
    func saveEditedFavorites(_ mine: [Any]) {
        guard case .connection(let id) = kind else {
            replaceFavorites(mine)
            return
        }
        guard let merged = SAConnectionListMerge.merge(base: editingBase, opened: editingCopies, mine: mine,
                                                      theirs: store.favorites(forConnectionID: id)) else { return }
        store.setFavorites(merged, forConnectionID: id)
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
        SAConnectionLocalScopeContext.savedOnlyText(connectionName)
    }
}
