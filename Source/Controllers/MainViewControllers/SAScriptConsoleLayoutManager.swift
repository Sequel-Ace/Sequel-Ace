//
//  SAScriptConsoleLayoutManager.swift
//  Sequel Ace
//
//  Draws the Run All console's block decorations behind the text: a faint line
//  above each statement block, and for failed blocks a clay tint with a 2pt clay
//  left edge. App target only.
//

import AppKit

final class SAScriptConsoleLayoutManager: NSLayoutManager {

    var separatorColour: NSColor = .separatorColor
    var errorTint: NSColor = .clear
    var errorEdge = NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }

        // macOS 14+ views don't clip: fill only inside the text container, the
        // text view's bounds and the area being redrawn.
        var clip = NSRect(origin: origin, size: container.containerSize)
        if let textView = container.textView { clip = clip.intersection(textView.bounds) }
        if let context = NSGraphicsContext.current?.cgContext { clip = clip.intersection(context.boundingBoxOfClipPath) }
        guard !clip.isEmpty else { return }
        func fill(_ rect: NSRect) {
            let visible = rect.intersection(clip)
            if !visible.isEmpty { visible.fill() }
        }

        // Decorations reach ~5pt beyond their lines (into the gap between blocks),
        // so look one gap further up and down than the glyphs being drawn.
        let shown = boundingRect(forGlyphRange: glyphsToShow, in: container).insetBy(dx: 0, dy: -11)
        let glyphs = glyphRange(forBoundingRectWithoutAdditionalLayout: shown, in: container)
        let characters = characterRange(forGlyphRange: NSUnionRange(glyphs, glyphsToShow), actualGlyphRange: nil)

        storage.enumerateAttribute(.saConsoleBlockError, in: characters, options: []) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: glyphs, in: container)
            // A block ending the text would otherwise include the empty line after its last newline.
            let extra = extraLineFragmentRect
            if NSMaxRange(range) == storage.length, !extra.isEmpty, extra.minY < rect.maxY, extra.minY > rect.minY {
                rect.size.height = extra.minY - rect.minY
            }
            rect.origin.x = 0
            rect.size.width = container.containerSize.width
            rect = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: 0, dy: -5)
            errorTint.setFill()
            fill(rect)
            errorEdge.setFill()
            fill(NSRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height))
        }

        storage.enumerateAttribute(.saConsoleBlockStart, in: characters, options: []) { value, range, _ in
            guard (value as? Bool) == true, range.location > 0 else { return }
            let glyph = glyphIndexForCharacter(at: range.location)
            // The used rect starts below the block's paragraph spacing (the gap between blocks).
            let line = lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            separatorColour.setFill()
            fill(NSRect(x: origin.x, y: origin.y + line.minY - 5.5, width: container.containerSize.width, height: 1))
        }
    }
}
