//
//  SAClaudeEditorColoursSection.swift
//  Sequel Ace
//
//  The editor colours' model in the Claude look: Follow macOS (Claude
//  Light/Dark) or Custom (a theme to start from, the Query Editor pane's theme
//  actions, all 11 colours), the accent colour, and the shared colour panel's
//  hand-off between the colour rows and the accent well. The Settings
//  window's Appearance pane draws it (SAClaudeSettingsColours.swift).
//  Shared with the Unit Tests target.
//

import AppKit
import SwiftUI

/// The editor colour keys in the order and with the labels of the pane's colour table.
enum SAClaudeEditorColourList {
    static let rows: [(key: String, label: String)] = [
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
}

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

    /// Lets go of the shared colour panel without closing it: if it was pointed at us, its target, action and our
    /// key are cleared, so a drag in the panel can no longer write an editor colour. Called before another
    /// client (the accent well) takes the panel over, and by `close()`.
    func releasePanel() {
        if Self.owner === self {
            Self.owner = nil
            let panel = NSColorPanel.shared
            panel.setTarget(nil)
            panel.setAction(nil)
        }
        key = nil
    }

    /// Closes the panel if it is editing for us, so a stray click can't edit the other mode's set.
    func close() {
        let ownsPanel = Self.owner === self
        releasePanel()
        if ownsPanel { NSColorPanel.shared.orderOut(nil) }
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
    /// The accent colour in effect, and whether the user has chosen one (else it is clay and Reset is disabled).
    @Published private(set) var accent: NSColor = SAClaudeAccent.clayAccent
    @Published private(set) var accentIsStored = false
    /// The accent row's colour well, so it can stop editing when another colour is picked or the accent reset.
    weak var accentWell: NSColorWell?

    /// Stops the accent well editing, only if it is (deactivating an inactive well still talks to the colour panel).
    func deactivateAccentWell() {
        if let accentWell, accentWell.isActive { accentWell.deactivate() }
    }

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
        for row in SAClaudeEditorColourList.rows { newColours[row.key] = SAArchiving.color(from: defaults.data(forKey: row.key)) ?? .textColor }
        if newColours != colours { colours = newColours }
        let storedAccent = SAClaudeAccent.stored(in: defaults)
        let resolvedAccent = storedAccent ?? SAClaudeAccent.clayAccent
        if resolvedAccent != accent { accent = resolvedAccent }
        if (storedAccent != nil) != accentIsStored { accentIsStored = storedAccent != nil }
    }

    /// Stores the accent the well picked (opaque); every Claude view recolours live.
    func setAccent(_ colour: NSColor) {
        SAClaudeAccent.store(colour.withAlphaComponent(1), in: defaults)
        refresh()
    }

    /// Back to clay.
    func resetAccent() {
        deactivateAccentWell()
        SAClaudeAccent.store(nil, in: defaults)
        refresh()
    }

    /// The accent well is about to take the shared colour panel: the editor colours' hand-off is dropped first
    /// (called before the well sets itself as the panel's target, not after).
    func accentWellWillActivate() {
        panelTarget.releasePanel()
    }

    /// Opens the colour panel for an editor colour; the accent well gives the panel up first.
    func editColour(_ key: String) {
        deactivateAccentWell()
        panelTarget.edit(key)
    }

    var modeSetting: Bool {
        get { followsMacOS }
        set {
            deactivateAccentWell()
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

/// The accent row's colour well. It tells its owner before it takes the shared colour panel over, and lets go
/// of the panel when it leaves its window or the window closes (a later use of the panel must not move the accent).
final class SAClaudeAccentColorWell: NSColorWell {
    var willActivate: (() -> Void)?
    private var closeObserver: NSObjectProtocol?

    override func activate(_ exclusive: Bool) {
        willActivate?()
        super.activate(exclusive)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, isActive { deactivate() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                if self?.isActive == true { self?.deactivate() }
            }
        }
    }

    deinit { if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) } }
}

/// A minimal-style colour well (the accent row's): every change, including a drag in the colour panel, is
/// reported at once.
struct SAClaudeAccentWell: NSViewRepresentable {
    let colour: NSColor
    let onChange: (NSColor) -> Void
    let willActivate: () -> Void
    let register: (NSColorWell) -> Void

    final class Coordinator: NSObject {
        var onChange: (NSColor) -> Void = { _ in }
        @objc func changed(_ sender: NSColorWell) { onChange(sender.color) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSColorWell {
        let well = SAClaudeAccentColorWell(style: .minimal)
        well.color = colour
        well.isContinuous = true
        well.target = context.coordinator
        well.action = #selector(Coordinator.changed(_:))
        well.willActivate = willActivate
        well.setAccessibilityLabel(NSLocalizedString("Accent colour", comment: "Preferences > Query Editor: label of the accent colour well"))
        register(well)
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.onChange = onChange
        register(well)
        // While the well is being edited it already shows what the panel holds.
        guard !well.isActive, well.color.usingColorSpace(.sRGB) != colour.usingColorSpace(.sRGB) else { return }
        well.color = colour
    }
}
