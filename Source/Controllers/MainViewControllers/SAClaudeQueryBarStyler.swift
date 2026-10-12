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
    private weak var copyButton: SAClaudeCopyButton?
    private weak var editorSplitView: SPSplitView?
    private weak var editorScrollView: NSScrollView?
    private let background = SAClaudeEditorBarBackgroundView()
    private let bottomLine = SAClaudeDividerLine(frame: .zero)
    private var observer: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?
    private var runFrameObserver: NSObjectProtocol?
    private var appliedPalette: SAClaudeEditorChrome.Palette?
    private var isLayingOut = false

    /// Restyles the bar once per bar view and keeps it in step with the editor theme.
    @objc(attachToBarWithOptionsButton:favoritesButton:historyButton:runButton:resultsView:editorSplitView:resultsTable:)
    static func attach(optionsButton: NSPopUpButton, favoritesButton: NSPopUpButton, historyButton: NSPopUpButton,
                       runButton: NSView, resultsView: NSView, editorSplitView: SPSplitView, resultsTable: SPCopyTable?) {
        guard let bar = favoritesButton.superview, let container = bar.superview,
              objc_getAssociatedObject(bar, &associationKey) == nil else { return }
        let styler = SAClaudeQueryBarStyler()
        styler.bar = bar
        styler.optionsButton = optionsButton
        styler.favoritesButton = favoritesButton
        styler.historyButton = historyButton
        styler.runButton = runButton
        styler.editorSplitView = editorSplitView
        objc_setAssociatedObject(bar, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Pin the 44pt bar to the top of its pane; the results area runs up to it.
        let frames = SAClaudeEditorChrome.barFrames(container: container.bounds, results: resultsView.frame, height: SAClaudeEditorChrome.barHeight)
        bar.frame = frames.bar
        bar.autoresizingMask = [.width, .minYMargin]
        resultsView.frame = frames.results
        resultsView.autoresizingMask = [.width, .height]

        styler.background.frame = bar.bounds
        styler.background.autoresizingMask = [.width, .height]
        bar.addSubview(styler.background, positioned: .below, relativeTo: nil)
        styler.bottomLine.frame = NSRect(x: 0, y: 0, width: bar.bounds.width, height: 1)
        styler.bottomLine.autoresizingMask = [.width, .maxYMargin]
        bar.addSubview(styler.bottomLine)

        SAClaudeSidebarChrome.styleSidebarSplitView(editorSplitView)
        // The editor's scroll view has the XIB's default bezel; its bottom edge would double the hairline.
        if let editorPane = editorSplitView.subviews.first {
            for case let scrollView as NSScrollView in editorPane.subviews where scrollView.documentView is NSTextView {
                scrollView.borderType = .noBorder
                styler.editorScrollView = scrollView
            }
        }
        for button in [optionsButton, favoritesButton, historyButton] {
            button.isBordered = false
            (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
            button.font = .systemFont(ofSize: 13)
            button.alignment = .left // the XIB centres titles, which pushes the label away from its icon
            SAClaudeHoverHighlighter.attach(to: button)
        }
        favoritesButton.item(at: 0)?.title = NSLocalizedString("Favorites", comment: "query editor bar: label of the query favorites menu button")
        historyButton.item(at: 0)?.title = NSLocalizedString("History", comment: "query editor bar: label of the query history menu button")
        favoritesButton.imagePosition = .imageLeading
        historyButton.imagePosition = .imageLeading
        optionsButton.imagePosition = .imageOnly
        if let resultsTable {
            let copy = SAClaudeCopyButton.make(table: resultsTable)
            bar.addSubview(copy)
            styler.copyButton = copy
            // A different default action changes the label slot, hence the width.
            copy.preferredWidthDidChange = { [weak styler, weak bar] in
                if let styler, let bar { styler.layoutButtons(in: bar) }
            }
        }

        styler.applyPalette()
        styler.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak styler] _ in
            styler?.applyPalette()
        }
        // Re-lay out when the window (and so the bar) is resized.
        bar.postsFrameChangedNotifications = true
        styler.frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: bar, queue: .main) { [weak styler, weak bar] _ in
            if let styler, let bar { styler.layoutButtons(in: bar) }
        }
        // The Run button resizes itself to its title (awakeFromNib, setTitle:), possibly after this ran.
        runButton.postsFrameChangedNotifications = true
        styler.runFrameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: runButton, queue: .main) { [weak styler, weak bar] _ in
            if let styler, let bar { styler.layoutButtons(in: bar) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        if let runFrameObserver { NotificationCenter.default.removeObserver(runFrameObserver) }
    }

    /// Applies the colours derived from the current editor theme and re-lays out the buttons.
    private func applyPalette() {
        guard let bar else { return }
        let palette = SAClaudeEditorChrome.palette(from: .standard)
        // The defaults observer fires on every app-wide defaults write; only react when the palette changed.
        guard palette != appliedPalette else { return }
        appliedPalette = palette
        if background.fillColour != palette.background { background.fillColour = palette.background }
        bottomLine.colourOverride = palette.hairline
        // Dark scrollers on a dark editor theme and light ones on a light theme.
        editorScrollView?.appearance = SAClaudeGridChrome.scrollerAppearance(for: palette.background)
        if let split = editorSplitView {
            split.customDividerColor = palette.hairline
            // A plain needsDisplay didn't repaint the divider after a theme change; invalidate it explicitly.
            split.setNeedsDisplay(split.bounds)
            split.layer?.setNeedsDisplay()
        }

        let glyphs: [(NSPopUpButton?, SAClaudeGlyph)] = [(optionsButton, .more), (favoritesButton, .favorite), (historyButton, .history)]
        for (button, glyph) in glyphs {
            guard let button else { continue }
            button.item(at: 0)?.image = SAClaudeGlyphs.image(glyph, tint: palette.icon)
            button.contentTintColor = palette.buttonText
            SAClaudeHoverHighlighter.setFillColour(palette.hover, for: button)
        }
        copyButton?.palette = palette
        layoutButtons(in: bar)
    }

    /// Icon + label width. Not `sizeToFit`, which still reserves room for the hidden pull-down arrow;
    /// the cell draws the icon at x 8 and the label from x 28 (left-aligned).
    private func labelledWidth(of button: NSPopUpButton) -> CGFloat {
        let title = (button.item(at: 0)?.title ?? "") as NSString
        let titleWidth = ceil(title.size(withAttributes: [.font: button.font ?? .systemFont(ofSize: 13)]).width)
        return 28 + titleWidth + 10
    }

    fileprivate func layoutButtons(in bar: NSView) {
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        let height = SAClaudeEditorChrome.buttonHeight
        let y = SAClaudeEditorChrome.centredY(height: height, in: bar.bounds.height)
        var runMinX = bar.bounds.maxX - SAClaudeEditorChrome.barSidePadding
        if let run = runButton {
            let width = run.frame.width
            let runFrame = NSRect(x: bar.bounds.maxX - SAClaudeEditorChrome.barSidePadding - width, y: y, width: width, height: height)
            if run.frame != runFrame { run.frame = runFrame }
            runMinX = run.frame.minX
        }
        let left = [optionsButton, favoritesButton, historyButton].compactMap { $0 }
        let gapToRun = SAClaudeEditorChrome.buttonGap * 4
        // Shrink in order: the Copy label first, then the Favorites/History labels.
        let modes: [(copyLabelled: Bool, leftLabelled: Bool)] = [(true, true), (false, true), (false, false)]
        for (index, mode) in modes.enumerated() {
            var limit = runMinX
            var copyFrame: NSRect?
            if let copy = copyButton {
                let width = copy.preferredWidth(labelled: mode.copyLabelled)
                copyFrame = NSRect(x: runMinX - gapToRun - width, y: y, width: width, height: height)
                limit = copyFrame!.minX
            }
            for button in left where button !== optionsButton { button.imagePosition = mode.leftLabelled ? .imageLeading : .imageOnly }
            let widths = left.map { $0 === optionsButton || !mode.leftLabelled ? height : max(labelledWidth(of: $0), height) }
            let xs = SAClaudeEditorChrome.leadingXs(widths: widths, start: SAClaudeEditorChrome.barSidePadding, gap: SAClaudeEditorChrome.buttonGap)
            let fits = (xs.last.map { $0 + widths[widths.count - 1] } ?? 0) <= limit - gapToRun
            if fits || index == modes.count - 1 {
                for (i, button) in left.enumerated() { button.frame = NSRect(x: xs[i], y: y, width: widths[i], height: height) }
                if let copy = copyButton, let copyFrame {
                    copy.showsLabel = mode.copyLabelled
                    if copy.frame != copyFrame { copy.frame = copyFrame }
                }
                return
            }
        }
    }
}

/// A plain fill in the editor theme's background, behind the bar's controls.
final class SAClaudeEditorBarBackgroundView: NSView {
    var fillColour: NSColor = .clear { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) { fillColour.setFill(); bounds.intersection(dirtyRect).fill() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
