//
//  SAPrintUtility.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import AppKit
import WebKit

// Inlined so this file stays free of project ObjC types and can compile into
// the Unit Tests target (no bridging header there). Keep in sync with
// `SPPrintBackground` in SPConstants.m.
let printBackgroundPreferenceKey = "PrintBackground"

/// Builds `NSPrintOperation`s for `WKWebView`s with the app's shared page
/// setup: symmetric margins derived from the printable page bounds, fit-width
/// pagination, and the extended print-panel options.
///
/// Replaces the legacy `SPPrintUtility`, which printed via the deprecated
/// WebKit `WebView`.
@objc final class SAPrintUtility: NSObject {

    /// The app's shared page setup: a copy of the shared print info with
    /// symmetric margins derived from the printable page bounds, fit-width
    /// pagination, and top-aligned content. Pure — safe to call (and test)
    /// without any web view or printer interaction.
    @objc static func configuredPrintInfo() -> NSPrintInfo {
        // Applied to a copy so the shared print info isn't mutated for the
        // rest of the app.
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()

        let paperSize = printInfo.paperSize
        let printableRect = printInfo.imageablePageBounds

        let marginL = printableRect.origin.x
        let marginR = paperSize.width - (printableRect.origin.x + printableRect.size.width)
        let marginB = printableRect.origin.y
        let marginT = paperSize.height - (printableRect.origin.y + printableRect.size.height)

        // Make sure margins are symmetric and positive
        let marginLR = max(0, max(marginL, marginR))
        let marginTB = max(0, max(marginT, marginB))

        printInfo.leftMargin = marginLR
        printInfo.rightMargin = marginLR
        printInfo.topMargin = marginTB
        printInfo.bottomMargin = marginTB

        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isVerticallyCentered = false

        return printInfo
    }

    @objc(printOperationForWebView:)
    static func printOperation(for webView: WKWebView) -> NSPrintOperation {
        // The legacy print accessory toggled WebPreferences.shouldPrintBackgrounds;
        // WKWebView only exposes this from macOS 13.3.
        if #available(macOS 13.3, *) {
            webView.configuration.preferences.shouldPrintBackgrounds = UserDefaults.standard.bool(forKey: printBackgroundPreferenceKey)
        }

        let operation = webView.printOperation(with: configuredPrintInfo())

        // WKWebView's print operation view starts with a zero frame; without
        // sizing it the preview and output are blank.
        operation.view?.frame = NSRect(origin: .zero, size: webView.frame.size)

        // Assign the panel back explicitly: relying on the lazy printPanel
        // getter to cache the mutated panel is not guaranteed for the
        // operation WebKit returns.
        let panel = operation.printPanel
        panel.options.formUnion([.showsOrientation, .showsScaling, .showsPaperSize])
        operation.printPanel = panel

        return operation
    }
}

/// Renders an HTML string in an offscreen `WKWebView` and hands back a ready
/// `NSPrintOperation` once the content has finished loading.
///
/// The web view is kept alive after the completion fires — the print operation
/// draws from it while the print panel is open. Call `invalidate()` (or start
/// another render, which does it implicitly) to cancel a pending render; the
/// owner should also call it when closing so a late navigation callback can't
/// fire into a dead context.
@objc final class SAHTMLPrintRenderer: NSObject, WKNavigationDelegate {

    private var webView: WKWebView?
    private var completion: ((NSPrintOperation?) -> Void)?

    /// Loads `html` offscreen and calls `completionHandler` on the main thread
    /// with a configured print operation, or `nil` if the content failed to load.
    @objc(printHTMLString:completionHandler:)
    func printHTMLString(_ html: String, completionHandler: @escaping (NSPrintOperation?) -> Void) {
        invalidate()

        // A plausible page frame; the print operation repaginates for the real
        // paper size, but a zero-sized web view renders nothing.
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1100))
        webView.navigationDelegate = self
        self.webView = webView
        completion = completionHandler

        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Drops any pending completion and releases the offscreen web view.
    @objc func invalidate() {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        completion = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(with: SAPrintUtility.printOperation(for: webView), from: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: nil, from: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: nil, from: webView)
    }

    private func finish(with operation: NSPrintOperation?, from webView: WKWebView) {
        guard webView === self.webView, let completion = completion else { return }
        self.completion = nil
        completion(operation)
    }
}
