//
//  SPRuleFilterDropBox.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.04.22.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Cocoa

/// Builds the display text for the live WHERE-clause preview shown in the
/// filter bar. Pure so it can be unit-tested: a usable clause is prefixed
/// with `WHERE `, anything empty collapses to `nil` (the drop box then shows
/// its normal prompt).
@objc public final class SARuleFilterPreviewFormatter: NSObject {
    /// - Parameter clause: The generated WHERE clause, if any.
    /// - Returns: The label text, or `nil` when there is nothing to preview.
    @objc(previewTextForClause:)
    public static func previewText(clause: String?) -> String? {
        guard let trimmed = clause?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return "WHERE " + trimmed
    }
}

/// What a click on the filter bar's drop zone does.
enum SARuleFilterDropBoxClickAction: Equatable {
    /// Append an empty filter row.
    case addFilterRow
    /// Append a nested AND/OR group.
    case addFilterGroup
    /// Open the filter menu (Add Filter, Add AND/OR Group, Copy WHERE Clause).
    case showFilterMenu
}

/// Decides what a click on the drop zone does.
enum SARuleFilterDropBoxClickPolicy {
    /// While the zone shows only its prompt, a click adds a filter row and an
    /// ⌥-click a group, as the prompt says. Once it shows the WHERE preview it
    /// reads as text, and adding a row on a click there came as a surprise, so
    /// a click then opens the filter menu instead - the same one as a
    /// right-click, which also offers to copy the clause.
    ///
    /// - Parameters:
    ///   - showingPreview: Whether the zone currently shows the WHERE preview.
    ///   - optionPressed: Whether ⌥ was held when the button went down.
    /// - Returns: The action for the click.
    static func action(showingPreview: Bool, optionPressed: Bool) -> SARuleFilterDropBoxClickAction {
        if showingPreview {
            return .showFilterMenu
        }
        return optionPressed ? .addFilterGroup : .addFilterRow
    }
}

/// A permanently-visible drop zone rendered next to the rule editor in
/// the Content tab. The view does two jobs:
///
/// * When the user drops a result-grid cell onto it, it asks its
///   `SPFilterRuleEditorDropHandler` to append a fully-populated filter
///   rule (column, default operator, value).
/// * When the user clicks it, it asks the handler to add an empty rule
///   – same semantics as the existing "+ Add Filter" button. ⌥-click (or
///   the context menu) adds a nested AND/OR group instead. While it shows
///   the live WHERE preview, a click opens the filter menu instead (see
///   `SARuleFilterDropBoxClickPolicy`).
///
/// Rendered as a dashed rounded rectangle with a short centred prompt.
/// During a drag the border flips to the system accent colour and the
/// interior fills with the native selection tint so the user has clear
/// affordance that they are hovering over a valid target.
@objc public class SPRuleFilterDropBox: NSView {
    private static let rowDropType = NSPasteboard.PasteboardType(SPCellValuePasteboard.pasteboardRowTypeRaw)

    /// The controller that turns a drop / click into a rule-editor
    /// mutation. Held weakly because the controller owns the view.
    @objc public weak var dropHandler: SPFilterRuleEditorDropHandler?

    private static let promptText = NSLocalizedString("Drop a value here, or click to add a filter", comment: "content tab : rule filter : drop zone prompt")

    private let label: NSTextField = {
        let l = NSTextField(labelWithString: SPRuleFilterDropBox.promptText)
        l.alignment = .center
        l.textColor = .secondaryLabelColor
        l.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        l.isSelectable = false
        // Don't add an ellipsis when the container is tight; the drop
        // box bounds already clip the label visually, and a clipped
        // edge reads better than "add fil…".
        l.lineBreakMode = .byClipping
        // Plain autoresize so we never mix Auto-Layout into the filter
        // container's frame-based layout – the mix was triggering an
        // infinite constraint-update cycle when the container briefly
        // passed through a zero-sized state during Content-tab load.
        l.translatesAutoresizingMaskIntoConstraints = true
        l.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        return l
    }()

    /// Shows a live preview of the WHERE clause the current rules produce, or
    /// falls back to the drop prompt when there is nothing to preview. The
    /// full clause goes into the tooltip since the label is a single line.
    @objc(setPreviewClause:)
    public func setPreviewClause(_ clause: String?) {
        if let text = SARuleFilterPreviewFormatter.previewText(clause: clause) {
            previewClause = clause?.trimmingCharacters(in: .whitespacesAndNewlines)
            isShowingPreview = true
            label.stringValue = text
            // Left-aligned with tail truncation: the clause reads naturally
            // from its start and only the far end is elided - a mid-string
            // ellipsis tears the expression apart.
            label.alignment = .left
            label.lineBreakMode = .byTruncatingTail
            // Full clause plus the interaction hint - the prompt is replaced
            // by the preview, so the tooltip is the only place left for it.
            toolTip = text + "\n\n" + SPRuleFilterDropBox.previewTooltip
            menuIndicator.isHidden = false
        } else {
            previewClause = nil
            isShowingPreview = false
            label.stringValue = SPRuleFilterDropBox.promptText
            label.alignment = .center
            label.lineBreakMode = .byClipping
            toolTip = SPRuleFilterDropBox.promptTooltip
            menuIndicator.isHidden = true
        }
        needsLayout = true
    }

    /// Whether the label currently shows the WHERE preview (left-aligned,
    /// full-width) instead of the centred drop prompt.
    private(set) var isShowingPreview = false

    /// The raw clause behind the current preview (no `WHERE ` prefix), kept
    /// for the context menu's copy action.
    private var previewClause: String?

    /// Copies the previewed clause to the general pasteboard.
    @objc private func copyPreviewClause(_ sender: Any?) {
        guard let previewClause else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(previewClause, forType: .string)
    }

    private static let promptTooltip = NSLocalizedString("Click to add a filter, ⌥-click to add an AND/OR group", comment: "content tab : rule filter : drop zone tooltip")

    private static let previewTooltip = NSLocalizedString("Click for the filter menu: add a filter or an AND/OR group, or copy the WHERE clause", comment: "content tab : rule filter : drop zone tooltip while it shows the WHERE preview")

    /// Marks the WHERE preview as a pull-down menu; hidden while the prompt shows.
    private let menuIndicator: NSImageView = {
        let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: NSFont.smallSystemFontSize, weight: .regular))
        let view = NSImageView(image: image ?? NSImage())
        view.contentTintColor = .secondaryLabelColor
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }()

    private var isDragHovering: Bool = false {
        didSet {
            if isDragHovering != oldValue { needsDisplay = true }
        }
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        addSubview(label)
        addSubview(menuIndicator)
        registerForDraggedTypes([Self.rowDropType])
        toolTip = SPRuleFilterDropBox.promptTooltip
    }

    /// Right-click offers the same "Add Filter" / "Add AND/OR Group" actions
    /// as a plain click / ⌥-click, so the group feature is discoverable –
    /// plus "Copy WHERE Clause" while the preview is showing.
    override public func menu(for event: NSEvent) -> NSMenu? {
        return filterMenu() ?? super.menu(for: event)
    }

    /// The filter menu shown on a right-click, and on a click while the WHERE
    /// preview shows: "Add Filter", "Add AND/OR Group" and, with a preview,
    /// "Copy WHERE Clause".
    ///
    /// - Returns: The menu, or `nil` without a handler to send the actions to.
    func filterMenu() -> NSMenu? {
        guard let handler = dropHandler else { return nil }
        let menu = SARuleFilterContextMenu.menu(for: handler)
        if previewClause != nil {
            menu.addItem(.separator())
            let copyItem = NSMenuItem(
                title: NSLocalizedString("Copy WHERE Clause", comment: "content tab : rule filter : drop zone context menu : copy the previewed WHERE clause"),
                action: #selector(copyPreviewClause(_:)),
                keyEquivalent: ""
            )
            copyItem.target = self
            menu.addItem(copyItem)
        }
        return menu
    }

    override public func layout() {
        super.layout()
        let labelSize = label.intrinsicContentSize
        let y = (bounds.height - labelSize.height) / 2.0
        if isShowingPreview {
            // The preview uses the full width with a small inset, minus the
            // chevron at the right end; the label itself tail-truncates when
            // the clause is longer than the bar.
            let inset: CGFloat = 10
            let indicatorSize = menuIndicator.intrinsicContentSize
            let indicatorX = max(bounds.width - inset - indicatorSize.width, 0)
            menuIndicator.frame = NSRect(x: indicatorX, y: (bounds.height - indicatorSize.height) / 2.0,
                                         width: indicatorSize.width, height: indicatorSize.height)
            label.frame = NSRect(x: inset, y: y, width: max(indicatorX - 4 - inset, 0), height: labelSize.height)
            return
        }
        // Center the prompt at its natural width, but clamp to the drop
        // box's own bounds so a narrow container clips the text inside
        // the dashed border instead of letting it spill outside.
        // `byClipping` on the label prevents a mid-word ellipsis.
        let labelWidth = min(labelSize.width, bounds.width)
        let x = max((bounds.width - labelWidth) / 2.0, 0)
        label.frame = NSRect(x: x, y: y, width: labelWidth, height: labelSize.height)
    }

    override public var acceptsFirstResponder: Bool { false }

    override public func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override public func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: inset, xRadius: 6, yRadius: 6)

        if isDragHovering {
            // Native selection tint + solid accent border.
            NSColor.selectedContentBackgroundColor.setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        } else {
            // Subtle dashed border – the standard empty-placeholder
            // idiom for a drop zone.
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1.0
            path.setLineDash([4.0, 3.0], count: 2, phase: 0)
            path.stroke()
        }
    }

    override public func mouseDown(with event: NSEvent) {
        // Fire the click on mouse-up inside bounds, not immediately on
        // press. This matches standard AppKit button behavior: the user
        // can press, change their mind, drag away, and release without
        // triggering an unwanted empty row. Tracking happens inline via
        // the modal event loop so we don't have to juggle state between
        // mouseDown / mouseDragged / mouseUp.
        guard let window = self.window else { return }
        // ⌥ at press time decides between a plain row and a nested group;
        // read it here so releasing the key mid-press doesn't change it.
        let wantsGroup = event.modifierFlags.contains(.option)
        var tracking = true
        while tracking {
            guard let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { break }
            switch next.type {
            case .leftMouseUp:
                let point = self.convert(next.locationInWindow, from: nil)
                if self.bounds.contains(point) {
                    switch SARuleFilterDropBoxClickPolicy.action(showingPreview: isShowingPreview, optionPressed: wantsGroup) {
                    case .addFilterRow:
                        dropHandler?.addEmptyFilterRow()
                    case .addFilterGroup:
                        dropHandler?.addEmptyFilterGroup()
                    case .showFilterMenu:
                        // Below the bar, left-aligned, like a pull-down menu.
                        let origin = NSPoint(x: bounds.minX, y: isFlipped ? bounds.maxY : bounds.minY)
                        filterMenu()?.popUp(positioning: nil, at: origin, in: self)
                    }
                }
                tracking = false
            default:
                break
            }
        }
    }

    // MARK: - NSDraggingDestination

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrop(sender) else { return [] }
        isDragHovering = true
        return .copy
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return acceptsDrop(sender) ? .copy : []
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHovering = false
    }

    override public func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return acceptsDrop(sender)
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { isDragHovering = false }
        guard
            let plist = sender.draggingPasteboard.propertyList(forType: Self.rowDropType) as? [String: Any],
            let columnName = plist[SPCellValuePasteboard.rowColumnNameKey] as? String,
            !columnName.isEmpty,
            let handler = dropHandler
        else {
            return false
        }
        let value = plist[SPCellValuePasteboard.rowValueKey] as? String
        let isNull = (plist[SPCellValuePasteboard.rowValueKindKey] as? String) == SPCellValuePasteboard.rowValueKindNull
        return handler.appendFilter(forColumn: columnName, value: value, isNull: isNull)
    }

    override public func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isDragHovering = false
    }

    private func acceptsDrop(_ sender: NSDraggingInfo) -> Bool {
        return sender.draggingPasteboard.availableType(from: [Self.rowDropType]) != nil && dropHandler != nil
    }
}
