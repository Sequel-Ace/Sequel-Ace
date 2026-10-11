//
//  SAClaudeQueryInfoStyler.swift
//  Sequel Ace
//
//  Restyles the Query tab's status pane (under the results) and the strip
//  below it like Claude: theme background, a hairline divider, a muted title
//  with a status dot, the last error in a soft clay block, and ghost icon
//  buttons for the pane toggle and the export menu. Colours come from the
//  editor theme. App target only.
//

import AppKit

@objc(SAClaudeQueryInfoStyler) final class SAClaudeQueryInfoStyler: NSObject {

    private static var associationKey: UInt8 = 0
    /// Message text view → its styler, so `setErrorState(_:forTextView:)` can find it. Weak both ways:
    /// the split view retains the styler.
    private static let registry = NSMapTable<NSTextView, SAClaudeQueryInfoStyler>(keyOptions: .weakMemory, valueOptions: .weakMemory)

    private static let buttonSize: CGFloat = 28
    private static let titleShift: CGFloat = 13
    private static let dotSize: CGFloat = 7
    private static let dotGap: CGFloat = 6
    /// NSTextFieldCell draws its text 2pt in from the field's left edge.
    private static let titleTextInset: CGFloat = 2
    /// The error text's inset inside its block.
    private static let errorTextInset = NSSize(width: 10, height: 8)
    private static let statusGap: CGFloat = 8

    private weak var split: SPSplitView?
    private weak var pane: NSView?
    private weak var titleField: NSTextField?
    private weak var messageTextView: NSTextView?
    private weak var messageScrollView: NSScrollView?
    private weak var statusField: NSTextField?
    private weak var infoButton: NSButton?
    private weak var exportButton: NSPopUpButton?

    private let paneBackground = SAClaudeEditorBarBackgroundView()
    private let dot = SAClaudeRoundedFillView(frame: .zero)
    /// The eye toggle's resting fill while the pane is open (its image and alternate image are the same).
    private let infoButtonStateFill = SAClaudeRoundedFillView(frame: .zero)
    private let errorBlock = SAClaudeErrorBlockView(frame: .zero)
    private let stripBackground = SAClaudeEditorBarBackgroundView()
    private let stripLine = SAClaudeDividerLine(frame: .zero)

    private var isError = false
    private var appliedTheme: SAClaudeThemeColours?
    private var colours: Colours?
    private var defaultsObserver: NSObjectProtocol?
    private var scrollFrameObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var infoButtonStateObservation: NSKeyValueObservation?
    private var statusTextObservation: NSKeyValueObservation?

    /// The theme-derived colours, resolved for the split view's appearance.
    private struct Colours {
        let theme: SAClaudeThemeColours
        let muted, hairline, errorText, errorFill, icon, hover: NSColor
    }

    // MARK: - Attaching

    /// Restyles the status pane and the strip under it, once per split view, and keeps them in step
    /// with the editor theme and the light/dark appearance.
    ///
    /// - Parameter exportButton: The export pull-down; `nil` looks it up among `infoButton`'s siblings.
    @objc(attachToInfoSplitView:titleField:messageTextView:statusField:infoButton:exportButton:)
    static func attach(infoSplitView split: SPSplitView?, titleField: NSTextField?, messageTextView: NSTextView?,
                       statusField: NSTextField?, infoButton: NSButton?, exportButton: NSPopUpButton?) {
        guard let split, split.subviews.count > 1,
              objc_getAssociatedObject(split, &associationKey) == nil else { return }
        let styler = SAClaudeQueryInfoStyler()
        objc_setAssociatedObject(split, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.split = split
        styler.pane = split.subviews[1]
        styler.titleField = titleField
        styler.messageTextView = messageTextView
        styler.messageScrollView = messageTextView?.enclosingScrollView
        styler.statusField = statusField
        styler.infoButton = infoButton
        styler.exportButton = exportButton ?? infoButton.flatMap(findExportButton(near:))
        if let messageTextView { registry.setObject(styler, forKey: messageTextView) }

        styler.buildPane()
        styler.buildStrip()
        styler.refresh(force: true)

        styler.defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak styler] _ in
            styler?.refresh(force: false)
        }
        // Dynamic fallback colours (no theme saved yet) resolve differently in light and dark.
        styler.appearanceObservation = split.observe(\.effectiveAppearance) { [weak styler] _, _ in
            DispatchQueue.main.async { styler?.refresh(force: true) }
        }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        if let scrollFrameObserver { NotificationCenter.default.removeObserver(scrollFrameObserver) }
    }

    /// The pull-down beside the pane toggle whose menu (or a submenu) exports the query result.
    private static func findExportButton(near infoButton: NSButton) -> NSPopUpButton? {
        let action = NSSelectorFromString("exportCustomQueryResultAsFormat:")
        func contains(_ menu: NSMenu?) -> Bool {
            guard let menu else { return false }
            return menu.items.contains { $0.action == action || contains($0.submenu) }
        }
        return infoButton.superview?.subviews.lazy.compactMap { $0 as? NSPopUpButton }.first { contains($0.menu) }
    }

    // MARK: - Error state

    /// Shows the status pane in its error (`true`) or normal state: the message colour, the error
    /// block, the title dot and the strip's status text. A text view without a styler just gets
    /// red or control text.
    @objc(setErrorState:forTextView:)
    static func setErrorState(_ isError: Bool, forTextView textView: NSTextView?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { setErrorState(isError, forTextView: textView) }
            return
        }
        guard let textView else { return }
        guard let styler = registry.object(forKey: textView) else {
            textView.textColor = isError ? .systemRed : .controlTextColor
            return
        }
        styler.isError = isError
        styler.applyState()
    }

    // MARK: - Building

    private func buildPane() {
        guard let split, let pane else { return }
        paneBackground.frame = pane.bounds
        paneBackground.autoresizingMask = [.width, .height]
        pane.addSubview(paneBackground, positioned: .below, relativeTo: nil)

        if let titleField {
            titleField.font = .systemFont(ofSize: 11.5, weight: .semibold)
            titleField.stringValue = NSLocalizedString("Query status", comment: "Query tab status pane title when there is no error")
            if titleField.superview === pane {
                titleField.frame.origin.x += Self.titleShift
                let textX = titleField.frame.minX + Self.titleTextInset
                dot.frame = NSRect(x: (textX - Self.dotGap - Self.dotSize).rounded(),
                                   y: (titleField.frame.midY - Self.dotSize / 2).rounded(),
                                   width: Self.dotSize, height: Self.dotSize)
                // Pinned like the title: to the pane's top-left.
                dot.autoresizingMask = pane.isFlipped ? [.maxXMargin, .maxYMargin] : [.maxXMargin, .minYMargin]
                pane.addSubview(dot)
            }
        }

        if let scrollView = messageScrollView {
            scrollView.drawsBackground = false
            scrollView.contentView.drawsBackground = false
            if scrollView.superview === pane {
                errorBlock.isHidden = true
                pane.addSubview(errorBlock, positioned: .below, relativeTo: scrollView)
                layoutErrorBlock()
                scrollView.postsFrameChangedNotifications = true
                scrollFrameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main) { [weak self] _ in
                    self?.layoutErrorBlock()
                }
            }
        }
        if let messageTextView {
            messageTextView.drawsBackground = false
            messageTextView.font = .systemFont(ofSize: 12.5)
        }
        split.dividerStyle = .thin
    }

    /// The block covers the message's scroll view, its left edge on the text's line start (the dot's x);
    /// the error text is inset inside it (see `applyState`).
    private func layoutErrorBlock() {
        guard let scrollView = messageScrollView else { return }
        let padding = messageTextView?.textContainer?.lineFragmentPadding ?? 5
        let frame = scrollView.frame.insetBy(dx: padding, dy: 0)
        if errorBlock.frame != frame { errorBlock.frame = frame }
    }

    private func buildStrip() {
        guard let split, let container = split.superview else { return }
        // The strip is the container's area outside the split, on the side the buttons are on (below it).
        let height = container.isFlipped ? container.bounds.maxY - split.frame.maxY : split.frame.minY - container.bounds.minY
        guard height > 0 else { return }
        let stripY = container.isFlipped ? container.bounds.maxY - height : container.bounds.minY
        // As wide as the split above it.
        stripBackground.frame = NSRect(x: split.frame.minX, y: stripY, width: split.frame.width, height: height)
        stripBackground.autoresizingMask = container.isFlipped ? [.width, .minYMargin] : [.width, .maxYMargin]
        container.addSubview(stripBackground, positioned: .below, relativeTo: nil)
        // Hairline along the strip's top edge (non-flipped background view).
        stripLine.frame = NSRect(x: 0, y: height - 1, width: stripBackground.bounds.width, height: 1)
        stripLine.autoresizingMask = [.width, .minYMargin]
        stripBackground.addSubview(stripLine)

        // 28pt ghost buttons, kept on their centres horizontally and centred in the strip vertically
        // (on their old centres they would run 4pt into the split above).
        let centreY = stripY + height / 2
        func ghostFrame(for view: NSView) -> NSRect {
            NSRect(x: (view.frame.midX - Self.buttonSize / 2).rounded(), y: (centreY - Self.buttonSize / 2).rounded(),
                   width: Self.buttonSize, height: Self.buttonSize)
        }
        if let infoButton {
            infoButton.isBordered = false
            infoButton.imagePosition = .imageOnly
            if infoButton.superview === container { infoButton.frame = ghostFrame(for: infoButton) }
            SAClaudeHoverHighlighter.attach(to: infoButton)
            if let buttonSuperview = infoButton.superview {
                infoButtonStateFill.cornerRadius = SAClaudeStyle.barButtonRadius
                infoButtonStateFill.frame = infoButton.frame
                infoButtonStateFill.autoresizingMask = infoButton.autoresizingMask
                buttonSuperview.addSubview(infoButtonStateFill, positioned: .below, relativeTo: infoButton)
                updateInfoButtonStateFill()
                // SPSplitView sets the toggle's state whenever the pane collapses or expands.
                infoButtonStateObservation = infoButton.observe(\.state, options: [.initial]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.updateInfoButtonStateFill() }
                }
            }
        }
        if let exportButton {
            exportButton.isBordered = false
            (exportButton.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
            exportButton.imagePosition = .imageOnly
            if exportButton.superview === container { exportButton.frame = ghostFrame(for: exportButton) }
            exportButton.setAccessibilityLabel(NSLocalizedString("Export result", comment: "accessibility name of the ⋯ menu button in the Query tab's bottom strip, which holds Export Result"))
            SAClaudeHoverHighlighter.attach(to: exportButton)
        }

        // The status text follows the buttons and is centred in the strip like them.
        if let statusField {
            let font = NSFont.systemFont(ofSize: 11)
            statusField.font = font
            // One line tall now; a long status ends in an ellipsis instead of wrapping out of sight.
            statusField.lineBreakMode = .byTruncatingTail
            // The full text, which the truncation may hide.
            statusTextObservation = statusField.observe(\.stringValue, options: [.initial]) { field, _ in
                let text = field.stringValue
                field.toolTip = text.isEmpty ? nil : text
            }
            guard statusField.superview === container else { return }
            var frame = statusField.frame
            let buttons = [infoButton as NSView?, exportButton].compactMap { $0 }.filter { $0.superview === container }
            if let lastButtonMaxX = buttons.map(\.frame.maxX).max() {
                let newX = lastButtonMaxX + Self.statusGap
                frame.size.width += frame.minX - newX
                frame.origin.x = newX
            }
            let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
            frame.size.height = lineHeight
            frame.origin.y = (centreY - lineHeight / 2).rounded()
            statusField.frame = frame
        }
    }

    // MARK: - Colours

    /// Re-derives the colours when the editor theme changed (or always, when `force`).
    private func refresh(force: Bool) {
        guard let split else { return }
        let theme = SAClaudeThemeColours.from(defaults: .standard)
        guard force || theme != appliedTheme else { return }
        appliedTheme = theme

        var resolved: Colours?
        split.effectiveAppearance.performAsCurrentDrawingAppearance {
            let palette = SAClaudeEditorChrome.palette(text: theme.text, background: theme.background)
            resolved = Colours(theme: theme,
                               muted: SAClaudeStatusChrome.muted(theme: theme),
                               hairline: SAClaudeStatusChrome.hairline(theme: theme),
                               errorText: SAClaudeStatusChrome.errorText(theme: theme),
                               errorFill: SAClaudeStatusChrome.errorFill(theme: theme),
                               icon: palette.icon, hover: palette.hover)
        }
        guard let resolved else { return }
        colours = resolved

        paneBackground.fillColour = theme.background
        stripBackground.fillColour = theme.background
        stripLine.colourOverride = resolved.hairline
        split.customDividerColor = resolved.hairline
        // A plain needsDisplay doesn't repaint SPSplitView's divider after a theme change.
        split.setNeedsDisplay(split.bounds)
        split.layer?.setNeedsDisplay()
        messageScrollView?.appearance = SAClaudeGridChrome.scrollerAppearance(for: theme.background)
        errorBlock.edgeColour = SAClaudeStatusChrome.clay
        titleField?.textColor = resolved.muted

        if let infoButton {
            let image = SAClaudeGlyphs.image(.infoPanel, tint: resolved.icon)
            infoButton.image = image
            infoButton.alternateImage = image
            SAClaudeHoverHighlighter.setFillColour(resolved.hover, for: infoButton)
        }
        if let exportButton {
            let image = SAClaudeGlyphs.image(.more, tint: resolved.icon)
            image.accessibilityDescription = exportButton.accessibilityLabel()
            exportButton.item(at: 0)?.image = image
            SAClaudeHoverHighlighter.setFillColour(resolved.hover, for: exportButton)
        }
        applyState()
    }

    /// The colours and visibility that depend on whether the pane shows an error.
    private func applyState() {
        guard let colours else { return }
        let theme = colours.theme
        let messageColour = isError ? colours.errorText : colours.muted
        if messageTextView?.textColor != messageColour { messageTextView?.textColor = messageColour }
        let inset = isError ? Self.errorTextInset : .zero
        if let messageTextView, messageTextView.textContainerInset != inset { messageTextView.textContainerInset = inset }
        dot.fillColour = SAClaudeStatusChrome.statusDot(isError: isError, theme: theme)
        errorBlock.fillColour = colours.errorFill
        errorBlock.isHidden = !isError
        statusField?.textColor = isError ? colours.errorText : colours.muted
        infoButtonStateFill.fillColour = colours.hover
    }

    /// Shows the eye toggle's resting fill while the pane is expanded (or expanding).
    private func updateInfoButtonStateFill() {
        guard let split else { return }
        infoButtonStateFill.isHidden = split.isCollapsibleSubviewCollapsed()
    }
}

/// A rounded layer fill: the 7pt status dot before the pane's title (round by default) and the eye
/// toggle's open-state fill.
final class SAClaudeRoundedFillView: NSView {
    var fillColour: NSColor = .clear { didSet { needsDisplay = true } }
    /// `nil` rounds the view fully (half its height).
    var cornerRadius: CGFloat? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    /// Runs with the view's appearance current, so a dynamic colour resolves for light/dark.
    override func updateLayer() {
        layer?.cornerRadius = cornerRadius ?? bounds.height / 2
        layer?.backgroundColor = fillColour.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The soft clay block behind the last error: a 7pt rounded fill with a 2pt clay left edge.
final class SAClaudeErrorBlockView: NSView {
    var fillColour: NSColor = .clear { didSet { needsDisplay = true } }
    var edgeColour: NSColor = .clear { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let area = bounds.intersection(dirtyRect)
        guard !area.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        area.clip()
        let shape = NSBezierPath(roundedRect: bounds, xRadius: SAClaudeStyle.barButtonRadius, yRadius: SAClaudeStyle.barButtonRadius)
        fillColour.setFill()
        shape.fill()
        // The edge follows the rounded corners, like an inset left border.
        shape.addClip()
        edgeColour.setFill()
        NSRect(x: bounds.minX, y: bounds.minY, width: 2, height: bounds.height).fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
