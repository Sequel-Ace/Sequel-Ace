//
//  SAClaudeAlertCard.swift
//  Sequel Ace
//
//  The Claude alert card, laid out inside the NSAlert's own window: a flipped card view fills the alert's content
//  view (NSAlert's own views are hidden behind it), and the alert's buttons, suppression checkbox and accessory view
//  are re-parented into it at the frames `SAClaudeAlertLayout` gives. The new views are decoration only (the glyph
//  tile, the title / explanation labels and the "MySQL said" block), so return codes, the default and cancel
//  buttons, the suppression state and the accessory's own behaviour stay NSAlert's.
//
//  Replacing the window's content view is not an option: every `beginSheetModal` re-runs `-[NSAlert layout]`, which
//  installs constraints on the content view and throws if that is not its own. That re-layout also takes the buttons
//  back into NSAlert's stack view, moves the suppression checkbox and the accessory, un-hides some of its views and
//  resizes the window, so `verify()` re-installs the card right after the original `beginSheetModal` returns.
//  `runModal` never re-lays out; there `verify()` only re-applies.
//
//  App target only; AppKit, the alert pure files and the card views only.
//

import AppKit

final class SAClaudeAlertCard: NSObject {

    private static var cardKey: UInt8 = 0

    /// The generic window skin's surface view (`SAClaudeWindowSkin`): it stays visible below the card root.
    static let keptSurfaceIdentifier = NSUserInterfaceItemIdentifier("SAClaudeSheetSurface")

    /// The card installed on `alert`, if any.
    static func card(for alert: NSAlert) -> SAClaudeAlertCard? {
        objc_getAssociatedObject(alert, &cardKey) as? SAClaudeAlertCard
    }

    let root: SAClaudeAlertCardView
    let classification: SAClaudeAlertClassification
    var kind: SAClaudeAlertKind { classification.kind }

    let tile: SAClaudeAlertGlyphTile
    let textScrollView: NSScrollView
    let textDocument: SAClaudeAlertTextDocument
    let titleLabel: NSTextField
    /// nil when the alert has no explanation (or the whole message is the server's text).
    let messageLabel: NSTextField?
    /// nil when the message carries no server text.
    let serverBlock: SAClaudeAlertServerBlock?

    private weak var alert: NSAlert?
    private let buttons: [NSButton]
    private let suppression: NSButton?
    private let accessory: NSView?
    private let accessorySize: NSSize
    private let accessoryIsFlexible: Bool
    /// The window's `initialFirstResponder` before the card re-parented anything (a caller's choice, or NSAlert's own).
    private weak var savedInitialFirstResponder: NSView?

    private(set) var colours: SAClaudeAlertCardColours
    /// The frames last applied.
    private(set) var frames: SAClaudeAlertLayout.Frames?
    /// How many times `verify()` had to put the card back (expected once per `beginSheetModal`).
    private(set) var reinstallCount = 0
    private var gaveUp = false
    private var scrollerStyleObserver: NSObjectProtocol?

    private var controls: [NSView] {
        var views: [NSView] = buttons
        if let suppression { views.append(suppression) }
        if let accessory { views.append(accessory) }
        return views
    }

    // MARK: - Installing

    /// After `alert.layout()`. nil, and the alert untouched, when its structure isn't the expected one.
    static func install(on alert: NSAlert, classification: SAClaudeAlertClassification,
                        parts: SAClaudeAlertMessageParts, colours: SAClaudeAlertCardColours) -> SAClaudeAlertCard? {
        // 1. Check everything first; change nothing until the alert is known to be the expected one.
        guard card(for: alert) == nil else { return refuse("a card is already installed") }
        let window = alert.window
        guard let content = window.contentView else { return refuse("the alert window has no content view") }
        guard !content.subviews.contains(where: { $0 is SAClaudeAlertCardView }) else { return refuse("a card root is already installed") }
        let buttons = alert.buttons
        guard !buttons.isEmpty else { return refuse("the alert has no buttons after layout") }
        guard buttons.allSatisfy({ $0.isDescendant(of: content) }) else { return refuse("a button is not in the alert's content view") }
        var suppression: NSButton?
        if alert.showsSuppressionButton {
            guard let button = alert.suppressionButton, button.isDescendant(of: content) else {
                return refuse("the suppression checkbox is not in the alert's content view")
            }
            suppression = button
        }
        let accessory = alert.accessoryView
        if let accessory, !accessory.isDescendant(of: content) { return refuse("the accessory view is not in the alert's content view") }

        // 3 (measured before anything moves). An Auto Layout accessory (the bookmark list) has a zero frame.
        var accessorySize = accessory?.frame.size ?? .zero
        if let accessory, accessorySize.width == 0 || accessorySize.height == 0 { accessorySize = accessory.fittingSize }
        let flexible = accessory.map(isFlexible) ?? false

        // 2. The card's own views.
        let card = SAClaudeAlertCard(alert: alert, classification: classification, parts: parts, colours: colours,
                                     buttons: buttons, suppression: suppression, accessory: accessory,
                                     accessorySize: NSSize(width: ceil(accessorySize.width), height: ceil(accessorySize.height)),
                                     accessoryIsFlexible: flexible)
        // Re-parenting resets a caller's choice (D7): keep the exact value to put back.
        card.savedInitialFirstResponder = window.initialFirstResponder

        // 3. Re-parent the controls, 4. lay the card inside the existing content view, 5. apply and retain.
        card.reparentControls()
        card.installRoot(in: content)
        card.apply(colours: colours)
        card.restoreFocus()
        objc_setAssociatedObject(alert, &cardKey, card, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return card
    }

    private init(alert: NSAlert, classification: SAClaudeAlertClassification, parts: SAClaudeAlertMessageParts,
                 colours: SAClaudeAlertCardColours, buttons: [NSButton], suppression: NSButton?, accessory: NSView?,
                 accessorySize: NSSize, accessoryIsFlexible: Bool) {
        self.alert = alert
        self.classification = classification
        self.colours = colours
        self.buttons = buttons
        self.suppression = suppression
        self.accessory = accessory
        self.accessorySize = accessorySize
        self.accessoryIsFlexible = accessoryIsFlexible

        root = SAClaudeAlertCardView(frame: .zero)
        root.translatesAutoresizingMaskIntoConstraints = true

        tile = SAClaudeAlertGlyphTile(frame: .zero)

        textDocument = SAClaudeAlertTextDocument(frame: .zero)
        textScrollView = NSScrollView(frame: .zero)
        textScrollView.borderType = .noBorder
        textScrollView.drawsBackground = false
        textScrollView.hasHorizontalScroller = false
        textScrollView.hasVerticalScroller = false
        textScrollView.autohidesScrollers = true
        // The alert window's content runs under its (hidden) title bar: no automatic inset for it.
        textScrollView.automaticallyAdjustsContentInsets = false
        textScrollView.contentInsets = NSEdgeInsetsZero
        textScrollView.documentView = textDocument

        titleLabel = NSTextField(wrappingLabelWithString: alert.messageText)
        titleLabel.font = SAClaudeAlertChrome.titleFont
        titleLabel.isSelectable = false
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        textDocument.addSubview(titleLabel)

        if parts.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messageLabel = nil
        } else {
            let label = NSTextField(wrappingLabelWithString: parts.explanation)
            label.font = SAClaudeAlertChrome.messageFont
            label.isSelectable = true
            label.drawsBackground = false
            label.isBordered = false
            textDocument.addSubview(label)
            messageLabel = label
        }

        if let serverText = parts.serverText {
            let block = SAClaudeAlertServerBlock(frame: .zero)
            block.label.stringValue = NSLocalizedString("ClaudeAlertMySQLSaid", value: "MySQL said",
                                                        comment: "Claude alert card: label above the MySQL server's error text")
            block.text.stringValue = serverText
            textDocument.addSubview(block)
            serverBlock = block
        } else {
            serverBlock = nil
        }

        super.init()
        root.addSubview(tile)
        root.addSubview(textScrollView)
        // A legacy scroller narrows the text column: re-measure when the system's scroller style changes.
        scrollerStyleObserver = NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                                                                       object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.apply(colours: self.colours)
        }
    }

    deinit {
        if let scrollerStyleObserver { NotificationCenter.default.removeObserver(scrollerStyleObserver) }
    }

    /// Ruling 10: a scroll view, a width-sizable view, or a view wrapping one width-sizable scroll view that fills it
    /// (CHECK TABLE's results) spans the card; anything else keeps its own size.
    private static func isFlexible(_ accessory: NSView) -> Bool {
        if accessory is NSScrollView || accessory.autoresizingMask.contains(.width) { return true }
        if accessory.subviews.count == 1, let scrollView = accessory.subviews.first as? NSScrollView,
           scrollView.autoresizingMask.contains(.width), scrollView.frame == accessory.bounds {
            return true
        }
        return false
    }

    private static func refuse(_ reason: String) -> SAClaudeAlertCard? {
        #if DEBUG
        NSLog("SAClaudeAlertCard: %@; keeping the skinned alert", reason)
        #endif
        return nil
    }

    /// Moves every control NSAlert holds into the card root (out of NSAlert's stack views). The accessory keeps its
    /// internal constraints; its own frame is the card's.
    private func reparentControls() {
        for view in controls where view.superview !== root {
            if let stack = view.superview as? NSStackView { stack.removeArrangedSubview(view) }
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = true
            view.autoresizingMask = []
            root.addSubview(view)
        }
    }

    /// Lays the root over the whole content view (above the skin's surface) and hides NSAlert's own views.
    private func installRoot(in content: NSView) {
        if root.superview !== content {
            root.removeFromSuperview()
            content.addSubview(root, positioned: .above, relativeTo: nil)
        } else if content.subviews.last !== root {
            content.addSubview(root, positioned: .above, relativeTo: nil)
        }
        root.autoresizingMask = [.width, .height]
        if root.frame != content.bounds { root.frame = content.bounds }
        for view in content.subviews where isHiddenByCard(view) && !view.isHidden {
            view.isHidden = true
        }
    }

    /// NSAlert's own views of the content view: everything but the root and the skin's surface.
    private func isHiddenByCard(_ view: NSView) -> Bool {
        view !== root && view.identifier != Self.keptSurfaceIdentifier
    }

    /// The saved `initialFirstResponder` (exactly), unless that is nil or one of the alert's buttons (no caller
    /// choice): then the accessory's first editable text field, if any (ruling 12).
    private func restoreFocus() {
        guard let alert else { return }
        let window = alert.window
        var target = savedInitialFirstResponder
        if target == nil || buttons.contains(where: { $0 === target }), let field = Self.firstEditableField(in: accessory) {
            target = field
        }
        if window.initialFirstResponder !== target { window.initialFirstResponder = target }
    }

    private static func firstEditableField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable, !field.isHidden { return field }
        for subview in view.subviews {
            if let field = firstEditableField(in: subview) { return field }
        }
        return nil
    }

    // MARK: - Applying

    private static let buttonTitleFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    private func spec(for window: NSWindow) -> SAClaudeAlertLayout.Spec {
        let widths = buttons.map { button in
            SAClaudeAlertLayout.buttonWidth(titleWidth: NSAttributedString(string: button.title, attributes: [.font: Self.buttonTitleFont]).size().width)
        }
        let suppressionSize = suppression.map { button -> NSSize in
            let size = button.cell?.cellSize ?? button.fittingSize
            return NSSize(width: ceil(size.width), height: ceil(size.height))
        }
        let screen = window.screen ?? NSScreen.main
        let maximumHeight = screen.map { floor($0.visibleFrame.height * 2 / 3) } ?? .greatestFiniteMagnitude
        return SAClaudeAlertLayout.Spec(buttonWidths: widths, suppressionSize: suppressionSize,
                                        accessory: accessory.map { _ in SAClaudeAlertLayout.Accessory(size: accessorySize, flexibleWidth: accessoryIsFlexible) },
                                        maximumHeight: maximumHeight)
    }

    private static func height(of field: NSTextField, width: CGFloat) -> CGFloat {
        guard let cell = field.cell else { return 0 }
        return ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height)
    }

    private func textHeights(width: CGFloat) -> SAClaudeAlertLayout.TextHeights {
        SAClaudeAlertLayout.TextHeights(title: Self.height(of: titleLabel, width: width),
                                        message: messageLabel.map { Self.height(of: $0, width: width) } ?? 0,
                                        block: serverBlock?.height(blockWidth: width) ?? 0)
    }

    private static func place(_ view: NSView, _ frame: NSRect) {
        if view.frame != frame { view.frame = frame }
    }

    /// Re-measures, re-lays out and recolours the card (idempotent: a view moves only when its frame differs, the
    /// window resizes only when its size differs).
    func apply(colours: SAClaudeAlertCardColours) {
        self.colours = colours
        guard let alert, let content = alert.window.contentView else { return }
        let window = alert.window

        let spec = spec(for: window)
        let column = SAClaudeAlertLayout.textColumnWidth(cardWidth: SAClaudeAlertLayout.width(spec))
        var textWidth = column
        var frames = SAClaudeAlertLayout.frames(spec, text: textHeights(width: column))
        if textScrollView.hasVerticalScroller != frames.scrolls { textScrollView.hasVerticalScroller = frames.scrolls }
        // A scroll view not yet shown can still carry the default style; the shown one takes the system's.
        if textScrollView.scrollerStyle != NSScroller.preferredScrollerStyle { textScrollView.scrollerStyle = NSScroller.preferredScrollerStyle }
        if frames.scrolls {
            // A legacy (always shown) scroller takes its width from the text: measure again at what the clip view leaves.
            let clipWidth = NSScrollView.contentSize(forFrameSize: frames.textViewport.size, horizontalScrollerClass: nil,
                                                     verticalScrollerClass: NSScroller.self, borderType: .noBorder,
                                                     controlSize: .regular, scrollerStyle: textScrollView.scrollerStyle).width
            if clipWidth > 0, clipWidth < column {
                textWidth = clipWidth
                frames = SAClaudeAlertLayout.frames(spec, text: textHeights(width: textWidth))
            }
        }
        self.frames = frames

        if content.frame.size != frames.size { window.setContentSize(frames.size) }
        if root.frame != content.bounds { root.frame = content.bounds }

        Self.place(tile, frames.tile)
        Self.place(textScrollView, frames.textViewport)
        Self.place(textDocument, NSRect(x: 0, y: 0, width: textWidth, height: frames.textDocumentHeight))
        Self.place(titleLabel, NSRect(x: frames.title.minX, y: frames.title.minY, width: textWidth, height: frames.title.height))
        if let messageLabel, let rect = frames.message {
            Self.place(messageLabel, NSRect(x: rect.minX, y: rect.minY, width: textWidth, height: rect.height))
        }
        if let serverBlock, let rect = frames.block {
            Self.place(serverBlock, NSRect(x: rect.minX, y: rect.minY, width: textWidth, height: rect.height))
            serverBlock.layoutContent()
        }
        if let accessory, let rect = frames.accessory { Self.place(accessory, rect) }
        if let suppression, let rect = frames.suppression { Self.place(suppression, rect) }
        for (button, rect) in zip(buttons, frames.buttons) { Self.place(button, rect) }

        window.recalculateKeyViewLoop()

        root.colours = colours
        tile.update(kind: kind, colours: colours)
        if titleLabel.textColor != colours.text { titleLabel.textColor = colours.text }
        if let messageLabel, messageLabel.textColor != colours.secondaryText { messageLabel.textColor = colours.secondaryText }
        serverBlock?.update(colours: colours)
    }

    // MARK: - Verifying

    /// Whether the card is still in place: the root in the content view, every control in the root, NSAlert's own
    /// views hidden. (Frames and the window size are re-set by `apply` either way.)
    private var isInstalled: Bool {
        guard let alert, let content = alert.window.contentView, root.superview === content else { return false }
        guard controls.allSatisfy({ $0.superview === root }) else { return false }
        return !content.subviews.contains { isHiddenByCard($0) && !$0.isHidden }
    }

    /// Puts the card back if AppKit replaced the content or moved the alert's controls; false = gave up (today's skin).
    @discardableResult
    func verify() -> Bool {
        guard !gaveUp, let alert else { return false }
        if isInstalled {
            apply(colours: colours)
            return true
        }
        // A sheet's re-layout (expected once per beginSheetModal): re-parent, re-hide, re-size, re-focus.
        if let content = alert.window.contentView {
            reparentControls()
            installRoot(in: content)
            apply(colours: colours)
            restoreFocus()
        }
        if isInstalled {
            reinstallCount += 1
            return true
        }
        gaveUp = true
        #if DEBUG
        NSLog("SAClaudeAlertCard: could not put the card back on \"%@\"; leaving the alert as it is", alert.messageText)
        #endif
        return false
    }
}
