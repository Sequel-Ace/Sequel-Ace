//
//  SAClaudePlainPage.swift
//  Sequel Ace
//
//  Whether a bundle's HTML is "plain": it sets no colours or fonts of its own, so it can follow the theme (dark in
//  dark) instead of sitting on the light paper. Deliberately not a parser: the page is styled as soon as any of
//  `styleSignals` appears anywhere in it, in any case — in a tag, an attribute, a comment, a script or plain text — and
//  `text` or `link` followed by `=` (after optional whitespace) covers the `text`, `link`, `vlink` and `alink`
//  attributes. Plain only when none appears. It can only err towards "styled": a page that merely mentions "color" or
//  "style" in its text stays on the paper, as it always did, while no way of writing a style (missing spaces, `/`
//  separators, `>` inside quotes, odd comments) can make a styled page count as plain. Styling done by a script at run
//  time (no signal in the source) and SVG `fill`/`stroke` attributes can't be seen. One pass over the page per signal
//  (Foundation's literal search, one simple regex): linear, whatever the page. Pure Foundation, shared with the Unit
//  Tests target.
//

import Foundation

enum SAClaudePlainPage {

    /// Substrings (lowercase ASCII) that mark a page as styling itself: `<style>` and `style=`, stylesheet links, font
    /// elements, and the colour and background attributes (`color` also covers `bgcolor`).
    static let styleSignals = ["style", "<link", "<font", "<basefont", "color", "background", "bgcolor"]

    /// Attribute names that only count before `=`, since the words are common in text.
    static let attributeSignals = ["text", "link"]

    static func isPlain(_ html: String) -> Bool {
        let lowered = html.lowercased()
        if styleSignals.contains(where: { lowered.range(of: $0, options: .literal) != nil }) { return false }
        return attributePattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) == nil
    }

    // MARK: Private

    /// `text` or `link` (so also `vlink`, `alink`), optional whitespace, `=`. A literal start and one `\s*` run: no
    /// nested repetition, so a match attempt never backtracks past the whitespace it scanned.
    private static let attributePattern = try! NSRegularExpression(
        pattern: "(?:\(attributeSignals.joined(separator: "|")))\\s*=", options: [.caseInsensitive])
}
