//
//  SAClaudeCopyButton.swift
//  Sequel Ace
//
//  The query bar's Copy split button: the main part repeats the last-used copy
//  action on the results (all rows when none are selected), the chevron lists
//  all four. SPComboPopupButton splits the clicks; this draws it as a Claude
//  ghost button. App target only.
//

import AppKit

@objc(SAClaudeCopyButton) final class SAClaudeCopyButton: SPComboPopupButton {

    private enum Part { case main, chevron }

    private static let glyphSize: CGFloat = 16
    private static let leadingPadding: CGFloat = 8
    private static let glyphGap: CGFloat = 6
    private static let trailingPadding: CGFloat = 10
    private static let copiedDuration: TimeInterval = 1.2
    private static var labelFont: NSFont { .systemFont(ofSize: 13) }

    private weak var table: SPCopyTable?
    var palette: SAClaudeEditorChrome.Palette? { didSet { needsDisplay = true } }
    var showsLabel = true { didSet { if showsLabel != oldValue { needsDisplay = true } } }
    /// Called when the default action (and so the label slot, hence the preferred width) changed.
    var preferredWidthDidChange: (() -> Void)?

    private var currentAction = SAClaudeQueryCopyAction.plain
    private var mainAvailable = false
    private var isShowingCopied = false
    private var copiedReset: DispatchWorkItem?
    private var hoveredPart: Part? { didSet { if hoveredPart != oldValue { needsDisplay = true } } }
    private var isMenuOpen = false { didSet { if isMenuOpen != oldValue { needsDisplay = true } } }
    private var ownTrackingArea: NSTrackingArea?
    private var footerItem = NSMenuItem()
    private var observers: [NSObjectProtocol] = []

    static func make(table: SPCopyTable) -> SAClaudeCopyButton {
        let button = SAClaudeCopyButton(frame: NSRect(x: 0, y: 0, width: 60, height: SAClaudeEditorChrome.buttonHeight), pullsDown: true)
        button.table = table
        button.setUp()
        return button
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func setUp() {
        isBordered = false
        (cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))   // a pull-down's item 0 is its title
        for action in SAClaudeQueryCopyAction.allCases {
            let item = NSMenuItem(title: action.menuTitle, action: #selector(chooseAction(_:)), keyEquivalent: "")
            item.tag = action.tag
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        footerItem.isEnabled = false
        menu.addItem(footerItem)
        self.menu = menu
        menu.delegate = self   // SPComboPopupButton tracks the open menu as its delegate

        setAccessibilityHelp(NSLocalizedString("ClaudeCopyOptions", value: "Copy options", comment: "accessibility help of the query bar Copy button: its chevron lists the copy actions"))

        // No target/action: SPComboPopupButton's setTarget: stores a strong reference, so `target = self`
        // would retain the button forever. A main-part click (or Space) arrives in performClick(_:) instead.

        let centre = NotificationCenter.default
        // NSMenu tracking swallows mouseExited, so follow the menu to draw the chevron's open state and re-read the hover.
        // (menuWillOpen/menuDidClose are SPComboPopupButton's, as the menu delegate.)
        observers.append(centre.addObserver(forName: NSMenu.didBeginTrackingNotification, object: menu, queue: .main) { [weak self] _ in
            self?.isMenuOpen = true
        })
        observers.append(centre.addObserver(forName: NSMenu.didEndTrackingNotification, object: menu, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.isMenuOpen = false
            self.hoveredPart = self.partUnderMouse()
        })
        observers.append(centre.addObserver(forName: NSTableView.selectionDidChangeNotification, object: table, queue: .main) { [weak self] _ in self?.refreshState() })
        observers.append(centre.addObserver(forName: .SAClaudeCopyTableDidReload, object: table, queue: .main) { [weak self] _ in self?.refreshState() })
        observers.append(centre.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, SAClaudeQueryCopyAction.storedDefault(in: .standard) != self.currentAction else { return }
            self.refreshState()
        })
        refreshState()
    }

    // MARK: - State

    /// Re-reads the default, the row counts and the column definitions: enablement, ticks, footer, tooltip.
    private func refreshState() {
        let previousAction = currentAction
        currentAction = SAClaudeQueryCopyAction.storedDefault(in: .standard)
        let total = table?.numberOfRows ?? 0
        let selected = table?.numberOfSelectedRows ?? 0
        let hasColumns = table?.hasColumnDefinitions ?? false

        isEnabled = total > 0
        let reason = currentAction.unavailableReason(totalRows: total, hasColumnDefinitions: hasColumns)
        mainAvailable = reason == nil
        let scope = currentAction.scopeDescription(selectedRows: selected, totalRows: total)
        toolTip = reason ?? scope
        setAccessibilityLabel(reason == nil ? scope : "\(currentAction.shortLabel). \(reason!)")

        for item in menu?.items ?? [] {
            guard let action = SAClaudeQueryCopyAction(rawValue: item.tag), item.action == #selector(chooseAction(_:)) else { continue }
            item.state = action == currentAction ? .on : .off
            item.isEnabled = action.unavailableReason(totalRows: total, hasColumnDefinitions: hasColumns) == nil
        }
        footerItem.title = SAClaudeQueryCopyAction.footer(selectedRows: selected, totalRows: total)
        needsDisplay = true
        if currentAction != previousAction {
            invalidateIntrinsicContentSize()
            preferredWidthDidChange?()
        }
    }

    // MARK: - Actions

    /// A main-part click (SPComboPopupButtonCell calls this) or Space repeats the default action.
    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        copyDefault()
    }

    private func copyDefault() {
        guard mainAvailable else { NSSound.beep(); return }
        perform(currentAction)
    }

    @objc private func chooseAction(_ sender: NSMenuItem) {
        guard let action = SAClaudeQueryCopyAction(rawValue: sender.tag) else { return }
        SAClaudeQueryCopyAction.store(action, in: .standard)
        refreshState()
        perform(action)
    }

    /// Copies the selected rows, or every row when none are selected, in today's format for the action.
    private func perform(_ action: SAClaudeQueryCopyAction) {
        guard let table else { return }
        let onlySelected = table.numberOfSelectedRows > 0
        guard table.copyRows(forTag: action.tag, onlySelectedRows: onlySelected) else { NSSound.beep(); return }
        showCopied()
    }

    private func showCopied() {
        copiedReset?.cancel()
        isShowingCopied = true
        needsDisplay = true
        let reset = DispatchWorkItem { [weak self] in
            self?.isShowingCopied = false
            self?.needsDisplay = true
        }
        copiedReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedDuration, execute: reset)
    }

    // MARK: - Claude card

    /// The chevron's card; while it is shown the chevron draws open, as for the native menu.
    private func showCard() -> Bool {
        showSplitCard(adapter: SAClaudeCopyMenuAdapter.shared) { [weak self] open in
            guard let self else { return }
            self.isMenuOpen = open
            if !open { self.hoveredPart = self.partUnderMouse() }
        }
    }

    /// The chevron part opens the copy card; the main part copies (SPComboPopupButtonCell's tracking, unchanged).
    override func mouseDown(with event: NSEvent) {
        if isOnChevron(event), showCard() { return }
        super.mouseDown(with: event)
    }

    /// ↓ opens the copy card; Space/Return keep copying.
    override func keyDown(with event: NSEvent) {
        if Self.opensCard(event), showCard() { return }
        super.keyDown(with: event)
    }

    override func accessibilityPerformShowMenu() -> Bool {
        showCard() || super.accessibilityPerformShowMenu()
    }

    /// VoiceOver's press copies, as Space does (NSPopUpButton's own press would open the native menu).
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }

    // MARK: - Size

    /// Wide enough for the current action's label or "Copied", so the flash never moves the button.
    private var labelSlotWidth: CGFloat {
        let labels = [currentAction.shortLabel, SAClaudeQueryCopyAction.copiedLabel]
        return labels.map { ceil(($0 as NSString).size(withAttributes: [.font: Self.labelFont]).width) }.max() ?? 0
    }

    func preferredWidth(labelled: Bool) -> CGFloat {
        let chevron = CGFloat(lineOffset)
        let glyphPart = Self.leadingPadding + Self.glyphSize
        return labelled
            ? glyphPart + Self.glyphGap + labelSlotWidth + Self.trailingPadding + chevron
            : glyphPart + Self.leadingPadding + chevron
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth(labelled: showsLabel), height: SAClaudeEditorChrome.buttonHeight)
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ownTrackingArea { removeTrackingArea(ownTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        ownTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) { hoveredPart = part(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { hoveredPart = part(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hoveredPart = nil }

    private func part(at point: NSPoint) -> Part {
        point.x >= bounds.maxX - CGFloat(lineOffset) ? .chevron : .main
    }

    /// The part under the mouse right now, nil when it is outside the button.
    private func partUnderMouse() -> Part? {
        guard let window else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(point) ? part(at: point) : nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let palette else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.intersection(dirtyRect).clip()

        let chevronWidth = CGFloat(lineOffset)
        let mainRect = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width - chevronWidth, height: bounds.height)
        let chevronRect = NSRect(x: bounds.maxX - chevronWidth, y: bounds.minY, width: chevronWidth, height: bounds.height)
        let shape = NSBezierPath(roundedRect: bounds, xRadius: SAClaudeStyle.barButtonRadius, yRadius: SAClaudeStyle.barButtonRadius)
        palette.hover.setFill()
        shape.fill()
        if isEnabled {
            // Hover or press fills the main part; hover or an open menu fills the chevron part.
            let pressed = !isMenuOpen && (cell?.isHighlighted ?? false)
            let fillMain = pressed || (!isMenuOpen && hoveredPart == .main)
            let fillChevron = isMenuOpen || hoveredPart == .chevron
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            SAClaudeEditorChrome.derivedColour(text: palette.buttonText, background: palette.hover, ratio: 0.08).setFill()
            if fillMain { mainRect.fill() }
            if fillChevron { chevronRect.fill() }
            NSGraphicsContext.restoreGraphicsState()
        }
        palette.hairline.setFill()
        NSRect(x: chevronRect.minX - 0.5, y: bounds.minY + 6, width: 1, height: bounds.height - 12).fill()

        let mainAlpha: CGFloat = isEnabled && mainAvailable ? 1 : 0.4
        let glyphRect = NSRect(x: mainRect.minX + Self.leadingPadding, y: mainRect.midY - Self.glyphSize / 2,
                               width: Self.glyphSize, height: Self.glyphSize)
        if isShowingCopied {
            drawCheck(in: glyphRect, colour: palette.icon)
        } else {
            SAClaudeGlyphs.image(.copy, tint: palette.icon).draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: mainAlpha, respectFlipped: true, hints: nil)
        }
        if showsLabel {
            let label = (isShowingCopied ? SAClaudeQueryCopyAction.copiedLabel : currentAction.shortLabel) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.labelFont, .foregroundColor: palette.buttonText.withAlphaComponent(mainAlpha)]
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: glyphRect.maxX + Self.glyphGap, y: (mainRect.midY - size.height / 2).rounded()), withAttributes: attributes)
        }
        drawChevron(in: chevronRect, colour: palette.icon.withAlphaComponent(isEnabled ? 1 : 0.4))
    }

    private func drawCheck(in rect: NSRect, colour: NSColor) {
        let check = NSBezierPath()
        let up: CGFloat = isFlipped ? -1 : 1
        check.move(to: NSPoint(x: rect.minX + 3, y: rect.midY))
        check.line(to: NSPoint(x: rect.minX + 6.5, y: rect.midY - 3.5 * up))
        check.line(to: NSPoint(x: rect.maxX - 2.5, y: rect.midY + 4 * up))
        check.lineWidth = 1.6
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        colour.setStroke()
        check.stroke()
    }

    private func drawChevron(in rect: NSRect, colour: NSColor) {
        let chevron = NSBezierPath()
        let c = NSPoint(x: rect.midX, y: rect.midY)
        chevron.move(to: NSPoint(x: c.x - 3.5, y: c.y + (isFlipped ? -1.75 : 1.75)))
        chevron.line(to: NSPoint(x: c.x, y: c.y + (isFlipped ? 1.75 : -1.75)))
        chevron.line(to: NSPoint(x: c.x + 3.5, y: c.y + (isFlipped ? -1.75 : 1.75)))
        chevron.lineWidth = 1.5
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        colour.setStroke()
        chevron.stroke()
    }
}
