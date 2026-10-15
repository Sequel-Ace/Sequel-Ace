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
        model = SAClaudeWindowTabBarModel(window: window) { [weak self] in self?.groupDidChange() }
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
    /// to repeat. Only the controller is hidden - hiding the strip view alone would leave an empty band.
    static func hideNativeTabBar(in window: NSWindow) {
        for controller in window.titlebarAccessoryViewControllers
        where !(controller is SAClaudeWindowTabBarAccessory) && controller.layoutAttribute == .bottom && !controller.isHidden {
            controller.isHidden = true
        }
        #if DEBUG
        reportVisibleNativeStrip(in: window)
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

    // MARK: Private

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
        let shouldShow = windows.count > 1
        if !Self.isReordering, windows.contains(where: { Self.controller(for: $0).map { $0.isVisible != shouldShow } ?? false }) {
            rebuild()
        } else {
            refresh()
        }
    }

    /// Builds the items for the group and shows them in every group window's bar. Returns the windows covered.
    @discardableResult
    private func rebuild() -> [NSWindow] {
        guard let window else { return [] }
        let windows = groupWindows
        let selected = window.tabGroup?.selectedWindow ?? window
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
            controller?.tabBar?.show(items)
            controller?.tabBarSelectionDidChange(isSelected: item.isSelected)
        }
        return windows
    }

    private func show(_ items: [SAClaudeWindowTabItem]) {
        setVisible(items.count > 1)
        barView.items = items
    }

    #if DEBUG
    /// The safety net for the hiding above: a debug log when a macOS tab strip is still visible in the window's
    /// frame view. Logged rather than asserted - a future macOS that hosts the strip differently only shows its
    /// strip above ours, which must not take a debug build down.
    private static func reportVisibleNativeStrip(in window: NSWindow) {
        guard let frameView = window.contentView?.superview, let strip = visibleNativeStrip(in: frameView) else { return }
        NSLog("SAClaudeWindowTabBar: macOS's tab strip is still visible in '%@' (%@)", window.title, NSStringFromClass(type(of: strip)))
    }

    /// A hidden accessory controller collapses its view rather than hiding it, so a strip counts as visible only
    /// when some of it is on screen.
    private static func visibleNativeStrip(in view: NSView) -> NSView? {
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
