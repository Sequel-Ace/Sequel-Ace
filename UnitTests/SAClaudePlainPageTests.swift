//
//  SAClaudePlainPageTests.swift
//  Unit Tests
//
//  Which bundle HTML is "plain" (follows the theme) and which styles itself (stays on the paper): every rule Kunal set
//  (walkthrough item 16), the conservative signal check of fix round 1 (it can only err towards "styled"), the ways of
//  writing a style that a parser could miss, and that the check stays fast on any page.
//

import XCTest

final class SAClaudePlainPageTests: XCTestCase {

    private func assertPlain(_ html: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(SAClaudePlainPage.isPlain(html), "should be plain: \(html)", file: file, line: line)
    }

    private func assertStyled(_ html: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(SAClaudePlainPage.isPlain(html), "should be styled: \(html)", file: file, line: line)
    }

    // MARK: Plain

    func testPagesWithoutColoursOrFontsArePlain() {
        assertPlain("")
        assertPlain("plain text")
        assertPlain("<b>x</b>")
        assertPlain("<!DOCTYPE html><html><head><title>Report</title><meta charset=\"utf-8\"></head>"
                    + "<body><h1>Tables</h1><table border=\"1\" cellpadding=\"4\"><tr><th colspan=2>a</th></tr>"
                    + "<tr><td align=right>1</td><td>2</td></tr></table><p><a href=\"https://x\">link</a></p>"
                    + "<img src=\"x.png\" width=\"20\"><ul><li>i</li></ul></body></html>")
        assertPlain("<input type=\"text\" value=\"a\"><textarea>t</textarea>")
        assertPlain("<p class=\"x\" id=\"a\">the link and the text</p>")
        assertPlain("<script>var a = 1 < 2;</script><p>text: 5</p>")
        assertPlain("<span title=\"a > b\">x</span><!-- generated -->")
        assertPlain("<pre>&lt;b&gt;x&lt;/b&gt;</pre>") // View Source of a plain page
    }

    // MARK: Styled

    func testStyleElementIsStyled() {
        assertStyled("<style>body{background:#000}</style><p>x</p>")
        assertStyled("<STYLE type=\"text/css\">p{}</STYLE>")
        assertStyled("<style/>")
    }

    func testStylesheetLinkIsStyled() {
        assertStyled("<link rel=\"stylesheet\" href=\"a.css\">")
        assertStyled("<LINK REL=stylesheet HREF=a.css>")
        assertStyled("<link href='a.css' rel='alternate stylesheet'>")
        assertStyled("<link\nrel=\"stylesheet\"\nhref=\"a.css\">")
    }

    func testStyleAttributeIsStyled() {
        assertStyled("<p style=\"color:red\">x</p>")
        assertStyled("<div class=a STYLE='margin:0'>x</div>")
        assertStyled("<p\tstyle = \"x\">x</p>")
    }

    func testColourAttributesAreStyled() {
        for attribute in ["bgcolor", "text", "link", "vlink", "alink", "color", "background"] {
            assertStyled("<body \(attribute)=\"#000000\">x</body>")
            assertStyled("<TD \(attribute.uppercased())=red>x</TD>")
            assertStyled("<td \(attribute) = red>x</td>")
        }
        assertStyled("<table bgcolor=#ECECEC><tr><td>x</td></tr></table>")
    }

    func testFontElementsAreStyled() {
        assertStyled("<font color=blue>x</font>")
        assertStyled("<FONT face=\"Monaco\">x</FONT>")
        assertStyled("<font>x</font>")
        assertStyled("<basefont size=3>")
    }

    /// DB Report (the default bundle that writes HTML): `<font color=blue>` and `#ECECEC` bars.
    func testDBReportStaysOnThePaper() {
        assertStyled("<html><body><h2>Database</h2><table width=\"100%\"><tr bgcolor=\"#ECECEC\"><td>"
                     + "<font color=blue>orders</font></td></tr></table></body></html>")
    }

    /// The check is not a parser: a signal anywhere counts, so a page that only mentions one stays on the paper (the
    /// harmless direction). Comments and scripts count too.
    func testSignalsCountAnywhere() {
        assertStyled("<p>Pick a colour, not a color.</p>")
        assertStyled("<p>lifestyle</p>")
        assertStyled("<p>background</p>")
        assertStyled("<!-- <style>body{}</style> --><p>x</p>")
        assertStyled("<p data-color=\"red\">x</p>")
        assertStyled("<link rel=\"icon\" href=\"favicon.png\">")
        assertStyled("<pre>&lt;style&gt;</pre>") // View Source of a styled page mentions style
        assertStyled("<script>document.body.style.color = 'red'</script>")
    }

    /// Ways of writing a style that a tag/attribute parser could miss (review 2c I1): all come back styled.
    func testParserBypassesAreStyled() {
        assertStyled("<p class=\"x\"style=\"color:red\">x</p>")           // no space after a quoted value
        assertStyled("<p/style=\"margin:0\">x</p>")                        // `/` as the separator
        assertStyled("<link/rel=stylesheet href=a.css>")
        assertStyled("<a title=\"a > b\" style=\"margin:0\">x</a>")         // `>` inside an earlier quoted value
        assertStyled("<link href=\"a>b.css\" rel=stylesheet>")
        assertStyled("<!--><p>x</p><style>p{}</style>")                     // an empty comment
        assertStyled("<!---><p>x</p><font>x</font>")
        assertStyled("<script>var s = '<!--';</script><style>p{}</style>")  // an unclosed comment in a script
        assertStyled("<p>x</p><!-- unclosed <style>")
        assertStyled("<body\ntext\n=\n\"#fff\">x</body>")
        assertStyled("<body tex text=\"#fff\">x</body>")
        assertStyled("<body textext=\"#fff\">x</body>")
        assertStyled("<BODY VLINK=#00f>x</BODY>")
        assertStyled("<body alink='#f00'>x</body>")
    }

    // MARK: Cost

    func testBigPagesAreFast() {
        let row = "<tr><td>1</td><td>a value &amp; more</td><td><a href=\"x\">x</a></td></tr>\n"
        let page = "<html><body><table>" + String(repeating: row, count: 20_000) + "</table></body></html>"
        var start = Date()
        XCTAssertTrue(SAClaudePlainPage.isPlain(page))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)

        // Many stray `<` and comments.
        let stray = String(repeating: "a < b ", count: 50_000) + String(repeating: "<!--c-->", count: 5_000)
        start = Date()
        XCTAssertTrue(SAClaudePlainPage.isPlain(stray))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    /// A long unspaced run after `<` + a letter (minified JSON or JS in a page) took the old tag regex 29 s for 60k
    /// characters (review 2c M1); the signal check stays well under 50 ms.
    func testLongUnspacedRunIsFast() {
        let run = "<a" + String(repeating: "b", count: 60_000)
        var start = Date()
        XCTAssertTrue(SAClaudePlainPage.isPlain(run))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05)
        // Many near-misses of the attribute names and a long whitespace run without an `=`.
        let near = String(repeating: "tex", count: 20_000) + "text" + String(repeating: " ", count: 60_000) + "x"
        start = Date()
        XCTAssertTrue(SAClaudePlainPage.isPlain(near))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05)
    }
}
