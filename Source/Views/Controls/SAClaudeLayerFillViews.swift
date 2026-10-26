//
//  SAClaudeLayerFillViews.swift
//  Sequel Ace
//
//  The flat Claude surfaces — page, bar and sidebar backgrounds, hairlines, cards and field outlines — as layer
//  properties instead of drawn pictures. A view that draws keeps a bitmap of its whole size (4 bytes a pixel at 2×,
//  plus the copy the layer shows) for as long as its window lives, hidden tabs included: a full-window page fill
//  alone was tens of MB per open tab. A layer colour, corner radius and border cost nothing per pixel.
//
//  Colours are resolved in `updateLayer()` under the view's own appearance (a dynamic colour's CGColor depends on
//  it), which AppKit runs again whenever a colour is set (`needsDisplay`) and after an appearance change. The
//  views ignore the mouse unless a subclass says otherwise. Shared with the Unit Tests target.
//

import AppKit

/// A flat colour filling the view, optionally with rounded corners; never takes clicks.
class SAClaudeFlatFillView: NSView {
    /// The fill; a dynamic colour follows light and dark.
    var fillColour: NSColor = .clear { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = fillColour.cgColor
        }
        layer.cornerRadius = cornerRadius
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A rounded fill with a 1pt line along its inside edge: what filling, then stroking 1pt wide,
/// `NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)` drew.
/// The line is the layer's border (radius `radius + 0.5` outside, `radius - 0.5` inside), which CA composites over
/// the sublayers; the fill is a subview inset by half the line. So the line's outer half lies over whatever is under
/// the view and its inner half over the fill, as when it was drawn, whatever the colours' alpha.
class SAClaudeOutlinedFillView: NSView {
    var fill: NSColor = .clear { didSet { fillView.fillColour = fill } }
    var stroke: NSColor = .clear { didSet { needsDisplay = true } }
    /// The corner radius of the path the line follows (its middle).
    var radius: CGFloat = 0 {
        didSet {
            fillView.cornerRadius = radius
            needsDisplay = true
        }
    }

    private let fillView = SAClaudeFlatFillView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        wantsLayer = true
        addSubview(fillView, positioned: .below, relativeTo: nil)
        layOutFill()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layOutFill()
    }

    /// The fill covers the path's inside: the bounds less half the line. Nothing while too small for a path.
    private func layOutFill() {
        let frame = bounds.width > 1 && bounds.height > 1 ? bounds.insetBy(dx: 0.5, dy: 0.5) : .zero
        if fillView.frame != frame { fillView.frame = frame }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.borderColor = stroke.cgColor
        }
        layer.borderWidth = 1
        layer.cornerRadius = radius + 0.5
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
