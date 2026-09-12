//
//  SAAppearancePreference.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.09.09.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import AppKit

/// Applies the "Appearance" preference (system / light / dark) to the app,
/// skipping redundant work: `NSUserDefaultsDidChangeNotification` fires for
/// every defaults write anywhere in the app, and re-applying an unchanged
/// appearance on each of them added up to seconds of main-thread work in
/// profiling. The applied selection is cached, so only real changes reach
/// `NSApp`.
@objc public final class SAAppearancePreference: NSObject {
    /// Keep in sync with `SPAppearance` in SPConstants.m - inlined as a
    /// literal because this file is also compiled into the Unit Tests
    /// target, which has no bridging header for project ObjC globals
    /// (the established workaround, see AGENTS.md).
    private static let preferenceKey = "Appearance"
    /// Sentinel distinct from every valid selection so the first call applies.
    private static var lastAppliedSelection = Int.min

    /// The appearance for a preference selection: 1 = Aqua, 2 = Dark Aqua,
    /// anything else follows the system (`nil`).
    static func appearanceName(for selection: Int) -> NSAppearance.Name? {
        switch selection {
        case 1: return .aqua
        case 2: return .darkAqua
        default: return nil
        }
    }

    /// Whether `selection` differs from the last applied one; records it as
    /// applied when it does.
    static func shouldApply(_ selection: Int) -> Bool {
        guard selection != lastAppliedSelection else { return false }
        lastAppliedSelection = selection
        return true
    }

    /// Test hook: forget the cached selection.
    static func resetForTesting() {
        lastAppliedSelection = .min
    }

    /// Reads the preference and pushes it to `NSApp` when it changed.
    /// Main thread only.
    @objc public static func applyIfChanged() {
        let selection = UserDefaults.standard.integer(forKey: preferenceKey)
        guard shouldApply(selection) else { return }
        NSApp.appearance = appearanceName(for: selection).flatMap { NSAppearance(named: $0) }
    }
}
