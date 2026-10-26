//
//  SAClaudeTableInfoCopyButton.swift
//  Sequel Ace
//
//  The Table Info tab's ghost Copy button: the copy glyph and "Copy", copying the whole CREATE statement to
//  the general pasteboard and flashing "Copied" for a moment. It draws itself completely (no cell, no AppKit
//  bezel: macOS 26+ draws a glass bezel behind borderless buttons that draw through their cell), at a fixed
//  width that fits both labels so the flash never moves it. App target only.
//

import AppKit

final class SAClaudeTableInfoCopyButton: NSButton {

    private static let glyphSize: CGFloat = 14
    private static let leadingPadding: CGFloat = 8
    private static let glyphGap: CGFloat = 5
    private static let trailingPadding: CGFloat = 10
    private static let copiedDuration: TimeInterval = 1.2
    private static let disabledAlpha: CGFloat = 0.45
    private static var labelFont: NSFont { .systemFont(ofSize: 12) }
    private static var copyLabel: String { NSLocalizedString("Copy", comment: "table info : copy create syntax button") }

    /// The text to copy, read at click time.
    var syntaxProvider: () -> String = { "" }

    /// A disabled button shows no hover fill: one already showing when it is disabled is cleared (the highlighter
    /// itself only declines to start one on a disabled control).
    override var isEnabled: Bool {
        didSet {
            if !isEnabled { SAClaudeHoverHighlighter.highlighter(for: self)?.setHovered(false) }
            needsDisplay = true
        }
    }

    private var palette: SAClaudeEditorChrome.Palette?
    private var isShowingCopied = false
    private var copiedReset: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isBordered = false
        imagePosition = .noImage
        focusRingType = .none
        target = self
        action = #selector(copySyntax(_:))
        title = Self.copyLabel
        setAccessibilityLabel(Self.copyLabel)
    }

    deinit { copiedReset?.cancel() }

    // MARK: - Size

    /// Wide enough for "Copy" and "Copied" with the glyph and padding, whichever is shown.
    var preferredWidth: CGFloat {
        let widest = [Self.copyLabel, SAClaudeQueryCopyAction.copiedLabel]
            .map { ceil(($0 as NSString).size(withAttributes: [.font: Self.labelFont]).width) }.max() ?? 0
        return Self.leadingPadding + Self.glyphSize + Self.glyphGap + widest + Self.trailingPadding
    }

    // MARK: - Colours

    func refresh(palette: SAClaudeEditorChrome.Palette) {
        self.palette = palette
        SAClaudeHoverHighlighter.attach(to: self)
        SAClaudeHoverHighlighter.setFillColour(palette.hover, for: self)
        needsDisplay = true
    }

    // MARK: - Copying

    @objc private func copySyntax(_ sender: Any?) {
        let text = syntaxProvider()
        guard SAClaudeTableInfoLayout.copyEnabled(syntax: text) else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopied()
    }

    private func showCopied() {
        copiedReset?.cancel()
        isShowingCopied = true
        title = SAClaudeQueryCopyAction.copiedLabel
        let reset = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isShowingCopied = false
            self.title = Self.copyLabel
        }
        copiedReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedDuration, execute: reset)
    }

    // MARK: - Drawing

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let palette else { return }
        let alpha: CGFloat = isEnabled ? (isHighlighted ? 0.7 : 1) : Self.disabledAlpha
        let glyphRect = NSRect(x: bounds.minX + Self.leadingPadding, y: (bounds.midY - Self.glyphSize / 2).rounded(),
                               width: Self.glyphSize, height: Self.glyphSize)
        SAClaudeGlyphs.image(.copy, tint: palette.icon)
            .draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)

        let label = (isShowingCopied ? SAClaudeQueryCopyAction.copiedLabel : Self.copyLabel) as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.labelFont,
                                                         .foregroundColor: palette.buttonText.withAlphaComponent(alpha)]
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: glyphRect.maxX + Self.glyphGap, y: (bounds.midY - size.height / 2).rounded()),
                   withAttributes: attributes)
    }
}
