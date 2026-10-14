//
//  SAClaudeProgressBar.swift
//  Sequel Ace
//
//  The Claude export progress bar: a 6pt rounded hairline track with the accent filling it from the left. It is a
//  plain view laid over the sheet's NSProgressIndicator and reads that indicator's value, range and mode when it
//  draws; the indicator itself is not touched (its frame, `maxValue` and animation are the export's progress scale
//  and stay AppKit's), so this does not depend on how AppKit draws a determinate indicator on the running macOS.
//  The indeterminate "Initializing..." state is left to the indicator, which `SAClaudeExportProgressStyler` shows
//  then. App target only.
//

import AppKit

final class SAClaudeProgressBar: NSView {

    static let trackHeight: CGFloat = 6

    /// The indicator whose value this draws; weak, as the indicator and this view are siblings.
    weak var indicator: NSProgressIndicator? { didSet { needsDisplay = true } }
    var trackColour: NSColor = .clear { didSet { needsDisplay = true } }

    /// How much of the track `value` fills: its share of the range, from 0 to 1.
    static func fraction(value: Double, minimum: Double, maximum: Double) -> CGFloat {
        CGFloat(min(1, max(0, (value - minimum) / max(1, maximum - minimum))))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let indicator, !indicator.isIndeterminate else { return }
        let height = Self.trackHeight
        let track = NSRect(x: bounds.minX, y: floor(bounds.midY - height / 2), width: bounds.width, height: height)
        let shape = NSBezierPath(roundedRect: track, xRadius: height / 2, yRadius: height / 2)
        trackColour.setFill()
        shape.fill()

        let fraction = Self.fraction(value: indicator.doubleValue, minimum: indicator.minValue, maximum: indicator.maxValue)
        guard fraction > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        SAClaudeAccent.accent.setFill()
        NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
