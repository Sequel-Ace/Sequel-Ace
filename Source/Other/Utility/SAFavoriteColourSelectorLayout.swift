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

    /// The colour dot itself, drawn inside a full-size slot.
    @objc static let visualDotSize: CGFloat = 12

    /// The tightest pitch the dots are squeezed to in a narrow control.
    private static let minimumPitch: CGFloat = 14

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

    /// The pitch that fits the slots of `colourCount` colours into a control `width` points wide: the
    /// full pitch when there is room, then the gaps shrink while the slots stay full size, then the
    /// slots shrink with the pitch (never below `minimumPitch`).
    @objc(pitchForColourCount:width:)
    static func pitch(colourCount: Int, width: CGFloat) -> CGFloat {
        let slots = CGFloat(slotCount(colourCount: colourCount))
        let roomy = (width - 2 * originX - dotSize) / max(1, slots - 1)
        let squeezed = (width - originX) / slots
        let fitted = roomy >= dotSize + slotGap ? roomy : squeezed
        return max(minimumPitch, min(pitch, fitted))
    }

    /// The edge of a slot at that pitch: full size until the slots would run into each other.
    @objc(slotSizeForPitch:)
    static func slotSize(forPitch pitch: CGFloat) -> CGFloat {
        min(dotSize, pitch - slotGap)
    }

    /// The gap kept between two neighbouring slots once they shrink.
    private static let slotGap: CGFloat = 3

    /// The slot's rect in a control `width` points wide.
    @objc(rectForSlot:colourCount:width:)
    static func rect(forSlot slot: Int, colourCount: Int, width: CGFloat) -> NSRect {
        let pitch = pitch(colourCount: colourCount, width: width)
        let size = slotSize(forPitch: pitch)
        return NSRect(x: originX + CGFloat(slot) * pitch, y: originY, width: size, height: size)
    }

    /// The narrowest control the slots of `colourCount` colours are squeezed into.
    @objc(minimumWidthForColourCount:)
    static func minimumWidth(colourCount: Int) -> CGFloat {
        CGFloat(slotCount(colourCount: colourCount)) * minimumPitch + originX
    }

    /// The right edge of the last dot.
    @objc(contentWidthForColourCount:)
    static func contentWidth(colourCount: Int) -> CGFloat {
        rect(forSlot: slotCount(colourCount: colourCount) - 1).maxX
    }
}
