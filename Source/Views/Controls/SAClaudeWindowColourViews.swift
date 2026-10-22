//
//  SAClaudeWindowColourViews.swift
//  Sequel Ace
//
//  The window chrome that shows a connection's colour (see SAWindowTitlebarTint, which decides what shows): the
//  base class of our own title bar accessories, the 2pt line under the toolbar, and the Name pill title.
//

import AppKit

/// The base of every title bar accessory controller of ours. macOS's tab strip lives in a bottom accessory of
/// AppKit's own, which the tab bar keeps hidden (`SAClaudeWindowTabBarController.hideNativeTabBar(in:)`); the
/// hiding leaves accessories of this class alone.
class SAClaudeOwnedTitlebarAccessory: NSTitlebarAccessoryViewController {}

/// The Underline line while the tab bar is hidden: a 2pt line in the connection colour right under the toolbar, at
/// the top edge of the window's content view, in place of the hairline. While the tab bar shows, the bar draws the
/// line itself (it is then the bottom of the chrome) and this one has no colour.
///
/// Not a title bar accessory: showing or hiding one changes the title bar's height, and doing that in the same
/// tab-group change that shows or hides the tab bar left the document view's content 2pt taller than the content
/// view each time, creeping up over the toolbar. Nor a subview of AppKit's frame view: with one there, AppKit built
/// some new windows' title bars without their container, and the tab bar in them stopped laying out. The overlay
/// sits in the content view, above the document, and never changes any layout: it keeps to the top edge by its
/// autoresizing mask and only hides itself. It ignores the mouse.
final class SAConnectionColourLineOverlay: NSView {
    static let height: CGFloat = 2

    /// The line's colour, `nil` for no line. Kept unresolved and set at draw time, so an asset colour follows light
    /// and dark.
    var colour: NSColor? {
        didSet {
            guard colour != oldValue else { return }
            needsDisplay = true
            update()
        }
    }

    private weak var contentView: NSView?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: Self.height))
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Puts the line along the top edge of `window`'s content view, above everything already there.
    func attach(to window: NSWindow) {
        guard let contentView = window.contentView else { return }
        self.contentView = contentView
        let bounds = contentView.bounds
        frame = NSRect(x: bounds.minX, y: contentView.isFlipped ? bounds.minY : bounds.maxY - Self.height,
                       width: bounds.width, height: Self.height)
        autoresizingMask = contentView.isFlipped ? [.width, .maxYMargin] : [.width, .minYMargin]
        contentView.addSubview(self, positioned: .above, relativeTo: nil)
        update()
    }

    /// Shows the line when it has a colour, kept above any view added to the content view since.
    private func update() {
        let shouldHide = colour == nil
        if isHidden != shouldHide { isHidden = shouldHide }
        if !shouldHide, let contentView, contentView.subviews.last !== self {
            contentView.addSubview(self, positioned: .above, relativeTo: nil)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let colour else { return }
        colour.setFill()
        bounds.intersection(dirtyRect).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Name pill

/// The window title in Name pill mode, in place of the native title: the `.spf` file prefix, a pill with a dot and
/// the connection's name tinted in its colour, then "db/table"; the subtitle (the MySQL version) under it, or after
/// it on the same line ("– MySQL 8.4") when the title bar is too short for a second line (the toolbar hidden).
///
/// Frames only: everything is measured and drawn here. Colours are resolved at draw time, so the view follows light
/// and dark. It ignores the mouse, so the title bar under it still drags and zooms the window.
final class SAConnectionNamePillTitleView: NSView {
    struct Content: Equatable {
        var parts: SAWindowNamePillParts
        var subtitle: String
        var colour: NSColor
        var accessibilityTitle: String
    }

    enum Metrics {
        /// In the accessory: the pill starts where the native title view does; the toolbar adds its own gap after
        /// the view.
        static let accessoryInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        /// Over the native title view (which starts where the accessory's pill does): 8pt clear of the first
        /// toolbar item, whose view starts 5pt inside the title view's frame. In full screen the left inset is where
        /// the native title's text starts instead (`SAConnectionNamePillAccessory`).
        static let nativeTitleInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 13)
        /// How far a text field's text starts inside its title rect (the cell's line fragment padding).
        static let textFieldTextInset: CGFloat = 2
        static let pillHeight: CGFloat = 20
        static let pillRadius: CGFloat = 7
        static let pillPadding: CGFloat = 8
        static let dotSize: CGFloat = 8
        static let dotGap: CGFloat = 6
        static let maxNameWidth: CGFloat = 140
        static let restGap: CGFloat = 6
        /// What "db/table" keeps before the name starts giving way, and the least the name keeps.
        static let restFloor: CGFloat = 48
        static let nameFloor: CGFloat = 40
        /// Where the native title's and subtitle's text sits, below the traffic lights' centre (their baselines,
        /// measured against the native title in the same window: 5 and 19, less the half point the text field
        /// draws above its baseline).
        static let titleBaselineBelowLights: CGFloat = 4.5
        static let subtitleBaselineBelowLights: CGFloat = 18.5
        /// The native one-line title (a short title bar, the subtitle inline) sits a point higher.
        static let inlineTitleBaselineBelowLights: CGFloat = 3.5
    }

    /// The room kept clear before and after the content (`Metrics`, by where the view is hosted).
    var insets = Metrics.accessoryInsets {
        didSet { needsDisplay = true }
    }
    private var leadingInset: CGFloat { insets.left }
    private var trailingInset: CGFloat { insets.right }

    /// Whether VoiceOver sees this view. Off over the native title, whose (transparent) fields already carry the
    /// same text.
    var exposesAccessibility = true

    /// Called when the view leaves or joins a window (AppKit discarding or moving the view it is in).
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }

    /// Called when the view's height changes (the toolbar shown or hidden) or the subtitle's place no longer
    /// matches the one the width was measured for, so the accessory can re-measure.
    var onPlacementChange: (() -> Void)?
    /// The subtitle placement `naturalWidth` was last measured with.
    private var measuredPlacement: SAWindowNamePillSubtitlePlacement?

    var content: Content? {
        didSet {
            guard content != oldValue else { return }
            needsDisplay = true
            if exposesAccessibility, content.map(Self.accessibilityText) != oldValue.map(Self.accessibilityText) {
                NSAccessibility.post(element: self, notification: .valueChanged)
            }
        }
    }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let nameFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let subtitleFont = NSFont.systemFont(ofSize: 11)
    /// The subtitle on the title's line: the title's size, regular, muted.
    private static let inlineSubtitleFont = NSFont.systemFont(ofSize: 13)

    /// Where the subtitle goes in the title bar as it is now: under the title when the second line fits above the
    /// bar's bottom, else after the title on its line (a short title bar: the toolbar hidden).
    var subtitlePlacement: SAWindowNamePillSubtitlePlacement {
        guard let content, !content.subtitle.isEmpty else { return .below }
        let centre = lightsMidY(hasSubtitle: true)
        return .forSpace(belowCentre: centre - bounds.minY, baselineBelowCentre: Metrics.subtitleBaselineBelowLights,
                         descent: ceil(-Self.subtitleFont.descender))
    }

    /// The inline subtitle's text and the gap before it (a space after "db/table", the rest gap after the pill).
    private static func inlineSubtitle(_ content: Content) -> (text: String, gap: CGFloat, width: CGFloat) {
        let text = SAWindowNamePillSubtitlePlacement.inlineText(content.subtitle)
        let gap = content.parts.rest.isEmpty ? Metrics.restGap : ceil(width(" ", inlineSubtitleFont))
        return (text, gap, ceil(width(text, inlineSubtitleFont)))
    }

    /// The room the inline subtitle takes after the title row (its gap and text), 0 when it goes under the title.
    var inlineSubtitleWidth: CGFloat {
        guard let content, !content.subtitle.isEmpty, subtitlePlacement == .inline else { return 0 }
        let inline = Self.inlineSubtitle(content)
        return inline.gap + inline.width
    }

    /// The width the content asks for, with nothing truncated except a name past `Metrics.maxNameWidth`.
    var naturalWidth: CGFloat {
        guard let content else { return 0 }
        let row = Widths(content).row
        let placement = subtitlePlacement
        measuredPlacement = placement
        if content.subtitle.isEmpty { return leadingInset + row + trailingInset }
        if placement == .inline {
            let inline = Self.inlineSubtitle(content)
            return leadingInset + row + inline.gap + inline.width + trailingInset
        }
        let subtitle = ceil(Self.width(content.subtitle, Self.subtitleFont))
        return leadingInset + max(row, subtitle) + trailingInset
    }

    /// The widths of the title row's pieces; `fit(_:)` shrinks them to a width.
    private struct Widths {
        var prefix: CGFloat
        var name: CGFloat
        var rest: CGFloat
        let hasRest: Bool

        init(_ content: Content) {
            prefix = content.parts.prefix.isEmpty ? 0 : ceil(SAConnectionNamePillTitleView.width(content.parts.prefix, SAConnectionNamePillTitleView.titleFont))
            name = min(ceil(SAConnectionNamePillTitleView.width(content.parts.name, SAConnectionNamePillTitleView.nameFont)), Metrics.maxNameWidth)
            rest = content.parts.rest.isEmpty ? 0 : ceil(SAConnectionNamePillTitleView.width(content.parts.rest, SAConnectionNamePillTitleView.titleFont))
            hasRest = !content.parts.rest.isEmpty
        }

        var pill: CGFloat { Metrics.pillPadding + Metrics.dotSize + Metrics.dotGap + name + Metrics.pillPadding }
        var row: CGFloat { prefix + pill + (hasRest ? Metrics.restGap + rest : 0) }

        /// Gives way, in order: "db/table" down to its floor, the name down to its floor, the file prefix, then the
        /// rest of "db/table".
        mutating func fit(_ available: CGFloat) {
            var over = row - available
            func shrink(_ value: inout CGFloat, to floor: CGFloat) {
                guard over > 0 else { return }
                let cut = min(over, max(0, value - floor))
                value -= cut
                over -= cut
            }
            shrink(&rest, to: min(rest, Metrics.restFloor))
            shrink(&name, to: min(name, Metrics.nameFloor))
            shrink(&prefix, to: 0)
            shrink(&rest, to: 0)
        }
    }

    private static func width(_ string: String, _ font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    private static func attributes(_ font: NSFont, _ colour: NSColor, _ truncation: NSLineBreakMode) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = truncation
        return [.font: font, .foregroundColor: colour, .paragraphStyle: paragraph]
    }

    /// The pill's fill, dot and name colours for the window's favourite colour: the palette's when it is one of
    /// the vivid colours, else the colour itself for the dot, itself at the tint alpha for the pill, and the primary
    /// text colour for the name.
    private func pillColours(for colour: NSColor) -> (tint: NSColor, dot: NSColor, ink: NSColor) {
        if let name = colour.colorNameComponentIfNamed, let vivid = SAVividColour(assetName: name) {
            return (vivid.tintColour, vivid.fillColour, vivid.inkColour)
        }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let alpha = dark ? SAVividColour.tintAlphaDark : SAVividColour.tintAlphaLight
        return (colour.withAlphaComponent(alpha), colour, SAClaudeStyle.textPrimary)
    }

    /// The traffic lights' vertical centre, which the native title and subtitle hang from; without them (full
    /// screen) a centre that puts the two lines in the middle of the view.
    private func lightsMidY(hasSubtitle: Bool) -> CGFloat {
        if let button = window?.standardWindowButton(.closeButton), button.window === window, !button.isHidden {
            let mid = convert(NSPoint(x: 0, y: button.bounds.midY), from: button).y
            if mid > bounds.minY, mid < bounds.maxY { return mid }
        }
        // The pill spans about mid + 10 ... mid - 10 and the subtitle reaches about mid - 22, so the pair is centred 6pt up.
        return bounds.midY + (hasSubtitle ? 6 : 0)
    }

    override var isFlipped: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        let heightChanged = newSize.height != frame.height
        super.setFrameSize(newSize)
        if heightChanged {
            needsDisplay = true
            onPlacementChange?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let content else { return }
        let placement = subtitlePlacement
        if let measuredPlacement, measuredPlacement != placement {
            // The traffic lights moved after the height did: re-measure once this pass is over.
            RunLoop.main.perform { [weak self] in self?.onPlacementChange?() }
        }
        let inline = !content.subtitle.isEmpty && placement == .inline
        let inlineSubtitle = Self.inlineSubtitle(content)
        var widths = Widths(content)
        let available = bounds.width - leadingInset - trailingInset
        // Inline, the title row leaves the subtitle its room (the accessory's cap is the row's plus the subtitle's).
        widths.fit(inline ? max(0, available - inlineSubtitle.gap - inlineSubtitle.width) : available)

        let lightsMid = lightsMidY(hasSubtitle: !content.subtitle.isEmpty && !inline)
        let titleBaseline = lightsMid - (inline ? Metrics.inlineTitleBaselineBelowLights : Metrics.titleBaselineBelowLights)
        var x = leadingInset

        /// One line of text with its baseline at `baseline`, truncated to `width`.
        func drawText(_ text: String, font: NSFont, colour: NSColor, width: CGFloat, baseline: CGFloat,
                      truncation: NSLineBreakMode = .byTruncatingTail) {
            guard width > 0 else { return }
            let height = ceil(font.ascender - font.descender + font.leading)
            let rect = NSRect(x: x, y: baseline + font.ascender - height, width: width, height: height)
            (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                    attributes: Self.attributes(font, colour, truncation))
        }

        if widths.prefix > 0 {
            drawText(content.parts.prefix, font: Self.titleFont, colour: SAClaudeStyle.textPrimary, width: widths.prefix, baseline: titleBaseline)
            x += widths.prefix
        }

        // The pill and its name are centred on the title's capitals, level with the title text.
        let rowMid = titleBaseline + Self.titleFont.capHeight / 2
        let colours = pillColours(for: content.colour)
        let pillRect = NSRect(x: x, y: rowMid - Metrics.pillHeight / 2, width: widths.pill, height: Metrics.pillHeight)
        colours.tint.setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: Metrics.pillRadius, yRadius: Metrics.pillRadius).fill()
        let dotRect = NSRect(x: pillRect.minX + Metrics.pillPadding, y: rowMid - Metrics.dotSize / 2, width: Metrics.dotSize, height: Metrics.dotSize)
        colours.dot.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        x = dotRect.maxX + Metrics.dotGap
        drawText(content.parts.name, font: Self.nameFont, colour: colours.ink, width: widths.name,
                 baseline: rowMid - Self.nameFont.capHeight / 2)
        x = pillRect.maxX

        if widths.hasRest {
            x += Metrics.restGap
            drawText(content.parts.rest, font: Self.titleFont, colour: SAClaudeStyle.textPrimary, width: widths.rest,
                     baseline: titleBaseline, truncation: .byTruncatingMiddle)
        }

        if inline {
            // After the title on its line, in what room the title leaves.
            x = (widths.hasRest ? x + widths.rest : x) + inlineSubtitle.gap
            drawText(inlineSubtitle.text, font: Self.inlineSubtitleFont, colour: SAClaudeStyle.textMuted,
                     width: min(inlineSubtitle.width, bounds.width - trailingInset - x), baseline: titleBaseline)
        } else if !content.subtitle.isEmpty {
            x = leadingInset
            drawText(content.subtitle, font: Self.subtitleFont, colour: SAClaudeStyle.textMuted,
                     width: bounds.width - leadingInset - trailingInset,
                     baseline: lightsMid - Metrics.subtitleBaselineBelowLights)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Accessibility

    /// The window title, then the subtitle (the native title bar shows both).
    private static func accessibilityText(_ content: Content) -> String {
        content.subtitle.isEmpty ? content.accessibilityTitle : content.accessibilityTitle + ", " + content.subtitle
    }

    override func isAccessibilityElement() -> Bool { exposesAccessibility && content != nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { content.map(Self.accessibilityText) }
    override func accessibilityValue() -> Any? { content.map(Self.accessibilityText) }
    /// The mouse passes through (`hitTest`), but VoiceOver still finds the title under the pointer.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { exposesAccessibility && content != nil ? self : nil }
}

/// Name pill mode's title. Where it is drawn depends on the toolbar (`SAWindowNamePillHost`):
///
/// - Toolbar shown: over AppKit's native title view (in the window, or in full screen in AppKit's toolbar window),
///   which stays visible with its own text made transparent and its document proxy off (the `.spf` file's icon is
///   not revealed under the pill and cannot be dragged), so a drag on the pill moves the window. In the
///   unified toolbar that view is the flexible leading area that takes the spare room and keeps the items packed to
///   the trailing side; hiding it would hand the room to the toolbar's flexible spaces and slide the database picker
///   and the view buttons left. Drawn over it, the pill leaves every item exactly where it is without the pill, and
///   gets the room the native title has (it truncates within it, as the native title does). The pill view rides in
///   the title view (frame and full screen follow it); this accessory stays installed at zero width. VoiceOver reads
///   the native title's fields, which carry the same text.
/// - Toolbar hidden (no items to keep in place), or no native title view to be found (looked for again only when the
///   toolbar is shown or hidden, full screen changes or the window becomes key or main, so a title change never toggles
///   the native title): as a leading title bar accessory with the native title hidden, right of the traffic lights.
///   Its width is the content's, capped at 30% of the window's and at 240pt; in a short title bar the subtitle follows
///   the title on its line and its width comes on top of that cap, within 60% of the window. The width is measured
///   again when the bar's height changes.
///
/// Installed once per window and never removed; with nothing to show, or while the pill is drawn over the native
/// title, it is at zero width (AppKit keeps a hidden leading accessory's width in the toolbar layout). Neither host
/// changes the title bar's height. The window's `titleVisibility` is set here, by the host.
final class SAConnectionNamePillAccessory: SAClaudeOwnedTitlebarAccessory {
    static let maxWidthFraction: CGFloat = 0.3
    static let maxWidth: CGFloat = 240
    static let maxInlineWidthFraction: CGFloat = 0.6
    /// AppKit's title view in a unified toolbar (private; looked up by name, with the accessory as the fallback).
    private static let nativeTitleViewClassName = "NSToolbarTitleView"

    /// The pill in the accessory (toolbar hidden).
    private let titleView = SAConnectionNamePillTitleView(frame: NSRect(x: 0, y: 0, width: 0, height: 28))
    /// The pill over the native title view (toolbar shown).
    private let overlayView = SAConnectionNamePillTitleView(frame: .zero)
    private var content: SAConnectionNamePillTitleView.Content?
    /// The native title view's own subviews this made transparent, with their alpha before, to restore.
    private let dimmedViews = NSMapTable<NSView, NSNumber>.weakToStrongObjects()
    /// The native title view's document proxy views this hid, with their hidden state before, to restore.
    private let hiddenViews = NSMapTable<NSView, NSNumber>.weakToStrongObjects()
    /// The native title view's document-drag recognizers this turned off (all were on), to turn back on.
    private let disabledRecognizers = NSHashTable<NSGestureRecognizer>.weakObjects()
    /// The toolbar and full-screen state a lookup of the native title view last failed in: not tried again (with
    /// the title made visible and the bar laid out) until one of them changes.
    private var failedLookup: LookupState?
    private struct LookupState: Equatable {
        let toolbarVisible: Bool
        let fullScreen: Bool
    }
    private var resizeObserver: NSObjectProtocol?
    private var fullScreenObservers: [NSObjectProtocol] = []
    private var keyObservers: [NSObjectProtocol] = []
    private var toolbarVisibilityObservation: NSKeyValueObservation?
    private weak var observedToolbar: NSToolbar?
    /// The document window (in full screen the toolbar moves to AppKit's toolbar window).
    private weak var hostWindow: NSWindow?

    /// Where the pill is drawn now.
    private(set) var host = SAWindowNamePillHost.none

    /// Whether the pill shows.
    var isShowing: Bool { content != nil }

    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .leading
        // Before `view`: otherwise AppKit sizes the view to its own idea of an accessory's size in `setView:`.
        automaticallyAdjustsSize = false
        titleView.isHidden = true
        view = titleView
        // Toolbar shown or hidden: the subtitle may move between its own line and the title's.
        titleView.onPlacementChange = { [weak self] in self?.updateWidth() }
        overlayView.insets = SAConnectionNamePillTitleView.Metrics.nativeTitleInsets
        overlayView.autoresizingMask = [.width, .height]
        overlayView.exposesAccessibility = false
        // AppKit discarded the title view it was in (or moved it between windows): find the current one.
        overlayView.onWindowChange = { [weak self] in
            guard let self, self.host == .nativeTitle, self.overlayView.window == nil else { return }
            RunLoop.main.perform { [weak self] in self?.apply() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        fullScreenObservers.forEach { NotificationCenter.default.removeObserver($0) }
        keyObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Adds the accessory to `window` (empty: zero width until `show`), keeps its width capped as the window
    /// resizes, and follows the toolbar being shown or hidden.
    func attach(to window: NSWindow) {
        hostWindow = window
        window.addTitlebarAccessoryViewController(self)
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: nil) { [weak self] _ in
            self?.updateWidth()
        }
        observeToolbar(of: window)
        // In full screen the toolbar, and the title view with it, lives in AppKit's toolbar window.
        fullScreenObservers = [NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
                               NSWindow.didExitFullScreenNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.reapplyAfterChromeChange()
            }
        }
        // A lookup that failed for a passing reason (say, a background tab in full screen whose toolbar window was
        // not attached yet) is not stuck until the next chrome change: the window coming to the front retries it.
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.retryAfterBecomingKey()
            }
        }
    }

    /// The window became key or main: forget a failed lookup and, while the pill shows in the accessory with the
    /// toolbar shown (a lookup failed) or over a title view that has gone, apply again, at once and once AppKit has
    /// settled. A pill already over a live title view, or in the accessory because the toolbar is hidden, is left
    /// alone, so a key change costs nothing.
    private func retryAfterBecomingKey() {
        failedLookup = nil
        let lookupFailed = host == .accessory && hostWindow?.toolbar?.isVisible == true
        let titleViewGone = host == .nativeTitle && overlayView.window == nil
        guard content != nil, lookupFailed || titleViewGone else { return }
        reapplyAfterChromeChange()
    }

    /// The toolbar was shown or hidden, or full screen changed: look for the title view again, at once and once
    /// AppKit has settled.
    private func reapplyAfterChromeChange() {
        failedLookup = nil
        apply()
        RunLoop.main.perform { [weak self] in
            self?.failedLookup = nil
            self?.apply()
        }
    }

    func show(parts: SAWindowNamePillParts, subtitle: String, colour: NSColor, accessibilityTitle: String) {
        content = .init(parts: parts, subtitle: subtitle, colour: colour, accessibilityTitle: accessibilityTitle)
        apply()
    }

    /// No pill: the native title, fully drawn.
    func hide() {
        content = nil
        apply()
    }

    /// Puts the content in the host the toolbar calls for and sets the native title's visibility to match.
    private func apply() {
        guard let window = hostWindow else { return }
        observeToolbar(of: window)
        let toolbarVisible = window.toolbar?.isVisible == true
        let native = content != nil && toolbarVisible
            ? nativeTitleView(in: window, state: LookupState(toolbarVisible: true, fullScreen: window.styleMask.contains(.fullScreen)))
            : nil
        host = .choose(showsPill: content != nil, toolbarVisible: toolbarVisible, nativeTitleAvailable: native != nil)

        if host == .nativeTitle, let native {
            drawOver(native)
        } else {
            removeOverlay()
        }

        let accessoryContent = host == .accessory ? content : nil
        titleView.content = accessoryContent
        if titleView.isHidden != (accessoryContent == nil) { titleView.isHidden = accessoryContent == nil }
        updateWidth()

        let visibility: NSWindow.TitleVisibility = host.hidesNativeTitle ? .hidden : .visible
        if window.titleVisibility != visibility { window.titleVisibility = visibility }
    }

    /// The pill over `native`, filling it, with the title view's own text transparent (its room in the toolbar stays)
    /// and its document proxy off: the proxy's view hidden and the title view's document-drag recognizer disabled, so a
    /// drag on the pill goes to the toolbar's window-drag recognizer and moves the window rather than dragging the
    /// `.spf` file out of an invisible icon.
    private func drawOver(_ native: NSView) {
        if overlayView.superview !== native {
            removeOverlay()
            overlayView.frame = native.bounds
            native.addSubview(overlayView, positioned: .above, relativeTo: nil)
        }
        // In full screen (AppKit's toolbar window, no traffic lights before the title) the pill starts where the
        // native title's text does, not at the view's edge, which there is right by the screen's.
        var insets = SAConnectionNamePillTitleView.Metrics.nativeTitleInsets
        if native.window !== hostWindow, let start = Self.nativeTextStart(in: native, skipping: overlayView) {
            insets.left = start
        }
        if overlayView.insets.left != insets.left || overlayView.insets.right != insets.right { overlayView.insets = insets }
        overlayView.content = content
        // Every pass: AppKit may add or replace the title's views (a title or subtitle change).
        for subview in native.subviews where subview !== overlayView {
            if Self.isDocumentProxy(subview) {
                if !subview.isHidden {
                    if hiddenViews.object(forKey: subview) == nil { hiddenViews.setObject(NSNumber(value: false), forKey: subview) }
                    subview.isHidden = true
                }
            } else if subview.alphaValue != 0 {
                if dimmedViews.object(forKey: subview) == nil { dimmedViews.setObject(NSNumber(value: Double(subview.alphaValue)), forKey: subview) }
                subview.alphaValue = 0
            }
        }
        for recognizer in native.gestureRecognizers where recognizer.isEnabled && Self.isDocumentDrag(recognizer) {
            recognizer.isEnabled = false
            disabledRecognizers.add(recognizer)
        }
    }

    /// Takes the pill off the native title and gives its views back what they had.
    private func removeOverlay() {
        for case let view? in dimmedViews.keyEnumerator().allObjects.map({ $0 as? NSView }) {
            if let alpha = dimmedViews.object(forKey: view) { view.alphaValue = CGFloat(alpha.doubleValue) }
        }
        dimmedViews.removeAllObjects()
        for case let view? in hiddenViews.keyEnumerator().allObjects.map({ $0 as? NSView }) {
            if let hidden = hiddenViews.object(forKey: view) { view.isHidden = hidden.boolValue }
        }
        hiddenViews.removeAllObjects()
        disabledRecognizers.allObjects.forEach { $0.isEnabled = true }
        disabledRecognizers.removeAllObjects()
        overlayView.content = nil
        if overlayView.superview != nil { overlayView.removeFromSuperview() }
    }

    /// Where the native title's text starts in `native`: its first text field with text (the title, then the
    /// subtitle; both start at the same x), plus the cell's text inset. Nil when there is none.
    private static func nativeTextStart(in native: NSView, skipping overlay: NSView) -> CGFloat? {
        var queue = native.subviews.filter { $0 !== overlay }
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let field = view as? NSTextField, !field.stringValue.isEmpty, !field.isHidden {
                let titleRect = field.cell?.titleRect(forBounds: field.bounds) ?? field.bounds
                return field.convert(titleRect, to: native).minX + SAConnectionNamePillTitleView.Metrics.textFieldTextInset
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// The title view's document proxy view (where AppKit reveals the represented file's icon on hover).
    private static func isDocumentProxy(_ view: NSView) -> Bool {
        NSStringFromClass(type(of: view)).contains("DocumentProxy")
    }

    /// The title view's recognizer that drags the represented file out of its proxy icon.
    private static func isDocumentDrag(_ recognizer: NSGestureRecognizer) -> Bool {
        NSStringFromClass(type(of: recognizer)).contains("ProxyDocumentDrag")
    }

    /// The window's native title view: the one the pill is in while it is still in a window (it keeps the same view
    /// across title changes, resizes and full screen), else found in the title bar or, in full screen, AppKit's
    /// toolbar window (a child window), after making the title visible and laying the bar out (AppKit makes a new view
    /// when the title or the toolbar shows again). Nil when there is none, for the accessory to take over; a failed
    /// lookup is not repeated in the same `state`.
    private func nativeTitleView(in window: NSWindow, state: LookupState) -> NSView? {
        if let current = overlayView.superview, current.window != nil, Self.isNativeTitleView(current) {
            return current
        }
        guard failedLookup != state else { return nil }
        if window.titleVisibility != .visible { window.titleVisibility = .visible }
        let roots = ([window] + (window.childWindows ?? [])).compactMap { $0.contentView?.superview }
        for pass in 0..<2 {
            for root in roots {
                if let found = Self.findNativeTitleView(in: root, skipping: window.contentView) {
                    failedLookup = nil
                    return found
                }
            }
            if pass == 0 { roots.forEach { $0.layoutSubtreeIfNeeded() } }
        }
        failedLookup = state
        return nil
    }

    private static func isNativeTitleView(_ view: NSView) -> Bool {
        NSStringFromClass(type(of: view)) == nativeTitleViewClassName
    }

    /// Searches a frame view, skipping the document window's content (the full-screen toolbar window's content is
    /// the toolbar itself).
    private static func findNativeTitleView(in frameView: NSView, skipping documentContent: NSView?) -> NSView? {
        var stack = frameView.subviews.filter { $0 !== documentContent }
        while let view = stack.popLast() {
            if isNativeTitleView(view) { return view }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// Re-applies when the toolbar is shown or hidden (View ▸ Show/Hide Toolbar), at once and once AppKit has
    /// settled, so the pill changes host without the native title showing in between.
    private func observeToolbar(of window: NSWindow) {
        guard let toolbar = window.toolbar, toolbar !== observedToolbar else { return }
        observedToolbar = toolbar
        toolbarVisibilityObservation = toolbar.observe(\.isVisible) { [weak self] _, _ in
            self?.reapplyAfterChromeChange()
        }
    }

    private func updateWidth() {
        var width: CGFloat = 0
        if titleView.content != nil {
            let windowWidth = (hostWindow ?? view.window)?.frame.width ?? .greatestFiniteMagnitude
            // The title row keeps its cap; a subtitle on its line (a short title bar, no toolbar to share it with)
            // comes on top, within `maxInlineWidthFraction` of the window.
            let natural = titleView.naturalWidth
            let rowCap = min(windowWidth * Self.maxWidthFraction, Self.maxWidth)
            let inline = titleView.inlineSubtitleWidth
            width = ceil(min(natural, rowCap + inline, windowWidth * Self.maxInlineWidthFraction))
        }
        guard titleView.frame.width != width else { return }
        titleView.setFrameSize(NSSize(width: width, height: titleView.frame.height))
        titleView.needsDisplay = true
    }
}
