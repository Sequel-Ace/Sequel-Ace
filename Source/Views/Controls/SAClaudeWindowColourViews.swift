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
/// the connection's name tinted in its colour, then "db/table"; the subtitle (the MySQL version) under it.
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
        /// The pill starts where the native title view does; the toolbar adds its own gap after the view.
        static let leadingInset: CGFloat = 4
        static let trailingInset: CGFloat = 0
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
    }

    var content: Content? {
        didSet {
            guard content != oldValue else { return }
            needsDisplay = true
            if content.map(Self.accessibilityText) != oldValue.map(Self.accessibilityText) {
                NSAccessibility.post(element: self, notification: .valueChanged)
            }
        }
    }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let nameFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let subtitleFont = NSFont.systemFont(ofSize: 11)

    /// The width the content asks for, with nothing truncated except a name past `Metrics.maxNameWidth`.
    var naturalWidth: CGFloat {
        guard let content else { return 0 }
        let row = Widths(content).row
        let subtitle = content.subtitle.isEmpty ? 0 : ceil(Self.width(content.subtitle, Self.subtitleFont))
        return Metrics.leadingInset + max(row, subtitle) + Metrics.trailingInset
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

    override func draw(_ dirtyRect: NSRect) {
        guard let content else { return }
        var widths = Widths(content)
        widths.fit(bounds.width - Metrics.leadingInset - Metrics.trailingInset)

        let lightsMid = lightsMidY(hasSubtitle: !content.subtitle.isEmpty)
        let titleBaseline = lightsMid - Metrics.titleBaselineBelowLights
        var x = Metrics.leadingInset

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

        if !content.subtitle.isEmpty {
            x = Metrics.leadingInset
            drawText(content.subtitle, font: Self.subtitleFont, colour: SAClaudeStyle.textMuted,
                     width: bounds.width - Metrics.leadingInset - Metrics.trailingInset,
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

    override func isAccessibilityElement() -> Bool { content != nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { content.map(Self.accessibilityText) }
    override func accessibilityValue() -> Any? { content.map(Self.accessibilityText) }
    /// The mouse passes through (`hitTest`), but VoiceOver still finds the title under the pointer.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { content == nil ? nil : self }
}

/// Name pill mode's title, as a leading title bar accessory: right of the traffic lights, left of the toolbar's
/// first item. Installed once per window and never removed; `hide()` takes it to zero width (AppKit keeps a hidden
/// leading accessory's width in the toolbar layout), so the toolbar gets its room back. Neither changes the title
/// bar's height. The width is the content's, capped at 30% of the window's and at 240pt, so the toolbar keeps its
/// items about as the native title (which truncates to make room) does.
final class SAConnectionNamePillAccessory: SAClaudeOwnedTitlebarAccessory {
    static let maxWidthFraction: CGFloat = 0.3
    static let maxWidth: CGFloat = 240

    private let titleView = SAConnectionNamePillTitleView(frame: NSRect(x: 0, y: 0, width: 0, height: 28))
    private var resizeObserver: NSObjectProtocol?
    /// The document window (in full screen the accessory moves to AppKit's toolbar window).
    private weak var hostWindow: NSWindow?

    /// Whether the pill shows.
    var isShowing: Bool { titleView.content != nil }

    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .leading
        // Before `view`: otherwise AppKit sizes the view to its own idea of an accessory's size in `setView:`.
        automaticallyAdjustsSize = false
        titleView.isHidden = true
        view = titleView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    /// Adds the accessory to `window` (empty: zero width until `show`), and keeps its width capped as the window
    /// resizes.
    func attach(to window: NSWindow) {
        hostWindow = window
        window.addTitlebarAccessoryViewController(self)
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: nil) { [weak self] _ in
            self?.updateWidth()
        }
    }

    func show(parts: SAWindowNamePillParts, subtitle: String, colour: NSColor, accessibilityTitle: String) {
        titleView.content = .init(parts: parts, subtitle: subtitle, colour: colour, accessibilityTitle: accessibilityTitle)
        if titleView.isHidden { titleView.isHidden = false }
        updateWidth()
    }

    func hide() {
        guard titleView.content != nil else { return }
        titleView.content = nil
        titleView.isHidden = true
        updateWidth()
    }

    private func updateWidth() {
        var width: CGFloat = 0
        if titleView.content != nil {
            let windowWidth = (hostWindow ?? view.window)?.frame.width ?? .greatestFiniteMagnitude
            width = ceil(min(titleView.naturalWidth, windowWidth * Self.maxWidthFraction, Self.maxWidth))
        }
        guard titleView.frame.width != width else { return }
        titleView.setFrameSize(NSSize(width: width, height: titleView.frame.height))
        titleView.needsDisplay = true
    }
}
