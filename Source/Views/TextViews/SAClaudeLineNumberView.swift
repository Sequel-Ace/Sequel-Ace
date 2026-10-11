//
//  SAClaudeLineNumberView.swift
//  Sequel Ace
//
//  The query editor's line-number gutter in the Claude style: the editor
//  theme's background, no separator line, SF Mono 11 numbers in a colour
//  derived from the theme. App target only.
//

import AppKit

@objc(SAClaudeLineNumberView) final class SAClaudeLineNumberView: NoodleLineNumberView {

    private var observer: NSObjectProtocol?
    private var appliedPalette: SAClaudeEditorChrome.Palette?
    private var gutterBackground: NSColor = .textBackgroundColor

    override init(scrollView aScrollView: NSScrollView) {
        super.init(scrollView: aScrollView)
        setFont(.monospacedSystemFont(ofSize: 11, weight: .regular))
        applyPalette()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyPalette()
        }
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    /// Re-derives the gutter colours from the editor theme. The observer fires on every
    /// app-wide defaults write, so unchanged palettes are skipped.
    private func applyPalette() {
        let palette = SAClaudeEditorChrome.palette(from: .standard)
        guard palette != appliedPalette else { return }
        appliedPalette = palette
        gutterBackground = palette.background
        backgroundColor = palette.background
        setTextColor(palette.gutterNumbers)
        needsDisplay = true
    }

    /// Fills the gutter with the theme background and draws the numbers. Deliberately does not call
    /// `super.draw`, so the stock ruler background and separator line are not drawn. NoodleLineNumberView
    /// has no ruler markers (removed in the Sequel Ace version), so there is nothing else to draw.
    /// Clipped to bounds: since macOS 14 views don't clip by default and `dirtyRect` can extend past
    /// the ruler, so filling it unclipped would paint over the text view beside the gutter.
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.intersection(dirtyRect)
        gutterBackground.setFill()
        rect.fill()
        drawHashMarksAndLabels(in: rect)
    }
}
