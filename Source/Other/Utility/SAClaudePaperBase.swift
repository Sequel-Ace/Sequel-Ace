//
//  SAClaudePaperBase.swift
//  Sequel Ace
//
//  The paper base under the HTML Sequel Ace hands the bundle HTML window (bundle output, its own help pages): Claude
//  type and text colour on the light paper, whatever the theme, and the theme palette as CSS variables for the pages of
//  ours that style themselves from it. Bundle HTML has always rendered on a light page, so a page that colours only
//  part of itself stays readable. Every rule has zero specificity (`:where(…)`) and comes before the page's own styles,
//  so any CSS of the page wins. Legacy attributes (`<body bgcolor text>`, `<font color>`, table colours) are
//  presentational hints, which a later zero-specificity author rule on the same element would beat, so the base names
//  none of those elements: it styles `html` (inherited, so an element's own hint still wins) and links, the link colour
//  only while the body sets none (`<body link>` reaches links through the UA's link colour, which any author rule beats).
//  There is no background rule: the paper is drawn behind a transparent web view, so any page background paints over
//  it. Pure Foundation/AppKit so it is shared with the Unit Tests target.
//

import AppKit

enum SAClaudePaperBase {

    /// The attribute that marks the base's `<style>` element.
    static let marker = "data-sa-base"

    /// The base's `<style>` element: the theme's variables, Claude type in the paper's text colour, links in the paper's
    /// accent, and the paper's variables when printed.
    static func stylesheet(paper: SAClaudeHintCardPalette, theme: SAClaudeHintCardPalette) -> String {
        let css = ":where(:root){\(SAClaudeHintCardCSS.declarations(theme))}"
            + ":where(html){color:\(SAClaudeHintCardCSS.colour(paper.text));"
            + "font:13px/1.5 -apple-system,system-ui,sans-serif;color-scheme:light}"
            + ":where(body:not([link]):not([vlink]):not([alink]) a:any-link){color:\(SAClaudeHintCardCSS.colour(paper.accent))}"
            + "@media print{:where(:root){\(SAClaudeHintCardCSS.declarations(paper))}}"
        return "<style \(marker)>\(css)</style>"
    }

    /// `html` with `stylesheet` ahead of the page's own styles: right after `<head…>`; with no head, after `<html…>`;
    /// with neither, after a leading `<!DOCTYPE…>`; otherwise (a fragment) at the start. Whitespace after an `<html>` or
    /// doctype tag stays before the base, where the parser drops it (after the base it would become text in the head).
    /// Unchanged when the page already carries the marker.
    static func inject(_ stylesheet: String, into html: String) -> String {
        guard !html.contains(marker) else { return html }
        var result = html
        result.insert(contentsOf: stylesheet, at: insertionIndex(in: html))
        return result
    }

    /// `html` without the base `inject` added, also as WebKit serialises it back (`data-sa-base=""`) for View Source and
    /// Save Page As. A page without the base is returned unchanged.
    static func strip(_ html: String) -> String {
        guard let match = html.range(of: "<style \(marker)(?:=\"\")?>[^<]*</style>", options: .regularExpression) else {
            return html
        }
        var result = html
        result.removeSubrange(match)
        return result
    }

    // MARK: - Where the base goes

    private static func insertionIndex(in html: String) -> String.Index {
        // A head or html tag counts only before the body (not one written inside the page's content or scripts).
        let prologueEnd = html.range(of: "<body[\\s>]", options: [.regularExpression, .caseInsensitive])?.lowerBound ?? html.endIndex
        let prologue = html.startIndex..<prologueEnd
        if let head = html.range(of: "<head(?:\\s[^>]*)?>", options: [.regularExpression, .caseInsensitive], range: prologue) {
            return head.upperBound
        }
        if let root = html.range(of: "<html(?:\\s[^>]*)?>\\s*", options: [.regularExpression, .caseInsensitive], range: prologue) {
            return root.upperBound
        }
        if let doctype = html.range(of: "^\\s*<!DOCTYPE[^>]*>\\s*", options: [.regularExpression, .caseInsensitive]) {
            return doctype.upperBound
        }
        return html.startIndex
    }
}
