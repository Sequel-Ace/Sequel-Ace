//
//  SAClaudeSettingsColours.swift
//  Sequel Ace
//
//  Settings ▸ Appearance's colour rows, drawn with the Claude kit over the editor colours' model
//  (SAClaudeEditorColoursSettings, SAClaudeEditorColoursSection.swift — behaviour unchanged): the accent well + Reset to
//  clay (Look), and the "Editor and grid colours" section — Colours (Match appearance / Custom, with the Light/Dark
//  preview tiles while matching), Start from a theme (pill + ⋯ with the Query Editor pane's theme actions) and the 11
//  colours, both shown only while Custom, as the Customise half of the old section showed them.
//
//  One model per Settings window (SAClaudeSettingsColoursModel), so the colour rows and the accent well share the one
//  colour-panel hand-off. App target only.
//

import AppKit
import SwiftUI

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

// MARK: - Model per window

/// Makes the window's editor colours model on first use, wired to the Query Editor pane's theme code
/// (SPEditorPreferencePane: -confirmDiscardUnsavedTheme, -saveAsColorScheme:, -importColorScheme:, -exportColorScheme:,
/// -editThemeList:, its themes folder), as SPEditorPreferencePane -preferencePaneView used to wire the old section.
@MainActor
final class SAClaudeSettingsColoursModel {
    private var settings: SAClaudeEditorColoursSettings?

    func settings(for controller: SPPreferenceController?) -> SAClaudeEditorColoursSettings {
        if let settings { return settings }
        let pane: SPEditorPreferencePane? = controller?.editorPreferencePane
        let made = SAClaudeEditorColoursSettings(
            themesDirectory: pane?.themesDirectory ?? "",
            confirmDiscardUnsaved: { [weak pane] in pane?.confirmDiscardUnsavedTheme() ?? false },
            saveAs: { [weak pane] in pane?.saveAsColorScheme(nil) },
            importTheme: { [weak pane] in pane?.importColorScheme(nil) },
            exportTheme: { [weak pane] in pane?.exportColorScheme(nil) },
            editThemeList: { [weak pane] in pane?.editThemeList(nil) })
        settings = made
        return made
    }
}

// MARK: - Look ▸ Accent colour

/// The accent row's control: the minimal colour well, then Reset to clay (disabled while the accent is clay).
struct SAClaudeSettingsAccentControl: View {
    @ObservedObject var settings: SAClaudeEditorColoursSettings

    var body: some View {
        HStack(spacing: 8) {
            SAClaudeAccentWell(colour: settings.accent, onChange: settings.setAccent,
                               willActivate: settings.accentWellWillActivate) { [weak settings] well in settings?.accentWell = well }
                .frame(width: 40, height: 24)
            Button(NSLocalizedString("Reset to clay", comment: "Preferences > Query Editor: puts the accent colour back to the default clay"),
                   action: settings.resetAccent)
                .buttonStyle(SAClaudeSettingsPillButtonStyle())
                .disabled(!settings.accentIsStored)
        }
        .fixedSize()
        // The pane going away ends the accent well's use of the shared colour panel.
        .onDisappear { settings.deactivateAccentWell() }
    }
}

// MARK: - Editor and grid colours

/// The section: heading + card; while the colours match the appearance only the Colours row shows. The theme list is
/// re-read when the pane appears and after a sheet (Edit theme list, Save as) ends, since those change theme files
/// without a defaults write.
struct SAClaudeSettingsColoursSection: View {
    let context: SAClaudeSettingsSectionContext
    @ObservedObject var settings: SAClaudeEditorColoursSettings

    var body: some View {
        let ids = SAClaudeSettingsRules.colourSectionRowIDs(context.section.rows.map(\.id), followsAppearance: settings.followsMacOS)
        let rows = context.section.rows.filter { ids.contains($0.id) }
        VStack(alignment: .leading, spacing: SAClaudeSettingsMetrics.sectionTitleGap) {
            context.heading
            SAClaudeSettingsCard {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SAClaudeSettingsDivider() }
                    context.row(row)
                }
            }
        }
        .onAppear { settings.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification)) { _ in settings.refresh() }
    }
}

/// Colours: Match appearance / Custom; while matching, the bundled Claude Light / Dark previews under the row.
struct SAClaudeSettingsColourModeRow: View {
    let context: SAClaudeSettingsRowContext
    @ObservedObject var settings: SAClaudeEditorColoursSettings

    private static let light = SAClaudeEditorColoursSettings.bundledThemeColours("Claude Light")
    private static let dark = SAClaudeEditorColoursSettings.bundledThemeColours("Claude Dark")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            context.standardRow {
                SAClaudePopUpPill(titles: [localized("ClaudeSettings.editorColours.option.matchAppearance"),
                                           localized("ClaudeSettings.editorColours.option.custom")],
                                  selectedIndex: settings.followsMacOS ? 0 : 1,
                                  accessibilityLabel: localized(context.row.nameKey)) { index in
                    let follows = index == 0
                    // The pop-up reports a re-pick of the current item too; the old segmented control didn't.
                    if follows != settings.followsMacOS { settings.modeSetting = follows }
                }
                .fixedSize()
            }
            if settings.followsMacOS {
                HStack(spacing: 10) {
                    SAClaudeSettingsThemeTile(title: NSLocalizedString("Light", comment: "Preferences > Query Editor: caption of the light-mode theme preview"),
                                              colours: Self.light)
                    SAClaudeSettingsThemeTile(title: NSLocalizedString("Dark", comment: "Preferences > Query Editor: caption of the dark-mode theme preview"),
                                              colours: Self.dark)
                }
                .padding(.horizontal, SAClaudeSettingsMetrics.rowHorizontalPadding)
                .padding(.bottom, 12)
            }
        }
    }
}

/// Start from a theme: the theme pill (a missing file shows "Name (missing)") and the ⋯ menu of theme actions.
struct SAClaudeSettingsStartFromControl: View {
    let context: SAClaudeSettingsRowContext
    @ObservedObject var settings: SAClaudeEditorColoursSettings

    var body: some View {
        let entries = settings.startFromEntries()
        let current = settings.startFromSetting
        HStack(spacing: 4) {
            SAClaudePopUpPill(titles: entries.map(settings.displayName),
                              selectedIndex: entries.firstIndex(of: current) ?? 0,
                              accessibilityLabel: localized(context.row.nameKey), maxWidth: 220) { index in
                guard entries.indices.contains(index) else { return }
                // Asks first when the colours are unsaved; a refusal re-selects the stored theme.
                settings.startFromSetting = entries[index]
            }
            .fixedSize()
            SAClaudeSettingsMenuButton(accessibilityLabel: localized("ClaudeSettings.startFromTheme.actions"), items: [
                .init(NSLocalizedString("Save as theme…", comment: "Preferences > Query Editor > Customise: save the current colours as a theme file"), settings.saveAs),
                .init(NSLocalizedString("Import theme…", comment: "Preferences > Query Editor > Customise: import a theme file"), settings.importTheme),
                .init(NSLocalizedString("Export current theme…", comment: "Preferences > Query Editor > Customise: export the current colours as a theme file"), settings.exportTheme),
                .separator,
                .init(NSLocalizedString("Edit theme list…", comment: "Preferences > Query Editor > Customise: rename, duplicate or remove theme files"), settings.editThemeList),
            ])
        }
    }
}

/// The 11 colours: the row, then the colour list on the editor's own background, each line in its colour (Background,
/// Query Background and Selection in the text colour, the last two filled with their own), clicking one opens the
/// shared colour panel for it.
struct SAClaudeSettingsColourListRow: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let context: SAClaudeSettingsRowContext
    @ObservedObject var settings: SAClaudeEditorColoursSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            context.standardRow { EmptyView() }
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            VStack(spacing: 0) {
                ForEach(SAClaudeEditorColourList.rows, id: \.key) { row in
                    Button { settings.editColour(row.key) } label: {
                        HStack {
                            Text(row.label)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color(nsColor: settings.labelColour(for: row.key)))
                            Spacer(minLength: 8)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color(nsColor: settings.colours[row.key] ?? .clear))
                                .frame(width: 24, height: 14)
                                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(palette.hairline, lineWidth: 1))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(settings.rowFill(for: row.key).map { Color(nsColor: $0) } ?? Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SAClaudeBareButtonStyle())
                    .accessibilityLabel(Text(String(format: localized("ClaudeSettings.colourList.editColour"), row.label)))
                }
            }
            .padding(.vertical, 4)
            .background(shape.fill(Color(nsColor: settings.colours[SAEditorThemeLoader.backgroundColourKey] ?? .textBackgroundColor)))
            .overlay(shape.strokeBorder(palette.hairline, lineWidth: 1))
            .clipShape(shape)
            .padding(.horizontal, SAClaudeSettingsMetrics.rowHorizontalPadding)
            .padding(.bottom, 12)
        }
    }
}

/// A bundled theme's preview: three lines of SQL in its colours on its background, captioned.
struct SAClaudeSettingsThemeTile: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let title: String
    let colours: [String: NSColor]

    private func colour(_ key: String, _ fallback: NSColor) -> Color { Color(nsColor: colours[key] ?? fallback) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        VStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                (Text("SELECT ").foregroundColor(colour(SAEditorThemeLoader.keywordColourKey, .systemBlue)) + Text("id"))
                Text("FROM t")
                (Text("WHERE s = ") + Text("'a'").foregroundColor(colour(SAEditorThemeLoader.quoteColourKey, .systemGreen)))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(colour(SAEditorThemeLoader.textColourKey, .textColor))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 54)
            .background(shape.fill(colour(SAEditorThemeLoader.backgroundColourKey, .textBackgroundColor)))
            .overlay(shape.strokeBorder(palette.hairline, lineWidth: 1))
            Text(title)
                .font(SAClaudeSettingsMetrics.descriptionFont)
                .foregroundColor(palette.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
    }
}

// MARK: - ⋯ menu button

/// A ghost ⋯ button that opens a menu of actions under itself (the kit has no SwiftUI menu without a bezel).
struct SAClaudeSettingsMenuButton: View {
    struct Item {
        let title: String
        let action: (() -> Void)?

        init(_ title: String, _ action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }

        private init() {
            title = ""
            action = nil
        }

        static let separator = Item()
    }

    let accessibilityLabel: String
    let items: [Item]
    @State private var anchor = SAClaudeSettingsViewAnchor()

    var body: some View {
        Button(action: openMenu) {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(SAClaudeGhostIconButtonStyle())
        .background(SAClaudeSettingsViewAnchor.Probe(anchor: anchor))
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func openMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let target = SAClaudeSettingsMenuTarget()
        for item in items {
            guard let action = item.action else { menu.addItem(.separator()); continue }
            let menuItem = NSMenuItem(title: item.title, action: #selector(SAClaudeSettingsMenuTarget.perform(_:)), keyEquivalent: "")
            menuItem.target = target
            menuItem.representedObject = SAClaudeSettingsMenuTarget.Box(action)
            menu.addItem(menuItem)
        }
        if let view = anchor.view {
            // Under the button, left-aligned with it (popUp keeps `target` alive while the menu is open).
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY + 2 : -2), in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        withExtendedLifetime(target) {}
    }
}

/// Runs a menu item's closure.
final class SAClaudeSettingsMenuTarget: NSObject {
    final class Box: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
    }

    @objc func perform(_ sender: NSMenuItem) {
        (sender.representedObject as? Box)?.action()
    }
}

/// The NSView behind a SwiftUI view, for anchoring an AppKit menu to it.
final class SAClaudeSettingsViewAnchor {
    weak var view: NSView?

    struct Probe: NSViewRepresentable {
        let anchor: SAClaudeSettingsViewAnchor

        func makeNSView(context: Context) -> NSView {
            let view = NSView(frame: .zero)
            anchor.view = view
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            anchor.view = view
        }
    }
}
