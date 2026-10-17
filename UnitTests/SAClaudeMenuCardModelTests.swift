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
}
