//
//  SAScrollableAlertTextTests.swift
//  Unit Tests
//
//  Covers NSAlert.setScrollableInformativeText(_:), used for lengthy connection errors.
//

import XCTest

final class SAScrollableAlertTextTests: XCTestCase {

    private var longText: String {
        (1...200).map { "Line \($0) of a lengthy diagnostic message" }.joined(separator: "\n")
    }

    private func makeAlert(text: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.addButton(withTitle: "OK")
        alert.setScrollableInformativeText(text)
        return alert
    }

    private func detailTextView(of alert: NSAlert, file: StaticString = #filePath, line: UInt = #line) -> NSTextView? {
        let scrollView = alert.accessoryView as? NSScrollView
        XCTAssertNotNil(scrollView, "Long text should be shown in a scroll view", file: file, line: line)
        let textView = scrollView?.documentView as? NSTextView
        XCTAssertNotNil(textView, "The scroll view should hold a text view", file: file, line: line)
        return textView
    }

    func testShortTextStaysPlainInformativeText() {
        let alert = makeAlert(text: "Could not connect.")

        XCTAssertEqual(alert.informativeText, "Could not connect.")
        XCTAssertNil(alert.accessoryView)
    }

    func testLongTextMovesIntoAScrollableTextView() {
        let text = longText
        let alert = makeAlert(text: text)

        XCTAssertEqual(alert.informativeText, "")
        guard let textView = detailTextView(of: alert) else { return }
        XCTAssertEqual(textView.string, text)
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
    }

    func testLongTextViewIsAnAlertDetailTextView() {
        let alert = makeAlert(text: longText)

        guard let textView = detailTextView(of: alert) else { return }
        // Guards the key-view behaviour below: scrollableTextView() must hand back our subclass.
        XCTAssertTrue(textView is SAAlertDetailTextView, "Got \(String(describing: type(of: textView)))")
    }

    func testLongTextViewCannotBecomeKeyViewBeforeTheAlertIsOnScreen() {
        let alert = makeAlert(text: longText)
        // Lay the alert out so its accessory view is in the alert's window, as it is when shown.
        alert.layout()

        guard let textView = detailTextView(of: alert) else { return }
        XCTAssertNotNil(textView.window, "The text view should be in the alert's window")
        XCTAssertFalse(alert.window.isVisible, "The alert must not be on screen in a unit test")
        // A text view that can become key view is picked as the alert's initial key view when the
        // alert is ordered in, and the focus system then scrolls it into view, which opens a tall
        // text mid-way down. It only becomes a key view once the alert is visible.
        XCTAssertFalse(textView.canBecomeKeyView)
        // Clicking into the text must still work, so the error stays selectable and copyable.
        XCTAssertTrue(textView.acceptsFirstResponder)
    }
}
