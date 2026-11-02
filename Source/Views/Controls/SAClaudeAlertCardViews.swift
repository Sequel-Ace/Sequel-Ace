//
//  SAClaudeAlertCardViews.swift
//  Sequel Ace
//
//  The decorative views of the Claude alert card: the surface, the glyph tile, the "MySQL said" block and the
//  document view of the text scroll view. Colours are handed in by `update` (or `colours`) and read at draw time;
//  every `draw(_:)` fills only the dirty part of its bounds (macOS 14 and later views do not clip). Geometry comes
//  from `SAClaudeAlertLayout`. App target only; AppKit and the alert pure files only.
//

import AppKit

/// The card's root: flipped, filled with the card surface.
final class SAClaudeAlertCardView: NSView {
    var colours: SAClaudeAlertCardColours? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let colours else { return }
        colours.surface.setFill()
        bounds.intersection(dirtyRect).fill()
    }
}

/// The 32x32 rounded tile: the tone at 13% over the surface, the kind's symbol in the tone. Decoration only: the
/// alert's text carries the meaning, so VoiceOver skips it.
final class SAClaudeAlertGlyphTile: NSView {
    private(set) var kind: SAClaudeAlertKind = .warning
    private(set) var colours: SAClaudeAlertCardColours?

    static let cornerRadius: CGFloat = 8

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: SAClaudeAlertLayout.tileSize, height: SAClaudeAlertLayout.tileSize) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func isAccessibilityElement() -> Bool { false }

    func update(kind: SAClaudeAlertKind, colours: SAClaudeAlertCardColours) {
        self.kind = kind
        self.colours = colours
        needsDisplay = true
    }

    /// The symbol at 18pt medium, filled with `tone`.
    private func glyph(tone: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: SAClaudeAlertChrome.glyphPointSize, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: SAClaudeAlertChrome.symbolName(for: kind), accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            tone.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let colours else { return }
        let tone = SAClaudeAlertChrome.tone(for: kind, secondaryText: colours.secondaryText)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds.intersection(dirtyRect)).addClip()

        SAClaudeAlertChrome.tileFill(tone: tone, surface: colours.surface).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()

        if let image = glyph(tone: tone) {
            let size = image.size
            let rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

/// The "MySQL said" block: a rounded surface with a hairline, the label above the server's wrapping, selectable text.
final class SAClaudeAlertServerBlock: NSView {
    static let cornerRadius: CGFloat = 8

    let label: NSTextField
    let text: NSTextField
    private(set) var colours: SAClaudeAlertCardColours?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        label = NSTextField(labelWithString: "")
        label.font = SAClaudeAlertChrome.blockLabelFont
        label.lineBreakMode = .byTruncatingTail
        label.drawsBackground = false

        text = NSTextField(wrappingLabelWithString: "")
        text.font = SAClaudeAlertChrome.serverFont
        text.isSelectable = true
        text.drawsBackground = false
        text.isBordered = false

        super.init(frame: frameRect)
        addSubview(label)
        addSubview(text)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(colours: SAClaudeAlertCardColours) {
        self.colours = colours
        label.textColor = colours.secondaryText
        text.textColor = colours.text
        needsDisplay = true
    }

    /// The label's and the server text's heights when the block is `blockWidth` wide.
    func contentHeights(blockWidth: CGFloat) -> (label: CGFloat, text: CGFloat) {
        let width = max(blockWidth - 2 * SAClaudeAlertLayout.blockPaddingX, 1)
        func height(_ field: NSTextField) -> CGFloat {
            guard let cell = field.cell else { return 0 }
            return ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)).height)
        }
        return (height(label), height(text))
    }

    /// The block's height at `blockWidth`.
    func height(blockWidth: CGFloat) -> CGFloat {
        let heights = contentHeights(blockWidth: blockWidth)
        return SAClaudeAlertLayout.blockHeight(labelHeight: heights.label, textHeight: heights.text)
    }

    /// Places the label and the text from `SAClaudeAlertLayout.blockFrames` at the block's current width.
    func layoutContent() {
        let heights = contentHeights(blockWidth: bounds.width)
        let frames = SAClaudeAlertLayout.blockFrames(blockWidth: bounds.width, labelHeight: heights.label, textHeight: heights.text)
        if label.frame != frames.label { label.frame = frames.label }
        if text.frame != frames.text { text.frame = frames.text }
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let colours else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds.intersection(dirtyRect)).addClip()

        colours.blockFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()

        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius - 0.5, yRadius: Self.cornerRadius - 0.5)
        outline.lineWidth = 1
        colours.hairline.setStroke()
        outline.stroke()
    }
}

/// The flipped document view of the text scroll view (title, explanation and the server block live in it).
final class SAClaudeAlertTextDocument: NSView {
    override var isFlipped: Bool { true }
}
