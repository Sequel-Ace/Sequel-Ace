//
//  SAClaudeRareWindowChrome.swift
//  Sequel Ace
//
//  The window around a rare Claude page (the SQL help viewer, About, the bundle HTML window): the palette's surface
//  behind a transparent title bar, and the window's appearance set from the palette's lightness, so the title, the
//  scrollers and the system colours in it match the page (the palette follows the editor theme, not the app's
//  appearance). App target only.
//

import AppKit

@MainActor
enum SAClaudeRareWindowChrome {

    /// Applies the surface, the transparent title bar and the matching aqua / darkAqua appearance. Idempotent: a value
    /// already in place is not set again (setting the appearance would re-fire `effectiveAppearance` observers).
    static func apply(to window: NSWindow, palette: SAClaudeHintCardPalette) {
        if window.backgroundColor != palette.surface { window.backgroundColor = palette.surface }
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        let name: NSAppearance.Name = palette.isDark ? .darkAqua : .aqua
        if window.appearance?.name != name { window.appearance = NSAppearance(named: name) }
    }
}
