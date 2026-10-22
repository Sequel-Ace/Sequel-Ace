//
//  SAFavoriteColourSelectorLayout.swift
//  Sequel Ace
//
//  Where the connection colour picker (SPColorSelectorView) puts its dots: a
//  "none" slot, then the favourite colours in rainbow order. A slot is a place
//  on screen; a tag is what the picker stores (-1 for none, otherwise the
//  colour's stored index), so the stored indices keep their meaning while the
//  dots read as a spectrum.
//

import Foundation

@objc(SAFavoriteColourSelectorLayout)
final class SAFavoriteColourSelectorLayout: NSObject {

    @objc static let dotSize: CGFloat = 16
    @objc static let pitch: CGFloat = 21
    @objc static let originX: CGFloat = 3
    @objc static let originY: CGFloat = 2

    /// The tag of the "none" slot.
    private static let noneTag = -1

    /// The stored indices shown for a list of `colourCount` colours, in rainbow order.
    private static func shownIndices(colourCount: Int) -> [Int] {
        SAVividColour.rainbowOrder.map(\.rawValue).filter { $0 < colourCount }
    }

    /// The "none" slot plus one slot per rainbow-order colour the list has.
    @objc(slotCountForColourCount:)
    static func slotCount(colourCount: Int) -> Int {
        1 + shownIndices(colourCount: colourCount).count
    }

    /// The tag shown in `slot`, or `NSNotFound` outside the slots.
    @objc(tagForSlot:colourCount:)
    static func tag(forSlot slot: Int, colourCount: Int) -> Int {
        guard slot >= 0 else { return NSNotFound }
        if slot == 0 { return noneTag }
        let shown = shownIndices(colourCount: colourCount)
        return slot - 1 < shown.count ? shown[slot - 1] : NSNotFound
    }

    /// The slot that shows `tag`, or `NSNotFound` when no slot does.
    @objc(slotForTag:colourCount:)
    static func slot(forTag tag: Int, colourCount: Int) -> Int {
        if tag == noneTag { return 0 }
        guard let position = shownIndices(colourCount: colourCount).firstIndex(of: tag) else { return NSNotFound }
        return position + 1
    }

    @objc(rectForSlot:)
    static func rect(forSlot slot: Int) -> NSRect {
        NSRect(x: originX + CGFloat(slot) * pitch, y: originY, width: dotSize, height: dotSize)
    }

    /// The right edge of the last dot.
    @objc(contentWidthForColourCount:)
    static func contentWidth(colourCount: Int) -> CGFloat {
        rect(forSlot: slotCount(colourCount: colourCount) - 1).maxX
    }
}
