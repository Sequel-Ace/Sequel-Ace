//
//  SAStaleBookmarkAlertContentTests.swift
//  Unit Tests
//
//  Covers the bounded launch-time stale bookmark alert content.
//

import XCTest

final class SAStaleBookmarkAlertContentTests: XCTestCase {

    func testDisplayNamesDecodeFileURLLastPathComponents() {
        let displayNames = SABookmarkAlertContent.displayNames(forBookmarkPaths: [
            "file:///Users/tom/Backups/My%20Backup.sql",
            "file:///Users/tom/Exports/report.csv"
        ])

        XCTAssertEqual(displayNames, [
            "My Backup.sql",
            "report.csv"
        ])
    }

    func testDisplayNamesHandlePlainFilePaths() {
        let displayNames = SABookmarkAlertContent.displayNames(forBookmarkPaths: [
            "/Users/tom/Backups/nightly.sql"
        ])

        XCTAssertEqual(displayNames, ["nightly.sql"])
    }

    func testDisplayNamesDecodeReservedCharactersAfterExtractingFileURLPath() {
        let displayNames = SABookmarkAlertContent.displayNames(forBookmarkPaths: [
            "file:///Users/tom/Backups/foo%23bar%3Fbaz.sql"
        ])

        XCTAssertEqual(displayNames, ["foo#bar?baz.sql"])
    }

    func testBookmarkPathNormalizerPreservesEncodedReservedCharacters() {
        let normalizedPath = SABookmarkPathNormalizer.normalizedFilePath(forBookmarkPath: "file:///tmp/foo%23bar%3Fbaz.sql")

        XCTAssertEqual(normalizedPath, "/tmp/foo#bar?baz.sql")
    }

    func testStaleBookmarksMessageStaysBoundedForLargeLists() {
        let message = SABookmarkAlertContent.staleBookmarksMessage(count: 200)

        XCTAssertTrue(message.contains("200"))
        XCTAssertFalse(message.contains("\n"))
        XCTAssertLessThan(message.count, 180)
    }

    func testMissingBookmarksMessageUsesSingularForm() {
        let message = SABookmarkAlertContent.missingBookmarksMessage(count: 1)

        XCTAssertTrue(message.contains("1 missing secure bookmark"))
        XCTAssertFalse(message.contains("them"))
    }

    func testScrollableAccessoryUsesCappedScrollViewForLargeLists() throws {
        let helpView = NSTextField(labelWithString: "Bookmark help")
        let listItems = (0..<200).map { "backup-\($0).sql" }

        let accessoryView = NSAlert.scrollableListAccessoryView(listItems: listItems, helpView: helpView)
        let stackView = try XCTUnwrap(accessoryView.subviews.first as? NSStackView)
        let scrollView = try XCTUnwrap(stackView.arrangedSubviews.first as? NSScrollView)
        let heightConstraint = try XCTUnwrap(scrollView.constraints.first { $0.firstAttribute == .height })

        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertLessThanOrEqual(heightConstraint.constant, 220)
        XCTAssertGreaterThanOrEqual(heightConstraint.constant, 96)
        XCTAssertLessThanOrEqual(accessoryView.frame.width, 520)
    }

    func testScrollableAccessoryPreservesFixedFrameHelpViewHeight() throws {
        let helpView = NSView(frame: NSRect(x: 0, y: 0, width: 193, height: 24))
        let helpButton = NSButton(frame: NSRect(x: -2, y: -2, width: 25, height: 25))
        let helpLabel = NSTextField(labelWithString: "App Sandbox Info")
        helpLabel.frame = NSRect(x: 23, y: 0, width: 137, height: 21)
        helpView.addSubview(helpButton)
        helpView.addSubview(helpLabel)

        let accessoryView = NSAlert.scrollableListAccessoryView(listItems: ["backup.sql"], helpView: helpView)
        let stackView = try XCTUnwrap(accessoryView.subviews.first as? NSStackView)
        let stackedHelpView = try XCTUnwrap(stackView.arrangedSubviews.last)
        let heightConstraint = try XCTUnwrap(stackedHelpView.constraints.first { $0.identifier == "SABookmarkAlertHelpHeight" })
        let widthConstraint = try XCTUnwrap(stackedHelpView.constraints.first { $0.identifier == "SABookmarkAlertHelpWidth" })

        XCTAssertEqual(heightConstraint.constant, 24)
        XCTAssertEqual(widthConstraint.constant, 193)
    }
}
