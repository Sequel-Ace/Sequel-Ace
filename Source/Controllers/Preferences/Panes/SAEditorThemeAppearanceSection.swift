//
//  SAEditorThemeAppearanceSection.swift
//  Sequel Ace
//
//  Settings → Query Editor: "Match system appearance" with a Light and a Dark
//  theme picker. Attached below the pane's XIB view the same way the Script
//  Output section is.
//

import AppKit
import SwiftUI

/// The section's state, read from and written to the user defaults.
final class SAEditorThemeAppearanceSettings: ObservableObject {
    private let defaults: UserDefaults
    private let themesDirectory: String
    private let confirmDiscardUnsaved: () -> Bool
    private let onThemeApplied: () -> Void
    private var observers: [NSObjectProtocol] = []

    @Published private(set) var themeNames: [String] = []
    @Published private(set) var matches = false
    @Published private(set) var lightTheme = ""
    @Published private(set) var darkTheme = ""

    init(defaults: UserDefaults = .standard, themesDirectory: String,
         confirmDiscardUnsaved: @escaping () -> Bool, onThemeApplied: @escaping () -> Void) {
        self.defaults = defaults
        self.themesDirectory = themesDirectory
        self.confirmDiscardUnsaved = confirmDiscardUnsaved
        self.onThemeApplied = onThemeApplied
        refresh()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            self?.refresh()
        })
        observers.append(center.addObserver(forName: SAEditorAppearanceThemeSwitcher.themeDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onThemeApplied()
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func refresh() {
        let names = SAEditorAppearanceThemeSwitcher.availableThemeNames(in: themesDirectory)
        if names != themeNames { themeNames = names }
        let newMatches = defaults.bool(forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
        if newMatches != matches { matches = newMatches }
        let newLight = defaults.string(forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey) ?? ""
        if newLight != lightTheme { lightTheme = newLight }
        let newDark = defaults.string(forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey) ?? ""
        if newDark != darkTheme { darkTheme = newDark }
    }

    // Read-write accessors the view binds to through `$settings.…` (no closure-built Bindings).
    var matchesSetting: Bool {
        get { matches }
        set {
            if newValue, !confirmDiscardUnsaved() {
                // Nothing in the model changed, so SwiftUI would not re-render and the
                // checkbox would keep its flipped state. Republish after the toggle has
                // finished writing so the body re-reads `matches` (false) and pushes it back.
                DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
                return
            }
            defaults.set(newValue, forKey: SAEditorAppearanceThemeSwitcher.matchesAppearanceKey)
            if newValue { SAEditorAppearanceThemeSwitcher.shared.applyForCurrentAppearance() }
            refresh()
        }
    }

    var lightSetting: String {
        get { SAEditorAppearanceThemeSwitcher.canonicalName(lightTheme, in: themeNames) }
        set { choose(newValue, forKey: SAEditorAppearanceThemeSwitcher.lightThemeKey) }
    }

    var darkSetting: String {
        get { SAEditorAppearanceThemeSwitcher.canonicalName(darkTheme, in: themeNames) }
        set { choose(newValue, forKey: SAEditorAppearanceThemeSwitcher.darkThemeKey) }
    }

    private func choose(_ name: String, forKey key: String) {
        defaults.set(name, forKey: key)
        SAEditorAppearanceThemeSwitcher.shared.applyForCurrentAppearance()
        refresh()
    }

    func entries(selected: String) -> [String] {
        SAEditorAppearanceThemeSwitcher.pickerNames(available: themeNames, selected: selected)
    }

    func displayName(_ name: String) -> String {
        themeNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
            ? name
            : String(format: NSLocalizedString("%@ (missing)", comment: "Preferences > Query Editor > Appearance: a chosen theme whose file no longer exists"), name)
    }
}

struct SAEditorThemeAppearanceSection: View {
    @ObservedObject var settings: SAEditorThemeAppearanceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(NSLocalizedString("Theme Appearance", comment: "Preferences > Query Editor: section title for choosing editor themes per light/dark appearance"))
                .bold()
            Toggle(NSLocalizedString("Match system appearance", comment: "Preferences > Query Editor > Theme Appearance: checkbox making the editor theme follow light/dark mode"),
                   isOn: $settings.matchesSetting)
                .toggleStyle(.checkbox)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text(NSLocalizedString("Light theme", comment: "Preferences > Query Editor > Theme Appearance: label for the theme used in light mode"))
                        .gridColumnAlignment(.trailing)
                    Picker(NSLocalizedString("Light theme", comment: "Preferences > Query Editor > Theme Appearance: label for the theme used in light mode"),
                           selection: $settings.lightSetting) {
                        ForEach(settings.entries(selected: settings.lightSetting), id: \.self) { Text(settings.displayName($0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240, alignment: .leading)
                }
                GridRow {
                    Text(NSLocalizedString("Dark theme", comment: "Preferences > Query Editor > Theme Appearance: label for the theme used in dark mode"))
                    Picker(NSLocalizedString("Dark theme", comment: "Preferences > Query Editor > Theme Appearance: label for the theme used in dark mode"),
                           selection: $settings.darkSetting) {
                        ForEach(settings.entries(selected: settings.darkSetting), id: \.self) { Text(settings.displayName($0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240, alignment: .leading)
                }
            }
            .padding(.leading, 20)
            .disabled(!settings.matches)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The theme list can change (Edit Theme List) without any defaults write.
        .onAppear { settings.refresh() }
    }
}

/// ObjC entry point: wraps the Query Editor pane's XIB view with the Theme
/// Appearance section below it (same container approach as the Script Output
/// section's host, repeated so this layer stays independent of that branch).
@objc final class SAEditorThemeAppearanceSectionHost: NSObject {

    private static var containerKey: UInt8 = 0

    @objc(paneViewWrapping:themesDirectory:confirmDiscardUnsaved:onThemeApplied:)
    static func paneView(wrapping xibView: NSView, themesDirectory: String,
                         confirmDiscardUnsaved: @escaping () -> Bool,
                         onThemeApplied: @escaping () -> Void) -> NSView {
        if let cached = objc_getAssociatedObject(xibView, &containerKey) as? NSView {
            return cached
        }
        let settings = SAEditorThemeAppearanceSettings(themesDirectory: themesDirectory,
                                                       confirmDiscardUnsaved: confirmDiscardUnsaved,
                                                       onThemeApplied: onThemeApplied)
        let hostingView = NSHostingView(rootView: SAEditorThemeAppearanceSection(settings: settings))
        hostingView.sizingOptions = [.minSize, .intrinsicContentSize]
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        hostingView.setContentCompressionResistancePriority(.required, for: .vertical)

        let xibSize = xibView.frame.size
        let container = NSView(frame: NSRect(x: 0, y: 0, width: xibSize.width,
                                             height: xibSize.height + hostingView.fittingSize.height))
        container.translatesAutoresizingMaskIntoConstraints = false
        xibView.removeFromSuperview()
        xibView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(xibView)
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            xibView.topAnchor.constraint(equalTo: container.topAnchor),
            xibView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            xibView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: xibView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        objc_setAssociatedObject(xibView, &containerKey, container, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return container
    }
}
