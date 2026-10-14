//
//  SAClaudeExportProgressStyler.swift
//  Sequel Ace
//
//  The Claude look of the export's two small sheets, which `SAClaudeExportStyler` creates once per
//  `SPExportController`: the progress sheet (medium title, muted middle-truncated status line, the Claude progress
//  bar over the XIB's indicator) and the errors sheet (medium label, the log in the editor font inside a hairline
//  frame). The sheets' surface, buttons and text colours stay the generic sheet skin's. No card is added behind
//  either sheet's content: on the skin's surface it would be a box inside a box. Each sheet is styled only when its
//  outlets are all there. App target only.
//

import AppKit

final class SAClaudeExportProgressStyler {

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let statusFont = NSFont.systemFont(ofSize: 11)
    private static let logFrameRadius: CGFloat = 7
    /// Keeps the log's square corners inside the frame's rounded outline.
    private static let logInset: CGFloat = 3
    private static let logTextInset = NSSize(width: 4, height: 4)

    private struct Progress {
        let indicator: NSProgressIndicator
        let bar = SAClaudeProgressBar()
        var observations: [NSKeyValueObservation] = []
    }

    private struct Log {
        let textView: NSTextView
        let frame = SAClaudeTableInfoCardView()
    }

    private var progress: Progress?
    private var log: Log?

    /// Styles the progress and errors sheets of `controller` (an `SPExportController`); nil when neither sheet has
    /// all its outlets.
    init?(controller: NSObject) {
        if let title: NSTextField = SAClaudeExportStyler.outlet(controller, "exportProgressTitle"),
           let status: NSTextField = SAClaudeExportStyler.outlet(controller, "exportProgressText"),
           let indicator: NSProgressIndicator = SAClaudeExportStyler.outlet(controller, "exportProgressIndicator"),
           let parent = indicator.superview {
            title.font = Self.titleFont
            status.font = Self.statusFont
            status.lineBreakMode = .byTruncatingMiddle
            progress = Progress(indicator: indicator)
            installBar(over: indicator, in: parent)
        }
        if let window: NSWindow = SAClaudeExportStyler.outlet(controller, "errorsWindow"),
           let textView: NSTextView = SAClaudeExportStyler.outlet(controller, "errorsTextView"),
           let scrollView = textView.enclosingScrollView, let parent = scrollView.superview {
            // The label above the log has no outlet: the topmost static text of the sheet.
            let label = window.contentView?.subviews.compactMap { $0 as? NSTextField }
                .filter { !$0.isEditable && !$0.isHidden }.max { $0.frame.maxY < $1.frame.maxY }
            label?.font = Self.titleFont
            textView.font = SAClaudeCompletionStyler.editorFont()
            textView.textContainerInset = Self.logTextInset
            installFrame(around: scrollView, in: parent, textView: textView)
        }
        if progress == nil && log == nil { return nil }
    }

    deinit {
        progress?.observations.forEach { $0.invalidate() }
    }

    /// Recolours the bar's track and the log's frame, and redraws the bar (the accent may have changed).
    func recolour(palette: SAClaudeEditorChrome.Palette) {
        if let progress {
            progress.bar.trackColour = palette.hairline
            progress.bar.needsDisplay = true
        }
        if let log {
            log.frame.fill = palette.background
            log.frame.stroke = palette.hairline
            let font = SAClaudeCompletionStyler.editorFont()
            if log.textView.font != font { log.textView.font = font }
        }
    }

    // MARK: - Progress

    /// The bar goes over the indicator, same frame and resizing. The indicator stays in the window with its frame and
    /// `maxValue`, and keeps receiving the export's values: it is invisible while a value is shown (and the bar
    /// draws it), and visible while indeterminate (and the bar is hidden). The bar follows the indicator by KVO.
    private func installBar(over indicator: NSProgressIndicator, in parent: NSView) {
        guard var progress else { return }
        let bar = progress.bar
        bar.frame = indicator.frame
        bar.autoresizingMask = indicator.autoresizingMask
        bar.indicator = indicator
        parent.addSubview(bar, positioned: .above, relativeTo: indicator)
        let sync: () -> Void = { [weak indicator, weak bar] in
            guard let indicator, let bar else { return }
            let hidden = indicator.isHidden || indicator.isIndeterminate
            if bar.isHidden != hidden { bar.isHidden = hidden }
            let alpha: CGFloat = indicator.isIndeterminate ? 1 : 0
            if indicator.alphaValue != alpha { indicator.alphaValue = alpha }
            bar.needsDisplay = true
        }
        // The exporters may report progress from a background thread.
        let onMain: () -> Void = { Thread.isMainThread ? sync() : DispatchQueue.main.async(execute: sync) }
        progress.observations = [
            indicator.observe(\.doubleValue) { _, _ in onMain() },
            indicator.observe(\.isIndeterminate) { _, _ in onMain() },
            indicator.observe(\.minValue) { _, _ in onMain() },
            indicator.observe(\.maxValue) { _, _ in onMain() },
            indicator.observe(\.isHidden) { _, _ in onMain() },
        ]
        self.progress = progress
        sync()
    }

    // MARK: - Errors

    /// The log's 1pt hairline frame sits behind its scroll view (an NSScrollView's own layer border doesn't draw);
    /// the scroll view moves in a little so its square corners stay inside the rounded outline.
    private func installFrame(around scrollView: NSScrollView, in parent: NSView, textView: NSTextView) {
        let log = Log(textView: textView)
        log.frame.radius = Self.logFrameRadius
        log.frame.frame = scrollView.frame
        log.frame.autoresizingMask = scrollView.autoresizingMask
        parent.addSubview(log.frame, positioned: .below, relativeTo: scrollView)
        scrollView.borderType = .noBorder
        let inner = scrollView.frame.insetBy(dx: Self.logInset, dy: Self.logInset)
        if scrollView.frame != inner { scrollView.frame = inner }
        self.log = log
    }
}
