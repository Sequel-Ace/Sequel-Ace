//
//  SAClaudeSettingsControls.swift
//  Sequel Ace
//
//  The Settings window's building blocks, drawn with the Claude SwiftUI kit (`SAClaudeSwiftUIStyle.swift`, `.form`
//  sizes): the defaults binding every control writes through, a section (small heading + card), a row (name + (i),
//  description, control at the right; dependents indented 22pt and dimmed while their parent is off; the (i)
//  explanation inline under the row, ending in its muted "Was: …" line), and the standard control for each plain
//  catalog row (switch, switch + number, number, fixed pill, text). Dynamic pills and custom rows supply their own
//  control. Inject `SAClaudeSwiftUIPalette` (`.app`) and `SAClaudeDefaultsWatcher` with `.environmentObject` at the
//  root. App target only.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Defaults

/// Reads a setting from `defaults` and writes it through `controller.values` — the same path a XIB binding to the
/// shared user defaults controller takes — so every `NSUserDefaultsController` binding and observer of
/// `values.<key>` fires as it did when the Preferences XIB wrote the key, and so does plain `UserDefaults` KVO and
/// `UserDefaults.didChangeNotification` (the controller applies immediately). `.standard` is the app's defaults and
/// the shared controller; a harness passes a scratch suite and its own controller.
struct SAClaudeDefaultsBinding {
    let defaults: UserDefaults
    let controller: NSUserDefaultsController

    static var standard: SAClaudeDefaultsBinding {
        SAClaudeDefaultsBinding(defaults: .standard, controller: .shared)
    }

    func bool(_ key: String) -> Binding<Bool> {
        Binding(get: { defaults.bool(forKey: key) }, set: { write($0, forKey: key) })
    }

    func double(_ key: String) -> Binding<Double> {
        Binding(get: { defaults.double(forKey: key) }, set: { write($0, forKey: key) })
    }

    func int(_ key: String) -> Binding<Int> {
        Binding(get: { defaults.integer(forKey: key) }, set: { write($0, forKey: key) })
    }

    func string(_ key: String) -> Binding<String> {
        Binding(get: { defaults.string(forKey: key) ?? "" }, set: { write($0, forKey: key) })
    }

    /// A number field's value: read as a double, written as an integer for a whole-step field and a double for a
    /// tenths field (`SAClaudeSettingsValues.storedValue`), as the XIB formatters stored them.
    func number(_ key: String, step: Double) -> Binding<Double> {
        Binding(get: { defaults.double(forKey: key) },
                set: { write(SAClaudeSettingsValues.storedValue($0, step: step), forKey: key) })
    }

    /// Sets `values.<key>` on the controller (KVC on its values proxy), which writes `defaults`.
    func write(_ value: Any?, forKey key: String) {
        (controller.values as AnyObject).setValue(value, forKey: key)
    }

    static func bool(_ key: String) -> Binding<Bool> { standard.bool(key) }
    static func double(_ key: String) -> Binding<Double> { standard.double(key) }
    static func int(_ key: String) -> Binding<Int> { standard.int(key) }
    static func string(_ key: String) -> Binding<String> { standard.string(key) }
}

/// Re-renders the settings views when their defaults change — from a control, a menu item, another window, or a
/// pane controller's own code — so a value written elsewhere shows at once and a dependent row's enabled state
/// follows its parent's switch. Main thread.
@MainActor
final class SAClaudeDefaultsWatcher: ObservableObject {
    let binding: SAClaudeDefaultsBinding
    private var observer: NSObjectProtocol?

    init(binding: SAClaudeDefaultsBinding = .standard) {
        self.binding = binding
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                          object: binding.defaults, queue: nil) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.objectWillChange.send() }
            } else {
                DispatchQueue.main.async { self?.objectWillChange.send() }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var defaults: UserDefaults { binding.defaults }

    /// Whether `row` is enabled now (a dependent with `disabledWhenParentOff` follows its parent's switch).
    func isEnabled(_ row: SAClaudeSettingRow) -> Bool {
        SAClaudeSettingsCatalog.isEnabled(row) { defaults.bool(forKey: $0) }
    }
}

// MARK: - Metrics

enum SAClaudeSettingsMetrics {
    static let nameFont = Font.system(size: 13)
    static let descriptionFont = Font.system(size: 11.5)
    static let sectionTitleFont = Font.system(size: 11.5, weight: .semibold)
    static let infoFont = Font.system(size: 11.5)
    static let dependentIndent: CGFloat = 22
    static let cardRadius: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 9
    static let rowMinHeight: CGFloat = 28
    static let controlGap: CGFloat = 16
    static let nameToDescription: CGFloat = 2
    static let infoGlyphSize: CGFloat = 11
    static let infoHitSize: CGFloat = 14
    static let infoTopGap: CGFloat = 8
    static let infoPadding = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
    static let infoRadius: CGFloat = 7
    static let sectionTitleGap: CGFloat = 6
    static let textFieldWidth: CGFloat = 140
}

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

// MARK: - Card and section

/// A settings card: the surface inside a 1pt hairline, 10pt radius.
struct SAClaudeSettingsCard<Content: View>: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SAClaudeSettingsMetrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(palette.surface))
            .overlay(shape.strokeBorder(palette.hairline, lineWidth: 1))
            .clipShape(shape)
    }
}

/// The hairline between two rows of a card, inset from the card's leading edge.
struct SAClaudeSettingsDivider: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette

    var body: some View {
        palette.hairline
            .frame(height: 1)
            .padding(.leading, SAClaudeSettingsMetrics.rowHorizontalPadding)
            .accessibilityHidden(true)
    }
}

/// A section: its small secondary heading (none for a pane with one untitled section), then a card of its rows with
/// hairlines between them. `openInfoRowID` is the one row whose (i) is open — shared by the whole window so opening
/// one closes any other. `control` supplies each row's control; the convenience initialiser uses the standard one.
struct SAClaudeSettingsSectionView<Control: View>: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    let section: SAClaudeSettingsSection
    @Binding var openInfoRowID: String?
    @ViewBuilder let control: (SAClaudeSettingRow) -> Control

    init(section: SAClaudeSettingsSection, openInfoRowID: Binding<String?>,
         @ViewBuilder control: @escaping (SAClaudeSettingRow) -> Control) {
        self.section = section
        _openInfoRowID = openInfoRowID
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SAClaudeSettingsMetrics.sectionTitleGap) {
            if let titleKey = section.titleKey {
                Text(localized(titleKey))
                    .font(SAClaudeSettingsMetrics.sectionTitleFont)
                    .foregroundColor(palette.secondary)
                    .padding(.leading, 2)
                    .accessibilityAddTraits(.isHeader)
            }
            SAClaudeSettingsCard {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SAClaudeSettingsDivider() }
                    SAClaudeSettingsRowView(row: row, infoOpen: openInfoRowID == row.id,
                                            onInfo: { toggleInfo(row.id) }) { control(row) }
                }
            }
        }
    }

    private func toggleInfo(_ rowID: String) {
        openInfoRowID = openInfoRowID == rowID ? nil : rowID
    }
}

extension SAClaudeSettingsSectionView where Control == SAClaudeSettingStandardControl {
    /// Every row with its standard control (custom and dynamic rows show none).
    init(section: SAClaudeSettingsSection, openInfoRowID: Binding<String?>) {
        self.init(section: section, openInfoRowID: openInfoRowID) { SAClaudeSettingStandardControl(row: $0) }
    }
}

// MARK: - Row

/// One setting: its name (13pt) and (i) button, the description under it (11.5pt muted) when it has one, and its
/// control at the right. A dependent row is indented 22pt; while its parent's switch is off (`disabledWhenParentOff`)
/// its name and description dim and its control is disabled — the (i) still opens. Open, the (i) explanation sits
/// under the row: the row's info text (rows without one show only the "Was:" line) then "Was: <old name> (<old
/// pane>)" in the muted colour.
struct SAClaudeSettingsRowView<Content: View>: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @EnvironmentObject var defaults: SAClaudeDefaultsWatcher
    let row: SAClaudeSettingRow
    let infoOpen: Bool
    let onInfo: () -> Void
    @ViewBuilder let content: () -> Content

    init(row: SAClaudeSettingRow, infoOpen: Bool, onInfo: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.row = row
        self.infoOpen = infoOpen
        self.onInfo = onInfo
        self.content = content
    }

    private typealias Metrics = SAClaudeSettingsMetrics

    var body: some View {
        let isEnabled = defaults.isEnabled(row)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Metrics.controlGap) {
                VStack(alignment: .leading, spacing: Metrics.nameToDescription) {
                    HStack(alignment: .center, spacing: 5) {
                        Text(localized(row.nameKey))
                            .font(Metrics.nameFont)
                            .foregroundColor(palette.text)
                            .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.disabledOpacity)
                            .fixedSize(horizontal: false, vertical: true)
                        infoButton
                    }
                    if row.hasDescription {
                        Text(localized(row.descKey))
                            .font(Metrics.descriptionFont)
                            .foregroundColor(palette.muted)
                            .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.disabledOpacity)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)

                content()
                    .disabled(!isEnabled)
            }
            .frame(minHeight: Metrics.rowMinHeight)
            // Always its ideal height: a stack short of room would otherwise squeeze the row and centre its
            // overflowing text (opening an (i) below nudged the row up by 2pt).
            .fixedSize(horizontal: false, vertical: true)

            if infoOpen {
                info
                    .padding(.top, Metrics.infoTopGap)
                    .transition(.opacity)
            }
        }
        .padding(.leading, row.parentID == nil ? 0 : Metrics.dependentIndent)
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .padding(.vertical, Metrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(row.id)
    }

    private var infoButton: some View {
        Button(action: onInfo) {
            Image(systemName: infoOpen ? "info.circle.fill" : "info.circle")
                .font(.system(size: Metrics.infoGlyphSize))
                .foregroundColor(infoOpen ? palette.accent : palette.muted)
                // One box for both glyphs, so opening the (i) never moves the row.
                .frame(width: Metrics.infoHitSize, height: Metrics.infoHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(SAClaudeBareButtonStyle())
        .accessibilityLabel(Text(String(format: NSLocalizedString("ClaudeSettings.ui.infoButton",
                                                                  comment: "Claude Settings: accessibility label of a setting's (i) button; %@ is the setting's name"),
                                        localized(row.nameKey))))
        .accessibilityValue(Text(infoOpen ? NSLocalizedString("ClaudeSettings.ui.infoShown", comment: "Claude Settings: accessibility value of a setting's (i) button while its explanation is shown")
                                          : NSLocalizedString("ClaudeSettings.ui.infoHidden", comment: "Claude Settings: accessibility value of a setting's (i) button while its explanation is hidden")))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            if row.hasInfo {
                Text(localized(row.infoKey))
                    .foregroundColor(palette.secondary)
            }
            Text(localized(row.wasKey))
                .foregroundColor(palette.muted)
        }
        .font(Metrics.infoFont)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Metrics.infoPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.infoRadius, style: .continuous).fill(palette.hover))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Standard controls

/// The control a plain catalog row gets: a switch; a number field then a switch (the field disabled while the switch
/// is off, as the XIB bound the field's enabled state to it); a number field; a pill of the fixed choices; a text
/// field. Custom rows and dynamic pills show nothing here (Tasks 4–5 build them; `handles(_:)` says which rows these
/// are). Writes go through the watcher's `SAClaudeDefaultsBinding`.
struct SAClaudeSettingStandardControl: View {
    @EnvironmentObject var defaults: SAClaudeDefaultsWatcher
    let row: SAClaudeSettingRow

    static func handles(_ row: SAClaudeSettingRow) -> Bool {
        switch row.control {
        case .toggle, .toggleNumber, .number, .text, .choice(_, .fixed): return true
        case .choice(_, .dynamic), .custom: return false
        }
    }

    private var name: String { localized(row.nameKey) }

    var body: some View {
        let binding = defaults.binding
        switch row.control {
        case .toggle(let key):
            switchControl(binding.bool(key))

        case let .toggleNumber(toggleKey, numberKey, unit, range, step):
            HStack(spacing: 10) {
                SAClaudeNumberField(value: binding.number(numberKey, step: step), range: range, step: step, unit: unit,
                                    accessibilityLabel: name)
                    .disabled(!defaults.defaults.bool(forKey: toggleKey))
                switchControl(binding.bool(toggleKey))
            }

        case let .number(key, unit, range, step):
            SAClaudeNumberField(value: binding.number(key, step: step), range: range, step: step, unit: unit,
                                accessibilityLabel: name)

        case let .choice(key, .fixed(options)):
            let current = defaults.defaults.integer(forKey: key)
            SAClaudePopUpPill(titles: options.map { localized($0.0) },
                              selectedIndex: options.firstIndex { $0.1 == current } ?? 0,
                              accessibilityLabel: name) { index in
                guard options.indices.contains(index) else { return }
                binding.int(key).wrappedValue = options[index].1
            }
            .fixedSize()

        case .text(let key):
            SAClaudeSettingsTextField(text: binding.string(key), accessibilityLabel: name)

        case .choice(_, .dynamic), .custom:
            EmptyView()
        }
    }

    private func switchControl(_ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(name) }
            .toggleStyle(SAClaudeSwitchToggleStyle(showsLabel: false))
            // The style's accessibility representation came out unnamed with its label hidden (in-process probe).
            .accessibilityLabel(Text(name))
    }
}

/// A Claude text field for a string setting that, like the XIB field it replaces, writes when editing ends (Return or
/// leaving the field), not on every keystroke; Escape restores the stored text. A value changed elsewhere shows while
/// the field isn't being edited.
struct SAClaudeSettingsTextField: View {
    @Binding var text: String
    let accessibilityLabel: String
    var width: CGFloat = SAClaudeSettingsMetrics.textFieldWidth

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    init(text: Binding<String>, accessibilityLabel: String, width: CGFloat = SAClaudeSettingsMetrics.textFieldWidth) {
        _text = text
        self.accessibilityLabel = accessibilityLabel
        self.width = width
    }

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(SAClaudeFieldStyle(isFocused: isFocused, size: .form))
            .focused($isFocused)
            .onSubmit(commit)
            .onExitCommand { draft = text }
            .accessibilityLabel(Text(accessibilityLabel))
            .frame(width: width)
            .onAppear { draft = text }
            .onChange(of: text) { stored in if !isFocused { draft = stored } }
            .onChange(of: isFocused) { focused in if !focused { commit() } }
    }

    private func commit() {
        if draft != text { text = draft }
    }
}
