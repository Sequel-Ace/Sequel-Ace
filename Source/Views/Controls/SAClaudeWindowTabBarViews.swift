//
//  SAClaudeWindowTabBarViews.swift
//  Sequel Ace
//
//  The views of the Claude window tab bar: the bar itself (a scrolling strip of chips and "+") and the chips.
//  The controller and model that feed them are in SAClaudeWindowTabBar.swift.
//

import AppKit

// MARK: - Bar view

/// The bar: chips in a horizontally scrolling strip, and "+" at the right. Transparent, so the Claude bar colour
/// or the favourite tint of the window shows through, with a divider line along its bottom. A chip dragged along
/// the strip reorders the tabs. For accessibility it is a tab group whose tabs are the chips.
final class SAClaudeWindowTabBarView: NSView {
    /// The document window this bar belongs to. In full screen AppKit moves the bar into its own toolbar window,
    /// so `window` is not it then.
    weak var hostWindow: NSWindow?

    var items: [SAClaudeWindowTabItem] = [] {
        didSet {
            // The chips are about to show other items: a drag in progress would move the wrong one.
            endDrag()
            let selected = items.first(where: \.isSelected)?.window
            if selected !== shownSelection {
                shownSelection = selected
                needsScrollToSelection = true
            }
            updateChips()
        }
    }

    /// How far the pointer moves before a press on a chip becomes a drag.
    private static let dragThreshold: CGFloat = 4
    /// Releasing a drag further than this above or below the bar cancels it.
    private static let cancelDistance: CGFloat = 24
    /// A drag this close to an edge of the scrolling area scrolls the strip that way.
    private static let autoscrollEdge: CGFloat = 24
    private static let maxAutoscrollStep: CGFloat = 16
    private static let draggedChipAlpha: CGFloat = 0.85
    /// Kept visible at either side of the selected chip when scrolling it into view.
    private static let selectionMargin: CGFloat = 8
    private static let escapeKeyCode: UInt16 = 53

    /// A chip being dragged. `windows` is the group's tab order at the start; chip and step ids index into it.
    private struct Drag {
        let chip: SAClaudeWindowTabChipView
        let index: Int
        let windows: [NSWindow]
        let selectedIndex: Int
        /// The pointer's x minus the chip's left edge at the start, in strip coordinates.
        let grabOffset: CGFloat
        /// Where a release would insert the chip; `nil` when it would leave the order as it is, or cancel.
        var insertion: Int?
    }

    private let scrollView = SAClaudeWindowTabScrollView()
    private let stripView = SAClaudeWindowTabStripView()
    private var chips: [SAClaudeWindowTabChipView] = []
    /// The chips' laid-out frames in strip coordinates; a dragged chip leaves its slot here.
    private var chipSlots: [NSRect] = []
    private var scrolls = false
    private let plusButton = SAClaudeWindowTabBarButton()
    private let insertionMarker = SAClaudeWindowTabInsertionMarker()
    private var drag: Drag?
    /// The selected tab the strip last scrolled for.
    private weak var shownSelection: NSWindow?
    private var needsScrollToSelection = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = stripView
        addSubview(scrollView)
        insertionMarker.isHidden = true
        stripView.addSubview(insertionMarker)

        let image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        plusButton.image = image
        plusButton.imagePosition = .imageOnly
        plusButton.isBordered = false
        plusButton.contentTintColor = SAClaudeStyle.textSecondary
        plusButton.target = self
        plusButton.action = #selector(newTab(_:))
        // A new tab joins the main window: let the first click bring an inactive app's window forward first.
        plusButton.answersFirstClick = false
        let newTabTitle = NSLocalizedString("ClaudeTabBarNewTab", comment: "window tab bar: tooltip and accessibility name of the button that opens a new tab")
        plusButton.toolTip = newTabTitle
        plusButton.setAccessibilityLabel(newTabTitle)
        SAClaudeHoverHighlighter.attach(to: plusButton)
        addSubview(plusButton)

        SAClaudeAccent.observe(self) { SAClaudeAccent.redisplay($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        if window !== hostWindow {
            // Full screen: the bar sits in AppKit's toolbar window, which has no window colour behind it.
            SAClaudeStyle.toolbarBackground.setFill()
            bounds.fill()
        }
        SAClaudeStyle.divider.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let frames = SAClaudeWindowTabBarLayout.frames(count: chips.count, barWidth: bounds.width)
        scrollView.frame = frames.scrollArea
        scrollView.tile()
        stripView.frame = NSRect(x: 0, y: 0, width: frames.contentWidth, height: frames.scrollArea.height)
        for (chip, frame) in zip(chips, frames.chips) {
            chip.frame = frame
        }
        chipSlots = frames.chips
        scrolls = frames.scrolls
        plusButton.frame = frames.plus
        if !scrolls {
            scrollView.scrollHorizontally(to: 0)
        } else if needsScrollToSelection, let index = items.firstIndex(where: \.isSelected), index < chipSlots.count {
            scrollView.scrollHorizontally(toShow: chipSlots[index].insetBy(dx: -Self.selectionMargin, dy: 0))
        }
        needsScrollToSelection = false
        if drag != nil, let window {
            updateDrag(to: window.mouseLocationOutsideOfEventStream)
        }
        updateHover()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Entering or leaving full screen moves the bar between windows; the fill depends on which.
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        SAClaudeAccent.redisplay(self)
    }

    /// One chip per item, reusing the chips already there.
    private func updateChips() {
        while chips.count > items.count {
            chips.removeLast().removeFromSuperview()
        }
        while chips.count < items.count {
            let chip = SAClaudeWindowTabChipView(item: items[chips.count])
            chip.bar = self
            stripView.addSubview(chip, positioned: .below, relativeTo: insertionMarker)
            chips.append(chip)
        }
        for (chip, item) in zip(chips, items) {
            chip.item = item
        }
        needsLayout = true
    }

    /// Chips move under a still pointer when tabs open, close or the window resizes, which their tracking areas
    /// don't report; set the hover from where the pointer is now.
    private func updateHover() {
        guard let window else { return }
        let location = window.mouseLocationOutsideOfEventStream
        for chip in chips {
            chip.isHovered = chip.visibleRect.contains(chip.convert(location, from: nil))
        }
    }

    /// "+": a new tab in this bar's window, the way the native strip's "+" and ⌘T make one.
    @objc private func newTab(_ sender: Any?) {
        guard let hostWindow else { return }
        hostWindow.makeKeyAndOrderFront(nil)
        NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: hostWindow)
    }

    // MARK: Drag to reorder

    /// A press on a chip, tracked until the button comes up: a click selects the chip's tab; past the threshold
    /// the chip follows the pointer along the strip, a marker shows where it would go, and the release moves the
    /// tab there. Esc, or a release well above or below the bar, cancels.
    func trackPress(on chip: SAClaudeWindowTabChipView, with mouseDown: NSEvent) {
        guard let window else { return }
        let start = mouseDown.locationInWindow
        var began = false
        var autoscroll: Timer?
        defer {
            autoscroll?.invalidate()
            endDrag()
        }
        while let event = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            // The group changed under the drag, which rebuilt the chips and ended it.
            if began && drag == nil { return }
            switch event.type {
            case .leftMouseDragged:
                let location = event.window === window ? event.locationInWindow : window.mouseLocationOutsideOfEventStream
                if !began {
                    guard hypot(location.x - start.x, location.y - start.y) >= Self.dragThreshold else { continue }
                    guard beginDrag(chip, at: start) else { return }
                    began = true
                    autoscroll = startAutoscroll()
                }
                updateDrag(to: location)
            case .leftMouseUp:
                if began {
                    drop()
                } else {
                    chip.select()
                }
                return
            case .keyDown where event.keyCode == Self.escapeKeyCode:
                return
            default:
                continue
            }
        }
    }

    /// Lifts `chip` out of its slot. Fails when the chips don't show the group's current tab order.
    private func beginDrag(_ chip: SAClaudeWindowTabChipView, at start: NSPoint) -> Bool {
        guard let index = chips.firstIndex(where: { $0 === chip }), index < chipSlots.count,
              let group = hostWindow?.tabGroup, let selected = group.selectedWindow else { return false }
        let windows = group.windows
        guard windows.count == items.count, zip(windows, items).allSatisfy({ $0 === $1.window }),
              let selectedIndex = windows.firstIndex(where: { $0 === selected }) else { return false }
        drag = Drag(chip: chip, index: index, windows: windows, selectedIndex: selectedIndex,
                    grabOffset: stripView.convert(start, from: nil).x - chipSlots[index].minX, insertion: nil)
        // Drawn above the other chips, with the marker above it.
        stripView.addSubview(chip, positioned: .below, relativeTo: insertionMarker)
        chip.alphaValue = Self.draggedChipAlpha
        return true
    }

    /// Moves the dragged chip under the pointer (`location` in window coordinates) and the marker to the gap it
    /// would drop into.
    private func updateDrag(to location: NSPoint) {
        guard var drag, drag.index < chipSlots.count else { return }
        let slot = chipSlots[drag.index]
        let x = stripView.convert(location, from: nil).x
        let chipX = min(max(0, x - drag.grabOffset), max(0, stripView.bounds.width - slot.width))
        drag.chip.setFrameOrigin(NSPoint(x: chipX, y: slot.minY))
        let y = convert(location, from: nil).y
        let insertion = SAClaudeWindowTabBarLayout.insertionIndex(x: x, chips: chipSlots)
        let isNearBar = y >= -Self.cancelDistance && y <= bounds.height + Self.cancelDistance
        let moves = insertion != drag.index && insertion != drag.index + 1
        drag.insertion = isNearBar && moves ? insertion : nil
        self.drag = drag
        if let insertion = drag.insertion {
            insertionMarker.frame = NSRect(x: markerX(at: insertion), y: slot.minY, width: SAClaudeWindowTabInsertionMarker.width, height: slot.height)
            insertionMarker.isHidden = false
        } else {
            insertionMarker.isHidden = true
        }
    }

    /// The marker's x for the gap before chip `insertion` (after the last chip for `chipSlots.count`), in strip
    /// coordinates, kept inside the strip.
    private func markerX(at insertion: Int) -> CGFloat {
        let centre: CGFloat
        if insertion <= 0 {
            centre = chipSlots[0].minX
        } else if insertion >= chipSlots.count {
            centre = chipSlots[chipSlots.count - 1].maxX
        } else {
            centre = (chipSlots[insertion - 1].maxX + chipSlots[insertion].minX) / 2
        }
        let width = SAClaudeWindowTabInsertionMarker.width
        return min(max(0, (centre - width / 2).rounded(.down)), max(0, stripView.bounds.width - width))
    }

    /// Moves the tab to the marked gap: only the dragged tab when it isn't the selected one, otherwise the others
    /// around it (moving the selected window out of the group and back would change the selection).
    private func drop() {
        guard let drag, let insertion = drag.insertion else { return }
        let order = Array(drag.windows.indices)
        let target = SAClaudeWindowTabBarLayout.target(order: order, moving: drag.index, toInsertion: insertion)
        guard target != order, let draggedTarget = target.firstIndex(of: drag.index) else { return }
        let steps = drag.index == drag.selectedIndex
            ? SAClaudeWindowTabBarLayout.reorderSteps(order: order, target: target, selected: drag.selectedIndex)
            : [SAClaudeWindowTabBarLayout.Step(id: drag.index, index: draggedTarget)]
        let reordered = target.map { items[$0] }
        endDrag()
        // The new order at once; the group's own refresh follows.
        items = reordered
        SAClaudeWindowTabBarController.reorder(drag.windows, steps: steps, keeping: drag.windows[drag.selectedIndex])
    }

    /// Puts a dragged chip back into the layout; a no-op when nothing is dragged.
    private func endDrag() {
        guard let drag else { return }
        self.drag = nil
        drag.chip.alphaValue = 1
        insertionMarker.isHidden = true
        needsLayout = true
    }

    /// Scrolls the strip while a drag is held near an edge of the scrolling area.
    private func startAutoscroll() -> Timer {
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.autoscroll() }
        RunLoop.current.add(timer, forMode: .eventTracking)
        return timer
    }

    private func autoscroll() {
        guard drag != nil, scrolls, let window else { return }
        let location = window.mouseLocationOutsideOfEventStream
        let x = scrollView.convert(location, from: nil).x
        let edge = Self.autoscrollEdge
        let delta: CGFloat
        if x < edge {
            delta = -min(Self.maxAutoscrollStep, (edge - x) / 2 + 1)
        } else if x > scrollView.bounds.width - edge {
            delta = min(Self.maxAutoscrollStep, (x - scrollView.bounds.width + edge) / 2 + 1)
        } else {
            return
        }
        if scrollView.scrollHorizontally(by: delta) {
            updateDrag(to: location)
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .tabGroup }
    override func accessibilityChildren() -> [Any]? { chips + [plusButton] }
    override func accessibilityTabs() -> [Any]? { chips }
    override func accessibilityValue() -> Any? { chips.first { $0.item.isSelected } }
}

/// The scrolling area of the strip: scrolls only horizontally, a mouse wheel's vertical turns included.
private final class SAClaudeWindowTabScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard !event.hasPreciseScrollingDeltas, event.scrollingDeltaX == 0, event.scrollingDeltaY != 0 else {
            super.scrollWheel(with: event)
            return
        }
        // Wheel down scrolls towards the end, as shift-wheel does.
        scrollHorizontally(by: -event.scrollingDeltaY * horizontalLineScroll)
    }

    /// Scrolls by `delta` points, kept within the strip; whether it moved.
    @discardableResult
    func scrollHorizontally(by delta: CGFloat) -> Bool {
        scrollHorizontally(to: contentView.bounds.minX + delta)
    }

    /// Scrolls the least that brings `rect` (strip coordinates) into view.
    func scrollHorizontally(toShow rect: NSRect) {
        let visible = contentView.bounds
        if rect.minX < visible.minX || rect.width > visible.width {
            scrollHorizontally(to: rect.minX)
        } else if rect.maxX > visible.maxX {
            scrollHorizontally(to: rect.maxX - visible.width)
        }
    }

    @discardableResult
    func scrollHorizontally(to x: CGFloat) -> Bool {
        let clip = contentView
        let maxX = max(0, (documentView?.frame.width ?? 0) - clip.bounds.width)
        let clamped = min(max(0, x), maxX)
        guard clamped != clip.bounds.minX else { return false }
        clip.scroll(to: NSPoint(x: clamped, y: clip.bounds.minY))
        reflectScrolledClipView(clip)
        return true
    }
}

/// The scrolling content holding the chips. Its empty space drags the window, like the rest of the title bar.
private final class SAClaudeWindowTabStripView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}

/// The 2pt accent bar showing where a dragged chip would drop.
private final class SAClaudeWindowTabInsertionMarker: NSView {
    static let width: CGFloat = 2

    override func draw(_ dirtyRect: NSRect) {
        SAClaudeAccent.accent.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.width / 2, yRadius: Self.width / 2).fill()
    }
}

/// A borderless glyph button for the bar.
private final class SAClaudeWindowTabBarButton: NSButton {
    /// Whether the click that brings an inactive window forward also presses the button.
    var answersFirstClick = true

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { answersFirstClick }
    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: - Chip

/// One tab: favourite dot, title and SSL padlock centred as a group (`SAClaudeTabContentLayout`, as the native
/// tab content did) in the space left of the close button, which shows at the right while hovered or selected. Selected: card fill with a
/// hairline, medium primary title. Others: no fill (hover fill under the pointer), regular secondary title.
/// A press is tracked by the bar (click to select, drag to reorder); right-click shows the tab's menu.
final class SAClaudeWindowTabChipView: NSView {
    static let cornerRadius: CGFloat = 8
    static let closeSize: CGFloat = 16
    static let closeInset: CGFloat = 6
    /// Kept clear at the right of the content whether or not the close button shows, so the title never moves.
    static let closeReserve: CGFloat = closeInset + closeSize + 2
    /// The content's padding at the left.
    static let contentInset: CGFloat = 10

    var item: SAClaudeWindowTabItem {
        didSet { applyItem() }
    }

    /// The bar showing this chip, which tracks presses on it and is its accessibility parent.
    weak var bar: SAClaudeWindowTabBarView?

    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            updateCloseButton()
            needsDisplay = true
        }
    }

    private let titleField: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.truncatesLastVisibleLine = true
        return field
    }()

    private let lockView: NSImageView = {
        let image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: SAClaudeTabContentLayout.lockSize, weight: .regular))
            ?? NSImage(named: "fallback_lock.fill")
        image?.isTemplate = true
        let view = NSImageView()
        view.image = image
        view.imageScaling = .scaleProportionallyDown
        view.contentTintColor = SAClaudeStyle.textMuted
        view.toolTip = NSLocalizedString("Connection Secured via SSL", comment: "Connection Secured via SSL information text")
        return view
    }()

    private let closeButton: SAClaudeWindowTabBarButton = {
        let button = SAClaudeWindowTabBarButton()
        button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = SAClaudeStyle.textSecondary
        button.setAccessibilityLabel(NSLocalizedString("ClaudeTabBarCloseTab", comment: "window tab bar: accessibility name of a tab's close button, and the context menu item that closes the tab"))
        SAClaudeHoverHighlighter.attach(to: button)
        button.layer?.cornerRadius = 4
        return button
    }()

    /// Where the favourite dot is drawn, `nil` when there is none.
    private var dotFrame: NSRect?

    init(item: SAClaudeWindowTabItem) {
        self.item = item
        super.init(frame: .zero)
        // The chip itself is the accessibility element and carries the title.
        titleField.setAccessibilityElement(false)
        lockView.setAccessibilityElement(false)
        addSubview(titleField)
        addSubview(lockView)
        addSubview(closeButton)
        closeButton.target = self
        closeButton.action = #selector(closeTab(_:))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
        applyItem()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyItem() {
        titleField.stringValue = item.title
        titleField.font = .systemFont(ofSize: 12, weight: item.isSelected ? .medium : .regular)
        titleField.textColor = item.isSelected ? SAClaudeStyle.textPrimary : SAClaudeStyle.textSecondary
        if toolTip != item.tooltip { toolTip = item.tooltip }
        updateCloseButton()
        needsLayout = true
        needsDisplay = true
    }

    private func updateCloseButton() {
        closeButton.isHidden = !(isHovered || item.isSelected)
    }

    override func layout() {
        super.layout()
        let inset = Self.contentInset
        let content = NSSize(width: max(0, bounds.width - inset - Self.closeReserve), height: bounds.height)
        let frames = SAClaudeTabContentLayout.frames(size: content,
                                                     titleWidth: titleField.cell?.cellSize.width ?? 0,
                                                     hasColour: item.colour != nil,
                                                     isSSL: item.isSSL)
        dotFrame = frames.dot?.offsetBy(dx: inset, dy: 0)
        titleField.frame = frames.title.offsetBy(dx: inset, dy: 0)
        lockView.isHidden = frames.lock == nil
        if let lock = frames.lock { lockView.frame = lock.offsetBy(dx: inset, dy: 0) }
        closeButton.frame = NSRect(x: bounds.width - Self.closeInset - Self.closeSize,
                                   y: ((bounds.height - Self.closeSize) / 2).rounded(.down),
                                   width: Self.closeSize, height: Self.closeSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if item.isSelected {
            let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius - 0.5, yRadius: Self.cornerRadius - 0.5)
            SAClaudeStyle.hoverFill.setFill()
            card.fill()
            SAClaudeStyle.divider.setStroke()
            card.lineWidth = 1
            card.stroke()
        } else if isHovered {
            SAClaudeStyle.hoverFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
        }
        if let colour = item.colour, let dotFrame {
            colour.setFill()
            NSBezierPath(ovalIn: dotFrame).fill()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        if let bar {
            bar.trackPress(on: self, with: event)
        } else {
            select()
        }
    }

    /// Makes this chip's tab the group's selected one.
    func select() {
        guard !item.isSelected, let window = item.window, let group = window.tabGroup else { return }
        group.selectedWindow = window
    }

    /// Middle-click closes the tab, as in browsers.
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseUp(with: event)
            return
        }
        item.window?.performClose(nil)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseDown(with: event)
            return
        }
    }

    @objc private func closeTab(_ sender: Any?) {
        item.window?.performClose(nil)
    }

    // MARK: Menu

    override func menu(for event: NSEvent) -> NSMenu? { tabMenu() }

    /// Close tab, Close other tabs, Move tab to new window, Merge all windows.
    private func tabMenu() -> NSMenu? {
        guard let window = item.window else { return nil }
        let group = window.tabGroup?.windows ?? [window]
        let hasOtherTabs = group.contains { $0 !== window }
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let menuItem = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            menuItem.target = self
            menuItem.isEnabled = enabled
        }
        add(NSLocalizedString("ClaudeTabBarCloseTab", comment: "window tab bar: accessibility name of a tab's close button, and the context menu item that closes the tab"),
            #selector(closeTab(_:)))
        add(NSLocalizedString("ClaudeTabBarCloseOthers", comment: "window tab bar: context menu item that closes every tab of the window except the clicked one"),
            #selector(closeOtherTabs(_:)), enabled: hasOtherTabs)
        menu.addItem(.separator())
        add(NSLocalizedString("ClaudeTabBarMoveToNewWindow", comment: "window tab bar: context menu item that moves the clicked tab out into a window of its own"),
            #selector(moveTabToNewWindow(_:)), enabled: hasOtherTabs)
        add(NSLocalizedString("ClaudeTabBarMergeAll", comment: "window tab bar: context menu item that merges every window of the app into tabs of this window"),
            #selector(mergeAllWindows(_:)), enabled: Self.hasOtherWindows(than: window, group: group))
        return menu
    }

    /// Whether the app shows a window, outside `group`, that `window` could merge with.
    private static func hasOtherWindows(than window: NSWindow, group: [NSWindow]) -> Bool {
        NSApp.windows.contains { other in
            other.tabbingIdentifier == window.tabbingIdentifier
                && !group.contains { $0 === other }
                && (other.isVisible || other.isMiniaturized)
        }
    }

    /// Asks every other tab of the group to close, each the way ⌘W would.
    @objc private func closeOtherTabs(_ sender: Any?) {
        guard let window = item.window else { return }
        for other in window.tabGroup?.windows ?? [] where other !== window {
            other.performClose(nil)
        }
    }

    @objc private func moveTabToNewWindow(_ sender: Any?) {
        item.window?.moveTabToNewWindow(nil)
    }

    @objc private func mergeAllWindows(_ sender: Any?) {
        item.window?.mergeAllWindows(nil)
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }
    override func accessibilityLabel() -> String? { item.title }
    override func accessibilityHelp() -> String? { item.tooltip }
    override func accessibilityValue() -> Any? { NSNumber(value: item.isSelected) }
    override func isAccessibilitySelected() -> Bool { item.isSelected }
    override func accessibilityParent() -> Any? { bar ?? super.accessibilityParent() }

    override func accessibilityPerformPress() -> Bool {
        select()
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu = tabMenu() else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
        return true
    }
}
