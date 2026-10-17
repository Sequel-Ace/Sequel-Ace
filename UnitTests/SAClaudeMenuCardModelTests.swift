import AppKit
import XCTest

final class SAClaudeMenuCardModelTests: XCTestCase {
    private func e(_ i: Int, _ title: String, kind: SAClaudeMenuEntry.Kind = .item, searchText: String? = nil,
                   enabled: Bool = true, hidden: Bool = false, footer: Bool = false, alternate: Bool = false) -> SAClaudeMenuEntry {
        var entry = SAClaudeMenuEntry(index: i, kind: kind, title: title)
        entry.searchText = searchText
        entry.isEnabled = enabled
        entry.isHidden = hidden
        entry.isFooter = footer
        entry.isAlternate = alternate
        return entry
    }
    private func sep(_ i: Int) -> SAClaudeMenuEntry { e(i, "", kind: .separator) }
    private func header(_ i: Int, _ title: String) -> SAClaudeMenuEntry { e(i, title, kind: .header) }

    private func rows(_ entries: [SAClaudeMenuEntry], option: Bool = false) -> (list: [SAClaudeMenuRow], footer: [SAClaudeMenuRow]) {
        SAClaudeMenuCardModel.rows(entries, optionHeld: option)
    }
    private func row(_ entry: SAClaudeMenuEntry) -> SAClaudeMenuRow { SAClaudeMenuRow(kind: .item, entry: entry) }
    private func shape(_ list: [SAClaudeMenuRow]) -> [String] {
        list.map { r in
            switch r.kind {
            case .item: return "item \(r.entry?.title ?? "?")"
            case .header: return "header \(r.entry?.title ?? "?")"
            case .separator: return "separator"
            case .noMatches: return "noMatches"
            }
        }
    }

    func testEntriesFromMenu() {
        let menu = NSMenu(title: "m")
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Title", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let copy = menu.addItem(withTitle: "Copy History", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copy.keyEquivalentModifierMask = .command
        let save = menu.addItem(withTitle: "Save History…", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        save.keyEquivalentModifierMask = [.command, .option]
        save.isAlternate = true
        let hidden = menu.addItem(withTitle: "Hidden", action: nil, keyEquivalent: "")
        hidden.isHidden = true
        let disabled = menu.addItem(withTitle: "Disabled", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        disabled.isEnabled = false
        let on = menu.addItem(withTitle: "Ticked", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        on.state = .on
        on.toolTip = "tip"

        let entries = SAClaudeMenuCardModel.entries(from: menu, skipping: [0])
        XCTAssertFalse(entries.contains { $0.index == 0 })
        XCTAssertEqual(entries.map(\.index), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(entries.map(\.kind), [.separator, .item, .item, .item, .item, .item])
        XCTAssertEqual(entries[1].title, "Copy History")
        XCTAssertEqual(entries[1].shortcut, "⌘C")
        XCTAssertFalse(entries[1].isAlternate)
        XCTAssertTrue(entries[2].isAlternate)
        XCTAssertEqual(entries[2].shortcut, "⌥⌘C")
        XCTAssertFalse(entries[1].requiresOption)
        XCTAssertTrue(entries[2].requiresOption)
        XCTAssertTrue(entries[3].isHidden)
        XCTAssertFalse(entries[4].isEnabled)
        XCTAssertTrue(entries[5].isTicked)
        XCTAssertEqual(entries[5].toolTip, "tip")
        XCTAssertFalse(entries[1].isTicked)
        XCTAssertTrue(entries[1].isEnabled)

        XCTAssertEqual(SAClaudeMenuCardModel.entries(from: menu).count, 7)
    }

    func testRowsDropHiddenAndCollapseSeparators() {
        let r = rows([sep(0), e(1, "A"), sep(2), sep(3), e(4, "B", hidden: true), sep(5), e(6, "C"), sep(7)])
        XCTAssertEqual(shape(r.list), ["item A", "separator", "item C"])
        XCTAssertTrue(r.footer.isEmpty)
    }

    func testSeparatorNotDirectlyUnderHeader() {
        let r = rows([header(0, "X"), sep(1), e(2, "A")])
        XCTAssertEqual(shape(r.list), ["header X", "item A"])
    }

    func testHeaderWithoutItemsIsDropped() {
        let r = rows([header(0, "X"), header(1, "Y"), e(2, "A")])
        XCTAssertEqual(shape(r.list), ["header Y", "item A"])
        XCTAssertEqual(shape(rows([e(0, "A"), header(1, "Z")]).list), ["item A"])
    }

    func testFooterSplit() {
        let r = rows([e(0, "A"), e(1, "Manage", footer: true), sep(2), e(3, "B"), e(4, "Other", footer: true)])
        XCTAssertEqual(shape(r.list), ["item A", "separator", "item B"])
        XCTAssertEqual(shape(r.footer), ["item Manage", "item Other"])
    }

    func testAlternateResolvesWhileOptionHeld() {
        let entries = [e(0, "Copy History"), e(1, "Save History…", alternate: true)]
        let plain = rows(entries, option: false)
        XCTAssertEqual(shape(plain.list), ["item Copy History"])
        XCTAssertEqual(plain.list.first?.entry?.index, 0)
        let held = rows(entries, option: true)
        XCTAssertEqual(shape(held.list), ["item Save History…"])
        XCTAssertEqual(held.list.first?.entry?.index, 1)
    }

    /// A pair read from a menu resolves as AppKit does: by which entry's modifier mask has ⌥.
    private func pairMenu(primaryMask: NSEvent.ModifierFlags, alternateMask: NSEvent.ModifierFlags) -> [SAClaudeMenuEntry] {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Copy History", action: #selector(NSText.copy(_:)), keyEquivalent: "").keyEquivalentModifierMask = primaryMask
        let alternate = menu.addItem(withTitle: "Save History…", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        alternate.keyEquivalentModifierMask = alternateMask
        alternate.isAlternate = true
        return SAClaudeMenuCardModel.entries(from: menu)
    }

    func testAlternatePairAsInDBViewShowsTheUnmodifiedItemWithoutOption() {
        // DBView.xib: Copy History carries ⌥ in its mask, Save History… is the alternate with an empty mask; the native
        // menu shows Save History… with no modifier and Copy History while ⌥ is held.
        let entries = pairMenu(primaryMask: .option, alternateMask: [])
        let plain = rows(entries, option: false)
        XCTAssertEqual(shape(plain.list), ["item Save History…"])
        XCTAssertEqual(plain.list.first?.entry?.index, 1)
        let held = rows(entries, option: true)
        XCTAssertEqual(shape(held.list), ["item Copy History"])
        XCTAssertEqual(held.list.first?.entry?.index, 0)
    }

    func testClassicAlternatePairShowsTheOptionItemWhileOptionHeld() {
        // Primary without ⌥, alternate with ⌥ (e.g. ⌘C / ⌥⌘C): the alternate shows while ⌥ is held.
        let entries = pairMenu(primaryMask: .command, alternateMask: [.command, .option])
        XCTAssertEqual(shape(rows(entries, option: false).list), ["item Copy History"])
        XCTAssertEqual(shape(rows(entries, option: true).list), ["item Save History…"])
        // Neither or both with ⌥: the primary unless ⌥ is held (the fallback).
        for masks in [([], []), ([.option], [.option])] as [(NSEvent.ModifierFlags, NSEvent.ModifierFlags)] {
            let same = pairMenu(primaryMask: masks.0, alternateMask: masks.1)
            XCTAssertEqual(shape(rows(same, option: false).list), ["item Copy History"])
            XCTAssertEqual(shape(rows(same, option: true).list), ["item Save History…"])
        }
    }

    func testOrphanAlternateIsKept() {
        // An alternate with no primary directly before it is shown like a normal item.
        let r = rows([e(0, "Alone", alternate: true)])
        XCTAssertEqual(shape(r.list), ["item Alone"])
    }

    func testHiddenPrimaryDropsItsAlternateToo() {
        let r = rows([e(0, "Primary", hidden: true), e(1, "Alt", alternate: true), e(2, "Other")], option: true)
        XCTAssertEqual(shape(r.list), ["item Other"])
    }

    private var sample: [SAClaudeMenuRow] {
        rows([header(0, "Your databases"), e(1, "Test DB"), e(2, "analytics"), header(3, "System"), e(4, "mysql")]).list
    }

    func testFilterKeepsMatchingItemsAndTheirHeaders() {
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(sample, query: "TEST")), ["header Your databases", "item Test DB"])
        XCTAssertEqual(SAClaudeMenuCardModel.filter(sample, query: ""), sample)
        XCTAssertEqual(SAClaudeMenuCardModel.filter(sample, query: "   "), sample)
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(sample, query: " mysql ")), ["header System", "item mysql"])
    }

    func testFilterRecollapsesSeparators() {
        let list = rows([e(0, "Apple"), sep(1), e(2, "Banana"), sep(3), e(4, "Avocado")]).list
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(list, query: "av")), ["item Avocado"])
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(list, query: "ap")), ["item Apple"])
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(list, query: "an")), ["item Banana"])
    }

    func testFilterIsDiacriticInsensitiveAndUsesSearchText() {
        let list = rows([e(0, "Recent orders", searchText: "Recent orders ord SELECT * FROM orders"), e(1, "Café")]).list
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(list, query: "from ord")), ["item Recent orders"])
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(list, query: "cafe")), ["item Café"])
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(list, query: "CAFÉ")), ["item Café"])
    }

    func testFilterWithNoMatches() {
        let result = SAClaudeMenuCardModel.filter(sample, query: "zzz")
        XCTAssertEqual(result, [SAClaudeMenuRow(kind: .noMatches, entry: nil)])
        XCTAssertNil(SAClaudeMenuCardModel.firstChoosable(in: result))
    }

    func testFilterMovesHighlightToFirstVisibleItem() {
        let list = rows([header(0, "H"), e(1, "Off alpha", enabled: false), sep(2), e(3, "Beta alpha"), e(4, "Gamma")]).list
        let filtered = SAClaudeMenuCardModel.filter(list, query: "alpha")
        XCTAssertEqual(shape(filtered), ["header H", "item Off alpha", "separator", "item Beta alpha"])
        let first = SAClaudeMenuCardModel.firstChoosable(in: filtered)
        XCTAssertEqual(first, 3)
        XCTAssertEqual(filtered[first!].entry?.title, "Beta alpha")
        XCTAssertEqual(SAClaudeMenuCardModel.firstChoosable(in: list), 3)
    }

    func testIsChoosable() {
        XCTAssertTrue(row(e(0, "A")).isChoosable)
        XCTAssertFalse(row(e(0, "A", enabled: false)).isChoosable)
        XCTAssertFalse(SAClaudeMenuRow(kind: .header, entry: header(0, "H")).isChoosable)
        XCTAssertFalse(SAClaudeMenuRow(kind: .separator, entry: sep(0)).isChoosable)
        XCTAssertFalse(SAClaudeMenuRow(kind: .noMatches, entry: nil).isChoosable)
    }

    func testMoveSkipsNonChoosableAndStopsAtEnds() {
        let list: [SAClaudeMenuRow] = [
            SAClaudeMenuRow(kind: .header, entry: header(0, "H")),
            row(e(1, "A")),
            SAClaudeMenuRow(kind: .separator, entry: sep(2)),
            row(e(3, "B", enabled: false)),
            row(e(4, "C")),
        ]
        XCTAssertEqual(SAClaudeMenuCardModel.move(highlight: nil, in: list, by: 1), 1)
        XCTAssertEqual(SAClaudeMenuCardModel.move(highlight: 1, in: list, by: 1), 4)
        XCTAssertEqual(SAClaudeMenuCardModel.move(highlight: 4, in: list, by: 1), 4)
        XCTAssertEqual(SAClaudeMenuCardModel.move(highlight: 1, in: list, by: -1), 1)
        XCTAssertEqual(SAClaudeMenuCardModel.move(highlight: nil, in: list, by: -1), 4)
        XCTAssertEqual(SAClaudeMenuCardModel.move(highlight: 4, in: list, by: -1), 1)
        XCTAssertNil(SAClaudeMenuCardModel.move(highlight: nil, in: [], by: 1))
    }

    func testCardSize() {
        XCTAssertEqual(SAClaudeMenuCardModel.cardSize(contentWidth: 100, contentHeight: 300, screenVisibleHeight: 1000), NSSize(width: 240, height: 300))
        XCTAssertEqual(SAClaudeMenuCardModel.cardSize(contentWidth: 600, contentHeight: 900, screenVisibleHeight: 1000), NSSize(width: 420, height: 600))
        XCTAssertEqual(SAClaudeMenuCardModel.cardSize(contentWidth: 300, contentHeight: 200, screenVisibleHeight: 1000), NSSize(width: 300, height: 200))
    }

    // MARK: Database pop-up sections

    private final class DatabaseActions: NSObject {
        @objc func addDatabase(_ sender: Any?) {}
        @objc func setDatabases(_ sender: Any?) {}
    }

    /// The pop-up as `SPDatabaseDocument -setDatabases` builds it.
    private func databasePopUp(_ names: [String], current: String?) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        _ = SADatabaseListManager.configurePopup(popup, databases: names, currentDatabase: current,
                                                 addDatabaseSelector: #selector(DatabaseActions.addDatabase(_:)),
                                                 refreshDatabasesSelector: #selector(DatabaseActions.setDatabases(_:)))
        return popup
    }

    private func databaseEntries(_ popup: NSPopUpButton) -> [SAClaudeMenuEntry] {
        SAClaudeMenuCardModel.databaseEntries(from: popup.menu!, selectedIndex: popup.indexOfSelectedItem,
                                              userHeader: "Your databases", systemHeader: "System")
    }

    func testDatabaseEntriesSplitUserThenSystemWithFooter() {
        let popup = databasePopUp(["mysql", "shop", "sys", "analytics", "information_schema"], current: "analytics")
        let entries = databaseEntries(popup)
        let resolved = rows(entries)
        XCTAssertEqual(shape(resolved.list), ["header Your databases", "item shop", "item analytics",
                                              "header System", "item mysql", "item sys", "item information_schema"])
        XCTAssertEqual(shape(resolved.footer), ["item Add Database...", "item Refresh Databases"])
        XCTAssertEqual(resolved.footer.map { $0.entry?.symbol }, ["plus", "arrow.clockwise"])
        XCTAssertTrue(resolved.footer.allSatisfy { $0.entry?.isFooter == true })
        let items = resolved.list.filter { $0.kind == .item }
        XCTAssertTrue(items.allSatisfy { $0.entry?.symbol == "cylinder" && $0.entry?.isFooter == false })
        // Every row points at its own menu item.
        for row in items { XCTAssertEqual(popup.menu!.items[row.entry!.index].title, row.entry!.title) }
        XCTAssertEqual(items.filter { $0.entry?.isTicked == true }.map { $0.entry!.title }, ["analytics"])
    }

    func testDatabaseEntriesSkipPlaceholderAndTickNothingWithoutDatabase() {
        let popup = databasePopUp(["shop"], current: nil)
        XCTAssertEqual(popup.indexOfSelectedItem, 0)
        let entries = databaseEntries(popup)
        XCTAssertFalse(entries.contains { $0.index == 0 })
        XCTAssertFalse(entries.contains { $0.kind == .separator })
        XCTAssertFalse(entries.contains { $0.isTicked })
        // No system databases: the System header goes.
        XCTAssertEqual(shape(rows(entries).list), ["header Your databases", "item shop"])
    }

    func testDatabaseEntriesOnlySystemOrNone() {
        XCTAssertEqual(shape(rows(databaseEntries(databasePopUp(["sys", "mysql"], current: "sys"))).list),
                       ["header System", "item sys", "item mysql"])
        let none = rows(databaseEntries(databasePopUp([], current: nil)))
        XCTAssertTrue(none.list.isEmpty)
        XCTAssertEqual(shape(none.footer), ["item Add Database...", "item Refresh Databases"])
    }

    func testDatabaseEntriesKeepADatabaseAddedWithoutGlyph() {
        // SADatabaseListManager.performSelection appends a database the list didn't have, without the glyph.
        let popup = databasePopUp(["shop"], current: "shop")
        popup.addItem(withTitle: "late")
        popup.selectItem(withTitle: "late")
        XCTAssertEqual(shape(rows(databaseEntries(popup)).list), ["header Your databases", "item shop", "item late"])
        XCTAssertEqual(databaseEntries(popup).filter(\.isTicked).map(\.title), ["late"])
    }

    func testDatabaseEntriesFilterKeepsFooter() {
        let resolved = rows(databaseEntries(databasePopUp(["mysql", "shop", "shipping"], current: nil)))
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(resolved.list, query: "SH")), ["header Your databases", "item shop", "item shipping"])
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(resolved.list, query: "my")), ["header System", "item mysql"])
    }

    // MARK: - Query editor bar menus

    /// Every glyph an adapter names must be a real SF Symbol (the card draws nothing for an unknown name).
    private func assertSymbolsExist(_ entries: [SAClaudeMenuEntry], file: StaticString = #filePath, line: UInt = #line) {
        for symbol in entries.compactMap(\.symbol) {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), "\(symbol) is not an SF Symbol", file: file, line: line)
        }
    }

    /// Records the pull-down's action and validates like SPCustomQuery: favourites headers disabled.
    private final class QueryActions: NSObject, NSMenuItemValidation {
        var picks: [Int] = []
        @objc func choose(_ sender: NSPopUpButton) { picks.append(sender.indexOfSelectedItem) }
        @objc func copyQueryHistory(_ sender: Any?) {}
        @objc func saveQueryHistory(_ sender: Any?) {}
        @objc func clearQueryHistory(_ sender: Any?) {}
        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { menuItem.tag != SAClaudeMenuCardModel.favoriteHeaderTag }
    }

    private func searchItem() -> (NSMenuItem, NSSearchField) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        let field = NSSearchField(frame: container.bounds)
        container.addSubview(field)
        let item = NSMenuItem(title: "..placeholder for seachfield..", action: nil, keyEquivalent: "")
        item.view = container
        return (item, field)
    }

    /// The History pull-down as DBView.xib and SPCustomQuery -historyItemsHaveBeenUpdated: build it.
    private func historyPullDown(_ queries: [String], target: QueryActions) -> (NSPopUpButton, NSSearchField) {
        let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 140, height: 25), pullsDown: true)
        button.target = target
        button.action = #selector(QueryActions.choose(_:))
        let menu = button.menu!
        let title = NSMenuItem(title: "History", action: nil, keyEquivalent: ""); title.isHidden = true; menu.addItem(title)
        for (name, tag, selector, alternate) in [("Copy History", SAClaudeMenuCardModel.historyCopyTag, #selector(QueryActions.copyQueryHistory(_:)), false),
                                                 ("Save History…", SAClaudeMenuCardModel.historySaveTag, #selector(QueryActions.saveQueryHistory(_:)), true),
                                                 ("Clear History", SAClaudeMenuCardModel.historyClearTag, #selector(QueryActions.clearQueryHistory(_:)), false)] {
            let item = NSMenuItem(title: name, action: selector, keyEquivalent: "")
            item.tag = tag
            item.target = target
            item.isAlternate = alternate
            item.keyEquivalentModifierMask = alternate ? [] : .option
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let (search, field) = searchItem()
        menu.addItem(search)
        menu.addItem(.separator())
        for query in queries {
            let item = NSMenuItem(title: query.count > 64 ? String(query.prefix(63)) + "…" : query, action: nil, keyEquivalent: "")
            item.toolTip = query.count > 256 ? String(query.prefix(255)) + "…" : query
            menu.addItem(item)
        }
        return (button, field)
    }

    /// The Favorites pull-down as DBView.xib and SPCustomQuery -queryFavoritesHaveBeenUpdated: build it.
    private func favoritesPullDown(file: [(String, String?, String)], global: [(String, String?, String)], target: QueryActions) -> (NSPopUpButton, NSSearchField) {
        let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 140, height: 25), pullsDown: true)
        button.target = target
        button.action = #selector(QueryActions.choose(_:))
        let menu = button.menu!
        let title = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: ""); title.isHidden = true; menu.addItem(title)
        menu.addItem(withTitle: "Save Query to Favorites", action: nil, keyEquivalent: "").tag = 100000
        menu.addItem(withTitle: "Save All to Favorites", action: nil, keyEquivalent: "").tag = 100001
        menu.addItem(withTitle: "Edit Favorites...", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let (search, field) = searchItem()
        menu.addItem(search)
        menu.addItem(.separator())
        for (header, favourites) in [("shop.spf", file), ("Global", global)] {
            let item = NSMenuItem(title: header, action: nil, keyEquivalent: "")
            item.tag = SAClaudeMenuCardModel.favoriteHeaderTag
            menu.addItem(item)
            for (name, trigger, query) in favourites {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                item.toolTip = query
                item.attributedTitle = NSAttributedString(string: trigger.map { "\(name)\t\($0)⇥" } ?? name,
                                                          attributes: [.font: NSFont.systemFont(ofSize: 11)])
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }
        return (button, field)
    }

    func testQueryHistoryEntriesRowsAndFooter() {
        let target = QueryActions()
        let long = "SELECT " + String(repeating: "a, ", count: 40) + "b FROM t"
        let (button, _) = historyPullDown(["SELECT 1", long], target: target)
        button.menu!.update()
        let entries = SAClaudeMenuCardModel.queryHistoryEntries(from: button.menu!)
        assertSymbolsExist(entries)
        // Item 0, the head separators and the search-field view item are not entries.
        XCTAssertFalse(entries.contains { $0.index == 0 || $0.index == 5 || $0.kind == .separator && $0.index < 7 })
        let resolved = rows(entries)
        XCTAssertEqual(shape(resolved.list), ["item SELECT 1", "item \(long)"])
        let second = resolved.list[1].entry!
        XCTAssertEqual(second.index, 8)
        XCTAssertEqual(second.detail, long)          // the tooltip (the query), not the 64-character title
        XCTAssertEqual(second.searchText, long)
        XCTAssertEqual(second.toolTip, long)
        XCTAssertNil(second.symbol)
        XCTAssertEqual(second.title, long)            // detail-only row: title equal to the detail
        // As the native menu: Save History… without ⌥ (Copy History carries ⌥ in its mask, DBView.xib).
        XCTAssertEqual(shape(resolved.footer), ["item Save History…", "item Clear History"])
        XCTAssertEqual(resolved.footer.map { $0.entry?.symbol }, ["square.and.arrow.down", "trash"])
        // ⌥ swaps Save History… for Copy History inside the footer.
        let option = rows(entries, option: true)
        XCTAssertEqual(shape(option.footer), ["item Copy History", "item Clear History"])
        XCTAssertEqual(option.footer.first?.entry?.symbol, "doc.on.doc")
        XCTAssertTrue(option.list.count == 2)
        // Footer actions are never filtered.
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(resolved.list, query: "b from")), ["item \(long)"])
    }

    func testQueryHistoryEntriesEmptyHistoryIsFooterOnly() {
        let (button, _) = historyPullDown([], target: QueryActions())
        let resolved = rows(SAClaudeMenuCardModel.queryHistoryEntries(from: button.menu!))
        XCTAssertTrue(resolved.list.isEmpty)
        XCTAssertEqual(shape(resolved.footer), ["item Save History…", "item Clear History"])
    }

    func testResetNativeSearchClearsFieldAndShowsFilteredItems() {
        let (button, field) = historyPullDown(["SELECT 1", "SELECT 2"], target: QueryActions())
        field.stringValue = "2"
        button.menu!.items[7].isHidden = true   // what SPCustomQuery's filter did for "2"
        SAClaudeMenuCardModel.resetNativeSearch(in: button.menu!)
        XCTAssertEqual(field.stringValue, "")
        XCTAssertFalse(button.menu!.items[7].isHidden)
        XCTAssertTrue(button.menu!.items[0].isHidden)   // the pull-down title stays hidden
        XCTAssertEqual(shape(rows(SAClaudeMenuCardModel.queryHistoryEntries(from: button.menu!)).list), ["item SELECT 1", "item SELECT 2"])
    }

    func testFavoriteTitleParts() {
        XCTAssertEqual(SAClaudeMenuCardModel.favoriteTitleParts("Orders").name, "Orders")
        XCTAssertNil(SAClaudeMenuCardModel.favoriteTitleParts("Orders").trigger)
        let parts = SAClaudeMenuCardModel.favoriteTitleParts("Orders by day\tord⇥")
        XCTAssertEqual(parts.name, "Orders by day")
        XCTAssertEqual(parts.trigger, "ord⇥")
        XCTAssertNil(SAClaudeMenuCardModel.favoriteTitleParts("Name\t ").trigger)
        XCTAssertEqual(SAClaudeMenuCardModel.favoriteTitleParts("a\tb\tc⇥").name, "a")
        XCTAssertEqual(SAClaudeMenuCardModel.favoriteTitleParts("a\tb\tc⇥").trigger, "b\tc⇥")
    }

    func testQueryFavoritesEntriesSectionsRowsAndFooter() {
        let target = QueryActions()
        let (button, _) = favoritesPullDown(file: [("Orders", "ord", "SELECT * FROM orders")],
                                            global: [("Users", nil, "SELECT * FROM users"), ("Count", "cnt", "SELECT COUNT(*) FROM t")],
                                            target: target)
        button.menu!.update()
        let entries = SAClaudeMenuCardModel.queryFavoritesEntries(from: button.menu!)
        assertSymbolsExist(entries)
        let resolved = rows(entries)
        XCTAssertEqual(shape(resolved.list), ["header shop.spf", "item Orders", "header Global", "item Users", "item Count"])
        let orders = resolved.list[1].entry!
        XCTAssertEqual(orders.index, 8)
        XCTAssertEqual(orders.trailingChip, "ord⇥")
        XCTAssertEqual(orders.detail, "SELECT * FROM orders")
        XCTAssertNil(resolved.list[3].entry!.trailingChip)
        XCTAssertEqual(shape(resolved.footer), ["item Save Query to Favorites", "item Save All to Favorites", "item Edit Favorites..."])
        XCTAssertEqual(resolved.footer.map { $0.entry!.index }, [1, 2, 3])
        XCTAssertEqual(resolved.footer.map { $0.entry?.symbol }, ["star", "star.square.on.square", "pencil"])
        XCTAssertFalse(entries.contains { $0.index == 5 })   // the search-field view item
        // Headers aren't choosable, favourites are.
        XCTAssertFalse(resolved.list[0].isChoosable)
        XCTAssertTrue(resolved.list[1].isChoosable)
        // Search covers name, trigger and query; the empty section's header goes.
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(resolved.list, query: "cnt")), ["header Global", "item Count"])
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(resolved.list, query: "from users")), ["header Global", "item Users"])
        XCTAssertEqual(shape(SAClaudeMenuCardModel.filter(resolved.list, query: "orders")), ["header shop.spf", "item Orders"])
    }

    func testQueryFavoritesEntriesEmptyIsFooterOnly() {
        let (button, _) = favoritesPullDown(file: [], global: [], target: QueryActions())
        let resolved = rows(SAClaudeMenuCardModel.queryFavoritesEntries(from: button.menu!))
        XCTAssertTrue(resolved.list.isEmpty)
        XCTAssertEqual(resolved.footer.count, 3)
    }

    func testFavouritePickSelectsTheSameIndexAsTheNativeMenu() {
        let target = QueryActions()
        let (button, _) = favoritesPullDown(file: [("Orders", "ord", "SELECT 1")], global: [("Users", nil, "SELECT 2")], target: target)
        let users = rows(SAClaudeMenuCardModel.queryFavoritesEntries(from: button.menu!)).list.first { $0.entry?.title == "Users" }!.entry!
        // The card fires a pull-down item with performActionForItem(at:) (SAClaudeMenuCardPresenter.fire).
        button.menu!.performActionForItem(at: users.index)
        XCTAssertEqual(target.picks, [users.index])
        XCTAssertEqual(button.indexOfSelectedItem, users.index)
        XCTAssertEqual(button.selectedItem?.toolTip, "SELECT 2")
    }

    private final class RunActions: NSObject {
        @objc func runPrimaryQueryAction(_ sender: Any?) {}
        @objc func runSecondaryQueryAction(_ sender: Any?) {}
        @objc func switchDefaultQueryAction(_ sender: Any?) {}
        @objc func runExplainQueryAction(_ sender: Any?) {}
        @objc func runAllAsScriptAction(_ sender: Any?) {}
    }

    func testRunEntriesKeepOrderWithGlyphsAndShortcuts() {
        let target = RunActions()
        let menu = NSMenu()
        menu.addItem(withTitle: "Run Current", action: nil, keyEquivalent: "").isHidden = true
        func add(_ title: String, _ action: Selector, _ key: String, _ mask: NSEvent.ModifierFlags) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mask
            item.target = target
        }
        add("Run Current Query", #selector(RunActions.runPrimaryQueryAction(_:)), "r", .command)
        menu.addItem(.separator())
        add("Run All Queries", #selector(RunActions.runSecondaryQueryAction(_:)), "r", [.option, .command])
        add("Switch Default", #selector(RunActions.switchDefaultQueryAction(_:)), "", [])
        menu.addItem(.separator())
        add("Explain Current Query", #selector(RunActions.runExplainQueryAction(_:)), "e", [.option, .command])
        add("Run All as Script", #selector(RunActions.runAllAsScriptAction(_:)), "r", [.shift, .option, .command])
        assertSymbolsExist(SAClaudeMenuCardModel.runEntries(from: menu))
        let resolved = rows(SAClaudeMenuCardModel.runEntries(from: menu))
        XCTAssertEqual(shape(resolved.list), ["item Run Current Query", "separator", "item Run All Queries", "item Switch Default",
                                              "separator", "item Explain Current Query", "item Run All as Script"])
        let items = resolved.list.compactMap { $0.kind == .item ? $0.entry : nil }
        XCTAssertEqual(items.map(\.symbol), ["play", "forward.end", "arrow.left.arrow.right", "text.magnifyingglass", "scroll"])
        XCTAssertEqual(items.map(\.shortcut), ["⌘R", "⌥⌘R", "", "⌥⌘E", "⌥⇧⌘R"])
        XCTAssertTrue(resolved.footer.isEmpty)
    }

    func testCopyEntriesGlyphsTickAndFooterNote() {
        // Built as SAClaudeCopyButton builds it: a menu set on a pull-down (whose action-less items get the cell's action).
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
        for action in SAClaudeQueryCopyAction.allCases {
            let item = menu.addItem(withTitle: action.menuTitle, action: #selector(NSText.copy(_:)), keyEquivalent: "")
            item.tag = action.tag
            item.state = action == .sqlInsert ? .on : .off
            item.isEnabled = action != .sqlInsertNoAutoIncrement
        }
        menu.addItem(.separator())
        let note = NSMenuItem()
        note.isEnabled = false
        menu.addItem(note)
        note.title = "Copies 3 rows · nothing selected"
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.menu = menu
        XCTAssertNotNil(note.action)   // the pop-up cell's item action: why the note is found by tag
        assertSymbolsExist(SAClaudeMenuCardModel.copyEntries(from: menu))
        let resolved = rows(SAClaudeMenuCardModel.copyEntries(from: menu))
        XCTAssertEqual(resolved.list.map { $0.entry?.title }, SAClaudeQueryCopyAction.allCases.map { Optional($0.menuTitle) })
        XCTAssertEqual(resolved.list.map { $0.entry?.symbol }, ["doc.on.doc", "tablecells", "chevron.left.forwardslash.chevron.right", "number.square"])
        XCTAssertEqual(resolved.list.filter { $0.entry?.isTicked == true }.map { menu.items[$0.entry!.index].tag }, [SAClaudeQueryCopyAction.sqlInsert.tag])
        XCTAssertFalse(resolved.list[3].isChoosable)
        XCTAssertEqual(shape(resolved.footer), ["item Copies 3 rows · nothing selected"])
        XCTAssertFalse(resolved.footer[0].isChoosable)
    }
}
