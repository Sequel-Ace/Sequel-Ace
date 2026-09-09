//
//  SAQueryHistoryMerger.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.09.09.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Merges new query-history entries into an existing list - the replacement
/// for the old trick of abusing a hidden `NSPopUpButton` as a de-duplicator,
/// which allocated a control (plus its debug description for logging) on
/// every saved query. Replicates the popup semantics exactly: existing
/// entries keep their order with a later duplicate winning, new entries are
/// inserted at the front one by one - several new entries therefore end up
/// in reverse order, as the old `insertItemWithTitle:atIndex:0` loop
/// produced - and an older duplicate of a new entry is removed. The result
/// is trimmed to `limit` from the end (a negative limit never trims; a limit
/// of 0 empties the list, both as before).
@objc public final class SAQueryHistoryMerger: NSObject {
    /// - Parameters:
    ///   - newEntries: The entries to add, most recent intent first.
    ///   - existing: The stored history, oldest first. Sourced from plists a
    ///     user can hand-edit (preferences, .spf session files), so elements
    ///     are accepted as `Any` and anything that is not a string is dropped
    ///     rather than trapping in the ObjC-to-Swift array bridge.
    ///   - limit: Maximum number of entries to keep.
    /// - Returns: The merged, de-duplicated, trimmed history.
    @objc(mergedHistoryWithNewEntries:existing:limit:)
    public static func merged(newEntries: [Any], existing: [Any], limit: Int) -> [String] {
        // NSPopUpButton de-duplicates by title but keeps repeated EMPTY
        // titles, so empty strings are exempt from the removal - parity for
        // hand-edited history lists.
        var list: [String] = []
        for entry in existing.compactMap({ $0 as? String }) {
            if !entry.isEmpty {
                list.removeAll { $0 == entry }
            }
            list.append(entry)
        }
        for entry in newEntries.compactMap({ $0 as? String }) {
            if !entry.isEmpty {
                list.removeAll { $0 == entry }
            }
            list.insert(entry, at: 0)
        }
        if limit >= 0, list.count > limit {
            list.removeLast(list.count - limit)
        }
        return list
    }
}
