//
//  SAClaudeFilterBarStyler.swift
//  Sequel Ace
//
//  Restyles the Content tab's filter bar: the container gets the editor
//  theme's background with a hairline along its bottom edge, the rule
//  editor's rows are 32pt tall and show that background with a hairline
//  between rows instead of AppKit's own row backgrounds. Colours follow the
//  editor theme and the light/dark appearance. App target only.
//
//  Rows: on macOS 26 and later each rule row (a private slice view) paints
//  itself through a private NSBannerView subview, and the editor's slice
//  holder has one more behind all rows. Hiding those painters (public
//  `isHidden`, nothing private is called) leaves the rows transparent, so
//  the clip view's theme background shows through; the row controls, the
//  +/- buttons, clicks, drags and the drag-hover highlight are untouched.
//  Where a row has no such painter (older macOS, or a future AppKit that
//  draws rows differently) the row is left exactly as AppKit draws it.
//

import AppKit

@objc(SAClaudeFilterBarStyler) final class SAClaudeFilterBarStyler: NSObject {

    private static var associationKey: UInt8 = 0
    private static let rowHairlineIdentifier = NSUserInterfaceItemIdentifier("SAClaudeFilterRowHairline")
    /// The private view AppKit paints a rule row's background with; `nil` where it doesn't exist.
    private static let rowPainterClass: AnyClass? = NSClassFromString("NSBannerView")

    /// The editor theme's palette, as last derived by a styler. The filter bar's cells have no
    /// stored properties and read it at draw time.
    private(set) static var currentPalette = SAClaudeEditorChrome.palette(from: .standard)
    /// The editor theme's text colour, as last derived by a styler (read at draw time like `currentPalette`).
    private(set) static var currentThemeText = SAClaudeThemeColours.from(defaults: .standard).text

    private weak var ruleEditor: NSRuleEditor?
    private weak var container: NSView?
    /// Kept for the controls' styling.
    private(set) weak var rootConjunctionPopUp: NSPopUpButton?
    private(set) weak var applyButton: NSButton?
    private(set) weak var addFilterButton: NSButton?

    private let background = SAClaudeEditorBarBackgroundView()
    private let bottomLine = SAClaudeDividerLine(frame: .zero)

    private var appliedPalette: SAClaudeEditorChrome.Palette?
    private var defaultsObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?

    // MARK: - Attaching

    /// Styles the filter container, the rule editor's surface (clip view background, row backgrounds),
    /// sets the row height to `SAClaudeFilterChrome.rowHeight`, and keeps everything in step with the
    /// editor theme. Once per rule editor; the rule editor retains the styler.
    @objc(attachToRuleEditor:rootConjunctionPopUp:applyButton:addFilterButton:)
    static func attach(ruleEditor: NSRuleEditor?, rootConjunctionPopUp: NSPopUpButton?, applyButton: NSButton?, addFilterButton: NSButton?) {
        guard let ruleEditor, objc_getAssociatedObject(ruleEditor, &associationKey) == nil else { return }
        let styler = SAClaudeFilterBarStyler()
        objc_setAssociatedObject(ruleEditor, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        styler.ruleEditor = ruleEditor
        styler.rootConjunctionPopUp = rootConjunctionPopUp
        styler.applyButton = applyButton
        styler.addFilterButton = addFilterButton

        styler.buildSurface()
        ruleEditor.rowHeight = SAClaudeFilterChrome.rowHeight

        styler.applyColours(force: true)
        styler.defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak styler] _ in
            styler?.applyColours(force: false)
        }
        // Dynamic fallback colours (no theme saved yet) resolve differently in light and dark.
        styler.appearanceObservation = ruleEditor.observe(\.effectiveAppearance) { [weak styler] _, _ in
            DispatchQueue.main.async { styler?.applyColours(force: true) }
        }
        restyleRows(of: ruleEditor)
    }

    /// Re-applies the row styling after AppKit rebuilt rows (call at the end of -ruleEditorRowsDidChange:).
    @objc(restyleRowsOfRuleEditor:)
    static func restyleRows(of ruleEditor: NSRuleEditor?) {
        guard let ruleEditor else { return }
        // The rows-changed notification can arrive on the thread that mutated the rows.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { restyleRows(of: ruleEditor) }
            return
        }
        guard let styler = objc_getAssociatedObject(ruleEditor, &associationKey) as? SAClaudeFilterBarStyler else { return }
        styler.restyleRows()
        // AppKit posts the notification before it builds a newly inserted row's view: catch that row next turn.
        DispatchQueue.main.async { [weak styler] in styler?.restyleRows() }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    // MARK: - Surface

    /// The container's theme background (below its subviews) and the hairline along its bottom edge.
    private func buildSurface() {
        guard let container = ruleEditor?.enclosingScrollView?.superview else { return }
        self.container = container

        background.frame = container.bounds
        background.autoresizingMask = [.width, .height]
        container.addSubview(background, positioned: .below, relativeTo: nil)

        let flipped = container.isFlipped
        bottomLine.frame = NSRect(x: 0, y: flipped ? container.bounds.height - 1 : 0, width: container.bounds.width, height: 1)
        bottomLine.autoresizingMask = [.width, flipped ? .minYMargin : .maxYMargin]
        container.addSubview(bottomLine)
    }

    // MARK: - Rows

    /// Makes every row AppKit paints through a row painter transparent, with a hairline on its top edge
    /// (none on the top row, so the lines fall between rows).
    private func restyleRows() {
        guard let ruleEditor, let painterClass = Self.rowPainterClass else { return }
        let hairline = (appliedPalette ?? Self.currentPalette).hairline
        for holder in ruleEditor.subviews {
            var rows: [NSView] = []
            for child in holder.subviews {
                if child.isKind(of: painterClass) {
                    // The holder's own background behind all rows.
                    child.isHidden = true
                } else {
                    let painters = child.subviews.filter { $0.isKind(of: painterClass) }
                    guard !painters.isEmpty else { continue }
                    painters.forEach { $0.isHidden = true }
                    rows.append(child)
                }
            }
            // Row order survives AppKit's row animations, so the top row is the one nearest the top edge; a row
            // being inserted above it starts at the same origin with less height.
            let topRow = holder.isFlipped
                ? rows.min { ($0.frame.minY, $0.frame.height) < ($1.frame.minY, $1.frame.height) }
                : rows.max { ($0.frame.maxY, -$0.frame.height) < ($1.frame.maxY, -$1.frame.height) }
            for row in rows {
                let line = Self.hairline(in: row)
                line.colourOverride = hairline
                line.isHidden = row === topRow
            }
        }
    }

    /// The row's top-edge hairline, added the first time.
    private static func hairline(in row: NSView) -> SAClaudeDividerLine {
        if let line = row.subviews.first(where: { $0.identifier == rowHairlineIdentifier }) as? SAClaudeDividerLine {
            return line
        }
        let flipped = row.isFlipped
        let line = SAClaudeDividerLine(frame: NSRect(x: 0, y: flipped ? 0 : row.bounds.height - 1, width: row.bounds.width, height: 1))
        line.identifier = rowHairlineIdentifier
        line.autoresizingMask = [.width, flipped ? .maxYMargin : .minYMargin]
        row.addSubview(line)
        return line
    }

    // MARK: - Colours

    /// Re-derives the colours when the editor theme changed (or always, when `force`).
    private func applyColours(force: Bool) {
        guard let ruleEditor else { return }
        var resolved: SAClaudeEditorChrome.Palette?
        var themeText: NSColor?
        ruleEditor.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = SAClaudeEditorChrome.palette(from: .standard)
            themeText = SAClaudeThemeColours.from(defaults: .standard).text
        }
        guard let palette = resolved, let themeText else { return }
        Self.currentPalette = palette
        Self.currentThemeText = themeText
        guard force || palette != appliedPalette else { return }
        appliedPalette = palette

        background.fillColour = palette.background
        bottomLine.colourOverride = palette.hairline
        if let clipView = ruleEditor.enclosingScrollView?.contentView {
            clipView.backgroundColor = palette.background
            clipView.drawsBackground = true
        }
        restyleRows()
        // Cells read the current colours at draw time.
        Self.markForDisplay(ruleEditor)
    }

    private static func markForDisplay(_ view: NSView) {
        view.needsDisplay = true
        view.subviews.forEach(markForDisplay)
    }
}
