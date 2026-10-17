//
//  SAClaudeMenuCard.swift
//  Sequel Ace
//
//  The Claude card a main-window dropdown opens instead of its native menu: rows built from the
//  control's NSMenu by `SAClaudeMenuCardModel` (which stays the source of truth and stays attached,
//  so shortcuts keep working), an optional search field, keyboard highlight, ⌥ alternates, and a
//  pick that does what picking the native item does. One shared presenter (a transient NSPopover
//  with SwiftUI content, as the ⋯ editor-options card) serves every control; per-control adapters
//  supply the entries and the palette. App target only.
//

import AppKit
import SwiftUI

// MARK: - Palette

/// The card's colours: the editor theme's (editor-bar controls, like the ⋯ card) or Sequel Ace's
/// appearance (toolbar controls, like the toolbar pills).
struct SAClaudeMenuCardPalette {
    var surface, text, muted, hairline, hover, selected, tick: NSColor
    var isDark: Bool

    /// The editor theme's popup surface, as the ⋯ card builds its colours.
    static func editor() -> Self {
        let theme = SAClaudeThemeColours.from(defaults: .standard)
        let surface = SAClaudeStatusChrome.popupSurface(theme: theme)
        return Self(surface: surface,
                    text: theme.text,
                    muted: SAClaudeStatusChrome.muted(theme: theme),
                    hairline: SAClaudeStatusChrome.hairline(theme: theme),
                    hover: SAClaudeEditorChrome.derivedColour(text: theme.text, background: surface, ratio: 0.08),
                    selected: SAClaudeEditorChrome.derivedColour(text: theme.text, background: surface, ratio: 0.14),
                    tick: SAClaudeAccent.accent,
                    isDark: SAClaudeGridChrome.isDark(theme.background))
    }

    /// Sequel Ace's Claude colours resolved in `view`'s appearance.
    static func app(for view: NSView) -> Self {
        let appearance = view.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        func resolved(_ colour: NSColor) -> NSColor {
            var result = colour
            appearance.performAsCurrentDrawingAppearance {
                result = NSColor(cgColor: colour.cgColor) ?? colour
            }
            return result
        }
        return Self(surface: resolved(SAClaudeStyle.tabSelectedFill),
                    text: resolved(SAClaudeStyle.textPrimary),
                    muted: resolved(SAClaudeStyle.textMuted),
                    hairline: resolved(SAClaudeStyle.tabBorder),
                    hover: resolved(SAClaudeStyle.hoverFill),
                    selected: resolved(SAClaudeStyle.selection),
                    tick: SAClaudeAccent.accent,
                    isDark: isDark)
    }
}

// MARK: - Adapter

/// What a control tells the card: its entries (headers, footer, details, glyphs) and its palette.
///
/// Row rendering from an entry: `detail` set → two lines (title, then the detail in mono, at most two
/// lines). `detail` set and `title` empty or equal to `detail` → a detail-only row: the text in mono,
/// at most two lines (Query History).
protocol SAClaudeMenuCardAdapter: AnyObject {
    var hasSearch: Bool { get }
    var searchPlaceholder: String { get }
    /// The menu's entries (`SAClaudeMenuCardModel.entries(from:skipping:)` plus the adapter's marks);
    /// nil refuses the card and the caller opens the native menu.
    func entries(for menu: NSMenu) -> [SAClaudeMenuEntry]?
    func palette(for control: NSView) -> SAClaudeMenuCardPalette
}

// MARK: - Presenter

/// Shows one card at a time, anchored to its control.
final class SAClaudeMenuCardPresenter: NSObject, NSPopoverDelegate {

    static let shared = SAClaudeMenuCardPresenter()

    /// Everything that lives while one card is up.
    private final class Session {
        let popover: NSPopover
        let model: SAClaudeMenuCardViewModel
        let adapter: SAClaudeMenuCardAdapter
        let menu: NSMenu
        weak var control: NSView?
        let onClose: (() -> Void)?

        init(popover: NSPopover, model: SAClaudeMenuCardViewModel, adapter: SAClaudeMenuCardAdapter, menu: NSMenu,
             control: NSView, onClose: (() -> Void)?) {
            self.popover = popover
            self.model = model
            self.adapter = adapter
            self.menu = menu
            self.control = control
            self.onClose = onClose
        }
    }

    private var session: Session?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var watchingStyle = false
    private var appearanceObservation: NSKeyValueObservation?
    /// The mouse-down that closed a transient card: the same click reaching its control must not reopen it.
    private weak var lastClosedControl: NSView?
    private var lastClosingMouseDown: TimeInterval?
    /// Type-to-jump on cards without search.
    private var typeSelectBuffer = ""
    private var typeSelectTime: TimeInterval = 0

    private static let minRoomBelow: CGFloat = 200

    var isShown: Bool { session != nil }
    var shownControl: NSView? { session?.control }

    /// Opens the card for `menu` anchored to `control` (to `anchorRect`, in the control's coordinates, when given),
    /// or closes it when it is already open for `control`. Returns false when the card refuses the menu: the caller
    /// opens the native menu instead. `onClose` runs once when this card closes, whatever closes it.
    @discardableResult
    func show(menu: NSMenu, from control: NSView, adapter: SAClaudeMenuCardAdapter, preferredEdge: NSRectEdge? = nil,
              anchorRect: NSRect? = nil, onClose: (() -> Void)? = nil) -> Bool {
        if let session, session.control === control {
            close()
            return true
        }
        if isClosingClick(on: control) { return true }
        guard control.window != nil else { return fallback("control is not in a window") }
        if session != nil { close() }

        menu.update()
        guard let entries = adapter.entries(for: menu) else { return fallback("adapter refused the menu") }
        if let reason = Self.unsupportedItem(in: menu, entries: entries) { return fallback(reason) }

        let palette = adapter.palette(for: control)
        let screenHeight = control.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        let model = SAClaudeMenuCardViewModel(entries: entries, hasSearch: adapter.hasSearch, placeholder: adapter.searchPlaceholder,
                                              palette: palette, optionHeld: NSEvent.modifierFlags.contains(.option),
                                              screenVisibleHeight: screenHeight)
        guard !model.isEmpty else { return fallback("no rows") }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: SAClaudeMenuCardView(model: model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.appearance = Self.appearance(isDark: palette.isDark)

        let session = Session(popover: popover, model: model, adapter: adapter, menu: menu, control: control, onClose: onClose)
        model.choose = { [weak self, weak session] position in
            guard let self, let session, self.session === session else { return }
            self.choose(position)
        }
        self.session = session
        typeSelectBuffer = ""

        let anchor = anchorRect ?? control.bounds
        popover.show(relativeTo: anchor, of: control, preferredEdge: preferredEdge ?? Self.edge(for: control, anchor: anchor))
        installMonitors()
        observe(control: control, popover: popover)
        watchStyleChanges()
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
    /// popover. Only a choosable row fires.
    private func choose(_ position: Int) {
        guard let session, let row = session.model.row(at: position), row.isChoosable, let entry = row.entry,
              entry.index >= 0, entry.index < session.menu.numberOfItems else { return }
        let item = session.menu.items[entry.index]
        // The modifiers held when choosing (Return's keyDown, or the click's mouse-up): actions such as
        // chooseQueryHistory: read `[NSApp currentEvent] modifierFlags` to flip replace/insert.
        let flags = (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).intersection(.deviceIndependentFlagsMask)
        close()
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
        NSLog("SAClaudeMenuCard: fallback %@", reason)
        #endif
        return false
    }

    /// An entry the card can't draw: an item with a custom view or a submenu.
    private static func unsupportedItem(in menu: NSMenu, entries: [SAClaudeMenuEntry]) -> String? {
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
            close()
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

    private func isEditing(_ field: NSTextField) -> Bool {
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

    private func observe(control: NSView, popover: NSPopover) {
        let centre = NotificationCenter.default
        let controlWindow = control.window
        observers.append(centre.addObserver(forName: NSWindow.willCloseNotification, object: controlWindow, queue: .main) { [weak self] _ in
            self?.close()
        })
        observers.append(centre.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
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
        observers.append(centre.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main, using: check))
        observers.append(centre.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main, using: check))
    }

    /// Editor theme, accent and app appearance changes rebuild the open card's palette.
    private func watchStyleChanges() {
        guard !watchingStyle else { return }
        watchingStyle = true
        SAClaudeThemeWatcher.observe(self) { $0.refreshPalette() }
        SAClaudeAccent.observe(self) { $0.refreshPalette() }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            // Let the new appearance reach the control before resolving colours in it.
            DispatchQueue.main.async { self?.refreshPalette() }
        }
    }

    private func refreshPalette() {
        guard let session, let control = session.control else { return }
        let palette = session.adapter.palette(for: control)
        session.model.apply(palette)
        session.popover.appearance = Self.appearance(isDark: palette.isDark)
    }
}

// MARK: - View model

/// The open card's rows, highlight, query and colours.
final class SAClaudeMenuCardViewModel: ObservableObject {

    struct Colours: Equatable {
        var surface, text, muted, hairline, hover, selected, tick: Color

        init(_ palette: SAClaudeMenuCardPalette) {
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
        let row: SAClaudeMenuRow
        let height: CGFloat
    }

    @Published private(set) var list: [Line] = []
    @Published private(set) var footer: [Line] = []
    @Published private(set) var highlight: Int?
    @Published private(set) var highlightByMouse = false
    @Published private(set) var colours: Colours
    /// The AppKit colours behind `colours`, for the search field.
    private(set) var palette: SAClaudeMenuCardPalette
    /// Bumped when the keyboard moves the highlight, so the list scrolls to it (a hover doesn't scroll).
    @Published private(set) var scrollRequest = 0
    private(set) var scrollTarget: Int?

    let hasSearch: Bool
    let placeholder: String
    let size: NSSize
    let listHeight: CGFloat
    weak var searchField: NSTextField?
    var choose: (Int) -> Void = { _ in }

    private let entries: [SAClaudeMenuEntry]
    /// Entry index → the index of its primary (itself unless it is an alternate), so ⌥ keeps the highlight on the pair.
    private let pairKeys: [Int: Int]
    private let metrics: SAClaudeMenuCardMetrics
    private var baseList: [SAClaudeMenuRow] = []
    private var baseFooter: [SAClaudeMenuRow] = []
    private var rows: [SAClaudeMenuRow] = []
    private(set) var optionHeld: Bool
    private(set) var query = ""

    var isEmpty: Bool { baseList.isEmpty && baseFooter.isEmpty }

    init(entries: [SAClaudeMenuEntry], hasSearch: Bool, placeholder: String, palette: SAClaudeMenuCardPalette,
         optionHeld: Bool, screenVisibleHeight: CGFloat) {
        self.entries = entries
        self.hasSearch = hasSearch
        self.placeholder = placeholder
        self.optionHeld = optionHeld
        self.palette = palette
        colours = Colours(palette)

        var keys: [Int: Int] = [:]
        var previous: SAClaudeMenuEntry?
        for entry in entries {
            if entry.isAlternate, entry.kind == .item, let previous, previous.kind == .item {
                keys[entry.index] = keys[previous.index] ?? previous.index
            } else {
                keys[entry.index] = entry.index
            }
            previous = entry
        }
        pairKeys = keys

        let resolved = SAClaudeMenuCardModel.rows(entries, optionHeld: optionHeld)
        metrics = SAClaudeMenuCardMetrics(entries: entries, list: resolved.list, footer: resolved.footer, hasSearch: hasSearch,
                                          screenVisibleHeight: screenVisibleHeight)
        size = metrics.size
        listHeight = metrics.listHeight
        baseList = resolved.list
        baseFooter = resolved.footer
        publishRows()
        // Open on the current (ticked) row, else the first choosable one.
        highlight = rows.indices.first { rows[$0].isChoosable && rows[$0].entry?.isTicked == true && $0 < list.count }
            ?? SAClaudeMenuCardModel.firstChoosable(in: Array(rows.prefix(list.count)))
        requestScroll()
    }

    func row(at position: Int) -> SAClaudeMenuRow? {
        rows.indices.contains(position) ? rows[position] : nil
    }

    func apply(_ palette: SAClaudeMenuCardPalette) {
        self.palette = palette
        colours = Colours(palette)
    }

    // MARK: Rows

    private func publishRows() {
        // An empty list stays empty while searching: there is nothing to match and no room to say so.
        let filtered = baseList.isEmpty ? [] : SAClaudeMenuCardModel.filter(baseList, query: query)
        rows = filtered + baseFooter
        list = filtered.enumerated().map { makeLine($0.element, position: $0.offset) }
        footer = baseFooter.enumerated().map { makeLine($0.element, position: filtered.count + $0.offset) }
    }

    private func makeLine(_ row: SAClaudeMenuRow, position: Int) -> Line {
        Line(id: row.entry?.index ?? -1 - position, position: position, row: row, height: metrics.height(of: row))
    }

    func setQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        publishRows()
        // A filter change never leaves the highlight on a row the filter hid, nor on a footer action.
        highlight = SAClaudeMenuCardModel.firstChoosable(in: Array(rows.prefix(list.count)))
        highlightByMouse = false
        requestScroll()
    }

    /// ⌥ swaps alternates in place; the highlight stays on the same primary/alternate pair.
    func setOptionHeld(_ held: Bool) {
        guard held != optionHeld else { return }
        optionHeld = held
        let oldKey = highlight.flatMap { row(at: $0)?.entry }.flatMap { pairKeys[$0.index] }
        let resolved = SAClaudeMenuCardModel.rows(entries, optionHeld: held)
        baseList = resolved.list
        baseFooter = resolved.footer
        publishRows()
        if let oldKey, let position = rows.indices.first(where: { rows[$0].isChoosable && rows[$0].entry.flatMap { pairKeys[$0.index] } == oldKey }) {
            highlight = position
        } else {
            highlight = SAClaudeMenuCardModel.firstChoosable(in: Array(rows.prefix(list.count)))
        }
    }

    // MARK: Highlight

    func moveHighlight(by step: Int) {
        let start = highlight.flatMap { rows.indices.contains($0) ? $0 : nil }
        highlight = SAClaudeMenuCardModel.move(highlight: start, in: rows, by: step)
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
            if title.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
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
struct SAClaudeMenuCardMetrics {
    static let cardPadding: CGFloat = 6
    static let rowPadding: CGFloat = 10
    static let rowHeight: CGFloat = 28
    static let headerHeight: CGFloat = 24
    static let separatorHeight: CGFloat = 9
    static let searchHeight: CGFloat = 28
    static let searchGap: CGFloat = 6
    static let symbolWidth: CGFloat = 15
    static let gap: CGFloat = 8

    static let titleFont = NSFont.systemFont(ofSize: 13)
    static let smallFont = NSFont.systemFont(ofSize: 11)
    static let headerFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    let size: NSSize
    let listHeight: CGFloat
    private var heights: [Int: CGFloat] = [:]

    init(entries: [SAClaudeMenuEntry], list: [SAClaudeMenuRow], footer: [SAClaudeMenuRow], hasSearch: Bool, screenVisibleHeight: CGFloat) {
        // Width over every entry, alternates included, so ⌥ never needs a wider card.
        var contentWidth: CGFloat = 0
        for entry in entries where !entry.isHidden && entry.kind != .separator {
            contentWidth = max(contentWidth, Self.width(of: entry))
        }
        let width = min(max(contentWidth, SAClaudeMenuCardModel.minCardWidth), SAClaudeMenuCardModel.maxCardWidth)

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
        let size = SAClaudeMenuCardModel.cardSize(contentWidth: width, contentHeight: fixed + listContent, screenVisibleHeight: screenVisibleHeight)
        self.size = NSSize(width: size.width, height: max(size.height, fixed))
        listHeight = list.isEmpty ? 0 : max(self.size.height - fixed, 0)
    }

    func height(of row: SAClaudeMenuRow) -> CGFloat { Self.height(of: row, heights: heights) }

    private static func height(of row: SAClaudeMenuRow, heights: [Int: CGFloat]) -> CGFloat {
        switch row.kind {
        case .item: return row.entry.flatMap { heights[$0.index] } ?? rowHeight
        case .header: return headerHeight
        case .separator: return separatorHeight
        case .noMatches: return rowHeight
        }
    }

    /// Detail-only (History): the text alone in mono.
    static func isDetailOnly(_ entry: SAClaudeMenuEntry) -> Bool {
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

    /// Everything beside the title: glyph, chip, shortcut, tick and the paddings.
    private static func chrome(of entry: SAClaudeMenuEntry) -> CGFloat {
        var width = (cardPadding + rowPadding) * 2
        if entry.symbol != nil { width += symbolWidth + gap }
        if let chip = entry.trailingChip, !chip.isEmpty { width += gap + textWidth(chip, smallFont) + 12 }
        if !entry.shortcut.isEmpty { width += gap + textWidth(entry.shortcut, smallFont) }
        if entry.isTicked { width += gap + 12 }
        return width
    }

    private static func width(of entry: SAClaudeMenuEntry) -> CGFloat {
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
    private static func itemHeight(_ entry: SAClaudeMenuEntry, cardWidth: CGFloat) -> CGFloat {
        guard let detail = entry.detail else { return rowHeight }
        var available = cardWidth - (cardPadding + rowPadding) * 2
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

struct SAClaudeMenuCardView: View {
    @ObservedObject var model: SAClaudeMenuCardViewModel

    var body: some View {
        let colours = model.colours
        VStack(alignment: .leading, spacing: 0) {
            if model.hasSearch {
                SAClaudeMenuCardSearchField(model: model)
                    .frame(height: SAClaudeMenuCardMetrics.searchHeight)
                    .padding(.horizontal, SAClaudeMenuCardMetrics.cardPadding)
                    .padding(.bottom, SAClaudeMenuCardMetrics.searchGap)
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
                    .onChange(of: model.scrollRequest) { _ in
                        if let target = model.scrollTarget { proxy.scrollTo(target) }
                    }
                }
            }
            if !model.footer.isEmpty {
                if model.listHeight > 0 { hairline(colours) }
                ForEach(model.footer) { line in rowView(line) }
            }
        }
        .padding(.vertical, SAClaudeMenuCardMetrics.cardPadding)
        .frame(width: model.size.width, height: model.size.height, alignment: .top)
        .background(colours.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(colours.hairline, lineWidth: 1))
    }

    private func hairline(_ colours: SAClaudeMenuCardViewModel.Colours) -> some View {
        colours.hairline
            .frame(height: 1)
            .padding(.horizontal, SAClaudeMenuCardMetrics.cardPadding)
            .padding(.vertical, (SAClaudeMenuCardMetrics.separatorHeight - 1) / 2)
    }

    @ViewBuilder private func rowView(_ line: SAClaudeMenuCardViewModel.Line) -> some View {
        let colours = model.colours
        switch line.row.kind {
        case .header:
            Text(line.row.entry?.title ?? "")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colours.muted)
                .lineLimit(1)
                .padding(.top, 6)
                .padding(.horizontal, SAClaudeMenuCardMetrics.cardPadding + SAClaudeMenuCardMetrics.rowPadding)
                .frame(maxWidth: .infinity, minHeight: line.height, maxHeight: line.height, alignment: .topLeading)
                .accessibilityAddTraits(.isHeader)
        case .separator:
            hairline(colours)
        case .noMatches:
            Text(NSLocalizedString("ClaudeMenuNoMatches", value: "No matches", comment: "Claude menu card: the one line shown when the search matches no row"))
                .font(.system(size: 12))
                .foregroundColor(colours.muted)
                .padding(.horizontal, SAClaudeMenuCardMetrics.cardPadding + SAClaudeMenuCardMetrics.rowPadding)
                .frame(maxWidth: .infinity, minHeight: line.height, maxHeight: line.height, alignment: .leading)
        case .item:
            if let entry = line.row.entry {
                SAClaudeMenuCardItemRow(entry: entry, position: line.position, height: line.height, isChoosable: line.row.isChoosable,
                                        fill: fill(for: line.position), colours: colours,
                                        choose: { model.choose(line.position) },
                                        hover: { model.hover(line.position) })
                    .equatable()
            }
        }
    }

    private func fill(for position: Int) -> Color {
        guard model.highlight == position else { return .clear }
        return model.highlightByMouse ? model.colours.hover : model.colours.selected
    }
}

/// One choosable (or disabled) row. Equatable over its drawn inputs (the closures only capture the model and
/// `position`), so a highlight move re-evaluates the two rows it touches, not every visible row.
private struct SAClaudeMenuCardItemRow: View, Equatable {
    let entry: SAClaudeMenuEntry
    let position: Int
    let height: CGFloat
    let isChoosable: Bool
    let fill: Color
    let colours: SAClaudeMenuCardViewModel.Colours
    let choose: () -> Void
    let hover: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entry == rhs.entry && lhs.position == rhs.position && lhs.height == rhs.height && lhs.isChoosable == rhs.isChoosable
            && lhs.fill == rhs.fill && lhs.colours == rhs.colours
    }

    var body: some View {
        Button(action: choose) {
            HStack(spacing: SAClaudeMenuCardMetrics.gap) {
                if let symbol = entry.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15))
                        .foregroundColor(colours.muted)
                        .frame(width: SAClaudeMenuCardMetrics.symbolWidth)
                }
                label
                Spacer(minLength: 0)
                if !entry.shortcut.isEmpty {
                    Text(entry.shortcut).font(.system(size: 11)).foregroundColor(colours.muted).lineLimit(1).fixedSize()
                }
                if entry.isTicked {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundColor(colours.tick)
                        .frame(width: 12)
                }
            }
            .padding(.horizontal, SAClaudeMenuCardMetrics.rowPadding)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isChoosable)
        .padding(.horizontal, SAClaudeMenuCardMetrics.cardPadding)
        .onHover { if $0 { hover() } }
        .help(entry.toolTip ?? "")
        .accessibilityLabel(SAClaudeMenuCardMetrics.isDetailOnly(entry) ? (entry.detail ?? entry.title) : entry.title)
    }

    private var textColour: Color { isChoosable ? colours.text : colours.muted }

    @ViewBuilder private var label: some View {
        if SAClaudeMenuCardMetrics.isDetailOnly(entry), let detail = entry.detail {
            Text(detail)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(textColour)
                .lineLimit(2)
                .truncationMode(.tail)
        } else if let detail = entry.detail {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    title
                    chip
                }
                Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(colours.muted)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        } else {
            HStack(spacing: 6) {
                title
                chip
            }
        }
    }

    private var title: some View {
        Text(entry.title).font(.system(size: 13)).foregroundColor(textColour).lineLimit(1).truncationMode(.tail)
    }

    @ViewBuilder private var chip: some View {
        if let chip = entry.trailingChip, !chip.isEmpty {
            Text(chip)
                .font(.system(size: 11))
                .foregroundColor(colours.muted)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(colours.hairline, lineWidth: 1))
        }
    }
}

/// The search field: an AppKit text field (reliable first responder in a popover), borderless inside a rounded hairline.
private struct SAClaudeMenuCardSearchField: View {
    @ObservedObject var model: SAClaudeMenuCardViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(model.colours.muted)
            SAClaudeMenuCardTextField(model: model)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(model.colours.hairline, lineWidth: 1))
    }
}

private struct SAClaudeMenuCardTextField: NSViewRepresentable {
    @ObservedObject var model: SAClaudeMenuCardViewModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        field.setAccessibilityLabel(model.placeholder)
        model.searchField = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let text = model.palette.text
        field.textColor = text
        (field.currentEditor() as? NSTextView)?.insertionPointColor = text
        field.placeholderAttributedString = NSAttributedString(string: model.placeholder, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: model.palette.muted,
        ])
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: SAClaudeMenuCardViewModel

        init(model: SAClaudeMenuCardViewModel) { self.model = model }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.setQuery(field.stringValue)
        }
    }
}
