import XCTest

private typealias L = SAClaudeProgressCardLayout

final class SAClaudeProgressCardLayoutTests: XCTestCase {

    /// Export / Import: the XIB indicator (343 x 20) keeps its size; the card is that column inside 20pt padding.
    func testCardAroundTheIndicator() {
        let f = L.frames(barSize: CGSize(width: 343, height: 20), cancelTitleWidth: 40)
        XCTAssertEqual(f.size, CGSize(width: 383, height: 139))
        XCTAssertEqual(f.cancel, CGRect(x: 283, y: 20, width: 80, height: 28))
        XCTAssertEqual(f.bar, CGRect(x: 20, y: 58, width: 343, height: 20))
        XCTAssertEqual(f.detail, CGRect(x: 20, y: 84, width: 295, height: 14))
        XCTAssertEqual(f.percent, CGRect(x: 323, y: 84, width: 40, height: 14))
        XCTAssertEqual(f.title, CGRect(x: 20, y: 102, width: 343, height: 17))
        // Top padding as the bottom one.
        XCTAssertEqual(f.size.height - f.title.maxY, L.padding)
    }

    /// Everything sits in the one column: left edges on the padding, right edges on the column's end.
    func testOneColumnNoIconGutter() {
        let f = L.frames(barSize: CGSize(width: 343, height: 20), cancelTitleWidth: 90)
        for rect in [f.title, f.detail, f.bar] { XCTAssertEqual(rect.minX, L.padding) }
        for rect in [f.title, f.percent, f.bar, f.cancel] { XCTAssertEqual(rect.maxX, f.size.width - L.padding) }
        XCTAssertEqual(f.cancel.width, 122)
        XCTAssertLessThan(f.detail.maxX, f.percent.minX)
    }

    func testPercentText() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(L.percentText(value: 0, minimum: 0, maximum: 343, indeterminate: false, locale: en), "0%")
        XCTAssertEqual(L.percentText(value: 171.5, minimum: 0, maximum: 343, indeterminate: false, locale: en), "50%")
        XCTAssertEqual(L.percentText(value: 342, minimum: 0, maximum: 343, indeterminate: false, locale: en), "99%")
        XCTAssertEqual(L.percentText(value: 343, minimum: 0, maximum: 343, indeterminate: false, locale: en), "100%")
        XCTAssertEqual(L.percentText(value: 500, minimum: 0, maximum: 343, indeterminate: false, locale: en), "100%")
        XCTAssertNil(L.percentText(value: 10, minimum: 0, maximum: 343, indeterminate: true, locale: en))
        XCTAssertNil(L.percentText(value: 0, minimum: 0, maximum: 0, indeterminate: false, locale: en))
    }
}
