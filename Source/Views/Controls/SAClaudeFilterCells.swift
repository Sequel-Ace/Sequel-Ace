//
//  SAClaudeFilterCells.swift
//  Sequel Ace
//
//  The cells the Content filter bar draws its controls with: ghost pop-up
//  pills, the enable checkbox and the clay Apply button. They are installed
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

private enum FilterCellDrawing {
    static let cornerRadius: CGFloat = 7
    static let disabledAlpha: CGFloat = 0.4
    static let font = NSFont.systemFont(ofSize: 12)

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
        let palette = SAClaudeFilterBarStyler.currentPalette
        let themeText = SAClaudeFilterBarStyler.currentThemeText
        let flipped = controlView.isFlipped
        let pill = SAClaudeFilterChrome.controlFrame(in: cellFrame)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(FilterCellDrawing.disabledAlpha) }

        let fill = isHighlighted ? SAClaudeEditorChrome.derivedColour(text: themeText, background: palette.hover, ratio: 0.08) : palette.hover
        fill.setFill()
        FilterCellDrawing.roundedPath(pill, radius: FilterCellDrawing.cornerRadius).fill()

        let title: String = selectedItem?.title ?? self.title ?? ""
        FilterCellDrawing.drawTitle(title, in: SAClaudeFilterChrome.pillTitleRect(in: pill), colour: themeText, font: FilterCellDrawing.font, alignment: .left)

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

/// A checkbox drawn as a small rounded square: clay with a white check when on, an outline in a mid tone of the theme text when off (a hairline vanishes in dark mode).
@objc(SAClaudeCheckboxCell) final class SAClaudeCheckboxCell: NSButtonCell {

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let palette = SAClaudeFilterBarStyler.currentPalette
        let themeText = SAClaudeFilterBarStyler.currentThemeText
        let flipped = controlView.isFlipped
        let box = SAClaudeFilterChrome.checkboxRect(in: cellFrame)
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
            NSColor.white.setStroke()
            mark.stroke()
        }

        if imagePosition != .imageOnly, !title.isEmpty {
            let minX = box.maxX + 6
            let titleRect = NSRect(x: minX, y: cellFrame.minY, width: max(0, cellFrame.maxX - minX), height: cellFrame.height)
            FilterCellDrawing.drawTitle(title, in: titleRect, colour: themeText, font: FilterCellDrawing.font, alignment: .left)
        }
    }
}

/// The filter bar's Apply button: a clay rounded fill with a white medium-weight title.
@objc(SAClaudeAccentButtonCell) final class SAClaudeAccentButtonCell: NSButtonCell {

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Self.drawAccent(self, in: SAClaudeFilterChrome.controlFrame(in: cellFrame))
    }

    /// The clay pill and its white title, in `pill`.
    static func drawAccent(_ cell: NSButtonCell, in pill: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !cell.isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }

        (cell.isHighlighted ? SAClaudeEditorChrome.runFillPressed : SAClaudeEditorChrome.runFill).setFill()
        FilterCellDrawing.roundedPath(pill, radius: FilterCellDrawing.cornerRadius).fill()

        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        FilterCellDrawing.drawTitle(cell.title, in: pill.insetBy(dx: SAClaudeFilterChrome.pillPadding, dy: 0), colour: .white, font: font, alignment: .center)
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
        let palette = SAClaudeFilterBarStyler.currentPalette
        let themeText = SAClaudeFilterBarStyler.currentThemeText

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }

        let path = FilterCellDrawing.roundedPath(cellFrame.insetBy(dx: 0.5, dy: 0.5), radius: FilterCellDrawing.cornerRadius - 0.5)
        if isHighlighted {
            SAClaudeEditorChrome.derivedColour(text: themeText, background: palette.hover, ratio: 0.08).setFill()
            path.fill()
        }
        path.lineWidth = 1
        SAClaudeFilterChrome.dropStroke(text: themeText, background: palette.background).setStroke()
        path.stroke()

        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        FilterCellDrawing.drawTitle(title, in: cellFrame.insetBy(dx: SAClaudeFilterChrome.pillPadding, dy: 0), colour: themeText,
                                    font: font, alignment: .center)
    }
}

// MARK: - Installing

/// Swaps the filter bar's controls over to the cells above. Every function leaves a control alone unless it is
/// one of the exact AppKit classes below (a control of any other class, such as one KVO has already
/// isa-swizzled, is not ours to change), and never swaps twice.
enum SAClaudeFilterCells {

    /// The private classes AppKit's rule editor builds its pop-ups with.
    private static let ruleEditorPopUpClass = "NSRuleEditorPopupButton"
    private static let ruleEditorPopUpCellClass = "NSRuleEditorPopupButtonCell"
    /// The marker in the names of the runtime subclasses derived below.
    private static let derivedPrefix = "SAClaudeFilterDerived_"
    private static var derivedClasses: [String: AnyClass] = [:]

    /// Whether `cls` is one of the classes this file installs.
    private static func isInstalled(_ cls: AnyClass) -> Bool {
        cls == SAClaudePillPopUpButtonCell.self || cls == SAClaudeCheckboxCell.self || cls == SAClaudeAccentButtonCell.self
            || cls == SAClaudeFullHeightAccentButtonCell.self || cls == SAClaudeSecondaryButtonCell.self
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
    private static let updateLayerSelector = #selector(getter: NSView.wantsUpdateLayer)

    /// The control class to swap `button` (exactly an NSButton) to.
    private static func hostClass(for button: NSButton) -> AnyClass? {
        let cls: AnyClass = type(of: button)
        if cls == NSButton.self { return SAClaudeFilterButton.self }
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
        guard let newViewClass, let newCellClass else { return false }

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
        guard let newViewClass = hostClass(for: button) else { return false }
        object_setClass(button, newViewClass)
        if #available(macOS 14.0, *) { button.clipsToBounds = false }
        hideHostingViews(in: button)
        button.needsDisplay = true
        return true
    }

    /// Draws `button` with `cellClass` (`SAClaudeCheckboxCell` or one of the accent cells) in place of its
    /// own cell. Only an exact NSButton with an exact NSButtonCell is swapped.
    @discardableResult
    static func install(_ cellClass: AnyClass, on button: NSButton) -> Bool {
        guard let cell = button.cell as? NSButtonCell else { return false }
        if hasInstalledClass(cell) { return installCellDrawing(on: button) }
        guard type(of: cell) == NSButtonCell.self, installCellDrawing(on: button) else { return false }
        object_setClass(cell, cellClass)
        button.needsDisplay = true
        return true
    }
}
