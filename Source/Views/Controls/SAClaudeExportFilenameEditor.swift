//
//  SAClaudeExportFilenameEditor.swift
//  Sequel Ace
//
//  The Export sheet's "Customise" filename editor: the controller's own custom filename view (hint, token field,
//  token pool) re-parented into a small key-capable child panel of the export sheet, under the Save to card's
//  Customise button, in the Claude look. The controller keeps driving the token fields (delegate, drag and drop, the
//  synthesised Return that tokenises typed `{tokens}`, which it posts to the field's own window). The native token
//  pool is hidden (kept: the controller's source of the available tokens) and shown as Claude outline chips that add
//  a token on click or drag it into the field. Owned by `SAClaudeExportStyler`. App target only.
//
//  A panel, not an NSPopover: a popover over a sheet runs in AppKit's "deferred mode", where the popover's field
//  editor is reported as first responder of both windows, and closing it made the sheet resign a field editor it
//  does not own (NSInternalInconsistencyException). The panel is an ordinary key window: the sheet resigns key when
//  the panel becomes key, and the field editor only ever belongs to the panel.
//

import AppKit

/// The editor's window: borderless, key-capable (the token field edits in it), never main. Esc closes it.
final class SAClaudeExportFilenamePanel: NSPanel {
    /// Esc (when no field editor consumed it) — the editor closes.
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

final class SAClaudeExportFilenameEditor: NSObject {

    private static let width: CGFloat = 520
    private static let padding: CGFloat = 12
    /// From the field to the chips.
    private static let chipsGap: CGFloat = 12
    private static let fieldHeight: CGFloat = 22
    private static let hintHeight: CGFloat = 14
    private static let hintGap: CGFloat = 6
    private static let fieldRadius: CGFloat = 7
    private static let poolRadius: CGFloat = 9
    private static let cardRadius: CGFloat = 12
    /// From the Customise button to the panel's top (or bottom, when shown above it).
    private static let anchorGap: CGFloat = 6
    private static let hintFont = NSFont.systemFont(ofSize: 11)
    private static let escapeKeyCode: UInt16 = 53

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
    /// then keeps its XIB layout inside the panel).
    private let outerBox: NSBox?
    private let poolBox: NSBox?
    private let hintLabel: NSTextField?

    private var panel: SAClaudeExportFilenamePanel?
    /// The panel's rounded card: the surface fill and hairline behind the custom view (it takes no clicks).
    private let card = SAClaudeTableInfoCardView()
    private let chipsView = SAClaudeExportTokenChipsView()
    /// The token ids the chips show, in order (rebuilt only when the pool's tokens change).
    private var chipTokenIds: [String] = []
    /// After a chip changed the token field programmatically (no text notification): the controller updates its
    /// filename preview, as it does after its own programmatic changes.
    var onFieldChanged: (() -> Void)?
    private var colours: Colours?

    private weak var anchor: NSButton?
    private weak var exportWindow: NSWindow?
    private var eventMonitor: Any?
    private var sheetEndObserver: NSObjectProtocol?
    private var resignKeyObserver: NSObjectProtocol?

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
        removeObservers()
    }

    // MARK: - Showing and closing

    var isShown: Bool { panel?.isVisible ?? false }

    /// Shows the editor under `button`, or closes it when shown.
    func toggle(relativeTo button: NSButton) {
        if isShown {
            close()
            return
        }
        guard let window = button.window else { return }
        anchor = button
        exportWindow = window
        let panel = self.panel ?? install()
        customView.isHidden = false
        refreshTokens()
        applyColours()
        panel.level = window.level
        position(panel)
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(tokenField)
        observe(window)
    }

    /// The one way the editor closes: the field's typed text is kept, its editing ends inside the panel's own
    /// window, and the export sheet takes key again (unless another window took it: `restoreKey` false).
    func close(restoreKey: Bool = true) {
        removeObservers()
        guard let panel, panel.isVisible else { return }
        tokenField.validateEditing()
        panel.makeFirstResponder(nil)
        exportWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
        if restoreKey, let exportWindow, exportWindow.isVisible { exportWindow.makeKey() }
    }

    /// Its top 6pt under the Customise button, centred on it, inside the export sheet's frame horizontally; above
    /// the button when there is no room below it in the sheet.
    private func position(_ panel: NSPanel) {
        guard let anchor, let window = exportWindow else { return }
        let size = panel.frame.size
        let button = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let sheet = window.frame
        let x = min(max(button.midX - size.width / 2, sheet.minX), max(sheet.minX, sheet.maxX - size.width))
        var y = button.minY - Self.anchorGap - size.height
        if y < sheet.minY { y = button.maxY + Self.anchorGap }
        let origin = NSPoint(x: x.rounded(), y: y.rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    private func observe(_ window: NSWindow) {
        removeObservers()
        // A click anywhere else in the app closes the editor; the click itself goes on as usual. A click on Customise
        // is left to its own toggle (closing here would let the button reopen it).
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            if event.type == .keyDown {
                // Esc while the token field edits: its field editor would take it (`complete:`), so catch it here.
                guard event.window === panel, event.keyCode == Self.escapeKeyCode,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
                self.close()
                return nil
            }
            if event.window === panel { return event }
            if let anchor = self.anchor, event.window === anchor.window,
               anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) { return event }
            self.close()
            return event
        }
        // `closeSheet:` hides the custom view and ends the sheet: the editor goes with it.
        if let parent = window.sheetParent {
            sheetEndObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: parent, queue: nil) { [weak self] _ in
                DispatchQueue.main.async { self?.close() }
            }
        }
        // Key went to another window (not by a click in this app, which the monitor handles): close, leaving it there.
        if let panel {
            resignKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: nil) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, let panel = self.panel, panel.isVisible, !panel.isKeyWindow else { return }
                    self.close(restoreKey: false)
                }
            }
        }
    }

    private func removeObservers() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        if let sheetEndObserver { NotificationCenter.default.removeObserver(sheetEndObserver) }
        sheetEndObserver = nil
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
        resignKeyObserver = nil
    }

    /// The panel and its view, once: the custom view moves into it for the life of the dialog.
    private func install() -> SAClaudeExportFilenamePanel {
        let size = NSSize(width: Self.width, height: customView.frame.height)
        let panel = SAClaudeExportFilenamePanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.close() }

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        card.radius = Self.cardRadius
        card.frame = content.bounds
        card.autoresizingMask = [.width, .height]
        content.addSubview(card)
        customView.removeFromSuperview()
        content.addSubview(customView)
        customView.frame = content.bounds
        customView.autoresizingMask = [.width, .height]
        panel.contentView = content
        self.panel = panel

        restyle()
        rebuildChips()
        layOut()
        applyColours()
        return panel
    }

    // MARK: - Look

    /// The outer line box disappears (its content stays); the pool becomes chips (or, without them, a rounded hairline
    /// well); the editable token field gets the Claude field look on its layer (the sheet skin does not walk the panel).
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
        // Text and tokens inset from the outline and centred on one line, as the other Claude fields.
        SAClaudeSheetTokenFieldCell.install(on: tokenField)
        tokenPool.drawsBackground = false
    }

    /// Whether the pool is shown as chips (the XIB's boxes and hint were found; otherwise the view keeps its XIB layout).
    private var usesChips: Bool {
        outerBox?.contentView != nil && poolBox?.contentView != nil && hintLabel != nil
    }

    /// Hint, field and the chips top to bottom, 12pt in from the panel's edges; the panel is as tall as the chips
    /// need (they wrap onto as many rows as the width takes), its top edge kept while shown.
    private func layOut() {
        guard usesChips, let outerBox, let hintLabel, let outerContent = outerBox.contentView, let panel else { return }
        let innerWidth = Self.width - 2 * Self.padding
        let chipsHeight = chipsView.height(forWidth: innerWidth)
        let height = Self.padding + Self.hintHeight + Self.hintGap + Self.fieldHeight + (chipsHeight > 0 ? Self.chipsGap + chipsHeight : 0) + Self.padding
        let size = NSSize(width: Self.width, height: height)
        if panel.frame.size != size {
            // The card and the custom view follow the content view (width + height sizable).
            let top = panel.frame.maxY
            panel.setContentSize(size)
            if panel.isVisible { position(panel) } else { panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - size.height)) }
        }

        Self.place(outerBox, customView.bounds)
        Self.place(outerContent, outerBox.bounds)
        let inner = outerContent.bounds.insetBy(dx: Self.padding, dy: Self.padding)
        let hint = NSRect(x: inner.minX, y: inner.maxY - Self.hintHeight, width: inner.width, height: Self.hintHeight)
        let field = NSRect(x: inner.minX, y: hint.minY - Self.hintGap - Self.fieldHeight, width: inner.width, height: Self.fieldHeight)
        Self.place(hintLabel, hint)
        Self.place(tokenField, field)
        Self.place(chipsView, NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: chipsHeight))
        chipsView.layOutChips()
        panel.invalidateShadow()
    }

    // MARK: - Token chips

    /// Rebuilds the chips when the controller changed the available tokens (e.g. "Table" removed) and re-fits the
    /// panel. Cheap when nothing changed; called on show and whenever the controller updates the filename.
    func refreshTokens() {
        guard panel != nil, usesChips else { return }
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
        // Commit any text being typed first (the field tokenises it on ending editing), inside the panel's own window.
        tokenField.validateEditing()
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

    // MARK: - Colours

    /// Re-derives the colours from the editor theme under `appearance` (the export window's) and recolours the
    /// panel once it exists.
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
        guard let panel, let colours else { return }
        let appearanceName: NSAppearance.Name = colours.isDark ? .darkAqua : .aqua
        if panel.appearance?.name != appearanceName { panel.appearance = NSAppearance(named: appearanceName) }
        card.fill = colours.surface
        card.stroke = colours.hairline
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
        panel.invalidateShadow()
    }
}
