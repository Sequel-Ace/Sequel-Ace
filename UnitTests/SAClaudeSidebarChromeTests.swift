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
