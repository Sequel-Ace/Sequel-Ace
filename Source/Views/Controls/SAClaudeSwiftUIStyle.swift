//
//  SAClaudeSwiftUIStyle.swift
//  Sequel Ace
//
//  The shared Claude look for SwiftUI surfaces: one palette (`SAClaudeSwiftUIPalette`, from the editor theme for
//  panels that sit in the editor's chrome, or the sheets' colours for sheets) and the styles that read it from the
//  environment — the field, the primary / secondary / ghost-icon / link buttons and the checkbox — in two sizes:
//  `.form`, the AppKit Claude form sheets' own metrics (SAClaudeFormLayout, SAClaudeSheetStyler, SAClaudeFilterCells),
//  so a SwiftUI sheet sits beside them unchanged, and `.panel`, the roomier Record View panel's. Inject the palette
//  with `.environmentObject(palette)` at the root of the hosted view. App target only.
//

import AppKit
import SwiftUI

// MARK: - Palette

/// The colours a Claude SwiftUI surface draws with, kept live: rebuilt when the editor theme changes (the shared,
/// coalesced `SAClaudeThemeWatcher` check of every defaults write), when the accent changes, and when the app's
/// appearance changes (the theme's fallback colours are dynamic). All colours are resolved, never dynamic. Main
/// thread only.
@MainActor
final class SAClaudeSwiftUIPalette: ObservableObject {

    enum Source {
        /// The editor theme as the ⋯ options card derives it: the popup surface, theme text, status-chrome greys.
        case editorTheme
        /// The Claude sheets' colours (`SAClaudeSheetColours`), as the AppKit sheet skin draws with them.
        case app
    }

    let source: Source

    @Published private(set) var surface = Color.clear
    @Published private(set) var text = Color.primary
    @Published private(set) var secondary = Color.secondary
    @Published private(set) var muted = Color.secondary
    @Published private(set) var hairline = Color.gray
    @Published private(set) var hover = Color.gray
    @Published private(set) var selected = Color.gray
    @Published private(set) var fieldFill = Color.clear
    /// The accent for decorative uses: focus rings, links, ticks.
    @Published private(set) var accent = Color.orange
    /// The title colour on `accentFill`.
    @Published private(set) var onAccent = Color.white
    /// A soft accent wash (the accent at 28%) for search hits.
    @Published private(set) var highlight = Color.orange
    /// The accent's fill (a primary button, a checked box) and that fill pressed, as the AppKit sheet buttons draw them.
    @Published private(set) var accentFill = Color.orange
    @Published private(set) var accentPressed = Color.orange
    /// The outline of a secondary button and an unchecked box: brighter than `hairline`, which vanishes on a dark surface.
    @Published private(set) var stroke = Color.gray
    @Published private(set) var isDark = false

    static let selectedRatio: CGFloat = 0.14
    static let hoverRatio: CGFloat = 0.08
    static let highlightAlpha: CGFloat = 0.28

    private var appliedTheme: SAClaudeThemeColours?
    private var appliedAppearance: NSAppearance.Name?
    private var appearanceObservation: NSKeyValueObservation?

    init(source: Source) {
        self.source = source
        refresh(force: true)
        // Both call back on the main thread.
        SAClaudeThemeWatcher.observe(self) { palette in MainActor.assumeIsolated { palette.refresh(force: false) } }
        SAClaudeAccent.observe(self) { palette in MainActor.assumeIsolated { palette.refresh(force: true) } }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh(force: false) }
        }
    }

    deinit { appearanceObservation?.invalidate() }

    /// Rebuilds the colours when the theme or the app's appearance changed since the last build (always, when `force`).
    func refresh(force: Bool) {
        let appearance = NSApp.effectiveAppearance
        var theme: SAClaudeThemeColours!
        appearance.performAsCurrentDrawingAppearance { theme = SAClaudeThemeColours.from(defaults: .standard) }
        guard force || theme != appliedTheme || appearance.name != appliedAppearance else { return }
        appliedTheme = theme
        appliedAppearance = appearance.name
        switch source {
        case .editorTheme: buildEditorTheme(theme, in: appearance)
        case .app: buildApp()
        }
    }

    /// As `SAClaudeEditorOptionsModel.refresh()` (the ⋯ card) and `SAClaudeMenuCardPalette.editor()`.
    private func buildEditorTheme(_ theme: SAClaudeThemeColours, in appearance: NSAppearance) {
        var colours: [NSColor] = []
        var dark = false
        appearance.performAsCurrentDrawingAppearance {
            dark = SAClaudeGridChrome.isDark(theme.background)
            let surface = SAClaudeStatusChrome.popupSurface(theme: theme)
            colours = [surface,
                       theme.text,
                       SAClaudeEditorChrome.derivedColour(text: theme.text, background: surface, ratio: SAClaudeEditorChrome.buttonTextRatio),
                       SAClaudeStatusChrome.muted(theme: theme),
                       SAClaudeStatusChrome.hairline(theme: theme),
                       SAClaudeEditorChrome.derivedColour(text: theme.text, background: surface, ratio: Self.hoverRatio),
                       SAClaudeEditorChrome.derivedColour(text: theme.text, background: surface, ratio: Self.selectedRatio),
                       SAClaudeFilterChrome.fieldFill(text: theme.text, background: surface),
                       SAClaudeFilterChrome.dropStroke(text: theme.text, background: surface)].map(Self.resolved)
        }
        apply(surface: colours[0], text: colours[1], secondary: colours[2], muted: colours[3], hairline: colours[4],
              hover: colours[5], selected: colours[6], fieldFill: colours[7], stroke: colours[8], isDark: dark)
    }

    /// Exactly the AppKit sheet skin's colours (`SAClaudeSheetColours.current()`, which also sets every Claude sheet's
    /// lightness): the surface and field fill; text in the theme text; secondary text in the editor palette's button
    /// text; labels (`muted`) in the sheets' muted grey; the editor palette's hairline and hover; the drop stroke the
    /// AppKit secondary buttons and checkboxes outline with. Only `selected` (not drawn by the sheets) is derived here.
    private func buildApp() {
        let sheet = SAClaudeSheetColours.current()
        let lightness = NSAppearance(named: sheet.isDark ? .darkAqua : .aqua) ?? NSApp.effectiveAppearance
        var colours: [NSColor] = []
        lightness.performAsCurrentDrawingAppearance {
            colours = [sheet.surface,
                       sheet.theme.text,
                       sheet.palette.buttonText,
                       sheet.muted,
                       sheet.palette.hairline,
                       sheet.palette.hover,
                       SAClaudeEditorChrome.derivedColour(text: sheet.theme.text, background: sheet.surface, ratio: Self.selectedRatio),
                       sheet.fieldFill,
                       SAClaudeFilterChrome.dropStroke(text: sheet.theme.text, background: sheet.palette.background)].map(Self.resolved)
        }
        apply(surface: colours[0], text: colours[1], secondary: colours[2], muted: colours[3], hairline: colours[4],
              hover: colours[5], selected: colours[6], fieldFill: colours[7], stroke: colours[8], isDark: sheet.isDark)
    }

    private func apply(surface: NSColor, text: NSColor, secondary: NSColor, muted: NSColor, hairline: NSColor,
                       hover: NSColor, selected: NSColor, fieldFill: NSColor, stroke: NSColor, isDark: Bool) {
        let accent = Self.resolved(SAClaudeAccent.accent)
        self.surface = Color(nsColor: surface)
        self.text = Color(nsColor: text)
        self.secondary = Color(nsColor: secondary)
        self.muted = Color(nsColor: muted)
        self.hairline = Color(nsColor: hairline)
        self.hover = Color(nsColor: hover)
        self.selected = Color(nsColor: selected)
        self.fieldFill = Color(nsColor: fieldFill)
        self.stroke = Color(nsColor: stroke)
        self.accent = Color(nsColor: accent)
        self.highlight = Color(nsColor: accent.withAlphaComponent(Self.highlightAlpha))
        self.accentFill = Color(nsColor: Self.resolved(SAClaudeAccent.fill))
        self.accentPressed = Color(nsColor: Self.resolved(SAClaudeAccent.fillPressed(darkTheme: isDark)))
        self.onAccent = Color(nsColor: Self.resolved(SAClaudeAccent.onAccent))
        self.isDark = isDark
    }

    /// A fixed colour for whatever appearance is current (a dynamic or catalog colour would otherwise follow the
    /// SwiftUI environment's appearance rather than the theme's).
    private static func resolved(_ colour: NSColor) -> NSColor {
        NSColor(cgColor: colour.cgColor) ?? colour
    }
}

// MARK: - Sizes

/// How big the kit's controls are. `.form` is the AppKit Claude form sheets' metrics, read from their own constants;
/// `.panel` is the Record View panel's roomier look.
enum SAClaudeControlSize {
    case form, panel

    /// A text field's height.
    var fieldHeight: CGFloat {
        switch self {
        case .form: return SAClaudeFormLayout.fieldHeight
        case .panel: return 28
        }
    }

    /// The corner radius of fields, pop-up pills and buttons.
    var radius: CGFloat {
        switch self {
        case .form: return SAClaudeSheetColours.fieldRadius
        case .panel: return 8
        }
    }

    /// The accent outline of the focused field: the AppKit field's 1pt border, the panel's 1.5pt ring.
    var focusWidth: CGFloat {
        switch self {
        case .form: return 1
        case .panel: return 1.5
        }
    }

    /// A push button's height: the AppKit sheet button's (regular size), or the panel's.
    var buttonHeight: CGFloat {
        switch self {
        case .form: return SAClaudeSheetButtonGeometry.metrics(for: .regular).maximumHeight
        case .panel: return 28
        }
    }

    /// A pop-up pill's height and title font: the AppKit pill's 24pt control frame and 12pt title.
    var popUpHeight: CGFloat {
        switch self {
        case .form: return SAClaudeFilterChrome.controlHeight
        case .panel: return 28
        }
    }

    var popUpFont: NSFont {
        switch self {
        case .form: return FilterCellDrawing.font
        case .panel: return .systemFont(ofSize: 13)
        }
    }

    /// The checkbox's square, its corner radius, the tick's stroke and the title font.
    var checkboxSize: CGFloat {
        switch self {
        case .form: return SAClaudeFilterChrome.checkboxSize
        case .panel: return 16
        }
    }

    var checkboxRadius: CGFloat { SAClaudeFilterChrome.checkboxRadius }

    var tickWidth: CGFloat {
        switch self {
        case .form: return 1.6
        case .panel: return 1.8
        }
    }

    var checkboxTitleFont: Font {
        switch self {
        case .form: return Font(SAClaudeToggleTitleMetrics.font)
        case .panel: return .system(size: 13)
        }
    }
}

/// The kit's size-independent numbers, shared by the styles (and by views that line other things up with them).
enum SAClaudeSwiftUIMetrics {
    static let fieldHorizontalPadding: CGFloat = 8
    static let buttonHorizontalPadding: CGFloat = 14
    static let buttonMinWidth: CGFloat = 72
    /// The AppKit sheet buttons' title: the regular control font, medium.
    static let buttonFont = Font.system(size: NSFont.systemFontSize, weight: .medium)
    static let bodyFont = Font.system(size: 13)
    /// A disabled field or button (the AppKit sheet buttons' 45%).
    static let disabledOpacity: Double = 0.45
    static let iconButtonSize: CGFloat = 24
    static let iconButtonRadius: CGFloat = 6
    static let iconButtonDisabledOpacity: Double = 0.35
    static let linkFont = Font.system(size: 11)
    static let checkboxGap: CGFloat = SAClaudeToggleTitleMetrics.gap
    /// A disabled checkbox or pill (the AppKit Claude cells' 40%).
    static let checkboxDisabledOpacity: Double = Double(FilterCellDrawing.disabledAlpha)
}

// MARK: - Field

/// A Claude text field: the field fill inside a 1pt hairline, the accent outline while focused; `.form` 24pt high
/// with a 7pt radius and a 1pt accent border, as the AppKit sheet fields; `.panel` 28pt, 8pt and a 1.5pt ring.
/// SwiftUI cannot tell a style about focus: pass the field's `@FocusState` in.
struct SAClaudeFieldStyle: TextFieldStyle {
    var isFocused: Bool
    var size: SAClaudeControlSize

    init(isFocused: Bool, size: SAClaudeControlSize = .panel) {
        self.isFocused = isFocused
        self.size = size
    }

    func _body(configuration: TextField<Self._Label>) -> some View {
        SAClaudeFieldChrome(isFocused: isFocused, size: size) { configuration.textFieldStyle(.plain) }
    }
}

/// The field's chrome around any content — for a field that holds more than its text (the Record View's search field:
/// magnifier, text, match count).
struct SAClaudeFieldChrome<Content: View>: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @Environment(\.isEnabled) var isEnabled
    let isFocused: Bool
    let size: SAClaudeControlSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        let ring = isFocused && isEnabled
        content()
            .font(SAClaudeSwiftUIMetrics.bodyFont)
            .foregroundColor(palette.text)
            .padding(.horizontal, SAClaudeSwiftUIMetrics.fieldHorizontalPadding)
            .frame(height: size.fieldHeight)
            .background(shape.fill(palette.fieldFill))
            .overlay(shape.strokeBorder(ring ? palette.accent : palette.hairline, lineWidth: ring ? size.focusWidth : 1))
            .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.disabledOpacity)
    }
}

// MARK: - Buttons

/// The primary (Return) button: the accent fill with an `onAccent` medium title in the regular control font; pressed,
/// the fill 12% towards black (towards white on a dark theme), as the AppKit sheet buttons; 45% disabled.
struct SAClaudePrimaryButtonStyle: ButtonStyle {
    var size: SAClaudeControlSize = .panel

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, size: size)
    }

    private struct Styled: View {
        @EnvironmentObject var palette: SAClaudeSwiftUIPalette
        @Environment(\.isEnabled) var isEnabled
        let configuration: ButtonStyleConfiguration
        let size: SAClaudeControlSize

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
            configuration.label
                .font(SAClaudeSwiftUIMetrics.buttonFont)
                .foregroundColor(palette.onAccent)
                .lineLimit(1)
                .padding(.horizontal, SAClaudeSwiftUIMetrics.buttonHorizontalPadding)
                .frame(minWidth: SAClaudeSwiftUIMetrics.buttonMinWidth)
                .frame(height: size.buttonHeight)
                .background(shape.fill(configuration.isPressed && isEnabled ? palette.accentPressed : palette.accentFill))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.disabledOpacity)
        }
    }
}

/// A secondary button (Cancel): a 1pt outline on no fill, the title in the text colour, medium; the hover fill under
/// the pointer, a little darker pressed; 45% disabled.
struct SAClaudeSecondaryButtonStyle: ButtonStyle {
    var size: SAClaudeControlSize = .panel

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, size: size)
    }

    private struct Styled: View {
        @EnvironmentObject var palette: SAClaudeSwiftUIPalette
        @Environment(\.isEnabled) var isEnabled
        @State var isHovered = false
        let configuration: ButtonStyleConfiguration
        let size: SAClaudeControlSize

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
            let fill: Color = !isEnabled ? .clear : configuration.isPressed ? palette.selected : isHovered ? palette.hover : .clear
            configuration.label
                .font(SAClaudeSwiftUIMetrics.buttonFont)
                .foregroundColor(palette.text)
                .lineLimit(1)
                .padding(.horizontal, SAClaudeSwiftUIMetrics.buttonHorizontalPadding)
                .frame(minWidth: SAClaudeSwiftUIMetrics.buttonMinWidth)
                .frame(height: size.buttonHeight)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(palette.stroke, lineWidth: 1))
                .contentShape(shape)
                .onHover { isHovered = $0 }
                .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.disabledOpacity)
        }
    }
}

/// A borderless icon button: 24×24, 6pt radius, the glyph in the secondary colour; the hover fill under the
/// pointer, the selected fill pressed; 35% disabled.
struct SAClaudeGhostIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        @EnvironmentObject var palette: SAClaudeSwiftUIPalette
        @Environment(\.isEnabled) var isEnabled
        @State var isHovered = false
        let configuration: ButtonStyleConfiguration

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: SAClaudeSwiftUIMetrics.iconButtonRadius, style: .continuous)
            let fill: Color = !isEnabled ? .clear : configuration.isPressed ? palette.selected : isHovered ? palette.hover : .clear
            configuration.label
                .foregroundColor(palette.secondary)
                .frame(width: SAClaudeSwiftUIMetrics.iconButtonSize, height: SAClaudeSwiftUIMetrics.iconButtonSize)
                .background(shape.fill(fill))
                .contentShape(shape)
                .onHover { isHovered = $0 }
                .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.iconButtonDisabledOpacity)
        }
    }
}

/// A text link: the accent at 11pt, no chrome; dimmed while pressed; 45% disabled.
struct SAClaudeLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        @EnvironmentObject var palette: SAClaudeSwiftUIPalette
        @Environment(\.isEnabled) var isEnabled
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .font(SAClaudeSwiftUIMetrics.linkFont)
                .foregroundColor(palette.accent)
                .contentShape(Rectangle())
                .opacity(!isEnabled ? SAClaudeSwiftUIMetrics.disabledOpacity : configuration.isPressed ? 0.7 : 1)
        }
    }
}

// MARK: - Checkbox

/// The Claude checkbox: a rounded square — outlined in the drop stroke when off (the hover fill under the pointer),
/// the accent fill with an `onAccent` (white unless the accent is light) tick when on — then the label in the text
/// colour. `.form` is the AppKit Claude checkbox (14pt box, 12pt title); `.panel` 16pt and 13pt. The whole row
/// toggles; VoiceOver sees an ordinary checkbox. 40% disabled, as the AppKit Claude checkbox.
struct SAClaudeCheckboxToggleStyle: ToggleStyle {
    var size: SAClaudeControlSize = .panel

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, size: size)
    }

    private struct Styled: View {
        @EnvironmentObject var palette: SAClaudeSwiftUIPalette
        @Environment(\.isEnabled) var isEnabled
        @State var isHovered = false
        let configuration: ToggleStyleConfiguration
        let size: SAClaudeControlSize

        var body: some View {
            Button { configuration.isOn.toggle() } label: {
                HStack(spacing: SAClaudeSwiftUIMetrics.checkboxGap) {
                    box
                    configuration.label
                        .font(size.checkboxTitleFont)
                        .foregroundColor(palette.text)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SAClaudeBareButtonStyle())
            .onHover { isHovered = $0 }
            .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.checkboxDisabledOpacity)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .toggleStyle(.checkbox)
            }
        }

        private var box: some View {
            let shape = RoundedRectangle(cornerRadius: size.checkboxRadius, style: .continuous)
            return ZStack {
                if configuration.isOn {
                    shape.fill(palette.accentFill)
                    SAClaudeCheckMark()
                        .stroke(palette.onAccent, style: StrokeStyle(lineWidth: size.tickWidth, lineCap: .round, lineJoin: .round))
                } else {
                    shape.fill(isHovered && isEnabled ? palette.hover : Color.clear)
                    shape.strokeBorder(palette.stroke, lineWidth: 1)
                }
            }
            .frame(width: size.checkboxSize, height: size.checkboxSize)
        }
    }
}

/// The tick: the AppKit Claude checkbox's path in its 14pt box, scaled to the box it is drawn in.
private struct SAClaudeCheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / SAClaudeFilterChrome.checkboxSize
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 3.5 * s, y: rect.minY + 7.5 * s))
        path.addLine(to: CGPoint(x: rect.minX + 6 * s, y: rect.minY + 10 * s))
        path.addLine(to: CGPoint(x: rect.minX + 10.5 * s, y: rect.minY + 4.5 * s))
        return path
    }
}

// MARK: - Switch

/// Claude's small switch, as the editor ⋯ card draws it: a 26×15 capsule — the accent fill with an `onAccent` knob
/// when on, the drop stroke with a white knob when off — after the label (hide it with `showsLabel: false` when the
/// row already names the setting). The whole control toggles; VoiceOver sees an ordinary switch. 40% disabled, as the
/// kit's checkbox.
struct SAClaudeSwitchToggleStyle: ToggleStyle {
    var showsLabel = true

    static let trackSize = CGSize(width: 26, height: 15)
    static let knobInset: CGFloat = 2

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, showsLabel: showsLabel)
    }

    private struct Styled: View {
        @EnvironmentObject var palette: SAClaudeSwiftUIPalette
        @Environment(\.isEnabled) var isEnabled
        let configuration: ToggleStyleConfiguration
        let showsLabel: Bool

        var body: some View {
            Button { configuration.isOn.toggle() } label: {
                HStack(spacing: SAClaudeSwiftUIMetrics.checkboxGap) {
                    if showsLabel {
                        configuration.label
                            .font(SAClaudeControlSize.form.checkboxTitleFont)
                            .foregroundColor(palette.text)
                    }
                    track
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SAClaudeBareButtonStyle())
            .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.checkboxDisabledOpacity)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .toggleStyle(.switch)
            }
        }

        private var track: some View {
            let size = SAClaudeSwitchToggleStyle.trackSize
            let inset = SAClaudeSwitchToggleStyle.knobInset
            return ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? palette.accentFill : palette.stroke)
                Circle()
                    .fill(configuration.isOn ? palette.onAccent : Color.white)
                    .frame(width: size.height - 2 * inset, height: size.height - 2 * inset)
                    .padding(inset)
            }
            .frame(width: size.width, height: size.height)
            .animation(.easeOut(duration: 0.12), value: configuration.isOn)
        }
    }
}

/// A plain button look: the label as it is.
struct SAClaudeBareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

// MARK: - Pop-up pill

/// One entry of a pop-up pill's menu.
struct SAClaudePopUpItem: Equatable {
    var title: String
    var indentationLevel = 0
    var isEnabled = true
    var isSeparator = false

    init(_ title: String, indentationLevel: Int = 0, isEnabled: Bool = true) {
        self.title = title
        self.indentationLevel = indentationLevel
        self.isEnabled = isEnabled
    }

    static let separator: SAClaudePopUpItem = {
        var item = SAClaudePopUpItem("")
        item.isSeparator = true
        item.isEnabled = false
        return item
    }()
}

/// A choice as the AppKit form's Claude pill (`SAClaudePillPopUpButtonCell`): a 24pt hover-filled pill with a 7pt
/// radius (`.form`), the current choice at 12pt and the pop-up's own up-down chevron; the whole pill opens the menu,
/// which ticks the current choice. Sized to its widest item (up to `maxWidth`, then truncated), or filling the width
/// it is given with `fillsWidth`. A pop-up rather than a SwiftUI `Picker(.menu)`, whose bezel can't be removed.
/// `selectedIndex` counts separators, as the menu does.
struct SAClaudePopUpPill: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @Environment(\.isEnabled) private var isEnabled
    let items: [SAClaudePopUpItem]
    let selectedIndex: Int
    let accessibilityLabel: String
    var size: SAClaudeControlSize = .form
    var fillsWidth = false
    var maxWidth: CGFloat = 260
    let onSelect: (Int) -> Void

    init(items: [SAClaudePopUpItem], selectedIndex: Int, accessibilityLabel: String, size: SAClaudeControlSize = .form,
         fillsWidth: Bool = false, maxWidth: CGFloat = 260, onSelect: @escaping (Int) -> Void) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.accessibilityLabel = accessibilityLabel
        self.size = size
        self.fillsWidth = fillsWidth
        self.maxWidth = maxWidth
        self.onSelect = onSelect
    }

    init(titles: [String], selectedIndex: Int, accessibilityLabel: String, size: SAClaudeControlSize = .form,
         fillsWidth: Bool = false, maxWidth: CGFloat = 260, onSelect: @escaping (Int) -> Void) {
        self.init(items: titles.map { SAClaudePopUpItem($0) }, selectedIndex: selectedIndex,
                  accessibilityLabel: accessibilityLabel, size: size, fillsWidth: fillsWidth, maxWidth: maxWidth,
                  onSelect: onSelect)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        SAClaudeMenuPopUp(items: items, selectedIndex: selectedIndex, font: size.popUpFont, textColour: palette.text,
                          accessibilityLabel: accessibilityLabel, hugsTitle: !fillsWidth, onSelect: onSelect)
            .frame(maxWidth: fillsWidth ? .infinity : maxWidth - SAClaudeFilterChrome.pillPadding + 1)
            .padding(.leading, SAClaudeFilterChrome.pillPadding - 3)
            .padding(.trailing, 2)
            .frame(height: size.popUpHeight)
            .background(shape.fill(palette.hover))
            .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.checkboxDisabledOpacity)
    }
}

/// A borderless NSPopUpButton (its own up-down chevron at the right) filling the pill, its title and chevron in
/// `textColour`, in `font`: SwiftUI's own `Menu` opens only from its title's width, this from anywhere in the field.
/// VoiceOver sees a pop-up button; the menu follows the panel's appearance. With `hugsTitle` it asks for its widest
/// item's width (capped by the proposal); otherwise it takes the width it is offered.
/// Items are added one by one (`addItems(withTitles:)` drops duplicate titles, and two favourites may share a name).
struct SAClaudeMenuPopUp: NSViewRepresentable {
    let items: [SAClaudePopUpItem]
    let selectedIndex: Int
    let font: NSFont
    let textColour: Color
    let accessibilityLabel: String
    var hugsTitle = false
    let onSelect: (Int) -> Void

    init(items: [SAClaudePopUpItem], selectedIndex: Int, font: NSFont, textColour: Color, accessibilityLabel: String,
         hugsTitle: Bool = false, onSelect: @escaping (Int) -> Void) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.font = font
        self.textColour = textColour
        self.accessibilityLabel = accessibilityLabel
        self.hugsTitle = hugsTitle
        self.onSelect = onSelect
    }

    init(titles: [String], selectedIndex: Int, font: NSFont, textColour: Color, accessibilityLabel: String,
         onSelect: @escaping (Int) -> Void) {
        self.init(items: titles.map { SAClaudePopUpItem($0) }, selectedIndex: selectedIndex, font: font,
                  textColour: textColour, accessibilityLabel: accessibilityLabel, onSelect: onSelect)
    }

    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void = { _ in }
        var items: [SAClaudePopUpItem] = []
        @objc func picked(_ sender: NSPopUpButton) { onSelect(sender.indexOfSelectedItem) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.lineBreakMode = .byTruncatingTail
        button.alignment = .left
        button.autoenablesItems = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        if context.coordinator.items != items || button.numberOfItems != items.count {
            context.coordinator.items = items
            button.removeAllItems()
            for item in items {
                if item.isSeparator { button.menu?.addItem(.separator()); continue }
                let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                menuItem.indentationLevel = item.indentationLevel
                menuItem.isEnabled = item.isEnabled
                button.menu?.addItem(menuItem)
            }
        }
        if button.indexOfSelectedItem != selectedIndex, button.itemArray.indices.contains(selectedIndex) {
            button.selectItem(at: selectedIndex)
        }
        if button.font != font { button.font = font }
        button.contentTintColor = NSColor(textColour)
        button.setAccessibilityLabel(accessibilityLabel)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSPopUpButton, context: Context) -> CGSize? {
        guard hugsTitle else { return nil }
        let natural = button.intrinsicContentSize
        let width = proposal.width.map { min($0, natural.width) } ?? natural.width
        return CGSize(width: width, height: proposal.height ?? natural.height)
    }
}

// MARK: - Number field

/// A small Claude number field (`SAClaudeFieldChrome`): the number right-aligned in monospaced digits, the unit's
/// suffix after it inside the field in the muted colour ("60 s"). Typing doesn't write; Return or leaving the field
/// commits through `SAClaudeSettingsValues.parse` — a value outside `range` or not a number is refused with a beep and
/// the field shows the old value again (as the XIB formatters refused it); Escape restores the old value. A value
/// changed elsewhere shows while the field isn't being edited.
struct SAClaudeNumberField: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: SAClaudeSettingUnit
    let accessibilityLabel: String
    var size: SAClaudeControlSize = .form

    @State private var text = ""
    @FocusState private var isFocused: Bool

    init(value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: SAClaudeSettingUnit,
         accessibilityLabel: String, size: SAClaudeControlSize = .form) {
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.accessibilityLabel = accessibilityLabel
        self.size = size
    }

    /// Wide enough for the range's longest number (and "0.0" for tenths) plus the suffix.
    var width: CGFloat {
        let digits = max(SAClaudeSettingsValues.numberText(range.upperBound).count,
                         SAClaudeSettingsValues.isWholeStep(step) ? 1 : 3)
        let suffix: CGFloat = SAClaudeSettingsValues.suffix(for: unit) == nil ? 0 : 12
        return max(44, CGFloat(digits) * 7.5 + 2 * SAClaudeSwiftUIMetrics.fieldHorizontalPadding + suffix)
    }

    var body: some View {
        SAClaudeFieldChrome(isFocused: isFocused, size: size) {
            HStack(spacing: 3) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(SAClaudeSwiftUIMetrics.bodyFont.monospacedDigit())
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: revert)
                    .accessibilityLabel(Text(accessibilityLabel))
                if let suffix = SAClaudeSettingsValues.suffix(for: unit) {
                    Text(suffix)
                        .font(SAClaudeSwiftUIMetrics.bodyFont)
                        .foregroundColor(palette.muted)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: width)
        .onAppear(perform: revert)
        .onChange(of: value) { _ in if !isFocused { revert() } }
        .onChange(of: isFocused) { focused in if !focused { commit() } }
    }

    /// Shows the stored value.
    private func revert() {
        text = SAClaudeSettingsValues.numberText(value)
    }

    /// Writes the typed value, or refuses it and shows the old one. Unchanged text writes nothing.
    private func commit() {
        guard text != SAClaudeSettingsValues.numberText(value) else { return }
        if let parsed = SAClaudeSettingsValues.parse(text, range: range, step: step) {
            if parsed != value { value = parsed }
            text = SAClaudeSettingsValues.numberText(parsed)
        } else {
            NSSound.beep()
            revert()
        }
    }
}
