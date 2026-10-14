//
//  SAClaudeProgressSheetStyler.swift
//  Sequel Ace
//
//  The Claude look of a progress sheet and an errors sheet, shared by Export (`SAClaudeExportStyler`, once per
//  `SPExportController`) and Import (`SAClaudeImportStyler`, once per `SPDataImport`); each passes its own outlets.
//  The progress sheet: medium title, muted middle-truncated status line, the Claude progress bar over the XIB's
//  indicator. The errors sheet: medium label, the log in the editor font inside a hairline frame. The sheets'
//  surface, buttons and text colours stay the generic sheet skin's. No card is added behind either sheet's content:
//  on the skin's surface it would be a box inside a box. Each sheet is styled only when its outlets are all there.
//  App target only.
//

import AppKit

final class SAClaudeProgressSheetStyler {

    /// The progress sheet's title, status line and indicator.
    struct Outlets {
        var title: NSTextField
        var status: NSTextField
        var indicator: NSProgressIndicator
    }

    /// The errors sheet and its log.
    struct ErrorOutlets {
        var window: NSWindow
        var textView: NSTextView
    }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let statusFont = NSFont.systemFont(ofSize: 11)
    /// The errors label's height for the 13pt medium title (its XIB frame is 14pt and clips the descenders).
    private static let errorsLabelHeight: CGFloat = 17
    private static let logFrameRadius: CGFloat = 7
    /// Keeps the log's square corners inside the frame's rounded outline.
    private static let logInset: CGFloat = 3
    private static let logTextInset = NSSize(width: 4, height: 4)

    private struct Progress {
        let indicator: NSProgressIndicator
        let status: NSTextField
        let bar = SAClaudeProgressBar()
        var observations: [NSKeyValueObservation] = []
    }

    private struct Log {
        let textView: NSTextView
        let frame = SAClaudeTableInfoCardView()
    }

    private var progress: Progress?
    private var log: Log?

    /// Styles the progress sheet of `progress` and the errors sheet of `errors`; nil when neither is given (or
    /// neither has its views in place).
    init?(progress outlets: Outlets?, errors errorOutlets: ErrorOutlets?) {
        if let outlets, let parent = outlets.indicator.superview {
            outlets.title.font = Self.titleFont
            outlets.status.font = Self.statusFont
            outlets.status.lineBreakMode = .byTruncatingMiddle
            progress = Progress(indicator: outlets.indicator, status: outlets.status)
            installBar(over: outlets.indicator, in: parent)
        }
        if let errorOutlets, let scrollView = errorOutlets.textView.enclosingScrollView,
           let parent = scrollView.superview {
            let textView = errorOutlets.textView
            // The label above the log has no outlet: the topmost static text of the sheet.
            let label = errorOutlets.window.contentView?.subviews.compactMap { $0 as? NSTextField }
                .filter { !$0.isEditable && !$0.isHidden }.max { $0.frame.maxY < $1.frame.maxY }
            if let label {
                label.font = Self.titleFont
                // Taller for the bigger font, keeping its top edge (the label is pinned to the top of the sheet).
                if label.frame.height < Self.errorsLabelHeight {
                    label.frame = NSRect(x: label.frame.minX, y: label.frame.maxY - Self.errorsLabelHeight,
                                         width: label.frame.width, height: Self.errorsLabelHeight)
                }
            }
            textView.font = SAClaudeCompletionStyler.editorFont()
            textView.textContainerInset = Self.logTextInset
            installFrame(around: scrollView, in: parent, textView: textView)
        }
        if progress == nil && log == nil { return nil }
    }

    deinit {
        progress?.observations.forEach { $0.invalidate() }
    }

    /// Recolours the status line (muted), the bar's track and the log's frame, and redraws the bar (the accent may
    /// have changed).
    func recolour(palette: SAClaudeEditorChrome.Palette) {
        if let progress {
            if progress.status.textColor != palette.icon { progress.status.textColor = palette.icon }
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
    /// `maxValue`, and keeps receiving the export's or import's values: it is invisible while a value is shown
    /// (and the bar draws it), and visible while indeterminate (and the bar is hidden). The bar follows the indicator
    /// by KVO.
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
        // The exporters and importers may report progress from a background thread.
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

extension SAClaudeProgressSheetStyler.Outlets {
    /// `controller`'s outlets of these names (read by KVC); nil when one is missing.
    init?(_ controller: NSObject, title: String, status: String, indicator: String) {
        guard let title: NSTextField = SAClaudeExportStyler.outlet(controller, title),
              let status: NSTextField = SAClaudeExportStyler.outlet(controller, status),
              let indicator: NSProgressIndicator = SAClaudeExportStyler.outlet(controller, indicator) else {
            return nil
        }
        self.init(title: title, status: status, indicator: indicator)
    }
}

extension SAClaudeProgressSheetStyler.ErrorOutlets {
    /// `controller`'s outlets of these names (read by KVC); nil when one is missing.
    init?(_ controller: NSObject, window: String, textView: String) {
        guard let window: NSWindow = SAClaudeExportStyler.outlet(controller, window),
              let textView: NSTextView = SAClaudeExportStyler.outlet(controller, textView) else { return nil }
        self.init(window: window, textView: textView)
    }
}
