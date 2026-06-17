//
//  SAFavoritesList.swift
//  Sequel Ace
//
//  Phase C1b of the SwiftUI migration: a pure SwiftUI `List` /
//  `OutlineGroup` rendering of the favorites sidebar, replacing the
//  AppKit outline view used by the `NSViewRepresentable` wrap
//  (`SAFavoritesListView`, C1a).
//
//  This is the SwiftUI-native path. It currently covers display,
//  search filtering, selection, and double-click-to-connect. Drag &
//  drop reordering, inline rename, and expand/collapse persistence
//  still live in the AppKit data source and are follow-up work before
//  this can fully replace the wrap (tracked in the modernization
//  plan). Nothing hosts this view yet — Phase C3 is the intended host.
//

import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI favorites sidebar built over the value-type
/// `SAFavoriteItem` model.
struct SAFavoritesList: View {

    /// The full (unfiltered) model forest, e.g. from
    /// `SAFavoriteItem.tree(from:)`.
    let items: [SAFavoriteItem]

    /// Live search query. An empty/whitespace query shows everything.
    var searchQuery: String = ""

    /// Currently selected row id.
    @Binding var selection: SAFavoriteItem.ID?

    /// Invoked when a favorite (leaf) row is double-clicked — the host
    /// should initiate a connection. Groups and Quick Connect are
    /// ignored here (matching `-[SPConnectionController nodeDoubleClicked:]`).
    var onConnect: (SAFavoriteItem) -> Void = { _ in }

    private var visibleItems: [SAFavoriteItem] {
        items.filtered(query: searchQuery)
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(visibleItems) { item in
                OutlineGroup(item, children: \.children) { node in
                    SAFavoriteRow(item: node)
                        .tag(node.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if node.kind == .favorite {
                                onConnect(node)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// A single favorites row: icon + (color-tinted) name.
struct SAFavoriteRow: View {

    let item: SAFavoriteItem

    var body: some View {
        Label {
            Text(item.name)
                .foregroundColor(labelColor)
        } icon: {
            icon
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .quickConnect:
            Image("quick-connect-icon")
                .renderingMode(.template)
        case .group:
            Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                .resizable()
                .frame(width: 16, height: 16)
        case .favorite:
            Image("database-small")
        }
    }

    /// Favorites with a color tag get a tinted label, mirroring
    /// `-[SAFavoritesListDataSource outlineView:willDisplayCell:…]`.
    private var labelColor: Color? {
        guard item.kind == .favorite,
              let index = item.colorIndex,
              let nsColor = SPFavoriteColorSupport.sharedInstance().color(for: index) else {
            return nil
        }
        return Color(nsColor: nsColor)
    }
}
