//
//  SAScriptConsoleLayoutManager.swift
//  Sequel Ace
//
//  Draws the Run All console's block decorations behind the text: a faint line
//  above each statement block, and for failed blocks a clay tint with a 2pt clay
//  left edge, across the console's full width. App target only.
//

import AppKit

final class SAScriptConsoleLayoutManager: NSLayoutManager {

    var separatorColour: NSColor = .separatorColor
    var errorTint: NSColor = .clear
    var errorEdge = NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)

    /// Vertical padding of a block: the band reaches this far above and below its text,
    /// and blocks after the first sit twice this far apart (see the console's paragraph spacing).
    static let blockPadding: CGFloat = 10

    /// Draws the block decorations for `dirtyRect` of `textView`. Called by
    /// SAScriptConsoleBlockTextView before any text is drawn, so the selection
    /// (drawn later by drawBackground(forGlyphRange:at:)) stays visible on top.
    /// The text view, not drawBackground(forGlyphRange:at:), calls this because
    /// NSTextView clips glyph drawing to the text container (inside the 14pt
    /// inset), and blocks span the console's full width.
    func drawBlockDecorations(in dirtyRect: NSRect, of textView: NSTextView) {
        guard let storage = textStorage, storage.length > 0, let container = textView.textContainer else { return }

        // macOS 14+ views don't clip: fill only inside the bounds and the area being redrawn.
        var clip = textView.bounds.intersection(dirtyRect)
        if let context = NSGraphicsContext.current?.cgContext { clip = clip.intersection(context.boundingBoxOfClipPath) }
        guard !clip.isEmpty else { return }
        func fill(_ rect: NSRect) {
            let visible = rect.intersection(clip)
            if !visible.isEmpty { visible.fill() }
        }
        let padding = Self.blockPadding
        let origin = textView.textContainerOrigin
        let full = textView.bounds

        // Decorations reach one block padding beyond their lines (into the gap
        // between blocks), so look a little further up and down than the dirty rect.
        let shown = clip.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: 0, dy: -(2 * padding + 1))
        let glyphs = glyphRange(forBoundingRectWithoutAdditionalLayout: NSRect(x: 0, y: shown.minY, width: container.containerSize.width, height: shown.height), in: container)
        guard glyphs.length > 0 else { return }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)

        storage.enumerateAttribute(.saConsoleBlockError, in: characters, options: []) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: glyphs, in: container)
            // A block ending the text would otherwise include the empty line after its last newline.
            let extra = extraLineFragmentRect
            if NSMaxRange(range) == storage.length, !extra.isEmpty, extra.minY < rect.maxY, extra.minY > rect.minY {
                rect.size.height = extra.minY - rect.minY
            }
            rect = NSRect(x: full.minX, y: origin.y + rect.minY, width: full.width, height: rect.height).insetBy(dx: 0, dy: -padding)
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
            fill(NSRect(x: full.minX, y: origin.y + line.minY - padding - 0.5, width: full.width, height: 1))
        }
    }
}

/// The console's text view: draws the block decorations over its background,
/// before the selection and the text.
final class SAScriptConsoleBlockTextView: NSTextView {
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        (layoutManager as? SAScriptConsoleLayoutManager)?.drawBlockDecorations(in: rect, of: self)
    }
}
