//
//  HyperlinkTextField.swift
//  Sequel Ace
//
//  Created by James on 4/1/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

import AppKit


@IBDesignable
class HyperlinkTextField: NSTextField {

    @IBInspectable var href: String = ""

    // provides the link finger pointer cursor
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(self.bounds, cursor: NSCursor.pointingHand)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.foregroundColor: NSColor.linkColor,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue as AnyObject
        ]
        attributedStringValue = NSAttributedString(string: self.stringValue, attributes: attributes)

        isBezeled = false
        drawsBackground = false
        isEditable = false
        isSelectable = true
        allowsEditingTextAttributes = true

    }

    override func mouseDown(with theEvent: NSEvent) {
        if let localHref = URL(string: href) {
            NSWorkspace.shared.open(localHref)
        }
    }

    @objc public func reapplyAttributes() {

        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.foregroundColor: NSColor.linkColor,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue as AnyObject
        ]
        attributedStringValue = NSAttributedString(string: self.stringValue, attributes: attributes)

        isBezeled = false
        drawsBackground = false
        isEditable = false
        isSelectable = true
        allowsEditingTextAttributes = true

    }
}
