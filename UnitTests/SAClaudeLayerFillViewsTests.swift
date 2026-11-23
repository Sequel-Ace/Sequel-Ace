//
//  SAClaudeLayerFillViewsTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeLayerFillViewsTests: XCTestCase {

    private static let dark = NSAppearance(named: .darkAqua)!
    private static let light = NSAppearance(named: .aqua)!

    private func srgbComponents(_ colour: CGColor?) throws -> [CGFloat] {
        let converted = try XCTUnwrap(colour?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil))
        return try XCTUnwrap(converted.components)
    }

    private func assertColour(_ colour: CGColor?, is hex: UInt32, alpha: CGFloat = 1,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let c = try srgbComponents(colour)
        XCTAssertEqual(c[0], CGFloat((hex >> 16) & 0xFF) / 255, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(c[1], CGFloat((hex >> 8) & 0xFF) / 255, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(c[2], CGFloat(hex & 0xFF) / 255, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(c[3], alpha, accuracy: 0.002, file: file, line: line)
    }

    // MARK: - Flat fill

    /// Verifies the fill is a layer colour with no drawn picture behind it.
    func testFlatFillIsALayerColourNotAPicture() throws {
        let view = SAClaudeFlatFillView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.fillColour = SAClaudeStyle.srgb(0x123456)
        view.cornerRadius = 6
        XCTAssertTrue(view.wantsUpdateLayer)
        view.displayIfNeeded()
        let layer = try XCTUnwrap(view.layer)
        XCTAssertNil(layer.contents)
        try assertColour(layer.backgroundColor, is: 0x123456)
        XCTAssertEqual(layer.cornerRadius, 6)
    }

    /// Verifies a dynamic colour resolves for the view's own appearance, and again when that appearance changes.
    func testFlatFillResolvesADynamicColourForItsAppearance() throws {
        let view = SAClaudeFlatFillView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        view.fillColour = SAClaudeStyle.sidebarBackground
        view.appearance = Self.dark
        view.displayIfNeeded()
        try assertColour(view.layer?.backgroundColor, is: 0x111111)
        view.appearance = Self.light
        view.displayIfNeeded()
        try assertColour(view.layer?.backgroundColor, is: 0xF6F6F4)
    }

    /// Verifies a new colour reaches the layer at the next display.
    func testFlatFillTakesANewColour() throws {
        let view = SAClaudeFlatFillView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        view.fillColour = SAClaudeStyle.srgb(0x112233)
        view.displayIfNeeded()
        view.fillColour = SAClaudeStyle.srgb(0x445566)
        view.displayIfNeeded()
        try assertColour(view.layer?.backgroundColor, is: 0x445566)
    }

    /// Verifies the flat views built on it keep ignoring the mouse.
    func testFlatFillIgnoresClicks() {
        let view = SAClaudeFlatFillView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertNil(view.hitTest(NSPoint(x: 5, y: 5)))
    }

    /// Verifies the divider line keeps its colour and override as a layer colour.
    func testDividerLineIsALayerColour() throws {
        let line = SAClaudeDividerLine(frame: NSRect(x: 0, y: 0, width: 100, height: 1))
        line.appearance = Self.dark
        line.displayIfNeeded()
        try assertColour(line.layer?.backgroundColor, is: 0x202020)
        line.colourOverride = SAClaudeStyle.srgb(0xABCDEF)
        line.displayIfNeeded()
        try assertColour(line.layer?.backgroundColor, is: 0xABCDEF)
        line.colourOverride = nil
        line.displayIfNeeded()
        try assertColour(line.layer?.backgroundColor, is: 0x202020)
        XCTAssertNil(line.layer?.contents)
    }

    // MARK: - Outlined fill

    /// Verifies the line is the layer's 1pt border following the path's outside edge, and the fill sits half a
    /// line inside, rounded like the path.
    func testOutlinedFillGeometry() throws {
        let view = SAClaudeOutlinedFillView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        view.fill = SAClaudeStyle.srgb(0x101010)
        view.stroke = SAClaudeStyle.srgb(0x808080)
        view.radius = 7
        view.displayIfNeeded()
        let layer = try XCTUnwrap(view.layer)
        XCTAssertNil(layer.contents)
        XCTAssertEqual(layer.borderWidth, 1)
        XCTAssertEqual(layer.cornerRadius, 7.5)
        try assertColour(layer.borderColor, is: 0x808080)
        let fill = try XCTUnwrap(view.subviews.first as? SAClaudeFlatFillView)
        XCTAssertEqual(fill.frame, NSRect(x: 0.5, y: 0.5, width: 199, height: 39))
        XCTAssertEqual(fill.cornerRadius, 7)
        fill.displayIfNeeded()
        try assertColour(fill.layer?.backgroundColor, is: 0x101010)

        view.setFrameSize(NSSize(width: 120, height: 30))
        XCTAssertEqual(fill.frame, NSRect(x: 0.5, y: 0.5, width: 119, height: 29))
        view.setFrameSize(.zero)
        XCTAssertEqual(fill.frame, .zero)
    }

    /// Verifies the fill stays the bottom subview, under views added later.
    func testOutlinedFillStaysUnderLaterSubviews() {
        let view = SAClaudeOutlinedFillView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        let field = NSTextField(frame: NSRect(x: 8, y: 6, width: 84, height: 18))
        view.addSubview(field)
        XCTAssertTrue(view.subviews.first is SAClaudeFlatFillView)
        XCTAssertTrue(view.subviews.last === field)
    }

    /// Verifies the layers paint what the drawn path did, pixel for pixel away from the rounded corners, with
    /// translucent colours over an opaque backdrop: the line's outer half over the backdrop, its inner half over
    /// the fill. (At the corners only the antialiasing of the arcs differs.)
    func testOutlinedFillMatchesTheDrawnPathAlongItsEdges() throws {
        let size = NSSize(width: 60, height: 30), radius: CGFloat = 7, scale: CGFloat = 2
        let backdrop = SAClaudeStyle.srgb(0xF0EEE6)
        let fill = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 0.35)
        let stroke = NSColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 0.5)

        func bitmap() -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
            return rep.retagging(with: .sRGB)!
        }

        // What the views drew before: the path filled, then stroked 1pt, over the backdrop.
        let drawn = bitmap()
        drawn.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: drawn)
        backdrop.setFill()
        NSRect(origin: .zero, size: size).fill()
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // The layers, rendered over the same backdrop.
        let host = SAClaudeFlatFillView(frame: NSRect(origin: .zero, size: size))
        host.fillColour = backdrop
        let view = SAClaudeOutlinedFillView(frame: host.bounds)
        view.fill = fill
        view.stroke = stroke
        view.radius = radius
        host.addSubview(view)
        host.layoutSubtreeIfNeeded()
        let layered = bitmap()
        layered.size = size
        host.cacheDisplay(in: host.bounds, to: layered)

        let corner = Int((radius + 1) * scale)
        let w = layered.pixelsWide, h = layered.pixelsHigh
        var compared = 0
        for y in 0..<h {
            for x in 0..<w {
                let inCornerSquare = (x < corner || x >= w - corner) && (y < corner || y >= h - corner)
                guard !inCornerSquare else { continue }
                let a = try XCTUnwrap(drawn.colorAt(x: x, y: y)), b = try XCTUnwrap(layered.colorAt(x: x, y: y))
                for (ca, cb) in zip([a.redComponent, a.greenComponent, a.blueComponent, a.alphaComponent],
                                    [b.redComponent, b.greenComponent, b.blueComponent, b.alphaComponent]) {
                    // One 8-bit step: drawing quantises the line-over-fill pixel once more than compositing does.
                    XCTAssertEqual(ca, cb, accuracy: 1.5 / 255, "pixel \(x),\(y)")
                }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, w * h / 2)
        // The edge pixels really are the two different blends (not vacuously equal).
        let outer = try XCTUnwrap(layered.colorAt(x: w / 2, y: 0)), inner = try XCTUnwrap(layered.colorAt(x: w / 2, y: 1))
        XCTAssertNotEqual(outer.redComponent, inner.redComponent, accuracy: 2 / 255)
    }
}
