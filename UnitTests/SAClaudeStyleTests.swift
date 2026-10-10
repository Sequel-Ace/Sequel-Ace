//
//  SAClaudeStyleTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeStyleTests: XCTestCase {

    /// Resolves a colour under an appearance to 0xRRGGBB in sRGB.
    private func hex(_ color: NSColor, _ name: NSAppearance.Name) -> UInt32 {
        var value: UInt32 = 0
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            value = UInt32((c.redComponent * 255).rounded()) << 16
                | UInt32((c.greenComponent * 255).rounded()) << 8
                | UInt32((c.blueComponent * 255).rounded())
        }
        return value
    }

    /// Verifies every colour resolves to the spec's exact value in dark and light.
    func testColoursMatchTheSpec() {
        let expected: [(NSColor, UInt32, UInt32, String)] = [
            (SAClaudeStyle.sidebarBackground, 0x111111, 0xF6F6F4, "sidebarBackground"),
            (SAClaudeStyle.selection, 0x343434, 0xE4E3DD, "selection"),
            (SAClaudeStyle.hoverFill, 0x1E1E1D, 0xEAE9E4, "hoverFill"),
            (SAClaudeStyle.divider, 0x202020, 0xE7E6E1, "divider"),
            (SAClaudeStyle.textPrimary, 0xF0EFEC, 0x0B0B0B, "textPrimary"),
            (SAClaudeStyle.textSecondary, 0xC3C2B7, 0x52514E, "textSecondary"),
            (SAClaudeStyle.textMuted, 0x898781, 0x7B7974, "textMuted"),
            (SAClaudeStyle.tintDatabase, 0xD97757, 0xC6613F, "tintDatabase"),
            (SAClaudeStyle.tintTable, 0x6DA7EC, 0x2A78D6, "tintTable"),
            (SAClaudeStyle.tintView, 0xA096EB, 0x7161E0, "tintView"),
            (SAClaudeStyle.tintProcedure, 0xEC835A, 0xC25124, "tintProcedure"),
            (SAClaudeStyle.tintFunction, 0x55BF50, 0x008300, "tintFunction"),
        ]
        for (color, dark, light, name) in expected {
            XCTAssertEqual(hex(color, .darkAqua), dark, "\(name) dark")
            XCTAssertEqual(hex(color, .aqua), light, "\(name) light")
        }
    }

    /// Verifies the fonts are SF Pro (the system font) at the spec's sizes.
    func testFontsAreSystemFontAtSpecSizes() {
        XCTAssertEqual(SAClaudeStyle.rowFont, NSFont.systemFont(ofSize: 14))
        XCTAssertEqual(SAClaudeStyle.headerFont, NSFont.systemFont(ofSize: 13))
        XCTAssertEqual(SAClaudeStyle.infoFont, NSFont.systemFont(ofSize: 12))
    }

    /// Verifies the padded icon canvas puts the icon 18pt in and the name 44pt in,
    /// given the cell's 3pt image inset and the text cell's 2pt inset.
    func testIconCanvasPlacesIconAndText() {
        let iconX = SAClaudeStyle.cellImageInset + SAClaudeStyle.sidebarIconLeading
        XCTAssertEqual(iconX, SAClaudeStyle.pillInset + SAClaudeStyle.rowContentPadding)
        XCTAssertEqual(iconX, 18)
        let textX = SAClaudeStyle.cellImageInset + SAClaudeStyle.sidebarIconCanvasWidth + SAClaudeStyle.cellTextInset
        XCTAssertEqual(textX, iconX + SAClaudeStyle.iconSize + SAClaudeStyle.iconTextGap)
        XCTAssertEqual(textX, 44)
    }

    /// Verifies info rows start 18pt in like the names (16pt indent plus the
    /// text cell's 2pt inset) and keep the list's 18pt clear on the right.
    func testInfoRowMetrics() {
        XCTAssertEqual(SAClaudeStyle.infoRowLeadingIndent + SAClaudeStyle.cellTextInset, SAClaudeStyle.pillInset + SAClaudeStyle.rowContentPadding)
        XCTAssertEqual(SAClaudeStyle.infoRowLeadingIndent, 16)
        XCTAssertEqual(SAClaudeStyle.infoRowTrailingPadding, SAClaudeStyle.sidebarTrailingPadding)
        XCTAssertEqual(SAClaudeStyle.infoRowTrailingPadding, 18)
    }

    /// Verifies the name cell is centred vertically and stops short of the pill's right padding.
    func testCellFrameIsCentredAndTrimmed() {
        let frame = SAClaudeSidebarGeometry.cellFrame(in: NSRect(x: 0, y: 64, width: 260, height: 32), textHeight: 18)
        XCTAssertEqual(frame, NSRect(x: 0, y: 71, width: 242, height: 18))
    }

    /// Verifies a row narrower than the paddings yields no negative sizes.
    func testCellFrameClampsInNarrowRows() {
        let frame = SAClaudeSidebarGeometry.cellFrame(in: NSRect(x: 0, y: 0, width: 10, height: 32), textHeight: 40)
        XCTAssertEqual(frame.width, 0)
        XCTAssertEqual(frame.height, 32)
        XCTAssertEqual(frame.minY, 0)
    }

    /// Verifies the header text sits 6pt above the row bottom, aligned with the names' icons.
    func testHeaderTextFrame() {
        let frame = SAClaudeSidebarGeometry.headerTextFrame(in: NSRect(x: 0, y: 0, width: 260, height: 32), textHeight: 16)
        XCTAssertEqual(frame, NSRect(x: 18, y: 10, width: 224, height: 16))
        let narrow = SAClaudeSidebarGeometry.headerTextFrame(in: NSRect(x: 0, y: 0, width: 20, height: 32), textHeight: 16)
        XCTAssertEqual(narrow.width, 0)
    }

    private func rowRect(_ row: Int) -> NSRect { NSRect(x: 0, y: CGFloat(row) * 32, width: 260, height: 32) }

    /// Verifies one selected row gets one pill inset 8pt on both sides.
    func testSingleRowPill() {
        let rects = SAClaudeSelectionLayout.pillRects(selectedRows: [3], rowRect: rowRect, inset: 8)
        XCTAssertEqual(rects, [NSRect(x: 8, y: 96, width: 244, height: 32)])
    }

    /// Verifies adjacent rows merge into one pill and separate runs stay separate.
    func testAdjacentRowsMergeAndRunsSplit() {
        XCTAssertEqual(SAClaudeSelectionLayout.pillRects(selectedRows: [2, 3], rowRect: rowRect, inset: 8),
                       [NSRect(x: 8, y: 64, width: 244, height: 64)])
        XCTAssertEqual(SAClaudeSelectionLayout.pillRects(selectedRows: [1, 3], rowRect: rowRect, inset: 8),
                       [NSRect(x: 8, y: 32, width: 244, height: 32), NSRect(x: 8, y: 96, width: 244, height: 32)])
    }

    /// Verifies index order does not matter.
    func testUnsortedSelectionMergesRuns() {
        XCTAssertEqual(SAClaudeSelectionLayout.pillRects(selectedRows: [5, 3, 4, 1], rowRect: rowRect, inset: 8),
                       [NSRect(x: 8, y: 32, width: 244, height: 32), NSRect(x: 8, y: 96, width: 244, height: 96)])
    }

    /// Verifies no selection draws nothing.
    func testEmptySelectionHasNoPills() {
        XCTAssertEqual(SAClaudeSelectionLayout.pillRects(selectedRows: [], rowRect: rowRect, inset: 8), [])
    }

    /// Verifies a list narrower than both insets yields zero-width pills, not negative ones.
    func testPillRectsClampInNarrowList() {
        let rects = SAClaudeSelectionLayout.pillRects(selectedRows: [0], rowRect: { _ in NSRect(x: 0, y: 0, width: 10, height: 32) }, inset: 8)
        XCTAssertEqual(rects.first?.width, 0)
    }
}
