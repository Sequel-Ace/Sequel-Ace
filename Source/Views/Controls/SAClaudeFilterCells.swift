//
//  SAClaudeFilterCells.swift
//  Sequel Ace
//
//  The cells the Content filter bar draws its controls with: ghost pop-up
//  pills, the enable checkbox, the radio and the accent Apply button. They are installed
//  onto the controls AppKit and the XIB already built with `object_setClass`,
//  so every target, action, menu and binding stays as it was. The cells have
//  no stored properties (an isa swap must keep the instance layout) and read
//  their colours at draw time from `SAClaudeFilterBarStyler`. App target only.
//
//  On macOS 26 and later NSButton and NSPopUpButton draw through
//  `updateLayer` and never ask their cell to draw, and AppKit's rule editor
//  adds a SwiftUI hosting view to its own bordered controls. A swapped cell
//  therefore only shows up if the control also draws the classic way, so the
//  control's class is swapped too, for one that answers `wantsUpdateLayer`
//  with false. AppKit's rule-editor controls and cells are private subclasses
//  of NSPopUpButton / NSButton with extra behaviour (tracking, accessibility,
//  sizing), so for those a runtime subclass of the actual class is derived and
//  given the drawing methods, which keeps every inherited override.
//

import AppKit

// MARK: - Control classes that draw through their cell

/// An NSPopUpButton that draws through its cell on every macOS version.
@objc(SAClaudeFilterPopUpButton) final class SAClaudeFilterPopUpButton: NSPopUpButton {
    override var wantsUpdateLayer: Bool { false }
}

/// An NSButton that draws through its cell on every macOS version.
@objc(SAClaudeFilterButton) final class SAClaudeFilterButton: NSButton {
    override var wantsUpdateLayer: Bool { false }
}

// MARK: - Drawing helpers

/// Shared with the other Claude cells (the Import mapping table's pill and operator cells).
enum FilterCellDrawing {
    static let cornerRadius: CGFloat = 7
    static let disabledAlpha: CGFloat = 0.4
    static let font = NSFont.systemFont(ofSize: 12)
    /// From the box (or circle) to the title.
    static let titleGap: CGFloat = SAClaudeToggleTitleMetrics.gap
    /// Spare width so a measured title never truncates by a rounding hair.
    static let titleSlack: CGFloat = SAClaudeToggleTitleMetrics.slack

    /// The size a Claude checkbox or radio cell draws (`SAClaudeToggleTitleMetrics.cellSize`): a title with line breaks
    /// is measured line by line, in the font it is drawn in.
    static func toggleCellSize(title: String, drawsTitle: Bool, nativeHeight: CGFloat) -> NSSize {
        SAClaudeToggleTitleMetrics.cellSize(title: title, drawsTitle: drawsTitle, nativeHeight: nativeHeight)
    }

    /// AppKit's own size for a checkbox / radio cell (only its height is used), through NSButtonCell's implementation
    /// rather than `super`: a cell derived from one of NSAlert's private cells carries the toggle cells'
    /// `cellSize(forBounds:)` (`SAClaudeFilterCells`), and `super` from that donated method calls it again, forever.
    static func nativeToggleCellSize(_ cell: NSButtonCell, forBounds rect: NSRect) -> NSSize {
        typealias CellSize = @convention(c) (AnyObject, Selector, NSRect) -> NSSize
        let selector = #selector(NSCell.cellSize(forBounds:))
        guard let implementation = class_getMethodImplementation(NSButtonCell.self, selector) else { return .zero }
        return unsafeBitCast(implementation, to: CellSize.self)(cell, selector, rect)
    }

    /// The height of a checkbox / radio title wrapped on word boundaries to fit a cell `cellWidth` wide (beside its 14pt
    /// mark and the gap). One line's height when the title fits on one line. The alert card sizes a long suppression
    /// checkbox with this, and the cells draw the same wrapped text, so no title is truncated.
    static func wrappedToggleTitleHeight(_ title: String, cellWidth: CGFloat) -> CGFloat {
        SAClaudeToggleTitleMetrics.wrappedTitleHeight(title, cellWidth: cellWidth)
    }

    /// One line of a checkbox / radio title.
    static var toggleTitleLineHeight: CGFloat { SAClaudeToggleTitleMetrics.lineHeight }

    /// Draws a title that needs several lines (see `wrappedToggleTitleHeight`) from the top of `rect`.
    static func drawWrappedTitle(_ text: String, in rect: NSRect, colour: NSColor, font: NSFont) {
        guard rect.width > 0 else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.alignment = .left
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: colour, .paragraphStyle: style])
            .draw(with: rect, options: [.usesLineFragmentOrigin])
    }

    static func roundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    /// Y of a point `fromTop` points below the top edge of `rect`, whichever way the view is flipped.
    static func y(_ fromTop: CGFloat, in rect: NSRect, flipped: Bool) -> CGFloat {
        flipped ? rect.minY + fromTop : rect.maxY - fromTop
    }

    /// Draws `text` on one line, centred vertically in `rect`, truncating at the tail.
    static func drawTitle(_ text: String, in rect: NSRect, colour: NSColor, font: NSFont, alignment: NSTextAlignment) {
        guard rect.width > 0 else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour, .paragraphStyle: style]
        let string = NSAttributedString(string: text, attributes: attributes)
        let height = ceil(string.size().height)
        let line = NSRect(x: rect.minX, y: (rect.midY - height / 2).rounded(), width: rect.width, height: height)
        string.draw(with: line, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

// MARK: - Cells

/// A ghost pill for a pop-up: a rounded hover-coloured fill, the selected title and a small up/down selector.
@objc(SAClaudePillPopUpButtonCell) final class SAClaudePillPopUpButtonCell: NSPopUpButtonCell {

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Self.drawPill(title: Self.displayTitle(of: self), in: SAClaudeFilterChrome.controlFrame(in: cellFrame), flipped: controlView.isFlipped,
                      font: FilterCellDrawing.font, enabled: isEnabled, highlighted: isHighlighted, outlined: false)
    }

    /// What the pill shows: a pop-up's selected item; a pull-down's own title (its first item's), as AppKit shows
    /// it — a pull-down's selected item is whichever entry was last chosen from it.
    static func displayTitle(of cell: NSPopUpButtonCell) -> String {
        (cell.pullsDown ? cell.title : cell.selectedItem?.title ?? cell.title) ?? ""
    }

    /// The pill in `pill`: the hover-coloured fill (or, when `outlined`, a 1pt outline in the brighter drop stroke
    /// on a transparent fill), `title` in `font` and the up/down selector. Disabled draws at 40%.
    static func drawPill(title: String, in pill: NSRect, flipped: Bool, font: NSFont, enabled: Bool, highlighted: Bool, outlined: Bool) {
        let palette = SAClaudeFilterBarStyler.currentPalette
        let themeText = SAClaudeFilterBarStyler.currentThemeText

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !enabled { NSGraphicsContext.current?.cgContext.setAlpha(FilterCellDrawing.disabledAlpha) }

        let pressed = SAClaudeEditorChrome.derivedColour(text: themeText, background: palette.hover, ratio: 0.08)
        if outlined {
            let outline = FilterCellDrawing.roundedPath(pill.insetBy(dx: 0.5, dy: 0.5), radius: FilterCellDrawing.cornerRadius - 0.5)
            if highlighted {
                pressed.setFill()
                outline.fill()
            }
            outline.lineWidth = 1
            SAClaudeFilterChrome.dropStroke(text: themeText, background: palette.background).setStroke()
            outline.stroke()
        } else {
            (highlighted ? pressed : palette.hover).setFill()
            FilterCellDrawing.roundedPath(pill, radius: FilterCellDrawing.cornerRadius).fill()
        }

        FilterCellDrawing.drawTitle(title, in: SAClaudeFilterChrome.pillTitleRect(in: pill), colour: themeText, font: font, alignment: .left)

        // Two 3pt chevrons, one above the other, in the right-hand selector slot.
        let centreX = pill.maxX - 4 - SAClaudeFilterChrome.selectorWidth / 2
        let centreY = pill.midY
        let sign: CGFloat = flipped ? -1 : 1
        let chevrons = NSBezierPath()
        for direction: CGFloat in [1, -1] {
            let base = centreY + sign * direction * 1.5
            let apex = centreY + sign * direction * 4.5
            chevrons.move(to: NSPoint(x: centreX - 3, y: base))
            chevrons.line(to: NSPoint(x: centreX, y: apex))
            chevrons.line(to: NSPoint(x: centreX + 3, y: base))
        }
        chevrons.lineWidth = 1.2
        chevrons.lineCapStyle = .round
        chevrons.lineJoinStyle = .round
        palette.icon.setStroke()
        chevrons.stroke()
    }
}

/// A checkbox drawn as a small rounded square: the accent with an `onAccent` check when on, an outline in a mid tone of the theme text when off (a hairline vanishes in dark mode).
/// A title-less one in a table column (a sheet table's checkbox data cell) is centred in its cell; elsewhere the box sits at the left.
@objc(SAClaudeCheckboxCell) final class SAClaudeCheckboxCell: NSButtonCell {

    /// Where the box is drawn in `cellFrame` (in a table the whole cell still toggles, as AppKit's own cell did).
    private func boxRect(in cellFrame: NSRect, of controlView: NSView) -> NSRect {
        var box = SAClaudeFilterChrome.checkboxRect(in: cellFrame)
        if title.isEmpty, controlView is NSTableView {
            box.origin.x = (cellFrame.midX - box.width / 2).rounded()
        } else if wrapsTitle(in: cellFrame) {
            // Several title lines: the box sits level with the first one.
            let line = FilterCellDrawing.toggleTitleLineHeight
            box.origin.y = FilterCellDrawing.y(((line - box.height) / 2).rounded(), in: cellFrame, flipped: controlView.isFlipped)
                - (controlView.isFlipped ? 0 : box.height)
        }
        return box
    }

    /// Whether the title takes several lines here: it does not fit on one and the frame is tall enough for the wrapped
    /// text (every ordinary one-line checkbox keeps its single truncating line).
    private func wrapsTitle(in cellFrame: NSRect) -> Bool {
        guard imagePosition != .imageOnly, !title.isEmpty else { return false }
        let lineHeight = FilterCellDrawing.toggleTitleLineHeight
        let wrapped = FilterCellDrawing.wrappedToggleTitleHeight(title, cellWidth: cellFrame.width)
        return wrapped > lineHeight * 1.5 && cellFrame.height >= wrapped
    }

    /// `cellSize` measures through this too.
    override func cellSize(forBounds rect: NSRect) -> NSSize {
        FilterCellDrawing.toggleCellSize(title: title, drawsTitle: imagePosition != .imageOnly,
                                         nativeHeight: FilterCellDrawing.nativeToggleCellSize(self, forBounds: rect).height)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let palette = SAClaudeFilterBarStyler.currentPalette
        let themeText = SAClaudeFilterBarStyler.currentThemeText
        let flipped = controlView.isFlipped
        let box = boxRect(in: cellFrame, of: controlView)
        let radius = SAClaudeFilterChrome.checkboxRadius

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(FilterCellDrawing.disabledAlpha) }

        if state == .off {
            if isHighlighted {
                palette.hover.setFill()
                FilterCellDrawing.roundedPath(box, radius: radius).fill()
            }
            let outline = FilterCellDrawing.roundedPath(box.insetBy(dx: 0.5, dy: 0.5), radius: radius - 0.5)
            outline.lineWidth = 1
            SAClaudeFilterChrome.dropStroke(text: themeText, background: palette.background).setStroke()
            outline.stroke()
        } else {
            (isHighlighted ? SAClaudeEditorChrome.runFillPressed : SAClaudeEditorChrome.runFill).setFill()
            FilterCellDrawing.roundedPath(box, radius: radius).fill()
            let mark = NSBezierPath()
            if state == .mixed {
                mark.move(to: NSPoint(x: box.minX + 3.5, y: FilterCellDrawing.y(7, in: box, flipped: flipped)))
                mark.line(to: NSPoint(x: box.maxX - 3.5, y: FilterCellDrawing.y(7, in: box, flipped: flipped)))
            } else {
                mark.move(to: NSPoint(x: box.minX + 3.5, y: FilterCellDrawing.y(7.5, in: box, flipped: flipped)))
                mark.line(to: NSPoint(x: box.minX + 6, y: FilterCellDrawing.y(10, in: box, flipped: flipped)))
                mark.line(to: NSPoint(x: box.maxX - 3.5, y: FilterCellDrawing.y(4.5, in: box, flipped: flipped)))
            }
            mark.lineWidth = 1.6
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            SAClaudeAccent.onAccent.setStroke()
            mark.stroke()
        }

        if imagePosition != .imageOnly, !title.isEmpty {
            let minX = box.maxX + FilterCellDrawing.titleGap
            let titleRect = NSRect(x: minX, y: cellFrame.minY, width: max(0, cellFrame.maxX - minX), height: cellFrame.height)
            if wrapsTitle(in: cellFrame) {
                FilterCellDrawing.drawWrappedTitle(title, in: titleRect, colour: themeText, font: SAClaudeToggleTitleMetrics.font)
            } else {
                FilterCellDrawing.drawTitle(title, in: titleRect, colour: themeText, font: SAClaudeToggleTitleMetrics.font, alignment: .left)
            }
        }
    }
}

/// A radio button drawn as a 14pt circle: a 1pt outline in the brighter drop stroke when off, the accent fill with
/// a 6pt `onAccent` dot when on. Disabled draws at 40%; the title is drawn as the checkbox cell draws it.
@objc(SAClaudeRadioCell) final class SAClaudeRadioCell: NSButtonCell {

    private static let dotDiameter: CGFloat = 6

    /// `cellSize` measures through this too.
    override func cellSize(forBounds rect: NSRect) -> NSSize {
        FilterCellDrawing.toggleCellSize(title: title, drawsTitle: imagePosition != .imageOnly,
                                         nativeHeight: FilterCellDrawing.nativeToggleCellSize(self, forBounds: rect).height)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let palette = SAClaudeFilterBarStyler.currentPalette
        let themeText = SAClaudeFilterBarStyler.currentThemeText
        let circle = SAClaudeFilterChrome.checkboxRect(in: cellFrame)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(FilterCellDrawing.disabledAlpha) }

        if state == .off {
            if isHighlighted {
                palette.hover.setFill()
                NSBezierPath(ovalIn: circle).fill()
            }
            let outline = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            SAClaudeFilterChrome.dropStroke(text: themeText, background: palette.background).setStroke()
            outline.stroke()
        } else {
            (isHighlighted ? SAClaudeEditorChrome.runFillPressed : SAClaudeEditorChrome.runFill).setFill()
            NSBezierPath(ovalIn: circle).fill()
            let dot = NSRect(x: circle.midX - Self.dotDiameter / 2, y: circle.midY - Self.dotDiameter / 2,
                             width: Self.dotDiameter, height: Self.dotDiameter)
            SAClaudeAccent.onAccent.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }

        if imagePosition != .imageOnly, !title.isEmpty {
            let minX = circle.maxX + FilterCellDrawing.titleGap
            let titleRect = NSRect(x: minX, y: cellFrame.minY, width: max(0, cellFrame.maxX - minX), height: cellFrame.height)
            FilterCellDrawing.drawTitle(title, in: titleRect, colour: themeText, font: SAClaudeToggleTitleMetrics.font, alignment: .left)
        }
    }
}

/// The filter bar's Apply button: an accent rounded fill with an `onAccent` medium-weight title.
@objc(SAClaudeAccentButtonCell) final class SAClaudeAccentButtonCell: NSButtonCell {

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Self.drawAccent(self, in: SAClaudeFilterChrome.controlFrame(in: cellFrame))
    }

    /// The accent pill and its `onAccent` title, in `pill`.
    static func drawAccent(_ cell: NSButtonCell, in pill: NSRect, font: NSFont = NSFont.systemFont(ofSize: 12, weight: .medium)) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !cell.isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }

        (cell.isHighlighted ? SAClaudeEditorChrome.runFillPressed : SAClaudeEditorChrome.runFill).setFill()
        FilterCellDrawing.roundedPath(pill, radius: FilterCellDrawing.cornerRadius).fill()

        FilterCellDrawing.drawTitle(cell.title, in: pill.insetBy(dx: SAClaudeFilterChrome.pillPadding, dy: 0), colour: SAClaudeAccent.onAccent, font: font, alignment: .center)
    }
}

/// The connection panel's Connect button: the accent pill at the button's own height (28pt) rather than the
/// filter bar's 24pt control height.
@objc(SAClaudeFullHeightAccentButtonCell) final class SAClaudeFullHeightAccentButtonCell: NSButtonCell {

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        SAClaudeAccentButtonCell.drawAccent(self, in: cellFrame)
    }
}

/// A bordered secondary button (the connection panel's "Connect without saving", "Save changes", …): a 7pt
/// rounded outline in the brighter drop stroke (a hairline vanishes in dark themes) on a transparent fill, the
/// title in the theme's text colour, SF Pro 12 medium. Hover is the hover highlighter's fill behind it; pressed
/// fills it a little darker; disabled draws at 45%. Drawn at the button's own height.
@objc(SAClaudeSecondaryButtonCell) final class SAClaudeSecondaryButtonCell: NSButtonCell {

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Self.drawSecondary(self, in: cellFrame, font: NSFont.systemFont(ofSize: 12, weight: .medium), hovered: false)
    }

    /// The outline, the pressed (or `hovered`) fill and the theme-coloured title, in `rect`.
    static func drawSecondary(_ cell: NSButtonCell, in rect: NSRect, font: NSFont, hovered: Bool) {
        let palette = SAClaudeFilterBarStyler.currentPalette
        drawSecondary(cell, in: rect, font: font, hovered: hovered, text: SAClaudeFilterBarStyler.currentThemeText,
                      background: palette.background, hover: palette.hover)
    }

    /// The same look in explicit colours: the title in `text`, the outline and pressed fill derived from `text`
    /// over `background`, the hover fill `hover` (for chrome that follows the app's tokens, not the editor theme).
    static func drawSecondary(_ cell: NSButtonCell, in rect: NSRect, font: NSFont, hovered: Bool,
                              text themeText: NSColor, background: NSColor, hover: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !cell.isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }

        let path = FilterCellDrawing.roundedPath(rect.insetBy(dx: 0.5, dy: 0.5), radius: FilterCellDrawing.cornerRadius - 0.5)
        if cell.isHighlighted {
            SAClaudeEditorChrome.derivedColour(text: themeText, background: hover, ratio: 0.08).setFill()
            path.fill()
        } else if hovered && cell.isEnabled {
            hover.setFill()
            path.fill()
        }
        path.lineWidth = 1
        SAClaudeFilterChrome.dropStroke(text: themeText, background: background).setStroke()
        path.stroke()

        FilterCellDrawing.drawTitle(cell.title, in: rect.insetBy(dx: SAClaudeFilterChrome.pillPadding, dy: 0), colour: themeText,
                                    font: font, alignment: .center)
    }
}

// MARK: - Sheet buttons

/// Where a sheet button draws inside whatever frame the XIB gave it, and in which font.
private enum SheetButtonDrawing {
    /// Inside the classic bezel's side margins, except on NSAlert's own buttons (laid out without them).
    static func rect(_ cell: NSButtonCell, in cellFrame: NSRect, of controlView: NSView) -> NSRect {
        let isAlertButton = NSStringFromClass(type(of: controlView)).contains("_NSAlert")
        return SAClaudeSheetButtonGeometry.buttonRect(in: cellFrame, controlSize: cell.controlSize, classicMargins: !isAlertButton)
    }

    /// The cell's own point size (13 for regular buttons, 11 for small ones).
    static func font(_ cell: NSButtonCell, weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: cell.font?.pointSize ?? NSFont.systemFontSize, weight: weight)
    }

    /// Whether the mouse is over `rect` of `controlView` (an `SAClaudeSheetHoverTracker` redraws the button on enter / exit).
    static func isHovered(_ rect: NSRect, in controlView: NSView) -> Bool {
        guard let window = controlView.window, window.isVisible else { return false }
        return rect.contains(controlView.convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
}

/// A sheet's or alert's primary button: the accent pill with an `onAccent` medium title in the button's own
/// font size, drawn at a sensible height centred in the XIB frame (`SAClaudeSheetButtonGeometry`).
@objc(SAClaudeSheetPrimaryButtonCell) final class SAClaudeSheetPrimaryButtonCell: NSButtonCell {

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        SAClaudeAccentButtonCell.drawAccent(self, in: SheetButtonDrawing.rect(self, in: cellFrame, of: controlView),
                                            font: SheetButtonDrawing.font(self, weight: .medium))
    }
}

/// A destructive alert button (Delete, Remove, Kill…): the primary button's geometry and font in a true red
/// (`SAClaudeAlertChrome.red`, never the clay accent), pressed 12% towards black, an `onAccent` medium title,
/// 45% when disabled.
@objc(SAClaudeSheetDestructiveButtonCell) final class SAClaudeSheetDestructiveButtonCell: NSButtonCell {
    private static let pressedRatio: CGFloat = 0.12

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let pill = SheetButtonDrawing.rect(self, in: cellFrame, of: controlView)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }

        let red = SAClaudeAlertChrome.red
        let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        (isHighlighted ? SAClaudeEditorChrome.derivedColour(text: black, background: red, ratio: Self.pressedRatio) : red).setFill()
        FilterCellDrawing.roundedPath(pill, radius: FilterCellDrawing.cornerRadius).fill()

        FilterCellDrawing.drawTitle(title, in: pill.insetBy(dx: SAClaudeFilterChrome.pillPadding, dy: 0), colour: SAClaudeAccent.onAccent(fill: red),
                                    font: SheetButtonDrawing.font(self, weight: .medium), alignment: .center)
    }
}

/// A secondary destructive alert button (every destructive button but the default one, e.g. "Delete ALL ROWS IN
/// TABLE" beside the default "Delete Selected Row"): the secondary button's geometry and font, a 1pt red dashed
/// outline and a red title (`SAClaudeAlertChrome.destructiveOutline`: `red` light, `redGlyphDark` dark); pressed, a
/// faint (10%) red fill; 45% when disabled.
@objc(SAClaudeSheetDestructiveSecondaryButtonCell) final class SAClaudeSheetDestructiveSecondaryButtonCell: NSButtonCell {

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let rect = SheetButtonDrawing.rect(self, in: cellFrame, of: controlView)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }

        // Resolved in the button's own appearance (the dynamic red is the glyph's).
        var red = SAClaudeAlertChrome.red
        controlView.effectiveAppearance.performAsCurrentDrawingAppearance {
            red = SAClaudeAlertChrome.destructiveOutline.usingColorSpace(.sRGB) ?? SAClaudeAlertChrome.red
        }
        let path = FilterCellDrawing.roundedPath(rect.insetBy(dx: 0.5, dy: 0.5), radius: FilterCellDrawing.cornerRadius - 0.5)
        if isHighlighted {
            red.withAlphaComponent(SAClaudeAlertChrome.destructiveOutlinePressedAlpha).setFill()
            path.fill()
        }
        path.lineWidth = SAClaudeAlertChrome.destructiveOutlineWidth
        let dash = SAClaudeAlertChrome.destructiveOutlineDash
        path.setLineDash(dash, count: dash.count, phase: 0)
        red.setStroke()
        path.stroke()

        FilterCellDrawing.drawTitle(title, in: rect.insetBy(dx: SAClaudeFilterChrome.pillPadding, dy: 0), colour: red,
                                    font: SheetButtonDrawing.font(self, weight: .medium), alignment: .center)
    }
}

/// A sheet's or alert's secondary button: the bordered secondary look, drawn like the primary one inside the
/// XIB frame, with the hover fill inside its outline.
@objc(SAClaudeSheetSecondaryButtonCell) final class SAClaudeSheetSecondaryButtonCell: NSButtonCell {

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let rect = SheetButtonDrawing.rect(self, in: cellFrame, of: controlView)
        SAClaudeSecondaryButtonCell.drawSecondary(self, in: rect, font: SheetButtonDrawing.font(self, weight: .medium),
                                                  hovered: SheetButtonDrawing.isHovered(rect, in: controlView))
    }
}

/// The looks of a sheet or alert push button: `destructive` is the filled red default, `destructiveSecondary` the
/// red dashed outline of every other destructive alert button.
enum SAClaudeSheetButtonLook: CaseIterable { case primary, secondary, destructive, destructiveSecondary }

// MARK: - Installing

/// Swaps the filter bar's controls over to the cells above. Every function leaves a control alone unless it is
/// one of the exact AppKit classes below (a control of any other class, such as one KVO has already
/// isa-swizzled, is not ours to change), never swaps twice, and never swaps an object something observes by
/// KVO (`SAClaudeClassSwap`).
enum SAClaudeFilterCells {

    /// The private classes AppKit's rule editor builds its pop-ups with.
    private static let ruleEditorPopUpClass = "NSRuleEditorPopupButton"
    private static let ruleEditorPopUpCellClass = "NSRuleEditorPopupButtonCell"
    /// The marker in the names of the runtime subclasses derived below.
    private static let derivedPrefix = "SAClaudeFilterDerived_"
    private static var derivedClasses: [String: AnyClass] = [:]

    /// Whether `cls` is one of the classes this file installs.
    private static func isInstalled(_ cls: AnyClass) -> Bool {
        cls == SAClaudePillPopUpButtonCell.self || cls == SAClaudeCheckboxCell.self || cls == SAClaudeRadioCell.self
            || cls == SAClaudeAccentButtonCell.self
            || cls == SAClaudeFullHeightAccentButtonCell.self || cls == SAClaudeSecondaryButtonCell.self
            || cls == SAClaudeSheetPrimaryButtonCell.self || cls == SAClaudeSheetSecondaryButtonCell.self
            || cls == SAClaudeSheetDestructiveButtonCell.self || cls == SAClaudeSheetDestructiveSecondaryButtonCell.self
            || cls == SAClaudeFilterPopUpButton.self || cls == SAClaudeFilterButton.self
            || NSStringFromClass(cls).hasPrefix(derivedPrefix)
    }

    /// Whether `object`'s class, or any superclass of it (KVO derives a subclass of a class it observes), is installed.
    private static func hasInstalledClass(_ object: AnyObject) -> Bool {
        var cls: AnyClass? = object_getClass(object)
        while let current = cls {
            if isInstalled(current) { return true }
            cls = class_getSuperclass(current)
        }
        return false
    }

    /// A runtime subclass of `base` that carries `selectors`' implementations from `donor`: the inherited
    /// overrides of `base` stay, and the donor's methods only call up to its own (public) superclass.
    private static func derivedClass(of base: AnyClass, donor: AnyClass, selectors: [Selector]) -> AnyClass? {
        let name = derivedPrefix + NSStringFromClass(donor) + "_" + NSStringFromClass(base)
        if let existing = derivedClasses[name] { return existing }
        guard let derived = objc_allocateClassPair(base, name, 0) else { return NSClassFromString(name) }
        for selector in selectors {
            guard let method = class_getInstanceMethod(donor, selector) else { continue }
            class_addMethod(derived, selector, method_getImplementation(method), method_getTypeEncoding(method))
        }
        objc_registerClassPair(derived)
        derivedClasses[name] = derived
        return derived
    }

    private static let drawSelector = #selector(NSCell.draw(withFrame:in:))
    private static let cellSizeSelector = #selector(NSCell.cellSize(forBounds:))

    /// What a cell derived from one of NSAlert's private cells takes from `donor`: its drawing, and for a checkbox or
    /// radio its measurement too, so NSAlert's suppression checkbox is sized as it is drawn (in the toggle title font,
    /// line by line), not by AppKit at the caller's own font.
    private static func donatedSelectors(for donor: AnyClass) -> [Selector] {
        donor == SAClaudeCheckboxCell.self || donor == SAClaudeRadioCell.self ? [drawSelector, cellSizeSelector] : [drawSelector]
    }
    private static let updateLayerSelector = #selector(getter: NSView.wantsUpdateLayer)

    /// The prefix of the private classes NSAlert builds its buttons (and their cells) with.
    private static let alertButtonClassPrefix = "_NSAlert"

    /// Whether `cls` is one of NSAlert's private button or button-cell classes.
    private static func isAlertButtonClass(_ cls: AnyClass) -> Bool {
        NSStringFromClass(cls).hasPrefix(alertButtonClassPrefix)
    }

    /// The control class to swap `button` (exactly an NSButton, or one of NSAlert's private buttons) to.
    private static func hostClass(for button: NSButton) -> AnyClass? {
        let cls: AnyClass = type(of: button)
        if cls == NSButton.self { return SAClaudeFilterButton.self }
        if isAlertButtonClass(cls) {
            return derivedClass(of: cls, donor: SAClaudeFilterButton.self, selectors: [updateLayerSelector])
        }
        return nil
    }

    /// Hides any SwiftUI hosting view AppKit put inside a control; a control that draws through its cell has no use for it.
    private static func hideHostingViews(in control: NSControl) {
        for subview in control.subviews where String(describing: type(of: subview)).contains("HostingView") {
            subview.isHidden = true
        }
    }

    // MARK: Pop-ups

    /// Makes an AppKit-built pop-up (the rule rows' column and operator pop-ups, the AND/OR pop-up) a ghost
    /// pill: borderless, drawn by `SAClaudePillPopUpButtonCell`. Its frame is untouched.
    @discardableResult
    static func installPill(on popUp: NSPopUpButton) -> Bool {
        guard let cell = popUp.cell as? NSPopUpButtonCell else { return false }
        let viewClass: AnyClass = type(of: popUp)
        let cellClass: AnyClass = type(of: cell)
        let viewInstalled = hasInstalledClass(popUp)
        let cellInstalled = hasInstalledClass(cell)
        if viewInstalled && cellInstalled {
            if popUp.isBordered { popUp.isBordered = false }
            hideHostingViews(in: popUp)
            return true
        }
        guard !viewInstalled, !cellInstalled else { return false }

        let newViewClass: AnyClass?
        let newCellClass: AnyClass?
        if viewClass == NSPopUpButton.self, cellClass == NSPopUpButtonCell.self {
            newViewClass = SAClaudeFilterPopUpButton.self
            newCellClass = SAClaudePillPopUpButtonCell.self
        } else if NSStringFromClass(viewClass) == ruleEditorPopUpClass, NSStringFromClass(cellClass) == ruleEditorPopUpCellClass {
            newViewClass = derivedClass(of: viewClass, donor: SAClaudeFilterPopUpButton.self, selectors: [updateLayerSelector])
            newCellClass = derivedClass(of: cellClass, donor: SAClaudePillPopUpButtonCell.self, selectors: [drawSelector])
        } else {
            return false
        }
        guard let newViewClass, let newCellClass,
              SAClaudeClassSwap.mayChangeClass(of: popUp), SAClaudeClassSwap.mayChangeClass(of: cell) else { return false }

        popUp.isBordered = false
        object_setClass(cell, newCellClass)
        object_setClass(popUp, newViewClass)
        if #available(macOS 14.0, *) { popUp.clipsToBounds = false }
        hideHostingViews(in: popUp)
        popUp.needsDisplay = true
        return true
    }

    // MARK: Buttons

    /// Lets a plain NSButton (the rule rows' +/- buttons, the Add Filter button) draw through its cell on macOS 26+.
    /// The cell is left as it is. Only an exact NSButton is swapped.
    @discardableResult
    static func installCellDrawing(on button: NSButton) -> Bool {
        if hasInstalledClass(button) {
            hideHostingViews(in: button)
            return true
        }
        guard let newViewClass = hostClass(for: button), SAClaudeClassSwap.mayChangeClass(of: button) else { return false }
        object_setClass(button, newViewClass)
        if #available(macOS 14.0, *) { button.clipsToBounds = false }
        hideHostingViews(in: button)
        button.needsDisplay = true
        return true
    }

    /// Draws `button` with `cellClass` (`SAClaudeCheckboxCell`, `SAClaudeRadioCell` or one of the accent cells) in place of its
    /// own cell. Only an exact NSButton with an exact NSButtonCell is swapped, or one of NSAlert's private
    /// buttons, whose cell becomes a runtime subclass of its own class drawing like `cellClass`.
    @discardableResult
    static func install(_ cellClass: AnyClass, on button: NSButton) -> Bool {
        guard let cell = button.cell as? NSButtonCell else { return false }
        if hasInstalledClass(cell) { return installCellDrawing(on: button) }
        let currentCellClass: AnyClass = type(of: cell)
        let newCellClass: AnyClass?
        if currentCellClass == NSButtonCell.self {
            newCellClass = cellClass
        } else if isAlertButtonClass(currentCellClass) {
            newCellClass = derivedClass(of: currentCellClass, donor: cellClass, selectors: donatedSelectors(for: cellClass))
        } else {
            newCellClass = nil
        }
        guard let newCellClass, SAClaudeClassSwap.mayChangeClass(of: cell), installCellDrawing(on: button) else { return false }
        object_setClass(cell, newCellClass)
        button.needsDisplay = true
        return true
    }

    /// The cell class that draws `look`.
    static func sheetCellClass(for look: SAClaudeSheetButtonLook) -> AnyClass {
        switch look {
        case .primary: return SAClaudeSheetPrimaryButtonCell.self
        case .secondary: return SAClaudeSheetSecondaryButtonCell.self
        case .destructive: return SAClaudeSheetDestructiveButtonCell.self
        case .destructiveSecondary: return SAClaudeSheetDestructiveSecondaryButtonCell.self
        }
    }

    /// Switches an installed sheet button between the primary, secondary and (filled or outlined) destructive looks (a button whose
    /// default-ness or role changed). Returns false when the cell is not one of the sheet button cells or a subclass
    /// derived from them.
    @discardableResult
    static func switchSheetButton(_ button: NSButton, to look: SAClaudeSheetButtonLook) -> Bool {
        guard let cell = button.cell as? NSButtonCell else { return false }
        let wanted: AnyClass = sheetCellClass(for: look)
        let wantedName = NSStringFromClass(wanted)
        let current: AnyClass = type(of: cell)
        if current == wanted || NSStringFromClass(current).hasPrefix(derivedPrefix + wantedName + "_") { return true }
        guard SAClaudeClassSwap.mayChangeClass(of: cell), SAClaudeClassSwap.mayChangeClass(of: button) else { return false }
        let others = SAClaudeSheetButtonLook.allCases.filter { $0 != look }.map(sheetCellClass(for:))
        if others.contains(where: { $0 == current }) {
            object_setClass(cell, wanted)
            button.needsDisplay = true
            return true
        }
        // A derived alert cell: re-derive from its AppKit base with the wanted donor.
        let name = NSStringFromClass(current)
        guard others.contains(where: { name.hasPrefix(derivedPrefix + NSStringFromClass($0) + "_") }),
              let base = class_getSuperclass(current),
              let derived = derivedClass(of: base, donor: wanted, selectors: [drawSelector]) else { return false }
        object_setClass(cell, derived)
        button.needsDisplay = true
        return true
    }

    /// `switchSheetButton(_:to:)` between the primary and secondary looks.
    @discardableResult
    static func switchSheetButton(_ button: NSButton, toPrimary primary: Bool) -> Bool {
        switchSheetButton(button, to: primary ? .primary : .secondary)
    }
}
