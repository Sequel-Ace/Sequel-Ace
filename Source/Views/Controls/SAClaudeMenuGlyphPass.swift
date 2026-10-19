//
//  SAClaudeMenuGlyphPass.swift
//  Sequel Ace
//
//  Gives the native menus their Claude glyphs just before they open: on
//  `NSMenu.didBeginTrackingNotification` (any menu) it runs
//  `SAClaudeMenuGlyphs.apply` on the menu being opened, with 15pt regular
//  outline SF Symbols (templates, which the menu tints). That notification
//  arrives before AppKit lays the menu out and creates its window, so the
//  glyphs are there when it first shows and the menu doesn't change width. It
//  covers every way a menu opens: a right-click on a view's `menu` or
//  `menuForEvent:` (which, on macOS 27, doesn't go through
//  `+popUpContextMenu:withEvent:forView:`), ⌥⎋'s `popUpContextMenu`, a
//  pull-down's click, and `popUp(positioning:at:in:)`. Menus that code
//  rebuilds before each opening (the grids', the query editor's, the tab
//  chips') are filled again each time. Only menus opened in a main document
//  window (key, no sheet attached) or in one of the utility windows and its
//  sheets (User Manager, Process List, Server Variables, the two favourites
//  managers, Navigator, Bundle Editor, Advanced Filter: by their owner) are
//  filled: other sheets, panels, Settings and the Console keep their menus as
//  they are, and the main menu bar's menus are left to macOS
//  (`SAClaudeMenuGlyphs.shouldApply`). App target only.
//

import AppKit

@objc(SAClaudeMenuGlyphPass) final class SAClaudeMenuGlyphPass: NSObject {

    private static var observer: NSObjectProtocol?
    private static var images: [String: NSImage] = [:]

    /// Starts filling menus as they open (once; call at launch).
    @objc static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            // Posted on the main thread as the menu starts tracking; it has to be filled now, before it lays out.
            guard Thread.isMainThread, let menu = note.object as? NSMenu else { return }
            let window = openingWindow()
            guard SAClaudeMenuGlyphs.shouldApply(isMainMenu: SAClaudeMenuGlyphs.isInMainMenu(menu, mainMenu: NSApp.mainMenu),
                                                 isMainDocumentWindow: window.map(isMainDocumentWindow) ?? false,
                                                 hasAttachedSheet: window?.attachedSheet != nil,
                                                 ownerClasses: window.map(ownerClasses) ?? []) else { return }
            SAClaudeMenuGlyphs.apply(to: menu, imageFor: image(named:))
        }
    }

    /// The window a menu opens in: the key window (a menu opens from it, and it stays key while the menu tracks);
    /// without one (a right-click in a window of the inactive app), the window of the event that opened it.
    static var openingWindow: () -> NSWindow? = { NSApp.keyWindow ?? NSApp.currentEvent?.window }

    /// A database window: run by `SPWindowController` (the Bundle Editor and the field editor sheet are `SPWindow`s
    /// too, but not this) and not itself a sheet.
    private static func isMainDocumentWindow(_ window: NSWindow) -> Bool {
        window.windowController is SPWindowController && window.sheetParent == nil
    }

    /// The class names of the controllers and delegates of `window` and of the windows it is a sheet of (KVO's runtime
    /// subclasses skipped), for the utility windows' gate.
    private static func ownerClasses(of window: NSWindow) -> [String] {
        var names: [String] = []
        var current: NSWindow? = window
        while let w = current {
            for owner in [w.windowController as AnyObject?, w.delegate as AnyObject?].compactMap({ $0 }) {
                names.append(NSStringFromClass(SAClaudeSheetStyler.visibleClass(of: owner)))
            }
            current = w.sheetParent
        }
        return names
    }

    // MARK: Uniform glyphs

    /// The box a uniform menu glyph is drawn in, and the height every glyph's ink takes inside it: the size macOS 27 draws
    /// the pass's circle glyphs at in a menu (it redraws symbol images at its own size, so a tall symbol such as
    /// doc.on.doc shows taller than a circle beside it).
    static let uniformCanvas: CGFloat = 14
    static let uniformInkHeight: CGFloat = 12
    private static var uniformImages: [String: NSImage] = [:]

    /// A menu glyph of one size and one optical weight with the others made here: the symbol drawn (not a symbol image, so
    /// the menu keeps its size) with its ink `uniformInkHeight` tall (narrower than the box), centred in a `uniformCanvas`
    /// square; a symbol that has to be drawn smaller than a circle is drawn heavier, so its strokes match. A template;
    /// cached.
    @objc(uniformImageNamed:) static func uniformImage(named name: String) -> NSImage? {
        if let image = uniformImages[name] { return image }
        let reference: CGFloat = 15
        guard let probe = symbol(name, pointSize: reference, weight: .regular), let probeInk = inkRect(of: probe), probeInk.height > 0 else { return nil }
        // A circle's ink is 16pt tall at 15pt: the point size a circle needs is the yardstick for the weight.
        var pointSize = reference * uniformInkHeight / probeInk.height
        if probeInk.width * pointSize / reference > uniformCanvas { pointSize = reference * uniformCanvas / probeInk.width }
        let ratio = pointSize / (reference * uniformInkHeight / 16)
        let weight = SAClaudeMenuGlyphs.uniformWeight(scale: ratio)
        guard let glyph = symbol(name, pointSize: pointSize, weight: weight), let ink = inkRect(of: glyph) else { return nil }
        // Symbols don't scale linearly with their point size (their optical sizes): the last step fits the drawn ink to
        // the height exactly.
        let canvas = uniformCanvas
        let fit = min(uniformInkHeight / ink.height, (canvas - 1) / ink.width)
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
            let origin = NSPoint(x: (canvas - ink.width * fit) / 2 - ink.minX * fit, y: (canvas - ink.height * fit) / 2 - ink.minY * fit)
            glyph.draw(in: NSRect(origin: origin, size: NSSize(width: glyph.size.width * fit, height: glyph.size.height * fit)))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = glyph.accessibilityDescription
        uniformImages[name] = image
        return image
    }

    private static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }

    /// Where `image` has ink (non-flipped, in points), from a 4× render of it at its own size.
    private static func inkRect(of image: NSImage) -> NSRect? {
        let scale: CGFloat = 4
        let width = Int(ceil(image.size.width * scale)), height = Int(ceil(image.size.height * scale))
        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: rep), let pixels = rep.bitmapData else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // At its own size in a scaled context, as a menu draws it (a symbol drawn into a larger rect renders at a larger
        // optical size, whose ink differs).
        context.cgContext.scaleBy(x: scale, y: scale)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 64 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        // Bitmap rows run from the top.
        return NSRect(x: CGFloat(minX) / scale, y: CGFloat(height - 1 - maxY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    /// The menu glyph for a symbol name: 15pt regular, a template, cached.
    private static func image(named name: String) -> NSImage? {
        if let image = images[name] { return image }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) else { return nil }
        image.isTemplate = true
        images[name] = image
        return image
    }
}
