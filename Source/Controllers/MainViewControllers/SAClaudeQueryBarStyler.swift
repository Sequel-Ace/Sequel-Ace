//
//  SAClaudeQueryBarStyler.swift
//  Sequel Ace
//
//  Restyles the bar under the query editor like Claude: 44pt, ghost buttons
//  for the editor menu, Favorites and History, colours derived from the editor
//  theme, a hairline above (the editor split) and below. App target only.
//

import AppKit

@objc final class SAClaudeQueryBarStyler: NSObject {

    private static var associationKey: UInt8 = 0

    private weak var bar: NSView?
    private weak var optionsButton: NSPopUpButton?
    private weak var favoritesButton: NSPopUpButton?
    private weak var historyButton: NSPopUpButton?
    private weak var runButton: NSView?
    private weak var editorSplitView: SPSplitView?
    private let background = SAClaudeEditorBarBackgroundView()
    private let bottomLine = SAClaudeDividerLine(frame: .zero)
    private var observer: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?

    /// Restyles the bar once per bar view and keeps it in step with the editor theme.
    @objc(attachToBarWithOptionsButton:favoritesButton:historyButton:runButton:resultsView:editorSplitView:)
    static func attach(optionsButton: NSPopUpButton, favoritesButton: NSPopUpButton, historyButton: NSPopUpButton,
                       runButton: NSView, resultsView: NSView, editorSplitView: SPSplitView) {
        guard let bar = favoritesButton.superview, objc_getAssociatedObject(bar, &associationKey) == nil else { return }
        let styler = SAClaudeQueryBarStyler()
        styler.bar = bar
        styler.optionsButton = optionsButton
        styler.favoritesButton = favoritesButton
        styler.historyButton = historyButton
        styler.runButton = runButton
        styler.editorSplitView = editorSplitView
        objc_setAssociatedObject(bar, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Grow the bar to 44pt, taking the space from the top of the results area.
        let frames = SAClaudeEditorChrome.barFrames(bar: bar.frame, results: resultsView.frame, height: SAClaudeEditorChrome.barHeight)
        bar.frame = frames.bar
        resultsView.frame = frames.results

        styler.background.frame = bar.bounds
        styler.background.autoresizingMask = [.width, .height]
        bar.addSubview(styler.background, positioned: .below, relativeTo: nil)
        styler.bottomLine.frame = NSRect(x: 0, y: 0, width: bar.bounds.width, height: 1)
        styler.bottomLine.autoresizingMask = [.width, .maxYMargin]
        bar.addSubview(styler.bottomLine)

        SAClaudeSidebarChrome.styleSidebarSplitView(editorSplitView)
        for button in [optionsButton, favoritesButton, historyButton] {
            button.isBordered = false
            (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
            button.font = .systemFont(ofSize: 13)
            SAClaudeHoverHighlighter.attach(to: button)
        }
        favoritesButton.item(at: 0)?.title = NSLocalizedString("Favorites", comment: "query editor bar: label of the query favorites menu button")
        historyButton.item(at: 0)?.title = NSLocalizedString("History", comment: "query editor bar: label of the query history menu button")
        favoritesButton.imagePosition = .imageLeading
        historyButton.imagePosition = .imageLeading
        optionsButton.imagePosition = .imageOnly

        styler.applyPalette()
        styler.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak styler] _ in
            styler?.applyPalette()
        }
        // Re-lay out when the window (and so the bar) is resized.
        bar.postsFrameChangedNotifications = true
        styler.frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: bar, queue: .main) { [weak styler, weak bar] _ in
            if let styler, let bar { styler.layoutButtons(in: bar) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
    }

    /// Applies the colours derived from the current editor theme and re-lays out the buttons.
    private func applyPalette() {
        guard let bar else { return }
        let palette = SAClaudeEditorChrome.palette(from: .standard)
        if background.fillColour != palette.background { background.fillColour = palette.background }
        bottomLine.colourOverride = palette.hairline
        editorSplitView?.customDividerColor = palette.hairline
        editorSplitView?.needsDisplay = true

        let glyphs: [(NSPopUpButton?, SAClaudeGlyph)] = [(optionsButton, .more), (favoritesButton, .favorite), (historyButton, .history)]
        for (button, glyph) in glyphs {
            guard let button else { continue }
            button.item(at: 0)?.image = SAClaudeGlyphs.image(glyph, tint: palette.icon)
            button.contentTintColor = palette.buttonText
            SAClaudeHoverHighlighter.setFillColour(palette.hover, for: button)
        }
        layoutButtons(in: bar)
    }

    fileprivate func layoutButtons(in bar: NSView) {
        let height = SAClaudeEditorChrome.buttonHeight
        let y = SAClaudeEditorChrome.centredY(height: height, in: bar.bounds.height)
        var runMinX = bar.bounds.maxX - SAClaudeEditorChrome.barSidePadding
        if let run = runButton {
            let width = run.frame.width
            run.frame = NSRect(x: bar.bounds.maxX - SAClaudeEditorChrome.barSidePadding - width, y: y, width: width, height: height)
            runMinX = run.frame.minX
        }
        let left = [optionsButton, favoritesButton, historyButton].compactMap { $0 }
        // Labels first; icon-only Favorites/History when the labels would run into Run.
        for labelled in [true, false] {
            for button in left where button !== optionsButton { button.imagePosition = labelled ? .imageLeading : .imageOnly }
            for button in left { button.sizeToFit() }
            let widths = left.map { $0 === optionsButton || !labelled ? height : max($0.frame.width + 12, height) }
            let xs = SAClaudeEditorChrome.leadingXs(widths: widths, start: SAClaudeEditorChrome.barSidePadding, gap: SAClaudeEditorChrome.buttonGap)
            let fits = (xs.last.map { $0 + widths[widths.count - 1] } ?? 0) <= runMinX - SAClaudeEditorChrome.buttonGap * 4
            if fits || !labelled {
                for (index, button) in left.enumerated() {
                    button.frame = NSRect(x: xs[index], y: y, width: widths[index], height: height)
                }
                return
            }
        }
    }
}

/// A plain fill in the editor theme's background, behind the bar's controls.
final class SAClaudeEditorBarBackgroundView: NSView {
    var fillColour: NSColor = .clear { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) { fillColour.setFill(); dirtyRect.fill() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
