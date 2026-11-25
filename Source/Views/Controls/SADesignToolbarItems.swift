//
//  SADesignToolbarItems.swift
//  Sequel Ace
//
//  Draws the main window toolbar's image items as buttons: an outline
//  glyph, a hover fill, and an accent-tinted chip with an accent glyph
//  (made readable on the chip) on the selected view. Identifiers, labels,
//  tooltips, targets, actions and validation stay the document's; only the
//  drawing changes. App target only.
//

import AppKit

/// The main window toolbar. It keeps the selected view itself rather than passing it to AppKit, which
/// would draw its own selection bezel and accent-colored label under the chip; the document
/// reads and writes the selection through this same property, so nothing else changes.
@objc(SADesignToolbar) final class SADesignToolbar: NSToolbar {
    private var designSelectedItemIdentifier: NSToolbarItem.Identifier?

    override var selectedItemIdentifier: NSToolbarItem.Identifier? {
        get { designSelectedItemIdentifier }
        set {
            designSelectedItemIdentifier = newValue
            items.forEach { $0.view?.needsDisplay = true }
        }
    }
}

@objc(SADesignToolbarItems) final class SADesignToolbarItems: NSObject {

    @objc static var defaultItemIdentifiers: [String] { SADesignToolbarLayout.defaultItems }

    /// A custom-drawn copy of an image item with a glyph; any other item is returned unchanged. `willBeInserted` is
    /// the toolbar delegate's flag: false when the Customize Toolbar palette asks for the item.
    @objc(styledItem:willBeInsertedIntoToolbar:)
    static func styled(_ item: NSToolbarItem?, willBeInserted: Bool) -> NSToolbarItem? {
        guard let item else { return nil }
        // No system bezel (the glass capsule on recent macOS): the views draw their own pills.
        item.isBordered = false
        if let control = item.view {
            // The document's database pop-up and history control: one instance per window, which every request for
            // the item hands over. The palette gets an inert copy instead, so it never takes the live control out of
            // the toolbar.
            if !willBeInserted {
                if let copying = control as? SADesignToolbarPalettePreviewing {
                    item.view = SADesignToolbarItemContainer(preview: copying.palettePreview())
                }
                return item
            }
            // A segmented control still gets the glass capsule; inside a plain container it's a custom view. A control
            // already in its container (the item re-inserted, the layout reset) keeps it.
            if let control = control as? NSSegmentedControl {
                item.view = (control.superview as? SADesignToolbarItemContainer) ?? SADesignToolbarItemContainer(wrapping: control)
                // Its control sets the item's enabled state (the Table History label follows its chevrons).
                item.autovalidates = false
            }
            return item
        }
        guard let glyph = SADesignToolbarLayout.glyph(for: item.itemIdentifier.rawValue) else { return item }
        let styled = SADesignToolbarItem(itemIdentifier: item.itemIdentifier)
        styled.isBordered = false
        styled.label = item.label
        styled.paletteLabel = item.paletteLabel
        styled.toolTip = item.toolTip
        styled.target = item.target
        styled.action = item.action

        let button = SADesignToolbarButton(glyph: glyph, selectable: SADesignToolbarLayout.selectableItems.contains(item.itemIdentifier.rawValue))
        button.target = item.target
        button.action = item.action
        button.toolTip = item.toolTip
        button.setAccessibilityLabel(item.label)
        button.toolbarItem = styled
        styled.view = button

        let menuItem = NSMenuItem(title: item.label, action: item.action, keyEquivalent: "")
        menuItem.target = item.target
        menuItem.image = SADesignGlyphs.image(glyph, tint: SADesignStyle.textMuted)
        styled.menuFormRepresentation = menuItem
        return styled
    }
}

/// A toolbar control the window owns once (the database pop-up, the history control): it draws a copy of itself for
/// the Customize Toolbar palette, with no target, action or menu of its own.
protocol SADesignToolbarPalettePreviewing: NSView {
    func palettePreview() -> NSView
}

/// The rounded-rect focus ring of the toolbar's 8pt-radius fills.
enum SADesignToolbarFocusRing {
    static let radius: CGFloat = 8

    static func drawMask(_ rect: NSRect) {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}

/// A view-based item that still asks its target to validate it, as image items do.
@objc(SADesignToolbarItem) final class SADesignToolbarItem: NSToolbarItem {
    // NSToolbarItem forwards setImage: to its view, and -[SPDatabaseDocument validateToolbarItem:] sets the
    // Console item's image on every validation pass; store it without touching (and invalidating) the button.
    private var storedImage: NSImage?
    override var image: NSImage? {
        get { storedImage }
        set { storedImage = newValue }
    }

    override func validate() {
        var enabled = true
        if let action, let target = target as? NSObject {
            let selector = NSSelectorFromString("validateToolbarItem:")
            if target.responds(to: selector) {
                typealias Validate = @convention(c) (AnyObject, Selector, NSToolbarItem) -> Bool
                let implementation = unsafeBitCast(target.method(for: selector), to: Validate.self)
                enabled = implementation(target, selector, self)
            } else {
                enabled = target.responds(to: action)
            }
        }
        isEnabled = enabled
        (view as? NSControl)?.isEnabled = enabled
    }
}

/// The 40×32 toolbar button (20pt glyph).
final class SADesignToolbarButton: NSButton {

    weak var toolbarItem: NSToolbarItem?
    private let glyph: SADesignGlyph
    private let showsSelection: Bool
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    init(glyph: SADesignGlyph, selectable: Bool) {
        self.glyph = glyph
        self.showsSelection = selectable
        super.init(frame: NSRect(x: 0, y: 0, width: 40, height: 32))
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = .noImage
        configure()
    }

    private static let glyphKey = "SADesignToolbarButtonGlyph"
    private static let selectableKey = "SADesignToolbarButtonSelectable"

    /// A copy AppKit archived (`encode(with:)`); nil when the coder doesn't carry a glyph.
    required init?(coder: NSCoder) {
        guard coder.containsValue(forKey: Self.glyphKey),
              let glyph = SADesignGlyph(rawValue: coder.decodeInteger(forKey: Self.glyphKey)) else { return nil }
        self.glyph = glyph
        showsSelection = coder.decodeBool(forKey: Self.selectableKey)
        super.init(coder: coder)
        configure()
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(glyph.rawValue, forKey: Self.glyphKey)
        coder.encode(showsSelection, forKey: Self.selectableKey)
    }

    private func configure() {
        // The selected glyph is drawn in the accent: redraw (it re-renders the tinted image) when it changes.
        SADesignAccent.observe(self) { $0.needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 32) }

    private var isSelectedItem: Bool {
        guard showsSelection, let item = toolbarItem else { return false }
        return item.toolbar?.selectedItemIdentifier == item.itemIdentifier
    }

    override func isAccessibilitySelected() -> Bool { isSelectedItem }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    // The keyboard focus ring follows the button's rounded fill.
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { SADesignToolbarFocusRing.drawMask(bounds) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    /// The selected view's chip: the accent at the vivid palette's tint alpha (its glyph is `selectedGlyph`).
    static func selectedFill(dark: Bool) -> NSColor {
        SADesignAccent.accent.withAlphaComponent(dark ? SAVividColor.tintAlphaDark : SAVividColor.tintAlphaLight)
    }

    /// The selected view's glyph: the accent, made readable on the chip (its tint over the toolbar background).
    static func selectedGlyph(dark: Bool) -> NSColor {
        let chip = SADesignAccent.composite(selectedFill(dark: dark), over: SADesignStyle.toolbarBackground, dark: dark)
        return SADesignAccent.readableGlyph(on: chip, dark: dark)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.intersection(dirtyRect).clip()

        let selected = isSelectedItem
        let pressed = cell?.isHighlighted ?? false
        if selected || (isEnabled && (isHovered || pressed)) {
            (selected ? Self.selectedFill(dark: isDark) : SADesignStyle.hoverFill).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: SADesignToolbarFocusRing.radius, yRadius: SADesignToolbarFocusRing.radius).fill()
        }
        let tint = selected ? Self.selectedGlyph(dark: isDark) : SADesignStyle.textMuted
        let image = SADesignGlyphs.image(glyph, tint: tint)
        let rect = NSRect(x: bounds.midX - 10, y: bounds.midY - 10, width: 20, height: 20)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.35, respectFlipped: true, hints: nil)
    }
}

/// A plain view hosting a toolbar control, so the toolbar treats the item as a custom view and draws no
/// system bezel around it. The control stays the same object (its outlets and actions are unchanged).
final class SADesignToolbarItemContainer: NSView {
    /// Hosts a palette preview: clicks reach the palette (which drags the item), never the copy.
    private var isPreview = false

    init(wrapping control: NSView) {
        super.init(frame: NSRect(origin: .zero, size: control.intrinsicContentSize))
        translatesAutoresizingMaskIntoConstraints = false
        control.removeFromSuperview()
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor),
            control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.topAnchor.constraint(equalTo: topAnchor),
            control.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Hosts `copy`, a control's palette preview: not clickable, not focusable, not a separate accessibility element.
    convenience init(preview copy: NSView) {
        self.init(wrapping: copy)
        isPreview = true
        (copy as? NSControl)?.refusesFirstResponder = true
        copy.setAccessibilityElement(false)
    }

    /// A copy AppKit archived: its subviews and constraints come back with it.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isPreview ? nil : super.hitTest(point)
    }
}
