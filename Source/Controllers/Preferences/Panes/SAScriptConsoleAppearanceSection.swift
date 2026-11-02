//
//  SAScriptConsoleAppearanceSection.swift
//  Sequel Ace
//
//  Preferences → Query Editor → "Script Output": lets the "Run All as Script"
//  console use its own font and colours instead of following the Query
//  Editor's. Hosted below the pane's XIB view by
//  SAScriptConsoleAppearanceSectionHost (called from SPEditorPreferencePane).
//

import AppKit
import Combine
import ObjectiveC
import SwiftUI

/// Reads and writes the script console appearance defaults for the section,
/// refreshing whenever UserDefaults change (the font panel, the editor's own
/// font and colours, or another window).
final class SAScriptConsoleAppearanceSettings: ObservableObject {

    @Published private(set) var appearance: SAScriptConsoleAppearance
    @Published private(set) var isCustom: Bool

    private let defaults: UserDefaults
    private var defaultsObserver: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = SAScriptConsoleAppearance.resolve(from: defaults)
        isCustom = defaults.bool(forKey: SAScriptConsoleAppearance.useCustomKey)
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    // MARK: - Bindable properties (bound via key paths, see AGENTS.md)

    var useCustom: Bool {
        get { isCustom }
        set {
            SAScriptConsoleAppearance.setUseCustom(newValue, in: defaults)
            refresh()
        }
    }

    var textColor: Color {
        get { Color(nsColor: appearance.textColor) }
        set { store(newValue, current: appearance.textColor, forKey: SAScriptConsoleAppearance.customTextColorKey) }
    }

    var backgroundColor: Color {
        get { Color(nsColor: appearance.backgroundColor) }
        set { store(newValue, current: appearance.backgroundColor, forKey: SAScriptConsoleAppearance.customBackgroundColorKey) }
    }

    // MARK: - Display and actions

    /// e.g. "Menlo 12" or "Menlo Bold 12".
    var fontDescription: String {
        let font = appearance.font
        let size = font.pointSize
        let sizeText = size.rounded() == size ? String(format: "%.0f", size) : String(format: "%.1f", size)
        var name = font.displayName ?? font.fontName
        if let family = font.familyName, name == "\(family) Regular" {
            name = family
        }
        return "\(name) \(sizeText)"
    }

    func resetToEditor() {
        SAScriptConsoleAppearance.copyEditorValuesToCustom(in: defaults)
        refresh()
    }

    func refresh() {
        let newAppearance = SAScriptConsoleAppearance.resolve(from: defaults)
        if newAppearance != appearance { appearance = newAppearance }
        let newIsCustom = defaults.bool(forKey: SAScriptConsoleAppearance.useCustomKey)
        if newIsCustom != isCustom { isCustom = newIsCustom }
    }

    private func store(_ color: Color, current: NSColor, forKey key: String) {
        let nsColor = NSColor(color)
        guard nsColor != current else { return }
        // A SwiftUI-bridged colour may not support secure archiving; fall back
        // to a plain component colour in that case.
        let data = SAArchiving.archivedData(forColor: nsColor)
            ?? nsColor.usingColorSpace(.extendedSRGB).flatMap { SAArchiving.archivedData(forColor: $0) }
        guard let data else { return }
        defaults.set(data, forKey: key)
        refresh()
    }
}

struct SAScriptConsoleAppearanceSection: View {

    @ObservedObject var settings: SAScriptConsoleAppearanceSettings
    let onSelectFont: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(NSLocalizedString("Script Output", comment: "Preferences > Query Editor: section title for the Run All as Script console's appearance"))
                .bold()
            Toggle(NSLocalizedString("Use custom font & colours for script output", comment: "Preferences > Query Editor > Script Output: checkbox to stop the script console following the editor's font and colours"),
                   isOn: $settings.useCustom)
                .toggleStyle(.checkbox)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text(NSLocalizedString("Font", comment: "Preferences > Query Editor > Script Output: label for the script console font"))
                        .gridColumnAlignment(.trailing)
                    HStack(spacing: 8) {
                        Text(settings.fontDescription)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        Button(NSLocalizedString("Select…", comment: "Preferences > Query Editor > Script Output: button that opens the font panel"),
                               action: onSelectFont)
                    }
                }
                GridRow {
                    Text(NSLocalizedString("Text colour", comment: "Preferences > Query Editor > Script Output: label for the script console text colour"))
                    ColorPicker(NSLocalizedString("Text colour", comment: "Preferences > Query Editor > Script Output: label for the script console text colour"),
                                selection: $settings.textColor, supportsOpacity: false)
                        .labelsHidden()
                }
                GridRow {
                    Text(NSLocalizedString("Background colour", comment: "Preferences > Query Editor > Script Output: label for the script console background colour"))
                    ColorPicker(NSLocalizedString("Background colour", comment: "Preferences > Query Editor > Script Output: label for the script console background colour"),
                                selection: $settings.backgroundColor, supportsOpacity: false)
                        .labelsHidden()
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Button(NSLocalizedString("Reset to Editor", comment: "Preferences > Query Editor > Script Output: button that copies the editor's font and colours into the script console settings")) {
                        settings.resetToEditor()
                    }
                }
            }
            .padding(.leading, 20)
            .disabled(!settings.isCustom)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// ObjC entry point: wraps the Query Editor pane's XIB view with the Script
/// Output section below it.
@objc final class SAScriptConsoleAppearanceSectionHost: NSObject {

    private static var containerKey: UInt8 = 0

    /// Returns a container with `xibView` on top and the Script Output section
    /// below. Built once per XIB view and cached on it (the preference
    /// controller asks for the pane view every time the pane is shown). The
    /// container uses Auto Layout so `-[NSWindow resizeForContentView:]`'s
    /// fittingSize includes the section.
    @objc(paneViewWrapping:onSelectFont:)
    static func paneView(wrapping xibView: NSView, onSelectFont: @escaping () -> Void) -> NSView {
        if let cached = objc_getAssociatedObject(xibView, &containerKey) as? NSView {
            return cached
        }

        let section = SAScriptConsoleAppearanceSection(settings: SAScriptConsoleAppearanceSettings(),
                                                       onSelectFont: onSelectFont)
        let hostingView = NSHostingView(rootView: section)
        hostingView.sizingOptions = [.minSize, .intrinsicContentSize]
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        hostingView.setContentCompressionResistancePriority(.required, for: .vertical)

        let xibSize = xibView.frame.size
        let container = NSView(frame: NSRect(x: 0, y: 0,
                                             width: xibSize.width,
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

        // The XIB view holds the container (and the container its subviews) for
        // the preference pane's lifetime, which is the app's.
        objc_setAssociatedObject(xibView, &containerKey, container, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return container
    }
}
