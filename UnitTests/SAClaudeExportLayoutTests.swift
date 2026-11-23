import XCTest
import AppKit

final class SAClaudeExportLayoutTests: XCTestCase {
    private typealias L = SAClaudeExportLayout
    private let inputs = L.BodyInputs(sourceSwitcherWidth: 290, showsFilePerTable: true, allWidth: 32, noneWidth: 44,
                                      customiseWidth: 84, compressionLabelWidth: 80, compressionWidth: 160, lowMemoryWidth: 104)

    private func assertInside(_ inner: NSRect, _ outer: NSRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(outer.insetBy(dx: -0.5, dy: -0.5).contains(inner), "\(inner) not inside \(outer)", file: file, line: line)
    }
    private func assertApart(_ a: NSRect, _ b: NSRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(a.insetBy(dx: 0.5, dy: 0.5).intersects(b.insetBy(dx: 0.5, dy: 0.5)), "\(a) overlaps \(b)", file: file, line: line)
    }

    func testWindowAtMinimumSize() {
        let w = L.window(in: NSRect(origin: .zero, size: L.minimumContentSize), switcherWidth: 220)
        XCTAssertEqual(w.title.minX, 16); XCTAssertEqual(w.title.maxY, 584)
        XCTAssertEqual(w.formatSwitcher.maxX, 744); XCTAssertEqual(w.formatSwitcher.width, 220)
        XCTAssertEqual(w.body, NSRect(x: 0, y: 54, width: 760, height: 492))
        // Export's drawn edge (frame inset 6) sits on the right margin; Cancel's drawn edge 8pt to its left.
        XCTAssertEqual(w.export.maxX - 6, 744)
        XCTAssertEqual((w.export.minX + 6) - (w.cancel.maxX - 6), 8)
        XCTAssertEqual(w.presets.minX, 16)
        assertApart(w.info, w.presets); assertApart(w.info, w.cancel.insetBy(dx: 6, dy: 0))
        XCTAssertGreaterThan(w.info.width, 200)
    }

    func testBodyAtMinimumSizeHasNoOverlaps() {
        let b = L.body(in: NSRect(x: 0, y: 0, width: 760, height: 492), inputs)
        XCTAssertEqual(b.rightCard.width, 323)          // max(280, round(718 * 0.45))
        XCTAssertEqual(b.leftCard.width, 395)
        XCTAssertEqual(b.saveCard, NSRect(x: 16, y: 0, width: 728, height: 100))
        XCTAssertEqual(b.leftCard.minY, 110)
        for r in [b.leftTitle, b.sourceSwitcher, b.filePerTable, b.tableList, b.bar] { assertInside(r, b.leftCard) }
        for r in [b.rightTitle, b.options] { assertInside(r, b.rightCard) }
        for r in [b.saveTitle, b.folderGlyph, b.path, b.fileGlyph, b.filename, b.customise, b.compressionLabel, b.compression, b.lowMemory] {
            assertInside(r, b.saveCard)
        }
        assertApart(b.path, b.change.insetBy(dx: 6, dy: 0))
        assertApart(b.filename, b.customise); assertApart(b.customise, b.compressionLabel)
        assertApart(b.compressionLabel, b.compression); assertApart(b.compression, b.lowMemory)
        assertApart(b.tableList, b.bar); assertApart(b.tableList, b.filePerTable)
        assertApart(b.none, b.all); assertApart(b.refresh, b.none)
        XCTAssertGreaterThan(b.tableList.height, 200)
    }

    func testTableListTakesExtraHeightAndFilePerTableSpace() {
        let small = L.body(in: NSRect(x: 0, y: 0, width: 760, height: 492), inputs)
        let tall = L.body(in: NSRect(x: 0, y: 0, width: 1100, height: 692), inputs)
        XCTAssertEqual(tall.tableList.height - small.tableList.height, 200)
        var hidden = inputs; hidden.showsFilePerTable = false
        let noCheck = L.body(in: NSRect(x: 0, y: 0, width: 760, height: 492), hidden)
        XCTAssertEqual(noCheck.filePerTable.height, 0)
        XCTAssertEqual(noCheck.tableList.height - small.tableList.height, L.checkboxRowHeight + L.rowGap)
    }

    func testOptionsCardKeepsItsMinimumWidth() {
        let b = L.body(in: NSRect(x: 0, y: 0, width: 600, height: 492), inputs)
        XCTAssertEqual(b.rightCard.width, 280)
    }

    func testOptionRowsFlowTopDownWithGroupGapsAndIndent() {
        let content = NSRect(x: 10, y: 0, width: 200, height: 300)
        let rows = L.optionRows([.title, .control(indented: false), .control(indented: true), .title, .control(indented: false)], in: content)
        XCTAssertEqual(rows[0], NSRect(x: 10, y: 284, width: 200, height: 16))
        XCTAssertEqual(rows[1], NSRect(x: 10, y: 258, width: 200, height: 22))
        XCTAssertEqual(rows[2], NSRect(x: 28, y: 232, width: 182, height: 22))
        XCTAssertEqual(rows[3], NSRect(x: 10, y: 204, width: 200, height: 16))   // 4 row gap + 8 group gap
        XCTAssertEqual(rows[4], NSRect(x: 10, y: 178, width: 200, height: 22))
    }

    func testColumnTitles() {
        XCTAssertEqual(L.columnTitles(for: .sql), L.ColumnTitles(structure: "Structure", content: "Content", drop: "Drop"))
        XCTAssertEqual(L.columnTitles(for: .csv).content, "Include")
        XCTAssertEqual(L.columnTitles(for: .dot).content, "Include")
    }

    func testSourceSegmentsMirrorThePopUp() {
        // Pop-up order: Filtered, Query, Tables. Switcher order: Tables, Filtered, Query.
        XCTAssertEqual(L.sourceSegments(format: .csv, popUpEnabled: [true, false, true], popUpSelected: 0),
                       L.SourceSegments(enabled: [true, true, false], selected: 1))
        XCTAssertEqual(L.sourceSegments(format: .sql, popUpEnabled: [false, false, true], popUpSelected: 2),
                       L.SourceSegments(enabled: [true, false, false], selected: 0))
        // Applied settings picked Query results programmatically.
        XCTAssertEqual(L.sourceSegments(format: .xml, popUpEnabled: [true, true, true], popUpSelected: 1).selected, 2)
    }

    func testDotDisablesTheSourceSwitcher() {
        XCTAssertEqual(L.sourceSegments(format: .dot, popUpEnabled: [true, true, false], popUpSelected: 2),
                       L.SourceSegments(enabled: [false, false, false], selected: 0))
    }
}
