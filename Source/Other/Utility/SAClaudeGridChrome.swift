//
//  SAClaudeGridChrome.swift
//  Sequel Ace
//
//  The results grids' Claude look (Query and Content tabs): colours derived from
//  the editor theme, value/NULL fonts, the header's name/type split and the
//  scroller appearance for the theme. Shared with the Unit Tests target.
//

import AppKit

@objc final class SAClaudeGridChrome: NSObject {

    static let rowLineRatio: CGFloat = 0.12
    static let headerLineRatio: CGFloat = 0.12
    static let zebraRatio: CGFloat = 0.035
    static let headerFillRatio: CGFloat = 0.05
    static let headerLabelRatio: CGFloat = 0.55
    static let typeTagRatio: CGFloat = 0.36
    static let hoverRatio: CGFloat = 0.08
    static let nullRatio: CGFloat = 0.36
    @objc static let headerHeight: CGFloat = 30
    @objc static let minimumRowHeight: CGFloat = 30

    struct Palette: Equatable {
        let background, text, rowLine, headerLine, zebra, headerBackground, headerLabel, typeTag, hover, selection, null, displayOverride, caret: NSColor
    }

    static func palette(text: NSColor, background: NSColor, selection: NSColor, keyword: NSColor, caret: NSColor) -> Palette {
        func mix(_ ratio: CGFloat) -> NSColor { SAClaudeEditorChrome.derivedColour(text: text, background: background, ratio: ratio) }
        return Palette(background: background, text: text, rowLine: mix(rowLineRatio), headerLine: mix(headerLineRatio),
                       zebra: mix(zebraRatio), headerBackground: mix(headerFillRatio),
                       headerLabel: mix(headerLabelRatio), typeTag: mix(typeTagRatio), hover: mix(hoverRatio),
                       selection: selection, null: mix(nullRatio), displayOverride: keyword, caret: caret)
    }

    static func palette(from defaults: UserDefaults) -> Palette {
        func colour(_ key: String, _ fallback: NSColor) -> NSColor { SAArchiving.color(from: defaults.data(forKey: key)) ?? fallback }
        return palette(text: colour(SAEditorThemeLoader.textColourKey, .textColor),
                       background: colour(SAEditorThemeLoader.backgroundColourKey, .textBackgroundColor),
                       selection: colour(SAEditorThemeLoader.selectionColourKey, .selectedTextBackgroundColor),
                       keyword: colour(SAEditorThemeLoader.keywordColourKey, .systemBlue),
                       caret: colour(SAEditorThemeLoader.caretColourKey, .textColor))
    }

    /// Every other row is shaded: rows 1, 3, 5...
    static func isZebra(row: Int) -> Bool { row % 2 == 1 }

    /// Column separators sit at each column's right edge, except the last one at the edge of the
    /// table (within 1pt, so float noise can't draw it).
    static func drawsColumnSeparator(columnMaxX: CGFloat, boundsMaxX: CGFloat) -> Bool {
        columnMaxX < boundsMaxX - 1
    }

    /// Where column lines end: the bottom of the last row, or nil (no lines) when there are no rows.
    static func columnLineExtent(rowCount: Int, lastRowMaxY: CGFloat) -> CGFloat? {
        rowCount > 0 ? lastRowMaxY : nil
    }

    /// Relative luminance below 0.5 counts as a dark background.
    static func isDark(_ background: NSColor) -> Bool {
        guard let c = background.usingColorSpace(.sRGB) else { return false }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent < 0.5
    }

    /// Dark scrollers on dark theme backgrounds and light ones on light, whatever macOS uses.
    @objc static func scrollerAppearance(for background: NSColor) -> NSAppearance? {
        NSAppearance(named: isDark(background) ? .darkAqua : .aqua)
    }

    /// The upright font with tabular (monospaced) digits.
    static func valueFont(_ font: NSFont) -> NSFont {
        let upright = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
        let descriptor = upright.fontDescriptor.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: descriptor, size: upright.pointSize) ?? upright
    }

    /// The value font in italic, for NULL and not-yet-loaded cells.
    static func nullFont(_ font: NSFont) -> NSFont {
        let value = valueFont(font)
        let italic = NSFontManager.shared.convert(value, toHaveTrait: .italicFontMask)
        if italic.fontDescriptor.symbolicTraits.contains(.italic) { return italic }
        // Fonts without an italic face: slant the value font.
        let slanted = value.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: slanted, size: value.pointSize) ?? value
    }

    /// Splits a column header title into name and type. The type, when shown, is the
    /// last attribute run (a smaller font, see NSDictionary.tableContentColumnHeaderAttributedString);
    /// the name keeps any spaces it contains.
    static func headerParts(_ title: NSAttributedString) -> (name: String, type: String?) {
        var runs: [NSRange] = []
        title.enumerateAttributes(in: NSRange(location: 0, length: title.length), options: []) { _, range, _ in runs.append(range) }
        let string = title.string as NSString
        guard runs.count >= 2, let last = runs.last, last.location > 0 else { return (title.string, nil) }
        let type = string.substring(with: last).trimmingCharacters(in: .whitespaces)
        let name = string.substring(to: last.location).trimmingCharacters(in: .whitespaces)
        return type.isEmpty ? (title.string, nil) : (name, type)
    }
}
