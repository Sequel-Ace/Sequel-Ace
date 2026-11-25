//
//  SADesignMenuCard.swift
//  Sequel Ace
//
//  The card a main-window dropdown opens instead of its native menu: rows built from the
//  control's NSMenu by `SADesignMenuCardModel` (which stays the source of truth and stays attached,
//  so shortcuts keep working), an optional search field, keyboard highlight, ⌥ alternates, and a
//  pick that does what picking the native item does. One shared presenter (a transient NSPopover
//  with SwiftUI content) serves every control; per-control adapters supply the entries and the
//  palette. App target only.
//

import AppKit
import SwiftUI

// MARK: - Palette

/// The card's colors, which each adapter picks. `app(for:)` follows Sequel Ace's appearance (the toolbar's
/// cards, like the toolbar pills). The tick is the accent, made readable on the surface and on a highlighted row.
struct SADesignMenuCardPalette {
    var surface, text, muted, hairline, hover, selected, tick: NSColor
    var isDark: Bool

    /// The palette's colors resolved in `view`'s appearance.
    static func app(for view: NSView) -> Self {
        let appearance = view.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        func resolved(_ color: NSColor) -> NSColor {
            var result = color
            appearance.performAsCurrentDrawingAppearance {
                result = NSColor(cgColor: color.cgColor) ?? color
            }
            return result
        }
        let surface = resolved(SADesignStyle.cardSurface)
        let hover = resolved(SADesignStyle.hoverFill)
        let selected = resolved(SADesignStyle.selection)
        return Self(surface: surface,
                    text: resolved(SADesignStyle.textPrimary),
                    muted: resolved(SADesignStyle.textMuted),
                    hairline: resolved(SADesignStyle.cardHairline),
                    hover: hover,
                    selected: selected,
                    tick: SADesignAccent.readableGlyph(on: surface, hover, selected, dark: isDark),
                    isDark: isDark)
    }
}

// MARK: - Adapter

/// What a control tells the card: its entries (headers, footer, details, glyphs) and its palette.
///
/// Row rendering from an entry: `detail` set → two lines (title, then the detail in mono, at most two
/// lines). `detail` set and `title` empty or equal to `detail` → a detail-only row: the text in mono,
/// at most two lines.
protocol SADesignMenuCardAdapter: AnyObject {
    var hasSearch: Bool { get }
    var searchPlaceholder: String { get }
    /// The menu's entries (`SADesignMenuCardModel.entries(from:skipping:)` plus the adapter's marks);
    /// nil refuses the card and the caller opens the native menu.
    func entries(for menu: NSMenu) -> [SADesignMenuEntry]?
    func palette(for control: NSView) -> SADesignMenuCardPalette
    /// Called as the adapter's card opens. An adapter whose palette follows something beyond the accent and the app's
    /// appearance (which the presenter already watches) registers that source here with
    /// `SADesignMenuCardPresenter.followStyleSource(_:start:)`. Default: nothing.
    func cardWillOpen(in presenter: SADesignMenuCardPresenter)
}

extension SADesignMenuCardAdapter {
    func cardWillOpen(in presenter: SADesignMenuCardPresenter) {}
}

// MARK: - Presenter

/// Shows one card at a time, anchored to its control.
final class SADesignMenuCardPresenter: NSObject, NSPopoverDelegate {

    static let shared = SADesignMenuCardPresenter()

    /// Everything that lives while one card is up.
    private final class Session {
        let popover: NSPopover
        let model: SADesignMenuCardViewModel
        let adapter: SADesignMenuCardAdapter
        let menu: NSMenu
        /// The menu's items when the card opened, by index: a row fires the item it was built from, even when the menu
        /// was rebuilt or reordered under the open card (entry indices point into this, not into the live menu).
        let items: [NSMenuItem]
        weak var control: NSView?
        let onClose: (() -> Void)?

        init(popover: NSPopover, model: SADesignMenuCardViewModel, adapter: SADesignMenuCardAdapter, menu: NSMenu,
             items: [NSMenuItem], control: NSView, onClose: (() -> Void)?) {
            self.popover = popover
            self.model = model
            self.adapter = adapter
            self.menu = menu
            self.items = items
            self.control = control
            self.onClose = onClose
        }
    }

    private var session: Session?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var watchingStyle = false
    /// The extra style sources adapters registered (`followStyleSource`), by id.
    private var styleSources: Set<String> = []
    private var appearanceObservation: NSKeyValueObservation?
    /// The mouse-down that closed a transient card: the same click reaching its control must not reopen it.
    private weak var lastClosedControl: NSView?
    private var lastClosingMouseDown: TimeInterval?
    /// Type-to-jump on cards without search.
    private var typeSelectBuffer = ""
    private var typeSelectTime: TimeInterval = 0

    private static let minRoomBelow: CGFloat = 200

    /// The control whose card is open, if any.
    var shownControl: NSView? { session?.control }

    /// Opens the card for `menu` anchored to `control` (to `anchorRect`, in the control's coordinates, when given),
    /// or closes it when it is already open for `control`. Returns false when the card refuses the menu: the caller
    /// opens the native menu instead. `onClose` runs once when this card closes, whatever closes it (the control
    /// drops its pressed look then).
    @discardableResult
    func show(menu: NSMenu, from control: NSView, adapter: SADesignMenuCardAdapter, anchorRect: NSRect? = nil,
              onClose: (() -> Void)? = nil) -> Bool {
        if let session, session.control === control {
            close()
            return true
        }
        if isClosingClick(on: control) { return true }
        guard control.window != nil else { return fallback("control is not in a window") }
        if session != nil { close() }

        menu.update()
        guard let entries = adapter.entries(for: menu) else { return fallback("adapter refused the menu") }
        let items = menu.items
        if let reason = Self.unsupportedItem(in: menu, entries: entries) { return fallback(reason) }

        let palette = adapter.palette(for: control)
        let screenHeight = control.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        let model = SADesignMenuCardViewModel(entries: entries, hasSearch: adapter.hasSearch, placeholder: adapter.searchPlaceholder,
                                              palette: palette, optionHeld: NSEvent.modifierFlags.contains(.option),
                                              screenVisibleHeight: screenHeight)
        guard !model.isEmpty else { return fallback("no rows") }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: SADesignMenuCardView(model: model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.appearance = Self.appearance(isDark: palette.isDark)

        let session = Session(popover: popover, model: model, adapter: adapter, menu: menu, items: items, control: control, onClose: onClose)
        model.choose = { [weak self, weak session] position in
            guard let self, let session, self.session === session else { return }
            self.choose(position)
        }
        self.session = session
        typeSelectBuffer = ""

        let anchor = anchorRect ?? control.bounds
        popover.show(relativeTo: anchor, of: control, preferredEdge: Self.edge(for: control, anchor: anchor))
        installMonitors()
        observe(control: control, popover: popover, menu: menu)
        watchStyleChanges()
        adapter.cardWillOpen(in: self)
        focusSearchField()
        return true
    }

    /// Closes the card (no item fires).
    func close() {
        guard let session else { return }
        // The search field made the popover's window key: give key back to the control's window, so a ⌘ shortcut
        // passed through and a fired nil-target action reach its responder chain.
        let popoverHadKey = session.popover.contentViewController?.view.window?.isKeyWindow == true
        finish(session)
        session.popover.close()
        if popoverHadKey { session.control?.window?.makeKey() }
    }

    // MARK: Firing

    /// Does what choosing `item` in its native menu does. A value-bound item has its new value written through the
    /// binding, its state set, and its action sent (performActionForItem would re-run the binding and write the old
    /// value back); any other item goes through `performActionForItem(at:)`, which also drives an NSPopUpButton's
    /// own selection and action.
    static func fire(_ item: NSMenuItem) {
        if let binding = item.infoForBinding(.value) {
            let newState: NSControl.StateValue = item.state == .on ? .off : .on
            writeBoundValue(binding, isOn: newState == .on)
            item.state = newState
            if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
            return
        }
        guard let menu = item.menu else { return }
        let index = menu.index(of: item)
        guard index >= 0 else { return }
        menu.performActionForItem(at: index)
    }

    private static func writeBoundValue(_ binding: [NSBindingInfoKey: Any], isOn: Bool) {
        guard let object = binding[.observedObject] as? NSObject, let keyPath = binding[.observedKeyPath] as? String else { return }
        var value: Any? = NSNumber(value: isOn)
        let options = binding[.options] as? [NSBindingOption: Any]
        if let transformer = options?[.valueTransformer] as? ValueTransformer {
            value = transformer.reverseTransformedValue(value)
        } else if let name = options?[.valueTransformerName] as? String, !name.isEmpty,
                  let transformer = ValueTransformer(forName: NSValueTransformerName(name)) {
            value = transformer.reverseTransformedValue(value)
        }
        object.setValue(value, forKeyPath: keyPath)
    }

    /// Closes first, then fires after this event, so a sheet or alert the action opens doesn't attach to a closing
    /// popover. Only a choosable row fires, and only the item that row was built from (`Session.items`), while it is
    /// still in a menu and enabled: a menu rebuilt under the open card (the database list after a refresh,
    /// back/forward after a navigation) fires nothing rather than whichever item now has the row's old index.
    private func choose(_ position: Int) {
        guard let session, let row = session.model.row(at: position), row.isChoosable, let entry = row.entry,
              entry.index >= 0, entry.index < session.items.count else { return }
        let item = session.items[entry.index]
        // The modifiers held when choosing (Return's keyDown, or the click's mouse-up): an action may read
        // `[NSApp currentEvent] modifierFlags`, as from its native menu.
        let flags = (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).intersection(.deviceIndependentFlagsMask)
        close()
        guard SADesignMenuCardModel.isStillFireable(item) else { return }
        scheduleFire(item, modifierFlags: flags)
    }

    /// Items waiting for their application-defined event, keyed by the event's `data1`.
    private var pendingFires: [Int: NSMenuItem] = [:]
    private var nextFireToken = 0
    private var fireMonitor: Any?
    private static let fireEventSubtype: Int16 = 0x5AC3

    /// Fires `item` from an application-defined event that carries `modifierFlags`, posted at the front of the queue:
    /// while the action runs, `NSApp.currentEvent` is that event (a plain main-queue hop would leave it nil).
    private func scheduleFire(_ item: NSMenuItem, modifierFlags: NSEvent.ModifierFlags) {
        if fireMonitor == nil {
            fireMonitor = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { [weak self] event in
                guard event.subtype.rawValue == Self.fireEventSubtype, let self,
                      let item = self.pendingFires.removeValue(forKey: event.data1) else { return event }
                Self.fire(item)
                return nil
            }
        }
        nextFireToken += 1
        let token = nextFireToken
        guard fireMonitor != nil,
              let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: modifierFlags,
                                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                                             subtype: Self.fireEventSubtype, data1: token, data2: 0) else {
            DispatchQueue.main.async { Self.fire(item) }
            return
        }
        pendingFires[token] = item
        NSApp.postEvent(event, atStart: true)
    }

    // MARK: Clicks on the card's own control

    /// Call at the top of a control's mouseDown, before its main action (a split button's main half, a back/forward
    /// segment's navigation). True when this click belongs to the card: the card is open for `control` (it is closed
    /// now), or this mouse-down is the one that just closed it as a transient popover. The control then returns without
    /// acting, as a native menu swallows the click that dismisses it.
    func consumesClick(on control: NSView) -> Bool {
        if let session, session.control === control {
            close()
            return true
        }
        return isClosingClick(on: control)
    }

    // MARK: Closing

    private func finish(_ session: Session) {
        guard self.session === session else { return }
        self.session = nil
        removeMonitors()
        session.onClose?()
    }

    func popoverWillClose(_ notification: Notification) {
        guard let session, notification.object as? NSPopover === session.popover else { return }
        // A transient close from a click outside: remember the click, it may be the one on the control.
        if let event = NSApp.currentEvent, event.type == .leftMouseDown {
            lastClosedControl = session.control
            lastClosingMouseDown = event.timestamp
        }
        finish(session)
    }

    private func isClosingClick(on control: NSView) -> Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown, let closing = lastClosingMouseDown,
              lastClosedControl === control else { return false }
        return event.timestamp == closing
    }

    // MARK: Placement

    private static func appearance(isDark: Bool) -> NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    /// Below the anchor, above it when the window has less than 200pt below.
    private static func edge(for control: NSView, anchor: NSRect) -> NSRectEdge {
        let below: NSRectEdge = control.isFlipped ? .maxY : .minY
        let above: NSRectEdge = control.isFlipped ? .minY : .maxY
        let roomBelow = control.convert(anchor, to: nil).minY
        return roomBelow < minRoomBelow ? above : below
    }

    // MARK: Fallback

    private func fallback(_ reason: String) -> Bool {
        #if DEBUG
        NSLog("SADesignMenuCard: fallback %@", reason)
        #endif
        return false
    }

    /// An entry the card can't draw: an item with a custom view or a submenu.
    private static func unsupportedItem(in menu: NSMenu, entries: [SADesignMenuEntry]) -> String? {
        for entry in entries where entry.index >= 0 && entry.index < menu.numberOfItems {
            let item = menu.items[entry.index]
            if item.view != nil { return "item \(entry.index) has a custom view" }
            if item.hasSubmenu { return "item \(entry.index) has a submenu" }
        }
        return nil
    }

    // MARK: Keyboard

    private func installMonitors() {
        removeMonitors()
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            // Not `self?.handleKeyDown(event) ?? event`: that would pass on the events the card swallows.
            guard let self else { return event }
            return self.handleKeyDown(event)
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.session?.model.setOptionHeld(event.modifierFlags.contains(.option))
            return event
        }) { monitors.append(monitor) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let session else { return event }
        let model = session.model
        switch event.keyCode {
        case 53: // Escape: swallowed, or a menu item with Esc as its key equivalent would fire in the window too
            switch SADesignMenuCardModel.escapeAction(hasSearch: model.hasSearch, query: model.query) {
            case .clearSearch:
                model.searchField?.stringValue = ""
                model.setQuery("")
            case .close:
                close()
            }
            return nil
        case 125: // ↓
            model.moveHighlight(by: 1)
            return nil
        case 126: // ↑
            model.moveHighlight(by: -1)
            return nil
        case 36, 76: // Return, Enter
            if let position = model.highlight { choose(position) }
            return nil
        default:
            break
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            // Text editing in the search field keeps its ⌘ keys; any other ⌘ shortcut acts on the window.
            if model.hasSearch, let field = model.searchField, event.window === field.window, isEditing(field),
               Self.isTextEditingShortcut(event) {
                return event
            }
            close()
            return event
        }
        if model.hasSearch {
            guard let field = model.searchField, let window = field.window else { return event }
            if event.window === window, isEditing(field) { return event }
            // Focus went elsewhere (or the key came through the control's window): put it in the field.
            if !isEditing(field) {
                window.makeKey()
                window.makeFirstResponder(field)
            }
            window.sendEvent(event)
            return nil
        }
        typeSelect(event)
        return nil
    }

    private func isEditing(_ field: NSSearchField) -> Bool {
        guard let window = field.window, let editor = field.currentEditor() else { return false }
        return window.firstResponder === editor
    }

    private static func isTextEditingShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.shift, .capsLock, .numericPad, .function])
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return ["a", "c", "v", "x", "z"].contains(key)
    }

    /// A non-search card jumps to the next row whose title starts with what was typed, as a native menu does.
    private func typeSelect(_ event: NSEvent) {
        guard let model = session?.model, let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
        let now = event.timestamp
        let continuing = now - typeSelectTime < 1
        typeSelectTime = now
        typeSelectBuffer = continuing ? typeSelectBuffer + characters : characters
        model.jump(toPrefix: typeSelectBuffer, startingAfterHighlight: !continuing || typeSelectBuffer.count == 1)
    }

    private func focusSearchField() {
        guard let field = session?.model.searchField else { return }
        let focus = { [weak self] in
            guard let self, let window = field.window else { return }
            if !window.isKeyWindow { window.makeKey() }
            if !self.isEditing(field) { window.makeFirstResponder(field) }
            (field.currentEditor() as? NSTextView)?.insertionPointColor = field.textColor ?? .textColor
        }
        focus()
        // The popover window may only accept key after this turn's layout.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.session?.model.searchField === field else { return }
            focus()
        }
    }

    // MARK: Window and style observation

    private func observe(control: NSView, popover: NSPopover, menu: NSMenu) {
        let center = NotificationCenter.default
        let controlWindow = control.window
        // The menu gained or lost items under the card (rebuilt by its owner): the rows are stale, close. Synchronous
        // (no queue), so a pick can't land between the rebuild and the close.
        for name in [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification] {
            observers.append(center.addObserver(forName: name, object: menu, queue: nil) { [weak self, weak popover] _ in
                guard let self, let popover, self.session?.popover === popover else { return }
                self.close()
            })
        }
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: controlWindow, queue: .main) { [weak self] _ in
            self?.close()
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.close()
        })
        // The control's window gives key to the popover's when the search field takes focus; close only when key
        // goes to some other window (another tab, a sheet, the Settings window).
        let check: (Notification) -> Void = { [weak self, weak controlWindow, weak popover] _ in
            DispatchQueue.main.async {
                guard let self, let popover, self.session?.popover === popover else { return }
                let popoverWindow = popover.contentViewController?.view.window
                guard let key = NSApp.keyWindow else { return }
                if key !== popoverWindow && key !== controlWindow { self.close() }
            }
        }
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main, using: check))
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main, using: check))
    }

    /// Accent and app appearance changes rebuild the open card's palette (every palette follows both).
    private func watchStyleChanges() {
        guard !watchingStyle else { return }
        watchingStyle = true
        SADesignAccent.observe(self) { $0.refreshPalette() }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            // Let the new appearance reach the control before resolving colors in it.
            DispatchQueue.main.async { self?.refreshPalette() }
        }
    }

    /// Starts following one more style source for the open card's palette: `start` runs once per `id` for the
    /// presenter's lifetime and should call `refreshPalette()` whenever the source changes.
    func followStyleSource(_ id: String, start: (SADesignMenuCardPresenter) -> Void) {
        guard styleSources.insert(id).inserted else { return }
        start(self)
    }

    /// Rebuilds the open card's palette from its adapter.
    func refreshPalette() {
        guard let session, let control = session.control else { return }
        let palette = session.adapter.palette(for: control)
        session.model.apply(palette)
        session.popover.appearance = Self.appearance(isDark: palette.isDark)
    }
}

// MARK: - View model

/// The open card's rows, highlight, query and colors.
final class SADesignMenuCardViewModel: ObservableObject {

    struct Colors: Equatable {
        var surface, text, muted, hairline, hover, selected, tick: Color

        init(_ palette: SADesignMenuCardPalette) {
            surface = Color(nsColor: palette.surface)
            text = Color(nsColor: palette.text)
            muted = Color(nsColor: palette.muted)
            hairline = Color(nsColor: palette.hairline)
            hover = Color(nsColor: palette.hover)
            selected = Color(nsColor: palette.selected)
            tick = Color(nsColor: palette.tick)
        }
    }

    /// One drawn row; `position` indexes `list + footer`, the keyboard's sequence.
    struct Line: Identifiable {
        let id: Int
        let position: Int
        let row: SADesignMenuRow
        let height: CGFloat
    }

    @Published private(set) var list: [Line] = []
    @Published private(set) var footer: [Line] = []
    @Published private(set) var highlight: Int?
    @Published private(set) var highlightByMouse = false
    @Published private(set) var colors: Colors
    /// The AppKit colors behind `colors`, for the search field.
    private(set) var palette: SADesignMenuCardPalette
    /// Bumped when the keyboard moves the highlight, so the list scrolls to it (a hover doesn't scroll).
    @Published private(set) var scrollRequest = 0
    private(set) var scrollTarget: Int?

    let hasSearch: Bool
    let placeholder: String
    let size: NSSize
    let listHeight: CGFloat
    weak var searchField: NSSearchField?
    var choose: (Int) -> Void = { _ in }

    private let entries: [SADesignMenuEntry]
    /// Entry index → the index of its primary (itself unless it is an alternate), so ⌥ keeps the highlight on the pair.
    private let pairKeys: [Int: Int]
    private let metrics: SADesignMenuCardMetrics
    private var baseList: [SADesignMenuRow] = []
    private var baseFooter: [SADesignMenuRow] = []
    private var rows: [SADesignMenuRow] = []
    private(set) var optionHeld: Bool
    private(set) var query = ""

    var isEmpty: Bool { baseList.isEmpty && baseFooter.isEmpty }

    init(entries: [SADesignMenuEntry], hasSearch: Bool, placeholder: String, palette: SADesignMenuCardPalette,
         optionHeld: Bool, screenVisibleHeight: CGFloat) {
        self.entries = entries
        self.hasSearch = hasSearch
        self.placeholder = placeholder
        self.optionHeld = optionHeld
        self.palette = palette
        colors = Colors(palette)

        var keys: [Int: Int] = [:]
        var previous: SADesignMenuEntry?
        for entry in entries {
            if entry.isAlternate, entry.kind == .item, let previous, previous.kind == .item {
                keys[entry.index] = keys[previous.index] ?? previous.index
            } else {
                keys[entry.index] = entry.index
            }
            previous = entry
        }
        pairKeys = keys

        let resolved = SADesignMenuCardModel.rows(entries, optionHeld: optionHeld)
        metrics = SADesignMenuCardMetrics(entries: entries, list: resolved.list, footer: resolved.footer, hasSearch: hasSearch,
                                          screenVisibleHeight: screenVisibleHeight)
        size = metrics.size
        listHeight = metrics.listHeight
        baseList = resolved.list
        baseFooter = resolved.footer
        publishRows()
        // Open on the current (ticked) row, else the first choosable one; the list scrolls to it when it appears.
        highlight = SADesignMenuCardModel.openingHighlight(in: rows, listCount: list.count)
        requestScroll()
    }

    func row(at position: Int) -> SADesignMenuRow? {
        rows.indices.contains(position) ? rows[position] : nil
    }

    func apply(_ palette: SADesignMenuCardPalette) {
        self.palette = palette
        colors = Colors(palette)
    }

    // MARK: Rows

    private func publishRows() {
        // An empty list stays empty while searching: there is nothing to match and no room to say so.
        let filtered = baseList.isEmpty ? [] : SADesignMenuCardModel.filter(baseList, query: query)
        rows = filtered + baseFooter
        list = filtered.enumerated().map { makeLine($0.element, position: $0.offset) }
        footer = baseFooter.enumerated().map { makeLine($0.element, position: filtered.count + $0.offset) }
    }

    private func makeLine(_ row: SADesignMenuRow, position: Int) -> Line {
        Line(id: row.entry?.index ?? -1 - position, position: position, row: row, height: metrics.height(of: row))
    }

    func setQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        publishRows()
        // A filter change never leaves the highlight on a row the filter hid, nor on a footer action; an exact match
        // takes it first.
        highlight = SADesignMenuCardModel.searchHighlight(in: rows, listCount: list.count, query: query)
        highlightByMouse = false
        requestScroll()
    }

    /// ⌥ swaps alternates in place; the highlight stays on the same primary/alternate pair.
    func setOptionHeld(_ held: Bool) {
        guard held != optionHeld else { return }
        optionHeld = held
        let oldKey = highlight.flatMap { row(at: $0)?.entry }.flatMap { pairKeys[$0.index] }
        let resolved = SADesignMenuCardModel.rows(entries, optionHeld: held)
        baseList = resolved.list
        baseFooter = resolved.footer
        publishRows()
        if let oldKey, let position = rows.indices.first(where: { rows[$0].isChoosable && rows[$0].entry.flatMap { pairKeys[$0.index] } == oldKey }) {
            highlight = position
        } else {
            highlight = SADesignMenuCardModel.firstChoosable(in: Array(rows.prefix(list.count)))
        }
    }

    // MARK: Highlight

    func moveHighlight(by step: Int) {
        let start = highlight.flatMap { rows.indices.contains($0) ? $0 : nil }
        highlight = SADesignMenuCardModel.move(highlight: start, in: rows, by: step)
        highlightByMouse = false
        requestScroll()
    }

    func hover(_ position: Int) {
        guard row(at: position)?.isChoosable == true else { return }
        if highlight != position { highlight = position }
        if !highlightByMouse { highlightByMouse = true }
    }

    func jump(toPrefix prefix: String, startingAfterHighlight: Bool) {
        let count = rows.count
        guard count > 0 else { return }
        let start = startingAfterHighlight ? ((highlight ?? -1) + 1) : (highlight ?? 0)
        for offset in 0..<count {
            let position = (start + offset) % count
            let row = rows[position]
            guard row.isChoosable, let title = row.entry?.title else { continue }
            if title.range(of: prefix, options: SADesignMenuCardModel.searchOptions.union(.anchored)) != nil {
                highlight = position
                highlightByMouse = false
                requestScroll()
                return
            }
        }
    }

    private func requestScroll() {
        guard let highlight, highlight < list.count else { return }
        scrollTarget = list[highlight].id
        scrollRequest += 1
    }
}

// MARK: - Metrics

/// Row heights and the card's size, computed once when the card opens (so 500 rows open quickly and the card
/// doesn't jump while filtering).
struct SADesignMenuCardMetrics {
    // `cardPadding`, `rowPadding` and `searchGap` are off the `SASpacing` scale on purpose: they set the card's size
    // and row layout, which the nearest steps (4 or 8, 8 or 12) would change by 4pt on every card.
    static let cardPadding: CGFloat = 6
    static let rowPadding: CGFloat = 10
    static let rowHeight: CGFloat = 28
    static let headerHeight: CGFloat = 24
    static let separatorHeight: CGFloat = 9
    static let searchHeight: CGFloat = 28
    static let searchGap: CGFloat = 6
    static let symbolWidth: CGFloat = 15
    static let gap: CGFloat = SASpacing.xSmall
    // The small insets below are off the scale too, kept as drawn: each sits between two steps, and snapping it would
    // move the text it spaces.
    /// Above a section header's title, which sits at the top of its 24pt row.
    static let headerTopPadding: CGFloat = 6
    /// Between a row's title and its trailing chip, and between the search glyph and the field (tighter than `gap`).
    static let innerGap: CGFloat = 6
    /// Between a two-line row's title and its detail line, so the two read as one entry.
    static let detailGap: CGFloat = 2
    /// The trigger chip's padding around its 11pt text (`chrome(of:)` adds it, and 1pt per side for the outline).
    static let chipHorizontalPadding: CGFloat = 5
    static let chipVerticalPadding: CGFloat = 1

    static let titleFont = NSFont.systemFont(ofSize: 13)
    static let smallFont = NSFont.systemFont(ofSize: 11)
    static let headerFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    let size: NSSize
    let listHeight: CGFloat
    private var heights: [Int: CGFloat] = [:]

    init(entries: [SADesignMenuEntry], list: [SADesignMenuRow], footer: [SADesignMenuRow], hasSearch: Bool, screenVisibleHeight: CGFloat) {
        // Width over every entry, alternates included, so ⌥ never needs a wider card.
        var contentWidth: CGFloat = 0
        for entry in entries where !entry.isHidden && entry.kind != .separator {
            contentWidth = max(contentWidth, Self.width(of: entry))
        }
        let width = min(max(contentWidth, SADesignMenuCardModel.minCardWidth), SADesignMenuCardModel.maxCardWidth)

        var rowHeights: [Int: CGFloat] = [:]
        for entry in entries where entry.kind == .item {
            rowHeights[entry.index] = Self.itemHeight(entry, cardWidth: width)
        }
        heights = rowHeights
        let listContent = list.reduce(0) { $0 + Self.height(of: $1, heights: rowHeights) }
        let footerContent = footer.reduce(0) { $0 + Self.height(of: $1, heights: rowHeights) }
        var fixed = Self.cardPadding * 2
        if hasSearch { fixed += Self.searchHeight + Self.searchGap }
        if !footer.isEmpty && !list.isEmpty { fixed += Self.separatorHeight }
        fixed += footerContent
        let size = SADesignMenuCardModel.cardSize(contentWidth: width, contentHeight: fixed + listContent, screenVisibleHeight: screenVisibleHeight)
        self.size = NSSize(width: size.width, height: max(size.height, fixed))
        listHeight = list.isEmpty ? 0 : max(self.size.height - fixed, 0)
    }

    func height(of row: SADesignMenuRow) -> CGFloat { Self.height(of: row, heights: heights) }

    private static func height(of row: SADesignMenuRow, heights: [Int: CGFloat]) -> CGFloat {
        switch row.kind {
        case .item: return row.entry.flatMap { heights[$0.index] } ?? rowHeight
        case .header: return headerHeight
        case .separator: return separatorHeight
        case .noMatches: return rowHeight
        }
    }

    /// Detail-only: the text alone in mono.
    static func isDetailOnly(_ entry: SADesignMenuEntry) -> Bool {
        guard let detail = entry.detail else { return false }
        return entry.title.isEmpty || entry.title == detail
    }

    private static func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static let monoAdvance: CGFloat = textWidth("0", monoFont)

    /// Mono width of the longest line, by character count (a monospaced font).
    private static func monoWidth(_ text: String) -> CGFloat {
        let longest = text.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 0
        return CGFloat(longest) * monoAdvance
    }

    /// Everything beside the title: glyph, chip, shortcut, tick, the paddings, and the row HStack's spacing before
    /// its Spacer (SwiftUI spaces a Spacer like any other child).
    private static func chrome(of entry: SADesignMenuEntry) -> CGFloat {
        var width = (cardPadding + rowPadding) * 2 + gap
        if entry.symbol != nil { width += symbolWidth + gap }
        if let chip = entry.trailingChip, !chip.isEmpty { width += gap + textWidth(chip, smallFont) + 2 * chipHorizontalPadding + 2 }
        if !entry.shortcut.isEmpty { width += gap + textWidth(entry.shortcut, smallFont) }
        if entry.isTicked { width += gap + 12 }
        return width
    }

    private static func width(of entry: SADesignMenuEntry) -> CGFloat {
        switch entry.kind {
        case .header: return (cardPadding + rowPadding) * 2 + textWidth(entry.title, headerFont)
        case .separator: return 0
        case .item:
            if isDetailOnly(entry), let detail = entry.detail { return chrome(of: entry) + monoWidth(detail) }
            var text = textWidth(entry.title, titleFont)
            if let detail = entry.detail { text = max(text, monoWidth(detail)) }
            return chrome(of: entry) + text
        }
    }

    /// 28pt; detail-only rows 28 / 44 for one / two mono lines; two-line rows 46 / 60.
    private static func itemHeight(_ entry: SADesignMenuEntry, cardWidth: CGFloat) -> CGFloat {
        guard let detail = entry.detail else { return rowHeight }
        var available = cardWidth - (cardPadding + rowPadding) * 2 - gap
        if entry.symbol != nil { available -= symbolWidth + gap }
        if !entry.shortcut.isEmpty { available -= gap + textWidth(entry.shortcut, smallFont) }
        if entry.isTicked { available -= gap + 12 }
        let perLine = max(1, floor(available / monoAdvance))
        var lines = 0
        for line in detail.split(separator: "\n", omittingEmptySubsequences: false) {
            lines += max(1, Int(ceil(CGFloat(line.count) / perLine)))
            if lines >= 2 { break }
        }
        let twoLines = lines >= 2
        if isDetailOnly(entry) { return twoLines ? 44 : rowHeight }
        return twoLines ? 60 : 46
    }
}

// MARK: - View

struct SADesignMenuCardView: View {
    @ObservedObject var model: SADesignMenuCardViewModel

    var body: some View {
        let colors = model.colors
        VStack(alignment: .leading, spacing: 0) {
            if model.hasSearch {
                SADesignMenuCardSearchField(model: model)
                    .frame(height: SADesignMenuCardMetrics.searchHeight)
                    .padding(.horizontal, SADesignMenuCardMetrics.cardPadding)
                    .padding(.bottom, SADesignMenuCardMetrics.searchGap)
            }
            if model.listHeight > 0 {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.list) { line in
                                rowView(line).id(line.id)
                            }
                        }
                    }
                    .frame(height: model.listHeight)
                    .onAppear {
                        // The opening highlight (the current row) was chosen before the list existed: bring it into
                        // view once the rows are laid out, however far down a long list it is.
                        guard let target = model.scrollTarget else { return }
                        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
                    }
                    .onChange(of: model.scrollRequest) { _ in
                        if let target = model.scrollTarget { proxy.scrollTo(target) }
                    }
                }
            }
            if !model.footer.isEmpty {
                if model.listHeight > 0 { hairline(colors) }
                ForEach(model.footer) { line in rowView(line) }
            }
        }
        .padding(.vertical, SADesignMenuCardMetrics.cardPadding)
        .frame(width: model.size.width, height: model.size.height, alignment: .top)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colors.hairline, lineWidth: 1))
    }

    private func hairline(_ colors: SADesignMenuCardViewModel.Colors) -> some View {
        colors.hairline
            .frame(height: 1)
            .padding(.horizontal, SADesignMenuCardMetrics.cardPadding)
            .padding(.vertical, (SADesignMenuCardMetrics.separatorHeight - 1) / 2)
    }

    @ViewBuilder private func rowView(_ line: SADesignMenuCardViewModel.Line) -> some View {
        let colors = model.colors
        switch line.row.kind {
        case .header:
            Text(line.row.entry?.title ?? "")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colors.muted)
                .lineLimit(1)
                .padding(.top, SADesignMenuCardMetrics.headerTopPadding)
                .padding(.horizontal, SADesignMenuCardMetrics.cardPadding + SADesignMenuCardMetrics.rowPadding)
                .frame(maxWidth: .infinity, minHeight: line.height, maxHeight: line.height, alignment: .topLeading)
                .accessibilityAddTraits(.isHeader)
        case .separator:
            hairline(colors)
        case .noMatches:
            Text(NSLocalizedString("No matches", comment: "Menu card: the one line shown when the search matches no row"))
                .font(.system(size: 12))
                .foregroundColor(colors.muted)
                .padding(.horizontal, SADesignMenuCardMetrics.cardPadding + SADesignMenuCardMetrics.rowPadding)
                .frame(maxWidth: .infinity, minHeight: line.height, maxHeight: line.height, alignment: .leading)
        case .item:
            if let entry = line.row.entry {
                SADesignMenuCardItemRow(entry: entry, position: line.position, height: line.height, isChoosable: line.row.isChoosable,
                                        fill: fill(for: line.position), colors: colors,
                                        choose: { model.choose(line.position) },
                                        hover: { model.hover(line.position) })
                    .equatable()
            }
        }
    }

    private func fill(for position: Int) -> Color {
        guard model.highlight == position else { return .clear }
        return model.highlightByMouse ? model.colors.hover : model.colors.selected
    }
}

/// One choosable (or disabled) row. Equatable over its drawn inputs (the closures only capture the model and
/// `position`), so a highlight move re-evaluates the two rows it touches, not every visible row.
private struct SADesignMenuCardItemRow: View, Equatable {
    let entry: SADesignMenuEntry
    let position: Int
    let height: CGFloat
    let isChoosable: Bool
    let fill: Color
    let colors: SADesignMenuCardViewModel.Colors
    let choose: () -> Void
    let hover: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entry == rhs.entry && lhs.position == rhs.position && lhs.height == rhs.height && lhs.isChoosable == rhs.isChoosable
            && lhs.fill == rhs.fill && lhs.colors == rhs.colors
    }

    var body: some View {
        Button(action: choose) {
            HStack(spacing: SADesignMenuCardMetrics.gap) {
                if let symbol = entry.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15))
                        .foregroundColor(colors.muted)
                        .frame(width: SADesignMenuCardMetrics.symbolWidth)
                }
                label
                Spacer(minLength: 0)
                if !entry.shortcut.isEmpty {
                    Text(entry.shortcut).font(.system(size: 11)).foregroundColor(colors.muted).lineLimit(1).fixedSize()
                }
                if entry.isTicked {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundColor(colors.tick)
                        .frame(width: 12)
                }
            }
            .padding(.horizontal, SADesignMenuCardMetrics.rowPadding)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isChoosable)
        .padding(.horizontal, SADesignMenuCardMetrics.cardPadding)
        .onHover { if $0 { hover() } }
        .help(entry.toolTip ?? "")
        .accessibilityLabel(SADesignMenuCardMetrics.isDetailOnly(entry) ? (entry.detail ?? entry.title) : entry.title)
        // The ticked row (the current database, say) is announced as selected, as its native menu item is.
        .accessibilityAddTraits(entry.isTicked ? .isSelected : [])
    }

    private var textColor: Color { isChoosable ? colors.text : colors.muted }

    @ViewBuilder private var label: some View {
        if SADesignMenuCardMetrics.isDetailOnly(entry), let detail = entry.detail {
            Text(detail)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(textColor)
                .lineLimit(2)
                .truncationMode(.tail)
        } else if let detail = entry.detail {
            VStack(alignment: .leading, spacing: SADesignMenuCardMetrics.detailGap) {
                HStack(spacing: SADesignMenuCardMetrics.innerGap) {
                    title
                    chip
                }
                Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(colors.muted)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        } else {
            HStack(spacing: SADesignMenuCardMetrics.innerGap) {
                title
                chip
            }
        }
    }

    private var title: some View {
        // Middle truncation keeps both ends of a long name (a database, a table), as native menus do.
        Text(entry.title).font(.system(size: 13)).foregroundColor(textColor).lineLimit(1).truncationMode(.middle)
    }

    @ViewBuilder private var chip: some View {
        if let chip = entry.trailingChip, !chip.isEmpty {
            Text(chip)
                .font(.system(size: 11))
                .foregroundColor(colors.muted)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, SADesignMenuCardMetrics.chipHorizontalPadding)
                .padding(.vertical, SADesignMenuCardMetrics.chipVerticalPadding)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(colors.hairline, lineWidth: 1))
        }
    }
}

/// The search field: an AppKit `NSSearchField` (a reliable first responder in a popover, with its clear button and the
/// search field role for VoiceOver). The presenter's key monitor keeps the card's keys: arrows and Return move and
/// choose, Escape clears the search and then closes the card.
private struct SADesignMenuCardSearchField: NSViewRepresentable {
    @ObservedObject var model: SADesignMenuCardViewModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.controlSize = .large
        field.font = .systemFont(ofSize: 13)
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        // The clear button clears the field and sends the action, without a text-change notification.
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.placeholderString = model.placeholder
        field.setAccessibilityLabel(model.placeholder)
        model.searchField = field
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        let text = model.palette.text
        field.textColor = text
        (field.currentEditor() as? NSTextView)?.insertionPointColor = text
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let model: SADesignMenuCardViewModel

        init(model: SADesignMenuCardViewModel) { self.model = model }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            model.setQuery(field.stringValue)
        }

        @objc func searchChanged(_ sender: NSSearchField) {
            model.setQuery(sender.stringValue)
        }
    }
}
