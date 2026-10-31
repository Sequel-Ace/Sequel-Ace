//
//  SAEditorThemeAppearanceSection.swift
//  Sequel Ace
//
//  Preferences ▸ Query Editor: "Match system appearance" with a Light and a
//  Dark theme picker, attached below the pane's XIB view. Its state is
//  SAEditorThemeAppearanceSettings. App target only.
//

import AppKit
import SwiftUI

struct SAEditorThemeAppearanceSection: View {
    @ObservedObject var settings: SAEditorThemeAppearanceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: SASpacing.small) {
            Divider()
            Text(NSLocalizedString("Theme Appearance", comment: "Preferences > Query Editor: section title for choosing editor themes per light/dark appearance"))
                .bold()
            Toggle(NSLocalizedString("Match system appearance", comment: "Preferences > Query Editor > Theme Appearance: checkbox making the editor theme follow light/dark mode"),
                   isOn: $settings.matchesSetting)
                .toggleStyle(.checkbox)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: SASpacing.xSmall, verticalSpacing: SASpacing.xSmall) {
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
            .padding(.leading, SASpacing.large)
            .disabled(!settings.matches)
        }
        .padding(.horizontal, SASpacing.large)
        .padding(.bottom, SASpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Theme files can change while the pane is hidden; the pane's own changes post themeListDidChange.
        .onAppear { settings.reloadThemeNames() }
    }
}

/// ObjC entry point: wraps the Query Editor pane's XIB view in a container with
/// the Theme Appearance section below it. The container is built once per XIB
/// view and cached on it.
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
