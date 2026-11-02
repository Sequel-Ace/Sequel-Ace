//
//  SAContentFilterLocalScope.swift
//  Sequel Ace
//
//  A window's local (non-global) content filters, wherever they live (walkthrough item 18 — the query favourites'
//  treatment, SAQueryFavoriteLocalScope): the saved connection's filters for an untitled window connected through a
//  connection favourite (SAConnectionContentFilterStore, per field type like the global ContentFilters preference),
//  else the window's file-URL filters in SPQueryController, exactly as before. The Content Filter manager and the
//  filter bar's operator menus (SPRuleFilterController) go through this, so they agree on the list and on its heading
//  (the connection's name, e.g. "Localhost", instead of "Untitled 1").
//
//  App target only (touches SPDatabaseDocument / SPQueryController). SPRuleFilterController.m, which the Unit Tests
//  target also compiles, looks this class up at runtime.
//

import Foundation

@objc(SAContentFilterLocalScope) final class SAContentFilterLocalScope: NSObject {

    let kind: SAConnectionLocalScopeKind

    /// The window's file URL (an "Untitled N" URL for an unsaved window); the key of the file-URL filters.
    @objc let fileURL: URL?

    /// The connection's name for a connection-scoped window, else nil (callers keep their file-name heading).
    @objc let connectionName: String?

    private let documentIsUntitled: Bool
    private let store: SAConnectionContentFilterStore

    init(context: SAConnectionLocalScopeContext, store: SAConnectionContentFilterStore = SAConnectionContentFilterStore()) {
        self.kind = context.kind
        self.fileURL = context.fileURL
        self.connectionName = context.connectionName
        self.documentIsUntitled = context.documentIsUntitled
        self.store = store
        super.init()
    }

    /// The local scope of `document`'s window, resolved now (call it when a list opens or a save happens).
    @objc(filterScopeForDocument:)
    static func scope(for document: SPDatabaseDocument?) -> SAContentFilterLocalScope {
        SAContentFilterLocalScope(context: SAConnectionLocalScopeContext(document: document))
    }

    /// True when the local filters are stored against the window's saved connection.
    @objc var isConnectionScoped: Bool {
        if case .connection = kind { return true }
        return false
    }

    /// Whether the manager may hide this section while it is empty (SAManagerDocumentSection): only an untitled
    /// quick-connect window's — a connection's section is a real place, shown even when empty.
    @objc var hidesEmptySection: Bool {
        documentIsUntitled && !isConnectionScoped
    }

    /// The local section header's tooltip for a connection ("Saved for ‘Localhost’ only"); nil for a file section.
    @objc var connectionHeaderToolTip: String? {
        connectionName.map(SAConnectionLocalScopeContext.savedOnlyText)
    }

    /// The local `filterType` filters, in order, as stored. A connection's are read fresh from the defaults (another
    /// window's saves show).
    @objc(filtersOfType:)
    func filters(ofType filterType: String) -> [Any] {
        switch kind {
        case .connection(let id):
            return store.filters(forConnectionID: id, filterType: filterType)
        case .document:
            guard let fileURL else { return [] }
            return SPQueryController.shared().contentFilter(forFileURL: fileURL)[filterType] as? [Any] ?? []
        }
    }

    // MARK: - The manager's editing session

    /// The list as read when the manager opened, its type, and the manager's mutable copy of each item (it edits them
    /// in place).
    private var editingType: String?
    private var editingBase: [Any] = []
    private var editingCopies: [AnyObject] = []

    /// The local `filterType` filters as mutable copies for the Content Filter manager, remembered so its Save can merge
    /// (`saveEditedFilters`). A file's are copied as before; a connection's are prepared like the global ones (the
    /// conjunction field edits "ConjunctionLabel", stored as the first of "ConjunctionLabels").
    @objc(editableFiltersOfType:)
    func editableFilters(ofType filterType: String) -> [Any] {
        editingType = filterType
        editingBase = filters(ofType: filterType)
        editingCopies = editingBase.map { item -> AnyObject in
            guard let filter = item as? NSDictionary else { return item as AnyObject }
            let copy = NSMutableDictionary(dictionary: filter)
            if isConnectionScoped, let labels = filter["ConjunctionLabels"] as? [Any], let first = labels.first {
                copy["ConjunctionLabel"] = first
            }
            return copy
        }
        return editingCopies
    }

    /// The manager's Save of its local `filterType` section: `filters` in the stored shape (its
    /// -contentFilterForFileURL:), made from `rows` (the section's rows, one per filter, in order). A connection's
    /// filters are shared by every window on it, so other windows' saves since the manager opened are kept
    /// (SAConnectionListMerge), and nothing is written when the section is unchanged. A file's filters are replaced as
    /// before.
    @objc(saveEditedFilters:rows:ofType:)
    func saveEditedFilters(_ filters: [Any], rows: [Any], ofType filterType: String) {
        switch kind {
        case .connection(let id):
            // The base is the list the manager opened with (`editableFilters`), always of this type.
            guard editingType == filterType else { return }
            guard let merged = SAConnectionListMerge.merge(base: editingBase, opened: editingCopies, mine: filters,
                                                           mineIdentities: rows.map { $0 as AnyObject },
                                                           theirs: store.filters(forConnectionID: id, filterType: filterType),
                                                           nameKey: "MenuLabel") else { return }
            store.setFilters(merged, forConnectionID: id, filterType: filterType)
        case .document:
            guard let fileURL else { return }
            SPQueryController.shared().replaceContentFilter(by: filters, ofType: filterType, forFileURL: fileURL)
        }
    }
}
