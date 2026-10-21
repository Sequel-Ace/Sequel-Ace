//
//  SAClaudePlainPageTests.swift
//  Unit Tests
//
//  Which bundle HTML is "plain" (follows the theme) and which styles itself (stays on the paper): every rule Kunal set
//  (walkthrough item 16), the cases that must not count, and that the check stays fast on a big page.
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
        assertPlain("<pre>&lt;style&gt;body{color:red}&lt;/style&gt; &lt;font color=red&gt;</pre>") // View Source output
        assertPlain("<!DOCTYPE html><html><head><title>Report</title><meta charset=\"utf-8\"></head>"
                    + "<body><h1>Tables</h1><table border=\"1\" cellpadding=\"4\"><tr><th colspan=2>a</th></tr>"
                    + "<tr><td align=right>1</td><td>2</td></tr></table><p><a href=\"https://x\">link</a></p>"
                    + "<img src=\"x.png\" width=\"20\"><ul><li>i</li></ul></body></html>")
        assertPlain("<input type=\"text\" value=\"a\"><textarea>t</textarea>")
        assertPlain("<link rel=\"icon\" href=\"favicon.png\"><link rel=alternate href=\"x\">")
        assertPlain("<p data-color=\"red\" class=\"x\" id=\"style\">x</p>")
        assertPlain("<script>var a = 1 < 2;</script><p>text = 5, color = blue</p>")
        assertPlain("<span title=\"a > b\">x</span>")
    }

    /// Markup that only appears inside a comment doesn't style the page.
    func testCommentsDoNotCount() {
        assertPlain("<!-- <style>body{}</style> <font color=red> --><p>x</p>")
        assertPlain("<p>x</p><!-- unclosed <style>")
        assertStyled("<!-- note --><style>body{}</style>")
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

    // MARK: Cost

    func testBigPagesAreFast() {
        let row = "<tr><td>1</td><td>a value &amp; more</td><td><a href=\"x\">x</a></td></tr>\n"
        let page = "<html><body><table>" + String(repeating: row, count: 20_000) + "</table></body></html>"
        var start = Date()
        XCTAssertTrue(SAClaudePlainPage.isPlain(page))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)

        // Many stray `<` with no closing `>` and many comments must not go quadratic.
        let stray = String(repeating: "a < b ", count: 50_000) + String(repeating: "<!--c-->", count: 5_000)
        start = Date()
        XCTAssertTrue(SAClaudePlainPage.isPlain(stray))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}
