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
//  chips') are filled again each time. The main menu bar's menus are left to
//  macOS. App target only.
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
            SAClaudeMenuGlyphs.apply(to: menu, imageFor: image(named:))
        }
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
