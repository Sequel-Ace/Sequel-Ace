//
//  SAAboutWindowController.swift
//  Sequel Ace
//
//  Created as part of the XIB to SwiftUI migration.
//  Copyright © 2024-2026 Sequel-Ace. All rights reserved.
//

import SwiftUI

@objc final class SAAboutWindowController: NSWindowController {

    @objc convenience init(delegate: NSWindowDelegate?) {
        let hostingController = NSHostingController(rootView: SAAboutView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Sequel Ace"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.delegate = delegate
        self.init(window: window)
    }
}
