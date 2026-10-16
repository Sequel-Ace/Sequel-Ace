import XCTest
import AppKit

final class SAClaudeFormLayoutTests: XCTestCase {
    private typealias L = SAClaudeFormLayout
    /// A small XIB push button (5pt classic side margins) and the sheet's small primary.
    private let small = L.FooterItem(width: 86, height: 28, inset: 5)
    private let smallPrimary = L.FooterItem(width: 70, height: 28, inset: 5)

    private func assertNonNegative(_ r: NSRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(r.width, 0, "\(r)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(r.height, 0, "\(r)", file: file, line: line)
    }

    func testRowsLabelsAndFooter() {
        let spec = L.Spec(items: [.row(labelWidth: 80, control: .field), .row(labelWidth: 100, control: .popUp), .row(labelWidth: 95, control: .popUp)],
                          hasContext: true, footerTrailing: [small, smallPrimary], currentSize: NSSize(width: 384, height: 133))
        let f = L.frames(spec)
        XCTAssertEqual(f.size, NSSize(width: 384, height: 237))
        XCTAssertEqual(f.minimumSize, NSSize(width: 360, height: 237))
        XCTAssertFalse(f.heightIsFlexible)
        XCTAssertEqual(f.labelColumnWidth, 100)
        XCTAssertFalse(f.truncatesLabels)
        XCTAssertEqual(f.title, NSRect(x: 20, y: 201, width: 344, height: 18))
        XCTAssertEqual(f.context, NSRect(x: 20, y: 184, width: 344, height: 15))
        XCTAssertEqual(f.items[0], L.ItemFrame(label: NSRect(x: 20, y: 146, width: 100, height: 16), control: NSRect(x: 130, y: 142, width: 234, height: 24)))
        XCTAssertEqual(f.items[1], L.ItemFrame(label: NSRect(x: 20, y: 108, width: 100, height: 16), control: NSRect(x: 130, y: 102, width: 234, height: 28)))
        XCTAssertEqual(f.items[2], L.ItemFrame(label: NSRect(x: 20, y: 70, width: 100, height: 16), control: NSRect(x: 130, y: 64, width: 234, height: 28)))
        XCTAssertEqual(f.footerTrailing, [NSRect(x: 215, y: 16, width: 86, height: 28), NSRect(x: 299, y: 16, width: 70, height: 28)])
        // Drawn edges: the primary ends on the right margin, Cancel 8pt to its left.
        XCTAssertEqual(f.footerTrailing[1].maxX - 5, 364)
        XCTAssertEqual((f.footerTrailing[1].minX + 5) - (f.footerTrailing[0].maxX - 5), 8)
        XCTAssertTrue(f.footerLeading.isEmpty)
    }

    func testSectionsAndCheckboxRows() {
        let spec = L.Spec(items: [.section, .row(labelWidth: 50, control: .popUp), .section, .row(labelWidth: 60, control: .field), .control(.checkbox)],
                          hasContext: false, currentSize: NSSize(width: 300, height: 200))
        let f = L.frames(spec)
        XCTAssertEqual(f.size, NSSize(width: 360, height: 268))
        XCTAssertNil(f.context)
        XCTAssertEqual(f.labelColumnWidth, 64)
        XCTAssertEqual(f.title, NSRect(x: 20, y: 232, width: 320, height: 18))
        XCTAssertEqual(f.items[0], L.ItemFrame(control: NSRect(x: 20, y: 202, width: 320, height: 14)))
        XCTAssertEqual(f.items[1], L.ItemFrame(label: NSRect(x: 20, y: 172, width: 64, height: 16), control: NSRect(x: 94, y: 166, width: 246, height: 28)))
        XCTAssertEqual(f.items[2], L.ItemFrame(control: NSRect(x: 20, y: 138, width: 320, height: 14)))
        XCTAssertEqual(f.items[3], L.ItemFrame(label: NSRect(x: 20, y: 108, width: 64, height: 16), control: NSRect(x: 94, y: 104, width: 246, height: 24)))
        XCTAssertEqual(f.items[4], L.ItemFrame(control: NSRect(x: 94, y: 69, width: 246, height: 18)))
    }

    func testGrowingBlockTakesExtraHeightWhenResizable() {
        var spec = L.Spec(items: [.row(labelWidth: 40, control: .field), .row(labelWidth: 40, control: .popUp), .row(labelWidth: 40, control: .popUp),
                                  .block(minHeight: 120, grows: true, stripHeight: 0)],
                          hasContext: true, currentSize: NSSize(width: 360, height: 500), resizable: true)
        var f = L.frames(spec)
        XCTAssertTrue(f.heightIsFlexible)
        XCTAssertEqual(f.size, NSSize(width: 360, height: 500))
        XCTAssertEqual(f.minimumSize, NSSize(width: 360, height: 367))
        XCTAssertEqual(f.items[3].surface, NSRect(x: 20, y: 64, width: 320, height: 253))
        XCTAssertEqual(f.items[3].control, NSRect(x: 24, y: 68, width: 312, height: 245))
        XCTAssertNil(f.items[3].strip)
        // A saved or dragged size smaller than the form: the natural height.
        spec.currentSize = NSSize(width: 360, height: 300)
        XCTAssertEqual(L.frames(spec).size.height, 367)
        // Not resizable: always the natural height, the block at its minimum.
        spec.currentSize = NSSize(width: 360, height: 500)
        spec.resizable = false
        f = L.frames(spec)
        XCTAssertFalse(f.heightIsFlexible)
        XCTAssertEqual(f.items[3].surface, NSRect(x: 20, y: 64, width: 320, height: 120))
        for item in f.items { assertNonNegative(item.control) }
    }

    func testBlockStripAtTheBottom() {
        let f = L.frames(L.Spec(items: [.block(minHeight: 104, grows: true, stripHeight: 24)], hasContext: false, currentSize: .zero, resizable: true))
        XCTAssertEqual(f.size, NSSize(width: 360, height: 220))
        XCTAssertEqual(f.items[0].surface, NSRect(x: 20, y: 64, width: 320, height: 104))
        XCTAssertEqual(f.items[0].strip, NSRect(x: 20, y: 64, width: 320, height: 24))
        XCTAssertEqual(f.items[0].control, NSRect(x: 24, y: 89, width: 312, height: 75))
    }

    func testLongLabelsWidenThenTruncate() {
        let moderate = L.frames(L.Spec(items: [.row(labelWidth: 250, control: .field)], hasContext: false, currentSize: NSSize(width: 384, height: 100)))
        XCTAssertEqual(moderate.size.width, 500)
        XCTAssertEqual(moderate.labelColumnWidth, 250)
        XCTAssertFalse(moderate.truncatesLabels)
        let long = L.frames(L.Spec(items: [.row(labelWidth: 400, control: .field)], hasContext: false, currentSize: NSSize(width: 384, height: 100)))
        XCTAssertEqual(long.size.width, 560)
        XCTAssertEqual(long.minimumSize.width, 560)
        XCTAssertEqual(long.labelColumnWidth, 310)
        XCTAssertTrue(long.truncatesLabels)
        XCTAssertEqual(long.items[0].control.minX, 340)
        XCTAssertEqual(long.items[0].control.width, 200)
        // Truncation starts only once the sheet is at its 560pt maximum: a sheet already wider (saved or dragged) gives the
        // labels the room it has.
        let wide = L.frames(L.Spec(items: [.row(labelWidth: 400, control: .field)], hasContext: false, currentSize: NSSize(width: 700, height: 100)))
        XCTAssertEqual(wide.size.width, 700)
        XCTAssertEqual(wide.labelColumnWidth, 400)
        XCTAssertFalse(wide.truncatesLabels)
        let tooLong = L.frames(L.Spec(items: [.row(labelWidth: 500, control: .field)], hasContext: false, currentSize: NSSize(width: 700, height: 100)))
        XCTAssertEqual(tooLong.labelColumnWidth, 450)
        XCTAssertTrue(tooLong.truncatesLabels)
        XCTAssertEqual(tooLong.items[0].control.width, 200)
    }

    func testFooterLeadingAndTrailing() {
        let f = L.frames(L.Spec(items: [.block(minHeight: 120, grows: true, stripHeight: 0)], hasContext: true,
                                footerLeading: [L.FooterItem(width: 90, height: 28, inset: 5), L.FooterItem(width: 124, height: 28, inset: 5)],
                                footerTrailing: [L.FooterItem(width: 77, height: 28, inset: 5)],
                                currentSize: NSSize(width: 411, height: 341), resizable: true))
        XCTAssertEqual(f.footerLeading, [NSRect(x: 15, y: 16, width: 90, height: 28), NSRect(x: 103, y: 16, width: 124, height: 28)])
        XCTAssertEqual(f.footerTrailing, [NSRect(x: 319, y: 16, width: 77, height: 28)])
        // A spinner (no bezel margins) sits on the margin centred on the footer row; a 32pt regular button overhangs it evenly.
        let footer = L.footerFrames(width: 400, leading: [L.FooterItem(width: 16, height: 16)], trailing: [L.FooterItem(width: 99, height: 32, inset: 6)])
        XCTAssertEqual(footer.leading, [NSRect(x: 20, y: 22, width: 16, height: 16)])
        XCTAssertEqual(footer.trailing, [NSRect(x: 287, y: 14, width: 99, height: 32)])
    }

    func testApplyingTwiceIsStable() {
        let items: [L.Item] = [.row(labelWidth: 70, control: .field), .section, .block(minHeight: 120, grows: true, stripHeight: 24), .control(.checkbox)]
        for resizable in [false, true] {
            var spec = L.Spec(items: items, hasContext: true, footerLeading: [L.FooterItem(width: 16, height: 16)], footerTrailing: [small, smallPrimary],
                              currentSize: NSSize(width: 330, height: 274), resizable: resizable)
            let first = L.frames(spec)
            spec.currentSize = first.size
            XCTAssertEqual(L.frames(spec), first)
        }
    }

    func testWidthFloorAndFixedWidth() {
        var spec = L.Spec(items: [.row(labelWidth: 60, control: .field)], hasContext: false, currentSize: NSSize(width: 260, height: 192))
        XCTAssertEqual(L.frames(spec).size.width, 360)
        spec.fixedWidth = 420
        XCTAssertEqual(L.frames(spec).size.width, 420)
        spec.fixedWidth = 300
        XCTAssertEqual(L.frames(spec).size.width, 360)
        // A wide footer widens the sheet too.
        spec.fixedWidth = nil
        spec.footerTrailing = [L.FooterItem(width: 210, height: 28, inset: 5), L.FooterItem(width: 210, height: 28, inset: 5)]
        XCTAssertEqual(L.frames(spec).size.width, 448)
    }

    func testFoldAddsExactlyItsRows() {
        let folded: [L.Item] = [.row(labelWidth: 70, control: .field), .row(labelWidth: 70, control: .popUp), .section,
                                .block(minHeight: 104, grows: true, stripHeight: 24), .section]
        let open = folded + [.row(labelWidth: 90, control: .popUp), .row(labelWidth: 90, control: .field)]
        let closed = L.frames(L.Spec(items: folded, hasContext: true, footerTrailing: [small, smallPrimary],
                                     currentSize: NSSize(width: 330, height: 274), resizable: true))
        XCTAssertEqual(closed.size.height, 367)
        XCTAssertEqual(closed.minimumSize.height, 367)
        let opened = L.frames(L.Spec(items: open, hasContext: true, footerTrailing: [small, smallPrimary], currentSize: closed.size, resizable: true))
        XCTAssertEqual(opened.minimumSize.height - closed.minimumSize.height, 74)
        XCTAssertEqual(opened.size.height, closed.size.height + 74)
        // The footer stays at the bottom: the last item's slot ends 20pt above the 28pt footer row (16 + 28 + 20 = 64);
        // closed, that is the 14pt disclosure section; open, a 28pt row slot.
        XCTAssertEqual(closed.items.last?.control.minY, 64)
        XCTAssertEqual(opened.items.last?.control.minY, 66)   // the 24pt field centred on that slot
    }

    func testRowLabelText() {
        XCTAssertEqual(SAClaudeFormText.rowLabel("Database Name:"), "Database Name")
        XCTAssertEqual(SAClaudeFormText.rowLabel("Reset AUTO_INCREMENT to: "), "Reset AUTO_INCREMENT to")
        XCTAssertEqual(SAClaudeFormText.rowLabel("名前："), "名前")
        XCTAssertEqual(SAClaudeFormText.rowLabel("Key Type"), "Key Type")
        XCTAssertEqual(SAClaudeFormText.rowLabel(":"), ":")
    }

    func testJoinedContext() {
        XCTAssertEqual(SAClaudeFormText.joined(["users", nil, " ", "INT(11)"]), "users · INT(11)")
        XCTAssertNil(SAClaudeFormText.joined([nil, ""]))
    }

    // MARK: - Field editor and BIT editor

    private var regularCancel: L.FooterItem { L.FooterItem(width: 99, height: 32, inset: 6) }
    private var regularOK: L.FooterItem { L.FooterItem(width: 99, height: 32, inset: 6) }

    func testEditorStripSwitcherIconsSurfaceAndFooterFrames() {
        let f = L.editorFrames(L.EditorSpec(size: NSSize(width: 735, height: 428), hasContext: true, switcherWidth: 200, iconCount: 3,
                                            footerLeading: [L.FooterItem(width: 220, height: 18)], footerTrailing: [regularCancel, regularOK]))
        XCTAssertEqual(f.title, NSRect(x: 20, y: 392, width: 695, height: 18))
        XCTAssertEqual(f.context, NSRect(x: 20, y: 375, width: 695, height: 15))
        XCTAssertEqual(f.surface, NSRect(x: 20, y: 64, width: 695, height: 295))
        XCTAssertEqual(f.strip, NSRect(x: 20, y: 319, width: 695, height: 40))
        XCTAssertEqual(f.switcher, NSRect(x: 28, y: 326, width: 200, height: 26))
        XCTAssertEqual(f.icons, [NSRect(x: 615, y: 325, width: 28, height: 28), NSRect(x: 647, y: 325, width: 28, height: 28),
                                 NSRect(x: 679, y: 325, width: 28, height: 28)])
        XCTAssertEqual(f.content, NSRect(x: 24, y: 68, width: 687, height: 250))
        XCTAssertEqual(f.footerLeading, [NSRect(x: 20, y: 21, width: 220, height: 18)])
        XCTAssertEqual(f.footerTrailing, [NSRect(x: 527, y: 14, width: 99, height: 32), NSRect(x: 622, y: 14, width: 99, height: 32)])
    }

    func testEditorStripCollapsesWithoutSwitcherAndIcons() {
        let f = L.editorFrames(L.EditorSpec(size: NSSize(width: 735, height: 428), hasContext: true, switcherWidth: 0, iconCount: 0))
        XCTAssertNil(f.strip)
        XCTAssertNil(f.switcher)
        XCTAssertTrue(f.icons.isEmpty)
        // No strip: the content starts 4pt under the surface's top edge (359 - 4 = 355) and fills the whole surface.
        XCTAssertEqual(f.surface, NSRect(x: 20, y: 64, width: 695, height: 295))
        XCTAssertEqual(f.content, NSRect(x: 24, y: 68, width: 687, height: 287))
        // Icons only: the strip stays and the icons are right-aligned, no switcher.
        let iconsOnly = L.editorFrames(L.EditorSpec(size: NSSize(width: 735, height: 428), hasContext: false, switcherWidth: 0, iconCount: 2))
        XCTAssertEqual(iconsOnly.strip, NSRect(x: 20, y: 336, width: 695, height: 40))
        XCTAssertNil(iconsOnly.switcher)
        XCTAssertEqual(iconsOnly.icons, [NSRect(x: 647, y: 342, width: 28, height: 28), NSRect(x: 679, y: 342, width: 28, height: 28)])
        XCTAssertEqual(iconsOnly.icons.last?.maxX, 707)
        // Switcher only: no icons, the switcher at the strip's left.
        let switcherOnly = L.editorFrames(L.EditorSpec(size: NSSize(width: 735, height: 428), hasContext: false, switcherWidth: 160, iconCount: 0))
        XCTAssertEqual(switcherOnly.switcher, NSRect(x: 28, y: 343, width: 160, height: 26))
        XCTAssertTrue(switcherOnly.icons.isEmpty)
    }

    func testEditorTinySizesStayNonNegative() {
        for size in [NSSize(width: 390, height: 150), NSSize(width: 390, height: 100), NSSize(width: 650, height: 200)] {
            let f = L.editorFrames(L.EditorSpec(size: size, hasContext: true, switcherWidth: 200, iconCount: 3, footerTrailing: [regularCancel, regularOK]))
            for r in [f.surface, f.content] + [f.strip, f.switcher].compactMap({ $0 }) + f.icons { assertNonNegative(r) }
            XCTAssertGreaterThanOrEqual(f.surface.minY, 64)
        }
    }

    func testReadOnlyFooterHasSinglePrimaryAtTheRightMargin() {
        let f = L.editorFrames(L.EditorSpec(size: NSSize(width: 735, height: 428), hasContext: false, switcherWidth: 200, iconCount: 3,
                                            footerTrailing: [regularOK]))
        XCTAssertEqual(f.footerTrailing, [NSRect(x: 622, y: 14, width: 99, height: 32)])
        XCTAssertEqual(f.footerTrailing.first?.maxX, 735 - L.sideMargin + 6)
        XCTAssertTrue(f.footerLeading.isEmpty)
    }

    func testBitGridOrder() {
        let g = L.bitGrid(chipsLeft: 100, top: 300)
        XCTAssertEqual(g.chips.count, 64)
        XCTAssertEqual(g.rowLabels.count, 8)
        XCTAssertEqual(L.bitGridHeight, 188)
        XCTAssertEqual(L.bitChipsWidth, 236)
        XCTAssertEqual(g.chips[63], NSRect(x: 100, y: 280, width: 26, height: 20))
        XCTAssertEqual(g.chips[56], NSRect(x: 310, y: 280, width: 26, height: 20))
        XCTAssertEqual(g.chips[55], NSRect(x: 100, y: 256, width: 26, height: 20))
        XCTAssertEqual(g.chips[7], NSRect(x: 100, y: 112, width: 26, height: 20))
        XCTAssertEqual(g.chips[0], NSRect(x: 310, y: 112, width: 26, height: 20))
        XCTAssertEqual(g.rowLabels[0], NSRect(x: 68, y: 284, width: 24, height: 12))
        XCTAssertEqual(g.rowLabels[7], NSRect(x: 68, y: 116, width: 24, height: 12))
        for row in 0..<8 {
            for column in 1..<8 {
                let bit = 63 - (8 * row + column)
                XCTAssertEqual(g.chips[bit].minY, g.chips[bit + 1].minY)
                XCTAssertEqual(g.chips[bit].minX - g.chips[bit + 1].maxX, 4)
            }
        }
        XCTAssertEqual(g.chips.map(\.minY).min(), 300 - L.bitGridHeight)
    }

    func testOperatorFrames() {
        let frames = L.operatorFrames(count: 7, in: NSRect(x: 100, y: 50, width: 276, height: 22))
        XCTAssertEqual(frames.count, 7)
        XCTAssertEqual(frames.first, NSRect(x: 100, y: 50, width: 36, height: 22))
        XCTAssertEqual(frames.last, NSRect(x: 340, y: 50, width: 36, height: 22))
        XCTAssertTrue(L.operatorFrames(count: 0, in: .zero).isEmpty)
    }

    func testBitControlColumnFitsTheSevenOperators() {
        XCTAssertEqual(L.operatorRowWidth(count: 7), 276)
        XCTAssertEqual(L.operatorRowWidth(count: 0), 0)
        XCTAssertEqual(L.bitControlColumnWidth, 276)
        // A BIT sheet: the 188pt grid across the form, the operator row in the control column.
        let items: [L.Item] = [.wide(.custom(height: L.bitGridHeight)), .control(.custom(height: L.operatorButtonSize.height))]
        let f = L.frames(L.Spec(items: items, hasContext: true, footerLeading: [L.FooterItem(width: 60, height: 28)],
                                footerTrailing: [small, smallPrimary], currentSize: NSSize(width: 360, height: 300),
                                minimumControlWidth: L.bitControlColumnWidth))
        let operators = f.items[1].control
        XCTAssertGreaterThanOrEqual(operators.width, 276)
        XCTAssertEqual(L.operatorFrames(count: 7, in: operators).last?.maxX ?? .infinity, operators.minX + 276)
        XCTAssertLessThanOrEqual(operators.minX + 276, f.size.width - L.sideMargin)
        // Without the guarantee the default 200pt column would clip the row.
        let narrow = L.frames(L.Spec(items: items, hasContext: true, currentSize: NSSize(width: 360, height: 300)))
        XCTAssertLessThan(narrow.items[1].control.width, 276)
    }

    func testFieldTitleParsing() {
        var t = SAClaudeFormText.fieldTitle("Field: “id” – INT(11) NOT NULL ")
        XCTAssertEqual(t.column, "id"); XCTAssertEqual(t.details, "INT(11) NOT NULL")
        t = SAClaudeFormText.fieldTitle("“flags” – BIT(8) ")
        XCTAssertEqual(t.column, "flags"); XCTAssertEqual(t.details, "BIT(8)")
        t = SAClaudeFormText.fieldTitle("Field: “a – b” – TEXT")
        XCTAssertEqual(t.column, "a – b"); XCTAssertEqual(t.details, "TEXT")
        t = SAClaudeFormText.fieldTitle("“doc” – ")
        XCTAssertEqual(t.column, "doc"); XCTAssertNil(t.details)
        t = SAClaudeFormText.fieldTitle("“note”")
        XCTAssertEqual(t.column, "note"); XCTAssertNil(t.details)
        t = SAClaudeFormText.fieldTitle("plain")
        XCTAssertEqual(t.column, "plain"); XCTAssertNil(t.details)
    }

    /// The content grid's header joins the name and the type with U+2004, and the controller's label carries
    /// that header text: the title is the name alone.
    func testFieldTitleDropsTheHeadersType() {
        var t = SAClaudeFormText.fieldTitle("Field: “payload\u{2004}JSON” – JSON")
        XCTAssertEqual(t.column, "payload"); XCTAssertEqual(t.details, "JSON")
        t = SAClaudeFormText.fieldTitle("Field: “data\u{2004}BLOB” – BLOB(65535)")
        XCTAssertEqual(t.column, "data"); XCTAssertEqual(t.details, "BLOB(65535)")
        t = SAClaudeFormText.fieldTitle("“flags\u{2004}BIT”")
        XCTAssertEqual(t.column, "flags")
        // Ordinary spaces are part of the name.
        t = SAClaudeFormText.fieldTitle("Field: “my json” – JSON")
        XCTAssertEqual(t.column, "my json")
    }
}
