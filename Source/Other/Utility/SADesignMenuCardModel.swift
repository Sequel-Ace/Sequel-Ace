//
//  SADesignMenuCardModel.swift
//  Sequel Ace
//
//  The pure model behind the menu cards (`SADesignMenuCardPresenter`): an NSMenu read into
//  entries, ⌥ alternates resolved, the footer split off, search, the keyboard highlight, the
//  card's size, and the database pop-up's sections. No UI; shared with the Unit Tests target.
//

import AppKit

/// One NSMenuItem as the menu card sees it. `index` is the item's index in its NSMenu;
/// an alternate entry directly follows its primary (as NSMenu orders them).
struct SADesignMenuEntry: Equatable {
    enum Kind { case item, header, separator }

    var index: Int
    var kind: Kind
    var title: String
    var detail: String? = nil
    var searchText: String? = nil
    var symbol: String? = nil
    var shortcut: String = ""
    var isEnabled = true
    var isHidden = false
    var isTicked = false
    var isFooter = false
    var isAlternate = false
    /// The item's key-equivalent modifier mask contains ⌥: of a primary/alternate pair, AppKit shows the one whose
    /// mask matches the held modifiers.
    var requiresOption = false
    var toolTip: String? = nil
    var trailingChip: String? = nil
}

struct SADesignMenuRow: Equatable {
    enum Kind { case item, header, separator, noMatches }

    var kind: Kind
    var entry: SADesignMenuEntry?

    var isChoosable: Bool { kind == .item && (entry?.isEnabled ?? false) }
}

/// Pure model behind the searchable menu cards: snapshot an NSMenu, resolve alternates, split the footer,
/// filter, move the highlight and size the card. No UI.
enum SADesignMenuCardModel {
    static let minCardWidth: CGFloat = 240
    static let maxCardWidth: CGFloat = 420
    static let maxScreenHeightFraction: CGFloat = 0.6

    // MARK: - Snapshot

    /// `skipping` drops those menu indices entirely (pull-down title item, native search-field items).
    static func entries(from menu: NSMenu, skipping: Set<Int> = []) -> [SADesignMenuEntry] {
        var result: [SADesignMenuEntry] = []
        for (index, item) in menu.items.enumerated() where !skipping.contains(index) {
            var entry = SADesignMenuEntry(index: index, kind: item.isSeparatorItem ? .separator : .item, title: item.title)
            entry.isEnabled = item.isEnabled
            entry.isHidden = item.isHidden
            entry.isTicked = item.state == .on
            entry.isAlternate = item.isAlternate
            entry.requiresOption = item.keyEquivalentModifierMask.contains(.option)
            entry.toolTip = item.toolTip
            entry.shortcut = SADesignEditorChrome.shortcutString(keyEquivalent: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
            result.append(entry)
        }
        return result
    }

    // MARK: - Rows

    static func rows(_ entries: [SADesignMenuEntry], optionHeld: Bool) -> (list: [SADesignMenuRow], footer: [SADesignMenuRow]) {
        var list: [SADesignMenuRow] = []
        var footer: [SADesignMenuRow] = []
        var lastVisiblePrimaryHidden = false
        var pendingPrimary: SADesignMenuEntry?

        func append(_ entry: SADesignMenuEntry) {
            let row = SADesignMenuRow(kind: rowKind(entry.kind), entry: entry)
            if entry.isFooter { footer.append(row) } else { list.append(row) }
        }

        // A primary is held back until we know whether an alternate follows it.
        func flushPrimary() {
            if let pending = pendingPrimary { append(pending) }
            pendingPrimary = nil
        }

        for entry in entries {
            if entry.isAlternate && entry.kind == .item {
                if let pending = pendingPrimary {
                    // Pair: as AppKit, the entry whose modifier mask has ⌥ shows exactly while ⌥ is held (say, Save…
                    // without ⌥, Copy with it). When neither or both have ⌥ in their mask, the primary shows unless ⌥
                    // is held.
                    pendingPrimary = nil
                    let showAlternate = pending.requiresOption != entry.requiresOption
                        ? entry.requiresOption == optionHeld
                        : optionHeld
                    if !entry.isHidden && showAlternate {
                        append(entry)
                    } else {
                        append(pending)
                    }
                    continue
                }
                if lastVisiblePrimaryHidden { continue }
                // Orphan alternate (no primary directly before it): shown like a normal item.
                if !entry.isHidden { append(entry) }
                continue
            }
            flushPrimary()
            lastVisiblePrimaryHidden = false
            if entry.isHidden {
                // A hidden primary hides its alternates with it.
                lastVisiblePrimaryHidden = entry.kind == .item
                continue
            }
            if entry.kind == .item {
                pendingPrimary = entry
            } else {
                append(entry)
            }
        }
        flushPrimary()

        return (tidy(list), tidy(footer))
    }

    private static func rowKind(_ kind: SADesignMenuEntry.Kind) -> SADesignMenuRow.Kind {
        switch kind {
        case .item: return .item
        case .header: return .header
        case .separator: return .separator
        }
    }

    /// Collapses separators (none leading, trailing, doubled or directly under a header) and drops headers with no item.
    private static func tidy(_ rows: [SADesignMenuRow]) -> [SADesignMenuRow] {
        // Drop headers that have no item before the next header or the end.
        var kept: [SADesignMenuRow] = []
        for (i, row) in rows.enumerated() {
            if row.kind == .header {
                var hasItem = false
                for next in rows[(i + 1)...] {
                    if next.kind == .header { break }
                    if next.kind == .item { hasItem = true; break }
                }
                if !hasItem { continue }
            }
            kept.append(row)
        }
        var result: [SADesignMenuRow] = []
        for row in kept {
            if row.kind == .separator {
                guard let last = result.last, last.kind != .separator, last.kind != .header else { continue }
            }
            result.append(row)
        }
        while result.last?.kind == .separator { result.removeLast() }
        return result
    }

    // MARK: - Filter

    /// How search text is compared: ignoring case, diacritics and width (full-width "ｓｈｏｐ" finds "shop"), as the
    /// "Go to Database" dialog does.
    static let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// The rows whose search text (else title) contains the trimmed `query`, with their headers and separators tidied;
    /// a single `.noMatches` row when no item matches.
    static func filter(_ list: [SADesignMenuRow], query: String) -> [SADesignMenuRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return list }
        let matching = list.filter { row in
            guard row.kind == .item, let entry = row.entry else { return row.kind == .header || row.kind == .separator }
            return (entry.searchText ?? entry.title).range(of: trimmed, options: searchOptions) != nil
        }
        let tidied = tidy(matching)
        if !tidied.contains(where: { $0.kind == .item }) {
            return [SADesignMenuRow(kind: .noMatches, entry: nil)]
        }
        return tidied
    }

    // MARK: - Highlight

    static func firstChoosable(in rows: [SADesignMenuRow]) -> Int? {
        rows.firstIndex { $0.isChoosable }
    }

    /// Where a card opens its highlight: on the current (ticked) row of the list, else its first choosable row. The
    /// first `listCount` rows are the list; the rest the footer, which never takes the opening highlight.
    static func openingHighlight(in rows: [SADesignMenuRow], listCount: Int) -> Int? {
        let list = Array(rows.prefix(listCount))
        return list.indices.first { list[$0].isChoosable && list[$0].entry?.isTicked == true } ?? firstChoosable(in: list)
    }

    /// The highlight after the search changed to `query`: the row whose title is the trimmed query (ignoring case,
    /// diacritics and width), else the first choosable row of the list. With no query, as the card opened
    /// (`openingHighlight`).
    static func searchHighlight(in rows: [SADesignMenuRow], listCount: Int, query: String) -> Int? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return openingHighlight(in: rows, listCount: listCount) }
        let list = Array(rows.prefix(listCount))
        let exact = list.indices.first {
            list[$0].isChoosable && list[$0].entry?.title.compare(needle, options: searchOptions) == .orderedSame
        }
        return exact ?? firstChoosable(in: list)
    }

    /// What Escape does on a card.
    enum EscapeAction: Equatable {
        /// Clear the search, keep the card open.
        case clearSearch
        /// Close the card.
        case close
    }

    /// Escape clears a non-empty search first; with no search (or an empty one) it closes the card.
    static func escapeAction(hasSearch: Bool, query: String) -> EscapeAction {
        hasSearch && !query.isEmpty ? .clearSearch : .close
    }

    /// Next choosable row in direction `step` (+1 / -1); stops at the ends (no wrap).
    static func move(highlight: Int?, in rows: [SADesignMenuRow], by step: Int) -> Int? {
        let direction = step >= 0 ? 1 : -1
        guard let current = highlight else {
            return direction > 0 ? firstChoosable(in: rows) : rows.lastIndex { $0.isChoosable }
        }
        var i = current + direction
        while i >= 0 && i < rows.count {
            if rows[i].isChoosable { return i }
            i += direction
        }
        return highlight
    }

    // MARK: - Firing

    /// Whether a card row's item (taken from the snapshot made when the card opened) may still fire: still in a menu
    /// (an item its owner removed or replaced has none) and enabled after that menu's validation (`update()`). An item
    /// moved to another menu (back/forward's cached items) may: the presenter fires it at its index there.
    static func isStillFireable(_ item: NSMenuItem) -> Bool {
        item.menu?.update()
        return item.menu != nil && item.isEnabled
    }

    // MARK: - Size

    static func cardSize(contentWidth: CGFloat, contentHeight: CGFloat, screenVisibleHeight: CGFloat) -> NSSize {
        let width = min(max(contentWidth, minCardWidth), maxCardWidth)
        let height = min(contentHeight, floor(screenVisibleHeight * maxScreenHeightFraction))
        return NSSize(width: width, height: height)
    }
}

// MARK: - Database pop-up sections

extension SADesignMenuCardModel {
    /// Indices of the two section headers the database card adds (no menu item behind them).
    static let databaseUserHeaderIndex = -100
    static let databaseSystemHeaderIndex = -101

    /// The database pop-up's entries (menu built by `SADatabaseListManager.configurePopup`): the "Choose Database..."
    /// placeholder (item 0) and the separators dropped; the database items as `userHeader` then the user databases,
    /// `systemHeader` then the system databases (split by `SADatabaseListManager.partition` on the titles, menu order
    /// kept), each with the cylinder glyph and the item at `selectedIndex` ticked; the command items (Add Database…,
    /// Refresh Databases, tagged `SADatabaseListManager.commandMenuItemTag`) as the footer.
    static func databaseEntries(from menu: NSMenu, selectedIndex: Int, userHeader: String, systemHeader: String) -> [SADesignMenuEntry] {
        var databases: [SADesignMenuEntry] = []
        var footer: [SADesignMenuEntry] = []
        for var entry in entries(from: menu, skipping: [0]) where entry.kind == .item {
            let item = menu.items[entry.index]
            if item.tag == SADatabaseListManager.commandMenuItemTag {
                // An action, never the current database: no tick, whatever the pop-up has selected.
                entry.isTicked = false
                entry.isFooter = true
                entry.symbol = databaseFooterSymbol(item.action)
                footer.append(entry)
            } else {
                entry.isTicked = entry.index == selectedIndex
                entry.symbol = "cylinder"
                databases.append(entry)
            }
        }
        let system = Set(SADatabaseListManager.partition(databases: databases.map(\.title)).systemDatabases)
        let user = databases.filter { !system.contains($0.title) }
        let systemEntries = databases.filter { system.contains($0.title) }
        return [SADesignMenuEntry(index: databaseUserHeaderIndex, kind: .header, title: userHeader)] + user
            + [SADesignMenuEntry(index: databaseSystemHeaderIndex, kind: .header, title: systemHeader)] + systemEntries
            + footer
    }

    private static func databaseFooterSymbol(_ action: Selector?) -> String? {
        switch action.map(NSStringFromSelector) {
        case "addDatabase:": return "plus"
        case "setDatabases:": return "arrow.clockwise"
        default: return nil
        }
    }
}
