//
//  SAClaudeSettingsStore.swift
//  Sequel Ace
//
//  The Settings window's defaults, as one observable store per window. A view
//  binds a control through a stable key path — `$store[bool: key]`,
//  `$store[number: key, step: 1]` — never a closure-built Binding (AGENTS.md).
//
//  Reads come from the controller's own defaults (so a never-set key reads its
//  registered default); writes go through `controller.values`, the path a XIB
//  binding to the shared user defaults controller takes, so every
//  NSUserDefaultsController binding and `values.<key>` observer fires as it
//  did when the Preferences XIB wrote the key — and so do UserDefaults KVO and
//  didChangeNotification (the controller applies immediately). The store
//  holds only the controller, so it cannot read one defaults object and write
//  another.
//
//  It republishes only when one of its keys changes (by KVO on each key of the
//  catalog — keys must not contain ".", which KVO reads as a key path; a test
//  checks the catalog's), however the change was made — a control, a menu item, another
//  window, a pane controller — so window-frame autosaves and other writes to
//  the same defaults don't re-render the window. Main thread.
//
//  App + Unit Tests targets (no SwiftUI here; the views derive the bindings).
//

import AppKit
import Combine

@MainActor
final class SAClaudeSettingsStore: NSObject, ObservableObject {

    /// Declared (the store has no `@Published` property) and nonisolated, so the KVO callback can send on it.
    nonisolated let objectWillChange = ObservableObjectPublisher()

    let controller: NSUserDefaultsController
    /// The keys whose changes republish the store.
    let keys: Set<String>

    var defaults: UserDefaults { controller.defaults }

    /// `controller` defaults to the app's shared controller (`UserDefaults.standard`); `keys` to every key a catalog
    /// row writes. A harness or test passes a controller over a scratch suite.
    init(controller: NSUserDefaultsController = .shared, keys: [String] = SAClaudeSettingsCatalog.allKeys) {
        self.controller = controller
        self.keys = Set(keys)
        observedDefaults = controller.defaults
        super.init()
        for key in self.keys {
            observedDefaults.addObserver(self, forKeyPath: key, options: [], context: Self.context)
        }
    }

    deinit {
        for key in keys { observedDefaults.removeObserver(self, forKeyPath: key, context: Self.context) }
    }

    // MARK: Values

    subscript(bool key: String) -> Bool {
        get { defaults.bool(forKey: key) }
        set { write(newValue, forKey: key) }
    }

    subscript(int key: String) -> Int {
        get { defaults.integer(forKey: key) }
        set { write(newValue, forKey: key) }
    }

    subscript(double key: String) -> Double {
        get { defaults.double(forKey: key) }
        set { write(newValue, forKey: key) }
    }

    /// A missing string reads as empty.
    subscript(string key: String) -> String {
        get { defaults.string(forKey: key) ?? "" }
        set { write(newValue, forKey: key) }
    }

    /// A number field's value: read as a double, written as an integer for a whole-step field and a double for a
    /// tenths field (`SAClaudeSettingsValues.storedValue`), as the XIB formatters stored them.
    subscript(number key: String, step step: Double) -> Double {
        get { defaults.double(forKey: key) }
        set { write(SAClaudeSettingsValues.storedValue(newValue, step: step), forKey: key) }
    }

    /// Sets `values.<key>` on the controller (KVC on its values proxy), which writes the defaults.
    func write(_ value: Any?, forKey key: String) {
        (controller.values as AnyObject).setValue(value, forKey: key)
    }

    /// Whether `row` is enabled now (a dependent with `disabledWhenParentOff` follows its parent's switch).
    func isEnabled(_ row: SAClaudeSettingRow) -> Bool {
        SAClaudeSettingsCatalog.isEnabled(row) { defaults.bool(forKey: $0) }
    }

    // MARK: Observing

    /// A fixed address that tells this store's KVO registrations apart.
    private nonisolated(unsafe) static let context = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    /// The defaults the observers were added to (kept so `deinit` doesn't touch main-actor state).
    private nonisolated(unsafe) let observedDefaults: UserDefaults

    override nonisolated func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard context == Self.context else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
        }
    }
}
