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
//  Controls: the rule rows' pop-ups become ghost pills, their +/- buttons
//  ghost glyph buttons, the enable checkbox a Claude checkbox and the value
//  field a rounded field in the editor font; the AND/OR pop-up is a pill, the
//  Apply button clay and Add Filter a ghost pill (cells in
//  SAClaudeFilterCells.swift). Controls are only restyled in place: targets,
//  actions, menus, bindings and the frames AppKit lays out are untouched.
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
        guard let ruleEditor else { return }
        restyleRowControls(in: ruleEditor)
        guard let painterClass = Self.rowPainterClass else { return }
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

    // MARK: - Controls

    private var palette: SAClaudeEditorChrome.Palette { appliedPalette ?? Self.currentPalette }

    /// The editor font at the size the filter bar uses.
    private static func fieldFont() -> NSFont {
        SAClaudeCompletionStyler.editorFont().withSize(12)
    }

    /// Visits every control of the rule editor's rows. Idempotent: each control is brought to the styled state
    /// whatever state it is in, and nothing AppKit lays out is moved.
    private func restyleRowControls(in view: NSView) {
        // The SwiftUI hosting views AppKit puts inside its own controls hold nothing of ours.
        if String(describing: type(of: view)).contains("HostingView") { return }
        if let popUp = view as? NSPopUpButton {
            SAClaudeFilterCells.installPill(on: popUp)
        } else if let field = view as? SPFilterRuleTextField {
            styleValueField(field)
        } else if let label = view as? NSTextField {
            styleLabel(label)
        } else if let button = view as? NSButton {
            styleRowButton(button)
        }
        view.subviews.forEach(restyleRowControls)
    }

    /// The rule row's +/- buttons are told apart by their actions; AppKit's add/remove template images
    /// (older macOS) are the fallback, as macOS 26 and later draw them through a hosting view with no image.
    private static func glyph(forRowButton button: NSButton) -> SAClaudeGlyph? {
        switch button.action.map(NSStringFromSelector) {
        case "_addOption:": return .add
        case "_deleteOption:": return .remove
        default: break
        }
        switch button.image?.name() {
        case NSImage.addTemplateName: return .add
        case NSImage.removeTemplateName: return .remove
        default: return nil
        }
    }

    private func styleRowButton(_ button: NSButton) {
        let palette = palette
        if let glyph = Self.glyph(forRowButton: button) {
            guard SAClaudeFilterCells.installCellDrawing(on: button) else { return }
            button.isBordered = false
            button.imagePosition = .imageOnly
            let image = SAClaudeGlyphs.image(glyph, tint: palette.icon)
            button.image = image
            button.alternateImage = image
            SAClaudeHoverHighlighter.attach(to: button)
            SAClaudeHoverHighlighter.setFillColour(palette.hover, for: button)
        } else if let cell = button.cell as? NSButtonCell, cell.showsStateBy == .contentsCellMask, cell.highlightsBy == .contentsCellMask {
            // A checkbox (NSButtonTypeSwitch): the rows' enable checkbox.
            SAClaudeFilterCells.install(SAClaudeCheckboxCell.self, on: button)
        }
    }

    /// The rule row's value field: a rounded fill and outline, the editor font, the theme's text colour. The fill is
    /// the layer's, not the cell's, so it follows the rounded corners (and the field editor stays transparent).
    private func styleValueField(_ field: SPFilterRuleTextField) {
        let palette = palette
        let themeText = Self.currentThemeText
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.wantsLayer = true
        field.font = Self.fieldFont()
        field.textColor = themeText
        guard let layer = field.layer else { return }
        layer.cornerRadius = 7
        layer.borderWidth = 1
        field.effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = SAClaudeFilterChrome.fieldFill(text: themeText, background: palette.background).cgColor
            layer.borderColor = palette.hairline.cgColor
        }
    }

    /// The rows' static text (for example "combines the conditions in this group"): SF Pro 12 in the muted tone.
    /// Left at the size AppKit measured it for when 12pt would no longer fit its frame.
    private func styleLabel(_ label: NSTextField) {
        guard !label.isEditable else { return }
        label.textColor = palette.icon
        let font = NSFont.systemFont(ofSize: 12)
        let width = ceil(NSAttributedString(string: label.stringValue, attributes: [.font: font]).size().width)
        // A text field's cell keeps 2pt free on each side of its text.
        guard width + 4 <= label.frame.width, label.font?.pointSize != 12 else { return }
        label.font = font
    }

    /// Styles the AND/OR pop-up, the Apply button and the Add Filter button. Re-run on a palette change.
    private func restyleBarControls() {
        let palette = palette
        if let popUp = rootConjunctionPopUp {
            SAClaudeFilterCells.installPill(on: popUp)
            popUp.needsDisplay = true
        }
        if let apply = applyButton, SAClaudeFilterCells.install(SAClaudeAccentButtonCell.self, on: apply) {
            apply.isBordered = false
            apply.needsDisplay = true
        }
        if let add = addFilterButton, SAClaudeFilterCells.installCellDrawing(on: add) {
            add.isBordered = false
            add.imagePosition = .imageLeading
            let image = SAClaudeGlyphs.image(.add, tint: palette.icon)
            add.image = image
            add.alternateImage = image
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            add.attributedTitle = NSAttributedString(string: add.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: palette.buttonText,
                .paragraphStyle: style,
            ])
            SAClaudeHoverHighlighter.attach(to: add)
            SAClaudeHoverHighlighter.setFillColour(palette.hover, for: add)
        }
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
        restyleBarControls()
        // Cells read the current colours at draw time.
        Self.markForDisplay(ruleEditor)
    }

    private static func markForDisplay(_ view: NSView) {
        view.needsDisplay = true
        view.subviews.forEach(markForDisplay)
    }
}
