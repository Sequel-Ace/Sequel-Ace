//
//  SAClaudeInfoRowLayout.swift
//  Sequel Ace
//
//  Where a sidebar Table information row's label and value go: label at the
//  list's indent, value right-aligned, the value narrowed (not the label)
//  when they would meet. Shared with the unit tests.
//

import AppKit

enum SAClaudeInfoRowLayout {
    static let minimumGap: CGFloat = 8

    /// Splits a drawn info row ("Label\tvalue", as SAClaudeInfoRow builds it) into label and value; nil without a tab.
    static func parts(of text: String) -> (label: String, value: String)? {
        guard let tab = text.firstIndex(of: "\t") else { return nil }
        return (String(text[..<tab]), String(text[text.index(after: tab)...]))
    }

    /// The label and value rects in a row: label from `leading`, value right-aligned `trailing` from the right edge,
    /// the value narrowed (never the label) to keep `minimumGap` between them.
    static func frames(in rect: NSRect, labelWidth: CGFloat, valueWidth: CGFloat, leading: CGFloat, trailing: CGFloat) -> (label: NSRect, value: NSRect) {
        let label = NSRect(x: rect.minX + leading, y: rect.minY, width: labelWidth, height: rect.height)
        let valueMaxX = rect.maxX - trailing
        let available = max(0, valueMaxX - (label.maxX + minimumGap))
        let width = min(valueWidth, available)
        return (label, NSRect(x: valueMaxX - width, y: rect.minY, width: width, height: rect.height))
    }
}
