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
//  The one element rule is `table{font-size:inherit}`, the standards-mode behaviour: a page without a doctype (DB Report)
//  is in quirks mode, whose UA sheet resets tables to the 16px default while the rest of the page takes the 13px type;
//  `<table>` has no font-size attribute, so no hint is overridden.
//  There is no background rule: the paper is drawn behind a transparent web view, so any page background paints over
//  it. A plain page (no colours or fonts of its own, `SAClaudePlainPage`) gets the theme base instead, which follows the
//  theme and goes in the same way (`themeStylesheet`). Pure Foundation/AppKit so it is shared with the Unit Tests target.
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
            + ":where(table){font-size:inherit}"
            + ":where(body:not([link]):not([vlink]):not([alink]) a:any-link){color:\(SAClaudeHintCardCSS.colour(paper.accent))}"
            + "@media print{:where(:root){\(SAClaudeHintCardCSS.declarations(paper))}}"
        return "<style \(marker)>\(css)</style>"
    }

    /// The theme base, for a plain page (`SAClaudePlainPage`: no colours or fonts of its own), which follows the theme
    /// instead of sitting on the paper: the theme's variables, Claude type in the theme's text colour, links in the
    /// theme's (readable) accent, and the paper's variables when printed. The theme's surface is drawn behind the
    /// transparent web view, as the paper is. Colours go through the variables, so the print rule (and a live theme
    /// change, which rewrites the element's CSS) reaches the text and links too. Same marker, so `inject`, `strip` and
    /// the rules above hold for it.
    static func themeStylesheet(theme: SAClaudeHintCardPalette, paper: SAClaudeHintCardPalette) -> String {
        "<style \(marker)>\(themeCSS(theme: theme, paper: paper))</style>"
    }

    /// The CSS inside `themeStylesheet`.
    static func themeCSS(theme: SAClaudeHintCardPalette, paper: SAClaudeHintCardPalette) -> String {
        ":where(:root){\(SAClaudeHintCardCSS.declarations(theme))}"
            + ":where(html){color:var(--sa-text);font:13px/1.5 -apple-system,system-ui,sans-serif}"
            + ":where(table){font-size:inherit}"
            + ":where(a:any-link){color:var(--sa-accent)}"
            + "@media print{:where(:root){\(SAClaudeHintCardCSS.declarations(paper))}}"
    }

    /// `html` with `stylesheet` ahead of the page's own styles: right after `<head…>`; with no head, after `<html…>`;
    /// with neither, after a leading `<!DOCTYPE…>` (comments, whitespace and a byte order mark may precede it);
    /// otherwise (a fragment) at the start, after a byte order mark. Tags inside HTML comments don't count. Whitespace
    /// after an `<html>` or doctype tag stays before the base, where the parser drops it (after the base it would become
    /// text in the head). Unchanged when the page already carries the marker.
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
        let prologueEnd = firstTag("<body[\\s>]", in: html)?.lowerBound ?? html.endIndex
        if let head = firstTag("<head(?:\\s[^>]*)?>", in: html), head.upperBound <= prologueEnd {
            return head.upperBound
        }
        if let root = firstTag("<html(?:\\s[^>]*)?>\\s*", in: html), root.lowerBound < prologueEnd {
            return root.upperBound
        }
        if let doctype = html.range(of: "^\u{FEFF}?(?>\\s|<!--[\\s\\S]*?-->)*<!DOCTYPE[^>]*>\\s*",
                                    options: [.regularExpression, .caseInsensitive]) {
            return doctype.upperBound
        }
        return html.hasPrefix("\u{FEFF}") ? html.index(after: html.startIndex) : html.startIndex
    }

    /// The first match of `pattern` (case-insensitive) outside HTML comments (an unclosed one runs to the end).
    private static func firstTag(_ pattern: String, in html: String) -> Range<String.Index>? {
        let regex = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?(?:-->|\\z)|(\(pattern))", options: [.caseInsensitive])
        var found: Range<String.Index>?
        regex.enumerateMatches(in: html, range: NSRange(html.startIndex..., in: html)) { match, _, stop in
            guard let match, match.range(at: 1).location != NSNotFound else { return }
            found = Range(match.range(at: 1), in: html)
            stop.pointee = true
        }
        return found
    }
}
