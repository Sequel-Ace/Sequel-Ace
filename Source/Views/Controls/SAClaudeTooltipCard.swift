//
//  SAClaudeTooltipCard.swift
//  Sequel Ace
//
//  What SPTooltip asks for to draw as the Claude hint card: the page for its web view in the present
//  palettes, and the native card its web view or image sits in. App target only.
//

import AppKit

@objc(SAClaudeTooltipCard) final class SAClaudeTooltipCard: NSObject {

    /// The tooltip page around `body`: `"text"` and plain bundle HTML on the theme card, bundle HTML that styles itself
    /// on the paper.
    @objc(documentWithBody:type:options:)
    static func document(body: String, type: String, options: [String: Any]?) -> String {
        SAClaudeTooltipHTML.document(body: body, kind: type == "text" ? .text : .html, options: options,
                                     theme: .current(), paper: .currentPaper())
    }

    /// A text value escaped into the tooltip's `<pre>`.
    @objc(textBody:options:)
    static func textBody(_ text: String, options: [String: Any]?) -> String {
        SAClaudeTooltipHTML.textBody(text, options: options)
    }

    /// The card with `view` filling it (and following its size).
    @objc(cardWrappingView:)
    static func card(wrapping view: NSView) -> NSView {
        let card = SAClaudeHintCardView(palette: .current())
        card.frame = view.frame
        view.frame = card.bounds
        view.autoresizingMask = [.width, .height]
        card.addSubview(view)
        return card
    }

    /// The card around an image: sized to the fitted image plus the padding, the image inset by it.
    @objc(cardForImage:)
    static func card(for image: NSImage) -> NSView {
        let size = SAClaudeHintCard.imageCardSize(image.size)
        let fit = SAClaudeHintCard.imageFit(image.size)
        let card = SAClaudeHintCardView(palette: .current())
        card.frame = NSRect(origin: .zero, size: size)
        let imageView = NSImageView(frame: NSRect(x: SAClaudeHintCard.horizontalPadding, y: SAClaudeHintCard.verticalPadding,
                                                  width: fit.width, height: fit.height))
        imageView.image = image
        card.addSubview(imageView)
        return card
    }
}
