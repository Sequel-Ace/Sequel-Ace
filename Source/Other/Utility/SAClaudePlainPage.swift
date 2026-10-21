//
//  SAClaudePlainPage.swift
//  Sequel Ace
//
//  Whether a bundle's HTML is "plain": it sets no colours or fonts of its own, so it can follow the theme (dark in
//  dark) instead of sitting on the light paper. A page is plain when, outside HTML comments, it has no `<style>`
//  element, no `<link rel=stylesheet>`, no `style=` attribute, no colour attribute (`bgcolor`, `text`, `link`, `vlink`,
//  `alink`, `color`, and the `background` image attribute, which paints behind the text) and no `<font>` or
//  `<basefont>`. The check errs towards "styled": an attribute-like run inside a tag's quoted value counts, and so
//  does markup written inside a script, since a styled page on the theme base could become unreadable while a plain
//  page on the paper only stays light, as it always was. Scripts that style the page at run time can't be seen.
//  Linear in the page's length (every pattern stops at the next `<` or `>`). Pure Foundation, shared with the Unit Tests
//  target.
//

import Foundation

enum SAClaudePlainPage {

    /// Attributes that colour an element (or put an image behind it).
    static let colourAttributes = ["style", "bgcolor", "text", "link", "vlink", "alink", "color", "background"]

    static func isPlain(_ html: String) -> Bool {
        let text = withoutComments(html)
        let range = NSRange(text.startIndex..., in: text)
        return !patterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    // MARK: Private

    private static let patterns: [NSRegularExpression] = [
        // <style …>, <font …>, <basefont …>
        "<(?:style|font|basefont)(?=[\\s/>])",
        // <link … rel=stylesheet …> (also "alternate stylesheet", quoted or not)
        "<link(?=[\\s/>])[^<>]*?\\srel\\s*=\\s*[\"']?[^\"'<>]*stylesheet",
        // Any tag carrying a colour attribute: the name after whitespace, then `=`.
        "<[a-z][^\\s/<>]*[^<>]*?\\s(?:\(colourAttributes.joined(separator: "|")))\\s*=",
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static let comment = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?(?:-->|\\z)")

    /// `html` with its comments (an unclosed one runs to the end) replaced by a space.
    private static func withoutComments(_ html: String) -> String {
        guard html.contains("<!--") else { return html }
        return comment.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: " ")
    }
}
