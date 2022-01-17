//
// Created by Luis Aguiniga on January 9, 2022.
// Copyright (c) 2022 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

import AppKit

/// Helper class to maintain the sort state changes of a Table View.
/// - Important: Sorting with `NSSortDescriptors` uses `Key-Value Coding` so the data
///   field names must match the `descriptor.key` as well as the `column.identifier`.
@objc final class TableSortHelper: NSObject {
    let descriptors: [NSSortDescriptor]
    let aliases: [String: String]
    let tableView: NSTableView
    private(set) var currentColumn: NSTableColumn?
    private(set) var currentOrder: SortOrder = .default

    enum SortOrder { case ascending, descending, `default` }

    @objc init(tableView: NSTableView, descriptors: [NSSortDescriptor], aliases: [String: String]) {
        self.descriptors = descriptors
        self.tableView = tableView
        self.aliases = aliases
        super.init()
    }
    
    /// Updates sort indicators on column  and prepares sort descriptor.
    /// - Parameters:
    ///   - tableView: The target table view for the column.
    ///   - newColumn: The column to inspect and try to sort by.
    /// - Returns: The sort descriptor to sort by; if table /column are not managed by this helper returns nil
    @objc func sortDescriptorForClick(on tableView: NSTableView, column newColumn: NSTableColumn) -> NSSortDescriptor? {
        guard canSort(newColumn) else { return nil }

        if let currColumn = currentColumn {
            if currColumn === newColumn {
                updateColumnState(newColumn, currentOrder.next)
                return currentSortDescriptor()
            }
            clearCurrentIndicator(currColumn)
        }

        updateColumnState(newColumn, .ascending)

        return currentSortDescriptor()
    }

    /// - Important: if handling a `click` event, call  `sortDescriptorsForClick:tableView:newColumn:` instead!
    @objc func currentSortDescriptor() -> NSSortDescriptor? {
        guard let column = currentColumn else {
            return descriptors.first
        }

            let alias = self.aliases[column.identifier.rawValue]
        guard let desc = descriptors.first(where: { $0.key == column.identifier.rawValue || (alias != nil && $0.key == alias) }) else {
            return nil
        }

        // if descriptor order matches return as is
        if currentOrder == .ascending && desc.ascending || currentOrder == .descending && !desc.ascending {
            return desc
        }

        // sort descriptor order doesn't match so we need to reverse it.
        return desc.reversedSortDescriptor as? NSSortDescriptor
    }

    private func updateColumnState(_ column: NSTableColumn, _ order: SortOrder) {
        tableView.setIndicatorImage(order.indicatorImage, in: column)
        currentOrder = order
        currentColumn = order != .default ? column : nil
    }

    private func clearCurrentIndicator(_ column: NSTableColumn) {
        tableView.setIndicatorImage(nil, in: column)
    }

    private func canSort(_ column: NSTableColumn) -> Bool {
        let alias = self.aliases[column.identifier.rawValue]
        return column === currentColumn || descriptors.contains(where: { $0.key == column.identifier.rawValue || (alias != nil && $0.key == alias) })
    }
}

 extension TableSortHelper.SortOrder {
    var next: TableSortHelper.SortOrder {
        switch self {
            case .ascending : return .descending
            case .descending: return .default
            case .default   : return .ascending
        }
    }

    var indicatorImage: NSImage? {
        switch self {
            case .ascending : return NSImage(named: "NSAscendingSortIndicator")
            case .descending: return NSImage(named: "NSDescendingSortIndicator")
            case .default   : return nil
        }
    }
}
