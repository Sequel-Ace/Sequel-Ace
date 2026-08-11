//
//  SAHelpViewerModelTests.swift
//  Unit Tests
//
//  Created as part of the WebView to WKWebView migration.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SAHelpViewerModelTests: XCTestCase {

    // MARK: - Term history

    func testVisitBuildsHistoryAndDisablesNavigationAtTheEnds() {
        let model = SAHelpViewerModel()

        XCTAssertNil(model.currentTerm)
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)

        model.visit("SELECT")
        XCTAssertEqual(model.currentTerm, "SELECT")
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.canGoForward)

        model.visit("INSERT")
        XCTAssertTrue(model.canGoBack)
        XCTAssertFalse(model.canGoForward)
    }

    func testGoBackAndGoForwardWalkTheTermStack() {
        let model = SAHelpViewerModel()
        model.visit("SELECT")
        model.visit("INSERT")
        model.visit("UPDATE")

        XCTAssertEqual(model.goBack(), "INSERT")
        XCTAssertEqual(model.goBack(), "SELECT")
        XCTAssertNil(model.goBack())
        XCTAssertFalse(model.canGoBack)

        XCTAssertEqual(model.goForward(), "INSERT")
        XCTAssertEqual(model.goForward(), "UPDATE")
        XCTAssertNil(model.goForward())
        XCTAssertFalse(model.canGoForward)
    }

    func testVisitTruncatesTheForwardEntries() {
        let model = SAHelpViewerModel()
        model.visit("SELECT")
        model.visit("INSERT")
        model.visit("UPDATE")

        XCTAssertEqual(model.goBack(), "INSERT")
        model.visit("DELETE")

        XCTAssertEqual(model.history, ["SELECT", "INSERT", "DELETE"])
        XCTAssertEqual(model.currentTerm, "DELETE")
        XCTAssertFalse(model.canGoForward)
    }

    func testVisitIgnoresEmptyTermsAndAdjacentDuplicates() {
        let model = SAHelpViewerModel()

        XCTAssertFalse(model.visit(""))
        XCTAssertTrue(model.visit("SELECT"))
        XCTAssertFalse(model.visit("SELECT"))
        XCTAssertEqual(model.history, ["SELECT"])

        // The same term is recorded again once another one was displayed in between.
        XCTAssertTrue(model.visit("INSERT"))
        XCTAssertTrue(model.visit("SELECT"))
        XCTAssertEqual(model.history, ["SELECT", "INSERT", "SELECT"])
    }

    /// Legacy parity: `[[helpWebView backForwardList] setCapacity:20]`.
    func testHistoryIsCappedAtTwentyEntriesEvictingTheOldest() {
        let model = SAHelpViewerModel()

        for index in 1...25 {
            model.visit("TERM \(index)")
        }

        XCTAssertEqual(SAHelpViewerModel.historyCapacity, 20)
        XCTAssertEqual(model.history.count, 20)
        XCTAssertEqual(model.history.first, "TERM 6")
        XCTAssertEqual(model.history.last, "TERM 25")
        XCTAssertEqual(model.currentTerm, "TERM 25")
    }

    func testEvictionKeepsTheCurrentTermAndBackNavigationAligned() {
        let model = SAHelpViewerModel()

        for index in 1...22 {
            model.visit("TERM \(index)")
        }

        XCTAssertEqual(model.goBack(), "TERM 21")
        XCTAssertEqual(model.goBack(), "TERM 20")

        // Walking all the way back stops at the oldest surviving entry.
        while model.canGoBack {
            _ = model.goBack()
        }
        XCTAssertEqual(model.currentTerm, "TERM 3")
    }

    // MARK: - Search target

    func testOnlyTheMySQLTargetSearchesIncrementally() {
        XCTAssertFalse(SAHelpTarget.mysql.sendsWholeSearchString)
        XCTAssertTrue(SAHelpTarget.page.sendsWholeSearchString)
        XCTAssertTrue(SAHelpTarget.web.sendsWholeSearchString)
    }

    func testHelpTargetRawValuesMatchTheSegmentOrder() {
        XCTAssertEqual(SAHelpTarget.allCases.map(\.rawValue), [0, 1, 2])
        XCTAssertEqual(SAHelpTarget(rawValue: 0), .mysql)
        XCTAssertEqual(SAHelpTarget(rawValue: 1), .page)
        XCTAssertEqual(SAHelpTarget(rawValue: 2), .web)
    }

    // MARK: - Navigation policy matrix

    func testInternalLinkClickLooksUpTheTerm() {
        let url = URL(string: "sequelace-help://help/SELECT")

        XCTAssertEqual(SAHelpViewerModel.policy(for: url, kind: .linkActivated), .lookupTerm("SELECT"))
    }

    func testInternalLinkTermIsPercentDecoded() {
        let url = URL(string: "sequelace-help://help/ALTER%20TABLE")

        XCTAssertEqual(SAHelpViewerModel.policy(for: url, kind: .linkActivated), .lookupTerm("ALTER TABLE"))
    }

    /// The policy only recognises internal links because the help HTML is loaded with
    /// `internalHelpBaseURL`: topic links in it are relative (`<a href='SELECT'>`), so
    /// they reach the delegate resolved against that base. With a nil base URL WebKit
    /// would load the document as `about:blank` and deliver a scheme-less relative URL,
    /// which is `.deny` — i.e. every topic link would be dead.
    func testRelativeTopicLinksResolveAgainstTheBaseURLAndLookUpTheTerm() {
        let baseURL = SAHelpViewerModel.internalHelpBaseURL
        XCTAssertEqual(baseURL?.scheme, SAHelpViewerModel.internalHelpScheme)

        let resolved = URL(string: "ALTER%20TABLE", relativeTo: baseURL)?.absoluteURL
        XCTAssertEqual(SAHelpViewerModel.policy(for: resolved, kind: .linkActivated), .lookupTerm("ALTER TABLE"))

        // Unresolved (what a nil base URL would produce) routes nowhere.
        let unresolved = URL(string: "ALTER%20TABLE")
        XCTAssertEqual(SAHelpViewerModel.policy(for: unresolved, kind: .linkActivated), .deny)
    }

    func testInternalBaseURLItselfIsNotATerm() {
        XCTAssertEqual(SAHelpViewerModel.policy(for: SAHelpViewerModel.internalHelpBaseURL, kind: .linkActivated), .deny)
    }

    func testWebLinkClickOpensExternally() {
        let httpsURL = URL(string: "https://dev.mysql.com/doc/refman/8.0/en/select.html")!
        let httpURL = URL(string: "http://example.com/page.html")!
        let ftpURL = URL(string: "ftp://ftp.example.com/manual.html")!

        XCTAssertEqual(SAHelpViewerModel.policy(for: httpsURL, kind: .linkActivated), .openExternally(httpsURL))
        XCTAssertEqual(SAHelpViewerModel.policy(for: httpURL, kind: .linkActivated), .openExternally(httpURL))
        XCTAssertEqual(SAHelpViewerModel.policy(for: ftpURL, kind: .linkActivated), .openExternally(ftpURL))
    }

    func testLinkClickWithAnUnsupportedSchemeIsDenied() {
        // The help HTML is generated from server-supplied text, so only browser
        // schemes are handed to the system.
        XCTAssertEqual(SAHelpViewerModel.policy(for: URL(string: "file:///etc/passwd"), kind: .linkActivated), .deny)
        XCTAssertEqual(SAHelpViewerModel.policy(for: URL(string: "javascript:alert(1)"), kind: .linkActivated), .deny)
        XCTAssertEqual(SAHelpViewerModel.policy(for: URL(string: "sequelace://x"), kind: .linkActivated), .deny)
    }

    func testTheRenderingNavigationItselfIsAllowed() {
        // loadHTMLString arrives as `.other`, with and without a URL.
        XCTAssertEqual(SAHelpViewerModel.policy(for: URL(string: "about:blank"), kind: .other), .allow)
        XCTAssertEqual(SAHelpViewerModel.policy(for: nil, kind: .other), .allow)
    }

    func testEverythingElseIsDenied() {
        let url = URL(string: "https://dev.mysql.com/")

        XCTAssertEqual(SAHelpViewerModel.policy(for: url, kind: .backForward), .deny)
        XCTAssertEqual(SAHelpViewerModel.policy(for: url, kind: .reload), .deny)
        XCTAssertEqual(SAHelpViewerModel.policy(for: url, kind: .formSubmitted), .deny)
        XCTAssertEqual(SAHelpViewerModel.policy(for: url, kind: .formResubmitted), .deny)
        XCTAssertEqual(SAHelpViewerModel.policy(for: nil, kind: .linkActivated), .deny)
    }

    // MARK: - Window title

    func testWindowTitleAppendsThePageTitle() {
        XCTAssertEqual(SAHelpViewerModel.windowTitle(pageTitle: "Version 8.0.36: SELECT"), "MySQL Help (Version 8.0.36: SELECT)")
    }

    func testWindowTitleWithoutPageTitleIsThePlainTitle() {
        XCTAssertEqual(SAHelpViewerModel.windowTitle(pageTitle: nil), "MySQL Help")
        XCTAssertEqual(SAHelpViewerModel.windowTitle(pageTitle: ""), "MySQL Help")
    }

    // MARK: - Theme hook

    func testThemeChangeScriptCallsTheTemplateHook() {
        XCTAssertEqual(SAHelpViewerModel.themeChangeScript(isDarkAppearance: true), "window.onThemeChange('dark')")
        XCTAssertEqual(SAHelpViewerModel.themeChangeScript(isDarkAppearance: false), "window.onThemeChange('light')")
    }

    // MARK: - Context menu

    func testSelectionSearchItemsNeedANonEmptySelection() {
        XCTAssertTrue(SAHelpViewerModel.offersSelectionSearchItems(selectedText: "SELECT", menuItemIdentifiers: ["WKMenuItemIdentifierCopy"]))
        XCTAssertFalse(SAHelpViewerModel.offersSelectionSearchItems(selectedText: "", menuItemIdentifiers: ["WKMenuItemIdentifierCopy"]))
        XCTAssertFalse(SAHelpViewerModel.offersSelectionSearchItems(selectedText: "  \n ", menuItemIdentifiers: ["WKMenuItemIdentifierCopy"]))
    }

    /// Loading a new topic must drop the cached selection, or the previous page's
    /// selection would still offer (and search for) text that is no longer displayed.
    func testClearingTheSelectionWithdrawsTheSelectionSearchItems() {
        let model = SAHelpViewerModel()
        model.selectedText = "SELECT"

        XCTAssertTrue(SAHelpViewerModel.offersSelectionSearchItems(
            selectedText: model.selectedText,
            menuItemIdentifiers: []
        ))

        model.clearSelection()

        XCTAssertEqual(model.selectedText, "")
        XCTAssertFalse(SAHelpViewerModel.offersSelectionSearchItems(
            selectedText: model.selectedText,
            menuItemIdentifiers: []
        ))
    }

    func testSelectionSearchItemsAreSuppressedOnALiveLink() {
        XCTAssertFalse(SAHelpViewerModel.offersSelectionSearchItems(
            selectedText: "SELECT",
            menuItemIdentifiers: ["WKMenuItemIdentifierOpenLink", "WKMenuItemIdentifierCopyLink"]
        ))
    }

    func testPrunedContextMenuIdentifiersCoverTheLegacyRemovals() {
        // Link, image, media, reload and paste items were all pruned by the legacy
        // controller; WebKit's own back/forward is dropped because this window
        // navigates its own term history.
        for identifier in [
            "WKMenuItemIdentifierOpenLink",
            "WKMenuItemIdentifierOpenLinkInNewWindow",
            "WKMenuItemIdentifierDownloadLinkedFile",
            "WKMenuItemIdentifierOpenImageInNewWindow",
            "WKMenuItemIdentifierDownloadImage",
            "WKMenuItemIdentifierCopyImage",
            "WKMenuItemIdentifierOpenFrameInNewWindow",
            "WKMenuItemIdentifierReload",
            "WKMenuItemIdentifierPaste",
            "WKMenuItemIdentifierGoBack",
            "WKMenuItemIdentifierGoForward"
        ] {
            XCTAssertTrue(SAHelpViewerModel.prunedContextMenuIdentifiers.contains(identifier), identifier)
        }

        // Copy and look-up stay.
        XCTAssertFalse(SAHelpViewerModel.prunedContextMenuIdentifiers.contains("WKMenuItemIdentifierCopy"))
        XCTAssertFalse(SAHelpViewerModel.prunedContextMenuIdentifiers.contains("WKMenuItemIdentifierLookUp"))
    }

    // MARK: - Key equivalents

    func testKeyCommandsMatchTheLegacyKeyEquivalents() {
        XCTAssertEqual(SAHelpViewerModel.keyCommand(characters: "f", hasCommand: true, hasShift: false), .focusSearchField)
        XCTAssertEqual(SAHelpViewerModel.keyCommand(characters: "g", hasCommand: true, hasShift: false), .findNextInPage)
        XCTAssertEqual(SAHelpViewerModel.keyCommand(characters: "G", hasCommand: true, hasShift: true), .findPreviousInPage)
        XCTAssertEqual(SAHelpViewerModel.keyCommand(characters: "M", hasCommand: true, hasShift: true), .selectTarget(.mysql))
        XCTAssertEqual(SAHelpViewerModel.keyCommand(characters: "P", hasCommand: true, hasShift: true), .selectTarget(.page))
        XCTAssertEqual(SAHelpViewerModel.keyCommand(characters: "W", hasCommand: true, hasShift: true), .selectTarget(.web))
        XCTAssertEqual(SAHelpViewerModel.keyCommand(characters: "+", hasCommand: true, hasShift: true), .makeTextLarger)
        XCTAssertEqual(SAHelpViewerModel.keyCommand(characters: "=", hasCommand: true, hasShift: false), .makeTextLarger)
        XCTAssertEqual(SAHelpViewerModel.keyCommand(characters: "-", hasCommand: true, hasShift: false), .makeTextSmaller)
    }

    func testKeysWithoutCommandOrWithTheWrongModifiersAreNotCommands() {
        XCTAssertNil(SAHelpViewerModel.keyCommand(characters: "g", hasCommand: false, hasShift: false))
        XCTAssertNil(SAHelpViewerModel.keyCommand(characters: "m", hasCommand: true, hasShift: false))
        XCTAssertNil(SAHelpViewerModel.keyCommand(characters: "w", hasCommand: true, hasShift: false))
        XCTAssertNil(SAHelpViewerModel.keyCommand(characters: "x", hasCommand: true, hasShift: false))
        XCTAssertNil(SAHelpViewerModel.keyCommand(characters: "", hasCommand: true, hasShift: false))
    }
}
