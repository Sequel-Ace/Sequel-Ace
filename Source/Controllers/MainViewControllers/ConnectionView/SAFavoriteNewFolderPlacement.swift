//
//  SAFavoriteNewFolderPlacement.swift
//  Sequel Ace
//
//  Where -[SPConnectionController addGroup:] puts a new folder. Pure Foundation, so it compiles into the Unit Tests
//  target and the rule is pinned by tests:
//  - the classic sidebar (the favourites show as an outline tree): beside the selection — inside the selected folder,
//    else in the selected favourite's folder (upstream behaviour; the tree shows where it went);
//  - the Claude connection page (the favourites show as cards; the sidebar's own + Folder button is hidden): always at
//    the top level — the cards show no tree, so a folder nested under whatever was selected would be a surprise.
//    Favourites still move into folders by drag and drop.
//  - nothing selected, or Quick Connect: the top level.
//

import Foundation

/// The node the new folder becomes a child of.
@objc enum SAFavoriteNewFolderParent: Int {
    /// The Favorites root's top level.
    case topLevel
    /// The selected folder.
    case selectedNode
    /// The selected node's parent (a favourite's folder, or the top level for a top-level favourite).
    case selectedNodeParent
}

@objc final class SAFavoriteNewFolderPlacement: NSObject {

    @objc(parentForSelectionIsFolder:selectionIsQuickConnect:hasSelection:favouritesShowAsCards:)
    static func parent(selectionIsFolder: Bool, selectionIsQuickConnect: Bool, hasSelection: Bool,
                       favouritesShowAsCards: Bool) -> SAFavoriteNewFolderParent {
        guard hasSelection, !selectionIsQuickConnect, !favouritesShowAsCards else { return .topLevel }
        return selectionIsFolder ? .selectedNode : .selectedNodeParent
    }
}
