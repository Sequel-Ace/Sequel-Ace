//
//  SPFilterRuleEditor.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.04.19.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Cocoa

/// Protocol the rule editor and the drop box use to ask their controller
/// to mutate the current filter set from a dropped cell payload.
/// `SPRuleFilterController` adopts this via its existing Objective-C
/// methods – there's no bespoke Swift surface.
@objc public protocol SPFilterRuleEditorDropHandler: AnyObject {
    /// Append a fully-populated rule to the current filter set without
    /// running the filter. The user presses Apply Filters (or Return in
    /// any argument field) to actually query.
    ///
    /// - Returns: `true` if a rule was appended.
    @objc(appendFilterForColumn:value:isNull:)
    func appendFilter(forColumn columnName: String, value: String?, isNull: Bool) -> Bool

    /// Replace the rule at `row` (0-indexed top-level row in the rule
    /// editor) with a fully-populated rule derived from the drop.
    ///
    /// - Returns: `true` if the rule was replaced.
    @objc(replaceFilterAtRow:forColumn:value:isNull:)
    func replaceFilter(at row: Int, forColumn columnName: String, value: String?, isNull: Bool) -> Bool

    /// Insert an empty filter row (same as clicking the "+" button), or check
    /// an unchecked row without a value when there is one instead of adding a
    /// second empty row (see `SARuleFilterPendingStarter.reusableEmptyRow`).
    /// Used when the user clicks the drop box instead of dropping onto it.
    @objc(addEmptyFilterRow)
    func addEmptyFilterRow()

    /// Append a nested AND/OR group holding one empty filter row – the
    /// discoverable equivalent of ⌥-clicking a row's "+" button.
    /// Used by the context menus and by ⌥-clicking the drop box.
    @objc(addEmptyFilterGroup)
    func addEmptyFilterGroup()
}

/// Context menu shared by the rule editor and its drop box. It exists to
/// surface the nested-group feature: `NSRuleEditor` only offers it via
/// ⌥-click on a row's "+" button, which nobody discovers on their own.
enum SARuleFilterContextMenu {
    /// Builds a fresh menu whose items send `addEmptyFilterRow` /
    /// `addEmptyFilterGroup` to `handler` (held weakly by the menu items).
    static func menu(for handler: SPFilterRuleEditorDropHandler) -> NSMenu {
        let menu = NSMenu()
        let addFilter = NSMenuItem(
            title: NSLocalizedString("Add Filter", comment: "table Content : rule filter editor : context menu : add filter row"),
            action: #selector(SPFilterRuleEditorDropHandler.addEmptyFilterRow),
            keyEquivalent: ""
        )
        addFilter.target = handler
        menu.addItem(addFilter)
        let addGroup = NSMenuItem(
            title: NSLocalizedString("Add AND/OR Group", comment: "table Content : rule filter editor : context menu : add nested AND/OR group"),
            action: #selector(SPFilterRuleEditorDropHandler.addEmptyFilterGroup),
            keyEquivalent: ""
        )
        addGroup.target = handler
        menu.addItem(addGroup)
        return menu
    }
}

/// Tracks the filter rows that are seeded empty and wait for their first edit: the row the
/// content view seeds when another table is selected, and the row each new AND/OR group
/// brings. Such a row starts unchecked - it is an empty template, not a filter, and a checked
/// one made the WHERE preview show `column = ''` while the table was unfiltered. Its first
/// edit checks it; a click on its checkbox is the user's own decision and ends the tracking.
///
/// Every waiting row is tracked on its own. With a single tracked row, a group added before the
/// one before it had been filled in took its place, and the row left behind no longer reacted
/// to being edited - so its condition was missing from the WHERE clause.
///
/// Only a weak reference to each row's checkbox is kept, so a removed or replaced row simply
/// stops being tracked; the controller records the state in the saved filter so a restored row
/// is tracked again.
@objc public final class SARuleFilterPendingStarter: NSObject {

    /// One row waiting for its first edit.
    private final class SAWaitingRow {
        /// The row's enable checkbox, held weakly so a row that is gone stops being tracked
        /// by itself.
        weak var checkbox: NSButton?

        /// Clears the mark a restored row carries, run when this row's tracking ends.
        var clearRestoredMark: (() -> Void)?

        /// - Parameters:
        ///   - checkbox: The row's enable checkbox.
        ///   - clearRestoredMark: Clears the mark a restored row carries.
        init(checkbox: NSButton, clearRestoredMark: (() -> Void)?) {
            self.checkbox = checkbox
            self.clearRestoredMark = clearRestoredMark
        }

        /// Ends this row's tracking and lets a restored row forget that it was ever waiting.
        func endTracking() {
            checkbox = nil
            clearRestoredMark?()
            clearRestoredMark = nil
        }
    }

    /// The rows waiting for their first edit, in no particular order: "Add Filter" inserts at the
    /// top, so the order rows began waiting in says nothing about where they sit. `waitingRows`
    /// puts them in the order the editor shows them, which is what the callers ask about.
    private var waiting: [SAWaitingRow] = []

    /// Tracks `checkbox`'s row as waiting and unchecks it.
    ///
    /// - Parameters:
    ///   - checkbox: The row's enable checkbox.
    ///   - clearRestoredMark: Clears the mark a restored row carries, called once that row's
    ///     tracking ends. A restored row keeps that mark so that tracking resumes whenever its
    ///     checkbox is built again - the editor rebuilds it on a reload, before the row has been
    ///     edited - which is also why the mark has to go the moment the row stops waiting.
    ///     Without that, a later rebuild would uncheck a row the user has since enabled.
    @objc(beginWithCheckbox:clearingRestoredMark:)
    public func begin(with checkbox: NSButton, clearingRestoredMark clearRestoredMark: (() -> Void)?) {
        checkbox.state = .off
        // A checkbox already tracked is the same row waiting again, so its mark stays: dropping
        // the old entry without ending its tracking is what lets the next rebuild find it.
        waiting.removeAll { $0.checkbox == nil || $0.checkbox === checkbox }
        waiting.append(SAWaitingRow(checkbox: checkbox, clearRestoredMark: clearRestoredMark))
    }

    /// Stops tracking the row `value` is the checkbox of, e.g. because the user clicked it.
    ///
    /// - Parameter value: A display value of the rule editor; anything else is ignored.
    @objc(forgetCheckbox:)
    public func forgetCheckbox(_ value: Any?) {
        guard let button = value as? NSButton else { return }
        var remaining: [SAWaitingRow] = []
        var ended: [SAWaitingRow] = []
        for entry in waiting {
            guard let box = entry.checkbox else { continue }
            if box === button { ended.append(entry) } else { remaining.append(entry) }
        }
        waiting = remaining
        ended.forEach { $0.endTracking() }
    }

    /// Stops tracking `row`.
    ///
    /// - Parameters:
    ///   - row: The row to stop tracking.
    ///   - editor: The rule editor holding it.
    @objc(forgetRow:inEditor:)
    public func forgetRow(_ row: Int, in editor: NSRuleEditor) {
        guard row != NSNotFound, row >= 0, row < editor.numberOfRows else { return }
        forgetCheckbox(editor.displayValues(forRow: row).first)
    }

    /// Whether `value` is the checkbox of a row that is waiting.
    ///
    /// - Parameter value: A display value of the rule editor.
    /// - Returns: Whether it is a waiting row's checkbox.
    @objc public func isCheckbox(_ value: Any?) -> Bool {
        guard let button = value as? NSButton else { return false }
        return waiting.contains { $0.checkbox === button }
    }

    /// The index of the first waiting row of the top-level list, or `NSNotFound` when there is
    /// none.
    ///
    /// A row inside an AND/OR group is not one: the caller replaces a row of the top-level
    /// list, which a nested row's index does not address.
    ///
    /// - Parameter editor: The rule editor holding the row.
    /// - Returns: The row index.
    @objc(rowInEditor:)
    public func row(in editor: NSRuleEditor) -> Int {
        return waitingRows(in: editor).first { editor.parentRow(forRow: $0.row) == -1 }?.row ?? NSNotFound
    }

    /// A seeded row of the top-level list, while it is still the empty template it was seeded
    /// as, or `NSNotFound`.
    ///
    /// "Add Filter" checks that row instead of adding a second empty one beside it. Only a
    /// seeded row counts. A row the user switched on once was a filter, and unchecking it sets
    /// that filter aside - including one whose value is the empty string, which from the
    /// editor's state alone looks exactly like a row nothing was ever typed into. Reusing it
    /// switched a filter the user had put away back on and put the cursor in it, so the next
    /// keystroke replaced it.
    ///
    /// - Parameter editor: The rule editor holding the row.
    /// - Returns: The row index.
    @objc(reusableEmptyRowInEditor:)
    public func reusableEmptyRow(in editor: NSRuleEditor) -> Int {
        return waitingRows(in: editor).first { isReusableEmptyRow($0.row, in: editor) }?.row ?? NSNotFound
    }

    /// Checks `row` when it is one of the waiting rows and stops tracking it: editing a row
    /// means filtering by it.
    ///
    /// - Parameters:
    ///   - row: The row that is being edited.
    ///   - editor: The rule editor holding it.
    /// - Returns: Whether a waiting row was checked.
    @objc(enableIfRow:inEditor:)
    public func enableIfRow(_ row: Int, in editor: NSRuleEditor) -> Bool {
        guard row != NSNotFound, row >= 0,
              let match = waitingRows(in: editor).first(where: { $0.row == row }) else { return false }
        match.entry.checkbox?.state = .on
        waiting.removeAll { $0 === match.entry }
        match.entry.endTracking()
        return true
    }

    /// The waiting rows with their index in `editor`, lowest index first; the rows that are no
    /// longer in the editor stop being tracked.
    ///
    /// Their mark is left alone: a row out of the editor is one being rebuilt as often as one
    /// that is gone, and the mark is what lets the rebuilt one resume waiting.
    ///
    /// - Parameter editor: The rule editor holding the rows.
    /// - Returns: The rows and their indexes.
    private func waitingRows(in editor: NSRuleEditor) -> [(row: Int, entry: SAWaitingRow)] {
        var alive: [SAWaitingRow] = []
        var found: [(row: Int, entry: SAWaitingRow)] = []
        for entry in waiting {
            guard let box = entry.checkbox else { continue }
            let row = editor.row(forDisplayValue: box)
            guard row != NSNotFound, row >= 0 else { continue }
            alive.append(entry)
            found.append((row: row, entry: entry))
        }
        waiting = alive
        return found.sorted { $0.row < $1.row }
    }

    /// Whether `row` is still the empty template a seeded row is.
    ///
    /// - Parameters:
    ///   - row: The row to judge.
    ///   - editor: The rule editor holding it.
    /// - Returns: Whether "Add Filter" may use it.
    private func isReusableEmptyRow(_ row: Int, in editor: NSRuleEditor) -> Bool {
        guard editor.parentRow(forRow: row) == -1, editor.rowType(forRow: row) == .simple else {
            return false
        }
        let values = editor.displayValues(forRow: row)
        guard let checkbox = values.first as? NSButton, checkbox.state == .off else { return false }
        let fields = values.compactMap { $0 as? NSTextField }
        return !fields.isEmpty && fields.allSatisfy { $0.stringValue.isEmpty }
    }
}

/// Keeps the rule editor's visibility setter free of model mutations when it
/// is only reapplying an already-visible state during table reloads.
@objc public final class SARuleFilterVisibilityPolicy: NSObject {
    /// A starter rule belongs to the first application of a saved visible
    /// preference (including after a blank-state reset), an explicit
    /// hidden-to-visible transition, or a switch to another table. Reapplying
    /// `visible` while rebuilding the current table must be idempotent, even
    /// when the transiently rebuilt model is empty.
    @objc(shouldAddStarterRuleWithVisibilityWasApplied:wasVisible:willBeVisible:tableChanged:editorIsEmpty:)
    public static func shouldAddStarterRule(
        visibilityWasApplied: Bool,
        wasVisible: Bool,
        willBeVisible: Bool,
        tableChanged: Bool,
        editorIsEmpty: Bool
    ) -> Bool {
        return (!visibilityWasApplied || !wasVisible || tableChanged) && willBeVisible && editorIsEmpty
    }
}

/// Presentation strings and checks for a group row's AND/OR choice, kept in
/// Swift so the Objective-C rule-editor delegate only forwards to it.
@objc public final class SARuleFilterConjunctionRowPresentation: NSObject {
    /// The static label shown after a group row's AND/OR popup, clarifying
    /// that the choice combines the group's own conditions.
    @objc public static var explainerText: String {
        return NSLocalizedString("combines the conditions in this group", comment: "table Content : rule filter editor : compound row : label after the AND/OR popup")
    }

    /// Whether the string is one of the two conjunction choices (as opposed
    /// to the explainer label, which is also rendered from a plain string).
    @objc(isConjunctionChoice:)
    public static func isConjunctionChoice(_ value: String?) -> Bool {
        return value == "AND" || value == "OR"
    }
}

/// What `-[SPRuleFilterController ruleEditorRowsDidChange:]` should do about
/// the container size after the rule editor reported a rows change.
@objc public enum SARuleFilterResizeAction: Int {
    /// The row count did not change – nothing to resize.
    case none
    /// Resize right away.
    case immediate
    /// Resize after `SARuleFilterResizePolicy.deferredResizeDelay`.
    case deferred
}

/// Decides when the filter container follows a rows change in the rule editor.
///
/// `NSRuleEditor` posts its rows-did-change notification several times per
/// click on "+" / "−", and not every post means the number of rows changed.
/// Scheduling a delayed resize for each of them (the pre-2026 behaviour)
/// stacked delay and container animations on top of the rule editor's own row
/// animation, which made the buttons feel like they hang. The policy turns a
/// (row count, previous row count) pair into a single action:
///
/// * unchanged count → nothing;
/// * growing → resize immediately, so the container makes room while the
///   rule editor animates the new row in (both animations run concurrently);
/// * shrinking → wait for the rule editor's removal animation first, because
///   resizing the container underneath it makes the remaining rows jump.
///
/// The caller is expected to cancel any pending deferred resize before acting
/// on the returned action, so one gesture ends in one resize.
@objc public final class SARuleFilterResizePolicy: NSObject {
    /// Delay for `.deferred`, matching the rule editor's row-removal animation.
    @objc public static let deferredResizeDelay: TimeInterval = 0.2

    /// Picks the resize action for a rows-did-change notification.
    ///
    /// - Parameters:
    ///   - rowCount: The rule editor's row count after the change.
    ///   - previousRowCount: The row count the controller last acted on.
    /// - Returns: `.none` when the count is unchanged, `.immediate` when rows
    ///   were added, `.deferred` when rows were removed.
    @objc(actionForRowCount:previousRowCount:)
    public static func action(rowCount: Int, previousRowCount: Int) -> SARuleFilterResizeAction {
        if rowCount == previousRowCount {
            return .none
        }
        return rowCount > previousRowCount ? .immediate : .deferred
    }
}

/// Immutable layout values consumed by the legacy table-content controller.
/// Keeping the policy in Swift makes the Objective-C call site a thin view
/// trampoline and gives the preference combinations direct unit coverage.
@objc public final class SARuleFilterDropZoneLayoutMetrics: NSObject {
    @objc public let dropZoneVisible: Bool
    @objc public let dropZoneReservedHeight: CGFloat
    @objc public let ruleEditorOriginY: CGFloat
    @objc public let containerRequestedHeight: CGFloat

    fileprivate init(
        dropZoneVisible: Bool,
        dropZoneReservedHeight: CGFloat,
        ruleEditorOriginY: CGFloat,
        containerRequestedHeight: CGFloat
    ) {
        self.dropZoneVisible = dropZoneVisible
        self.dropZoneReservedHeight = dropZoneReservedHeight
        self.ruleEditorOriginY = ruleEditorOriginY
        self.containerRequestedHeight = containerRequestedHeight
    }
}

/// Controls whether the optional filter drop zone participates in layout.
/// Missing preferences deliberately preserve the existing visible behavior for
/// users upgrading from versions that predate the setting.
@objc public final class SARuleFilterDropZoneLayoutPolicy: NSObject {
    private static let preferenceKey = "RuleFilterShowDropZone"

    @objc(defaultsKey)
    public static var defaultsKey: String {
        return preferenceKey
    }

    @objc(metricsWithEditorVisible:editorHasRows:requestedHeight:dropZoneHeight:userDefaults:)
    public static func metrics(
        editorVisible: Bool,
        editorHasRows: Bool,
        requestedHeight: CGFloat,
        dropZoneHeight: CGFloat,
        userDefaults: UserDefaults
    ) -> SARuleFilterDropZoneLayoutMetrics {
        let showDropZone = userDefaults.object(forKey: preferenceKey).map { _ in
            userDefaults.bool(forKey: preferenceKey)
        } ?? true

        return metrics(
            editorVisible: editorVisible,
            editorHasRows: editorHasRows,
            requestedHeight: requestedHeight,
            dropZoneHeight: dropZoneHeight,
            showDropZonePreference: showDropZone
        )
    }

    /// Height of the bottom bar when the drop zone is hidden: just enough for
    /// the button row (Apply/Add Filter + AND/OR popup, 27 pt plus padding).
    private static let buttonBarHeight: CGFloat = 31

    static func metrics(
        editorVisible: Bool,
        editorHasRows: Bool,
        requestedHeight: CGFloat,
        dropZoneHeight: CGFloat,
        showDropZonePreference: Bool
    ) -> SARuleFilterDropZoneLayoutMetrics {
        let effectiveEditorHasRows = editorVisible && editorHasRows
        let dropZoneVisible = editorVisible && showDropZonePreference

        // The bottom bar (drop zone, AND/OR popup, Apply/Add Filter buttons)
        // is always reserved while the filter UI is visible: the rule editor
        // rows span the full width above it and must never overlap it. With
        // the drop zone hidden the bar shrinks to the plain button row.
        let bottomBarHeight = editorVisible ? (dropZoneVisible ? max(dropZoneHeight, 0) : buttonBarHeight) : 0
        let ruleEditorTopMargin: CGFloat = effectiveEditorHasRows ? 1 : 0
        let ruleEditorHeight = effectiveEditorHasRows ? max(requestedHeight, 29) + ruleEditorTopMargin : 0

        return SARuleFilterDropZoneLayoutMetrics(
            dropZoneVisible: dropZoneVisible,
            dropZoneReservedHeight: bottomBarHeight,
            ruleEditorOriginY: bottomBarHeight + ruleEditorTopMargin,
            containerRequestedHeight: editorVisible ? bottomBarHeight + ruleEditorHeight : 0
        )
    }
}

/// `NSRuleEditor` subclass that extends the content-tab filter with
/// drag-and-drop support for the
/// `SPCellValuePasteboard.pasteboardRowTypeRaw` payload. Dropping a
/// result-grid cell onto an existing rule replaces that entire rule
/// with a new one derived from the dropped cell (column + default
/// operator + value). Appending fresh rules is handled separately by
/// `SPRuleFilterDropBox`, so the user can choose between "replace this
/// rule" and "add a new rule" purely by target.
@objc public class SPFilterRuleEditor: NSRuleEditor {
    private static let rowDropType = NSPasteboard.PasteboardType(SPCellValuePasteboard.pasteboardRowTypeRaw)

    /// Thin accent-coloured rectangle drawn around the row the drag is
    /// hovering over. Added the first time a drag enters, moved on
    /// every `draggingUpdated`, and torn down on exit / drop so we pay
    /// no drawing cost outside an active drag.
    private var highlightOverlay: SPFilterRuleEditorHighlight?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([Self.rowDropType])
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([Self.rowDropType])
    }

    /// Right-click on a row's background (the controls inside a row keep
    /// their own menus) offers the same add-row / add-group actions as the
    /// drop box, so the nested-group feature is reachable without ⌥-click.
    override public func menu(for event: NSEvent) -> NSMenu? {
        guard let handler = self.delegate as? SPFilterRuleEditorDropHandler else {
            return super.menu(for: event)
        }
        return SARuleFilterContextMenu.menu(for: handler)
    }

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return dragOperation(for: sender)
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return dragOperation(for: sender)
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        clearHighlight()
    }

    override public func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return row(for: sender) != nil
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { clearHighlight() }
        guard
            let row = row(for: sender),
            let plist = sender.draggingPasteboard.propertyList(forType: Self.rowDropType) as? [String: Any],
            let columnName = plist[SPCellValuePasteboard.rowColumnNameKey] as? String,
            !columnName.isEmpty,
            let handler = self.delegate as? SPFilterRuleEditorDropHandler
        else {
            return false
        }
        let value = plist[SPCellValuePasteboard.rowValueKey] as? String
        let isNull = (plist[SPCellValuePasteboard.rowValueKindKey] as? String) == SPCellValuePasteboard.rowValueKindNull
        // The handler addresses top-level (root) children, but `row` is the
        // flat visible index, which also counts the subrows of nested groups
        // - map it to the ordinal among top-level rows before handing over.
        return handler.replaceFilter(at: topLevelOrdinal(forRow: row), forColumn: columnName, value: value, isNull: isNull)
    }

    /// The position of a top-level row among the top-level rows only - i.e.
    /// the index of the corresponding root child in the serialized tree.
    /// (`row` itself must be a top-level row.)
    private func topLevelOrdinal(forRow row: Int) -> Int {
        return (0..<row).reduce(0) { $0 + (parentRow(forRow: $1) == -1 ? 1 : 0) }
    }

    override public func concludeDragOperation(_ sender: NSDraggingInfo?) {
        clearHighlight()
    }

    /// Returns a copy drag operation only when the drop lies over an
    /// existing top-level rule – that's the only valid target for the
    /// rule editor itself (the drop box handles the append case).
    /// Side-effect: updates the highlight overlay so the user sees which
    /// rule is about to be replaced.
    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard let row = row(for: sender) else {
            clearHighlight()
            return []
        }
        showHighlight(forRow: row)
        return .copy
    }

    /// Resolve the dragging point to a top-level row index, or `nil`
    /// when the cursor is outside the editor, no rows are dropped on,
    /// or the pasteboard doesn't carry our custom type. Row frames are
    /// computed from `rowHeight` rather than by hit-testing display
    /// views – NSRuleEditor can reuse the same display view across
    /// rows that share a criterion node, so a view-frame union is
    /// unreliable.
    private func row(for sender: NSDraggingInfo) -> Int? {
        guard sender.draggingPasteboard.availableType(from: [Self.rowDropType]) != nil else { return nil }
        guard self.delegate is SPFilterRuleEditorDropHandler else { return nil }
        let point = convert(sender.draggingLocation, from: nil)
        let rowH = self.rowHeight
        guard rowH > 0 else { return nil }

        // NSRuleEditor lays row 0 out at the top. When the view is
        // flipped, y grows downward so row index = floor(y / rowHeight);
        // otherwise row 0 starts at bounds.maxY and we invert.
        let y = isFlipped ? point.y : (bounds.maxY - point.y)
        let index = Int(floor(y / rowH))
        guard index >= 0, index < numberOfRows else { return nil }
        // Drop target must be a top-level simple rule: a compound
        // (AND / OR) row can't be "replaced" with a single expression, and
        // a nested subrow belongs to its group, not to the root. Both are
        // rejected; the user can use the drop box to append a new rule
        // instead. A plain top-level row next to a nested group IS a valid
        // target - performDragOperation maps the visible index to the root
        // child ordinal for the handler.
        guard parentRow(forRow: index) == -1 else { return nil }
        guard rowType(forRow: index) == .simple else { return nil }
        return index
    }

    private func showHighlight(forRow row: Int) {
        let rowH = self.rowHeight
        guard rowH > 0 else { return }
        let y: CGFloat = isFlipped
            ? CGFloat(row) * rowH
            : bounds.maxY - CGFloat(row + 1) * rowH
        // A 2pt inset keeps the border inside the row's own cell, so
        // it never bleeds into neighbouring rows.
        let frame = NSRect(x: 0, y: y, width: bounds.width, height: rowH).insetBy(dx: 2, dy: 2)

        if let overlay = highlightOverlay {
            overlay.frame = frame
        } else {
            let overlay = SPFilterRuleEditorHighlight(frame: frame)
            // Frontmost subview so the border is drawn on top of the
            // row's popup / checkbox / text field; the overlay is only
            // a stroke, so the cells remain fully visible – and it
            // ignores hit-testing, so they stay interactive too.
            addSubview(overlay, positioned: .above, relativeTo: subviews.last)
            highlightOverlay = overlay
        }
    }

    private func clearHighlight() {
        highlightOverlay?.removeFromSuperview()
        highlightOverlay = nil
    }
}

/// Thin rounded border drawn around the rule row a drag is hovering
/// over. Kept as a border only – never a filled tile – so it can't be
/// mistaken for, or obscured by, any tinting NSRuleEditor applies to
/// rows on drag-over. Hit-testing is disabled so the row's popups,
/// checkbox, and text field remain interactive through the overlay.
private final class SPFilterRuleEditorHighlight: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // transparent to mouse events
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
        path.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
