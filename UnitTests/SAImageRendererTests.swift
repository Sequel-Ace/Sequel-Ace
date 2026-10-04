//
//  SAImageRendererTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import AppKit
import XCTest

/// Pins the bitmap-render path that replaced the deprecated
/// `lockFocus` + `initWithFocusedViewRect:` snapshot in SPImageView's image
/// drag conversion.
///
/// A note on fixtures: the drag path this serves converts PICT
/// representations, but PICT *encoders* were removed from macOS long ago
/// (QuickDraw), so a genuine PICT blob cannot be synthesized here. The tests
/// exercise the identical rendering code through a bitmap-backed rep —
/// `NSPICTImageRep` drawing itself is AppKit's responsibility either way.
final class SAImageRendererTests: XCTestCase {

    /// A solid-colour source rep drawn through the same context machinery.
    private func makeSolidRep(width: Int, height: Int, color: NSColor) -> NSImageRep {
        let source = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: source)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return source
    }

    func testRendersRepToPNGWithMatchingSizeAndContent() throws {
        let source = makeSolidRep(width: 24, height: 16, color: .red)

        let pngData = try XCTUnwrap(SAImageRenderer.pngData(for: source))

        // PNG magic bytes
        XCTAssertEqual([UInt8](pngData.prefix(4)), [0x89, 0x50, 0x4E, 0x47])

        let decoded = try XCTUnwrap(NSBitmapImageRep(data: pngData))
        XCTAssertEqual(decoded.pixelsWide, 24)
        XCTAssertEqual(decoded.pixelsHigh, 16)

        let center = try XCTUnwrap(decoded.colorAt(x: 12, y: 8)?.usingColorSpace(.genericRGB))
        XCTAssertEqual(center.redComponent, 1.0, accuracy: 0.05)
        XCTAssertEqual(center.greenComponent, 0.0, accuracy: 0.05)
        XCTAssertEqual(center.blueComponent, 0.0, accuracy: 0.05)
        XCTAssertEqual(center.alphaComponent, 1.0, accuracy: 0.05)
    }

    func testNonIntegralSizeRoundsUp() throws {
        let source = makeSolidRep(width: 10, height: 10, color: .blue)
        source.size = NSSize(width: 10.4, height: 10.6)

        let pngData = try XCTUnwrap(SAImageRenderer.pngData(for: source))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: pngData))

        XCTAssertEqual(decoded.pixelsWide, 11)
        XCTAssertEqual(decoded.pixelsHigh, 11)
    }

    func testZeroSizedRepReturnsNil() {
        XCTAssertNil(SAImageRenderer.pngData(for: NSImageRep()))
    }
}
