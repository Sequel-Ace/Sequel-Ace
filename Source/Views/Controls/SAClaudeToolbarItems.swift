//
//  SAClaudeToolbarItems.swift
//  Sequel Ace
//
//  Draws the main window toolbar's image items as Claude buttons: a 16pt
//  outline glyph, a hover fill, and a pill with a clay glyph on the selected
//  view. Identifiers, labels, tooltips, targets, actions and validation stay
//  the document's; only the drawing changes. App target only.
//

import AppKit

/// The main window toolbar: redraws its Claude buttons when the selected view changes.
@objc(SAClaudeToolbar) final class SAClaudeToolbar: NSToolbar {
    override var selectedItemIdentifier: NSToolbarItem.Identifier? {
        didSet { items.forEach { $0.view?.needsDisplay = true } }
    }
}

@objc(SAClaudeToolbarItems) final class SAClaudeToolbarItems: NSObject {

    @objc static var defaultItemIdentifiers: [String] { SAClaudeToolbarLayout.defaultItems }

    /// A Claude-drawn copy of an image item with a Claude glyph; any other item is returned unchanged.
    @objc(styledItem:)
    static func styled(_ item: NSToolbarItem?) -> NSToolbarItem? {
        guard let item, item.view == nil, let glyph = SAClaudeToolbarLayout.glyph(for: item.itemIdentifier.rawValue) else { return item }
        let styled = SAClaudeToolbarItem(itemIdentifier: item.itemIdentifier)
        styled.label = item.label
        styled.paletteLabel = item.paletteLabel
        styled.toolTip = item.toolTip
        styled.target = item.target
        styled.action = item.action

        let button = SAClaudeToolbarButton(glyph: glyph, selectable: SAClaudeToolbarLayout.selectableItems.contains(item.itemIdentifier.rawValue))
        button.target = item.target
        button.action = item.action
        button.toolTip = item.toolTip
        button.setAccessibilityLabel(item.label)
        button.toolbarItem = styled
        styled.view = button

        let menuItem = NSMenuItem(title: item.label, action: item.action, keyEquivalent: "")
        menuItem.target = item.target
        menuItem.image = SAClaudeGlyphs.image(glyph, tint: SAClaudeStyle.textMuted)
        styled.menuFormRepresentation = menuItem
        return styled
    }
}

/// A view-based item that still asks its target to validate it, as image items do.
@objc(SAClaudeToolbarItem) final class SAClaudeToolbarItem: NSToolbarItem {
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

/// The 36×28 Claude toolbar button.
final class SAClaudeToolbarButton: NSButton {

    weak var toolbarItem: NSToolbarItem?
    private let glyph: SAClaudeGlyph
    private let showsSelection: Bool
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    init(glyph: SAClaudeGlyph, selectable: Bool) {
        self.glyph = glyph
        self.showsSelection = selectable
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = .noImage
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 36, height: 28) }

    private var isSelectedItem: Bool {
        guard showsSelection, let item = toolbarItem else { return false }
        return item.toolbar?.selectedItemIdentifier == item.itemIdentifier
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.intersection(dirtyRect).clip()

        let selected = isSelectedItem
        let pressed = cell?.isHighlighted ?? false
        if selected || (isEnabled && (isHovered || pressed)) {
            (selected ? SAClaudeStyle.selection : SAClaudeStyle.hoverFill).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        let tint = selected ? SAClaudeStatusChrome.clay : SAClaudeStyle.textMuted
        let image = SAClaudeGlyphs.image(glyph, tint: tint)
        let rect = NSRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.35, respectFlipped: true, hints: nil)
    }
}
