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
/// or the favourite tint of the window shows through, with a divider line along its bottom.
final class SAClaudeWindowTabBarView: NSView {
    /// The document window this bar belongs to. In full screen AppKit moves the bar into its own toolbar window,
    /// so `window` is not it then.
    weak var hostWindow: NSWindow?

    var items: [SAClaudeWindowTabItem] = [] {
        didSet { updateChips() }
    }

    private let scrollView = NSScrollView()
    private let stripView = SAClaudeWindowTabStripView()
    private var chips: [SAClaudeWindowTabChipView] = []
    private let plusButton = SAClaudeWindowTabBarButton()

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
        stripView.frame = NSRect(x: 0, y: 0, width: frames.contentWidth, height: frames.scrollArea.height)
        for (chip, frame) in zip(chips, frames.chips) {
            chip.frame = frame
        }
        plusButton.frame = frames.plus
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
            stripView.addSubview(chip)
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
}

/// The scrolling content holding the chips. Its empty space drags the window, like the rest of the title bar.
private final class SAClaudeWindowTabStripView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
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
}
