import AppKit
import XCTest

final class SADesignMenuCardModelTests: XCTestCase {
    private func e(_ i: Int, _ title: String, kind: SADesignMenuEntry.Kind = .item, searchText: String? = nil,
                   enabled: Bool = true, hidden: Bool = false, footer: Bool = false, alternate: Bool = false) -> SADesignMenuEntry {
        var entry = SADesignMenuEntry(index: i, kind: kind, title: title)
        entry.searchText = searchText
        entry.isEnabled = enabled
        entry.isHidden = hidden
        entry.isFooter = footer
        entry.isAlternate = alternate
        return entry
    }
    private func sep(_ i: Int) -> SADesignMenuEntry { e(i, "", kind: .separator) }
    private func header(_ i: Int, _ title: String) -> SADesignMenuEntry { e(i, title, kind: .header) }

    private func rows(_ entries: [SADesignMenuEntry], option: Bool = false) -> (list: [SADesignMenuRow], footer: [SADesignMenuRow]) {
        SADesignMenuCardModel.rows(entries, optionHeld: option)
    }
    private func row(_ entry: SADesignMenuEntry) -> SADesignMenuRow { SADesignMenuRow(kind: .item, entry: entry) }
    private func shape(_ list: [SADesignMenuRow]) -> [String] {
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

        let entries = SADesignMenuCardModel.entries(from: menu, skipping: [0])
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

        XCTAssertEqual(SADesignMenuCardModel.entries(from: menu).count, 7)
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
    private func pairMenu(primaryMask: NSEvent.ModifierFlags, alternateMask: NSEvent.ModifierFlags) -> [SADesignMenuEntry] {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Copy History", action: #selector(NSText.copy(_:)), keyEquivalent: "").keyEquivalentModifierMask = primaryMask
        let alternate = menu.addItem(withTitle: "Save History…", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        alternate.keyEquivalentModifierMask = alternateMask
        alternate.isAlternate = true
        return SADesignMenuCardModel.entries(from: menu)
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

    private var sample: [SADesignMenuRow] {
        rows([header(0, "Your databases"), e(1, "Test DB"), e(2, "analytics"), header(3, "System"), e(4, "mysql")]).list
    }

    func testFilterKeepsMatchingItemsAndTheirHeaders() {
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(sample, query: "TEST")), ["header Your databases", "item Test DB"])
        XCTAssertEqual(SADesignMenuCardModel.filter(sample, query: ""), sample)
        XCTAssertEqual(SADesignMenuCardModel.filter(sample, query: "   "), sample)
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(sample, query: " mysql ")), ["header System", "item mysql"])
    }

    func testFilterRecollapsesSeparators() {
        let list = rows([e(0, "Apple"), sep(1), e(2, "Banana"), sep(3), e(4, "Avocado")]).list
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(list, query: "av")), ["item Avocado"])
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(list, query: "ap")), ["item Apple"])
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(list, query: "an")), ["item Banana"])
    }

    func testFilterIsDiacriticInsensitiveAndUsesSearchText() {
        let list = rows([e(0, "Recent orders", searchText: "Recent orders ord SELECT * FROM orders"), e(1, "Café")]).list
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(list, query: "from ord")), ["item Recent orders"])
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(list, query: "cafe")), ["item Café"])
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(list, query: "CAFÉ")), ["item Café"])
    }

    func testFilterWithNoMatches() {
        let result = SADesignMenuCardModel.filter(sample, query: "zzz")
        XCTAssertEqual(result, [SADesignMenuRow(kind: .noMatches, entry: nil)])
        XCTAssertNil(SADesignMenuCardModel.firstChoosable(in: result))
    }

    func testFilterMovesHighlightToFirstVisibleItem() {
        let list = rows([header(0, "H"), e(1, "Off alpha", enabled: false), sep(2), e(3, "Beta alpha"), e(4, "Gamma")]).list
        let filtered = SADesignMenuCardModel.filter(list, query: "alpha")
        XCTAssertEqual(shape(filtered), ["header H", "item Off alpha", "separator", "item Beta alpha"])
        let first = SADesignMenuCardModel.firstChoosable(in: filtered)
        XCTAssertEqual(first, 3)
        XCTAssertEqual(filtered[first!].entry?.title, "Beta alpha")
        XCTAssertEqual(SADesignMenuCardModel.firstChoosable(in: list), 3)
    }

    func testIsChoosable() {
        XCTAssertTrue(row(e(0, "A")).isChoosable)
        XCTAssertFalse(row(e(0, "A", enabled: false)).isChoosable)
        XCTAssertFalse(SADesignMenuRow(kind: .header, entry: header(0, "H")).isChoosable)
        XCTAssertFalse(SADesignMenuRow(kind: .separator, entry: sep(0)).isChoosable)
        XCTAssertFalse(SADesignMenuRow(kind: .noMatches, entry: nil).isChoosable)
    }

    func testMoveSkipsNonChoosableAndStopsAtEnds() {
        let list: [SADesignMenuRow] = [
            SADesignMenuRow(kind: .header, entry: header(0, "H")),
            row(e(1, "A")),
            SADesignMenuRow(kind: .separator, entry: sep(2)),
            row(e(3, "B", enabled: false)),
            row(e(4, "C")),
        ]
        XCTAssertEqual(SADesignMenuCardModel.move(highlight: nil, in: list, by: 1), 1)
        XCTAssertEqual(SADesignMenuCardModel.move(highlight: 1, in: list, by: 1), 4)
        XCTAssertEqual(SADesignMenuCardModel.move(highlight: 4, in: list, by: 1), 4)
        XCTAssertEqual(SADesignMenuCardModel.move(highlight: 1, in: list, by: -1), 1)
        XCTAssertEqual(SADesignMenuCardModel.move(highlight: nil, in: list, by: -1), 4)
        XCTAssertEqual(SADesignMenuCardModel.move(highlight: 4, in: list, by: -1), 1)
        XCTAssertNil(SADesignMenuCardModel.move(highlight: nil, in: [], by: 1))
    }

    // MARK: - Firing a snapshot item

    private final class Validating: NSObject, NSMenuItemValidation {
        var allow = true
        @objc func act(_ sender: Any?) {}
        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { allow }
    }

    func testStillFireableOnlyWhileInAMenuAndEnabled() {
        let target = Validating()
        let menu = NSMenu()
        let item = menu.addItem(withTitle: "Pick", action: #selector(Validating.act(_:)), keyEquivalent: "")
        item.target = target
        XCTAssertTrue(SADesignMenuCardModel.isStillFireable(item))

        // Disabled since the card opened: validation runs again, the item is refused.
        target.allow = false
        XCTAssertFalse(SADesignMenuCardModel.isStillFireable(item))
        target.allow = true

        // Moved to another menu (back/forward's cached items): still fireable, at its new index.
        let other = NSMenu()
        other.addItem(withTitle: "Before", action: nil, keyEquivalent: "")
        menu.removeItem(item)
        other.addItem(item)
        XCTAssertTrue(SADesignMenuCardModel.isStillFireable(item))
        XCTAssertEqual(other.index(of: item), 1)

        // Removed (History and the database list are rebuilt with new items): never fired.
        other.removeItem(item)
        XCTAssertNil(item.menu)
        XCTAssertFalse(SADesignMenuCardModel.isStillFireable(item))

        // removeAllItems (SADatabaseListManager.configurePopup) detaches every item too.
        let rebuilt = NSMenu()
        let old = rebuilt.addItem(withTitle: "shop", action: #selector(Validating.act(_:)), keyEquivalent: "")
        old.target = target
        rebuilt.removeAllItems()
        rebuilt.addItem(withTitle: "shop", action: #selector(Validating.act(_:)), keyEquivalent: "").target = target
        XCTAssertFalse(SADesignMenuCardModel.isStillFireable(old))
    }

    func testCardSize() {
        XCTAssertEqual(SADesignMenuCardModel.cardSize(contentWidth: 100, contentHeight: 300, screenVisibleHeight: 1000), NSSize(width: 240, height: 300))
        XCTAssertEqual(SADesignMenuCardModel.cardSize(contentWidth: 600, contentHeight: 900, screenVisibleHeight: 1000), NSSize(width: 420, height: 600))
        XCTAssertEqual(SADesignMenuCardModel.cardSize(contentWidth: 300, contentHeight: 200, screenVisibleHeight: 1000), NSSize(width: 300, height: 200))
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

    private func databaseEntries(_ popup: NSPopUpButton) -> [SADesignMenuEntry] {
        SADesignMenuCardModel.databaseEntries(from: popup.menu!, selectedIndex: popup.indexOfSelectedItem,
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

    func testDatabaseEntriesKeepADatabaseAddedAfterTheListWasBuilt() {
        // SADatabaseListManager.performSelection appends a database the list didn't have, after the separators.
        let popup = databasePopUp(["shop"], current: "shop")
        popup.addItem(withTitle: "late")
        popup.selectItem(withTitle: "late")
        XCTAssertEqual(shape(rows(databaseEntries(popup)).list), ["header Your databases", "item shop", "item late"])
        XCTAssertEqual(databaseEntries(popup).filter(\.isTicked).map(\.title), ["late"])
    }

    func testDatabaseCommandsAreToldApartByTheirTag() {
        // A command is the tagged item, whatever its action; a database with an action of its own stays a database.
        let menu = NSMenu()
        menu.addItem(withTitle: "Choose Database...", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "shop", action: #selector(DatabaseActions.addDatabase(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Add Database...", action: nil, keyEquivalent: "").tag = SADatabaseListManager.commandMenuItemTag
        let resolved = rows(SADesignMenuCardModel.databaseEntries(from: menu, selectedIndex: 1, userHeader: "Your databases", systemHeader: "System"))
        XCTAssertEqual(shape(resolved.list), ["header Your databases", "item shop"])
        XCTAssertEqual(shape(resolved.footer), ["item Add Database..."])
    }

    func testDatabaseFooterIsNeverTicked() {
        // The pop-up can have a footer item selected (e.g. right after Add Database… was picked natively).
        let popup = databasePopUp(["shop", "mysql"], current: "shop")
        for title in ["Add Database...", "Refresh Databases"] {
            popup.selectItem(withTitle: title)
            XCTAssertEqual(popup.titleOfSelectedItem, title)
            let entries = databaseEntries(popup)
            XCTAssertFalse(entries.contains { $0.isFooter && $0.isTicked }, title)
            XCTAssertFalse(entries.contains { $0.isTicked }, title)
        }
        popup.selectItem(withTitle: "mysql")
        XCTAssertEqual(databaseEntries(popup).filter(\.isTicked).map(\.title), ["mysql"])
    }

    func testDatabaseEntriesFilterKeepsFooter() {
        let resolved = rows(databaseEntries(databasePopUp(["mysql", "shop", "shipping"], current: nil)))
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(resolved.list, query: "SH")), ["header Your databases", "item shop", "item shipping"])
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(resolved.list, query: "my")), ["header System", "item mysql"])
    }

    // MARK: - Search, highlight and Escape (the database card's picker behaviors)

    func testFilterIgnoresWidthAsWellAsCaseAndDiacritics() {
        let list = rows([e(0, "shop"), e(1, "Café_orders"), e(2, "ｓｈｉｐｐｉｎｇ")]).list
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(list, query: "ＳＨＯＰ")), ["item shop"])
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(list, query: "cafe")), ["item Café_orders"])
        XCTAssertEqual(shape(SADesignMenuCardModel.filter(list, query: "shipping")), ["item ｓｈｉｐｐｉｎｇ"])
    }

    /// While searching, a row titled exactly as the query (ignoring case, diacritics and width) takes the highlight,
    /// even after other matches; otherwise the first match does.
    func testSearchHighlightPrefersAnExactMatch() {
        let popup = databasePopUp(["admin_db", "db", "db_archive", "mysql"], current: nil)
        let list = rows(databaseEntries(popup)).list
        func highlighted(_ query: String) -> String? {
            let filtered = SADesignMenuCardModel.filter(list, query: query)
            return SADesignMenuCardModel.searchHighlight(in: filtered, listCount: filtered.count, query: query).flatMap { filtered[$0].entry?.title }
        }
        XCTAssertEqual(highlighted("db"), "db")
        XCTAssertEqual(highlighted(" DB "), "db")
        XCTAssertEqual(highlighted("ｄｂ"), "db")
        XCTAssertEqual(highlighted("_d"), "admin_db")
        XCTAssertEqual(highlighted("arch"), "db_archive")
        XCTAssertNil(highlighted("nothing"))
    }

    /// The exact match must be choosable and in the list, not a footer action.
    func testSearchHighlightSkipsDisabledRowsAndTheFooter() {
        let entries = [e(0, "Refresh"), e(1, "refresh", enabled: false), e(2, "Refresh", footer: true)]
        let resolved = rows([e(3, "refresh all")] + entries)
        let all = resolved.list + resolved.footer
        XCTAssertEqual(SADesignMenuCardModel.searchHighlight(in: all, listCount: resolved.list.count, query: "refresh"), 1)
        XCTAssertEqual(all[1].entry?.index, 0)
        let footerOnly = rows([e(2, "Refresh", footer: true)])
        XCTAssertNil(SADesignMenuCardModel.searchHighlight(in: footerOnly.footer, listCount: 0, query: "refresh"))
    }

    /// The card opens on the current database, however far down a long list, and clearing the search returns there.
    func testOpeningHighlightIsTheCurrentDatabaseInALongList() {
        let names = (0..<2000).map { String(format: "db_%04d", $0) }
        let popup = databasePopUp(names + ["mysql"], current: "db_1987")
        let resolved = rows(databaseEntries(popup))
        let all = resolved.list + resolved.footer
        let opening = SADesignMenuCardModel.openingHighlight(in: all, listCount: resolved.list.count)
        XCTAssertEqual(opening.flatMap { all[$0].entry?.title }, "db_1987")
        XCTAssertEqual(SADesignMenuCardModel.searchHighlight(in: all, listCount: resolved.list.count, query: ""), opening)
        // No current database: the first one; the footer never takes the opening highlight.
        let none = rows(databaseEntries(databasePopUp(["shop", "mysql"], current: nil)))
        let noneAll = none.list + none.footer
        XCTAssertEqual(SADesignMenuCardModel.openingHighlight(in: noneAll, listCount: none.list.count).flatMap { noneAll[$0].entry?.title }, "shop")
        let empty = rows(databaseEntries(databasePopUp([], current: nil)))
        XCTAssertNil(SADesignMenuCardModel.openingHighlight(in: empty.list + empty.footer, listCount: empty.list.count))
    }

    /// Escape clears a non-empty search first, then a second Escape closes; a card without search closes at once.
    func testEscapeClearsTheSearchBeforeClosing() {
        XCTAssertEqual(SADesignMenuCardModel.escapeAction(hasSearch: true, query: "sho"), .clearSearch)
        XCTAssertEqual(SADesignMenuCardModel.escapeAction(hasSearch: true, query: " "), .clearSearch)
        XCTAssertEqual(SADesignMenuCardModel.escapeAction(hasSearch: true, query: ""), .close)
        XCTAssertEqual(SADesignMenuCardModel.escapeAction(hasSearch: false, query: ""), .close)
    }
}
