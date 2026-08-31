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

/// A permanently-visible drop zone rendered next to the rule editor in
/// the Content tab. The view does two jobs:
///
/// * When the user drops a result-grid cell onto it, it asks its
///   `SPFilterRuleEditorDropHandler` to append a fully-populated filter
///   rule (column, default operator, value).
/// * When the user clicks it, it asks the handler to add an empty rule
///   – same semantics as the existing "+ Add Filter" button. ⌥-click (or
///   the context menu) adds a nested AND/OR group instead.
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
            isShowingPreview = true
            label.stringValue = text
            // Left-aligned with tail truncation: the clause reads naturally
            // from its start and only the far end is elided - a mid-string
            // ellipsis tears the expression apart.
            label.alignment = .left
            label.lineBreakMode = .byTruncatingTail
            // Full clause plus the interaction hint - the prompt is replaced
            // by the preview, so the tooltip is the only place left for it.
            toolTip = text + "\n\n" + SPRuleFilterDropBox.promptTooltip
        } else {
            isShowingPreview = false
            label.stringValue = SPRuleFilterDropBox.promptText
            label.alignment = .center
            label.lineBreakMode = .byClipping
            toolTip = SPRuleFilterDropBox.promptTooltip
        }
        needsLayout = true
    }

    /// Whether the label currently shows the WHERE preview (left-aligned,
    /// full-width) instead of the centred drop prompt.
    private var isShowingPreview = false

    private static let promptTooltip = NSLocalizedString("Click to add a filter, ⌥-click to add an AND/OR group", comment: "content tab : rule filter : drop zone tooltip")

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
        registerForDraggedTypes([Self.rowDropType])
        toolTip = SPRuleFilterDropBox.promptTooltip
    }

    /// Right-click offers the same "Add Filter" / "Add AND/OR Group" actions
    /// as a plain click / ⌥-click, so the group feature is discoverable.
    override public func menu(for event: NSEvent) -> NSMenu? {
        guard let handler = dropHandler else { return super.menu(for: event) }
        return SARuleFilterContextMenu.menu(for: handler)
    }

    override public func layout() {
        super.layout()
        let labelSize = label.intrinsicContentSize
        let y = (bounds.height - labelSize.height) / 2.0
        if isShowingPreview {
            // The preview uses the full width with a small inset; the label
            // itself tail-truncates when the clause is longer than the bar.
            let inset: CGFloat = 10
            label.frame = NSRect(x: inset, y: y, width: max(bounds.width - 2 * inset, 0), height: labelSize.height)
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
                    if wantsGroup {
                        dropHandler?.addEmptyFilterGroup()
                    } else {
                        dropHandler?.addEmptyFilterRow()
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
