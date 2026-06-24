//
//  SAFavoriteDeletionPrompt.swift
//  Sequel Ace
//
//  Created as part of the modernization effort (Phase D2).
//
//  Composes the confirmation alert shown before deleting a favorites-tree
//  node, lifted out of -[SPConnectionController removeNode:]. Pure
//  Foundation (no AppKit), so it compiles into the Unit Tests target and
//  the three-way rule is pinned by tests:
//  - favorite          → confirm with the favorite wording
//  - group with items  → confirm with the group wording
//  - empty group       → no confirmation, delete immediately
//

import Foundation

@objc final class SAFavoriteDeletionPrompt: NSObject {

    /// False for an empty group — deleting it loses nothing, so the
    /// controller skips the alert and removes the node directly.
    @objc let needsConfirmation: Bool

    /// Alert message title, e.g. "Delete favorite 'Prod'?". Empty when no
    /// confirmation is needed.
    @objc let title: String

    /// Alert informative text. Empty when no confirmation is needed.
    @objc let informativeText: String

    private init(needsConfirmation: Bool, title: String, informativeText: String) {
        self.needsConfirmation = needsConfirmation
        self.title = title
        self.informativeText = informativeText
    }

    /// Builds the prompt for the selected node. `name` is the favorite's
    /// name or the group's node name; `childCount` only matters for groups.
    @objc(promptForGroup:name:childCount:)
    static func prompt(forGroup isGroup: Bool, name: String?, childCount: Int) -> SAFavoriteDeletionPrompt {
        let displayName = name ?? ""

        if !isGroup {
            return SAFavoriteDeletionPrompt(
                needsConfirmation: true,
                title: String(format: NSLocalizedString("Delete favorite '%@'?", comment: "delete database message"), displayName),
                informativeText: String(format: NSLocalizedString("Are you sure you want to delete the favorite '%@'? This operation cannot be undone.", comment: "delete database informative message"), displayName)
            )
        }

        if childCount > 0 {
            return SAFavoriteDeletionPrompt(
                needsConfirmation: true,
                title: String(format: NSLocalizedString("Delete group '%@'?", comment: "delete database message"), displayName),
                informativeText: String(format: NSLocalizedString("Are you sure you want to delete the group '%@'? All groups and favorites within this group will also be deleted. This operation cannot be undone.", comment: "delete database informative message"), displayName)
            )
        }

        return SAFavoriteDeletionPrompt(needsConfirmation: false, title: "", informativeText: "")
    }
}
