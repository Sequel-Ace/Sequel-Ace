//
//  SAClaudeWindowColourViews.swift
//  Sequel Ace
//
//  The window chrome that shows a connection's colour (see SAWindowTitlebarTint, which decides what shows): the
//  base class of our own title bar accessories, and the 2pt line accessory under the toolbar.
//

import AppKit

/// The base of every title bar accessory controller of ours. macOS's tab strip lives in a bottom accessory of
/// AppKit's own, which the tab bar keeps hidden (`SAClaudeWindowTabBarController.hideNativeTabBar(in:)`); the
/// hiding leaves accessories of this class alone.
class SAClaudeOwnedTitlebarAccessory: NSTitlebarAccessoryViewController {}

/// The Underline line while the tab bar is hidden: a 2pt line in the connection colour along the bottom of the
/// window chrome, under the toolbar. While the tab bar shows, the bar draws the line itself (it is then the
/// bottom of the chrome) and this one has no colour. Hidden, which collapses it, when there is no colour.
final class SAConnectionColourLineAccessory: SAClaudeOwnedTitlebarAccessory {
    static let height: CGFloat = 2

    /// The line's colour, `nil` for no line. Kept unresolved: the line view sets it at draw time, so an asset
    /// colour follows light and dark.
    var colour: NSColor? {
        didSet {
            guard colour != oldValue else { return }
            lineView.colour = colour
            if isHidden != (colour == nil) { isHidden = colour == nil }
        }
    }

    private let lineView = SAConnectionColourLineView(frame: NSRect(x: 0, y: 0, width: 100, height: SAConnectionColourLineAccessory.height))

    init() {
        super.init(nibName: nil, bundle: nil)
        // AppKit otherwise gives a bottom accessory its standard bar height (36pt) as soon as the view is set.
        automaticallyAdjustsSize = false
        layoutAttribute = .bottom
        lineView.autoresizingMask = [.width]
        view = lineView
        fullScreenMinHeight = Self.height
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Fills its bounds with `colour`.
private final class SAConnectionColourLineView: NSView {
    var colour: NSColor? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let colour else { return }
        colour.setFill()
        bounds.intersection(dirtyRect).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
