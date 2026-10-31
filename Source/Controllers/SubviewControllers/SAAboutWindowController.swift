//
//  SAAboutWindowController.swift
//  Sequel Ace
//
//  Created as part of the XIB to SwiftUI migration.
//  Copyright © 2024-2026 Sequel-Ace. All rights reserved.
//

import SwiftUI

@objc final class SAAboutWindowController: NSWindowController {

    /// The Claude kit's colours for the About page and the license sheet (the sheets' colours, from the editor theme).
    private let palette = SAClaudeSwiftUIPalette(source: .app)

    @objc convenience init(delegate: NSWindowDelegate?) {
        self.init(window: nil)
        let hostingController = NSHostingController(rootView: SAAboutView().environmentObject(palette))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Sequel Ace"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.delegate = delegate
        self.window = window

        // The window's surface and appearance follow the palette, which follows the editor theme and the accent.
        themeChanged()
        SAClaudeThemeWatcher.observe(self) { controller in MainActor.assumeIsolated { controller.themeChanged() } }
        SAClaudeAccent.observe(self) { controller in MainActor.assumeIsolated { controller.themeChanged() } }
    }

    private func themeChanged() {
        guard let window else { return }
        SAClaudeRareWindowChrome.apply(to: window, palette: .current())
    }
}
