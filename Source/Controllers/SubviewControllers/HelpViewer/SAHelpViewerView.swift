//
//  SAHelpViewerView.swift
//  Sequel Ace
//
//  Created as part of the WebView to WKWebView migration.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import SwiftUI
import WebKit

/// The three back/TOC/forward actions of the navigation control.
enum SAHelpViewerNavigation {
    case back
    case tableOfContents
    case forward
}

/// Content of the MySQL help viewer window: the toolbar row from the legacy
/// HelpViewer.xib (navigation, search field, target selector) above a WKWebView,
/// in the Claude kit's look (`SAClaudeSwiftUIPalette` from the environment): ghost
/// icon buttons, the search field in the Claude field chrome, Claude segmented tabs
/// and a hairline rule on the theme's surface.
struct SAHelpViewerView: View {

    @ObservedObject var model: SAHelpViewerModel
    @ObservedObject var webViewModel: SAWebViewModel
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette

    /// Configuration carrying the selection bridge; built by the window controller.
    let webViewConfiguration: WKWebViewConfiguration

    let onSubmitSearch: () -> Void
    let onNavigate: (SAHelpViewerNavigation) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                navigationControl
                searchField
                targetSelector
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)

            SAWebView(model: webViewModel, externalConfiguration: webViewConfiguration)
        }
        .background(palette.surface)
    }

    private var navigationControl: some View {
        HStack(spacing: 2) {
            Button {
                onNavigate(.back)
            } label: {
                Image(systemName: "chevron.left").font(Self.glyphFont)
            }
            .buttonStyle(SAClaudeGhostIconButtonStyle())
            .disabled(!model.canGoBack)
            .accessibilityLabel(Self.backTitle)
            .help(Self.backTitle)

            Button {
                onNavigate(.tableOfContents)
            } label: {
                Image(systemName: "list.bullet").font(Self.glyphFont)
            }
            .buttonStyle(SAClaudeGhostIconButtonStyle())
            .accessibilityLabel(Self.tableOfContentsTitle)
            .help(Self.tableOfContentsTitle)

            Button {
                onNavigate(.forward)
            } label: {
                Image(systemName: "chevron.right").font(Self.glyphFont)
            }
            .buttonStyle(SAClaudeGhostIconButtonStyle())
            .disabled(!model.canGoForward)
            .accessibilityLabel(Self.forwardTitle)
            .help(Self.forwardTitle)
        }
    }

    private var searchField: some View {
        SAClaudeFieldChrome(isFocused: model.isSearchFieldFocused, size: .form) {
            SAHelpSearchField(
                text: $model.searchString,
                isFocused: $model.isSearchFieldFocused,
                placeholder: model.target.searchFieldPlaceholder,
                sendsWholeSearchString: model.target.sendsWholeSearchString,
                focusRequest: model.focusSearchFieldRequest,
                onSubmit: onSubmitSearch
            )
        }
        .frame(minWidth: 120, maxWidth: .infinity)
    }

    private var targetSelector: some View {
        // The legacy XIB explained this control with per-segment tooltips; one
        // tooltip covers all three.
        SAClaudeSegmentedTabs(
            titles: Self.targetTitles,
            selection: $model.targetIndex,
            help: SAHelpTarget.selectorHelpText,
            accessibilityLabel: NSLocalizedString("Search target", comment: "help viewer : search target selector accessibility label"),
            // The page's link colour (the card palette's readable accent), so the tab and the links agree.
            selectedText: SAClaudeHintCardPalette.current().accent
        )
    }

    /// The segments' titles, in `SAHelpTarget` raw-value order.
    private static let targetTitles = [
        NSLocalizedString("MySQL", comment: "help viewer : search target : mysql help"),
        NSLocalizedString("Page", comment: "help viewer : search target : current page"),
        NSLocalizedString("Web", comment: "help viewer : search target : online documentation")
    ]

    private static let glyphFont = Font.system(size: 12, weight: .medium)

    private static let backTitle = NSLocalizedString("Show the previous page", comment: "help viewer : back button tooltip")
    private static let tableOfContentsTitle = NSLocalizedString("MySQL Table of Contents", comment: "help viewer : table of contents button tooltip")
    private static let forwardTitle = NSLocalizedString("Show the next page", comment: "help viewer : forward button tooltip")
}

/// NSSearchField wrapper: SwiftUI has no equivalent of `sendsWholeSearchString`,
/// which is what makes the MySQL target search incrementally while the page and
/// web targets only search on Return. Borderless and unbezelled: the Claude field
/// chrome around it draws the field, and its accent outline follows `isFocused`.
struct SAHelpSearchField: NSViewRepresentable {

    @Binding var text: String
    /// Whether the field (or its field editor) is the window's first responder.
    @Binding var isFocused: Bool
    /// Names the current search target, tying the field to the target selector.
    var placeholder: String
    var sendsWholeSearchString: Bool
    /// Changing this value moves the keyboard focus into the field and selects its text.
    var focusRequest: Int
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> SAHelpSearchFieldView {
        let searchField = SAHelpSearchFieldView()
        searchField.font = .systemFont(ofSize: 12)
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.searchFieldAction(_:))
        let coordinator = context.coordinator
        searchField.onFocusChange = { focused in
            if coordinator.parent.isFocused != focused {
                coordinator.parent.isFocused = focused
            }
        }
        return searchField
    }

    func updateNSView(_ nsView: SAHelpSearchFieldView, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        (nsView.cell as? NSSearchFieldCell)?.sendsWholeSearchString = sendsWholeSearchString

        if context.coordinator.handledFocusRequest != focusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            // The window may not be attached yet on the very first update.
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                nsView.selectText(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {

        var parent: SAHelpSearchField
        /// nil until the field has been focused once: the legacy XIB made the
        /// search field the window's initialFirstResponder.
        var handledFocusRequest: Int?

        init(_ parent: SAHelpSearchField) {
            self.parent = parent
        }

        /// Keeps the bound text in sync while typing, so ⌘G and the target
        /// selector always see what the field currently shows — the legacy code
        /// read `-[NSSearchField stringValue]` directly for the same reason.
        func controlTextDidChange(_ obj: Notification) {
            guard let searchField = obj.object as? NSSearchField else { return }
            parent.text = searchField.stringValue
        }

        @objc func searchFieldAction(_ sender: NSSearchField) {
            parent.text = sender.stringValue
            parent.onSubmit()
        }
    }
}

/// The help viewer's search field, reporting when it gains or loses the keyboard
/// focus: the window's first responder is the field itself, or — while it is being
/// edited — the field editor it delegates to.
final class SAHelpSearchFieldView: NSSearchField {

    override class var cellClass: AnyClass? {
        get { SAHelpSearchFieldCell.self }
        set {}
    }

    /// Called with the new state whenever the focus moves into or out of the field.
    var onFocusChange: ((Bool) -> Void)?

    private var hasFocus = false
    private var firstResponderObservation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        firstResponderObservation = window?.observe(\.firstResponder, options: [.initial, .new]) { [weak self] _, _ in
            // Read on the next turn: focusing the field passes through the field
            // itself and then the field editor, whose delegate is set only after
            // it has become first responder.
            DispatchQueue.main.async { self?.updateFocus() }
        }
        if window == nil {
            updateFocus()
        }
    }

    private func updateFocus() {
        let responder = window?.firstResponder
        let focused = responder === self || (responder as? NSText)?.delegate === self
        guard focused != hasFocus else { return }
        hasFocus = focused
        onFocusChange?(focused)
    }
}

/// An unbezelled search field cell draws its text between the magnifier and the
/// cancel button but hands the field editor its whole frame, so typed text would
/// run under the magnifier: editing gets the same text rect as drawing.
final class SAHelpSearchFieldCell: NSSearchFieldCell {

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
}
