//
//  SAWindowTitlebarTint.swift
//  Sequel Ace
//
//  The window chrome appearance for a connection's favourite colour.
//  Split out of SPWindowController so it can be compiled into the Unit
//  Tests target: AppKit only, no project ObjC types, so the test target
//  needs no bridging header (same pattern as SAWindowTitleBuilder).
//

import AppKit

/// How the document window's chrome should look for a given connection colour.
///
/// Applying a favourite colour means painting the whole window top - title
/// bar, unified toolbar and the native tab bar - rather than only the 5pt line
/// on the tab accessory, which is hidden along with the tab bar (#1856).
/// `titlebarAppearsTransparent` is what makes that work: it stops the title bar
/// drawing its own background, so the window background shows through the
/// entire strip.
///
/// The `nil` case is deliberately not "transparent over
/// `windowBackgroundColor`" - that renders a flat, non-standard title bar
/// rather than undoing the tint, so all three properties have to be restored.
struct SAWindowTitlebarTint {

    /// Colour for `NSWindow.backgroundColor`. Kept as the caller's `NSColor`
    /// rather than a resolved value, so an asset colour with a light/dark pair
    /// keeps following the effective appearance.
    let backgroundColor: NSColor

    /// Whether the title bar should stop drawing its own background, letting
    /// `backgroundColor` show through the title bar, toolbar and tab bar.
    let titlebarAppearsTransparent: Bool

    /// Whether the hairline below the title bar is drawn. A separator reads as
    /// a stray line across a coloured strip, so a tinted window drops it.
    let separatorStyle: NSTitlebarSeparatorStyle

    /// Derive the chrome for a connection's favourite colour, or the stock
    /// title bar when `favoriteColor` is `nil` - meaning the connection has no
    /// favourite colour, or the document is not connected.
    init(favoriteColor: NSColor?) {
        if let favoriteColor = favoriteColor {
            backgroundColor = favoriteColor
            titlebarAppearsTransparent = true
            separatorStyle = .none
        } else {
            backgroundColor = .windowBackgroundColor
            titlebarAppearsTransparent = false
            separatorStyle = .automatic
        }
    }
}
