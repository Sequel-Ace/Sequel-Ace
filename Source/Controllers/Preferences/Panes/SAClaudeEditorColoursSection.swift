//
//  SAClaudeEditorColoursSection.swift
//  Sequel Ace
//
//  Settings → Query Editor's colour choice in the Claude look: Follow macOS
//  (Claude Light/Dark) or Customise (a theme to start from, a ⋯ menu with the
//  pane's theme actions, and all 11 colours). It takes the place of the XIB
//  colour table, gear and theme label. App target only.
//

import AppKit
import SwiftUI

/// The editor colour keys in the order and with the labels of the pane's colour table.
private let colourRows: [(key: String, label: String)] = [
    (SAEditorThemeLoader.textColourKey, NSLocalizedString("Text", comment: "text label for color table (Prefs > Editor)")),
    (SAEditorThemeLoader.backgroundColourKey, NSLocalizedString("Background", comment: "background label for color table (Prefs > Editor)")),
    (SAEditorThemeLoader.caretColourKey, NSLocalizedString("Caret", comment: "caret label for color table (Prefs > Editor)")),
    (SAEditorThemeLoader.commentColourKey, NSLocalizedString("Comment", comment: "comment label")),
    (SAEditorThemeLoader.keywordColourKey, NSLocalizedString("Keyword", comment: "keyword label for color table (Prefs > Editor)")),
    (SAEditorThemeLoader.numericColourKey, NSLocalizedString("Numeric", comment: "numeric label for color table (Prefs > Editor)")),
    (SAEditorThemeLoader.quoteColourKey, NSLocalizedString("Quote", comment: "quote label for color table (Prefs > Editor)")),
    (SAEditorThemeLoader.backtickColourKey, NSLocalizedString("Backtick Quote", comment: "backtick quote label for color table (Prefs > Editor)")),
    (SAEditorThemeLoader.variableColourKey, NSLocalizedString("Variable", comment: "variable label for color table (Prefs > Editor)")),
    (SAEditorThemeLoader.highlightColourKey, NSLocalizedString("Query Background", comment: "query background label for color table (Prefs > Editor)")),
    (SAEditorThemeLoader.selectionColourKey, NSLocalizedString("Selection", comment: "selection label for color table (Prefs > Editor)")),
]

/// Opens the shared colour panel for one editor colour and writes its changes.
final class SAClaudeEditorColourPanelTarget: NSObject {
    private let defaults: UserDefaults
    private var key: String?
    /// NSColorPanel has no `target` getter, so remember who last pointed it at themselves.
    private static weak var owner: SAClaudeEditorColourPanelTarget?

    init(defaults: UserDefaults) { self.defaults = defaults }

    func edit(_ key: String) {
        self.key = key
        Self.owner = self
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colourChanged(_:)))
        panel.color = SAArchiving.color(from: defaults.data(forKey: key)) ?? .textColor
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func colourChanged(_ sender: NSColorPanel) {
        guard sender.isVisible, let key, let data = SAArchiving.archivedData(forColor: sender.color) else { return }
        defaults.set(data, forKey: key)
        defaults.set(SAClaudeEditorDefaults.customSchemeName, forKey: SAEditorThemeLoader.themeNameKey)
    }

    /// Closes the panel if it is editing for us, so a stray click can't edit the other mode's set.
    func close() {
        let panel = NSColorPanel.shared
        if Self.owner === self {
            Self.owner = nil
            panel.setTarget(nil)
            panel.setAction(nil)
            panel.orderOut(nil)
        }
        key = nil
    }
}

final class SAClaudeEditorColoursSettings: ObservableObject {
    let defaults: UserDefaults
    let themesDirectory: String
    let confirmDiscardUnsaved: () -> Bool
    let saveAs: () -> Void, importTheme: () -> Void, exportTheme: () -> Void, editThemeList: () -> Void
    let panelTarget: SAClaudeEditorColourPanelTarget
    private var observer: NSObjectProtocol?

    @Published private(set) var followsMacOS = true
    @Published private(set) var themeNames: [String] = []
    @Published private(set) var themeName = ""
    @Published private(set) var colours: [String: NSColor] = [:]

    init(defaults: UserDefaults = .standard, themesDirectory: String, confirmDiscardUnsaved: @escaping () -> Bool,
         saveAs: @escaping () -> Void, importTheme: @escaping () -> Void, exportTheme: @escaping () -> Void, editThemeList: @escaping () -> Void) {
        self.defaults = defaults
        self.themesDirectory = themesDirectory
        self.confirmDiscardUnsaved = confirmDiscardUnsaved
        self.saveAs = saveAs
        self.importTheme = importTheme
        self.exportTheme = exportTheme
        self.editThemeList = editThemeList
        panelTarget = SAClaudeEditorColourPanelTarget(defaults: defaults)
        refresh()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func refresh() {
        let follows = SAEditorColourMode.isFollowingMacOS(defaults)
        if follows != followsMacOS { followsMacOS = follows }
        let names = SAEditorAppearanceThemeSwitcher.availableThemeNames(in: themesDirectory)
        if names != themeNames { themeNames = names }
        let name = defaults.string(forKey: SAEditorThemeLoader.themeNameKey) ?? ""
        if name != themeName { themeName = name }
        var newColours: [String: NSColor] = [:]
        for row in colourRows { newColours[row.key] = SAArchiving.color(from: defaults.data(forKey: row.key)) ?? .textColor }
        if newColours != colours { colours = newColours }
    }

    var modeSetting: Bool {
        get { followsMacOS }
        set {
            panelTarget.close()
            SAEditorColourMode.setFollowsMacOS(newValue)
            refresh()
        }
    }

    var startFromSetting: String {
        get { SAEditorAppearanceThemeSwitcher.canonicalName(themeName, in: themeNames) }
        set {
            guard newValue.caseInsensitiveCompare(themeName) != .orderedSame,
                  newValue != SAClaudeEditorDefaults.customSchemeName else { return }
            guard confirmDiscardUnsaved() else { resync(); return }
            if newValue.caseInsensitiveCompare(SAEditorThemeLoader.defaultSchemeName) == .orderedSame {
                SAEditorThemeLoader.loadDefaultColours(into: defaults)
            } else {
                let path = (themesDirectory as NSString).appendingPathComponent(newValue + ".spTheme")
                guard SAEditorThemeLoader.loadTheme(atPath: path, into: defaults) > 0 else { resync(); return }
            }
            defaults.set(newValue, forKey: SAEditorThemeLoader.themeNameKey)
            refresh()
        }
    }

    /// Like the legacy colour table: the Background, Query Background and Selection rows draw their
    /// label in the Text colour (their own colour is the fill), the others in their own colour.
    func labelColour(for key: String) -> NSColor {
        let usesText = key == SAEditorThemeLoader.backgroundColourKey
            || key == SAEditorThemeLoader.highlightColourKey
            || key == SAEditorThemeLoader.selectionColourKey
        return colours[usesText ? SAEditorThemeLoader.textColourKey : key] ?? .textColor
    }

    /// Query Background and Selection rows are filled with their own colour.
    func rowFill(for key: String) -> NSColor? {
        key == SAEditorThemeLoader.highlightColourKey || key == SAEditorThemeLoader.selectionColourKey ? colours[key] : nil
    }

    /// Makes the picker re-read the stored theme after a change that was refused or failed.
    private func resync() {
        DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
    }

    func startFromEntries() -> [String] {
        SAEditorAppearanceThemeSwitcher.pickerNames(available: themeNames, selected: startFromSetting)
    }

    func displayName(_ name: String) -> String {
        if name == SAClaudeEditorDefaults.customSchemeName { return name }
        return themeNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
            ? name
            : String(format: NSLocalizedString("%@ (missing)", comment: "Preferences > Query Editor > Theme Appearance: a chosen theme whose file no longer exists"), name)
    }

    /// The bundled Claude theme's colours, for the Follow macOS preview tiles.
    static func bundledThemeColours(_ name: String) -> [String: NSColor] {
        guard let support = Bundle.main.sharedSupportPath,
              let data = FileManager.default.contents(atPath: "\(support)/Default Themes/\(name).spTheme"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return [:] }
        return SAEditorThemeLoader.colours(fromThemePlist: plist)
    }
}

private struct SAClaudeThemeTile: View {
    let title: String
    let colours: [String: NSColor]

    private func colour(_ key: String, _ fallback: NSColor) -> Color { Color(nsColor: colours[key] ?? fallback) }

    var body: some View {
        VStack(spacing: 3) {
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
            .background(RoundedRectangle(cornerRadius: 7).fill(colour(SAEditorThemeLoader.backgroundColourKey, .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor)))
            Text(title).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}

struct SAClaudeEditorColoursSection: View {
    @ObservedObject var settings: SAClaudeEditorColoursSettings
    private let light = SAClaudeEditorColoursSettings.bundledThemeColours("Claude Light")
    private let dark = SAClaudeEditorColoursSettings.bundledThemeColours("Claude Dark")

    init(settings: SAClaudeEditorColoursSettings) { self.settings = settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Its own row, like "Start from:": beside the segmented control it would not fit the ~233pt column.
            Text(NSLocalizedString("Colours:", comment: "Preferences > Query Editor: label before the Follow macOS / Customise choice"))
                .accessibilityHidden(true)
            Picker(NSLocalizedString("Colours", comment: "Preferences > Query Editor: accessibility label of the Follow macOS / Customise choice"),
                   selection: $settings.modeSetting) {
                Text(NSLocalizedString("Follow macOS", comment: "Preferences > Query Editor: colours follow the macOS light/dark appearance with the Claude themes")).tag(true)
                Text(NSLocalizedString("Customise", comment: "Preferences > Query Editor: the user's own editor colours")).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            if settings.followsMacOS {
                Text(NSLocalizedString("Claude Light in light mode, Claude Dark in dark mode. Editor, results and console all follow.",
                                       comment: "Preferences > Query Editor: hint under Follow macOS"))
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    SAClaudeThemeTile(title: NSLocalizedString("Light", comment: "Preferences > Query Editor: caption of the light-mode theme preview"), colours: light)
                    SAClaudeThemeTile(title: NSLocalizedString("Dark", comment: "Preferences > Query Editor: caption of the dark-mode theme preview"), colours: dark)
                }
            } else {
                Text(NSLocalizedString("Your colours, the same in light and dark mode.", comment: "Preferences > Query Editor: hint under Customise"))
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(NSLocalizedString("Start from:", comment: "Preferences > Query Editor > Customise: label of the theme to start from"))
                HStack(spacing: 6) {
                    Picker(NSLocalizedString("Start from:", comment: "Preferences > Query Editor > Customise: label of the theme to start from"),
                           selection: $settings.startFromSetting) {
                        ForEach(settings.startFromEntries(), id: \.self) { Text(settings.displayName($0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    Menu {
                        Button(NSLocalizedString("Save as theme…", comment: "Preferences > Query Editor > Customise: save the current colours as a theme file"), action: settings.saveAs)
                        Button(NSLocalizedString("Import theme…", comment: "Preferences > Query Editor > Customise: import a theme file"), action: settings.importTheme)
                        Button(NSLocalizedString("Export current theme…", comment: "Preferences > Query Editor > Customise: export the current colours as a theme file"), action: settings.exportTheme)
                        Divider()
                        Button(NSLocalizedString("Edit theme list…", comment: "Preferences > Query Editor > Customise: rename, duplicate or remove theme files"), action: settings.editThemeList)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(colourRows, id: \.key) { row in
                            HStack {
                                Text(row.label)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(Color(nsColor: settings.labelColour(for: row.key)))
                                Spacer()
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(nsColor: settings.colours[row.key] ?? .clear))
                                    .frame(width: 24, height: 14)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(nsColor: .separatorColor)))
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(settings.rowFill(for: row.key).map { Color(nsColor: $0) } ?? Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { settings.panelTarget.edit(row.key) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: settings.colours[SAEditorThemeLoader.backgroundColourKey] ?? .textBackgroundColor)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The theme list can change (Edit theme list, Import) without a defaults write.
        .onAppear { settings.refresh() }
    }
}

/// ObjC entry point: places the section where the pane's colour table, gear and
/// theme label were, and detaches those (built once per pane view).
@objc(SAClaudeEditorColoursSectionHost) final class SAClaudeEditorColoursSectionHost: NSObject {

    private static var hostKey: UInt8 = 0
    private static var detachedKey: UInt8 = 0

    @objc(installInPaneView:replacingViews:themesDirectory:confirmDiscardUnsaved:saveAs:importTheme:exportTheme:editThemeList:)
    static func install(in paneView: NSView, replacing views: [NSView], themesDirectory: String,
                        confirmDiscardUnsaved: @escaping () -> Bool, saveAs: @escaping () -> Void,
                        importTheme: @escaping () -> Void, exportTheme: @escaping () -> Void,
                        editThemeList: @escaping () -> Void) {
        guard objc_getAssociatedObject(paneView, &hostKey) == nil else { return }
        // The gear pull-down has no outlet: it is the popup whose menu saves the theme.
        func popUps(in view: NSView) -> [NSPopUpButton] {
            view.subviews.flatMap { ($0 as? NSPopUpButton).map { [$0] } ?? popUps(in: $0) }
        }
        let gear = popUps(in: paneView).first {
            $0.menu?.items.contains { $0.action == NSSelectorFromString("saveAsColorScheme:") } == true
        }
        let replaced = views + (gear.map { [$0] } ?? [])
        // In pane coordinates: the views may sit in nested containers.
        let frame = replaced.map { paneView.convert($0.bounds, from: $0) }.reduce(NSRect.null) { $0.union($1) }
        // Detached, not hidden: the legacy pane code unhides its theme label on every pane show.
        // The pane's outlets keep messaging them harmlessly; the host also retains them so the
        // table keeps its enclosing scroll view (the ObjC caller looks it up on every show).
        replaced.forEach { $0.removeFromSuperview() }
        objc_setAssociatedObject(paneView, &detachedKey, replaced, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let settings = SAClaudeEditorColoursSettings(themesDirectory: themesDirectory, confirmDiscardUnsaved: confirmDiscardUnsaved,
                                                     saveAs: saveAs, importTheme: importTheme, exportTheme: exportTheme, editThemeList: editThemeList)
        let host = NSHostingView(rootView: SAClaudeEditorColoursSection(settings: settings))
        host.frame = frame
        host.autoresizingMask = [.maxXMargin, .minYMargin]
        paneView.addSubview(host)
        objc_setAssociatedObject(paneView, &hostKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
