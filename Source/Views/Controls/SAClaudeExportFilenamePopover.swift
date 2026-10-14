//
//  SAClaudeExportFilenamePopover.swift
//  Sequel Ace
//
//  The Export sheet's "Customise" popover: the controller's own custom filename view (hint, token field, token
//  pool) re-parented into a transient popover under the Save to card's Customise button, in the Claude look. The
//  controller keeps driving the token fields (delegate, drag and drop, the synthesised Return that tokenises typed
//  `{tokens}`, which it posts to the field's own window). Owned by `SAClaudeExportStyler`. App target only.
//

import AppKit

final class SAClaudeExportFilenamePopover: NSObject, NSPopoverDelegate {

    private static let width: CGFloat = 520
    private static let padding: CGFloat = 12
    private static let poolHeight: CGFloat = 32
    private static let fieldHeight: CGFloat = 22
    private static let hintHeight: CGFloat = 14
    private static let poolGap: CGFloat = 10
    private static let hintGap: CGFloat = 6
    private static let poolInset: CGFloat = 8
    private static let fieldRadius: CGFloat = 7
    private static let poolRadius: CGFloat = 9
    private static let hintFont = NSFont.systemFont(ofSize: 11)

    private struct Colours {
        let isDark: Bool
        let surface: NSColor
        let fieldFill: NSColor
        let hairline: NSColor
        let muted: NSColor
    }

    private let customView: NSView
    private let tokenField: NSTokenField
    private let tokenPool: NSTokenField
    /// The XIB's box around everything, the pool's box and the hint above the field; nil when not found (the view
    /// then keeps its XIB layout inside the popover).
    private let outerBox: NSBox?
    private let poolBox: NSBox?
    private let hintLabel: NSTextField?

    private var popover: NSPopover?
    private let surface = SAClaudeEditorBarBackgroundView()
    private var colours: Colours?
    private var sheetEndObserver: NSObjectProtocol?
    private weak var anchor: NSButton?
    /// The click on the Customise button that closed the (transient) popover: its button action must not reopen it.
    private var closingClick: Int?

    init(customView: NSView, tokenField: NSTokenField, tokenPool: NSTokenField) {
        self.customView = customView
        self.tokenField = tokenField
        self.tokenPool = tokenPool
        let outer = customView.subviews.first(where: { $0 is NSBox }) as? NSBox
        let pool = tokenPool.superview?.superview as? NSBox
        outerBox = outer
        poolBox = pool
        hintLabel = outer?.contentView?.subviews.first(where: {
            guard let label = $0 as? NSTextField else { return false }
            return !(label is NSTokenField) && !label.isEditable
        }) as? NSTextField
        super.init()
    }

    deinit {
        if let sheetEndObserver { NotificationCenter.default.removeObserver(sheetEndObserver) }
    }

    // MARK: - Showing

    /// Shows the popover under `button`, or closes it when shown.
    func toggle(relativeTo button: NSButton) {
        // A mouse-up shares its mouse-down's event number.
        let closedByThisClick = closingClick != nil && NSApp.currentEvent?.type == .leftMouseUp && NSApp.currentEvent?.eventNumber == closingClick
        closingClick = nil
        if closedByThisClick { return }
        if let popover, popover.isShown {
            close()
            return
        }
        anchor = button
        let popover = self.popover ?? install()
        customView.isHidden = false
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = tokenField.window {
            window.makeFirstResponder(tokenField)
            if !window.isKeyWindow { window.makeKey() }
        }
        observeSheetEnd(of: button.window)
    }

    func close() {
        guard let popover, popover.isShown else { return }
        popover.close()
    }

    func popoverWillClose(_ notification: Notification) {
        closingClick = nil
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown, let anchor, event.window === anchor.window,
              anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) else { return }
        closingClick = event.eventNumber
    }

    /// `closeSheet:` hides the custom view and ends the sheet: the popover goes with it.
    private func observeSheetEnd(of exportWindow: NSWindow?) {
        if let sheetEndObserver { NotificationCenter.default.removeObserver(sheetEndObserver) }
        sheetEndObserver = nil
        guard let parent = exportWindow?.sheetParent else { return }
        sheetEndObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: parent, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { self?.close() }
        }
    }

    /// The popover and its view, once: the custom view moves into it for the life of the dialog.
    private func install() -> NSPopover {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: customView.frame.height))
        surface.frame = content.bounds
        surface.autoresizingMask = [.width, .height]
        content.addSubview(surface)
        customView.removeFromSuperview()
        content.addSubview(customView)
        customView.frame = content.bounds
        customView.autoresizingMask = [.width, .height]

        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = controller
        popover.delegate = self
        popover.contentSize = content.frame.size
        self.popover = popover

        restyle()
        layOut()
        applyColours()
        return popover
    }

    // MARK: - Look

    /// The outer line box disappears (its content stays); the pool becomes a rounded hairline well; the editable
    /// token field gets the Claude field look on its layer (the sheet skin does not walk the popover's window).
    private func restyle() {
        if let outerBox {
            outerBox.boxType = .custom
            outerBox.borderWidth = 0
            outerBox.isTransparent = true
            outerBox.contentViewMargins = .zero
        }
        if let poolBox {
            poolBox.boxType = .custom
            poolBox.borderWidth = 1
            poolBox.cornerRadius = Self.poolRadius
            poolBox.contentViewMargins = .zero
        }
        hintLabel?.font = Self.hintFont
        tokenField.isBezeled = false
        tokenField.isBordered = false
        tokenField.drawsBackground = false
        tokenField.focusRingType = .none
        tokenField.wantsLayer = true
        tokenField.layer?.cornerRadius = Self.fieldRadius
        tokenField.layer?.borderWidth = 1
        tokenPool.drawsBackground = false
    }

    /// Hint, field and pool top to bottom, 12pt in from the popover's edges.
    private func layOut() {
        guard let outerBox, let poolBox, let hintLabel, let outerContent = outerBox.contentView,
              let poolContent = poolBox.contentView else { return }
        Self.place(outerBox, customView.bounds)
        Self.place(outerContent, outerBox.bounds)
        let inner = outerContent.bounds.insetBy(dx: Self.padding, dy: Self.padding)
        let pool = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: Self.poolHeight)
        let field = NSRect(x: inner.minX, y: pool.maxY + Self.poolGap, width: inner.width, height: Self.fieldHeight)
        Self.place(poolBox, pool)
        Self.place(tokenField, field)
        Self.place(hintLabel, NSRect(x: inner.minX, y: field.maxY + Self.hintGap, width: inner.width, height: Self.hintHeight))
        Self.place(poolContent, poolBox.bounds.insetBy(dx: poolBox.borderWidth, dy: poolBox.borderWidth))
        let poolBounds = poolContent.bounds
        Self.place(tokenPool, NSRect(x: Self.poolInset, y: ((poolBounds.height - Self.fieldHeight) / 2).rounded(.down),
                                     width: max(0, poolBounds.width - 2 * Self.poolInset), height: Self.fieldHeight))
    }

    private static func place(_ view: NSView, _ frame: NSRect) {
        if view.frame != frame { view.frame = frame }
        if !view.autoresizingMask.isEmpty { view.autoresizingMask = [] }
    }

    /// Re-derives the colours from the editor theme under `appearance` (the export window's) and recolours the
    /// popover once it exists.
    func recolour(in appearance: NSAppearance) {
        appearance.performAsCurrentDrawingAppearance {
            let theme = SAClaudeThemeColours.from(defaults: .standard)
            let palette = SAClaudeEditorChrome.palette(from: .standard)
            let surface = SAClaudeStatusChrome.popupSurface(theme: theme)
            colours = Colours(isDark: SAClaudeGridChrome.isDark(theme.background), surface: surface,
                              fieldFill: SAClaudeFilterChrome.fieldFill(text: theme.text, background: surface),
                              hairline: palette.hairline, muted: palette.icon)
        }
        applyColours()
    }

    private func applyColours() {
        guard let popover, let colours else { return }
        let appearanceName: NSAppearance.Name = colours.isDark ? .darkAqua : .aqua
        if popover.appearance?.name != appearanceName { popover.appearance = NSAppearance(named: appearanceName) }
        surface.fillColour = colours.surface
        if let poolBox {
            poolBox.borderColor = colours.hairline
            poolBox.fillColor = colours.fieldFill
        }
        if let hintLabel, hintLabel.textColor != colours.muted { hintLabel.textColor = colours.muted }
        (NSAppearance(named: appearanceName) ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            tokenField.layer?.backgroundColor = colours.fieldFill.cgColor
            tokenField.layer?.borderColor = colours.hairline.cgColor
        }
        tokenField.needsDisplay = true
    }
}
