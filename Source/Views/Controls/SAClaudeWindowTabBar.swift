//
//  SAClaudeWindowTabBar.swift
//  Sequel Ace
//
//  The Claude window tab bar: chips for the windows of a native tab group, shown under the toolbar in place of
//  macOS's tab strip. Native tabbing stays the model - every tab is still its own window in an `NSWindowTabGroup`,
//  and the bar only reads that group and drives it through its public API. This file holds the item, the
//  controller and the model; the views are in SAClaudeWindowTabBarViews.swift.
//  See docs/superpowers/specs/2026-10-15-claude-tab-bar-design.md.
//

import AppKit

/// One chip's worth of state: a window of the tab group.
struct SAClaudeWindowTabItem {
    weak var window: NSWindow?
    var title: String
    /// The full window title (the path), shown when hovering the chip.
    var tooltip: String
    /// The favourite's `-tab` colour, `nil` when the connection has none.
    var colour: NSColor?
    var isSSL: Bool
    var isSelected: Bool
}

// MARK: - Controller

/// Owns one window's bar: installs it as a bottom title bar accessory, keeps macOS's own strip hidden and rebuilds
/// the chips of the whole group when the group changes. One per `SPWindowController`.
@objc final class SAClaudeWindowTabBarController: NSObject {
    private weak var window: NSWindow?
    private let accessory = SAClaudeWindowTabBarAccessory()
    private let barView: SAClaudeWindowTabBarView
    private var model: SAClaudeWindowTabBarModel?
    private var windowObservers: [NSObjectProtocol] = []
    /// Whether the bar shows an older state of the group. Only the shown (selected) tab's bar is kept current;
    /// the others are brought up to date when their tab is selected, before it is displayed.
    private var isStale = true
    /// The strip offset the shown bar last scrolled to, for when this bar is next shown.
    private var sharedScrollOffset: CGFloat?

    /// AppKit also shows its strip on a lone window, with no group change, when "Show Tab Bar" was once chosen
    /// for this kind of window (it keeps that choice in the app's defaults); these hide it there too.
    private static let hidingNotifications: [Notification.Name] = [
        NSWindow.didBecomeKeyNotification,
        NSWindow.didBecomeMainNotification,
        NSWindow.didChangeOcclusionStateNotification,   // ordered on screen
    ]

    init(window: NSWindow) {
        self.window = window
        barView = SAClaudeWindowTabBarView(frame: NSRect(x: 0, y: 0, width: window.frame.width, height: SAClaudeWindowTabBarLayout.height))
        barView.hostWindow = window
        accessory.layoutAttribute = .bottom
        accessory.fullScreenMinHeight = SAClaudeWindowTabBarLayout.height
        accessory.view = barView
        super.init()
        // A lone window shows no bar; the group's first change below shows it when there are two or more tabs.
        setVisible(false)
        window.addTitlebarAccessoryViewController(accessory)
        Self.hideNativeTabBar(in: window)
        windowObservers = Self.hidingNotifications.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: nil) { [weak self, weak window] _ in
                if let window { Self.hideNativeTabBar(in: window) }
                self?.updateIfStale()
            }
        }
        barView.onScroll = { [weak self] offset in self?.shareScrollOffset(offset) }
        model = SAClaudeWindowTabBarModel(window: window) { [weak self] in self?.groupDidChange() }
    }

    deinit {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Rebuilds the chips of every bar in this window's group, at most once per main-queue turn.
    func refresh() {
        if Self.pendingRefreshes.isEmpty {
            DispatchQueue.main.async { Self.performPendingRefreshes() }
        }
        if !Self.pendingRefreshes.contains(where: { $0 === self }) {
            Self.pendingRefreshes.append(self)
        }
    }

    /// Hides macOS's tab strip in `window`: AppKit hosts it in a bottom title bar accessory controller of its own,
    /// and makes a fresh, visible one whenever the window joins a group, so this runs on every group change. Safe
    /// to repeat, and cheap. Only the controller is hidden - hiding the strip view alone would leave an empty band.
    static func hideNativeTabBar(in window: NSWindow) {
        for controller in window.titlebarAccessoryViewControllers
        where !(controller is SAClaudeWindowTabBarAccessory) && controller.layoutAttribute == .bottom && !controller.isHidden {
            controller.isHidden = true
        }
        #if DEBUG
        scheduleNativeStripReport(for: window)
        #endif
    }

    /// Reorders the tabs of `selected`'s group by `steps` (ids index into `windows`, the group's order the steps
    /// were planned on) through the group's own remove and insert, never moving `selected`, so the selection stays.
    /// Every remove and insert has AppKit add a fresh tab strip, which the group's KVO hides at once; the bars are
    /// rebuilt once at the end rather than for each intermediate order.
    static func reorder(_ windows: [NSWindow], steps: [SAClaudeWindowTabBarLayout.Step], keeping selected: NSWindow) {
        isReordering = true
        defer { isReordering = false }
        for step in steps where windows.indices.contains(step.id) {
            let moving = windows[step.id]
            // A tab closed since the drag started is not put back.
            guard moving !== selected, let group = selected.tabGroup, group.windows.contains(where: { $0 === moving }) else { continue }
            group.removeWindow(moving)
            group.insertWindow(moving, at: min(max(0, step.index), group.windows.count))
        }
        (selected.tabGroup?.windows ?? [selected]).forEach(hideNativeTabBar(in:))
        controller(for: selected)?.refresh()
    }

    /// Whether Merge All Windows has a window to bring into `window`'s group.
    @objc static func canMergeAllWindows(into window: NSWindow) -> Bool {
        !mergePlan(into: window).isEmpty
    }

    /// Merge All Windows, ours: AppKit refuses tabbing for windows with a transparent title bar (its merge is
    /// disabled, and a lone window gets no tab group), but still adds tabs when asked explicitly. Every other
    /// document window joins `window`'s group after its last tab, group by group in tab order; `window` stays
    /// selected. The bars follow from the group's KVO.
    @objc static func mergeAllWindows(into window: NSWindow) {
        for other in mergePlan(into: window) {
            (window.tabGroup?.windows.last ?? window).addTabbedWindow(other, ordered: .above)
        }
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
        (window.tabGroup?.windows ?? [window]).forEach(hideNativeTabBar(in:))
    }

    // MARK: Private

    /// The document windows to merge into `window`, in the order to append them. A tab that isn't selected is
    /// not visible, so a window counts as shown when it or its group's selected tab is.
    private static func mergePlan(into window: NSWindow) -> [NSWindow] {
        func isShown(_ w: NSWindow?) -> Bool { w.map { $0.isVisible || $0.isMiniaturized } ?? false }
        let documents = NSApp.windows.filter { w in
            w.windowController is SPWindowController && !w.isSheet && (isShown(w) || isShown(w.tabGroup?.selectedWindow))
        }
        return SAClaudeWindowTabBarLayout.mergePlan(target: window, windows: documents) { w in
            w.tabGroup.flatMap { $0.windows.isEmpty ? nil : $0.windows }
        }
    }

    /// While `reorder` runs, the group passes through orders (and, with two tabs, a single tab) that are not
    /// shown: bars are not shown, hidden or rebuilt for them.
    private static var isReordering = false

    /// Controllers whose group asked for a rebuild this main-queue turn.
    private static var pendingRefreshes: [SAClaudeWindowTabBarController] = []

    /// One rebuild per group: a rebuild covers every window of the group, so the other controllers of a group
    /// that was already rebuilt are skipped.
    private static func performPendingRefreshes() {
        let controllers = pendingRefreshes
        pendingRefreshes = []
        var covered = Set<ObjectIdentifier>()
        for controller in controllers where !covered.contains(ObjectIdentifier(controller)) {
            for window in controller.rebuild() {
                if let other = Self.controller(for: window) { covered.insert(ObjectIdentifier(other)) }
            }
        }
    }

    private static func controller(for window: NSWindow) -> SAClaudeWindowTabBarController? {
        (window.windowController as? SPWindowController)?.tabBar
    }

    /// The windows of this window's group in tab order, or just this window when it has no group (or an empty one,
    /// as before the window is first shown).
    private var groupWindows: [NSWindow] {
        guard let window else { return [] }
        let windows = window.tabGroup?.windows ?? []
        return windows.isEmpty ? [window] : windows
    }

    private var isVisible: Bool { !accessory.isHidden }

    /// Every tab has a bar of its own, but the group shows one strip: the shown bar's scroll offset is kept for
    /// the others, which take it when they are next shown, so switching tabs doesn't move the chips under the
    /// pointer.
    private func shareScrollOffset(_ offset: CGFloat) {
        guard let window, window.tabGroup?.selectedWindow === window else { return }
        for other in groupWindows where other !== window {
            Self.controller(for: other)?.sharedScrollOffset = offset
        }
    }

    /// The window shown for this window's group: its selected tab, or the window itself when it has no group.
    private var shownWindow: NSWindow? {
        window?.tabGroup?.selectedWindow ?? window
    }

    /// Brings the bar up to date synchronously if its tab is now the shown one and it missed group changes.
    private func updateIfStale() {
        guard isStale, let window, shownWindow === window else { return }
        rebuild()
    }

    private func setVisible(_ visible: Bool) {
        guard accessory.isHidden == visible || barView.isHidden == visible else { return }
        accessory.isHidden = !visible
        barView.isHidden = !visible
    }

    /// The model's callback, synchronous from KVO: hide macOS's strip in every window of the group right away (it
    /// must never reach the screen), then rebuild - at once when a bar has to appear or disappear, so a new tab
    /// never shows a frame without its bar, otherwise (and during a reorder) coalesced.
    private func groupDidChange() {
        let windows = groupWindows
        windows.forEach(Self.hideNativeTabBar(in:))
        // A newly selected tab is displayed at the end of this turn: its bar must be current by then.
        if !Self.isReordering, let shown = shownWindow { Self.controller(for: shown)?.updateIfStale() }
        let shouldShow = windows.count > 1
        if !Self.isReordering, windows.contains(where: { Self.controller(for: $0).map { $0.isVisible != shouldShow } ?? false }) {
            rebuild()
        } else {
            refresh()
        }
    }

    /// Builds the items for the group and shows them in the shown tab's bar; the other bars only follow whether
    /// the bar shows at all, and are marked stale. Returns the windows covered.
    @discardableResult
    private func rebuild() -> [NSWindow] {
        guard let window else { return [] }
        let windows = groupWindows
        let selected = shownWindow ?? window
        let items = windows.map { tab -> SAClaudeWindowTabItem in
            let controller = tab.windowController as? SPWindowController
            return SAClaudeWindowTabItem(window: tab,
                                         title: controller?.tabBarTitle ?? tab.title,
                                         tooltip: tab.title,
                                         colour: controller?.tabBarColour,
                                         isSSL: controller?.tabBarIsSSL ?? false,
                                         isSelected: tab === selected)
        }
        for (tab, item) in zip(windows, items) {
            let controller = tab.windowController as? SPWindowController
            controller?.tabBar?.show(items, isShown: tab === selected)
            controller?.tabBarSelectionDidChange(isSelected: item.isSelected)
        }
        return windows
    }

    /// Hidden tabs' bars still show or hide with the group (so the title bar has the right height when the tab
    /// is selected) but skip the chips.
    private func show(_ items: [SAClaudeWindowTabItem], isShown: Bool) {
        setVisible(items.count > 1)
        guard isShown else {
            isStale = true
            return
        }
        isStale = false
        if let offset = sharedScrollOffset {
            sharedScrollOffset = nil
            barView.adoptScrollOffset(offset)
        }
        barView.items = items
    }

    #if DEBUG
    /// Windows whose title bar the safety net below checks at the end of this main-queue turn.
    private static var windowsToReport: [NSWindow] = []

    /// Checks `window` once this turn, however often its strip was hidden (several KVO callbacks for each window
    /// of the group per change).
    private static func scheduleNativeStripReport(for window: NSWindow) {
        if windowsToReport.isEmpty {
            DispatchQueue.main.async {
                let windows = windowsToReport
                windowsToReport = []
                windows.forEach(reportVisibleNativeStrip(in:))
            }
        }
        if !windowsToReport.contains(where: { $0 === window }) {
            windowsToReport.append(window)
        }
    }

    /// The safety net for the hiding above: a debug log when a macOS tab strip is still visible in the window's
    /// title bar. Logged rather than asserted - a future macOS that hosts the strip differently only shows its
    /// strip above ours, which must not take a debug build down. Only the frame view's title bar side is walked,
    /// not the content view's (much larger) subtree, as this runs on every group change.
    private static func reportVisibleNativeStrip(in window: NSWindow) {
        guard let contentView = window.contentView, let frameView = contentView.superview else { return }
        for subview in frameView.subviews where subview !== contentView {
            if let strip = visibleNativeStrip(in: subview) {
                NSLog("SAClaudeWindowTabBar: macOS's tab strip is still visible in '%@' (%@)", window.title, NSStringFromClass(type(of: strip)))
                return
            }
        }
    }

    /// A hidden accessory controller collapses its view rather than hiding it, so a strip counts as visible only
    /// when some of it is on screen.
    private static func visibleNativeStrip(in view: NSView) -> NSView? {
        // The strip is never inside our own bar.
        if view is SAClaudeWindowTabBarView { return nil }
        if NSStringFromClass(type(of: view)) == "NSTabBar" {
            return view.isHiddenOrHasHiddenAncestor || view.visibleRect.height <= 1 ? nil : view
        }
        for subview in view.subviews {
            if let strip = visibleNativeStrip(in: subview) { return strip }
        }
        return nil
    }
    #endif
}

/// Our accessory controller, a class of its own so the hiding above can tell it from AppKit's.
private final class SAClaudeWindowTabBarAccessory: NSTitlebarAccessoryViewController {}

// MARK: - Model

/// Follows one window's tab group: `NSWindow.tabGroup` (the group object changes when tabs are merged, moved out
/// or reordered), and that group's `windows` and `selectedWindow`. Calls `onChange` synchronously for every change.
final class SAClaudeWindowTabBarModel: NSObject {
    private let onChange: () -> Void
    private var tabGroupObservation: NSKeyValueObservation?
    private var groupObservations: [NSKeyValueObservation] = []
    private weak var observedGroup: NSWindowTabGroup?

    init(window: NSWindow, onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
        tabGroupObservation = window.observe(\.tabGroup, options: [.initial, .new]) { [weak self] window, _ in
            self?.observe(window.tabGroup)
            self?.onChange()
        }
    }

    deinit {
        tabGroupObservation?.invalidate()
        groupObservations.forEach { $0.invalidate() }
    }

    /// Re-binds to `group`; a no-op while it is already the observed group. A deallocated group reads as nil.
    private func observe(_ group: NSWindowTabGroup?) {
        guard group !== observedGroup || (group != nil && groupObservations.isEmpty) else { return }
        groupObservations.forEach { $0.invalidate() }
        observedGroup = group
        guard let group else {
            groupObservations = []
            return
        }
        groupObservations = [
            group.observe(\.windows) { [weak self] _, _ in self?.onChange() },
            group.observe(\.selectedWindow) { [weak self] _, _ in self?.onChange() },
        ]
    }
}
