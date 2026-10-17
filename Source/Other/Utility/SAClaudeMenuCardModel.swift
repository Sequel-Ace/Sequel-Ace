import AppKit

/// One NSMenuItem as the Claude menu card sees it. `index` is the item's index in its NSMenu;
/// an alternate entry directly follows its primary (as NSMenu orders them).
struct SAClaudeMenuEntry: Equatable {
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

struct SAClaudeMenuRow: Equatable {
    enum Kind { case item, header, separator, noMatches }

    var kind: Kind
    var entry: SAClaudeMenuEntry?

    var isChoosable: Bool { kind == .item && (entry?.isEnabled ?? false) }
}

/// Pure model behind the searchable menu cards: snapshot an NSMenu, resolve alternates, split the footer,
/// filter, move the highlight and size the card. No UI.
enum SAClaudeMenuCardModel {
    static let minCardWidth: CGFloat = 240
    static let maxCardWidth: CGFloat = 420
    static let maxScreenHeightFraction: CGFloat = 0.6

    // MARK: - Snapshot

    /// `skipping` drops those menu indices entirely (pull-down title item, native search-field items).
    static func entries(from menu: NSMenu, skipping: Set<Int> = []) -> [SAClaudeMenuEntry] {
        var result: [SAClaudeMenuEntry] = []
        for (index, item) in menu.items.enumerated() where !skipping.contains(index) {
            var entry = SAClaudeMenuEntry(index: index, kind: item.isSeparatorItem ? .separator : .item, title: item.title)
            entry.isEnabled = item.isEnabled
            entry.isHidden = item.isHidden
            entry.isTicked = item.state == .on
            entry.isAlternate = item.isAlternate
            entry.requiresOption = item.keyEquivalentModifierMask.contains(.option)
            entry.toolTip = item.toolTip
            entry.shortcut = SAClaudeEditorChrome.shortcutString(keyEquivalent: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
            result.append(entry)
        }
        return result
    }

    // MARK: - Rows

    static func rows(_ entries: [SAClaudeMenuEntry], optionHeld: Bool) -> (list: [SAClaudeMenuRow], footer: [SAClaudeMenuRow]) {
        var list: [SAClaudeMenuRow] = []
        var footer: [SAClaudeMenuRow] = []
        var lastVisiblePrimaryHidden = false
        var pendingPrimary: SAClaudeMenuEntry?

        func append(_ entry: SAClaudeMenuEntry) {
            let row = SAClaudeMenuRow(kind: rowKind(entry.kind), entry: entry)
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
                    // Pair: as AppKit, the entry whose modifier mask has ⌥ shows exactly while ⌥ is held (History:
                    // Save History… without ⌥, Copy History with it). When neither or both have ⌥ in their mask, the
                    // primary shows unless ⌥ is held.
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

    private static func rowKind(_ kind: SAClaudeMenuEntry.Kind) -> SAClaudeMenuRow.Kind {
        switch kind {
        case .item: return .item
        case .header: return .header
        case .separator: return .separator
        }
    }

    /// Collapses separators (none leading, trailing, doubled or directly under a header) and drops headers with no item.
    private static func tidy(_ rows: [SAClaudeMenuRow]) -> [SAClaudeMenuRow] {
        // Drop headers that have no item before the next header or the end.
        var kept: [SAClaudeMenuRow] = []
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
        var result: [SAClaudeMenuRow] = []
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

    static func filter(_ list: [SAClaudeMenuRow], query: String) -> [SAClaudeMenuRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return list }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let matching = list.filter { row in
            guard row.kind == .item, let entry = row.entry else { return row.kind == .header || row.kind == .separator }
            return (entry.searchText ?? entry.title).range(of: trimmed, options: options) != nil
        }
        let tidied = tidy(matching)
        if !tidied.contains(where: { $0.kind == .item }) {
            return [SAClaudeMenuRow(kind: .noMatches, entry: nil)]
        }
        return tidied
    }

    // MARK: - Highlight

    static func firstChoosable(in rows: [SAClaudeMenuRow]) -> Int? {
        rows.firstIndex { $0.isChoosable }
    }

    /// Next choosable row in direction `step` (+1 / -1); stops at the ends (no wrap).
    static func move(highlight: Int?, in rows: [SAClaudeMenuRow], by step: Int) -> Int? {
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

    // MARK: - Size

    static func cardSize(contentWidth: CGFloat, contentHeight: CGFloat, screenVisibleHeight: CGFloat) -> NSSize {
        let width = min(max(contentWidth, minCardWidth), maxCardWidth)
        let height = min(contentHeight, floor(screenVisibleHeight * maxScreenHeightFraction))
        return NSSize(width: width, height: height)
    }
}

// MARK: - Database pop-up sections

extension SAClaudeMenuCardModel {
    /// Indices of the two section headers the database card adds (no menu item behind them).
    static let databaseUserHeaderIndex = -100
    static let databaseSystemHeaderIndex = -101

    /// The database pop-up's entries (menu built by `SADatabaseListManager.configurePopup`): the "Choose Database..."
    /// placeholder (item 0) and the separators dropped; the database items (no action of their own: the pop-up cell's
    /// item action) as `userHeader` then the user databases, `systemHeader` then the system databases (split by
    /// `SADatabaseListManager.partition` on the titles, menu order kept), each with the cylinder glyph and the item at
    /// `selectedIndex` ticked; the items with an action of their own (Add Database…, Refresh Databases) as the footer.
    static func databaseEntries(from menu: NSMenu, selectedIndex: Int, userHeader: String, systemHeader: String) -> [SAClaudeMenuEntry] {
        var databases: [SAClaudeMenuEntry] = []
        var footer: [SAClaudeMenuEntry] = []
        for var entry in entries(from: menu, skipping: [0]) where entry.kind == .item {
            let item = menu.items[entry.index]
            entry.isTicked = entry.index == selectedIndex
            if hasOwnAction(item) {
                entry.isFooter = true
                entry.symbol = databaseFooterSymbol(item.action)
                footer.append(entry)
            } else {
                entry.symbol = "cylinder"
                databases.append(entry)
            }
        }
        let system = Set(SADatabaseListManager.partition(databases: databases.map(\.title)).systemDatabases)
        let user = databases.filter { !system.contains($0.title) }
        let systemEntries = databases.filter { system.contains($0.title) }
        return [SAClaudeMenuEntry(index: databaseUserHeaderIndex, kind: .header, title: userHeader)] + user
            + [SAClaudeMenuEntry(index: databaseSystemHeaderIndex, kind: .header, title: systemHeader)] + systemEntries
            + footer
    }

    /// A pop-up's own items carry the cell's private item action; an item added with an action (Add/Refresh) has its own.
    private static func hasOwnAction(_ item: NSMenuItem) -> Bool {
        guard let action = item.action, !(item.target is NSPopUpButtonCell) else { return false }
        return action != NSSelectorFromString("_popUpItemAction:")
    }

    private static func databaseFooterSymbol(_ action: Selector?) -> String? {
        switch action.map(NSStringFromSelector) {
        case "addDatabase:": return "plus"
        case "setDatabases:": return "arrow.clockwise"
        default: return nil
        }
    }
}

// MARK: - Query editor bar menus (History, Favorites, Run, Copy)

extension SAClaudeMenuCardModel {
    /// `SP_FAVORITE_HEADER_MENUITEM_TAG` in SPCustomQuery.h: the tag of the favourites menu's section headers.
    static let favoriteHeaderTag = 200000
    /// `SP_HISTORY_COPY_MENUITEM_TAG` … `SP_HISTORY_CLEAR_MENUITEM_TAG` in SPCustomQuery.h.
    static let historyCopyTag = 300000
    static let historySaveTag = 300001
    static let historyClearTag = 300002
    /// The History and Favorites pull-downs (DBView.xib) have seven fixed head items (title, actions, separators,
    /// the search-field view item); the queries / favourites start here (SPCustomQuery -historyItemsHaveBeenUpdated:,
    /// -queryFavoritesHaveBeenUpdated:, which keep the first 7).
    static let queryMenuFirstListIndex = 7

    /// The Query History pull-down: one detail-only row per query (`detail` = the tooltip, the query up to 256
    /// characters, else the title), searched on it; the head actions as the footer: Save History… (Copy History while
    /// ⌥ is held, as the native menu shows the pair) and Clear History. Item 0 (the title), the head separators and
    /// the search-field view item are dropped.
    static func queryHistoryEntries(from menu: NSMenu) -> [SAClaudeMenuEntry] {
        var result: [SAClaudeMenuEntry] = []
        for var entry in entries(from: menu, skipping: [0]) {
            let item = menu.items[entry.index]
            if entry.index < queryMenuFirstListIndex {
                guard entry.kind == .item, item.view == nil else { continue }
                entry.isFooter = true   // both halves of the Copy / Save pair: the model routes the footer per entry
                entry.symbol = historyFooterSymbol(tag: item.tag)
            } else if entry.kind == .item {
                let query = item.toolTip ?? item.title
                entry.title = query
                entry.detail = query
                entry.searchText = query
            }
            result.append(entry)
        }
        return result
    }

    private static func historyFooterSymbol(tag: Int) -> String? {
        switch tag {
        case historyCopyTag: return "doc.on.doc"
        case historySaveTag: return "square.and.arrow.down"
        case historyClearTag: return "trash"
        default: return nil
        }
    }

    /// The Query Favorites pull-down: head actions 1…3 (Save Query to Favorites…, Save All…, Edit Favorites…) as the
    /// footer; items tagged `favoriteHeaderTag` as section headers; each favourite as a two-line row: its name, the
    /// tab trigger as the trailing chip, the query (tooltip) as the detail, searched on all three.
    static func queryFavoritesEntries(from menu: NSMenu) -> [SAClaudeMenuEntry] {
        let footerSymbols = [1: "star", 2: "star.square.on.square", 3: "pencil"]
        var result: [SAClaudeMenuEntry] = []
        for var entry in entries(from: menu, skipping: [0]) {
            let item = menu.items[entry.index]
            if entry.index < queryMenuFirstListIndex {
                guard entry.kind == .item, item.view == nil else { continue }
                entry.isFooter = true
                entry.symbol = footerSymbols[entry.index]
            } else if entry.kind == .item {
                if item.tag == favoriteHeaderTag {
                    entry.kind = .header
                } else {
                    let parts = favoriteTitleParts(item.title)
                    entry.title = parts.name
                    entry.trailingChip = parts.trigger
                    entry.detail = item.toolTip
                    entry.searchText = [parts.name, parts.trigger, item.toolTip].compactMap { $0 }.joined(separator: " ")
                }
            }
            result.append(entry)
        }
        return result
    }

    /// A favourite's menu title is "name" or "name\ttrigger⇥" (SPCustomQuery -queryFavoritesHaveBeenUpdated:):
    /// the name before the first tab, the trimmed text after it as the trigger (nil when there is none).
    static func favoriteTitleParts(_ title: String) -> (name: String, trigger: String?) {
        guard let tab = title.firstIndex(of: "\t") else { return (title, nil) }
        let trigger = title[title.index(after: tab)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (String(title[..<tab]), trigger.isEmpty ? nil : trigger)
    }

    /// The History/Favorites search field the card replaces: cleared, and the items its filter hid shown again
    /// (what SPCustomQuery's filter does for an empty string), so the card and a later native menu list them all.
    static func resetNativeSearch(in menu: NSMenu) {
        for item in menu.items {
            guard let view = item.view else { continue }
            var stack = [view]
            while let next = stack.popLast() {
                if let field = next as? NSSearchField { field.stringValue = "" }
                stack.append(contentsOf: next.subviews)
            }
        }
        for item in menu.items.dropFirst(queryMenuFirstListIndex) where item.isHidden { item.isHidden = false }
    }

    /// The Run split button's menu: every item in order (item 0, the pull-down's title, dropped), with a glyph by
    /// action and the item's shortcut.
    static func runEntries(from menu: NSMenu) -> [SAClaudeMenuEntry] {
        entries(from: menu, skipping: [0]).map { entry in
            var entry = entry
            if entry.kind == .item { entry.symbol = runSymbol(menu.items[entry.index].action) }
            return entry
        }
    }

    private static func runSymbol(_ action: Selector?) -> String? {
        switch action.map(NSStringFromSelector) {
        case "runPrimaryQueryAction:": return "play"
        case "runSecondaryQueryAction:": return "forward.end"
        case "runAllAsScriptAction:": return "scroll"
        case "runExplainQueryAction:": return "text.magnifyingglass"   // "questionmark.magnifyingglass" is not an SF Symbol
        case "switchDefaultQueryAction:": return "arrow.left.arrow.right"
        default: return nil
        }
    }

    /// The Copy split button's menu: the four copy actions (glyph by tag, ticked as the menu marks them), and the
    /// trailing note item (the row count; not a copy action) as a disabled footer row. Item 0 (the title) dropped.
    /// The note is found by its tag, not by "no action": a pop-up gives its action-less items the cell's item action.
    static func copyEntries(from menu: NSMenu) -> [SAClaudeMenuEntry] {
        let last = menu.items.indices.last
        let noteIndex = last.flatMap { index -> Int? in
            let item = menu.items[index]
            return index > 0 && !item.isSeparatorItem && SAClaudeQueryCopyAction(rawValue: item.tag) == nil ? index : nil
        }
        return entries(from: menu, skipping: [0]).map { entry in
            var entry = entry
            guard entry.kind == .item else { return entry }
            if entry.index == noteIndex {
                entry.isFooter = true
                entry.isEnabled = false
            } else {
                entry.symbol = copySymbol(tag: menu.items[entry.index].tag)
            }
            return entry
        }
    }

    private static func copySymbol(tag: Int) -> String? {
        switch SAClaudeQueryCopyAction(rawValue: tag) {
        case .plain: return "doc.on.doc"
        case .withColumnNames: return "tablecells"
        case .sqlInsert: return "chevron.left.forwardslash.chevron.right"
        case .sqlInsertNoAutoIncrement: return "number.square"
        case nil: return nil
        }
    }
}
