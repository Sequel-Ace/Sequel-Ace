import XCTest
import AppKit

final class SAClaudeImportLayoutTests: XCTestCase {
    private typealias A = SAClaudeImportAccessoryLayout
    private typealias M = SAClaudeImportMapperLayout
    private let inputs = M.Inputs(pathWidth: 260, intoLabelWidth: 30, newButtonWidth: 100, nameLabelWidth: 40, goBackWidth: 90)

    private func assertInside(_ inner: NSRect, _ outer: NSRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(outer.insetBy(dx: -0.5, dy: -0.5).contains(inner), "\(inner) not inside \(outer)", file: file, line: line)
    }
    private func assertApart(_ a: NSRect, _ b: NSRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(a.insetBy(dx: 0.5, dy: 0.5).intersects(b.insetBy(dx: 0.5, dy: 0.5)), "\(a) overlaps \(b)", file: file, line: line)
    }

    func testCSVStripHeightAndGrid() {
        for width: CGFloat in [537, 707] {
            let f = A.frames(width: width, format: .csv, switcherWidth: 110, encodingLabelWidth: 60)
            XCTAssertEqual(f.height, 142)
            let bounds = NSRect(x: 0, y: 0, width: width, height: f.height)
            XCTAssertEqual(f.csvLabels.count, 4); XCTAssertEqual(f.csvFields.count, 4)
            for r in [f.formatSwitcher, f.encodingLabel, f.encoding, f.firstLine] + f.csvLabels + f.csvFields { assertInside(r, bounds) }
            assertApart(f.formatSwitcher, f.encodingLabel)
            XCTAssertEqual(f.csvLabels[0].minY, f.csvLabels[1].minY)   // same row
            XCTAssertEqual(f.csvLabels[0].minX, f.csvLabels[2].minX)   // same column
            XCTAssertGreaterThan(f.csvLabels[0].minY, f.csvLabels[2].minY)
            for (label, field) in zip(f.csvLabels, f.csvFields) { assertApart(label, field) }
            assertApart(f.csvFields[0], f.csvLabels[1])
            XCTAssertEqual(f.encoding.maxX, width - 16)
            XCTAssertEqual(f.sqlPopUp, .zero)
        }
    }

    func testSQLStrip() {
        let f = A.frames(width: 707, format: .sql, switcherWidth: 110, encodingLabelWidth: 60)
        XCTAssertEqual(f.height, 84)
        XCTAssertEqual(f.sqlLabel.minX, 16)
        XCTAssertEqual(f.sqlPopUp.minX, 16 + 110 + 8)
        XCTAssertEqual(f.sqlPopUp.minY, 12)
        XCTAssertEqual(f.firstLine, .zero)
        XCTAssertTrue(f.csvFields.isEmpty)
    }

    func testMapperAtMinimumSize() {
        let f = M.frames(in: NSRect(origin: .zero, size: M.minimumContentSize), inputs)
        XCTAssertEqual(f.rightCard.width, 327)                 // max(300, round(818 * 0.4))
        XCTAssertEqual(f.leftCard.width, 491)
        XCTAssertEqual(f.leftCard.minY, 54); XCTAssertEqual(f.leftCard.height, 452)
        XCTAssertEqual(f.importButton.maxX - 6, 844)
        XCTAssertEqual((f.importButton.minX + 6) - (f.cancel.maxX - 6), 8)
        for r in [f.leftTitle, f.navigatorLabel, f.previousRow, f.nextRow, f.table] { assertInside(r, f.leftCard) }
        for r in [f.rightTitle, f.options] { assertInside(r, f.rightCard) }
        assertApart(f.leftTitle, f.navigatorLabel); assertApart(f.navigatorLabel, f.previousRow); assertApart(f.previousRow, f.nextRow)
        assertApart(f.title, f.path); assertApart(f.path, f.intoLabel); assertApart(f.intoLabel, f.target); assertApart(f.target, f.newButton)
        assertApart(f.nameLabel, f.nameField); assertApart(f.nameField, f.info)
        assertApart(f.goBack, f.cancel.insetBy(dx: 6, dy: 0))
        XCTAssertGreaterThan(f.table.height, 300)
        XCTAssertEqual(f.newButton.maxX, 844); XCTAssertEqual(f.info.maxX, 844)
    }

    func testTableTakesExtraHeightAndOptionsKeepMinimum() {
        let small = M.frames(in: NSRect(origin: .zero, size: M.minimumContentSize), inputs)
        let large = M.frames(in: NSRect(x: 0, y: 0, width: 1200, height: 800), inputs)
        XCTAssertEqual(large.table.height - small.table.height, 240)
        XCTAssertEqual(M.frames(in: NSRect(x: 0, y: 0, width: 700, height: 560), inputs).rightCard.width, 300)
    }

    func testPathShrinksToFitTheHeader() {
        var wide = inputs; wide.pathWidth = 2000
        let f = M.frames(in: NSRect(origin: .zero, size: M.minimumContentSize), wide)
        assertApart(f.path, f.intoLabel)
        XCTAssertLessThan(f.path.width, 2000)
    }

    func testMethodSegments() {
        XCTAssertEqual(M.methodSegments(itemEnabled: [true, false, true], selectedTag: 2, newTableMode: false),
                       M.MethodSegments(enabled: [true, false, true], selected: 2))
        XCTAssertEqual(M.methodSegments(itemEnabled: [true, true, true], selectedTag: 1, newTableMode: true),
                       M.MethodSegments(enabled: [true, false, false], selected: 0))
        XCTAssertEqual(M.methodSegments(itemEnabled: [true, true], selectedTag: 5, newTableMode: false).selected, 0)
    }
}
