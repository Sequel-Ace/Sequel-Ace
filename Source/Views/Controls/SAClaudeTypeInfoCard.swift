//
//  SAClaudeTypeInfoCard.swift
//  Sequel Ace
//
//  Shows the Structure tab's Type Info panel (DBView.xib) as a Claude hint card beside the open Type
//  dropdown. The XIB panel is restyled on its first show: no title bar, a card for its content, and it
//  never takes the mouse. App target only.
//

import AppKit

@objc(SAClaudeTypeInfoCard) final class SAClaudeTypeInfoCard: NSObject {

    /// Fills `panel` with the type's help, sizes it to the text and shows it beside `popUp`. `popUp` is
    /// optional because `-[SPComboBoxCell spPopUpWindow]` can return nil; a nil pop-up is placed as the ObjC
    /// code placed it (a zero frame, level unchanged).
    @objc(showDefinition:range:typeDescription:inPanel:textView:besidePopUpWindow:)
    static func show(definition: String, range: String?, description: String, in panel: NSPanel,
                     textView: NSTextView, besidePopUpWindow popUp: NSWindow?) {
        guard let scrollView = textView.enclosingScrollView,
              let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let palette = SAClaudeHintCardPalette.current()
        let card = restyle(panel, scrollView: scrollView, textView: textView, palette: palette)
        card.apply(palette)

        let width = panel.frame.width
        let textWidth = width - 2 * SAClaudeHintCard.horizontalPadding
        textView.setFrameSize(NSSize(width: textWidth, height: textView.frame.height))
        textView.textStorage?.setAttributedString(SAClaudeTypeInfoText.attributedString(
            definition: definition, range: range, description: description, palette: palette))
        layoutManager.ensureLayout(for: container)
        let textHeight = ceil(layoutManager.usedRect(for: container).height)

        let popUpFrame = popUp?.frame ?? .zero
        let size = NSSize(width: width, height: textHeight + 2 * SAClaudeHintCard.verticalPadding)
        let frame = SAClaudeTypeInfoText.frame(popUpFrame: popUpFrame,
                                               screenFrame: screenFrame(at: NSPoint(x: popUpFrame.minX, y: popUpFrame.maxY)),
                                               size: size)
        panel.setFrame(frame, display: false)
        scrollView.frame = card.bounds.insetBy(dx: SAClaudeHintCard.horizontalPadding, dy: SAClaudeHintCard.verticalPadding)
        textView.setFrameSize(NSSize(width: textWidth, height: textHeight))
        textView.scroll(.zero)
        card.needsDisplay = true
        panel.display()
        panel.invalidateShadow()

        if let popUp, panel.level.rawValue < popUp.level.rawValue { panel.level = popUp.level }
        panel.orderFront(nil)
    }

    /// The panel's card, made on the first show: the title bar goes, the window turns clear around a
    /// hint card that holds the XIB's scroll view at the card's padding.
    private static func restyle(_ panel: NSPanel, scrollView: NSScrollView, textView: NSTextView,
                                palette: SAClaudeHintCardPalette) -> SAClaudeHintCardView {
        if let card = panel.contentView as? SAClaudeHintCardView { return card }

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size
        let hidesOnDeactivate = panel.hidesOnDeactivate
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.hidesOnDeactivate = hidesOnDeactivate
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let card = SAClaudeHintCardView(palette: palette)
        card.frame = NSRect(origin: .zero, size: contentSize)
        card.autoresizingMask = [.width, .height]
        scrollView.removeFromSuperview()
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.drawsBackground = false
        scrollView.frame = card.bounds.insetBy(dx: SAClaudeHintCard.horizontalPadding, dy: SAClaudeHintCard.verticalPadding)
        scrollView.autoresizingMask = [.width, .height]
        card.addSubview(scrollView)
        panel.contentView = card
        panel.setContentSize(contentSize)

        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = .zero
        return card
    }

    /// The frame of the screen containing `point`, or zero when none does (as `+[NSScreen rectOfScreenAtPoint:]`).
    private static func screenFrame(at point: NSPoint) -> NSRect {
        NSScreen.screens.first { NSPointInRect(point, $0.frame) }?.frame ?? .zero
    }
}
