//
//  SAPinnedTableGroupPlanner.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// Pure rules for the groups of pinned tables: group names, their display order
/// and the header rows the table list shows for them. Kept free of AppKit and of
/// the store so the Unit Tests target can compile it.
enum SAPinnedTableGroupPlanner {

    /// Separates the localized "PINNED" header from the group name in a group's header row.
    static let headerSeparator = " — "

    /// Trims a group name. The empty name is reserved for the global pinned section.
    static func normalizedGroupName(_ groupName: String) -> String {
        groupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The distinct, non-empty group names in display order.
    static func orderedGroupNames(_ groupNames: [String]) -> [String] {
        let distinct = Set(groupNames.map(normalizedGroupName)).filter(\.isNotEmpty)
        return distinct.sorted(by: isOrderedBefore)
    }

    /// The table names in display order, without duplicates.
    static func orderedTableNames(_ tableNames: [String]) -> [String] {
        Set(tableNames).sorted(by: isOrderedBefore)
    }

    /// The title of the header row of a group; the global section keeps the plain header.
    static func headerTitle(pinnedHeader: String, groupName: String) -> String {
        groupName.isEmpty ? pinnedHeader : pinnedHeader + headerSeparator + groupName
    }

    /// The group a header row stands for, or `nil` when the title is not a group's header.
    /// The caller has to know the row is a header row (no table type) already: a table
    /// can be called exactly like a header, and must stay selectable.
    static func groupName(fromHeaderTitle title: String, pinnedHeader: String) -> String? {
        let prefix = pinnedHeader + headerSeparator
        guard title.hasPrefix(prefix) else {
            return nil
        }
        let groupName = String(title.dropFirst(prefix.count))
        return groupName.isEmpty ? nil : groupName
    }

    /// The pinned section a drop at a row lands in: the row of its header and its group (empty
    /// for the global section), or `nil` outside the pinned sections. Dropping on a header, on
    /// a table of the section or just below one all target that section.
    ///
    /// - Parameters:
    ///   - row: The proposed row.
    ///   - isDropOn: Whether the drop is on the row rather than above it.
    ///   - titles: The rows of the list.
    ///   - isHeader: Whether each row is a header row; only those can be pinned headers, so a
    ///     table called like a header is never taken for one.
    ///   - pinnedHeader: The localized "PINNED" header.
    static func dropTarget(row: Int, isDropOn: Bool, titles: [String], isHeader: [Bool], pinnedHeader: String) -> (headerRow: Int, groupName: String)? {
        guard titles.isNotEmpty, titles.count == isHeader.count else {
            return nil
        }
        var index = max(min(isDropOn ? row : row - 1, titles.count - 1), 0)
        while index >= 0 {
            if isHeader[index] {
                if titles[index] == pinnedHeader {
                    return (index, "")
                }
                if let groupName = groupName(fromHeaderTitle: titles[index], pinnedHeader: pinnedHeader) {
                    return (index, groupName)
                }
                return nil
            }
            index -= 1
        }
        return nil
    }

    /// Case-insensitive and locale-aware first; names that compare equal that way
    /// (`Alpha`, `alpha`) are ordered by the case-sensitive comparison and finally by
    /// their code points, so the order never depends on the order they arrive in.
    private static func isOrderedBefore(_ lhs: String, _ rhs: String) -> Bool {
        let insensitive = lhs.localizedCaseInsensitiveCompare(rhs)
        if insensitive != .orderedSame {
            return insensitive == .orderedAscending
        }
        let sensitive = lhs.localizedCompare(rhs)
        if sensitive != .orderedSame {
            return sensitive == .orderedAscending
        }
        return lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars) { $0.value < $1.value }
    }
}
