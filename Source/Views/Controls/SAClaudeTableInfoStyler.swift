//
//  SAClaudeTableInfoStyler.swift
//  Sequel Ace
//
//  Restyles the Table Info (Status) tab: the editor theme's background behind the tab, the "General" and
//  "Storage" section titles over two rounded cards, SF Pro 12 labels and values inside them, round 2's ghost
//  pills on the Type / Encoding / Collation pop-ups, and the auto-increment reset pop-up as a 20pt ghost
//  refresh glyph that follows the end of the auto-increment value, the Create syntax card with its ghost
//  Copy button, and the Comments title over a Claude field with a clay focus outline. The controls are the XIB's own objects:
//  they are restyled and repositioned, never rebuilt (targets, actions, menus and bindings are untouched). The
//  one structural change: the split view's Comments pane gets a fixed height and Create syntax fills the rest (see `lockPanes`).
//
//  Layout is frame based (SAClaudeTableInfoLayout) and re-runs on the status view's frame changes, on
//  changes of the auto-increment value and of the reset control's visibility, and on every refresh. Nothing
//  here overrides `layout()` or adds constraints. If an expected control or its label is missing, nothing
//  moves: only what was found is recoloured. Colours follow the editor theme and the light/dark appearance.
//  App target only.
//

import AppKit

/// A Table Info card: rounded fill and hairline, behind the form's controls; never takes clicks.
final class SAClaudeTableInfoCardView: NSView {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var stroke: NSColor = .clear { didSet { needsDisplay = true } }
    var radius: CGFloat = SAClaudeTableInfoLayout.cardRadius { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@objc(SAClaudeTableInfoStyler) final class SAClaudeTableInfoStyler: NSObject {

    private typealias Layout = SAClaudeTableInfoLayout

    private static var associationKey: UInt8 = 0
    private static let statusViewIdentifier = NSUserInterfaceItemIdentifier("StatusTabView")

    private static let generalRowCount = 3
    private static let storageRowCount = 4
    private static let expectedPopUpCount = 3
    private static let expectedGeneralValueCount = 2
    private static let expectedStorageValueCount = 8
    /// Index, in `storageValues`, of the auto-increment value (the reset control follows it).
    private static let autoIncrementIndex = 3

    private static let titleFont = NSFont.systemFont(ofSize: 11)
    private static let labelFont = NSFont.systemFont(ofSize: 12)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private static let commentsFont = NSFont.systemFont(ofSize: 12)
    private static let commentsRadius: CGFloat = 7
    private static let commentsInset = NSSize(width: 4, height: 4)
    private static let resetSize: CGFloat = 20
    /// From the end of the auto-increment text to the reset glyph, and from the end of the shrunk value to it.
    private static let resetGap: CGFloat = 6
    private static let resetValueGap: CGFloat = 4
    private static let syntaxInset = NSSize(width: 6, height: 6)
    /// The Comments field's fixed height (about four lines); Create syntax takes the rest and scrolls.
    private static let commentsPaneHeight: CGFloat = 84
    private static let minimumSyntaxPaneHeight: CGFloat = 80

    private weak var statusView: NSView?
    private weak var splitView: NSSplitView?
    private weak var createSyntaxView: NSTextView?
    /// Strong: they are observed with KVO, so they must outlive the observation tokens (they never reference the styler).
    private var commentsView: NSTextView?
    private var popUps: [NSPopUpButton] = []
    private var generalValues: [NSTextField] = []
    private var storageValues: [NSTextField] = []
    private var resetButton: NSPopUpButton?

    /// Every static label of the form (restyled even when nothing can be moved).
    private var labels: [NSTextField] = []
    /// The XIB labels of the controls above, in the same order (all empty unless `canLayOut`).
    private var popUpLabels: [NSTextField] = []
    private var generalLabels: [NSTextField] = []
    private var storageLabels: [NSTextField] = []
    private var canLayOut = false

    /// The split view's two panes and the scroll views in them (all set only when both were found, see `findPanes`).
    private weak var syntaxPane: NSView?
    private weak var commentsPane: NSView?
    private weak var syntaxScrollView: NSScrollView?
    private weak var commentsScrollView: NSScrollView?
    private var panesReady = false

    private let background = SAClaudeEditorBarBackgroundView()
    private let generalCard = SAClaudeTableInfoCardView()
    private let storageCard = SAClaudeTableInfoCardView()
    /// The outlines of the syntax card and the comments field. An NSScrollView's own layer border doesn't draw,
    /// so each scroll view sits just inside one of these.
    private let syntaxFrame = SAClaudeTableInfoCardView()
    private let commentsFrame = SAClaudeTableInfoCardView()
    /// Keeps the comments field's square corners inside its frame's rounded outline.
    private static let commentsFieldInset: CGFloat = 3
    private let generalTitle = NSTextField(labelWithString: NSLocalizedString("General", comment: "table info : section title"))
    private let storageTitle = NSTextField(labelWithString: NSLocalizedString("Storage", comment: "table info : section title"))
    private let syntaxTitle = NSTextField(labelWithString: NSLocalizedString("Create syntax", comment: "table info : section title"))
    private let commentsTitle = NSTextField(labelWithString: NSLocalizedString("Comments", comment: "table info : section title"))
    private let copyButton = SAClaudeTableInfoCopyButton()

    private var appliedPalette: SAClaudeEditorChrome.Palette?
    private var appliedThemeText: NSColor?
    private var defaultsObserver: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var autoIncrementObservation: NSKeyValueObservation?
    private var resetHiddenObservation: NSKeyValueObservation?
    private var syntaxChangeObserver: NSObjectProtocol?
    private var commentsEditingObservers: [NSObjectProtocol] = []
    private var commentsWindowObservation: NSKeyValueObservation?
    private var firstResponderObservation: NSKeyValueObservation?
    private var commentsEditableObservation: NSKeyValueObservation?
    private var splitResizeObserver: NSObjectProtocol?
    private weak var observedWindow: NSWindow?

    // MARK: - Attaching

    /// Styles the Status tab that holds `createSyntaxView` and keeps it in step with the editor theme.
    /// Once per status view (a second call is a no-op); the status view retains the styler.
    ///
    /// - Parameters:
    ///   - popUps: Type, Encoding and Collation, in that order.
    ///   - generalValues: Created at and Updated at.
    ///   - storageValues: Number of rows, Row format, Avg. row length, Auto increment, Data size,
    ///     Max data size, Index size, Free data size.
    ///   - resetAutoIncrementButton: The reset pop-up that follows the auto-increment value.
    @objc(attachWithCreateSyntaxView:commentsView:popUps:generalValues:storageValues:resetAutoIncrementButton:)
    static func attach(createSyntaxView: NSTextView, commentsView: NSTextView, popUps: [NSPopUpButton],
                       generalValues: [NSTextField], storageValues: [NSTextField], resetAutoIncrementButton: NSPopUpButton?) {
        var candidate = createSyntaxView.superview
        while let view = candidate, view.identifier != statusViewIdentifier { candidate = view.superview }
        guard let statusView = candidate, objc_getAssociatedObject(statusView, &associationKey) == nil else { return }

        let styler = SAClaudeTableInfoStyler()
        objc_setAssociatedObject(statusView, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.statusView = statusView
        styler.popUps = popUps
        styler.generalValues = generalValues
        styler.storageValues = storageValues
        styler.resetButton = resetAutoIncrementButton
        styler.createSyntaxView = createSyntaxView
        styler.commentsView = commentsView
        styler.copyButton.syntaxProvider = { [weak styler] in styler?.createSyntaxView?.string ?? "" }

        // The XIB frames are read before anything moves.
        styler.findLabelsAndSplitView()
        styler.buildViews()
        styler.refresh(force: true)
        styler.observe()
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        if let syntaxChangeObserver { NotificationCenter.default.removeObserver(syntaxChangeObserver) }
        if let splitResizeObserver { NotificationCenter.default.removeObserver(splitResizeObserver) }
        for observer in commentsEditingObservers { NotificationCenter.default.removeObserver(observer) }
        appearanceObservation?.invalidate()
        autoIncrementObservation?.invalidate()
        resetHiddenObservation?.invalidate()
        commentsWindowObservation?.invalidate()
        firstResponderObservation?.invalidate()
        commentsEditableObservation?.invalidate()
    }

    // MARK: - Finding the form

    /// Collects the static labels, pairs every control with its XIB label and decides whether the form can be laid out.
    private func findLabelsAndSplitView() {
        guard let statusView else { return }
        let valueIDs = Set((generalValues + storageValues).map { ObjectIdentifier($0) })
        labels = statusView.subviews.compactMap { $0 as? NSTextField }.filter {
            !$0.isEditable && !$0.isHidden && !valueIDs.contains(ObjectIdentifier($0))
        }
        splitView = statusView.subviews.first { $0 is NSSplitView } as? NSSplitView

        guard popUps.count == Self.expectedPopUpCount,
              generalValues.count == Self.expectedGeneralValueCount,
              storageValues.count == Self.expectedStorageValueCount,
              splitView != nil, !statusView.isFlipped else { return }
        let controls: [NSView] = popUps + generalValues + storageValues
        guard controls.allSatisfy({ $0.superview === statusView }),
              resetButton == nil || resetButton?.superview === statusView else { return }

        let frames = labels.map(\.frame)
        let paired = controls.compactMap { control in
            Layout.labelIndex(for: control.frame, among: frames).map { labels[$0] }
        }
        // Every control needs its own label.
        guard paired.count == controls.count, Set(paired.map { ObjectIdentifier($0) }).count == paired.count else { return }
        popUpLabels = Array(paired[0..<Self.expectedPopUpCount])
        generalLabels = Array(paired[Self.expectedPopUpCount..<(Self.expectedPopUpCount + Self.expectedGeneralValueCount)])
        storageLabels = Array(paired[(Self.expectedPopUpCount + Self.expectedGeneralValueCount)...])
        canLayOut = true
        findPanes()
    }

    /// The split view's panes holding the two text views. Only when both are found, and each pane holds its
    /// scroll view directly, are the panes rearranged (the static "Create syntax:" / "Comments:" labels hidden).
    private func findPanes() {
        guard let splitView, let createSyntaxView, let commentsView else { return }
        func pane(of textView: NSTextView) -> (pane: NSView, scrollView: NSScrollView)? {
            guard let scrollView = textView.enclosingScrollView else { return nil }
            var candidate: NSView? = scrollView
            while let view = candidate, view.superview !== splitView { candidate = view.superview }
            guard let pane = candidate, pane !== scrollView, scrollView.superview === pane, !pane.isFlipped else { return nil }
            return (pane, scrollView)
        }
        guard let syntax = pane(of: createSyntaxView), let comments = pane(of: commentsView), syntax.pane !== comments.pane,
              lockPanes(syntax.pane, comments.pane) else { return }
        syntaxPane = syntax.pane
        syntaxScrollView = syntax.scrollView
        commentsPane = comments.pane
        commentsScrollView = comments.scrollView
        panesReady = true
    }

    /// The XIB lists the Comments pane first and `NSSplitView` is flipped, so Comments is on top and Create syntax
    /// below — the order kept here. The Comments pane gets a fixed height (min = max, so the divider can't be dragged)
    /// and Create syntax takes the rest, scrolling when the statement is long. Autosave is switched off so a saved
    /// divider position can't fight the fixed layout. False, with nothing changed, unless the split view stacks exactly
    /// these two panes with Comments first.
    private func lockPanes(_ syntax: NSView, _ comments: NSView) -> Bool {
        guard let splitView, !splitView.isVertical, splitView.subviews.count == 2,
              splitView.subviews[0] === comments, splitView.subviews[1] === syntax else { return false }
        splitView.autosaveName = nil
        splitView.dividerStyle = .thin
        if let split = splitView as? SPSplitView {
            split.setMinSize(Self.commentsPaneHeight, ofSubviewAt: 0)
            split.setMaxSize(Self.commentsPaneHeight, ofSubviewAt: 0)
            split.setMinSize(Self.minimumSyntaxPaneHeight, ofSubviewAt: 1)
        }
        splitView.adjustSubviews()
        fixCommentsHeight()
        return true
    }

    /// Puts the divider back under the fixed-height Comments pane (a window resize may hand it extra height).
    private func fixCommentsHeight() {
        guard let splitView, let commentsPane, commentsPane.frame.height != Self.commentsPaneHeight else { return }
        splitView.setPosition(Self.commentsPaneHeight, ofDividerAt: 0)
    }

    /// The tab's theme background always; the titles, cards and separator changes only when the form can be laid out.
    private func buildViews() {
        guard let statusView else { return }
        if canLayOut {
            for box in statusView.subviews.compactMap({ $0 as? NSBox }) where box.boxType == .separator { box.isHidden = true }
            for card in [generalCard, storageCard] {
                statusView.addSubview(card, positioned: .below, relativeTo: nil)
            }
            for title in [generalTitle, storageTitle, commentsTitle] {
                styleTitle(title)
                statusView.addSubview(title)
            }
            buildPanes()
        }
        // Round 1 left the tab views themselves unpainted (each paints its own content), and this tab has no
        // scroll view to do so: the theme background goes below everything else.
        background.frame = statusView.bounds
        background.autoresizingMask = [.width, .height]
        statusView.addSubview(background, positioned: .below, relativeTo: nil)
    }

    private func styleTitle(_ title: NSTextField) {
        title.font = Self.titleFont
        title.lineBreakMode = .byTruncatingTail
        title.autoresizingMask = []
    }

    /// Hides the panes' static labels, makes the syntax scroll view fill its pane and adds the Comments title.
    /// The panes are then sized by `layOutPanes` and, while the divider is dragged, by the autoresizing masks.
    private func buildPanes() {
        guard panesReady, let syntaxPane, let commentsPane, let syntaxScrollView, let commentsScrollView else { return }
        for pane in [syntaxPane, commentsPane] {
            for label in pane.subviews.compactMap({ $0 as? NSTextField }) where !label.isEditable { label.isHidden = true }
        }
        syntaxScrollView.autoresizingMask = [.width, .height]
        commentsScrollView.autoresizingMask = [.width, .height]
        // The Create syntax title row (title + Copy) sits at the top of its own pane, above the statement card.
        styleTitle(syntaxTitle)
        syntaxTitle.autoresizingMask = [.width, .minYMargin]
        syntaxPane.addSubview(syntaxTitle)
        copyButton.autoresizingMask = [.minXMargin, .minYMargin]
        syntaxPane.addSubview(copyButton)
        syntaxPane.addSubview(syntaxFrame, positioned: .below, relativeTo: syntaxScrollView)
        commentsFrame.radius = Self.commentsRadius
        commentsPane.addSubview(commentsFrame, positioned: .below, relativeTo: commentsScrollView)
        layOutPanes()
    }

    private func observe() {
        guard let statusView else { return }
        statusView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: statusView, queue: nil) { [weak self] _ in
            self?.onMain { $0.layOut() }
        }
        defaultsObserver = SAClaudeAppearanceChange.addObserver { [weak self] _ in
            self?.onMain { $0.refresh(force: false) }
        }
        // The Comments field's focus outline is the accent.
        SAClaudeAccent.observe(self) { styler in
            styler.updateCommentsBorder()
            if let statusView = styler.statusView { SAClaudeAccent.redisplay(statusView) }
        }
        // Dynamic fallback colours (no theme saved yet) resolve differently in light and dark.
        appearanceObservation = statusView.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.onMain { $0.refresh(force: true) }
        }
        // Dragging the divider resizes the panes: the Comments title and field follow exactly (only the panes' children move).
        if let splitView, panesReady {
            splitResizeObserver = NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: splitView, queue: nil) { [weak self] _ in
                self?.onMain { $0.layOutPanes() }
            }
        }
        observeCopyEnabled()
        observeComments()
        // The reset glyph follows the end of the auto-increment text, and only takes room while it is shown.
        if canLayOut {
            autoIncrementObservation = storageValues[Self.autoIncrementIndex].observe(\.stringValue) { [weak self] _, _ in
                self?.onMain { $0.layOut() }
            }
            resetHiddenObservation = resetButton?.observe(\.isHidden) { [weak self] _, _ in
                self?.onMain { $0.layOut() }
            }
        }
    }

    private func onMain(_ work: @escaping (SAClaudeTableInfoStyler) -> Void) {
        if Thread.isMainThread {
            work(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                if let self { work(self) }
            }
        }
    }

    // MARK: - Colours and styling

    /// Re-derives the colours when the editor theme changed (or always, when `force`), restyles every
    /// control, and lays the form out again.
    private func refresh(force: Bool) {
        guard let statusView else { return }
        var resolvedPalette: SAClaudeEditorChrome.Palette?
        var resolvedText: NSColor?
        statusView.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedPalette = SAClaudeEditorChrome.palette(from: .standard)
            resolvedText = SAClaudeThemeColours.from(defaults: .standard).text
        }
        guard let palette = resolvedPalette, let themeText = resolvedText else { return }
        // The pills' cells read these at draw time; the Content filter bar may be detached or hop to main later.
        SAClaudeFilterBarStyler.currentPalette = palette
        SAClaudeFilterBarStyler.currentThemeText = themeText
        guard force || palette != appliedPalette || themeText != appliedThemeText else { return }
        appliedPalette = palette
        appliedThemeText = themeText

        background.fillColour = palette.background
        var cardFill: NSColor?
        statusView.effectiveAppearance.performAsCurrentDrawingAppearance {
            cardFill = SAClaudeFilterChrome.cardFill(text: themeText, background: palette.background)
        }
        for card in [generalCard, storageCard] {
            card.fill = cardFill ?? palette.background
            card.stroke = palette.hairline
        }
        for title in [generalTitle, storageTitle, syntaxTitle, commentsTitle] { title.textColor = palette.icon }

        styleLabels(palette: palette)
        styleValues(themeText: themeText)
        for popUp in popUps {
            SAClaudeFilterCells.installPill(on: popUp)
            popUp.needsDisplay = true
        }
        styleResetButton(palette: palette)
        copyButton.refresh(palette: palette)
        styleSyntaxCard(palette: palette, themeText: themeText)
        styleCommentsField(palette: palette, themeText: themeText)
        styleDivider(palette: palette)
        statusView.needsDisplay = true
        layOut()
    }

    private func styleLabels(palette: SAClaudeEditorChrome.Palette) {
        for label in labels {
            label.font = Self.labelFont
            label.textColor = palette.icon
            label.alignment = .right
            label.lineBreakMode = .byTruncatingTail
            label.drawsBackground = false
            if label.stringValue.hasSuffix(":") { label.stringValue = String(label.stringValue.dropLast()) }
        }
    }

    private func styleValues(themeText: NSColor) {
        for value in generalValues + storageValues {
            value.font = Self.valueFont
            value.textColor = themeText
            value.alignment = .left
            value.lineBreakMode = .byTruncatingTail
            value.drawsBackground = false
        }
    }

    /// The reset pop-up as a borderless glyph button. Chosen over `installPill` after rendering both on macOS 27:
    /// a pull-down with `isBordered = false`, image only and no arrow (its XIB setup) draws just the first
    /// item's image, with no AppKit bezel, so nothing needs a cell swap. Its menu, tooltip and visibility are left alone.
    private func styleResetButton(palette: SAClaudeEditorChrome.Palette) {
        guard let button = resetButton else { return }
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.item(at: 0)?.image = SAClaudeGlyphs.image(.refresh, tint: palette.icon)
        SAClaudeHoverHighlighter.attach(to: button)
        SAClaudeHoverHighlighter.setFillColour(palette.hover, for: button)
        button.needsDisplay = true
    }

    /// The split view's divider in the hairline colour (a plain `needsDisplay` doesn't repaint it after a theme change).
    private func styleDivider(palette: SAClaudeEditorChrome.Palette) {
        guard panesReady, let split = splitView as? SPSplitView else { return }
        split.customDividerColor = palette.background
        split.setNeedsDisplay(split.bounds)
        split.layer?.setNeedsDisplay()
    }

    /// The Create syntax scroll view as a card: rounded, 1pt hairline. Its text view keeps the editor theme's colours and font.
    private func styleSyntaxCard(palette: SAClaudeEditorChrome.Palette, themeText: NSColor) {
        guard let scrollView = syntaxScrollView ?? createSyntaxView?.enclosingScrollView else { return }
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .none
        // The card has the page's own background, so its outline alone marks it: the brighter drop-zone stroke
        // (0.30), as the 0.08 hairline vanishes in dark themes. Drawn by the frame view behind the scroll view.
        syntaxFrame.fill = .clear
        syntaxFrame.stroke = SAClaudeFilterChrome.dropStroke(text: themeText, background: palette.background)
        // Keeps the text off the rounded corners.
        createSyntaxView?.textContainerInset = Self.syntaxInset
    }

    /// The comments text view as a Claude field: the field fill, a hairline that turns clay while it is being edited.
    private func styleCommentsField(palette: SAClaudeEditorChrome.Palette, themeText: NSColor) {
        guard let commentsView, let scrollView = commentsScrollView ?? commentsView.enclosingScrollView else { return }
        var fill: NSColor?
        statusView?.effectiveAppearance.performAsCurrentDrawingAppearance {
            fill = SAClaudeFilterChrome.fieldFill(text: themeText, background: palette.background)
        }
        let fieldFill = fill ?? palette.background
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .none
        scrollView.drawsBackground = true
        scrollView.backgroundColor = fieldFill
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = fieldFill
        commentsFrame.fill = fieldFill
        commentsView.focusRingType = .none
        commentsView.drawsBackground = true
        commentsView.backgroundColor = fieldFill
        commentsView.textColor = themeText
        commentsView.insertionPointColor = themeText
        commentsView.font = Self.commentsFont
        commentsView.textContainerInset = Self.commentsInset
        updateCommentsBorder()
    }

    /// Clay only while the comments field really is the window's first responder and editable (a view's or an absent
    /// table's comments are not), else the hairline. Begin-editing notifications alone don't count: the controller's
    /// programmatic text changes post them without any focus.
    private func updateCommentsBorder() {
        guard let palette = appliedPalette else { return }
        let editing = commentsView.map { $0.isEditable && $0.window?.firstResponder === $0 } ?? false
        commentsFrame.stroke = editing ? SAClaudeStatusChrome.clay : palette.hairline
    }

    // MARK: - Copy button and comments focus

    private func updateCopyEnabled() {
        let enabled = Layout.copyEnabled(syntax: createSyntaxView?.string ?? "")
        if copyButton.isEnabled != enabled { copyButton.isEnabled = enabled }
    }

    /// The Copy button follows whether the create syntax is empty (the controller calls `didChangeText` after every load).
    private func observeCopyEnabled() {
        updateCopyEnabled()
        guard let createSyntaxView else { return }
        syntaxChangeObserver = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: createSyntaxView, queue: nil) { [weak self] _ in
            self?.onMain { $0.updateCopyEnabled() }
        }
    }

    /// Clay outline for the comments field. Begin / end of editing alone would only colour it from the first
    /// keystroke, so the window's first responder is followed too (the delegate is never touched).
    private func observeComments() {
        guard let commentsView else { return }
        let center = NotificationCenter.default
        commentsEditingObservers = [
            center.addObserver(forName: NSText.didBeginEditingNotification, object: commentsView, queue: nil) { [weak self] _ in
                self?.onMain { $0.updateCommentsBorder() }
            },
            center.addObserver(forName: NSText.didEndEditingNotification, object: commentsView, queue: nil) { [weak self] _ in
                self?.onMain { $0.updateCommentsBorder() }
            }
        ]
        commentsEditableObservation = commentsView.observe(\.isEditable) { [weak self] _, _ in
            self?.onMain { $0.updateCommentsBorder() }
        }
        commentsWindowObservation = commentsView.observe(\.window) { [weak self] _, _ in
            // Entering a window (the tab being shown) changes what the window's edge hides: lay out again.
            self?.onMain { $0.observeFirstResponder(); $0.layOut() }
        }
        observeFirstResponder()
    }

    /// Follows the first responder of the comments view's current window (a no-op until it has one, and while unchanged).
    private func observeFirstResponder() {
        guard let commentsView, commentsView.window !== observedWindow else { return }
        firstResponderObservation = nil
        observedWindow = commentsView.window
        updateCommentsBorder()
        guard let window = commentsView.window else { return }
        firstResponderObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            self?.onMain { $0.updateCommentsBorder() }
        }
    }

    // MARK: - Layout

    /// The natural size of a field's text (the cell keeps 2pt free on each side of it).
    private func textSize(of field: NSTextField) -> NSSize {
        let size = field.cell?.cellSize ?? field.fittingSize
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func place(_ view: NSView, _ frame: NSRect) {
        if view.frame != frame { view.frame = frame }
        if !view.autoresizingMask.isEmpty { view.autoresizingMask = [] }
    }

    private func labelWidth(_ fields: [NSTextField]) -> CGFloat {
        fields.map { textSize(of: $0).width }.max() ?? 0
    }

    /// Puts `label` in the row's label column and `control` in its value column, both centred on the row.
    private func place(label: NSTextField, in row: Layout.Row) {
        let height = textSize(of: label).height
        place(label, NSRect(x: row.label.minX, y: Layout.centred(height: height, in: row.label), width: row.label.width, height: height))
    }

    private func placeValue(_ value: NSTextField, in row: Layout.Row, width: CGFloat? = nil) {
        let height = textSize(of: value).height
        place(value, NSRect(x: row.value.minX, y: Layout.centred(height: height, in: row.value),
                            width: width ?? row.value.width, height: height))
    }

    private func layOut() {
        guard canLayOut, let statusView, let splitView else { return }
        // The window's edge hides the bottom of the tab view (it sits below the window's content area in DBView.xib),
        // so lay out in the visible part, as the Query tab's strip does. Before it is in a window nothing is hidden yet.
        var area = statusView.bounds
        if statusView.window != nil {
            let visible = statusView.visibleRect
            if visible.height > 0 { area = NSRect(x: area.minX, y: visible.minY, width: area.width, height: visible.height) }
        }
        let frames = Layout.frames(in: area, generalRows: Self.generalRowCount, storageRows: Self.storageRowCount,
                                   copyButtonWidth: 0)
        observeFirstResponder()
        place(generalTitle, frames.generalTitle)
        place(storageTitle, frames.storageTitle)
        // The title row above the split view now titles its first pane, Comments.
        place(commentsTitle, NSRect(x: frames.syntaxTitle.minX, y: Layout.centred(height: Layout.titleHeight, in: frames.syntaxTitle),
                                    width: frames.syntaxTitle.width, height: Layout.titleHeight))
        place(generalCard, frames.generalCard)
        place(storageCard, frames.storageCard)
        place(splitView, frames.splitView)
        fixCommentsHeight()
        layOutPanes()
        // The controller sometimes sets an empty syntax without `didChangeText`.
        updateCopyEnabled()

        // General: pills on the left, Created / Updated on the right.
        let leftGeneral = Layout.rows(in: frames.generalCard, count: Self.generalRowCount, half: .left, labelWidth: labelWidth(popUpLabels))
        for (popUp, (label, row)) in zip(popUps, zip(popUpLabels, leftGeneral)) {
            place(label: label, in: row)
            let height = SAClaudeFilterChrome.controlHeight
            place(popUp, NSRect(x: row.value.minX, y: Layout.centred(height: height, in: row.value),
                                width: min(row.value.width, Layout.pillMaxWidth), height: height))
        }
        let rightGeneral = Layout.rows(in: frames.generalCard, count: Self.expectedGeneralValueCount, half: .right,
                                       labelWidth: labelWidth(generalLabels))
        for ((value, label), row) in zip(zip(generalValues, generalLabels), rightGeneral) {
            place(label: label, in: row)
            placeValue(value, in: row)
        }

        // Storage: the first four values on the left, the rest on the right.
        let leftStorage = Layout.rows(in: frames.storageCard, count: Self.storageRowCount, half: .left,
                                      labelWidth: labelWidth(Array(storageLabels[..<Self.storageRowCount])))
        let rightStorage = Layout.rows(in: frames.storageCard, count: Self.storageRowCount, half: .right,
                                       labelWidth: labelWidth(Array(storageLabels[Self.storageRowCount...])))
        for (index, row) in (leftStorage + rightStorage).enumerated() {
            place(label: storageLabels[index], in: row)
            if index == Self.autoIncrementIndex, let resetButton {
                placeAutoIncrement(storageValues[index], resetButton: resetButton, in: row)
            } else {
                placeValue(storageValues[index], in: row)
            }
        }
    }

    /// Fills the panes: the Comments field takes its whole pane; the Create syntax pane has a section gap, its title row
    /// (title + Copy) and the statement card below.
    private func layOutPanes() {
        guard panesReady, let syntaxPane, let commentsPane, let syntaxScrollView, let commentsScrollView else { return }
        func set(_ view: NSView, _ frame: NSRect) { if view.frame != frame { view.frame = frame } }
        set(commentsFrame, commentsPane.bounds)
        set(commentsScrollView, commentsPane.bounds.insetBy(dx: Self.commentsFieldInset, dy: Self.commentsFieldInset))
        let bounds = syntaxPane.bounds
        let rowY = bounds.maxY - Layout.sectionGap - Layout.copyRowHeight
        let copyWidth = copyButton.preferredWidth
        let row = NSRect(x: bounds.minX, y: rowY, width: bounds.width, height: Layout.copyRowHeight)
        set(copyButton, NSRect(x: row.maxX - copyWidth, y: rowY, width: copyWidth, height: Layout.copyRowHeight))
        set(syntaxTitle, NSRect(x: row.minX, y: Layout.centred(height: Layout.titleHeight, in: row),
                                width: max(row.width - copyWidth - 8, 0), height: Layout.titleHeight))
        let cardTop = rowY - Layout.titleToCard
        let card = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(cardTop - bounds.minY, 0))
        set(syntaxFrame, card)
        set(syntaxScrollView, card.insetBy(dx: 1, dy: 1))
    }

    /// The auto-increment value, with the reset glyph just after its text while the glyph is shown.
    private func placeAutoIncrement(_ value: NSTextField, resetButton: NSPopUpButton, in row: Layout.Row) {
        let size = Self.resetSize
        let textWidth = min(textSize(of: value).width, row.value.width)
        let x = max(row.value.minX, min(row.value.minX + textWidth + Self.resetGap, row.value.maxX - size))
        place(resetButton, NSRect(x: x, y: Layout.centred(height: size, in: row.value), width: size, height: size))
        let width = resetButton.isHidden ? row.value.width : max(0, x - Self.resetValueGap - row.value.minX)
        placeValue(value, in: row, width: width)
    }
}
