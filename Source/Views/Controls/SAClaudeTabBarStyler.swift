//
//  SAClaudeTabBarStyler.swift
//  Sequel Ace
//
//  Restyles the table tabs' bottom bars (Content, Structure fields and indexes,
//  Relations, Triggers) like the Query tab's strip: a 32pt strip in the editor
//  theme with a hairline on its top edge, 28pt ghost icon buttons drawn with
//  Claude glyphs, muted status text, a Claude search field, and the content
//  moved up to sit on the strip. Also restyles the Structure tab's "Indexes"
//  section header. Which glyph a button draws, and where it sits, come from
//  SAClaudeTabBarLayout. Colours follow the editor theme. App target only.
//

import AppKit

@objc(SAClaudeTabBarStyler) final class SAClaudeTabBarStyler: NSObject {

    private static var associationKey: UInt8 = 0

    private static let statusFont = NSFont.systemFont(ofSize: 11)
    private static let searchFont = NSFont.systemFont(ofSize: 12)
    /// The search field's text starts this far inside its rounded fill.
    private static let searchFieldInset: CGFloat = 6
    private static let spinnerSize: CGFloat = 16

    @objc static var stripHeight: CGFloat { SAClaudeTabBarLayout.stripHeight }

    /// A bar button, its glyph (`nil` keeps the XIB image) and what it toggles.
    private struct BarButton {
        let button: NSButton
        let glyph: SAClaudeGlyph?
    }

    private weak var container: NSView?
    private weak var status: NSTextField?
    private weak var search: NSSearchField?
    private weak var label: NSTextField?
    private var buttons: [BarButton] = []
    /// How many of `buttons` are in the left group.
    private var leftCount = 0
    private var placeholder = ""

    private let stripBackground = SAClaudeEditorBarBackgroundView()
    private let stripLine = SAClaudeDividerLine(frame: .zero)
    private let searchFill = SAClaudeConsoleFieldView(frame: .zero)
    /// Edit mode's resting fill while it is switched on, by button.
    private var stateFills: [(button: NSButton, fill: SAClaudeRoundedFillView)] = []

    private var appliedPalette: SAClaudeEditorChrome.Palette?
    private var defaultsObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var statusTextObservation: NSKeyValueObservation?
    private var stateObservations: [NSKeyValueObservation] = []

    // MARK: - Attaching

    /// Restyles the bar under `content` in `container`, once per container, and keeps it in step with
    /// the editor theme and the light/dark appearance.
    ///
    /// - Parameters:
    ///   - container: The view holding the bar's controls and the content.
    ///   - barTop: The XIB bar's top edge: controls in `container` below it are bar controls.
    ///   - content: The scroll view above the bar; its bottom edge moves to the strip's top.
    ///   - status: The bar's status text, if any (Content's row count).
    ///   - search: The bar's search field, if any (Content's column filter).
    ///   - label: A label above the content (Relations and Triggers), restyled but not moved.
    @objc(attachToContainer:barTop:content:status:search:label:)
    static func attach(container: NSView?, barTop: CGFloat, content: NSView?, status: NSTextField?,
                       search: NSSearchField?, label: NSTextField?) {
        guard let container, !container.isFlipped,
              objc_getAssociatedObject(container, &associationKey) == nil else { return }
        let styler = SAClaudeTabBarStyler()
        objc_setAssociatedObject(container, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.container = container
        styler.status = status
        styler.search = search
        styler.label = label

        styler.collectButtons(barTop: barTop, excluding: [status, search, content].compactMap { $0 })
        let spinner = container.subviews.first {
            $0 is NSProgressIndicator && $0.frame.minY < barTop && $0 !== content
        }
        styler.buildStrip()
        styler.layoutControls(spinner: spinner)
        styler.moveContent(content)
        styler.styleSearchField()
        styler.styleStatus()
        if let table = (content as? NSScrollView)?.documentView as? SAClaudeCopyTable { table.stylesCells = true }

        styler.applyColours(force: true)
        styler.defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak styler] _ in
            styler?.applyColours(force: false)
        }
        // Dynamic fallback colours (no theme saved yet) resolve differently in light and dark.
        styler.appearanceObservation = container.observe(\.effectiveAppearance) { [weak styler] _, _ in
            DispatchQueue.main.async { styler?.applyColours(force: true) }
        }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    // MARK: - Building

    /// The bar's buttons in the order the layout draws them: the left group, then the right group
    /// (buttons that stay on the right edge as the window resizes), each by x. Glyphs come from the
    /// actions in that order, so a pagination pair reads previous then next.
    private func collectButtons(barTop: CGFloat, excluding excluded: [NSView]) {
        guard let container else { return }
        let barButtons = container.subviews.compactMap { view -> NSButton? in
            guard let button = view as? NSButton, button.frame.minY < barTop,
                  !excluded.contains(where: { $0 === button }) else { return nil }
            return button
        }
        func isRight(_ button: NSButton) -> Bool { button.autoresizingMask.contains(.minXMargin) }
        let left = barButtons.filter { !isRight($0) }.sorted { $0.frame.minX < $1.frame.minX }
        let right = barButtons.filter(isRight).sorted { $0.frame.minX < $1.frame.minX }
        let ordered = left + right
        let glyphs = SAClaudeTabBarLayout.glyphs(forActions: ordered.map(Self.actionName(of:)))
        buttons = zip(ordered, glyphs).map { BarButton(button: $0, glyph: $1) }
        leftCount = left.count
    }

    /// The action's name; a pull-down with none of its own reports its first menu item's action.
    private static func actionName(of button: NSButton) -> String {
        if let action = button.action { return NSStringFromSelector(action) }
        if let popUp = button as? NSPopUpButton, let action = firstAction(in: popUp.menu) { return NSStringFromSelector(action) }
        return ""
    }

    private static func firstAction(in menu: NSMenu?) -> Selector? {
        for item in menu?.items ?? [] {
            if let action = item.action { return action }
            if let action = firstAction(in: item.submenu) { return action }
        }
        return nil
    }

    private func buildStrip() {
        guard let container else { return }
        stripBackground.frame = NSRect(x: 0, y: 0, width: container.bounds.width, height: Self.stripHeight)
        stripBackground.autoresizingMask = [.width, .maxYMargin]
        container.addSubview(stripBackground, positioned: .below, relativeTo: nil)
        // Hairline along the strip's top edge (non-flipped background view).
        stripLine.frame = NSRect(x: 0, y: Self.stripHeight - 1, width: container.bounds.width, height: 1)
        stripLine.autoresizingMask = [.width, .minYMargin]
        stripBackground.addSubview(stripLine)

        for item in buttons {
            let button = item.button
            guard let glyph = item.glyph else { continue }
            button.isBordered = false
            button.imagePosition = .imageOnly
            if let tip = button.toolTip, !tip.isEmpty { button.setAccessibilityLabel(tip) }
            if let popUp = button as? NSPopUpButton { (popUp.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow }
            SAClaudeHoverHighlighter.attach(to: button)
            if glyph == .editMode { addStateFill(behind: button) }
        }
    }

    /// Shows a rounded fill behind `button` while it is on. State changes come from the app (setState:)
    /// and from clicks, which only reach the cell, so both are observed.
    private func addStateFill(behind button: NSButton) {
        guard let container else { return }
        let fill = SAClaudeRoundedFillView(frame: button.frame)
        fill.cornerRadius = SAClaudeStyle.barButtonRadius
        fill.autoresizingMask = button.autoresizingMask
        container.addSubview(fill, positioned: .below, relativeTo: button)
        stateFills.append((button, fill))
        let update: () -> Void = { [weak button, weak fill] in
            guard let button, let fill else { return }
            fill.isHidden = button.state != .on
        }
        update()
        stateObservations.append(button.observe(\.state) { _, _ in update() })
        if let cell = button.cell { stateObservations.append(cell.observe(\.state) { _, _ in update() }) }
    }

    /// Lays the buttons, the spinner and the status text out along the strip.
    private func layoutControls(spinner: NSView?) {
        guard let container else { return }
        let width = container.bounds.width
        let size = SAClaudeTabBarLayout.buttonSize
        let buttonY = SAClaudeTabBarLayout.centredY(height: size)
        let left = Array(buttons[..<leftCount])
        let right = Array(buttons[leftCount...])

        let leftXs = SAClaudeTabBarLayout.leftXs(count: left.count)
        for (item, x) in zip(left, leftXs) {
            item.button.frame = NSRect(x: x, y: buttonY, width: size, height: size)
            item.button.autoresizingMask = [.maxXMargin, .maxYMargin]
        }
        let rightXs = SAClaudeTabBarLayout.rightXs(count: right.count, width: width)
        for (item, x) in zip(right, rightXs) {
            item.button.frame = NSRect(x: x, y: buttonY, width: size, height: size)
            item.button.autoresizingMask = [.minXMargin, .maxYMargin]
        }
        for entry in stateFills {
            entry.fill.frame = entry.button.frame
            entry.fill.autoresizingMask = entry.button.autoresizingMask
        }

        var leftEdge = (leftXs.last.map { $0 + size } ?? 0)
        if let search, search.superview === container {
            leftEdge += SAClaudeTabBarLayout.groupGap
            let height = SAClaudeTabBarLayout.searchFieldHeight
            searchFill.frame = NSRect(x: leftEdge, y: SAClaudeTabBarLayout.centredY(height: height),
                                      width: SAClaudeTabBarLayout.searchFieldWidth, height: height)
            searchFill.autoresizingMask = [.maxXMargin, .maxYMargin]
            // A click on the fill's padding focuses the field, as in the Query Console.
            searchFill.onClick = { [weak search] in search?.window?.makeFirstResponder(search) }
            container.addSubview(searchFill, positioned: .below, relativeTo: search)
            leftEdge = searchFill.frame.maxX
            search.autoresizingMask = [.maxXMargin, .maxYMargin]
        }

        var rightEdge = rightXs.first ?? (width - SAClaudeTabBarLayout.sideInset)
        if let spinner {
            let y = SAClaudeTabBarLayout.centredY(height: Self.spinnerSize)
            let x = rightEdge - SAClaudeTabBarLayout.groupGap - Self.spinnerSize
            spinner.frame = NSRect(x: x, y: y, width: Self.spinnerSize, height: Self.spinnerSize)
            spinner.autoresizingMask = [.minXMargin, .maxYMargin]
            rightEdge = x
        }

        if let status, status.superview === container {
            let font = status.font ?? Self.statusFont
            let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
            let x = leftEdge + SAClaudeTabBarLayout.groupGap
            let maxX = rightEdge - SAClaudeTabBarLayout.groupGap
            status.frame = NSRect(x: x, y: ((Self.stripHeight - lineHeight) / 2).rounded(.down),
                                  width: max(0, maxX - x), height: lineHeight)
            status.autoresizingMask = [.width, .maxYMargin]
        }
        layoutSearchField()
    }

    /// Moves the content's bottom edge to the strip's top, keeping its top where it is.
    private func moveContent(_ content: NSView?) {
        guard let content, content.frame.minY != Self.stripHeight else { return }
        var frame = content.frame
        frame.size.height = max(0, frame.maxY - Self.stripHeight)
        frame.origin.y = Self.stripHeight
        content.frame = frame
    }

    // MARK: - Search field and status text

    /// Swaps the filter field's cell for the Claude one, which draws no bezel: the rounded fill
    /// behind it replaces that.
    private func styleSearchField() {
        guard let search else { return }
        placeholder = search.placeholderString ?? ""
        SAClaudeSearchFieldCell.install(on: search)
        search.isBezeled = false
        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.font = Self.searchFont
        layoutSearchField()
    }

    /// Insets the field in its fill, as tall as its text.
    private func layoutSearchField() {
        guard let search, searchFill.superview != nil else { return }
        let fill = searchFill.frame
        let height = ceil(search.cell?.cellSize.height ?? 16)
        let frame = NSRect(x: fill.minX + Self.searchFieldInset, y: fill.minY + ((fill.height - height) / 2).rounded(.down),
                           width: max(0, fill.width - Self.searchFieldInset * 2), height: height)
        if search.frame != frame { search.frame = frame }
    }

    private func styleStatus() {
        if let status {
            status.font = Self.statusFont
            // One line tall; a long status ends in an ellipsis instead of wrapping out of sight.
            status.lineBreakMode = .byTruncatingTail
            // The full text, which the truncation may hide.
            statusTextObservation = status.observe(\.stringValue, options: [.initial]) { field, _ in
                let text = field.stringValue
                field.toolTip = text.isEmpty ? nil : text
            }
        }
        label?.font = Self.statusFont
    }

    // MARK: - Colours

    /// Re-derives the colours when the editor theme changed (or always, when `force`).
    private func applyColours(force: Bool) {
        guard let container else { return }
        var resolved: SAClaudeEditorChrome.Palette?
        container.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = SAClaudeEditorChrome.palette(from: .standard)
        }
        guard let palette = resolved, force || palette != appliedPalette else { return }
        appliedPalette = palette

        stripBackground.fillColour = palette.background
        stripLine.colourOverride = palette.hairline
        // The icon ratio is the muted ratio.
        let muted = palette.icon
        status?.textColor = muted
        label?.textColor = muted

        for item in buttons {
            let button = item.button
            if let glyph = item.glyph {
                let image = SAClaudeGlyphs.image(glyph, tint: palette.icon)
                if let popUp = button as? NSPopUpButton {
                    popUp.item(at: 0)?.image = image
                } else {
                    button.image = image
                    switch glyph {
                    case .filter: button.alternateImage = SAClaudeGlyphs.image(.filterActive, tint: palette.icon)
                    default: button.alternateImage = image
                    }
                }
            }
            SAClaudeHoverHighlighter.setFillColour(palette.hover, for: button)
        }
        for entry in stateFills { entry.fill.fillColour = palette.hover }

        if let search {
            searchFill.fillColour = palette.hover
            search.textColor = palette.buttonText
            (search.cell as? NSSearchFieldCell)?.placeholderAttributedString =
                NSAttributedString(string: placeholder, attributes: [.foregroundColor: palette.icon, .font: Self.searchFont])
            search.needsDisplay = true
        }
    }

    // MARK: - Section header

    /// Restyles the Structure tab's header above the indexes list: "Indexes" in the header font and
    /// muted colour on a theme background with a hairline on top, and a muted drag grabber.
    ///
    /// - Parameter grabber: The grabber image at the header's right; its superview is the header.
    @objc(styleSectionHeaderWithGrabber:)
    static func styleSectionHeader(grabber: NSView?) {
        guard let grabber, let header = grabber.superview,
              objc_getAssociatedObject(header, &associationKey) == nil else { return }
        let styler = SAClaudeSectionHeaderStyler(header: header, grabber: grabber)
        objc_setAssociatedObject(header, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// Styles one section header (see `SAClaudeTabBarStyler.styleSectionHeader`) and keeps its colours in
/// step with the editor theme and the light/dark appearance. Retained by the header.
private final class SAClaudeSectionHeaderStyler: NSObject {

    private weak var header: NSView?
    private weak var titleField: NSTextField?
    private weak var grabber: NSView?
    private let background = SAClaudeEditorBarBackgroundView()
    private let topLine = SAClaudeDividerLine(frame: .zero)
    private var appliedPalette: SAClaudeEditorChrome.Palette?
    private var defaultsObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?

    init(header: NSView, grabber: NSView) {
        super.init()
        self.header = header
        self.grabber = grabber
        titleField = header.subviews.lazy.compactMap { $0 as? NSTextField }.first

        background.frame = header.bounds
        background.autoresizingMask = [.width, .height]
        header.addSubview(background, positioned: .below, relativeTo: nil)
        topLine.frame = NSRect(x: 0, y: header.bounds.height - 1, width: header.bounds.width, height: 1)
        topLine.autoresizingMask = [.width, .minYMargin]
        header.addSubview(topLine)

        if let titleField {
            titleField.stringValue = NSLocalizedString("ClaudeTabBarIndexesHeader", value: "Indexes", comment: "Structure tab: header above the indexes list")
            titleField.font = SAClaudeStyle.headerFont
            let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: SAClaudeStyle.headerFont))
            // Text starts in line with the bar buttons' icons below (the cell draws it 2pt in).
            var frame = titleField.frame
            frame.origin.x = SAClaudeTabBarLayout.sideInset + (SAClaudeTabBarLayout.buttonSize - 16) / 2 - 2
            frame.size.height = lineHeight
            frame.origin.y = ((header.bounds.height - lineHeight) / 2).rounded(.down)
            titleField.frame = frame
        }
        if let imageView = grabber as? NSImageView, let image = imageView.image, !image.isTemplate,
           let template = image.copy() as? NSImage {
            template.isTemplate = true
            imageView.image = template
        }

        applyColours(force: true)
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyColours(force: false)
        }
        appearanceObservation = header.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyColours(force: true) }
        }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    private func applyColours(force: Bool) {
        guard let header else { return }
        var resolved: SAClaudeEditorChrome.Palette?
        header.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = SAClaudeEditorChrome.palette(from: .standard)
        }
        guard let palette = resolved, force || palette != appliedPalette else { return }
        appliedPalette = palette
        background.fillColour = palette.background
        topLine.colourOverride = palette.hairline
        // The icon ratio is the muted ratio.
        titleField?.textColor = palette.icon
        (grabber as? NSImageView)?.contentTintColor = palette.icon
    }
}
