//
//  SABundleHTMLOutputView.swift
//  Sequel Ace
//
//  Created as part of the WebView to WKWebView migration.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import SwiftUI
import WebKit

/// Root SwiftUI view of the bundle HTML output window: a full-size web view
/// driven by the window controller through SAWebViewModel, on the paper (which
/// shows through wherever an HTML page the window was handed paints no
/// background; remote pages draw their own).
struct SABundleHTMLOutputView: View {

    @ObservedObject var model: SAWebViewModel

    /// Set only for child windows created via WebKit's createWebViewWith callback.
    var externalConfiguration: WKWebViewConfiguration?

    var body: some View {
        SAWebView(model: model, externalConfiguration: externalConfiguration)
            .frame(minWidth: 50, minHeight: 50)
            .background(Color(nsColor: SAClaudeHintCardPalette.currentPaper().surface))
    }
}
