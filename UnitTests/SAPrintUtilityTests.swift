//
//  SAPrintUtilityTests.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import AppKit
import WebKit
import XCTest

final class SAPrintUtilityTests: XCTestCase {

    private func makeWebView(width: CGFloat = 640, height: CGFloat = 480) -> WKWebView {
        WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    // MARK: - Page setup (pure, WebKit-independent)

    func testMarginsAreSymmetricAndNonNegative() {
        let info = SAPrintUtility.configuredPrintInfo()

        XCTAssertEqual(info.leftMargin, info.rightMargin)
        XCTAssertEqual(info.topMargin, info.bottomMargin)
        XCTAssertGreaterThanOrEqual(info.leftMargin, 0)
        XCTAssertGreaterThanOrEqual(info.topMargin, 0)
    }

    func testMarginsDeriveFromImageablePageBounds() {
        let info = SAPrintUtility.configuredPrintInfo()

        let paper = info.paperSize
        let printable = info.imageablePageBounds
        let expectedLR = max(0, max(printable.origin.x, paper.width - printable.maxX))
        let expectedTB = max(0, max(printable.origin.y, paper.height - printable.maxY))

        XCTAssertEqual(info.leftMargin, expectedLR, accuracy: 0.0001)
        XCTAssertEqual(info.topMargin, expectedTB, accuracy: 0.0001)
    }

    func testPaginationIsFitWidthAndAutomaticHeight() {
        let info = SAPrintUtility.configuredPrintInfo()

        XCTAssertEqual(info.horizontalPagination, .fit)
        XCTAssertEqual(info.verticalPagination, .automatic)
        XCTAssertFalse(info.isVerticallyCentered)
    }

    func testConfiguredPrintInfoIsACopyAndSharedIsNotMutated() {
        let shared = NSPrintInfo.shared
        let leftBefore = shared.leftMargin
        let topBefore = shared.topMargin
        let horizontalBefore = shared.horizontalPagination
        let verticalBefore = shared.verticalPagination
        let centeredBefore = shared.isVerticallyCentered

        let info = SAPrintUtility.configuredPrintInfo()

        XCTAssertFalse(info === NSPrintInfo.shared)
        XCTAssertEqual(NSPrintInfo.shared.leftMargin, leftBefore)
        XCTAssertEqual(NSPrintInfo.shared.topMargin, topBefore)
        XCTAssertEqual(NSPrintInfo.shared.horizontalPagination, horizontalBefore)
        XCTAssertEqual(NSPrintInfo.shared.verticalPagination, verticalBefore)
        XCTAssertEqual(NSPrintInfo.shared.isVerticallyCentered, centeredBefore)
    }

    // MARK: - Print operation

    func testSharedPrintInfoIsNotMutatedByBuildingAnOperation() {
        let leftBefore = NSPrintInfo.shared.leftMargin
        let horizontalBefore = NSPrintInfo.shared.horizontalPagination

        _ = SAPrintUtility.printOperation(for: makeWebView())

        XCTAssertEqual(NSPrintInfo.shared.leftMargin, leftBefore)
        XCTAssertEqual(NSPrintInfo.shared.horizontalPagination, horizontalBefore)
    }

    func testPrintPanelShowsExtendedOptions() throws {
        let operation = SAPrintUtility.printOperation(for: makeWebView())

        // Without a printing view (sandboxed test environments), the WebKit
        // operation also fails to retain its configured print panel, so the
        // options are only observable on a fully-formed operation.
        try XCTSkipIf(operation.view == nil, "WKWebView returned an operation without a printing view in this environment")

        let options = operation.printPanel.options
        XCTAssertTrue(options.contains(.showsOrientation))
        XCTAssertTrue(options.contains(.showsScaling))
        XCTAssertTrue(options.contains(.showsPaperSize))
    }

    func testOperationViewIsSizedToWebView() throws {
        let webView = makeWebView(width: 800, height: 1100)

        let operation = SAPrintUtility.printOperation(for: webView)

        // In sandboxed test environments WebKit may be unable to create its
        // printing view; the sizing behavior is only observable with one.
        try XCTSkipIf(operation.view == nil, "WKWebView returned an operation without a printing view in this environment")
        XCTAssertEqual(operation.view?.frame.origin, .zero)
        XCTAssertEqual(operation.view?.frame.size, webView.frame.size)
    }

    func testPrintBackgroundPreferenceIsAppliedToWebViewPreferences() {
        guard #available(macOS 13.3, *) else { return }

        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: printBackgroundPreferenceKey)
        defer {
            if let original {
                defaults.set(original, forKey: printBackgroundPreferenceKey)
            } else {
                defaults.removeObject(forKey: printBackgroundPreferenceKey)
            }
        }

        let webView = makeWebView()

        defaults.set(true, forKey: printBackgroundPreferenceKey)
        _ = SAPrintUtility.printOperation(for: webView)
        XCTAssertTrue(webView.configuration.preferences.shouldPrintBackgrounds)

        defaults.set(false, forKey: printBackgroundPreferenceKey)
        _ = SAPrintUtility.printOperation(for: webView)
        XCTAssertFalse(webView.configuration.preferences.shouldPrintBackgrounds)
    }

    // MARK: - Offscreen renderer

    func testRendererDeliversPrintOperationAfterLoad() {
        let renderer = SAHTMLPrintRenderer()
        let completionFired = expectation(description: "completion handler runs")
        var receivedOperation: NSPrintOperation?

        renderer.printHTMLString("<html><body><p>print me</p></body></html>") { operation in
            receivedOperation = operation
            completionFired.fulfill()
        }

        waitForExpectations(timeout: 15)
        XCTAssertNotNil(receivedOperation)
    }

    func testInvalidateDropsPendingCompletion() {
        let renderer = SAHTMLPrintRenderer()
        let completionFired = expectation(description: "completion handler must not run")
        completionFired.isInverted = true

        renderer.printHTMLString("<html><body>never</body></html>") { _ in
            completionFired.fulfill()
        }
        renderer.invalidate()

        waitForExpectations(timeout: 2)
    }

    func testWebContentProcessTerminationFinishesWithNil() {
        let renderer = SAHTMLPrintRenderer()
        let completionFired = expectation(description: "completion handler runs")
        var receivedOperation: NSPrintOperation? = NSPrintOperation()

        renderer.printHTMLString("<html><body>crash</body></html>") { operation in
            receivedOperation = operation
            completionFired.fulfill()
        }
        renderer.webViewWebContentProcessDidTerminate(makeWebView())

        waitForExpectations(timeout: 2)
        XCTAssertNil(receivedOperation)
    }

    // MARK: - Print accessory

    private func withRestoredPrintBackgroundDefault(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: printBackgroundPreferenceKey)
        body()
        if let original {
            defaults.set(original, forKey: printBackgroundPreferenceKey)
        } else {
            defaults.removeObject(forKey: printBackgroundPreferenceKey)
        }
    }

    func testAccessoryReadsInitialStateFromDefaults() {
        withRestoredPrintBackgroundDefault {
            UserDefaults.standard.set(true, forKey: printBackgroundPreferenceKey)
            XCTAssertTrue(SAPrintAccessoryController(webView: nil).printsBackgrounds)

            UserDefaults.standard.set(false, forKey: printBackgroundPreferenceKey)
            XCTAssertFalse(SAPrintAccessoryController(webView: nil).printsBackgrounds)
        }
    }

    func testAccessoryTogglePersistsDefaultAndAppliesToWebView() {
        withRestoredPrintBackgroundDefault {
            UserDefaults.standard.set(false, forKey: printBackgroundPreferenceKey)
            let webView = makeWebView()
            let accessory = SAPrintAccessoryController(webView: webView)

            accessory.printsBackgrounds = true

            XCTAssertTrue(UserDefaults.standard.bool(forKey: printBackgroundPreferenceKey))
            if #available(macOS 13.3, *) {
                XCTAssertTrue(webView.configuration.preferences.shouldPrintBackgrounds)
            }
        }
    }

    func testAccessorySummaryAndPreviewKeyPaths() {
        let accessory = SAPrintAccessoryController(webView: nil)

        let summary = accessory.localizedSummaryItems()
        XCTAssertEqual(summary.count, 1)
        XCTAssertNotNil(summary.first?[.itemName])
        XCTAssertNotNil(summary.first?[.itemDescription])

        XCTAssertTrue(accessory.keyPathsForValuesAffectingPreview().contains("printsBackgrounds"))
    }
}
