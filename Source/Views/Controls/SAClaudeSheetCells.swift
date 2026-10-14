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
private enum SheetFieldText {
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

/// A plain sheet field's cell once its bezel is off (installed with `object_setClass`, no stored properties).
@objc(SAClaudeSheetFieldCell) final class SAClaudeSheetFieldCell: NSTextFieldCell {
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

/// A separator drawn as a 1pt hairline along its long axis (installed with `object_setClass`; on macOS 26 and
/// later this also drops the private view NSBox draws its line with).
@objc(SAClaudeSheetSeparatorBox) final class SAClaudeSheetSeparatorBox: NSBox {
    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let line = bounds.width >= bounds.height
            ? NSRect(x: bounds.minX, y: (bounds.midY - 0.5).rounded(.down), width: bounds.width, height: 1)
            : NSRect(x: (bounds.midX - 0.5).rounded(.down), y: bounds.minY, width: 1, height: bounds.height)
        SAClaudeFilterBarStyler.currentPalette.hairline.setFill()
        line.intersection(dirtyRect).fill()
    }
}

/// A titled box drawn as a hairline card (radius 9) under its title in SF Pro 11, muted. Installed with
/// `object_setClass`; NSBox keeps its border, title and content rects, only the drawing is Claude's.
@objc(SAClaudeSheetTitledBox) final class SAClaudeSheetTitledBox: NSBox {
    private static let radius: CGFloat = 9

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let palette = SAClaudeFilterBarStyler.currentPalette
        let card = NSBezierPath(roundedRect: borderRect.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius - 0.5, yRadius: Self.radius - 0.5)
        card.lineWidth = 1
        palette.hairline.setStroke()
        card.stroke()

        guard titlePosition != .noTitle, !title.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: palette.icon]
        let string = NSAttributedString(string: title, attributes: attributes)
        let size = string.size()
        let titleArea = titleRect
        let origin = NSPoint(x: titleArea.minX, y: (titleArea.midY - size.height / 2).rounded())
        // The title sits on the card's top edge: clear the line behind it with the theme surface the box sits on
        // (in a save panel's accessory too, where the panel's own background differs).
        if titleArea.intersects(borderRect) {
            SAClaudeSheetColours.currentSurface.setFill()
            NSRect(x: origin.x - 3, y: titleArea.minY, width: size.width + 6, height: titleArea.height).fill()
        }
        string.draw(at: origin)
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
