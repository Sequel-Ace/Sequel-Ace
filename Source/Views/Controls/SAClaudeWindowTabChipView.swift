//
//  SAClaudeWindowTabChipView.swift
//  Sequel Ace
//
//  One chip of the Claude window tab bar (the bar is in SAClaudeWindowTabBarViews.swift): its look, its
//  content-sized width, the tab's context menu and its accessibility.
//

import AppKit

/// One tab, shaped as one: a rounded card with a hairline border, holding the favourite dot, title and SSL
/// padlock centred as a group (`SAClaudeTabContentLayout`, as the native tab content did) left of the close
/// button. Selected: raised - a lighter card with a soft shadow, medium primary title, close button always shown.
/// Others: regular secondary title; hover lightens the card and shows the close button. The line along the bottom
/// is the item's `line`: the selected chip's accent, or with Tab underline each chip's connection colour. A press is tracked by the bar (click to select, drag to reorder); right-click shows the
/// tab's menu.
final class SAClaudeWindowTabChipView: NSView {
    static let cornerRadius: CGFloat = 8
    static let closeSize: CGFloat = 16
    /// Between the content and the close button, kept whether or not the button shows, so the title never moves.
    static let closeGap: CGFloat = 6
    /// The padding at either side of the chip.
    static let sideInset: CGFloat = 10
    static let titleFontSize: CGFloat = 13
    /// The preferred width's room between the dot and the title, and between the title and the padlock.
    static let dotGap: CGFloat = 6
    static let lockGap: CGFloat = 5
    static let accentLineWidth: CGFloat = 2
    /// The line's distance from either side of the chip.
    static let accentLineInset: CGFloat = 10
    /// Lightens an unselected card under the pointer: the selected fill at this opacity over the tab fill.
    static let hoverOpacity: CGFloat = 0.6

    /// The width that shows `item` whole: padding, dot, title, padlock and the close button's slot. The title is
    /// measured in the selected (medium) weight so a chip keeps its width when the selection moves.
    static func preferredWidth(for item: SAClaudeWindowTabItem) -> CGFloat {
        measuringField.stringValue = item.title
        var width = sideInset + (measuringField.cell?.cellSize.width ?? 0) + closeGap + closeSize + sideInset
        if item.colour != nil { width += SAClaudeTabContentLayout.dotSize + dotGap }
        if item.isSSL { width += lockGap + SAClaudeTabContentLayout.lockSize }
        return width.rounded(.up)
    }

    private static let measuringField: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: titleFontSize, weight: .medium)
        return field
    }()

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
        titleField.font = .systemFont(ofSize: Self.titleFontSize, weight: item.isSelected ? .medium : .regular)
        titleField.textColor = item.isSelected ? SAClaudeStyle.textPrimary : SAClaudeStyle.textSecondary
        if toolTip != item.tooltip { toolTip = item.tooltip }
        closeButton.setAccessibilityLabel(String(format: NSLocalizedString("ClaudeTabBarCloseTabNamed", comment: "window tab bar: accessibility name of a tab's close button, with the tab's title"), item.title))
        updateCloseButton()
        updateShadow()
        needsLayout = true
        needsDisplay = true
    }

    private func updateCloseButton() {
        closeButton.isHidden = !(isHovered || item.isSelected)
    }

    /// The selected chip's lift: a soft shadow below it, stronger on a dark appearance.
    private func updateShadow() {
        guard item.isSelected else {
            if shadow != nil { shadow = nil }
            return
        }
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let lift = NSShadow()
        lift.shadowOffset = NSSize(width: 0, height: -1)
        lift.shadowBlurRadius = 2
        lift.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.18 : 0.08)
        shadow = lift
    }

    override func layout() {
        super.layout()
        let inset = Self.sideInset
        let closeX = bounds.width - Self.sideInset - Self.closeSize
        let content = NSSize(width: max(0, closeX - Self.closeGap - inset), height: bounds.height)
        let frames = SAClaudeTabContentLayout.frames(size: content,
                                                     titleWidth: titleField.cell?.cellSize.width ?? 0,
                                                     hasColour: item.colour != nil,
                                                     isSSL: item.isSSL)
        dotFrame = frames.dot?.offsetBy(dx: inset, dy: 0)
        titleField.frame = frames.title.offsetBy(dx: inset, dy: 0)
        lockView.isHidden = frames.lock == nil
        if let lock = frames.lock { lockView.frame = lock.offsetBy(dx: inset, dy: 0) }
        closeButton.frame = NSRect(x: closeX,
                                   y: ((bounds.height - Self.closeSize) / 2).rounded(.down),
                                   width: Self.closeSize, height: Self.closeSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius - 0.5, yRadius: Self.cornerRadius - 0.5)
        card.lineWidth = 1
        if item.isSelected {
            SAClaudeStyle.tabSelectedFill.setFill()
            card.fill()
            SAClaudeStyle.tabSelectedBorder.setStroke()
            card.stroke()
        } else {
            SAClaudeStyle.tabFill.setFill()
            card.fill()
            if isHovered {
                SAClaudeStyle.tabSelectedFill.withAlphaComponent(Self.hoverOpacity).setFill()
                card.fill()
            }
            SAClaudeStyle.tabBorder.setStroke()
            card.stroke()
        }
        drawLine()
        if let colour = item.colour, let dotFrame {
            colour.setFill()
            NSBezierPath(ovalIn: dotFrame).fill()
        }
    }

    /// The item's line, just inside the bottom border; its round caps end `accentLineInset` from the sides.
    private func drawLine() {
        let colour: NSColor
        switch item.line {
        case .none: return
        case .accent: colour = SAClaudeAccent.accent
        case .colour(let lineColour): colour = lineColour
        }
        let cap = Self.accentLineWidth / 2
        let y = 1 + cap
        let line = NSBezierPath()
        line.move(to: NSPoint(x: Self.accentLineInset + cap, y: y))
        line.line(to: NSPoint(x: bounds.width - Self.accentLineInset - cap, y: y))
        line.lineWidth = Self.accentLineWidth
        line.lineCapStyle = .round
        colour.setStroke()
        line.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateShadow()
        needsDisplay = true
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    /// The whole chip but its close button takes the mouse, so a ctrl-click on the title opens the tab's menu
    /// (AppKit asks the view under the pointer) and a press there is tracked like one on the padding.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit.isDescendant(of: closeButton) ? hit : self
    }

    override func mouseDown(with event: NSEvent) {
        if let bar {
            bar.trackPress(on: self, with: event)
        } else {
            select()
        }
    }

    /// Makes this chip's tab the group's selected one.
    func select() {
        Self.select(item.window)
    }

    /// Makes `window` its group's selected tab.
    static func select(_ window: NSWindow?) {
        guard let window, let group = window.tabGroup, group.selectedWindow !== window else { return }
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
        // Swallowed: the middle button closes the tab on its way up.
    }

    @objc private func closeTab(_ sender: Any?) {
        tab(for: sender)?.performClose(nil)
    }

    // MARK: Menu

    override func menu(for event: NSEvent) -> NSMenu? { tabMenu() }

    /// Close tab, Close other tabs, Move tab to new window, Merge all windows. Each item carries the tab's window,
    /// so it acts on that tab even if the chips are rebuilt while the menu is open.
    private func tabMenu() -> NSMenu? {
        guard let window = item.window else { return nil }
        let group = window.tabGroup?.windows ?? [window]
        let hasOtherTabs = group.contains { $0 !== window }
        let menu = NSMenu()
        menu.autoenablesItems = false
        // No "Ask Siri" field on top (macOS 27 adds it to context menus that allow plug-ins).
        menu.allowsContextMenuPlugIns = false
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let menuItem = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = window
            menuItem.isEnabled = enabled
        }
        add(NSLocalizedString("ClaudeTabBarCloseTab", comment: "window tab bar: context menu item that closes the tab"),
            #selector(closeTab(_:)))
        add(NSLocalizedString("ClaudeTabBarCloseOthers", comment: "window tab bar: context menu item that closes every tab of the window except the clicked one"),
            #selector(closeOtherTabs(_:)), enabled: hasOtherTabs)
        menu.addItem(.separator())
        add(NSLocalizedString("ClaudeTabBarMoveToNewWindow", comment: "window tab bar: context menu item that moves the clicked tab out into a window of its own"),
            #selector(moveTabToNewWindow(_:)), enabled: hasOtherTabs)
        add(NSLocalizedString("ClaudeTabBarMergeAll", comment: "window tab bar: context menu item that merges every window of the app into tabs of this window"),
            #selector(mergeAllWindows(_:)), enabled: SAClaudeWindowTabBarController.canMergeAllWindows(into: hostWindow ?? window))
        return menu
    }

    /// The window this chip's bar is in: the shown tab of the group.
    private var hostWindow: NSWindow? { bar?.hostWindow ?? self.window }

    /// The tab an action is for: the one its menu item was built for, else this chip's.
    private func tab(for sender: Any?) -> NSWindow? {
        (sender as? NSMenuItem)?.representedObject as? NSWindow ?? item.window
    }

    /// Asks every other tab of the group to close, each the way ⌘W would.
    @objc private func closeOtherTabs(_ sender: Any?) {
        guard let window = tab(for: sender) else { return }
        for other in window.tabGroup?.windows ?? [] where other !== window {
            other.performClose(nil)
        }
    }

    @objc private func moveTabToNewWindow(_ sender: Any?) {
        tab(for: sender)?.moveTabToNewWindow(nil)
    }

    /// Merges every other window into this bar's window, which stays selected (and becomes key).
    @objc private func mergeAllWindows(_ sender: Any?) {
        guard let window = hostWindow ?? tab(for: sender) else { return }
        SAClaudeWindowTabBarController.mergeAllWindows(into: window)
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
