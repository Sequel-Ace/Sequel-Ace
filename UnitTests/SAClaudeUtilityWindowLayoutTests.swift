//
//  SAClaudeUtilityWindowLayoutTests.swift
//  Unit Tests
//
//  The utility windows' pure geometry: the checkbox grid inside a card and a XIB's checkbox reading order, form card rows
//  (SAClaudeUtilityWindowLayout.swift), and the User Manager's pane, privilege cards (at the XIB size, with every
//  privilege a server can show) and schema columns (SAClaudeUserManagerLayout.swift).
//

import XCTest

final class SAClaudeUtilityWindowLayoutTests: XCTestCase {

    private typealias Grid = SAClaudeCheckboxGrid
    private typealias Layout = SAClaudeUserManagerLayout

    /// A Claude checkbox's width for `title`, as the cell measures it.
    private func width(_ title: String) -> CGFloat {
        SAClaudeToggleTitleMetrics.cellSize(title: title, drawsTitle: true, nativeHeight: 18).width
    }

    // The XIB's privilege cards, in their order, every checkbox visible (a server that supports all of them).
    private let databaseAndTables = ["Select", "Insert", "Update", "Delete", "References", "Create", "Drop", "Alter", "Index", "Trigger"]
    private let viewsAndProcedures = ["Create View", "Show View", "Create Routine", "Alter Routine", "Execute", "Show Create Routine"]
    private let administration = ["Reload", "Shutdown", "File", "Process", "Super", "Create Temp Table", "Lock Tables", "Show Databases",
                                  "Create User", "Grant", "Set Any Definer", "Nonexistent Definer", "Event", "Create Tablespace",
                                  "Create Role", "Drop Role", "Binlog Admin", "Binlog Monitor", "Binlog Replay", "Connection Admin",
                                  "Federated Admin", "Read Only Admin", "Replica Monitor", "Set User"]
    private let replication = ["Replication Client", "Replication Slave", "Replication Master Admin", "Replication Slave Admin"]

    /// The tab content of the XIB's 870×536 sheet: its 692pt right pane less the tabs and the footer.
    private var xibPrivilegesArea: NSRect {
        let pane = Layout.paneFrames(in: NSRect(x: 0, y: 0, width: 692, height: 536), tabsWidth: 400, cancelWidth: 96, applyWidth: 96, buttonInset: 6)
        return Layout.tabContent(in: NSRect(origin: .zero, size: pane.content.size))
    }

    /// An NSBox's chrome as macOS 26+ lays a titled box out: the title above the card, a 1pt line around.
    private let chrome = SAClaudeCardLayout.Chrome(top: 19, bottom: 1, left: 1, right: 1)

    // MARK: Checkbox grid

    func testTwoColumnsWhenEveryTitleFits() {
        XCTAssertEqual(Grid.columnCount(itemWidths: [60, 80, 100], width: 300), 2)
    }

    func testOneColumnWhenATitleWouldBeCut() {
        let available = 2 * 120 + Grid.columnGap
        XCTAssertEqual(Grid.columnWidth(columns: 2, width: available), 120)
        XCTAssertEqual(Grid.columnCount(itemWidths: [60, 121], width: available), 1)
        XCTAssertEqual(Grid.columnCount(itemWidths: [60, 120], width: available), 2)
    }

    func testNeverMoreColumnsThanItems() {
        XCTAssertEqual(Grid.columnCount(itemWidths: [40], width: 600), 1)
        XCTAssertEqual(Grid.columnCount(itemWidths: [], width: 600), 1)
    }

    func testFramesFillColumnByColumnInOrder() {
        // Seven items in two columns: four down the first, three down the second, each as wide as its column.
        let rect = NSRect(x: 10, y: 0, width: 2 * 100 + Grid.columnGap, height: 200)
        let frames = Grid.frames(count: 7, columns: 2, in: rect)
        XCTAssertEqual(frames.count, 7)
        XCTAssertEqual(frames.prefix(4).map(\.minX), [10, 10, 10, 10])
        XCTAssertEqual(frames.suffix(3).map(\.minX), Array(repeating: 10 + 100 + Grid.columnGap, count: 3))
        XCTAssertEqual(frames[0].maxY, rect.maxY)
        XCTAssertEqual(frames[4].maxY, rect.maxY, "the second column starts at the top")
        XCTAssertEqual(frames[1].minY, frames[0].minY - Grid.rowPitch)
        XCTAssertTrue(frames.allSatisfy { $0.width == 100 && $0.height == Grid.rowHeight })
        XCTAssertEqual(Grid.height(count: 7, columns: 2), 3 * Grid.rowPitch + Grid.rowHeight)
    }

    func testHiddenItemsCloseUpTheGrid() {
        // The same card with two checkboxes hidden (a server without them) is one row shorter, with no gaps.
        XCTAssertEqual(Grid.rows(count: 24, columns: 2), 12)
        XCTAssertEqual(Grid.rows(count: 22, columns: 2), 11)
        let frames = Grid.frames(count: 22, columns: 2, in: NSRect(x: 0, y: 0, width: 300, height: 400))
        let firstColumn = frames.prefix(11).map(\.minY)
        XCTAssertEqual(firstColumn, (0..<11).map { 400 - CGFloat($0) * Grid.rowPitch - Grid.rowHeight })
    }

    func testReadingOrderKeepsANudgedColumnTogether() {
        // A XIB column whose checkboxes drifted by up to 2.4pt in x stays one column, read top to bottom, before the next.
        let frames = [
            NSRect(x: 186, y: 97, width: 140, height: 18),   // 0: second column, top
            NSRect(x: 16.6, y: 78, width: 140, height: 18),  // 1: first column, second
            NSRect(x: 18.4, y: 59, width: 140, height: 18),  // 2: first column, third (nudged 2.4pt right)
            NSRect(x: 16, y: 97, width: 140, height: 18),    // 3: first column, top
            NSRect(x: 187, y: 78, width: 140, height: 18),   // 4: second column, second
            NSRect(x: 15.5, y: 40, width: 140, height: 18),  // 5: first column, last (nudged left)
        ]
        XCTAssertEqual(Grid.readingOrder(of: frames), [3, 1, 2, 5, 0, 4])
        // Rounding x (the old grouping) would split the nudged column and scramble the order.
        let rounded = frames.indices.sorted { (frames[$0].minX.rounded(), -frames[$0].midY) < (frames[$1].minX.rounded(), -frames[$1].midY) }
        XCTAssertNotEqual(rounded, [3, 1, 2, 5, 0, 4])
    }

    func testReadingOrderSeparatesColumnsFurtherApartThanTheTolerance() {
        let frames = [NSRect(x: 0, y: 0, width: 10, height: 10), NSRect(x: Grid.columnTolerance + 1, y: 20, width: 10, height: 10)]
        XCTAssertEqual(Grid.readingOrder(of: frames), [0, 1])
        XCTAssertEqual(Grid.readingOrder(of: []), [])
    }

    // MARK: Form cards

    func testFormRowsRightOfTheLabelColumn() {
        let rows = SAClaudeFormCardLayout.rows(count: 2, labelWidth: 80, labelHeight: 16, width: 400)
        let height = SAClaudeFormCardLayout.contentHeight(rows: 2)
        XCTAssertEqual(height, 2 * SAClaudeCardLayout.verticalPadding + 2 * SAClaudeFormCardLayout.fieldHeight + SAClaudeFormCardLayout.rowGap)
        XCTAssertEqual(rows[0].field.maxY, height - SAClaudeCardLayout.verticalPadding)
        XCTAssertEqual(rows[0].field.minX, SAClaudeCardLayout.horizontalPadding + 80 + SAClaudeFormCardLayout.labelGap)
        XCTAssertEqual(rows[0].field.maxX, 400 - SAClaudeCardLayout.horizontalPadding)
        XCTAssertEqual(rows[1].field.maxY, rows[0].field.minY - SAClaudeFormCardLayout.rowGap)
        XCTAssertEqual(rows[1].label.midY, rows[1].field.midY, accuracy: 0.5)
        XCTAssertEqual(rows[1].label.maxX, rows[1].field.minX - SAClaudeFormCardLayout.labelGap)
    }

    /// A form card spans the tab content (the tabs' left edge to the pane's margin), however wide the pane.
    func testFormCardSpansTheContentWidth() {
        let area = NSRect(x: 20, y: 0, width: 652, height: 424)
        let card = Layout.formCard(in: area, rows: 3, chrome: chrome)
        XCTAssertEqual(card.minX, area.minX + chrome.left)
        XCTAssertEqual(card.maxY, area.maxY - chrome.top)
        XCTAssertEqual(card.minX - chrome.left, area.minX)
        XCTAssertEqual(card.maxX + chrome.right, area.maxX)
        XCTAssertEqual(Layout.formCard(in: NSRect(x: 0, y: 0, width: 300, height: 200), rows: 1, chrome: chrome).width, 300 - chrome.width)
        XCTAssertEqual(Layout.formCard(in: NSRect(x: 0, y: 0, width: 1200, height: 200), rows: 1, chrome: chrome).width, 1200 - chrome.width)
    }

    // MARK: Pane

    func testPaneTabsAtTopAndButtonsOnTheMargin() {
        let bounds = NSRect(x: 0, y: 0, width: 692, height: 536)
        let f = Layout.paneFrames(in: bounds, tabsWidth: 400, cancelWidth: 96, applyWidth: 90, buttonInset: 6)
        XCTAssertEqual(f.tabs, NSRect(x: Layout.margin, y: 536 - Layout.tabsTop - Layout.tabsHeight, width: 400, height: Layout.tabsHeight))
        // The drawn Apply ends on the right margin; the drawn Cancel sits buttonGap to its left.
        XCTAssertEqual(f.apply.maxX - 6, 692 - Layout.margin)
        XCTAssertEqual((f.apply.minX + 6) - (f.cancel.maxX - 6), Layout.buttonGap)
        XCTAssertEqual(f.apply.minY, Layout.footerBottom)
        XCTAssertEqual(f.content.minY, f.apply.maxY + Layout.footerGap)
        XCTAssertEqual(f.content.maxY, f.tabs.minY - Layout.tabsContentGap)
        XCTAssertEqual(f.content.width, 692)
    }

    func testTabsNeverWiderThanThePane() {
        let f = Layout.paneFrames(in: NSRect(x: 0, y: 0, width: 300, height: 400), tabsWidth: 900, cancelWidth: 90, applyWidth: 90, buttonInset: 6)
        XCTAssertEqual(f.tabs.width, 300 - 2 * Layout.margin)
    }

    // MARK: Global privileges

    private func card(_ titles: [String]) -> Layout.PrivilegeCard { Layout.PrivilegeCard(itemWidths: titles.map(width)) }

    func testEveryPrivilegeFitsTheXIBSizedSheet() {
        let area = xibPrivilegesArea
        let f = Layout.privileges(in: area, left: [card(databaseAndTables), card(viewsAndProcedures), card(replication)],
                                  right: [card(administration)], chrome: chrome, checkAllWidth: 100, uncheckAllWidth: 110)
        XCTAssertEqual(f.cards.count, 4)
        XCTAssertGreaterThanOrEqual(f.bottom, area.minY, "the cards and the pills fit the tab without growing the sheet")
        XCTAssertGreaterThanOrEqual(f.checkAll.minY, area.minY)
        for (index, content) in f.cards.enumerated() {
            let outer = NSRect(x: content.minX - chrome.left, y: content.minY - chrome.bottom,
                               width: content.width + chrome.width, height: content.height + chrome.height)
            XCTAssertTrue(area.contains(outer), "card \(index) inside the tab")
            for other in f.cards.indices where other != index {
                XCTAssertFalse(content.intersects(f.cards[other]), "cards \(index) and \(other) don't overlap")
            }
        }
        // Database and Tables, Views and Procedures and Administration in two columns; the long replication titles in one.
        XCTAssertEqual(f.columns, [2, 2, 1, 2])
    }

    func testCheckboxFramesStayInsideTheirCardAndKeepTheirOrder() {
        let f = Layout.privileges(in: xibPrivilegesArea, left: [card(databaseAndTables)], right: [card(administration)],
                                  chrome: chrome, checkAllWidth: 100, uncheckAllWidth: 110)
        for (content, frames) in zip(f.cards, f.checkboxes) {
            let local = NSRect(origin: .zero, size: content.size)
            XCTAssertTrue(frames.allSatisfy { local.contains($0) })
        }
        // Reading down the first column, then the second: item order.
        let admin = f.checkboxes[1]
        XCTAssertEqual(admin.count, administration.count)
        for index in 1..<12 { XCTAssertLessThan(admin[index].minY, admin[index - 1].minY) }
        XCTAssertGreaterThan(admin[12].minX, admin[11].minX)
        XCTAssertEqual(admin[12].maxY, admin[0].maxY)
        // Every title fits its column (nothing truncated).
        let widths = administration.map(width)
        XCTAssertTrue(zip(admin, widths).allSatisfy { $0.0.width >= $0.1 })
    }

    func testPillsUnderTheRightColumn() {
        let area = xibPrivilegesArea
        let f = Layout.privileges(in: area, left: [card(databaseAndTables)], right: [card(viewsAndProcedures)],
                                  chrome: chrome, checkAllWidth: 100, uncheckAllWidth: 110)
        let rightCardBottom = f.cards[1].minY - chrome.bottom
        XCTAssertEqual(f.checkAll.maxY, rightCardBottom - SAClaudeCardLayout.spacing)
        XCTAssertEqual(f.checkAll.minX, f.cards[1].minX - chrome.left)
        XCTAssertEqual(f.uncheckAll.minX, f.checkAll.maxX + Layout.pillGap)
        XCTAssertEqual(f.uncheckAll.minY, f.checkAll.minY)
        XCTAssertEqual(f.checkAll.height, Layout.pillHeight)
    }

    func testCardsShrinkWhenTheServerHidesPrivileges() {
        let all = Layout.privileges(in: xibPrivilegesArea, left: [], right: [card(administration)], chrome: chrome,
                                    checkAllWidth: 100, uncheckAllWidth: 110)
        // A MySQL 8 server without the MariaDB-only ones: 17 visible of 24.
        let mysql = administration.filter { !["Binlog Monitor", "Binlog Replay", "Federated Admin", "Replica Monitor", "Set User",
                                              "Set Any Definer", "Nonexistent Definer"].contains($0) }
        let fewer = Layout.privileges(in: xibPrivilegesArea, left: [], right: [card(mysql)], chrome: chrome,
                                      checkAllWidth: 100, uncheckAllWidth: 110)
        XCTAssertEqual(fewer.checkboxes[0].count, 17)
        XCTAssertEqual(all.cards[0].height - fewer.cards[0].height, 3 * Grid.rowPitch)
        XCTAssertGreaterThan(fewer.checkAll.minY, all.checkAll.minY, "the pills follow the shorter card up")
    }

    func testMinimumPaneWidthKeepsEveryCardsColumns() {
        let cards = [card(databaseAndTables), card(viewsAndProcedures), card(replication), card(administration)]
        let atXIB = Layout.privileges(in: xibPrivilegesArea, left: Array(cards.prefix(3)), right: [cards[3]], chrome: chrome,
                                      checkAllWidth: 100, uncheckAllWidth: 110)
        let minimum = Layout.minimumPaneWidth(cards: cards, columns: atXIB.columns, chrome: chrome)
        XCTAssertLessThanOrEqual(minimum, 692, "the XIB's pane is wide enough")
        func columns(paneWidth: CGFloat) -> [Int] {
            let area = Layout.tabContent(in: NSRect(x: 0, y: 0, width: paneWidth, height: 424))
            return Layout.privileges(in: area, left: Array(cards.prefix(3)), right: [cards[3]], chrome: chrome,
                                     checkAllWidth: 100, uncheckAllWidth: 110).columns
        }
        XCTAssertEqual(columns(paneWidth: minimum), atXIB.columns)
        XCTAssertNotEqual(columns(paneWidth: minimum - 2), atXIB.columns, "any narrower and a card loses a column")
    }

    // MARK: Schema privileges

    func testSchemaListsAndArrows() {
        let area = NSRect(x: 20, y: 0, width: 652, height: 424)
        let f = Layout.schema(in: area)
        XCTAssertEqual(f.schemas.minX, area.minX)
        XCTAssertEqual(f.available.maxX, area.maxX)
        XCTAssertEqual(f.schemas.width, f.granted.width)
        XCTAssertEqual(f.granted.width, f.available.width)
        XCTAssertEqual(f.granted.minX, f.schemas.maxX + Layout.schemaGap)
        XCTAssertTrue([f.schemas, f.granted, f.available].allSatisfy { $0.height == area.height })
        // The arrows between granted and available, ◀ above ▶, centred.
        XCTAssertGreaterThanOrEqual(f.add.minX, f.granted.maxX + Layout.arrowColumnGap - 1)
        XCTAssertLessThanOrEqual(f.add.maxX, f.available.minX - Layout.arrowColumnGap + 1)
        XCTAssertEqual(f.add.minX, f.remove.minX)
        XCTAssertGreaterThan(f.add.minY, f.remove.maxY)
        XCTAssertEqual((f.add.maxY + f.remove.minY) / 2, area.midY, accuracy: 1)
    }

    // MARK: Sidebar bar

    /// Add and remove are 28pt squares; the gear pull-down takes the width its glyph and chevron need, and nothing after
    /// it overlaps it.
    func testBarButtonsLeftToRightWithAWiderGear() {
        let size = SAClaudeSidebarBarLayout.buttonSize, gap = SAClaudeSidebarBarLayout.buttonGap
        let frames = Layout.barButtons(widths: [size, size, 35], x: 6, midY: 16)
        XCTAssertEqual(frames.map(\.minX), [6, 6 + size + gap, 6 + 2 * (size + gap)])
        XCTAssertEqual(frames.map(\.width), [size, size, 35])
        XCTAssertTrue(frames.allSatisfy { $0.midY == 16 && $0.height == size })
    }

    // MARK: Manager forms

    private typealias Form = SAClaudeManagerFormLayout

    /// The Query Favorites manager's right pane at the XIB's size (385 × 359), its labels measured at 11pt.
    private func favorites(_ bounds: NSRect = NSRect(x: 0, y: 0, width: 385, height: 359)) -> Form.FavoritesFrames {
        Form.favorites(in: bounds, nameLabelWidth: 34, triggerLabelWidth: 63, saveWidth: 84, cancelWidth: 84, buttonInset: 6,
                       placeholderSize: NSSize(width: 144, height: 25), help: true)
    }

    /// One label column: Name and Tab Trigger end at the same x, their fields start at the same x, the longest label's
    /// text on the left margin with the editor's left edge.
    func testFavoritesLabelsShareOneColumn() {
        let f = favorites()
        XCTAssertEqual(f.name.label.maxX, f.trigger.label.maxX)
        XCTAssertEqual(f.name.field.minX, f.trigger.field.minX)
        XCTAssertEqual(f.name.label.minX + Form.labelInset, Form.margin)
        XCTAssertEqual(f.editor.minX, Form.margin)
        XCTAssertEqual(f.name.field.minX - (f.name.label.maxX - Form.labelInset), Form.labelGap)
        XCTAssertEqual(f.name.field.maxX, 385 - Form.margin)
        XCTAssertEqual(f.editor.maxX, 385 - Form.margin)
        XCTAssertEqual(f.name.label.midY, f.name.field.midY, accuracy: 0.5)
        XCTAssertEqual(f.trigger.label.midY, f.trigger.field.midY, accuracy: 0.5)
    }

    func testFavoritesEditorBetweenTheRowsAndTheFooterOnOneLine() {
        let f = favorites()
        XCTAssertEqual(f.name.field.maxY, 359 - Form.top)
        XCTAssertEqual(f.editor.maxY, f.name.field.minY - Form.editorGap)
        XCTAssertEqual(f.editor.minY, f.trigger.field.maxY + Form.editorGap)
        XCTAssertEqual(f.trigger.field.minY, f.footer.save.maxY + Form.editorGap)
        XCTAssertGreaterThan(f.editor.height, 150)
        let midY = f.footer.save.midY
        for rect in [f.footer.cancel, f.footer.help!, f.footer.accessory!] { XCTAssertEqual(rect.midY, midY, accuracy: 0.5) }
        XCTAssertEqual(f.footer.help!.minX + Form.helpInset, Form.margin)
        XCTAssertEqual(f.footer.accessory!.minX, f.footer.help!.maxX + Form.itemGap)
        XCTAssertLessThan(f.footer.accessory!.maxX, f.footer.cancel.minX + 6)
    }

    private func contentFilter(_ bounds: NSRect = NSRect(x: 0, y: 0, width: 286, height: 361)) -> Form.FilterFrames {
        Form.contentFilter(in: bounds, nameLabelWidth: 34, conjunctionLabelWidth: 98, saveWidth: 84, cancelWidth: 84, buttonInset: 6,
                           placeholderSize: NSSize(width: 146, height: 25), suppressWidth: 252,
                           argumentCountWidth: 128, resultHeight: 55)
    }

    func testContentFilterLabelsShareOneColumnAndTheLeftEdge() {
        let f = contentFilter()
        XCTAssertEqual(f.name.label.maxX, f.conjunction.label.maxX)
        XCTAssertEqual(f.name.field.minX, f.conjunction.field.minX)
        let left = Form.margin
        XCTAssertEqual(f.name.label.minX + Form.labelInset, left)
        XCTAssertEqual(f.clauseLabel.minX + Form.labelInset, left)
        XCTAssertEqual(f.resultLabel.minX + Form.labelInset, left)
        XCTAssertEqual(f.result.minX + Form.labelInset, left)
        XCTAssertEqual(f.editor.minX, left)
        XCTAssertEqual(f.placeholder.minX, left)
        XCTAssertEqual(f.suppress.minX, left)
        XCTAssertEqual(f.argumentCount.maxX - Form.labelInset, 286 - Form.margin)
        XCTAssertEqual(f.argumentCount.midY, f.clauseLabel.midY)
        XCTAssertEqual(f.argumentCount.width, 128 + 2 * Form.labelInset)
        XCTAssertEqual(f.clauseLabel.maxX, f.argumentCount.minX)
    }

    func testContentFilterTopToBottomWithoutOverlaps() {
        let f = contentFilter()
        let order = [f.name.field, f.clauseLabel, f.editor, f.suppress, f.placeholder, f.conjunction.field, f.resultLabel, f.result, f.footer.save]
        for (upper, lower) in zip(order, order.dropFirst()) { XCTAssertGreaterThan(upper.minY, lower.maxY - 0.5, "\(upper) over \(lower)") }
        XCTAssertGreaterThan(f.editor.height, 50)
        XCTAssertEqual(f.footer.cancel.midY, f.footer.save.midY)
        XCTAssertEqual(f.footer.save.maxX - 6, 286 - Form.margin)
    }
}
