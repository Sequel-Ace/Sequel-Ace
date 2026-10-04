//
//  SAImageRenderer.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import AppKit

/// Renders `NSImageRep`s into bitmap-backed PNG data.
///
/// Replaces the deprecated `lockFocus` + `initWithFocusedViewRect:` snapshot
/// pattern: the rep is drawn into an explicit bitmap graphics context instead
/// of a focused NSImage. Used for image drag conversions where the dragged
/// representation (e.g. PICT) has no direct bitmap form.
@objc final class SAImageRenderer: NSObject {

    /// PNG data for `imageRep` rendered at its natural size, or nil when the
    /// rep has no drawable size or fails to draw.
    @objc(pngDataForImageRep:)
    static func pngData(for imageRep: NSImageRep) -> Data? {
        let size = imageRep.size
        guard size.width >= 1, size.height >= 1 else { return nil }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(size.width)),
            pixelsHigh: Int(ceil(size.height)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let drawn = imageRep.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        guard drawn else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
