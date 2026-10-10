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
        XCTAssertEqual(paragraph?.tabStops.first?.location, 230)
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

    /// Verifies the bar gets one 1pt divider along its top edge that tracks its width, added once.
    func testTopDividerIsAddedOnce() {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: 215, height: 25))
        SAClaudeSidebarChrome.addTopDivider(to: bar)
        SAClaudeSidebarChrome.addTopDivider(to: bar)
        let lines = bar.subviews.compactMap { $0 as? SAClaudeDividerLine }
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.frame, NSRect(x: 0, y: 24, width: 215, height: 1))
        XCTAssertEqual(lines.first?.autoresizingMask, [.width, .minYMargin])
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
