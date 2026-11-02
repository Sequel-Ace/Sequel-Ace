//
//  SARecordViewPanelHostStub.swift
//  Unit Tests
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// Unit Tests stand-in for the app's `SARecordViewPanelHost` (Source/Views/SAClaudeRecordPanel.swift), whose SwiftUI
/// panel draws with the app-only Claude style kit. `SARecordViewController`'s tests exercise the overlay, the focus
/// handling and the key routing, which only need a view that can take the keyboard.
@MainActor
final class SARecordViewPanelHost {
    let view: NSView = SARecordViewPanelStubView()

    init(model: SARecordViewModel) {}

    func style(_ container: NSView) {}
}

private final class SARecordViewPanelStubView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
