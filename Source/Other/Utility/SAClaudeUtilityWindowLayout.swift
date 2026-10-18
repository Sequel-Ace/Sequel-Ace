//
//  SAClaudeUtilityWindowLayout.swift
//  Sequel Ace
//
//  The pure geometry of the utility windows' Claude look (spec 2026-10-18-claude-utility-windows-design.md, C and D):
//  a grid of checkboxes inside a titled card, label + field rows inside a card, and the User Manager's pane, privilege
//  cards and schema columns. Rects are in non-flipped coordinates (the first row at the top). Nothing here touches a
//  view; the stylers (SAClaudeUtilityWindowStyler.swift, SAClaudeUserManagerStyler.swift) apply the frames. Shared
//  with the Unit Tests target.
//

import AppKit

// MARK: - Checkbox grid

/// Checkboxes in columns inside a card, filled column by column (the first column top to bottom, then the next), so
/// reading down each column keeps the controls' own order.
enum SAClaudeCheckboxGrid {
    static let rowHeight: CGFloat = 18
    static let rowPitch: CGFloat = 20
    static let columnGap: CGFloat = 10
    static let maxColumns = 2

    /// The width of each of `columns` columns across `width`.
    static func columnWidth(columns: Int, width: CGFloat) -> CGFloat {
        let count = CGFloat(max(1, columns))
        return max(0, ((width - columnGap * (count - 1)) / count).rounded(.down))
    }

    /// The most columns (up to `maxColumns`, never more than there are items) in which every item fits whole; 1 when
    /// even two would cut a title.
    static func columnCount(itemWidths: [CGFloat], width: CGFloat, maxColumns: Int = maxColumns) -> Int {
        guard let widest = itemWidths.max() else { return 1 }
        var columns = min(maxColumns, itemWidths.count)
        while columns > 1 {
            if widest <= columnWidth(columns: columns, width: width) { return columns }
            columns -= 1
        }
        return 1
    }

    static func rows(count: Int, columns: Int) -> Int {
        guard count > 0 else { return 0 }
        let columns = max(1, columns)
        return (count + columns - 1) / columns
    }

    /// The height the grid takes: its rows at `rowPitch`, the last one `rowHeight` tall.
    static func height(count: Int, columns: Int) -> CGFloat {
        let rows = rows(count: count, columns: columns)
        return rows == 0 ? 0 : CGFloat(rows - 1) * rowPitch + rowHeight
    }

    /// One frame per item, in item order, in `rect` from its top: column-major, each as wide as its column.
    static func frames(count: Int, columns: Int, in rect: NSRect) -> [NSRect] {
        let rows = rows(count: count, columns: columns)
        guard rows > 0 else { return [] }
        let columns = max(1, columns)
        let width = columnWidth(columns: columns, width: rect.width)
        return (0..<count).map { index in
            let column = index / rows
            let row = index % rows
            return NSRect(x: rect.minX + CGFloat(column) * (width + columnGap),
                          y: rect.maxY - CGFloat(row) * rowPitch - rowHeight,
                          width: width, height: rowHeight)
        }
    }
}

// MARK: - Cards

/// A titled card (an NSBox drawn by `SAClaudeSheetTitledBox`) and the padding inside it.
enum SAClaudeCardLayout {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 12
    /// Between cards stacked in a column, and between card columns.
    static let spacing: CGFloat = 12

    /// What the box adds around its content frame: the title above, the hairline around (measured from the box).
    struct Chrome: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        var left: CGFloat
        var right: CGFloat

        static let zero = Chrome(top: 0, bottom: 0, left: 0, right: 0)
        var height: CGFloat { top + bottom }
        var width: CGFloat { left + right }
    }

    /// The content frame of a card whose whole box (title included) fills `outer`.
    static func contentFrame(outer: NSRect, chrome: Chrome) -> NSRect {
        NSRect(x: outer.minX + chrome.left, y: outer.minY + chrome.bottom,
               width: max(0, outer.width - chrome.width), height: max(0, outer.height - chrome.height))
    }

    /// The grid area inside a card's content.
    static func inset(_ content: NSRect) -> NSRect {
        content.insetBy(dx: horizontalPadding, dy: verticalPadding)
    }
}

/// Label + field rows inside a card: right-aligned labels in one column, fields filling the rest.
enum SAClaudeFormCardLayout {
    static let fieldHeight: CGFloat = 24
    static let rowGap: CGFloat = 10
    static let labelGap: CGFloat = 10

    struct Row: Equatable {
        var label: NSRect
        var field: NSRect
    }

    static func contentHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return 2 * SAClaudeCardLayout.verticalPadding }
        return 2 * SAClaudeCardLayout.verticalPadding + CGFloat(rows) * fieldHeight + CGFloat(rows - 1) * rowGap
    }

    /// Rows in a card content `width` wide (content-local, from the top); each label `labelHeight` tall, centred on its field.
    static func rows(count: Int, labelWidth: CGFloat, labelHeight: CGFloat, width: CGFloat) -> [Row] {
        let height = contentHeight(rows: count)
        let x = SAClaudeCardLayout.horizontalPadding
        let fieldX = x + labelWidth + labelGap
        let fieldWidth = max(0, width - SAClaudeCardLayout.horizontalPadding - fieldX)
        return (0..<count).map { index in
            let fieldY = height - SAClaudeCardLayout.verticalPadding - fieldHeight - CGFloat(index) * (fieldHeight + rowGap)
            let field = NSRect(x: fieldX, y: fieldY, width: fieldWidth, height: fieldHeight)
            let label = NSRect(x: x, y: (field.midY - labelHeight / 2).rounded(), width: labelWidth, height: labelHeight)
            return Row(label: label, field: field)
        }
    }
}

// MARK: - User Manager

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
    /// The widest a Login Information / Resource Limits card gets.
    static let formCardMaxWidth: CGFloat = 460
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

    /// The content frame of a form card at the top left of `area`, `rows` rows tall.
    static func formCard(in area: NSRect, rows: Int, chrome: SAClaudeCardLayout.Chrome) -> NSRect {
        let outerWidth = min(formCardMaxWidth, area.width)
        let height = SAClaudeFormCardLayout.contentHeight(rows: rows)
        return NSRect(x: area.minX + chrome.left, y: area.maxY - chrome.top - height,
                      width: max(0, outerWidth - chrome.width), height: height)
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

    /// The sidebar's bottom bar buttons (add, remove, gear), left to right from `x`, centred on `midY`.
    static let barButtonSize: CGFloat = 28
    static let barButtonGap: CGFloat = 2

    static func barButtons(count: Int, x: CGFloat, midY: CGFloat) -> [NSRect] {
        (0..<count).map { index in
            NSRect(x: x + CGFloat(index) * (barButtonSize + barButtonGap), y: (midY - barButtonSize / 2).rounded(),
                   width: barButtonSize, height: barButtonSize)
        }
    }
}
