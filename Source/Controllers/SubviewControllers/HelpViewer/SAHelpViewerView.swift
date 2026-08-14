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
/// HelpViewer.xib (navigation, search field, target selector) above a WKWebView.
struct SAHelpViewerView: View {

    @ObservedObject var model: SAHelpViewerModel
    @ObservedObject var webViewModel: SAWebViewModel

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
            .padding(.horizontal, 11)
            .padding(.vertical, 6)

            Divider()

            SAWebView(model: webViewModel, externalConfiguration: webViewConfiguration)
        }
    }

    private var navigationControl: some View {
        ControlGroup {
            Button {
                onNavigate(.back)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack)
            .accessibilityLabel(Self.backTitle)
            .help(Self.backTitle)

            Button {
                onNavigate(.tableOfContents)
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel(Self.tableOfContentsTitle)
            .help(Self.tableOfContentsTitle)

            Button {
                onNavigate(.forward)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward)
            .accessibilityLabel(Self.forwardTitle)
            .help(Self.forwardTitle)
        }
        .frame(width: 104)
    }

    private var searchField: some View {
        SAHelpSearchField(
            text: $model.searchString,
            placeholder: model.target.searchFieldPlaceholder,
            sendsWholeSearchString: model.target.sendsWholeSearchString,
            focusRequest: model.focusSearchFieldRequest,
            onSubmit: onSubmitSearch
        )
        .frame(minWidth: 120, maxWidth: .infinity)
    }

    private var targetSelector: some View {
        Picker("", selection: $model.target) {
            Text(NSLocalizedString("MySQL", comment: "help viewer : search target : mysql help")).tag(SAHelpTarget.mysql)
            Text(NSLocalizedString("Page", comment: "help viewer : search target : current page")).tag(SAHelpTarget.page)
            Text(NSLocalizedString("Web", comment: "help viewer : search target : online documentation")).tag(SAHelpTarget.web)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 152)
        // The legacy XIB explained this control with per-segment tooltips; SwiftUI
        // has no per-segment equivalent, so one tooltip covers all three.
        .accessibilityLabel(NSLocalizedString("Search target", comment: "help viewer : search target selector accessibility label"))
        .help(SAHelpTarget.selectorHelpText)
    }

    private static let backTitle = NSLocalizedString("Show the previous page", comment: "help viewer : back button tooltip")
    private static let tableOfContentsTitle = NSLocalizedString("MySQL Table of Contents", comment: "help viewer : table of contents button tooltip")
    private static let forwardTitle = NSLocalizedString("Show the next page", comment: "help viewer : forward button tooltip")
}

/// NSSearchField wrapper: SwiftUI has no equivalent of `sendsWholeSearchString`,
/// which is what makes the MySQL target search incrementally while the page and
/// web targets only search on Return.
struct SAHelpSearchField: NSViewRepresentable {

    @Binding var text: String
    /// Names the current search target, tying the field to the target selector.
    var placeholder: String
    var sendsWholeSearchString: Bool
    /// Changing this value moves the keyboard focus into the field and selects its text.
    var focusRequest: Int
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.searchFieldAction(_:))
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
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
