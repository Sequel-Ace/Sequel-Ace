//
//  SAClaudeUserManagerLayout.swift
//  Sequel Ace
//
//  The User Manager's pure geometry (spec 2026-10-18-claude-utility-windows-design.md, section C): the right pane (tabs,
//  tab content, footer), the form cards, the two columns of privilege cards with their checkbox grids and pills, the
//  narrowest pane that keeps every card's columns, the schema lists and arrows, the sidebar's bar buttons. Built on the
//  shared pieces in SAClaudeUtilityWindowLayout.swift; applied by SAClaudeUserManagerStyler.swift. Shared with the Unit
//  Tests target.
//

import AppKit

enum SAClaudeUserManagerLayout {
    /// Left and right of the tabs, every tab's content and the footer.
    static let margin: CGFloat = 18
    static let tabsTop: CGFloat = 16
    static let tabsHeight: CGFloat = 26
    static let tabsContentGap: CGFloat = 16
    static let footerBottom: CGFloat = 12
    /// The push buttons' XIB height (their classic margins included).
    static let footerHeight: CGFloat = 32
    static let footerGap: CGFloat = 10
    /// Between Cancel and Apply as drawn.
    static let buttonGap: CGFloat = 12
    static let pillHeight: CGFloat = 28
    static let pillGap: CGFloat = 8
    /// The schema tab's ◀ / ▶ buttons.
    static let arrowSize: CGFloat = 28
    static let arrowGap: CGFloat = 6
    static let schemaGap: CGFloat = 16
    static let arrowColumnGap: CGFloat = 8

    // MARK: Pane

    struct PaneFrames: Equatable {
        var tabs: NSRect
        /// The tab view: the whole width, between the tabs and the footer (each tab insets its content by `margin`).
        var content: NSRect
        var cancel: NSRect
        var apply: NSRect
    }

    /// `cancelWidth` / `applyWidth` are the push buttons' frame widths and `buttonInset` the classic side margin inside
    /// them, so the drawn buttons line up with the margin and sit `buttonGap` apart.
    static func paneFrames(in bounds: NSRect, tabsWidth: CGFloat, cancelWidth: CGFloat, applyWidth: CGFloat, buttonInset: CGFloat) -> PaneFrames {
        let tabs = NSRect(x: bounds.minX + margin, y: bounds.maxY - tabsTop - tabsHeight,
                          width: min(tabsWidth, max(0, bounds.width - 2 * margin)), height: tabsHeight)
        let footerY = bounds.minY + footerBottom
        let apply = NSRect(x: bounds.maxX - margin + buttonInset - applyWidth, y: footerY, width: applyWidth, height: footerHeight)
        let cancel = NSRect(x: apply.minX + 2 * buttonInset - buttonGap - cancelWidth, y: footerY, width: cancelWidth, height: footerHeight)
        let contentBottom = footerY + footerHeight + footerGap
        let content = NSRect(x: bounds.minX, y: contentBottom, width: bounds.width, height: max(0, tabs.minY - tabsContentGap - contentBottom))
        return PaneFrames(tabs: tabs, content: content, cancel: cancel, apply: apply)
    }

    /// A tab's content area inside the tab view's bounds.
    static func tabContent(in bounds: NSRect) -> NSRect {
        NSRect(x: bounds.minX + margin, y: bounds.minY, width: max(0, bounds.width - 2 * margin), height: bounds.height)
    }

    // MARK: Form cards (General, Resources)

    /// The content frame of a form card at the top of `area`, `rows` rows tall, as wide as the area (the tabs' left edge to
    /// the pane's margin), so its fields stretch with the pane.
    static func formCard(in area: NSRect, rows: Int, chrome: SAClaudeCardLayout.Chrome) -> NSRect {
        let height = SAClaudeFormCardLayout.contentHeight(rows: rows)
        return NSRect(x: area.minX + chrome.left, y: area.maxY - chrome.top - height,
                      width: max(0, area.width - chrome.width), height: height)
    }

    // MARK: Global privileges

    /// One privilege card: its visible checkboxes' widths, in order.
    struct PrivilegeCard: Equatable {
        var itemWidths: [CGFloat]
    }

    struct PrivilegeFrames: Equatable {
        /// Each card's content frame (for `NSBox.setFrameFromContentFrame`), left column first, then the right one.
        var cards: [NSRect]
        /// Each card's checkbox frames, content-local, in item order.
        var checkboxes: [[NSRect]]
        var columns: [Int]
        var checkAll: NSRect
        var uncheckAll: NSRect
        /// Where the lower of the two columns ends (below it the area is free).
        var bottom: CGFloat
    }

    /// Two columns of cards in `area` (`left` stacked in the first, `right` in the second); Check All and Uncheck All as
    /// pills under the right column.
    static func privileges(in area: NSRect, left: [PrivilegeCard], right: [PrivilegeCard], chrome: SAClaudeCardLayout.Chrome,
                           checkAllWidth: CGFloat, uncheckAllWidth: CGFloat) -> PrivilegeFrames {
        let columnWidth = max(0, ((area.width - SAClaudeCardLayout.spacing) / 2).rounded(.down))
        var result = PrivilegeFrames(cards: [], checkboxes: [], columns: [], checkAll: .zero, uncheckAll: .zero, bottom: area.maxY)

        /// Stacks `cards` from the top of the area at `x`; returns where the last one's box ends.
        func stack(_ cards: [PrivilegeCard], x: CGFloat) -> CGFloat {
            var top = area.maxY
            var bottom = area.maxY
            for card in cards {
                let contentWidth = max(0, columnWidth - chrome.width)
                let gridWidth = max(0, contentWidth - 2 * SAClaudeCardLayout.horizontalPadding)
                let columns = SAClaudeCheckboxGrid.columnCount(itemWidths: card.itemWidths, width: gridWidth)
                let gridHeight = max(SAClaudeCheckboxGrid.rowHeight, SAClaudeCheckboxGrid.height(count: card.itemWidths.count, columns: columns))
                let contentHeight = gridHeight + 2 * SAClaudeCardLayout.verticalPadding
                let content = NSRect(x: x + chrome.left, y: top - chrome.top - contentHeight, width: contentWidth, height: contentHeight)
                let grid = SAClaudeCardLayout.inset(NSRect(origin: .zero, size: content.size))
                result.cards.append(content)
                result.columns.append(columns)
                result.checkboxes.append(SAClaudeCheckboxGrid.frames(count: card.itemWidths.count, columns: columns, in: grid))
                bottom = content.minY - chrome.bottom
                top = bottom - SAClaudeCardLayout.spacing
            }
            return bottom
        }

        let leftBottom = stack(left, x: area.minX)
        let rightX = area.minX + columnWidth + SAClaudeCardLayout.spacing
        let rightBottom = stack(right, x: rightX)
        let pillY = rightBottom - SAClaudeCardLayout.spacing - pillHeight
        result.checkAll = NSRect(x: rightX, y: pillY, width: checkAllWidth, height: pillHeight)
        result.uncheckAll = NSRect(x: result.checkAll.maxX + pillGap, y: pillY, width: uncheckAllWidth, height: pillHeight)
        result.bottom = min(leftBottom, pillY)
        return result
    }

    /// The narrowest pane in which every card keeps `columns` columns (each card's widest checkbox whole in its column):
    /// the split view's minimum for the pane, so dragging the divider never squeezes a card down to fewer columns.
    static func minimumPaneWidth(cards: [PrivilegeCard], columns: [Int], chrome: SAClaudeCardLayout.Chrome) -> CGFloat {
        var column: CGFloat = 0
        for (card, count) in zip(cards, columns) {
            guard let widest = card.itemWidths.max() else { continue }
            let grid = CGFloat(count) * widest + CGFloat(max(0, count - 1)) * SAClaudeCheckboxGrid.columnGap
            column = max(column, grid + 2 * SAClaudeCardLayout.horizontalPadding + chrome.width)
        }
        return ceil(2 * column + SAClaudeCardLayout.spacing + 2 * margin)
    }

    // MARK: Schema privileges

    struct SchemaFrames: Equatable {
        var schemas: NSRect
        var granted: NSRect
        var available: NSRect
        /// ◀ (grant: available → granted) above ▶ (revoke), between the granted and available lists.
        var add: NSRect
        var remove: NSRect
    }

    /// Three equal lists across `area`: schemas, then granted and available with the arrows between them.
    static func schema(in area: NSRect) -> SchemaFrames {
        let arrowColumn = arrowSize + 2 * arrowColumnGap
        let listWidth = max(0, ((area.width - schemaGap - arrowColumn) / 3).rounded(.down))
        let schemas = NSRect(x: area.minX, y: area.minY, width: listWidth, height: area.height)
        let granted = NSRect(x: schemas.maxX + schemaGap, y: area.minY, width: listWidth, height: area.height)
        let available = NSRect(x: area.maxX - listWidth, y: area.minY, width: listWidth, height: area.height)
        let arrowX = (granted.maxX + (available.minX - granted.maxX - arrowSize) / 2).rounded(.down)
        let midY = area.midY
        let add = NSRect(x: arrowX, y: (midY + arrowGap / 2).rounded(), width: arrowSize, height: arrowSize)
        let remove = NSRect(x: arrowX, y: (midY - arrowGap / 2).rounded() - arrowSize, width: arrowSize, height: arrowSize)
        return SchemaFrames(schemas: schemas, granted: granted, available: available, add: add, remove: remove)
    }

    // MARK: Sidebar bar

    /// The sidebar's bottom bar buttons (add, remove, gear: each its frame width), left to right from `x`, centred on
    /// `midY` (the shared sidebar bar's).
    static func barButtons(widths: [CGFloat], x: CGFloat, midY: CGFloat) -> [NSRect] {
        SAClaudeSidebarBarLayout.buttons(widths: widths, x: x, midY: midY)
    }
}

