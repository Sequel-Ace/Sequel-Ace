//
//  SAClaudeSheetCells.swift
//  Sequel Ace
//
//  The cells, boxes and hover tracker the sheet styler (SAClaudeSheetStyler.swift)
//  installs on a sheet's own controls: bezel-less field cells that centre their
//  text in the XIB frame, a hairline separator, a titled box drawn as a card.
//  All are installed with `object_setClass` (no stored properties) and read
//  their colours at draw time. App target only.
//

import AppKit

// MARK: - Field cells

/// Where a bezel-less sheet field puts its text: inset from the rounded outline and centred on one line (a field
/// taller than two lines keeps its text at the top).
enum SheetFieldText {
    static let horizontalInset: CGFloat = 6
    static let multiLineTopInset: CGFloat = 3

    static func rect(_ rect: NSRect, font: NSFont?) -> NSRect {
        var text = rect.insetBy(dx: horizontalInset, dy: 0)
        let line = ceil(NSLayoutManager().defaultLineHeight(for: font ?? .systemFont(ofSize: NSFont.systemFontSize)))
        let spare = text.height - line
        if spare >= line {
            text = text.insetBy(dx: 0, dy: multiLineTopInset)
        } else if spare > 0 {
            text.origin.y += (spare / 2).rounded(.down)
            text.size.height = line
        }
        return text
    }
}

/// A plain sheet field's cell once its bezel is off (installed with `object_setClass`, no stored properties). Open for
/// `SAClaudeSheetPlaceholderFieldCell`.
@objc(SAClaudeSheetFieldCell) class SAClaudeSheetFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let drawingRect = super.drawingRect(forBounds: rect)
        return isBezeled || isBordered ? drawingRect : SheetFieldText.rect(drawingRect, font: font)
    }

    // AppKit places the field editor exactly where it is told to, not by -drawingRectForBounds:.
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

/// Draws the placeholder of a field whose placeholder must never read as a value: in the theme's muted colour (the sheet
/// palette's `muted`, as the sheets and the connection panel use), dimmed (more while disabled), where the value would be.
/// Shared by `SAClaudeSheetPlaceholderFieldCell` and the connection panel's field cell, so the rule lives in one place.
enum SAClaudeFieldPlaceholder {
    /// The placeholder: the muted colour at this alpha (dimmer than a value), and dimmer still while the field is disabled
    /// (dimmer than a disabled pop-up's value beside it).
    static let enabledAlpha: CGFloat = 0.7
    static let disabledAlpha: CGFloat = 0.3

    /// The placeholder `cell` shows now: its text while the field is empty - its value, or the field editor's text while
    /// it is being edited (AppKit keeps the placeholder up then, and would draw it as bright as a value) - else nil.
    static func shownText(of cell: NSTextFieldCell, in controlView: NSView) -> String? {
        let isEmpty = (controlView as? NSControl)?.currentEditor().map { $0.string.isEmpty } ?? cell.stringValue.isEmpty
        guard isEmpty else { return nil }
        let text = cell.placeholderString ?? cell.placeholderAttributedString?.string
        return text?.isEmpty == false ? text : nil
    }

    /// Draws `cell`'s placeholder when it shows one.
    ///
    /// - Returns: Whether it drew; when not, the cell draws its interior as usual.
    static func draw(_ cell: NSTextFieldCell, withFrame cellFrame: NSRect, in controlView: NSView) -> Bool {
        guard let text = shownText(of: cell, in: controlView) else { return false }
        let muted = SAClaudeSheetColours.current().muted
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = cell.alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let placeholder = NSAttributedString(string: text, attributes: [
            .font: cell.font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: muted.withAlphaComponent(cell.isEnabled ? enabledAlpha : disabledAlpha),
            .paragraphStyle: paragraph,
        ])
        // Where AppKit draws the value: the text container's 2pt padding inside the drawing rect.
        let rect = cell.drawingRect(forBounds: cellFrame).insetBy(dx: SAClaudeStyle.cellTextInset, dy: 0)
        placeholder.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        return true
    }
}

/// A sheet field whose placeholder must never read as a value (the Bundle Editor's Menu Label, Menu Category and Tooltip,
/// whose bindings set "optional" or the XIB's hint as the placeholder): while the field is empty it draws its placeholder
/// itself (`SAClaudeFieldPlaceholder`). Installed with `object_setClass` over an `SAClaudeSheetFieldCell` or a plain
/// NSTextFieldCell (no stored properties); the sheet skin takes it as one of its own.
@objc(SAClaudeSheetPlaceholderFieldCell) final class SAClaudeSheetPlaceholderFieldCell: SAClaudeSheetFieldCell {
    /// Swaps `field`'s cell for this one; false when it can't (another cell class, or observed by KVO).
    @discardableResult
    static func install(on field: NSTextField) -> Bool {
        guard let cell = field.cell else { return false }
        if cell is SAClaudeSheetPlaceholderFieldCell { return true }
        let cellClass: AnyClass = Swift.type(of: cell)
        guard cellClass == NSTextFieldCell.self || cellClass == SAClaudeSheetFieldCell.self, SAClaudeClassSwap.mayChangeClass(of: cell) else { return false }
        object_setClass(cell, SAClaudeSheetPlaceholderFieldCell.self)
        field.needsDisplay = true
        return true
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        if !SAClaudeFieldPlaceholder.draw(self, withFrame: cellFrame, in: controlView) {
            super.drawInterior(withFrame: cellFrame, in: controlView)
        }
    }
}

/// The token twin of `SAClaudeSheetFieldCell`: a bezel-less token field (the export dialog's custom filename) keeps its
/// text and tokens inset from the rounded outline and centred on one line, as every Claude field. Installed with
/// `object_setClass` (no stored properties).
@objc(SAClaudeSheetTokenFieldCell) final class SAClaudeSheetTokenFieldCell: NSTokenFieldCell {
    /// Swaps `field`'s cell for this one; false when it can't (another cell class, or observed by KVO).
    @discardableResult
    static func install(on field: NSTokenField) -> Bool {
        guard let cell = field.cell else { return false }
        if cell is SAClaudeSheetTokenFieldCell { return true }
        guard Swift.type(of: cell) == NSTokenFieldCell.self, SAClaudeClassSwap.mayChangeClass(of: cell) else { return false }
        object_setClass(cell, SAClaudeSheetTokenFieldCell.self)
        field.needsDisplay = true
        return true
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let drawingRect = super.drawingRect(forBounds: rect)
        return isBezeled || isBordered ? drawingRect : SheetFieldText.rect(drawingRect, font: font)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

/// The secure twin of `SAClaudeSheetFieldCell`.
@objc(SAClaudeSheetSecureFieldCell) final class SAClaudeSheetSecureFieldCell: NSSecureTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let drawingRect = super.drawingRect(forBounds: rect)
        return isBezeled || isBordered ? drawingRect : SheetFieldText.rect(drawingRect, font: font)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

/// The Claude search field cell (magnifier, text, cancel button laid out by the cell) with its text centred on
/// one line, as a sheet's search field keeps its XIB height.
@objc(SAClaudeSheetSearchFieldCell) final class SAClaudeSheetSearchFieldCell: SAClaudeSearchFieldCell {
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var text = super.searchTextRect(forBounds: rect)
        let line = ceil(NSLayoutManager().defaultLineHeight(for: font ?? .systemFont(ofSize: NSFont.systemFontSize)))
        let spare = text.height - line
        if spare > 0 {
            text.origin.y += (spare / 2).rounded(.down)
            text.size.height = line
        }
        return text
    }
}

/// What the Claude boxes share: hiding the views AppKit drew the box with before its class was swapped.
enum SAClaudeSheetBoxDrawing {
    /// Hides `box`'s own drawing views (macOS 26+: a SwiftUI box view drawing the native fill and border, and the text field
    /// showing its title), which stay after the swap until AppKit happens to rebuild the box and draw over the Claude box: a
    /// second title, offset from the Claude one. The box's content view is never touched. Called at every walk and layout.
    static func hideNativeDrawing(of box: NSBox) {
        let contentView = box.contentView
        for subview in box.subviews where !subview.isHidden {
            let field = subview as? NSTextField
            if SAClaudeNativeDrawingViews.isBoxDrawingView(className: String(describing: type(of: subview)), isContentView: subview === contentView,
                                                           isTextField: field != nil, text: field?.stringValue ?? "", boxTitle: box.title) {
                subview.isHidden = true
            }
        }
    }
}

/// A separator drawn as a 1pt hairline along its long axis (installed with `object_setClass`; AppKit's own drawing views
/// inside it are hidden, `SAClaudeSheetBoxDrawing`).
@objc(SAClaudeSheetSeparatorBox) final class SAClaudeSheetSeparatorBox: NSBox {
    override var wantsUpdateLayer: Bool { false }

    override func layout() {
        super.layout()
        SAClaudeSheetBoxDrawing.hideNativeDrawing(of: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let line = bounds.width >= bounds.height
            ? NSRect(x: bounds.minX, y: (bounds.midY - 0.5).rounded(.down), width: bounds.width, height: 1)
            : NSRect(x: (bounds.midX - 0.5).rounded(.down), y: bounds.minY, width: 1, height: bounds.height)
        SAClaudeFilterBarStyler.currentPalette.hairline.setFill()
        line.intersection(dirtyRect).fill()
    }
}

/// A titled box drawn as a Claude card (radius 9: the faint card fill and a hairline, as the Export sheet's cards) under its
/// title in SF Pro 11, muted, drawn once. Installed with `object_setClass`; NSBox keeps its border, title and content rects,
/// only the drawing is Claude's. AppKit's own box view and title field are hidden (`SAClaudeSheetBoxDrawing`). Where the
/// title sits on the card's edge, the outline leaves a gap for it rather than painting a colour behind it, so whatever the
/// box sits on (a sheet, a tab pane, a save panel's accessory) shows through.
@objc(SAClaudeSheetTitledBox) final class SAClaudeSheetTitledBox: NSBox {
    private static let radius: CGFloat = 9

    override var wantsUpdateLayer: Bool { false }

    override func layout() {
        super.layout()
        SAClaudeSheetBoxDrawing.hideNativeDrawing(of: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let palette = SAClaudeFilterBarStyler.currentPalette
        let card = NSBezierPath(roundedRect: borderRect.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius - 0.5, yRadius: Self.radius - 0.5)
        card.lineWidth = 1

        var title: NSAttributedString?
        var origin = NSPoint.zero
        var gap: NSRect?
        if titlePosition != .noTitle, !self.title.isEmpty {
            let string = NSAttributedString(string: self.title, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: palette.icon])
            let size = string.size()
            let titleArea = titleRect
            origin = NSPoint(x: titleArea.minX, y: (titleArea.midY - size.height / 2).rounded())
            gap = SAClaudeTitledBoxGeometry.titleGap(titleRect: titleArea, borderRect: borderRect, titleOriginX: origin.x, titleWidth: ceil(size.width))
            title = string
        }

        NSGraphicsContext.saveGraphicsState()
        if let gap {
            // Everything but the title's gap.
            let clip = NSBezierPath(rect: bounds)
            clip.append(NSBezierPath(rect: gap))
            clip.windingRule = .evenOdd
            clip.addClip()
        }
        // The card fill as a tint of the theme's text, so it reads the same on any background.
        SAClaudeFilterBarStyler.currentThemeText.withAlphaComponent(SAClaudeFilterChrome.cardFillRatio).setFill()
        card.fill()
        palette.hairline.setStroke()
        card.stroke()
        NSGraphicsContext.restoreGraphicsState()

        title?.draw(at: origin)
    }
}

// MARK: - Hover

/// Redraws a sheet's secondary button when the mouse enters or leaves it; the cell draws the hover fill itself
/// (inside its outline, which is smaller than a classic XIB frame). Retained by the button.
final class SAClaudeSheetHoverTracker: NSObject {
    private static var associationKey: UInt8 = 0
    private weak var view: NSView?

    static func attach(to view: NSView) {
        guard objc_getAssociatedObject(view, &associationKey) == nil else { return }
        let tracker = SAClaudeSheetHoverTracker()
        tracker.view = view
        view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                            owner: tracker, userInfo: nil))
        objc_setAssociatedObject(view, &associationKey, tracker, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    // The tracking area sends its owner `mouseEntered:` / `mouseExited:`; spelled out for a plain NSObject.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { view?.needsDisplay = true }
    @objc(mouseExited:) func mouseExited(with event: NSEvent) { view?.needsDisplay = true }
}
