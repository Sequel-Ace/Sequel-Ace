//
//  SAClaudeWindowColourViews.swift
//  Sequel Ace
//
//  The window chrome that shows a connection's colour (see SAWindowTitlebarTint, which decides what shows): the
//  base class of our own title bar accessories, and the 2pt line under the toolbar.
//

import AppKit

/// The base of every title bar accessory controller of ours. macOS's tab strip lives in a bottom accessory of
/// AppKit's own, which the tab bar keeps hidden (`SAClaudeWindowTabBarController.hideNativeTabBar(in:)`); the
/// hiding leaves accessories of this class alone.
class SAClaudeOwnedTitlebarAccessory: NSTitlebarAccessoryViewController {}

/// The Underline line while the tab bar is hidden: a 2pt line in the connection colour right under the toolbar, at
/// the top edge of the window's content view, in place of the hairline. While the tab bar shows, the bar draws the
/// line itself (it is then the bottom of the chrome) and this one has no colour.
///
/// Not a title bar accessory: showing or hiding one changes the title bar's height, and doing that in the same
/// tab-group change that shows or hides the tab bar left the document view's content 2pt taller than the content
/// view each time, creeping up over the toolbar. Nor a subview of AppKit's frame view: with one there, AppKit built
/// some new windows' title bars without their container, and the tab bar in them stopped laying out. The overlay
/// sits in the content view, above the document, and never changes any layout: it keeps to the top edge by its
/// autoresizing mask and only hides itself. It ignores the mouse.
final class SAConnectionColourLineOverlay: NSView {
    static let height: CGFloat = 2

    /// The line's colour, `nil` for no line. Kept unresolved and set at draw time, so an asset colour follows light
    /// and dark.
    var colour: NSColor? {
        didSet {
            guard colour != oldValue else { return }
            needsDisplay = true
            update()
        }
    }

    private weak var contentView: NSView?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: Self.height))
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Puts the line along the top edge of `window`'s content view, above everything already there.
    func attach(to window: NSWindow) {
        guard let contentView = window.contentView else { return }
        self.contentView = contentView
        let bounds = contentView.bounds
        frame = NSRect(x: bounds.minX, y: contentView.isFlipped ? bounds.minY : bounds.maxY - Self.height,
                       width: bounds.width, height: Self.height)
        autoresizingMask = contentView.isFlipped ? [.width, .maxYMargin] : [.width, .minYMargin]
        contentView.addSubview(self, positioned: .above, relativeTo: nil)
        update()
    }

    /// Shows the line when it has a colour, kept above any view added to the content view since.
    private func update() {
        let shouldHide = colour == nil
        if isHidden != shouldHide { isHidden = shouldHide }
        if !shouldHide, let contentView, contentView.subviews.last !== self {
            contentView.addSubview(self, positioned: .above, relativeTo: nil)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

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
