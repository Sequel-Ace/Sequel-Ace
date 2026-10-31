//
//  SAClaudeLineHeight.swift
//  Sequel Ace
//
//  One line of text in a font, measured once. `NSLayoutManager().defaultLineHeight(for:)` is the right answer, but a
//  layout manager registers (and on dealloc removes) default-centre observers, and the removal scans every observer
//  registered in the process, which grows with each open tab. Cell and strip layout asked for it per row, per draw.
//  Here a font is measured on one shared layout manager the first time and the height is kept, keyed by font name and
//  size, so a font changed in Settings is simply a new entry. Locked, so a stray background caller is safe, but these
//  are AppKit layout paths and run on the main thread. Shared with the Unit Tests target.
//

import AppKit

enum SAClaudeLineHeight {

    private struct Key: Hashable {
        let name: String
        let size: CGFloat
    }

    private static let lock = NSLock()
    private static var heights: [Key: CGFloat] = [:]
    private static var layoutManager: NSLayoutManager?
    private(set) static var measurementCount = 0

    /// The font's default line height, as `NSLayoutManager.defaultLineHeight(for:)` reports it.
    static func height(for font: NSFont) -> CGFloat {
        let key = Key(name: font.fontName, size: font.pointSize)
        lock.lock()
        defer { lock.unlock() }
        if let cached = heights[key] { return cached }
        let manager = layoutManager ?? NSLayoutManager()
        layoutManager = manager
        let height = manager.defaultLineHeight(for: font)
        heights[key] = height
        measurementCount += 1
        return height
    }

    /// `height(for:)` rounded up to a whole point, which is how the cells and strips use it.
    static func ceiledHeight(for font: NSFont) -> CGFloat {
        ceil(height(for: font))
    }

    /// Forgets every measurement (tests).
    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        heights.removeAll()
        layoutManager = nil
        measurementCount = 0
    }
}
