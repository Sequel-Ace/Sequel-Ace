//
//  SAClaudeExportFilenamePopover.swift
//  Sequel Ace
//
//  The Export sheet's "Customise" popover: the controller's own custom filename view (hint, token field, token
//  pool) re-parented into a transient popover under the Save to card's Customise button, in the Claude look. The
//  controller keeps driving the token fields (delegate, drag and drop, the synthesised Return that tokenises typed
//  `{tokens}`, which it posts to the field's own window). The native token pool is hidden (kept: the controller's
//  source of the available tokens) and shown as Claude outline chips that add a token on click or drag it into the
//  field. Owned by `SAClaudeExportStyler`. App target only.
//

import AppKit

final class SAClaudeExportFilenamePopover: NSObject, NSPopoverDelegate {

    private static let width: CGFloat = 520
    private static let padding: CGFloat = 12
    /// From the field to the chips.
    private static let chipsGap: CGFloat = 12
    private static let fieldHeight: CGFloat = 22
    private static let hintHeight: CGFloat = 14
    private static let hintGap: CGFloat = 6
    private static let fieldRadius: CGFloat = 7
    private static let poolRadius: CGFloat = 9
    private static let hintFont = NSFont.systemFont(ofSize: 11)

    private struct Colours {
        let isDark: Bool
        let surface: NSColor
        let fieldFill: NSColor
        let hairline: NSColor
        let muted: NSColor
        let text: NSColor
        /// A chip's outline under the pointer: a touch stronger than the hairline.
        let hoverStroke: NSColor

        var chip: SAClaudeExportTokenChip.Colours {
            SAClaudeExportTokenChip.Colours(stroke: hairline, hoverStroke: hoverStroke, text: text, muted: muted)
        }
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
    private let chipsView = SAClaudeExportTokenChipsView()
    /// The token ids the chips show, in order (rebuilt only when the pool's tokens change).
    private var chipTokenIds: [String] = []
    /// After a chip changed the token field programmatically (no text notification): the controller updates its
    /// filename preview, as it does after its own programmatic changes.
    var onFieldChanged: (() -> Void)?
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
        refreshTokens()
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
        rebuildChips()
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
        if usesChips, let poolBox, let outerContent = outerBox?.contentView {
            // The pool stays alive and filled by the controller, out of sight; its tokens show as chips.
            poolBox.isHidden = true
            outerContent.addSubview(chipsView)
            hintLabel?.stringValue = NSLocalizedString("ClaudeExportTokenHint", value: "Click a token to add it, or drag it into the field.",
                                                       comment: "export dialog: hint above the custom filename field in the Customise popover")
        } else if let poolBox {
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

    /// Whether the pool is shown as chips (the XIB's boxes and hint were found; otherwise the view keeps its XIB layout).
    private var usesChips: Bool {
        outerBox?.contentView != nil && poolBox?.contentView != nil && hintLabel != nil
    }

    /// Hint, field and the chips top to bottom, 12pt in from the popover's edges; the popover is as tall as the
    /// chips need (they wrap onto as many rows as the width takes).
    private func layOut() {
        guard usesChips, let outerBox, let hintLabel, let outerContent = outerBox.contentView,
              let content = popover?.contentViewController?.view else { return }
        let innerWidth = Self.width - 2 * Self.padding
        let chipsHeight = chipsView.height(forWidth: innerWidth)
        let height = Self.padding + Self.hintHeight + Self.hintGap + Self.fieldHeight + (chipsHeight > 0 ? Self.chipsGap + chipsHeight : 0) + Self.padding
        let size = NSSize(width: Self.width, height: height)
        // The custom view and the surface follow the content view (width + height sizable).
        if content.frame.size != size { content.setFrameSize(size) }
        if let popover, popover.contentSize != size { popover.contentSize = size }

        Self.place(outerBox, customView.bounds)
        Self.place(outerContent, outerBox.bounds)
        let inner = outerContent.bounds.insetBy(dx: Self.padding, dy: Self.padding)
        let hint = NSRect(x: inner.minX, y: inner.maxY - Self.hintHeight, width: inner.width, height: Self.hintHeight)
        let field = NSRect(x: inner.minX, y: hint.minY - Self.hintGap - Self.fieldHeight, width: inner.width, height: Self.fieldHeight)
        Self.place(hintLabel, hint)
        Self.place(tokenField, field)
        Self.place(chipsView, NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: chipsHeight))
        chipsView.layOutChips()
    }

    // MARK: - Token chips

    /// Rebuilds the chips when the controller changed the available tokens (e.g. "Table" removed) and re-fits the
    /// popover. Cheap when nothing changed; called on show and whenever the controller updates the filename.
    func refreshTokens() {
        guard popover != nil, usesChips else { return }
        if rebuildChips() { layOut() }
    }

    /// The pool's tokens (`SPExportFileNameTokenObject`s), as the controller last set them.
    private var poolTokens: [(object: NSObject, id: String)] {
        (tokenPool.objectValue as? [Any] ?? []).compactMap { item in
            guard let object = item as? NSObject, object.responds(to: NSSelectorFromString("tokenId")),
                  let id = object.value(forKey: "tokenId") as? String else { return nil }
            return (object, id)
        }
    }

    /// True when the chips changed.
    @discardableResult
    private func rebuildChips() -> Bool {
        guard usesChips else { return false }
        let tokens = poolTokens
        guard tokens.map(\.id) != chipTokenIds else { return false }
        chipTokenIds = tokens.map(\.id)
        let delegate = tokenPool.delegate
        let chipColours = colours?.chip ?? SAClaudeExportTokenChip.Colours(stroke: .separatorColor, hoverStroke: .tertiaryLabelColor,
                                                                             text: .labelColor, muted: .secondaryLabelColor)
        chipsView.setChips(tokens.map { token in
            // The name the native pool showed (the controller's localized token name).
            let title = delegate?.tokenField?(tokenPool, displayStringForRepresentedObject: token.object) ?? token.id
            let chip = SAClaudeExportTokenChip(tokenId: token.id, title: title, colours: chipColours)
            chip.onClick = { [weak self] in self?.add(token.object) }
            return chip
        })
        return true
    }

    /// Appends `token` (the pool's token object; its id never changes) to the filename field, then puts the caret
    /// after it and lets the controller update its preview.
    private func add(_ token: NSObject) {
        guard let window = tokenField.window else { return }
        // Commit any text being typed first (the field tokenises it on ending editing).
        if tokenField.currentEditor() != nil { window.makeFirstResponder(nil) }
        var parts: [Any]
        if let array = tokenField.objectValue as? [Any] {
            parts = array
        } else if let text = tokenField.objectValue as? String, !text.isEmpty {
            parts = [text]
        } else {
            parts = []
        }
        parts.append(token)
        tokenField.objectValue = parts
        onFieldChanged?()
        window.makeFirstResponder(tokenField)
        if let editor = tokenField.currentEditor() {
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }
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
                              hairline: palette.hairline, muted: palette.icon, text: theme.text,
                              hoverStroke: SAClaudeEditorChrome.derivedColour(text: theme.text, background: surface, ratio: 0.22))
        }
        applyColours()
    }

    private func applyColours() {
        guard let popover, let colours else { return }
        let appearanceName: NSAppearance.Name = colours.isDark ? .darkAqua : .aqua
        if popover.appearance?.name != appearanceName { popover.appearance = NSAppearance(named: appearanceName) }
        surface.fillColour = colours.surface
        for chip in chipsView.chips { chip.colours = colours.chip }
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
