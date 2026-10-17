//
//  SARecordView.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import SwiftUI

struct SARecordField: Identifiable, Equatable {
    var id: Int
    var name: String
    var value: String
    /// The column definition's type (`VARCHAR`, `JSON`, ...); empty when unknown.
    var type: String = ""
    /// SQL NULL, as opposed to an empty string or the text "NULL".
    var isNull = false
    /// A BLOB/TEXT value that has not been loaded yet.
    var notLoaded = false
}

enum SARecordViewFocusTarget: Equatable {
    case table
    case filter
}

enum SARecordViewFocusAction: Equatable {
    case recordView
    case resultTable
    case filter
}

/// A key the panel handles itself (the AppKit key monitor routes it; SwiftUI's key handling needs macOS 14).
enum SARecordViewPanelKey: Equatable {
    /// ↑ (-1) / ↓ (+1) on the field blocks.
    case moveSelection(Int)
    /// Return on a selected block.
    case editSelection
    /// ⌥↑ (-1) / ⌥↓ (+1): the previous / next row.
    case stepRow(Int)
    /// A printable character on a selected block starts a search with it.
    case search(String)
    /// Escape in the search field.
    case escapeSearch
    /// ↓ in the search field moves to the field blocks.
    case focusFields
}

@objc final class SARecordViewEditSupport: NSObject {
    @objc(validateValue:withFormatter:)
    static func validate(_ value: String, with formatter: Formatter?) -> String? {
        guard let formatter else {
            return value
        }

        if formatter is SABaseFormatter {
            let pointer = UnsafeMutablePointer<NSString>.allocate(capacity: 1)
            pointer.initialize(to: value as NSString)
            defer {
                pointer.deinitialize(count: 1)
                pointer.deallocate()
            }
            let partialString = AutoreleasingUnsafeMutablePointer<NSString>(pointer)
            let selection = NSRange(location: value.utf16.count, length: 0)
            return formatter.isPartialStringValid(
                partialString,
                proposedSelectedRange: nil,
                originalString: value,
                originalSelectedRange: selection,
                errorDescription: nil
            ) ? pointer.pointee as String : nil
        }

        var replacement: NSString?
        return formatter.isPartialStringValid(
            value,
            newEditingString: &replacement,
            errorDescription: nil
        ) ? value : replacement as String?
    }
}

/// Resolves record view fields to result table columns. A field is identified
/// by its column's identifier - the data column index - rather than by its
/// on-screen position: columns can be reordered by dragging and hidden by the
/// column filter while a record is shown, so a position recorded when the
/// record view was filled can name a different column by the time an edit
/// begins or commits, and the edit would silently change the wrong field.
@objc final class SARecordViewColumnMapping: NSObject {
    /// The table column currently showing a field, wherever it was moved.
    ///
    /// - Parameters:
    ///   - fieldID: The field ID, i.e. the data column index of the column.
    ///   - tableView: The result table.
    /// - Returns: The column, or `nil` when the column is hidden or the ID is invalid.
    @objc(tableColumnForFieldID:inTableView:)
    static func tableColumn(forFieldID fieldID: Int, in tableView: NSTableView) -> NSTableColumn? {
        guard fieldID >= 0 else {
            return nil
        }
        return tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(String(fieldID)))
    }
}

/// The fields a search shows, with where each matching field matched.
struct SARecordViewSearchResult {
    var fields: [SARecordField]
    /// Matches by field ID; empty when there is no query.
    var matches: [Int: SAClaudeRecordMatch]
    /// Matching fields (the field being edited is shown even when it doesn't match, but not counted).
    var matchCount: Int
}

final class SARecordViewModel: ObservableObject {
    @Published private(set) var selectedRowCount = 0
    @Published private(set) var fields: [SARecordField] = []
    /// 0-based position of the shown row in its grid; -1 when unknown.
    @Published private(set) var rowIndex = -1
    /// Rows currently in the grid; 0 when unknown.
    @Published private(set) var rowCount = 0
    /// The table name (Content) or "Query result" (Query).
    @Published private(set) var title = ""
    @Published var searchText = ""
    @Published var selectedFieldID: SARecordField.ID?
    @Published var editingFieldID: SARecordField.ID?
    @Published var focusedFieldID: SARecordField.ID?
    @Published var editDraft = ""
    @Published private(set) var focusRequestID = 0
    /// Which long values are expanded; belongs to the shown row (`SAClaudeRecordFields.carry`).
    @Published private(set) var panelState = SAClaudeRecordPanelState(rowKey: "", expandedFieldIDs: [])
    private(set) var focusTarget: SARecordViewFocusTarget?
    /// Bumped by every `update`: caches keyed by it (display values, measured lines) drop the previous snapshot's.
    private(set) var generation = 0
    /// Names the field list a row shows: the row (`panelState.rowKey`) and its columns. A refresh of the same row
    /// keeps it; another row, or the same row position in a different result (a re-run query), changes it.
    private(set) var listKey = ""

    var beginEditing: ((Int) -> Bool)?
    var validateEditing: ((Int, String) -> String?)?
    var commitEditing: ((Int, String) -> Bool)?
    /// Asks the host to select the previous (-1) or next (+1) row.
    var rowStepHandler: ((Int) -> Void)?
    /// Makes the field blocks (the panel itself) the first responder.
    var focusPanelHandler: (() -> Void)?
    /// Gives the keyboard back to the grid.
    var focusGridHandler: (() -> Void)?

    /// `displayValue` per field ID for the current snapshot: JSON is parsed and long values capped once per row,
    /// not on every search keystroke or body pass.
    private var displayCache: [Int: SAClaudeRecordDisplayValue] = [:]
    private var searchCache: (query: String, editingFieldID: Int?, generation: Int, result: SARecordViewSearchResult)?

    func display(for field: SARecordField) -> SAClaudeRecordDisplayValue {
        if let cached = displayCache[field.id] {
            return cached
        }
        let display = SAClaudeRecordFields.displayValue(field)
        displayCache[field.id] = display
        return display
    }

    /// The search over names and displayed values (`SAClaudeRecordFields.match`), memoised per query, edited
    /// field and snapshot.
    var searchResult: SARecordViewSearchResult {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cache = searchCache, cache.query == query, cache.editingFieldID == editingFieldID, cache.generation == generation {
            return cache.result
        }
        var result = SARecordViewSearchResult(fields: [], matches: [:], matchCount: 0)
        if query.isEmpty {
            result.fields = fields
        } else {
            for field in fields {
                if let match = SAClaudeRecordFields.match(field, display: display(for: field), query: query) {
                    result.fields.append(field)
                    result.matches[field.id] = match
                    result.matchCount += 1
                } else if field.id == editingFieldID {
                    result.fields.append(field)
                }
            }
        }
        searchCache = (query, editingFieldID, generation, result)
        return result
    }

    var visibleFields: [SARecordField] {
        searchResult.fields
    }

    var canFocusTable: Bool {
        selectedRowCount == 1 && !visibleFields.isEmpty
    }

    func update(fields: [SARecordField],
                selectedRowCount: Int,
                rowIndex: Int = -1,
                rowCount: Int = 0,
                title: String = "") {
        let previousSelection = selectedFieldID
        cancelEdit()
        self.selectedRowCount = selectedRowCount
        self.rowIndex = rowIndex
        self.rowCount = rowCount
        self.title = title
        generation += 1
        displayCache = [:]
        searchCache = nil
        self.fields = selectedRowCount == 1 ? fields : []
        panelState = SAClaudeRecordFields.carry(panelState, toRowKey: selectedRowCount == 1 ? "\(title)#\(rowIndex)" : "")
        var columns = Hasher()
        for field in self.fields {
            columns.combine(field.id)
            columns.combine(field.name)
        }
        listKey = "\(panelState.rowKey)|\(self.fields.count)|\(columns.finalize())"
        // The selected field follows a refresh or a row step when the new snapshot still has it.
        selectedFieldID = self.fields.contains { $0.id == previousSelection } ? previousSelection : nil
    }

    func clear() {
        searchText = ""
        update(fields: [], selectedRowCount: 0)
    }

    func isExpanded(_ fieldID: SARecordField.ID) -> Bool {
        panelState.expandedFieldIDs.contains(fieldID)
    }

    /// "Show all N lines" / "Show less".
    func toggleExpanded(_ fieldID: SARecordField.ID) {
        if panelState.expandedFieldIDs.remove(fieldID) == nil {
            panelState.expandedFieldIDs.insert(fieldID)
        }
    }

    /// Moves to the previous (-1) or next (+1) row through the host. Does
    /// nothing at the ends or without rows; an edit in progress is committed
    /// first and, if that fails, the panel stays on the row.
    func stepRow(_ delta: Int) {
        let step = SAClaudeRecordFields.rowStep(index: rowIndex, count: rowCount)
        guard (delta < 0 && step.previous) || (delta > 0 && step.next) else {
            return
        }
        if editingFieldID != nil {
            commitEdit()
            guard editingFieldID == nil else {
                return
            }
        }
        rowStepHandler?(delta < 0 ? -1 : 1)
    }

    // MARK: - Keyboard on the field blocks

    /// A click on a block: selects it and gives the panel the keyboard.
    func selectField(_ fieldID: SARecordField.ID) {
        selectedFieldID = fieldID
        focusPanelHandler?()
    }

    /// ↑ / ↓ over the visible fields; never wraps. Without a visible selection, selects the first visible field.
    func moveSelection(by delta: Int) {
        let visible = visibleFields
        guard !visible.isEmpty else {
            return
        }
        guard let index = visible.firstIndex(where: { $0.id == selectedFieldID }) else {
            selectedFieldID = visible.first?.id
            return
        }
        selectedFieldID = visible[min(max(index + delta, 0), visible.count - 1)].id
    }

    /// Return on a selected block.
    func editSelectedField() {
        guard let field = visibleFields.first(where: { $0.id == selectedFieldID }) else {
            return
        }
        requestEdit(field)
    }

    /// A printable character typed while a block is selected starts (or continues) the search with it.
    func typeIntoSearch(_ characters: String) {
        guard selectedFieldID != nil, !characters.isEmpty else {
            return
        }
        searchText += characters
        requestFocus(.filter)
    }

    /// Escape in the search field: clears the search; with nothing to clear, returns the keyboard to the grid.
    func escapeInSearch() {
        if searchText.isEmpty {
            focusGridHandler?()
        } else {
            searchText = ""
        }
    }

    func requestEdit(_ field: SARecordField) {
        guard beginEditing?(field.id) == true else {
            return
        }
        let field = fields.first { $0.id == field.id } ?? field
        editingFieldID = field.id
        focusedFieldID = field.id
        editDraft = field.value
    }

    func requestFocus(_ target: SARecordViewFocusTarget) {
        if target == .table && !visibleFields.contains(where: { $0.id == selectedFieldID }) {
            selectedFieldID = visibleFields.first?.id
        }
        focusTarget = target
        focusRequestID += 1
        if target == .table {
            focusPanelHandler?()
        }
    }

    func commitEdit() {
        guard let fieldID = editingFieldID,
              commitEditing?(fieldID, editDraft) == true else {
            return
        }
        cancelEdit()
    }

    /// Keypath-bindable draft that routes writes through validation.
    ///
    /// SwiftUI cannot compare closure-built `Binding(get:set:)` pairs, so a
    /// text field fed one is re-evaluated on every body pass. Binding
    /// `$model.validatedEditDraft` instead derives the binding through a
    /// stable key path SwiftUI can compare — the pre-`@Bindable` equivalent
    /// of the `@Bindable` + subscript pattern (`@Bindable` needs macOS 14).
    var validatedEditDraft: String {
        get { editDraft }
        set { updateEditDraft(newValue) }
    }

    func updateEditDraft(_ value: String) {
        guard let fieldID = editingFieldID else {
            return
        }
        guard let validateEditing else {
            editDraft = value
            return
        }
        if let value = validateEditing(fieldID, value) {
            editDraft = value
        }
    }

    func editorFocusChanged(_ fieldID: SARecordField.ID?) {
        if fieldID == nil { commitEdit() }
    }

    func cancelEdit() {
        editingFieldID = nil
        focusedFieldID = nil
        editDraft = ""
    }
}

private final class SARecordViewResizeHandle: NSView {
    weak var overlayView: SARecordViewOverlayView?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        overlayView?.mouseDown(with: event)
    }
}

private final class SARecordViewOverlayView: NSView {
    weak var resizedView: NSView?
    weak var resizeHandle: NSView?
    var resizedViewRightInset: CGFloat = 0
    var widthDefaultsKey = ""
    var recordViewWidth: CGFloat = 320

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }
        let startX = event.locationInWindow.x
        let startWidth = frame.width

        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                UserDefaults.standard.set(recordViewWidth, forKey: widthDefaultsKey)
                return
            }
            resize(to: startWidth + startX - next.locationInWindow.x)
        }
    }

    func show() {
        isHidden = false
        resize(to: recordViewWidth)
        if let resizeHandle {
            window?.invalidateCursorRects(for: resizeHandle)
        }
    }

    func hide() {
        guard let parent = superview, let resizedView else {
            return
        }
        var resizedFrame = resizedView.frame
        resizedFrame.size.width = parent.bounds.width - resizedFrame.minX - resizedViewRightInset
        resizedView.frame = resizedFrame
        isHidden = true
    }

    private func resize(to proposedWidth: CGFloat) {
        guard let parent = superview, let resizedView else {
            return
        }
        recordViewWidth = min(max(proposedWidth, 240), parent.bounds.width)

        frame = NSRect(
            x: parent.bounds.width - recordViewWidth,
            y: frame.minY,
            width: recordViewWidth,
            height: frame.height
        )

        var resizedFrame = resizedView.frame
        resizedFrame.size.width = max(frame.minX - resizedFrame.minX - 1, 0)
        resizedView.frame = resizedFrame
    }
}

@objc final class SARecordViewToolbarSupport: NSObject {
    private static let contentIdentifier = "SwitchToTableContentToolbarItemIdentifier"
    private static let queryIdentifier = "SwitchToRunQueryToolbarItemIdentifier"

    @objc static let itemIdentifier = "RecordViewToolbarItemIdentifier"

    @objc(hostIdentifierForTabIndex:)
    static func hostIdentifier(forTabIndex index: Int) -> String? {
        switch index {
        case 1: return contentIdentifier
        case 2: return queryIdentifier
        default: return nil
        }
    }

    static func shouldHandleSpace(_ event: NSEvent,
                                  firstResponder: NSResponder?,
                                  tableView: NSTableView,
                                  recordView: NSView) -> Bool {
        let modifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.type == .keyDown,
              event.keyCode == 49,
              !event.isARepeat,
              event.modifierFlags.intersection(modifiers).isEmpty,
              let firstResponder else {
            return false
        }
        if firstResponder === tableView {
            return true
        }
        guard !(firstResponder is NSTextField),
              !(firstResponder is NSTextView),
              let responderView = firstResponder as? NSView else {
            return false
        }
        return responderView === recordView || responderView.isDescendant(of: recordView)
    }

    static func focusAction(_ event: NSEvent,
                            firstResponder: NSResponder?,
                            tableView: NSTableView,
                            recordView: NSView,
                            isRecordViewVisible: Bool,
                            canFocusRecordView: Bool) -> SARecordViewFocusAction? {
        guard isRecordViewVisible,
              event.type == .keyDown,
              !event.isARepeat,
              let firstResponder else {
            return nil
        }

        let modifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let activeModifiers = event.modifierFlags.intersection(modifiers)
        if event.keyCode == 124,
           activeModifiers.isEmpty,
           firstResponder === tableView,
           canFocusRecordView {
            return .recordView
        }

        guard !(firstResponder is NSTextField),
              !(firstResponder is NSTextView),
              let responderView = firstResponder as? NSView,
              responderView === recordView || responderView.isDescendant(of: recordView) else {
            return nil
        }
        if event.keyCode == 123 && activeModifiers.isEmpty {
            return .resultTable
        }
        if event.charactersIgnoringModifiers?.lowercased() == "f", activeModifiers == .command {
            return .filter
        }
        return nil
    }

    /// The panel's own keys. On the field blocks (the panel focused, not a text field): ↑/↓ move the selection,
    /// Return edits it, ⌥↑/⌥↓ step rows, a printable character (no ⌘/⌃) with a block selected starts a search.
    /// In the search field: Escape, ↓ to the blocks, ⌥↑/⌥↓. The inline value editor keeps all its keys.
    static func panelKeyAction(_ event: NSEvent,
                               firstResponder: NSResponder?,
                               recordView: NSView,
                               isRecordViewVisible: Bool,
                               isEditing: Bool,
                               hasSelection: Bool) -> SARecordViewPanelKey? {
        guard isRecordViewVisible,
              event.type == .keyDown,
              let responderView = firstResponder as? NSView,
              responderView === recordView || responderView.isDescendant(of: recordView) else {
            return nil
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let vertical: Int? = event.keyCode == 126 ? -1 : event.keyCode == 125 ? 1 : nil

        if firstResponder is NSTextField || firstResponder is NSTextView {
            guard !isEditing else {
                return nil
            }
            if let vertical, modifiers == .option {
                return .stepRow(vertical)
            }
            if vertical == 1, modifiers.isEmpty {
                return .focusFields
            }
            if event.keyCode == 53, modifiers.isEmpty {
                return .escapeSearch
            }
            return nil
        }

        if let vertical {
            if modifiers == .option {
                return .stepRow(vertical)
            }
            return modifiers.isEmpty ? .moveSelection(vertical) : nil
        }
        guard hasSelection else {
            return nil
        }
        if (event.keyCode == 36 || event.keyCode == 76) && modifiers.isEmpty {
            return .editSelection
        }
        if modifiers.isDisjoint(with: [.command, .control]),
           let characters = event.characters,
           isPrintable(characters) {
            return .search(characters)
        }
        return nil
    }

    /// Text a key types into a field: no control characters (Return, Tab, Escape, Delete) and none of the
    /// function-key private-use characters (arrows, F-keys, Home/End).
    static func isPrintable(_ characters: String) -> Bool {
        !characters.isEmpty && characters.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }

    @objc(makeToolbarItemWithTarget:)
    static func makeToolbarItem(target: AnyObject) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier(itemIdentifier))
        item.label = NSLocalizedString("Record View", comment: "record view toolbar item label")
        item.paletteLabel = item.label
        item.toolTip = NSLocalizedString("Toggle Record View", comment: "record view toolbar item tooltip")
        item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
            ?? NSImage(named: NSImage.Name("NSListViewTemplate"))
        item.target = target
        item.action = NSSelectorFromString("toggleRecordView:")
        return item
    }
}

@objc final class SARecordViewController: NSObject {
    private let model = SARecordViewModel()
    /// The Claude panel (SAClaudeRecordPanel.swift, app target; a stand-in in Unit Tests): its hosting view, the
    /// editor-theme palette it draws with, and the overlay's live hairline and surface.
    private lazy var panel = MainActor.assumeIsolated { SARecordViewPanelHost(model: model) }
    private var panelView: NSView { MainActor.assumeIsolated { panel.view } }
    private weak var overlayView: SARecordViewOverlayView?
    private weak var shortcutTableView: NSTableView?
    private var shortcutMonitor: Any?
    private var showHandler: (() -> Void)?

    deinit {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
    }

    @objc(installOverlayInView:resizingView:shortcutTableView:bottomInset:topInset:autosaveName:)
    func installOverlay(in parentView: NSView,
                        resizing targetView: NSView,
                        shortcutTableView: NSTableView,
                        bottomInset: CGFloat,
                        topInset: CGFloat,
                        autosaveName: String) {
        self.shortcutTableView = shortcutTableView
        model.focusPanelHandler = { [weak self] in
            guard let self, let window = self.panelView.window, window.firstResponder !== self.panelView else {
                return
            }
            window.makeFirstResponder(self.panelView)
        }
        model.focusGridHandler = { [weak self] in
            guard let tableView = self?.shortcutTableView else {
                return
            }
            tableView.window?.makeFirstResponder(tableView)
        }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let tableView = self.shortcutTableView else {
                return event
            }
            let firstResponder = event.window?.firstResponder
            let recordView = self.panelView
            if SARecordViewToolbarSupport.shouldHandleSpace(
                event,
                firstResponder: firstResponder,
                tableView: tableView,
                recordView: recordView
            ) {
                self.toggle()
                return nil
            }
            switch SARecordViewToolbarSupport.focusAction(
                event,
                firstResponder: firstResponder,
                tableView: tableView,
                recordView: recordView,
                isRecordViewVisible: self.isVisible,
                canFocusRecordView: self.model.canFocusTable
            ) {
            case .recordView:
                self.model.requestFocus(.table)
                return nil
            case .resultTable:
                tableView.window?.makeFirstResponder(tableView)
                return nil
            case .filter:
                self.model.requestFocus(.filter)
                return nil
            case nil:
                break
            }
            guard let action = SARecordViewToolbarSupport.panelKeyAction(
                event,
                firstResponder: firstResponder,
                recordView: recordView,
                isRecordViewVisible: self.isVisible,
                isEditing: self.model.editingFieldID != nil,
                hasSelection: self.model.selectedFieldID != nil
            ) else {
                return event
            }
            self.perform(action)
            return nil
        }

        let savedWidth = UserDefaults.standard.double(forKey: autosaveName)
        let width = min(savedWidth >= 240 ? savedWidth : 320, parentView.bounds.width)
        let container = SARecordViewOverlayView(frame: NSRect(
            x: parentView.bounds.width - width,
            y: bottomInset,
            width: width,
            height: max(parentView.bounds.height - bottomInset - topInset, 0)
        ))
        container.autoresizingMask = [.minXMargin, .height]
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.resizedView = targetView
        container.resizedViewRightInset = parentView.bounds.width - targetView.frame.maxX
        container.widthDefaultsKey = autosaveName
        container.recordViewWidth = width

        let panelView = self.panelView
        panelView.frame = container.bounds
        panelView.autoresizingMask = [.width, .height]
        container.addSubview(panelView)
        // The palette's surface behind the panel and its hairline down the left edge, live.
        MainActor.assumeIsolated { panel.style(container) }

        let resizeHandle = SARecordViewResizeHandle(frame: NSRect(x: 0, y: 0, width: 10, height: container.bounds.height))
        resizeHandle.autoresizingMask = [.height]
        resizeHandle.overlayView = container
        container.addSubview(resizeHandle, positioned: .above, relativeTo: nil)
        container.resizeHandle = resizeHandle

        container.isHidden = true
        parentView.addSubview(container, positioned: .above, relativeTo: nil)
        overlayView = container
    }

    private func perform(_ action: SARecordViewPanelKey) {
        switch action {
        case .moveSelection(let delta):
            model.moveSelection(by: delta)
        case .editSelection:
            model.editSelectedField()
        case .stepRow(let delta):
            model.stepRow(delta)
        case .search(let characters):
            model.typeIntoSearch(characters)
            placeSearchCaretAtEnd()
        case .escapeSearch:
            model.escapeInSearch()
        case .focusFields:
            model.requestFocus(.table)
        }
    }

    /// A search started by typing on a block keeps what was typed: the search field selects its whole text when it
    /// takes focus, so once SwiftUI has moved focus there (a run-loop turn or two) the caret goes to the end.
    private func placeSearchCaretAtEnd(attempts: Int = 4) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            let panelView = self.panelView
            guard let editor = panelView.window?.firstResponder as? NSTextView, editor.isDescendant(of: panelView) else {
                if attempts > 1 {
                    self.placeSearchCaretAtEnd(attempts: attempts - 1)
                }
                return
            }
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }

    @objc var isVisible: Bool {
        overlayView?.isHidden == false
    }

    @objc(setShowHandler:)
    func setShowHandler(_ handler: @escaping () -> Void) {
        showHandler = handler
    }

    @objc func toggle() {
        guard let overlayView else {
            return
        }
        if overlayView.isHidden {
            overlayView.show()
            showHandler?()
        } else {
            overlayView.hide()
            if let shortcutTableView {
                shortcutTableView.window?.makeFirstResponder(shortcutTableView)
            }
        }
    }

    @objc(updateWithFields:selectedRowCount:)
    func update(with dictionaries: [NSDictionary], selectedRowCount: Int) {
        update(with: dictionaries, selectedRowCount: selectedRowCount, rowIndex: -1, rowCount: 0, title: "")
    }

    @objc(updateWithFields:selectedRowCount:rowIndex:rowCount:title:)
    func update(with dictionaries: [NSDictionary],
                selectedRowCount: Int,
                rowIndex: Int,
                rowCount: Int,
                title: String) {
        assert(Thread.isMainThread)
        model.update(
            fields: Self.fields(from: dictionaries),
            selectedRowCount: selectedRowCount,
            rowIndex: rowIndex,
            rowCount: rowCount,
            title: title
        )
    }

    /// Registers the host callback that selects the previous (-1) or next (+1) row.
    @objc(setRowStepHandler:)
    func setRowStepHandler(_ handler: @escaping (Int) -> Void) {
        model.rowStepHandler = handler
    }

    static func fields(from dictionaries: [NSDictionary]) -> [SARecordField] {
        dictionaries.enumerated().map { index, dictionary in
            SARecordField(
                id: (dictionary["id"] as? NSNumber)?.intValue ?? index,
                name: dictionary["name"] as? String ?? "",
                value: dictionary["value"] as? String ?? "",
                type: dictionary["type"] as? String ?? "",
                isNull: (dictionary["isNull"] as? NSNumber)?.boolValue ?? false,
                notLoaded: (dictionary["notLoaded"] as? NSNumber)?.boolValue ?? false
            )
        }
    }

    @objc func clear() {
        assert(Thread.isMainThread)
        model.clear()
    }

    @objc(setEditingHandlersWithBegin:validate:commit:)
    func setEditingHandlers(
        begin: @escaping (Int) -> Bool,
        validate: @escaping (Int, String) -> String?,
        commit: @escaping (Int, String) -> Bool
    ) {
        model.beginEditing = begin
        model.validateEditing = validate
        model.commitEditing = commit
    }
}
