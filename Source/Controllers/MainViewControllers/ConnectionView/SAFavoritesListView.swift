//
//  SAFavoritesListView.swift
//  Sequel Ace
//
//  Phase C1 of the SwiftUI migration: the first SwiftUI-hostable view
//  in the app. This is the *wrap* step — it embeds the existing
//  AppKit favorites sidebar (an `SPFavoritesOutlineView` driven by
//  `SAFavoritesListDataSource`) inside an `NSViewRepresentable` so the
//  list can be dropped into a SwiftUI hierarchy unchanged. A later
//  step iterates toward a pure SwiftUI `List` / `OutlineGroup`.
//
//  Nothing wires this into the running app yet (that's Phase C3, the
//  standalone connection window). Until then it exists as a reusable
//  building block.
//

import SwiftUI
import AppKit

/// SwiftUI wrapper around the AppKit favorites outline view.
///
/// The heavy lifting still lives in `SAFavoritesListDataSource` (the
/// outline view's data source + delegate). This type only owns the
/// AppKit plumbing: building the scroll view + outline view, applying
/// the same column / font / row-height configuration that
/// `-[SPConnectionController setUpFavoritesOutlineView]` applies, and
/// keeping the data source's `searchQuery` / `delegate` in sync with
/// SwiftUI state across `updateNSView`.
struct SAFavoritesListView: NSViewRepresentable {

    /// Root of the favorites tree (from `SPFavoritesController`).
    let favoritesRoot: SPTreeNode

    /// Backing favorites controller used for save operations.
    let favoritesController: SPFavoritesController

    /// Active search query. Changing it re-filters the list.
    var searchQuery: String

    /// Provides the (weakly-held) callback delegate. Captured as a
    /// closure rather than a stored `weak var` because
    /// `NSViewRepresentable` is a value type — SwiftUI keeps the most
    /// recent struct value alive for the view's lifetime, so a strong
    /// stored delegate could outlive its owner and form a retain cycle
    /// once this view is hosted inside that owner (Phase C3).
    private let delegateProvider: () -> SAFavoritesListDelegate?

    init(favoritesRoot: SPTreeNode,
         favoritesController: SPFavoritesController,
         searchQuery: String = "",
         delegate: SAFavoritesListDelegate?) {
        self.favoritesRoot = favoritesRoot
        self.favoritesController = favoritesController
        self.searchQuery = searchQuery
        weak var weakDelegate = delegate
        self.delegateProvider = { weakDelegate }
    }

    func makeCoordinator() -> Coordinator {
        let dataSource = SAFavoritesListDataSource(favoritesRoot: favoritesRoot,
                                                   favoritesController: favoritesController)
        dataSource.delegate = delegateProvider()
        return Coordinator(dataSource: dataSource)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = SPFavoritesOutlineView()
        outlineView.selectionHighlightStyle = .sourceList
        outlineView.headerView = nil
        outlineView.focusRingType = .none
        outlineView.allowsEmptySelection = true
        outlineView.allowsMultipleSelection = true
        outlineView.indentationPerLevel = 14

        // Single column, cell-based — matches the XIB outline view.
        // `SAFavoritesListDataSource` returns `SPFavoriteTextFieldCell`
        // instances from its `dataCellFor:` delegate method, so the
        // column's data cell must be one too.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "favorites"))
        column.isEditable = true
        column.resizingMask = .autoresizingMask
        let cell = SPFavoriteTextFieldCell()
        column.dataCell = cell
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        // Font + row height mirror -[SPConnectionController setUpFavoritesOutlineView].
        let font = UserDefaults.getFont()
        outlineView.font = font
        cell.font = font
        let probeHeight = ("{ǞṶḹÜ∑zgyf" as NSString)
            .size(withAttributes: [.font: font]).height
        outlineView.rowHeight = 4.0 + probeHeight

        // Data source / delegate / drag types are installed by -attach(to:).
        context.coordinator.dataSource.attach(to: outlineView)

        // Double click → connect (mirrors -[SPConnectionController nodeDoubleClicked:]).
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.nodeDoubleClicked(_:))

        context.coordinator.outlineView = outlineView

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        // Initial population + restore saved expand/collapse state.
        context.coordinator.dataSource.searchQuery = searchQuery
        context.coordinator.dataSource.reloadData(in: outlineView)
        context.coordinator.dataSource.restoreOutlineViewState(favoritesRoot, in: outlineView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = context.coordinator.outlineView else { return }
        let dataSource = context.coordinator.dataSource

        // Keep the (weak) delegate fresh in case SwiftUI handed us a
        // new closure capturing a different owner.
        dataSource.delegate = delegateProvider()

        // Re-filter only when the query actually changed — setting
        // `searchQuery` rebuilds the visible-node set on every assign.
        if dataSource.searchQuery != searchQuery {
            dataSource.searchQuery = searchQuery
            dataSource.reloadData(in: outlineView)
        }
    }

    // MARK: - Coordinator

    /// Holds the AppKit objects across SwiftUI view-value churn and
    /// forwards the cell-based double-click action to the delegate.
    final class Coordinator: NSObject {
        let dataSource: SAFavoritesListDataSource
        weak var outlineView: SPFavoritesOutlineView?

        init(dataSource: SAFavoritesListDataSource) {
            self.dataSource = dataSource
        }

        @objc func nodeDoubleClicked(_ sender: Any?) {
            guard let outlineView = outlineView,
                  let node = outlineView.itemForDoubleAction as? SPTreeNode else { return }

            // Ignore the Quick Connect row.
            if node === dataSource.quickConnectItem { return }

            if node.isGroup {
                // Begin editing the group name (matches the controller).
                let row = outlineView.selectedRow
                if row >= 0 {
                    outlineView.editColumn(0, row: row, with: nil, select: true)
                }
            } else {
                // Route through the data source's delegate rather than a
                // separately-captured closure: `updateNSView` refreshes
                // `dataSource.delegate` when SwiftUI recreates the view
                // with a new owner, so selection and double-click always
                // target the same (current) delegate.
                dataSource.delegate?.favoritesListNodeDoubleClicked(node)
            }
        }
    }
}
