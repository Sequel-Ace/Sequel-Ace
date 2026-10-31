//
//  SAClaudeChromeLayout.swift
//  Sequel Ace
//
//  Frames for the Claude everyday chrome: the loading-overlay (task HUD) card and the window tab content
//  (colour dot, title, SSL lock). Pure geometry, shared with Unit Tests. Coordinates are AppKit's (origin bottom-left).
//

import AppKit

enum SAClaudeTaskHUDLayout {
    static let size = NSSize(width: 360, height: 72)
    static let inset: CGFloat = 16
    static let spinnerSize: CGFloat = 28
    static let gap: CGFloat = 12
    static let buttonHeight: CGFloat = 24
    static let cornerRadius: CGFloat = 14

    struct Frames: Equatable {
        var spinner: NSRect
        var description: NSRect
        var duration: NSRect
        var button: NSRect?
    }

    /// `buttonWidth` nil = the cancel button is hidden; the text then runs to the right inset.
    static func frames(buttonWidth: CGFloat?) -> Frames {
        let W = size.width, Hh = size.height
        let spinner = NSRect(x: inset, y: ((Hh - spinnerSize) / 2).rounded(.down), width: spinnerSize, height: spinnerSize)
        let textX = spinner.maxX + gap
        var button: NSRect?
        var textRight = W - inset
        if let buttonWidth {
            let b = NSRect(x: W - inset - buttonWidth, y: ((Hh - buttonHeight) / 2).rounded(.down), width: buttonWidth, height: buttonHeight)
            button = b
            textRight = b.minX - gap
        }
        let width = max(0, textRight - textX)
        // Description (17) over duration (14) with a 3pt gap, centred as a pair.
        let pairTop = ((Hh - (17 + 3 + 14)) / 2).rounded(.down)        // from the top
        let description = NSRect(x: textX, y: Hh - pairTop - 17, width: width, height: 17)
        let duration = NSRect(x: textX, y: description.minY - 3 - 14, width: width, height: 14)
        return Frames(spinner: spinner, description: description, duration: duration, button: button)
    }

    static func buttonWidth(titleWidth: CGFloat) -> CGFloat { max(64, ceil(titleWidth) + 24) }

    static func ringFraction(value: Double, maximum: Double) -> CGFloat {
        guard maximum > 0 else { return 0 }
        return CGFloat(min(1, max(0, value / maximum)))
    }
}

enum SAClaudeTabContentLayout {
    static let dotSize: CGFloat = 7
    static let dotGap: CGFloat = 5
    static let lockSize: CGFloat = 10
    static let lockGap: CGFloat = 4
    static let titleHeight: CGFloat = 16

    struct Frames: Equatable {
        var dot: NSRect?
        var title: NSRect
        var lock: NSRect?
    }

    static func frames(size: NSSize, titleWidth: CGFloat, hasColour: Bool, isSSL: Bool) -> Frames {
        let lead = hasColour ? dotSize + dotGap : 0
        let trail = isSSL ? lockGap + lockSize : 0
        let available = max(0, size.width - lead - trail)
        let title = min(ceil(titleWidth), available)
        let x0 = ((size.width - (lead + title + trail)) / 2).rounded(.down)
        let dot = hasColour ? NSRect(x: x0, y: ((size.height - dotSize) / 2).rounded(.down), width: dotSize, height: dotSize) : nil
        let titleRect = NSRect(x: x0 + lead, y: ((size.height - titleHeight) / 2).rounded(.down), width: title, height: titleHeight)
        let lock = isSSL ? NSRect(x: titleRect.maxX + lockGap, y: ((size.height - lockSize) / 2).rounded(.down), width: lockSize, height: lockSize) : nil
        return Frames(dot: dot, title: titleRect, lock: lock)
    }
}
