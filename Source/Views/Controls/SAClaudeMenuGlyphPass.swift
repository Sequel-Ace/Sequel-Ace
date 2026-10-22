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
//  (`SAClaudeMenuGlyphs.shouldApply`). In those same windows, context menus go
//  without macOS 27's "Ask Siri" field (`allowsContextMenuPlugIns` off, set as
//  a right-click arrives, before AppKit builds the menu). App target only.
//

import AppKit

@objc(SAClaudeMenuGlyphPass) final class SAClaudeMenuGlyphPass: NSObject {

    private static var observer: NSObjectProtocol?
    private static var images: [String: NSImage] = [:]

    private static var contextClickMonitor: Any?

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
            // Too late for this opening (AppKit decides on the "Ask Siri" field before tracking starts), but a menu
            // shown again (a rebuilt or keyboard-opened one) opens without it.
            suppressAssistant(in: menu)
        }
        // A right-click (or control-click) in a gated window: the menus of the clicked view and its ancestors lose the
        // "Ask Siri" field before AppKit asks the view for its menu.
        contextClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            if event.type == .rightMouseDown || event.modifierFlags.contains(.control) { prepareContextMenus(for: event) }
            return event
        }
    }

    /// macOS 27 puts an "Ask Siri" field on top of a context menu that allows plug-ins; the Claude look's menus (in the
    /// windows this pass glyphs) go without it. Only matters when the menu is used as a context menu.
    static func suppressAssistant(in menu: NSMenu?) {
        guard let menu, menu.allowsContextMenuPlugIns else { return }
        menu.allowsContextMenuPlugIns = false
    }

    /// Before a right-click is dispatched: when it lands in a window whose menus this pass glyphs, the context menus of
    /// the view under it and of its ancestors (a table's, an outline's: the instances their `menuForEvent:` returns) are
    /// set not to allow plug-ins, which is what keeps the "Ask Siri" field out of them (it has to be set before the menu
    /// is presented; at `didBeginTracking` it only affects the next opening).
    private static func prepareContextMenus(for event: NSEvent) {
        guard let window = event.window,
              SAClaudeMenuGlyphs.shouldApply(isMainMenu: false, isMainDocumentWindow: isMainDocumentWindow(window),
                                             hasAttachedSheet: window.attachedSheet != nil, ownerClasses: ownerClasses(of: window)),
              let frameView = window.contentView?.superview else { return }
        // The frame view has no superview: hit-testing takes window coordinates.
        var view = frameView.hitTest(event.locationInWindow)
        while let current = view {
            suppressAssistant(in: current.menu)
            view = current.superview
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

    /// The box a uniform menu glyph is drawn in, and the height every glyph's ink takes inside it: the height macOS 27
    /// draws the pass's circle glyphs at in a menu (measured from a popped menu: info.circle's ink is 10.5pt tall; the
    /// menu redraws symbol images at its own size, so a tall symbol such as doc.on.doc shows taller than a circle).
    static let uniformCanvas: CGFloat = 14
    static let uniformInkHeight: CGFloat = 10.5
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
    /// Fills `menu`'s glyphs now, as the pass would when it opens: for a menu whose position depends on its width,
    /// measured before it is shown (the pass adds them only once tracking has begun).
    @objc(applyGlyphsToMenu:)
    static func applyGlyphs(to menu: NSMenu) {
        SAClaudeMenuGlyphs.apply(to: menu, imageFor: image(named:))
    }

    private static func image(named name: String) -> NSImage? {
        if let image = images[name] { return image }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) else { return nil }
        image.isTemplate = true
        images[name] = image
        return image
    }
}
