//
//  SAClaudeSettingsPanes.swift
//  Sequel Ace
//
//  The Settings window's bespoke rows: the controls of the custom rows (`SAClaudeSettingCustom`), the dynamic pills
//  (favourites, encodings, SSH config, known hosts) and the plain-looking rows whose control calls pane code (the MCP
//  port), plus any row or section that needs more than a control — registered with each window's
//  SAClaudeSettingsViewRegistry (see SAClaudeSettingsWindow.swift). Until a row is registered the window shows a
//  placeholder for its control.
//
//  Plain rows (switches, numbers, fixed pills, text) need nothing here: they bind to their keys through the window's
//  SAClaudeSettingsStore, which writes through NSUserDefaultsController so every binding, KVO and
//  didChangeNotification observer fires as the XIB's bindings made them — the appearance (SPAppController
//  -defaultsChanged:), analytics consent (same), the title-bar tint (SPWindowController's defaults observer), the
//  editor's and grids' KVO. None of the plain rows in Appearance, Startup, Tables, Query editor, Safety, Console or
//  Updates had pane code on change (Preferences.xib's only actions on them are steppers feeding their own field).
//
//  App target only.
//

import AppKit
import Combine
import SwiftUI

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum SAClaudeSettingsPanes {

    /// Called once per Settings window, before its content is first drawn.
    @MainActor static func register(in registry: SAClaudeSettingsViewRegistry) {
        let colours = SAClaudeSettingsColoursModel()
        let encodings = SAClaudeSettingsEncodings()

        // Appearance ▸ Look: the accent well and Reset to clay share the colours model's colour-panel hand-off.
        registry.registerControl(for: .accent) { context in
            SAClaudeSettingsColoursScope(model: colours, host: context.host) { SAClaudeSettingsAccentControl(settings: $0) }
        }
        // Appearance ▸ Editor and grid colours.
        registry.registerSection("editorGridColours") { context in
            SAClaudeSettingsColoursScope(model: colours, host: context.host) {
                SAClaudeSettingsColoursSection(context: context, settings: $0)
            }
        }
        registry.registerRow("editorColours") { context in
            SAClaudeSettingsColoursScope(model: colours, host: context.host) {
                SAClaudeSettingsColourModeRow(context: context, settings: $0)
            }
        }
        registry.registerControl(for: .startFromTheme) { context in
            SAClaudeSettingsColoursScope(model: colours, host: context.host) {
                SAClaudeSettingsStartFromControl(context: context, settings: $0)
            }
        }
        registry.registerRow("colourList") { context in
            SAClaudeSettingsColoursScope(model: colours, host: context.host) {
                SAClaudeSettingsColourListRow(context: context, settings: $0)
            }
        }
        // Appearance ▸ Fonts.
        registry.registerControl(for: .editorFont) { context in
            SAClaudeSettingsFontControl(kind: .editor, host: context.host, accessibilityName: localized(context.row.nameKey))
        }
        registry.registerControl(for: .resultsFont) { context in
            SAClaudeSettingsFontControl(kind: .results, host: context.host, accessibilityName: localized(context.row.nameKey))
        }

        // Startup and connections.
        registry.registerControl(forDynamicSource: "favorites") { context in
            SAClaudeSettingsFavouritePill(row: context.row)
        }
        registry.registerControl(forDynamicSource: "encodings") { context in
            SAClaudeSettingsEncodingPill(row: context.row, encodings: encodings, host: context.host)
        }

        // Tables and data.
        registry.registerControl(for: .reloadAfterSaving) { _ in
            SAClaudeSettingsReloadSwitches()
        }

        // Query editor: the delay's warning at 0.
        registry.registerRow("autoComplete") { context in
            SAClaudeSettingsAutoCompleteRow(context: context)
        }

        // Updates and privacy: the App Store gate (private builds have no GitHub updater either).
        registry.registerRow("checkUpdates") { context in
            SAClaudeSettingsUpdatesRow(context: context, isAppStore: !Bundle.main.offersGitHubUpdates)
        }

        // SSH and security, MCP server (SAClaudeSettingsSecurity.swift).
        SAClaudeSettingsSecurityPanes.register(in: registry)
    }
}

// MARK: - Shared pieces

/// Hands the window's colours model (made on first use from the preference controller's editor pane) to `content`.
struct SAClaudeSettingsColoursScope<Content: View>: View {
    let model: SAClaudeSettingsColoursModel
    weak var host: SAClaudeSettingsWindowHost?
    @ViewBuilder let content: (SAClaudeEditorColoursSettings) -> Content

    var body: some View {
        content(model.settings(for: host?.controller))
    }
}

/// A small action in a row, drawn like the choice pills beside it: the hover fill, a 7pt radius, 24pt high (`.form`),
/// the title at 12pt in the text colour; the selected fill pressed; 40% disabled ("Change…", "Reset", "Reset to clay").
struct SAClaudeSettingsPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        @EnvironmentObject var palette: SAClaudeSwiftUIPalette
        @Environment(\.isEnabled) var isEnabled
        let configuration: ButtonStyleConfiguration

        var body: some View {
            let size = SAClaudeControlSize.form
            let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
            configuration.label
                .font(Font(size.popUpFont))
                .foregroundColor(palette.text)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: size.popUpHeight)
                .background(shape.fill(configuration.isPressed && isEnabled ? palette.selected : palette.hover))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.checkboxDisabledOpacity)
        }
    }
}

/// A muted line under a row (inside its card), lined up with the row's name: a note or a warning about its value.
struct SAClaudeSettingsRowNote: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let row: SAClaudeSettingRow
    let text: String

    var body: some View {
        Text(text)
            .font(SAClaudeSettingsMetrics.descriptionFont)
            .foregroundColor(palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, row.parentID == nil ? 0 : SAClaudeSettingsMetrics.dependentIndent)
            .padding(.horizontal, SAClaudeSettingsMetrics.rowHorizontalPadding)
            .padding(.top, -3)
            .padding(.bottom, SAClaudeSettingsMetrics.rowVerticalPadding)
    }
}

// MARK: - Fonts

/// A font row's control: the current font's name and size in mono, "Change…" (the shared font panel through the pane's
/// own action, which points SPPreferenceController's `fontChangeTarget` at this font: SPGeneralPreferencePane
/// -showGlobalResultFontPanel: :85-105 / SPEditorPreferencePane -showCustomQueryFontPanel:), and for the editor font
/// "Reset" (SPEditorPreferencePane -resetSystemFont:, now SF Mono 13 — SAClaudeEditorDefaults.resetEditorFont).
/// The name follows the key live (the store observes both font keys).
struct SAClaudeSettingsFontControl: View {
    enum Kind { case editor, results }

    @EnvironmentObject private var store: SAClaudeSettingsStore
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let kind: Kind
    weak var host: SAClaudeSettingsWindowHost?
    let accessibilityName: String

    static let editorFontKey = "CustomQueryEditorFont"   // SPCustomQueryEditorFont
    static let resultsFontKey = "fontSettings"          // SPGlobalFontSettings

    var body: some View {
        let controller = host?.controller
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(palette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .trailing)
                .padding(.trailing, 4)
                .accessibilityLabel(Text(accessibilityName))
                .accessibilityValue(Text(label))
            Button(localized("ClaudeSettings.ui.changeFont")) { change(controller) }
                .buttonStyle(SAClaudeSettingsPillButtonStyle())
                .disabled(controller == nil)
            if kind == .editor {
                Button(localized("ClaudeSettings.editorFont.reset")) { reset(controller) }
                    .buttonStyle(SAClaudeSettingsPillButtonStyle())
            }
        }
        .fixedSize()
    }

    private var label: String {
        guard let font = currentFont else { return "—" }
        let name = SAClaudeSettingsRules.fontName(postScriptName: font.fontName, displayName: font.displayName,
                                                  isFixedPitch: font.isFixedPitch)
        return SAClaudeSettingsRules.fontLabel(name: name, pointSize: Double(font.pointSize))
    }

    /// The stored font, read without writing: NSUserDefaults +getFont saves the system font when the key is unset, which
    /// must not happen while drawing.
    private var currentFont: NSFont? {
        switch kind {
        case .editor:
            return SAArchiving.font(from: store.defaults.data(forKey: Self.editorFontKey))
        case .results:
            guard let data = store.defaults.data(forKey: Self.resultsFontKey) else {
                return NSFont.systemFont(ofSize: NSFont.systemFontSize)
            }
            if let font = SAArchiving.font(from: data) { return font }
            // The legacy format +getFont still reads: an archived font descriptor.
            if let descriptor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFontDescriptor.self, from: data) {
                return NSFont(descriptor: descriptor, size: 0)
            }
            return NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }
    }

    func change(_ controller: SPPreferenceController?) {
        switch kind {
        case .editor: controller?.editorPreferencePane?.showCustomQueryFontPanel(nil)
        case .results: controller?.generalPreferencePane?.showGlobalResultFontPanel(nil)
        }
    }

    func reset(_ controller: SPPreferenceController?) {
        if let pane = controller?.editorPreferencePane {
            pane.resetSystemFont(nil)
        } else {
            SAClaudeEditorDefaults.resetEditorFont(in: store.defaults)
        }
    }
}

// MARK: - Favourite to select

/// Tells the Settings window's favourite pill that the favourites tree changed. SPGeneralPreferencePane
/// -updateDefaultFavoritePopup calls it; SPConnectionController calls that whenever it adds, edits, moves or deletes a
/// favourite (and makes one the default), so the pill follows exactly when the old pop-up did.
@objc(SAClaudeSettingsFavourites)
final class SAClaudeSettingsFavourites: NSObject {
    static let didChangeNotification = Notification.Name("SAClaudeSettingsFavouritesDidChange")

    @objc static func treeDidChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// The favourites under the tree's root, as the old pop-up walked them (SPGeneralPreferencePane.m:141).
    static func currentTree() -> [SAClaudeSettingsRules.FavouriteNode] {
        guard let root = SPFavoritesController.shared().favoritesTree,
              let top = root.children?.first else { return [] }
        return (top.children ?? []).map(node)
    }

    private static func node(_ treeNode: SPTreeNode) -> SAClaudeSettingsRules.FavouriteNode {
        if treeNode.isGroup {
            let name = (treeNode.representedObject as? SPGroupNode)?.nodeName ?? ""
            return .group(name: name, children: (treeNode.children ?? []).map(node))
        }
        let favourite = (treeNode.representedObject as? SPFavoriteNode)?.nodeFavorite
        let name = favourite?[SPFavoriteNameKey] as? String ?? ""
        let id = (favourite?[SPFavoriteIDKey] as? NSNumber)?.intValue
            ?? (favourite?[SPFavoriteIDKey] as? NSString)?.integerValue ?? 0
        return .favourite(name: name, id: id)
    }
}

/// Favourite to select: "Last used", then the favourites tree (groups as disabled headings, indented). Choosing writes
/// SelectLastFavoriteUsed and DefaultFavorite as SPGeneralPreferencePane -updateDefaultFavorite: did (:70-83). The tree
/// is re-read when the pane appears, whenever SAClaudeSettingsFavourites says it changed and on
/// SPConnectionFavoritesChangedNotification; the selection follows the
/// two keys live (the connection screen's "Make Default" writes them too).
struct SAClaudeSettingsFavouritePill: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore
    let row: SAClaudeSettingRow
    @State private var tree: [SAClaudeSettingsRules.FavouriteNode]?

    static let selectLastUsedKey = "SelectLastFavoriteUsed"   // SPSelectLastFavoriteUsed
    static let defaultFavoriteKey = "DefaultFavorite"         // SPDefaultFavorite

    var body: some View {
        let items = SAClaudeSettingsRules.favouriteMenu(tree ?? SAClaudeSettingsFavourites.currentTree(),
                                                        lastUsedTitle: localized("ClaudeSettings.defaultFavourite.option.lastUsed"),
                                                        noneTitle: localized("ClaudeSettings.defaultFavourite.option.none"))
        let selected = SAClaudeSettingsRules.favouriteSelectedIndex(items, selectLastUsed: store[bool: Self.selectLastUsedKey],
                                                                    defaultFavorite: store[int: Self.defaultFavoriteKey])
        SAClaudePopUpPill(items: items.map(Self.popUpItem), selectedIndex: selected,
                          accessibilityLabel: localized(row.nameKey)) { index in
            guard let choice = SAClaudeSettingsRules.favouriteChoice(items, at: index) else { return }
            store.write(choice.selectLastUsed, forKey: Self.selectLastUsedKey)
            store.write(choice.defaultFavorite, forKey: Self.defaultFavoriteKey)
        }
        .fixedSize()
        .onAppear { tree = SAClaudeSettingsFavourites.currentTree() }
        .onReceive(NotificationCenter.default.publisher(for: SAClaudeSettingsFavourites.didChangeNotification)
                    .receive(on: DispatchQueue.main)) { _ in
            tree = SAClaudeSettingsFavourites.currentTree()
        }
        // Also when a favourite is added, moved or removed anywhere (SPFavoritesController posts it).
        .onReceive(NotificationCenter.default.publisher(for: .SPConnectionFavoritesChanged)
                    .receive(on: DispatchQueue.main)) { _ in
            tree = SAClaudeSettingsFavourites.currentTree()
        }
    }

    private static func popUpItem(_ item: SAClaudeSettingsRules.FavouriteItem) -> SAClaudePopUpItem {
        item.kind == .separator ? .separator
            : SAClaudePopUpItem(item.title, indentationLevel: item.indentation, isEnabled: item.isEnabled)
    }
}

// MARK: - Character set

/// Today's encoding list, read once per window from the General pane's own pop-up (the one bound to
/// values.DefaultEncodingTag in Preferences.xib), so its titles, order, separators and translations stay as they are.
@MainActor
final class SAClaudeSettingsEncodings {
    struct Item {
        let title: String
        /// nil for a separator.
        let tag: Int?
    }

    static let key = "DefaultEncodingTag"   // SPDefaultEncoding

    private var cached: [Item]?

    func items(for controller: SPPreferenceController?) -> [Item] {
        if let cached { return cached }
        guard let view = controller?.generalPreferencePane?.view,
              let popUp = Self.popUp(in: view) else { return [] }
        let items = popUp.itemArray.map { item in
            item.isSeparatorItem ? Item(title: "", tag: nil) : Item(title: item.title, tag: item.tag)
        }
        cached = items
        return items
    }

    private static func popUp(in view: NSView) -> NSPopUpButton? {
        for subview in view.subviews {
            if let popUp = subview as? NSPopUpButton,
               popUp.infoForBinding(.selectedTag)?[.observedKeyPath] as? String == "values.\(key)" {
                return popUp
            }
            if let found = popUp(in: subview) { return found }
        }
        return nil
    }
}

/// Character set: today's list; choosing writes the item's tag to DefaultEncodingTag, as the XIB's selectedTag binding
/// did. A stored tag the list lacks shows as a disabled "Other (tag)".
struct SAClaudeSettingsEncodingPill: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore
    let row: SAClaudeSettingRow
    let encodings: SAClaudeSettingsEncodings
    weak var host: SAClaudeSettingsWindowHost?

    var body: some View {
        pill(list: encodings.items(for: host?.controller), stored: store[int: SAClaudeSettingsEncodings.key])
    }

    private func pill(list: [SAClaudeSettingsEncodings.Item], stored: Int) -> some View {
        var items = list.map { $0.tag == nil ? SAClaudePopUpItem.separator : SAClaudePopUpItem($0.title) }
        var selected = SAClaudeSettingsRules.selectedIndex(tags: list.map(\.tag), stored: stored)
        if selected == nil {
            let title = String(format: localized("ClaudeSettings.ui.otherValue"), String(stored))
            items += [.separator, SAClaudePopUpItem(title, isEnabled: false)]
            selected = items.count - 1
        }
        return SAClaudePopUpPill(items: items, selectedIndex: selected ?? 0, accessibilityLabel: localized(row.nameKey)) { index in
            guard list.indices.contains(index), let tag = list[index].tag else { return }
            store[int: SAClaudeSettingsEncodings.key] = tag
        }
        .fixedSize()
    }
}

// MARK: - Reload after saving

/// Three small labelled switches on one row: Add, Edit, Delete (ReloadAfterAddingRow / EditingRow / RemovingRow).
struct SAClaudeSettingsReloadSwitches: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore

    static let switches: [(titleKey: String, key: String)] = [
        ("ClaudeSettings.reloadAfterSaving.option.add", "ReloadAfterAddingRow"),
        ("ClaudeSettings.reloadAfterSaving.option.edit", "ReloadAfterEditingRow"),
        ("ClaudeSettings.reloadAfterSaving.option.delete", "ReloadAfterRemovingRow"),
    ]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Self.switches, id: \.key) { item in
                Toggle(isOn: $store[bool: item.key]) { Text(localized(item.titleKey)) }
                    .toggleStyle(SAClaudeSwitchToggleStyle())
                    .accessibilityLabel(Text(String(format: localized("ClaudeSettings.reloadAfterSaving.switchLabel"),
                                                    localized(item.titleKey))))
            }
        }
        .fixedSize()
    }
}

// MARK: - Suggest completions

/// The standard row, then today's stepper warning as a muted line while the delay is below 0.1 s
/// (SPEditorPreferencePane -delayStepperChanged:, :380-394).
struct SAClaudeSettingsAutoCompleteRow: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore
    let context: SAClaudeSettingsRowContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            context.standardRow { SAClaudeSettingStandardControl(row: context.row) }
            if case let .toggleNumber(_, delayKey, _, _, _) = context.row.control,
               SAClaudeSettingsRules.showsAutoCompleteDelayWarning(store[double: delayKey]) {
                SAClaudeSettingsRowNote(row: context.row, text: NSLocalizedString(
                    "WARNING: Setting the auto-complete delay to 0.0 can result in strange output.",
                    comment: "WARNING: Setting the auto-complete delay to 0.0 can result in strange output."))
            }
        }
    }
}

// MARK: - Check for updates

/// The switch, except in App Store builds: there it is disabled and shown off (the key untouched) with today's note
/// under it (SPNotificationsPreferencePane -preferencePaneView, :50-61). The note is the switch's tooltip in every build,
/// as it was the checkbox's.
struct SAClaudeSettingsUpdatesRow: View {
    @EnvironmentObject private var store: SAClaudeSettingsStore
    let context: SAClaudeSettingsRowContext
    let isAppStore: Bool

    static let key = "ShowUpdateAvailable"   // SPShowUpdateAvailable

    private var note: String {
        NSLocalizedString("Only available for GitHub downloads", comment: "Only available for GitHub downloads")
    }

    var body: some View {
        let state = SAClaudeSettingsRules.updatesSwitch(isAppStore: isAppStore, stored: store[bool: Self.key])
        let name = localized(context.row.nameKey)
        VStack(alignment: .leading, spacing: 0) {
            context.standardRow {
                Group {
                    if state.isEnabled {
                        Toggle(isOn: $store[bool: Self.key]) { Text(name) }
                    } else {
                        Toggle(isOn: .constant(state.isOn)) { Text(name) }
                            .disabled(true)
                    }
                }
                .toggleStyle(SAClaudeSwitchToggleStyle(showsLabel: false))
                .accessibilityLabel(Text(name))
                .help(note)
            }
            if state.showsNote {
                SAClaudeSettingsRowNote(row: context.row, text: note)
            }
        }
    }
}
