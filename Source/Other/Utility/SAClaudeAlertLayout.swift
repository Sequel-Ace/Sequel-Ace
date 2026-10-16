import AppKit

/// Pure geometry for the Claude alert card. Coordinates are top-down (the card view and the text document are flipped).
/// Nothing here touches views: the same inputs always give the same frames, so the card can recompute and re-apply at any time.
enum SAClaudeAlertLayout {
    static let baseWidth: CGFloat = 420, margin: CGFloat = 20, tileSize: CGFloat = 32, tileTextGap: CGFloat = 12
    static let textColumnX: CGFloat = 64
    static let titleTopInset: CGFloat = 7, titleMessageGap: CGFloat = 4, blockGap: CGFloat = 10
    static let blockPaddingX: CGFloat = 10, blockPaddingY: CGFloat = 8, blockLabelGap: CGFloat = 4
    static let accessoryGap: CGFloat = 12, footerGap: CGFloat = 16
    static let buttonHeight: CGFloat = 28, buttonGap: CGFloat = 8, minimumButtonWidth: CGFloat = 72, buttonTitlePadding: CGFloat = 16
    static let suppressionGap: CGFloat = 16, maximumFooterWidth: CGFloat = 560, footerRowGap: CGFloat = 8
    static let minimumTextViewport: CGFloat = 60

    struct Accessory: Equatable { var size: NSSize; var flexibleWidth: Bool }

    struct Spec: Equatable {
        var buttonWidths: [CGFloat]          // alert.buttons order
        var suppressionSize: NSSize? = nil   // nil = not shown
        var accessory: Accessory? = nil
        var maximumHeight: CGFloat
    }

    /// Measured at `textColumnWidth(cardWidth:)`. 0 = absent (message: no explanation line; block: no MySQL block).
    struct TextHeights: Equatable { var title: CGFloat; var message: CGFloat = 0; var block: CGFloat = 0 }

    struct Frames: Equatable {
        var size: NSSize
        var tile: NSRect
        var textViewport: NSRect            // the text scroll view, in the card
        var textDocumentHeight: CGFloat
        var scrolls: Bool
        var title: NSRect                   // title / message / block: in the text document
        var message: NSRect?
        var block: NSRect?
        var accessory: NSRect?              // accessory / suppression / buttons: in the card
        var suppression: NSRect?
        var buttons: [NSRect]               // alert.buttons order
    }

    struct BlockFrames: Equatable { var label: NSRect; var text: NSRect }   // in the block

    // MARK: - Metrics

    static func textColumnWidth(cardWidth: CGFloat) -> CGFloat {
        cardWidth - textColumnX - margin
    }

    static func buttonWidth(titleWidth: CGFloat) -> CGFloat {
        max(minimumButtonWidth, ceil(titleWidth) + 2 * buttonTitlePadding)
    }

    static func blockHeight(labelHeight: CGFloat, textHeight: CGFloat) -> CGFloat {
        blockPaddingY + labelHeight + blockLabelGap + textHeight + blockPaddingY
    }

    static func blockFrames(blockWidth: CGFloat, labelHeight: CGFloat, textHeight: CGFloat) -> BlockFrames {
        let w = blockWidth - 2 * blockPaddingX
        let label = NSRect(x: blockPaddingX, y: blockPaddingY, width: w, height: labelHeight)
        let text = NSRect(x: blockPaddingX, y: label.maxY + blockLabelGap, width: w, height: textHeight)
        return BlockFrames(label: label, text: text)
    }

    private static func buttonsRowWidth(_ widths: [CGFloat]) -> CGFloat {
        widths.reduce(0, +) + buttonGap * CGFloat(max(widths.count - 1, 0))
    }

    static func width(_ spec: Spec) -> CGFloat {
        let buttons = buttonsRowWidth(spec.buttonWidths)
        var width = max(baseWidth, buttons + 2 * margin)
        if let accessory = spec.accessory {
            width = max(width, accessory.flexibleWidth ? accessory.size.width + 2 * margin
                                                       : textColumnX + accessory.size.width + margin)
        }
        if let suppression = spec.suppressionSize {
            let need = suppression.width + suppressionGap + buttons + 2 * margin
            if need <= maximumFooterWidth { width = max(width, need) }
        }
        return width
    }

    // MARK: - Frames

    static func frames(_ spec: Spec, text: TextHeights) -> Frames {
        let cardWidth = width(spec)
        let columnWidth = textColumnWidth(cardWidth: cardWidth)

        // Text document (top-down, relative to the text column).
        let title = NSRect(x: 0, y: titleTopInset, width: columnWidth, height: text.title)
        var documentHeight = title.maxY
        var message: NSRect?
        if text.message > 0 {
            let r = NSRect(x: 0, y: documentHeight + titleMessageGap, width: columnWidth, height: text.message)
            message = r
            documentHeight = r.maxY
        }
        var block: NSRect?
        if text.block > 0 {
            let r = NSRect(x: 0, y: documentHeight + blockGap, width: columnWidth, height: text.block)
            block = r
            documentHeight = r.maxY
        }

        // Footer geometry (needed first: the cap on the card height depends on it).
        let buttons = buttonsRowWidth(spec.buttonWidths)
        var suppressionOnOwnRow = false
        var footerHeight = buttonHeight
        if let s = spec.suppressionSize {
            if s.width + suppressionGap + buttons <= cardWidth - 2 * margin {
                footerHeight = max(buttonHeight, s.height)
            } else {
                suppressionOnOwnRow = true
                footerHeight = s.height + footerRowGap + buttonHeight
            }
        }
        let accessoryBlock = spec.accessory.map { accessoryGap + $0.size.height } ?? 0
        let chrome = margin + accessoryBlock + footerGap + footerHeight + margin

        // Over the maximum height only the text viewport shrinks (down to its minimum).
        var viewportHeight = documentHeight
        let natural = chrome + max(tileSize, documentHeight)
        let excess = natural - spec.maximumHeight
        if excess > 0 {
            viewportHeight = max(min(documentHeight, minimumTextViewport), documentHeight - excess)
        }
        let topSection = max(tileSize, viewportHeight)

        let viewport = NSRect(x: textColumnX, y: margin, width: columnWidth, height: viewportHeight)
        var y = margin + topSection

        var accessoryFrame: NSRect?
        if let accessory = spec.accessory {
            y += accessoryGap
            accessoryFrame = accessory.flexibleWidth
                ? NSRect(x: margin, y: y, width: cardWidth - 2 * margin, height: accessory.size.height)
                : NSRect(x: textColumnX, y: y, width: accessory.size.width, height: accessory.size.height)
            y += accessory.size.height
        }

        y += footerGap
        var suppressionFrame: NSRect?
        var buttonsY = y
        if let s = spec.suppressionSize {
            if suppressionOnOwnRow {
                // Never past the right margin: a wider checkbox truncates its title.
                suppressionFrame = NSRect(x: margin, y: y, width: min(s.width, cardWidth - 2 * margin), height: s.height)
                buttonsY = y + s.height + footerRowGap
            } else {
                suppressionFrame = NSRect(x: margin, y: y + (footerHeight - s.height) / 2, width: s.width, height: s.height)
            }
        }
        let buttonRowY = buttonsY + (suppressionOnOwnRow || spec.suppressionSize == nil ? 0 : (footerHeight - buttonHeight) / 2)

        var buttonFrames: [NSRect] = []
        var right = cardWidth - margin
        for w in spec.buttonWidths {
            buttonFrames.append(NSRect(x: right - w, y: buttonRowY, width: w, height: buttonHeight))
            right -= w + buttonGap
        }

        let height = y + footerHeight + margin

        return Frames(
            size: NSSize(width: cardWidth, height: height),
            tile: NSRect(x: margin, y: margin, width: tileSize, height: tileSize),
            textViewport: viewport,
            textDocumentHeight: documentHeight,
            scrolls: documentHeight > viewportHeight,
            title: title,
            message: message,
            block: block,
            accessory: accessoryFrame,
            suppression: suppressionFrame,
            buttons: buttonFrames
        )
    }
}
