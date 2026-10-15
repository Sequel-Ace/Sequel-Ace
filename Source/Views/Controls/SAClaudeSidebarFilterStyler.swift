//
//  SAClaudeSidebarFilterStyler.swift
//  Sequel Ace
//
//  The Claude look of the sidebar's table filter field: a 40pt band above the tables list holding a 28pt
//  rounded fill (radius 8, `SAClaudeStyle.hoverFill`) with the borderless Claude search field inset in it,
//  SF Pro 12, a muted "Filter tables" placeholder and a 1pt accent outline while the field is being edited.
//  The band, the fill and the field are placed by frame: their superview in the XIB is a fixed-frame view.
//  App target only.
//

import AppKit

/// The sidebar filter's cell. Whatever sets the placeholder string (the tables list does on every reload) gets
/// the styled "Filter tables" instead: setting a plain string would drop the attributed placeholder.
private final class SAClaudeSidebarFilterCell: SAClaudeSearchFieldCell {

    override var placeholderString: String? {
        get { SAClaudeSidebarFilterStyler.placeholder }
        set { placeholderAttributedString = SAClaudeSidebarFilterStyler.placeholderText() }
    }
}

@objc(SAClaudeSidebarFilterStyler) final class SAClaudeSidebarFilterStyler: NSObject {

    /// Height of the band the field sits in, above the list.
    static let bandHeight: CGFloat = 40
    /// Height and corner radius of the fill, and its distance from the sidebar's sides.
    static let fillHeight: CGFloat = 28
    static let fillRadius: CGFloat = 8
    static let sideMargin: CGFloat = 8
    /// The field's distance from the fill's sides.
    static let fieldInset: CGFloat = 6

    static let font = NSFont.systemFont(ofSize: 12)
    static let placeholder = NSLocalizedString("ClaudeSidebarFilterPlaceholder", value: "Filter tables",
                                               comment: "sidebar: placeholder of the field that filters the tables list")

    private static var associationKey: UInt8 = 0

    static func placeholderText() -> NSAttributedString {
        NSAttributedString(string: placeholder, attributes: [.foregroundColor: SAClaudeStyle.textMuted, .font: font])
    }

    private weak var field: NSSearchField?
    private weak var fill: SAClaudeConsoleFieldView?
    private weak var focusWindow: NSWindow?
    private var observations: [NSKeyValueObservation] = []
    private var focusObservation: NSKeyValueObservation?

    /// Restyles `field` and gives it its band: `listScrollView` (the tables list, which shares the field's
    /// superview) gives up the band's height at the top. Does nothing a second time for the same field.
    @objc(attachToField:listScrollView:)
    static func attach(to field: NSSearchField, listScrollView: NSScrollView) {
        guard let container = field.superview, listScrollView.superview === container, !container.isFlipped,
              objc_getAssociatedObject(field, &associationKey) == nil else { return }

        let fill = SAClaudeConsoleFieldView()
        let styler = SAClaudeSidebarFilterStyler(field: field, fill: fill)
        objc_setAssociatedObject(field, &associationKey, styler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        place(field: field, fill: fill, listScrollView: listScrollView, in: container)
        container.addSubview(fill, positioned: .below, relativeTo: field)
        styler.styleField()
        styler.observe()
    }

    private init(field: NSSearchField, fill: SAClaudeConsoleFieldView) {
        self.field = field
        self.fill = fill
        super.init()
    }

    // MARK: - Layout

    /// The list keeps the container's bottom, the band takes `bandHeight` of its top; the fill is centred in the
    /// band and the field in the fill. All stay pinned to the top and follow the container's width.
    private static func place(field: NSSearchField, fill: SAClaudeConsoleFieldView, listScrollView: NSScrollView, in container: NSView) {
        let bounds = container.bounds
        listScrollView.frame = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, bounds.height - bandHeight))
        listScrollView.autoresizingMask = [.width, .height]

        let fillFrame = NSRect(x: bounds.minX + sideMargin,
                               y: bounds.maxY - bandHeight + ((bandHeight - fillHeight) / 2).rounded(.down),
                               width: max(0, bounds.width - sideMargin * 2), height: fillHeight)
        fill.frame = fillFrame
        fill.autoresizingMask = [.width, .minYMargin]
        fill.cornerRadius = fillRadius

        let height = ceil(field.cell?.cellSize.height ?? 16)
        field.frame = NSRect(x: fillFrame.minX + fieldInset, y: fillFrame.minY + ((fillHeight - height) / 2).rounded(.down),
                             width: max(0, fillFrame.width - fieldInset * 2), height: height)
        field.autoresizingMask = [.width, .minYMargin]
    }

    // MARK: - Style

    private func styleField() {
        guard let field, let fill else { return }
        SAClaudeSearchFieldCell.install(on: field)
        if let cell = field.cell, Swift.type(of: cell) == SAClaudeSearchFieldCell.self {
            object_setClass(cell, SAClaudeSidebarFilterCell.self)
        }
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Self.font
        fill.onClick = { [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }
        applyColours()
    }

    /// The colours are dynamic; setting them again redraws the field and its fill under the current appearance.
    private func applyColours() {
        guard let field, let fill else { return }
        fill.fillColour = SAClaudeStyle.hoverFill
        field.textColor = SAClaudeStyle.textPrimary
        (field.cell as? NSSearchFieldCell)?.placeholderAttributedString = Self.placeholderText()
        field.needsDisplay = true
        updateFocus()
    }

    // MARK: - Observing

    private func observe() {
        guard let field, let fill else { return }
        // Appearance changes (and the main hop, as the other fields do: the change fires mid-layout).
        observations.append(field.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyColours() }
        })
        // The field is in no window until its tab is shown: follow the first responder of whichever it joins.
        observations.append(fill.observe(\.window, options: [.initial]) { [weak self] fill, _ in
            DispatchQueue.main.async { self?.observeFocus(in: fill.window) }
        })
        SAClaudeAccent.observe(self) { $0.updateFocus() }
    }

    private func observeFocus(in window: NSWindow?) {
        guard window !== focusWindow || focusObservation == nil else { return }
        focusWindow = window
        focusObservation = window?.observe(\.firstResponder) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateFocus() }
        }
        updateFocus()
    }

    /// The accent outline shows while the field's editor is the first responder, and no outline otherwise.
    private func updateFocus() {
        guard let field, let fill else { return }
        let responder = field.window?.firstResponder
        let editing = responder === field || ((responder as? NSText)?.delegate as AnyObject?) === field
        let colour: NSColor? = editing ? SAClaudeAccent.accent : nil
        if fill.borderColour != colour { fill.borderColour = colour }
    }
}
