//
//  SAClaudeSidebarChromeTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeSidebarChromeTests: XCTestCase {

    /// Verifies a header draws muted ink inside its text frame and nothing outside it.
    func testHeaderDrawsInsideItsTextFrame() {
        let rowRect = NSRect(x: 0, y: 0, width: 260, height: 32)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 260, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
            context.cgContext.translateBy(x: 0, y: 32)
            context.cgContext.scaleBy(x: 1, y: -1)
            SAClaudeSidebarChrome.drawHeader("Tables and views", inRowRect: rowRect)
            NSGraphicsContext.restoreGraphicsState()
        }
        var inkColumns: [Int] = []
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                inkColumns.append(x)
                break
            }
        }
        XCTAssertFalse(inkColumns.isEmpty, "header drew nothing")
        XCTAssertGreaterThanOrEqual(inkColumns.min() ?? 0, 18)
    }
}

final class SAClaudeInfoRowTests: XCTestCase {

    /// Verifies "rows: ~18,402" becomes a capitalised label and a value.
    func testSplitsLabelAndValue() {
        let parts = SAClaudeInfoRow.split("rows: ~18,402")
        XCTAssertEqual(parts?.label, "Rows")
        XCTAssertEqual(parts?.value, "~18,402")
    }

    /// Verifies only the first ": " splits, so times and later colons stay in the value.
    func testSplitsOnlyAtFirstSeparator() {
        let parts = SAClaudeInfoRow.split("updated: 2026-10-10 14:02:00")
        XCTAssertEqual(parts?.label, "Updated")
        XCTAssertEqual(parts?.value, "2026-10-10 14:02:00")
        XCTAssertEqual(SAClaudeInfoRow.split("comment: a: b")?.value, "a: b")
    }

    /// Verifies a row with no ": " (another language, or a plain message) stays whole.
    func testRowWithoutSeparatorStaysPlain() {
        XCTAssertNil(SAClaudeInfoRow.split("no table selected"))
        XCTAssertNil(SAClaudeInfoRow.split(": value"))
        XCTAssertNil(SAClaudeInfoRow.split("label: "))
        let row = SAClaudeInfoRow.attributedRow(text: "no table selected", width: 240)
        XCTAssertEqual(row.string, "no table selected")
        XCTAssertEqual(row.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, SAClaudeStyle.textSecondary)
    }

    /// Verifies the label is muted, the value secondary and right-aligned on a tab stop.
    func testAttributedRowStyling() {
        let row = SAClaudeInfoRow.attributedRow(text: "engine: InnoDB", width: 240)
        XCTAssertEqual(row.string, "Engine\tInnoDB")
        XCTAssertEqual(row.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, SAClaudeStyle.textMuted)
        XCTAssertEqual(row.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor, SAClaudeStyle.textSecondary)
        XCTAssertEqual(row.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, SAClaudeStyle.infoFont)
        let paragraph = row.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.tabStops.first?.alignment, .right)
        XCTAssertEqual(paragraph?.tabStops.first?.location, 222)
    }

    /// Verifies a split row's label and value both start at the info indent.
    func testSplitRowIsIndented() {
        let row = SAClaudeInfoRow.attributedRow(text: "engine: InnoDB", width: 240)
        for index in [0, 7] {
            let paragraph = row.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertEqual(paragraph?.firstLineHeadIndent, 16, "at \(index)")
            XCTAssertEqual(paragraph?.headIndent, 16, "at \(index)")
        }
    }

    /// Verifies a row without ": " is indented the same way.
    func testPlainRowIsIndented() {
        let paragraph = SAClaudeInfoRow.attributedRow(text: "Multiple selection", width: 240)
            .attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.firstLineHeadIndent, 16)
        XCTAssertEqual(paragraph?.headIndent, 16)
    }

    /// Verifies a pane header is muted header text, indented like the rows, truncating at the tail.
    func testHeaderStyling() {
        let header = SAClaudeInfoRow.attributedHeader(text: "Table information")
        XCTAssertEqual(header.string, "Table information")
        XCTAssertEqual(header.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, SAClaudeStyle.headerFont)
        XCTAssertEqual(header.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, SAClaudeStyle.textMuted)
        let paragraph = header.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.firstLineHeadIndent, 16)
        XCTAssertEqual(paragraph?.headIndent, 16)
        XCTAssertEqual(paragraph?.lineBreakMode, .byTruncatingTail)
    }

    /// Verifies a column narrower than the padding gets a zero tab stop, not a negative one.
    func testNarrowColumnTabStop() {
        let paragraph = SAClaudeInfoRow.attributedRow(text: "engine: InnoDB", width: 4)
            .attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraph?.tabStops.first?.location, 0)
    }
}

final class SAClaudeBarButtonTests: XCTestCase {

    /// Verifies a bar button gets its glyph, no border, and the hover fill on hover only.
    func testBarButtonStylingAndHover() throws {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.appearance = NSAppearance(named: .darkAqua)
        SAClaudeSidebarChrome.styleBarButton(button, glyph: .refresh)

        XCTAssertFalse(button.isBordered)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(button.image?.accessibilityDescription, "Refresh table list")
        XCTAssertEqual(button.layer?.cornerRadius, SAClaudeStyle.barButtonRadius)
        XCTAssertNil(button.layer?.backgroundColor)

        let highlighter = try XCTUnwrap(SAClaudeHoverHighlighter.highlighter(for: button))
        highlighter.setHovered(true)
        let fill = try XCTUnwrap(button.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) })
        XCTAssertEqual(fill.redComponent, CGFloat(0x1E) / 255, accuracy: 0.01)
        highlighter.setHovered(false)
        XCTAssertNil(button.layer?.backgroundColor)
    }

    /// Verifies a non-flipped pane gets one 1pt divider just above the bar that tracks its width, added once.
    func testBarDividerSitsAboveTheBarInANonFlippedPane() {
        let pane = NSView(frame: NSRect(x: 0, y: 0, width: 214, height: 549))
        let bar = NSButton(frame: NSRect(x: 0, y: 0, width: 25, height: 25))
        pane.addSubview(bar)
        SAClaudeSidebarChrome.addBarDivider(to: pane, above: bar)
        SAClaudeSidebarChrome.addBarDivider(to: pane, above: bar)
        let lines = pane.subviews.compactMap { $0 as? SAClaudeDividerLine }
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.frame, NSRect(x: 0, y: 25, width: 214, height: 1))
        XCTAssertEqual(lines.first?.autoresizingMask, [.width, .maxYMargin])
    }

    /// Verifies a flipped pane gets the divider on the bar's visual top edge, pinned to the bottom.
    func testBarDividerSitsAboveTheBarInAFlippedPane() {
        let pane = SAFlippedTestView(frame: NSRect(x: 0, y: 0, width: 214, height: 549))
        let bar = NSButton(frame: NSRect(x: 0, y: 524, width: 25, height: 25))
        pane.addSubview(bar)
        SAClaudeSidebarChrome.addBarDivider(to: pane, above: bar)
        SAClaudeSidebarChrome.addBarDivider(to: pane, above: bar)
        let lines = pane.subviews.compactMap { $0 as? SAClaudeDividerLine }
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.frame, NSRect(x: 0, y: 523, width: 214, height: 1))
        XCTAssertEqual(lines.first?.autoresizingMask, [.width, .minYMargin])
    }

    /// Verifies the divider line never takes clicks from the views under it.
    func testDividerLineIgnoresClicks() {
        let line = SAClaudeDividerLine(frame: NSRect(x: 0, y: 0, width: 100, height: 1))
        XCTAssertNil(line.hitTest(NSPoint(x: 10, y: 0.5)))
    }

    /// Verifies a disabled bar button gets no hover fill.
    func testDisabledButtonGetsNoHoverFill() throws {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.appearance = NSAppearance(named: .darkAqua)
        SAClaudeSidebarChrome.styleBarButton(button, glyph: .add)
        button.isEnabled = false
        let highlighter = try XCTUnwrap(SAClaudeHoverHighlighter.highlighter(for: button))
        highlighter.setHovered(true)
        XCTAssertNil(button.layer?.backgroundColor)
    }

    /// Verifies the hover fill is the light token under a light appearance.
    func testLightHoverFill() throws {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.appearance = NSAppearance(named: .aqua)
        SAClaudeSidebarChrome.styleBarButton(button, glyph: .add)
        try XCTUnwrap(SAClaudeHoverHighlighter.highlighter(for: button)).setHovered(true)
        assertFill(of: button, is: 0xEAE9E4)
    }

    /// Verifies a hovered button re-resolves its fill when its appearance changes.
    func testHoverFillFollowsAppearanceChange() throws {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        container.appearance = NSAppearance(named: .darkAqua)
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        container.addSubview(button)
        SAClaudeSidebarChrome.styleBarButton(button, glyph: .add)
        try XCTUnwrap(SAClaudeHoverHighlighter.highlighter(for: button)).setHovered(true)
        assertFill(of: button, is: 0x1E1E1D)
        container.appearance = NSAppearance(named: .aqua)
        assertFill(of: button, is: 0xEAE9E4)
    }

    /// Verifies the hover tracking stays active while a sheet holds key status.
    func testHoverTrackingIsActiveInActiveApp() throws {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        SAClaudeSidebarChrome.styleBarButton(button, glyph: .add)
        let area = try XCTUnwrap(button.trackingAreas.first { $0.owner is SAClaudeHoverHighlighter })
        XCTAssertTrue(area.options.contains(.activeInActiveApp))
        XCTAssertFalse(area.options.contains(.activeInKeyWindow))
    }

    /// A tracking area sends its owner `mouseEntered:` / `mouseExited:`. The
    /// highlighter is a plain NSObject, so a Swift `mouseEntered(with:)` would
    /// export as `mouseEnteredWith:` and the first hover crashed the app with an
    /// unrecognized selector. Drives the hover through those exact selectors.
    func testHighlighterAnswersTheTrackingAreaSelectors() throws {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.appearance = NSAppearance(named: .darkAqua)
        SAClaudeSidebarChrome.styleBarButton(button, glyph: .add)
        let owner = try XCTUnwrap(button.trackingAreas.first { $0.owner is SAClaudeHoverHighlighter }?.owner as? NSObject)
        let entered = NSSelectorFromString("mouseEntered:")
        let exited = NSSelectorFromString("mouseExited:")
        XCTAssertTrue(owner.responds(to: entered))
        XCTAssertTrue(owner.responds(to: exited))

        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                         windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        owner.perform(entered, with: event)
        assertFill(of: button, is: 0x1E1E1D)
        owner.perform(exited, with: event)
        XCTAssertNil(button.layer?.backgroundColor)
    }

    private func assertFill(of view: NSView, is hex: UInt32, file: StaticString = #filePath, line: UInt = #line) {
        guard let fill = view.layer?.backgroundColor.flatMap({ NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }) else {
            return XCTFail("no hover fill", file: file, line: line)
        }
        XCTAssertEqual(fill.redComponent, CGFloat((hex >> 16) & 0xFF) / 255, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(fill.greenComponent, CGFloat((hex >> 8) & 0xFF) / 255, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(fill.blueComponent, CGFloat(hex & 0xFF) / 255, accuracy: 0.01, file: file, line: line)
    }

    /// Verifies a pull-down menu button shows the glyph through its first (title) item.
    func testPullDownShowsGlyphOnItsFirstItem() {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 35, height: 28), pullsDown: true)
        popup.addItem(withTitle: "")
        popup.addItem(withTitle: "Rename Table...")
        SAClaudeSidebarChrome.styleBarButton(popup, glyph: .actions)
        XCTAssertEqual(popup.item(at: 0)?.image?.accessibilityDescription, "Table actions")
        XCTAssertNil(popup.item(at: 1)?.image)
    }
}

/// A flipped container, for checking placement in flipped panes.
private final class SAFlippedTestView: NSView {
    override var isFlipped: Bool { true }
}

final class SAClaudeTablesListCellTests: XCTestCase {

    private func styledCell(selected: Bool, enabled: Bool) -> NSTextFieldCell {
        let cell = NSTextFieldCell(textCell: "orders")
        cell.backgroundStyle = .emphasized
        SAClaudeSidebarChrome.styleTablesListCell(cell, selected: selected, enabled: enabled)
        return cell
    }

    /// Verifies an unselected row is secondary text in the row font on a normal background.
    func testUnselectedRow() {
        let cell = styledCell(selected: false, enabled: true)
        XCTAssertEqual(cell.textColor, SAClaudeStyle.textSecondary)
        XCTAssertEqual(cell.font, SAClaudeStyle.rowFont)
        XCTAssertEqual(cell.backgroundStyle, .normal)
    }

    /// Verifies a selected row is primary text and never switches to emphasized (white) text.
    func testSelectedRow() {
        let cell = styledCell(selected: true, enabled: true)
        XCTAssertEqual(cell.textColor, SAClaudeStyle.textPrimary)
        XCTAssertEqual(cell.backgroundStyle, .normal)
    }

    /// Verifies a disabled list is muted, selected or not.
    func testDisabledRow() {
        XCTAssertEqual(styledCell(selected: false, enabled: false).textColor, SAClaudeStyle.textMuted)
        XCTAssertEqual(styledCell(selected: true, enabled: false).textColor, SAClaudeStyle.textMuted)
    }

    /// Verifies the cell never stays highlighted (NSTableView highlights the
    /// selected row's cell before willDisplayCell), selected or not.
    func testStylingClearsHighlight() {
        for selected in [true, false] {
            let cell = NSTextFieldCell(textCell: "orders")
            cell.isHighlighted = true
            SAClaudeSidebarChrome.styleTablesListCell(cell, selected: selected, enabled: true)
            XCTAssertFalse(cell.isHighlighted, "selected: \(selected)")
        }
    }

    /// Verifies a styled cell that the table had highlighted draws no box of
    /// its own behind the text: the pixel just after the name is still the
    /// selection pill's colour (#343434 dark), not the cell's highlight (#464646).
    func testHighlightedCellDrawsNoBoxOverTheSelection() throws {
        let size = NSSize(width: 200, height: 24)
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.appearance = NSAppearance(named: .darkAqua)
        let cell = NSTextFieldCell(textCell: "orders")
        cell.isBordered = false
        cell.drawsBackground = false
        cell.isHighlighted = true
        cell.controlView = view
        SAClaudeSidebarChrome.styleTablesListCell(cell, selected: true, enabled: true)

        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            SAClaudeStyle.selection.setFill()
            NSRect(origin: .zero, size: size).fill()
            cell.draw(withFrame: NSRect(origin: .zero, size: size), in: view)
            NSGraphicsContext.restoreGraphicsState()
        }
        let textEnd = Int(ceil(cell.attributedStringValue.size().width)) + Int(SAClaudeStyle.cellTextInset)
        let color = try XCTUnwrap(rep.colorAt(x: textEnd + 3, y: Int(size.height) / 2)?.usingColorSpace(.sRGB))
        XCTAssertEqual(color.redComponent, CGFloat(0x34) / 255, accuracy: 0.01)
        XCTAssertEqual(color.greenComponent, CGFloat(0x34) / 255, accuracy: 0.01)
        XCTAssertEqual(color.blueComponent, CGFloat(0x34) / 255, accuracy: 0.01)
    }
}

final class SAClaudeSidebarPaneTests: XCTestCase {

    /// Verifies the sidebar split view gets a 1pt (thin) divider instead of the 9pt thick one.
    func testSidebarSplitViewIsThin() {
        let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: 214, height: 524))
        split.dividerStyle = .thick
        SAClaudeSidebarChrome.styleSidebarSplitView(split)
        XCTAssertEqual(split.dividerStyle, .thin)
        XCTAssertEqual(split.dividerThickness, 1)
    }

    /// Verifies the pane gets one background view, bottom-most, filling and tracking it.
    func testSidebarBackgroundIsInsertedOnceAtTheBottom() {
        let pane = NSView(frame: NSRect(x: 0, y: 0, width: 214, height: 549))
        pane.addSubview(NSButton(frame: NSRect(x: 0, y: 0, width: 25, height: 25)))
        SAClaudeSidebarChrome.addSidebarBackground(to: pane)
        SAClaudeSidebarChrome.addSidebarBackground(to: pane)
        XCTAssertEqual(pane.subviews.filter { $0 is SAClaudeSidebarBackgroundView }.count, 1)
        let background = pane.subviews.first
        XCTAssertTrue(background is SAClaudeSidebarBackgroundView)
        XCTAssertEqual(background?.frame, pane.bounds)
        XCTAssertEqual(background?.autoresizingMask, [.width, .height])
        XCTAssertNil(background?.hitTest(NSPoint(x: 100, y: 300)))
    }

    /// Verifies the background paints the sidebar colour for the current appearance.
    func testSidebarBackgroundPaintsTheSidebarColour() throws {
        let view = SAClaudeSidebarBackgroundView(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
        view.appearance = NSAppearance(named: .darkAqua)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let color = try XCTUnwrap(rep.colorAt(x: 1, y: 1)?.usingColorSpace(.sRGB))
        XCTAssertEqual(color.redComponent, CGFloat(0x11) / 255, accuracy: 0.02)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
    }
}
