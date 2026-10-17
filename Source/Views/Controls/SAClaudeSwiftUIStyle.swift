//
//  SAClaudeSwiftUIStyle.swift
//  Sequel Ace
//
//  The shared Claude look for SwiftUI surfaces: one palette (`SAClaudeSwiftUIPalette`, from the editor theme for
//  panels that sit in the editor's chrome, or the sheets' colours for sheets) and the styles that read it from the
//  environment — the field, the primary / secondary / ghost-icon / link buttons and the checkbox. Values follow the
//  AppKit Claude sheets (SAClaudeSheetStyler, SAClaudeFilterCells) so a SwiftUI sheet sits beside them unchanged.
//  Inject the palette with `.environmentObject(palette)` at the root of the hosted view. App target only.
//

import AppKit
import SwiftUI

// MARK: - Palette

/// The colours a Claude SwiftUI surface draws with, kept live: rebuilt when the editor theme changes (the shared,
/// coalesced `SAClaudeThemeWatcher` check of every defaults write), when the accent changes, and when the app's
/// appearance changes (the theme's fallback colours are dynamic). All colours are resolved, never dynamic.
final class SAClaudeSwiftUIPalette: ObservableObject {

    enum Source {
        /// The editor theme as the ⋯ options card derives it: the popup surface, theme text, status-chrome greys.
        case editorTheme
        /// The Claude sheets' colours (`SAClaudeSheetColours`): their surface, field fill and muted grey, with
        /// Sequel Ace's own text colours for the theme's lightness.
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
        SAClaudeThemeWatcher.observe(self) { $0.refresh(force: false) }
        SAClaudeAccent.observe(self) { $0.refresh(force: true) }
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

    /// The sheets' surface, field fill and muted grey (`SAClaudeSheetColours.current()`, which also sets every
    /// Claude sheet's lightness), Sequel Ace's text colours for that lightness, and the sheets' hairline and hover.
    private func buildApp() {
        let sheet = SAClaudeSheetColours.current()
        let lightness = NSAppearance(named: sheet.isDark ? .darkAqua : .aqua) ?? NSApp.effectiveAppearance
        var colours: [NSColor] = []
        lightness.performAsCurrentDrawingAppearance {
            colours = [sheet.surface,
                       SAClaudeStyle.textPrimary,
                       SAClaudeStyle.textSecondary,
                       sheet.muted,
                       sheet.palette.hairline,
                       SAClaudeEditorChrome.derivedColour(text: sheet.theme.text, background: sheet.surface, ratio: Self.hoverRatio),
                       SAClaudeEditorChrome.derivedColour(text: sheet.theme.text, background: sheet.surface, ratio: Self.selectedRatio),
                       sheet.fieldFill,
                       SAClaudeFilterChrome.dropStroke(text: sheet.theme.text, background: sheet.surface)].map(Self.resolved)
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

// MARK: - Metrics

/// The kit's sizes, shared by the styles (and by views that line other things up with them).
enum SAClaudeSwiftUIMetrics {
    static let controlHeight: CGFloat = 28
    static let controlRadius: CGFloat = 8
    static let fieldHorizontalPadding: CGFloat = 8
    static let fieldFocusWidth: CGFloat = 1.5
    static let buttonHorizontalPadding: CGFloat = 14
    static let buttonMinWidth: CGFloat = 72
    static let buttonFont = Font.system(size: 13, weight: .medium)
    static let bodyFont = Font.system(size: 13)
    /// A disabled field or button (the AppKit sheet buttons' 45%).
    static let disabledOpacity: Double = 0.45
    static let iconButtonSize: CGFloat = 24
    static let iconButtonRadius: CGFloat = 6
    static let iconButtonDisabledOpacity: Double = 0.35
    static let linkFont = Font.system(size: 11)
    static let checkboxSize: CGFloat = 16
    static let checkboxRadius: CGFloat = 4
    static let checkboxGap: CGFloat = 6
    /// A disabled checkbox (the AppKit Claude checkbox's 40%).
    static let checkboxDisabledOpacity: Double = 0.4
}

// MARK: - Field

/// A Claude text field: 28pt high, 8pt radius, the field fill inside a 1pt hairline, a 1.5pt accent ring while
/// focused. SwiftUI cannot tell a style about focus: pass the field's `@FocusState` in.
struct SAClaudeFieldStyle: TextFieldStyle {
    var isFocused: Bool

    init(isFocused: Bool) {
        self.isFocused = isFocused
    }

    func _body(configuration: TextField<Self._Label>) -> some View {
        SAClaudeFieldChrome(isFocused: isFocused) { configuration.textFieldStyle(.plain) }
    }
}

private struct SAClaudeFieldChrome<Content: View>: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @Environment(\.isEnabled) var isEnabled
    let isFocused: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SAClaudeSwiftUIMetrics.controlRadius, style: .continuous)
        let ring = isFocused && isEnabled
        content()
            .font(SAClaudeSwiftUIMetrics.bodyFont)
            .foregroundColor(palette.text)
            .padding(.horizontal, SAClaudeSwiftUIMetrics.fieldHorizontalPadding)
            .frame(height: SAClaudeSwiftUIMetrics.controlHeight)
            .background(shape.fill(palette.fieldFill))
            .overlay(shape.strokeBorder(ring ? palette.accent : palette.hairline,
                                        lineWidth: ring ? SAClaudeSwiftUIMetrics.fieldFocusWidth : 1))
            .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.disabledOpacity)
    }
}

// MARK: - Buttons

/// The primary (Return) button: the accent fill with an `onAccent` SF Pro 13 medium title, 8pt radius, 28pt high;
/// pressed, the fill 12% towards black (towards white on a dark theme, as the AppKit sheet buttons); 45% disabled.
struct SAClaudePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        @EnvironmentObject var palette: SAClaudeSwiftUIPalette
        @Environment(\.isEnabled) var isEnabled
        let configuration: ButtonStyleConfiguration

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: SAClaudeSwiftUIMetrics.controlRadius, style: .continuous)
            configuration.label
                .font(SAClaudeSwiftUIMetrics.buttonFont)
                .foregroundColor(palette.onAccent)
                .lineLimit(1)
                .padding(.horizontal, SAClaudeSwiftUIMetrics.buttonHorizontalPadding)
                .frame(minWidth: SAClaudeSwiftUIMetrics.buttonMinWidth)
                .frame(height: SAClaudeSwiftUIMetrics.controlHeight)
                .background(shape.fill(configuration.isPressed && isEnabled ? palette.accentPressed : palette.accentFill))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.disabledOpacity)
        }
    }
}

/// A secondary button (Cancel): a 1pt outline on no fill, the title in the text colour, SF Pro 13 medium; the hover
/// fill under the pointer, a little darker pressed; 45% disabled.
struct SAClaudeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        @EnvironmentObject var palette: SAClaudeSwiftUIPalette
        @Environment(\.isEnabled) var isEnabled
        @State var isHovered = false
        let configuration: ButtonStyleConfiguration

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: SAClaudeSwiftUIMetrics.controlRadius, style: .continuous)
            let fill: Color = !isEnabled ? .clear : configuration.isPressed ? palette.selected : isHovered ? palette.hover : .clear
            configuration.label
                .font(SAClaudeSwiftUIMetrics.buttonFont)
                .foregroundColor(palette.text)
                .lineLimit(1)
                .padding(.horizontal, SAClaudeSwiftUIMetrics.buttonHorizontalPadding)
                .frame(minWidth: SAClaudeSwiftUIMetrics.buttonMinWidth)
                .frame(height: SAClaudeSwiftUIMetrics.controlHeight)
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

/// The Claude checkbox: a 16pt rounded square — outlined when off (the hover fill under the pointer), the accent
/// fill with an `onAccent` (white unless the accent is light) tick when on — then the label at 13pt. The whole row
/// toggles; VoiceOver sees an ordinary checkbox. 40% disabled, as the AppKit Claude checkbox.
struct SAClaudeCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        @EnvironmentObject var palette: SAClaudeSwiftUIPalette
        @Environment(\.isEnabled) var isEnabled
        @State var isHovered = false
        let configuration: ToggleStyleConfiguration

        var body: some View {
            Button { configuration.isOn.toggle() } label: {
                HStack(spacing: SAClaudeSwiftUIMetrics.checkboxGap) {
                    box
                    configuration.label
                        .font(SAClaudeSwiftUIMetrics.bodyFont)
                        .foregroundColor(palette.text)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(BareButtonStyle())
            .onHover { isHovered = $0 }
            .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.checkboxDisabledOpacity)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .toggleStyle(.checkbox)
            }
        }

        private var box: some View {
            let size = SAClaudeSwiftUIMetrics.checkboxSize
            let shape = RoundedRectangle(cornerRadius: SAClaudeSwiftUIMetrics.checkboxRadius, style: .continuous)
            return ZStack {
                if configuration.isOn {
                    shape.fill(palette.accentFill)
                    SAClaudeCheckMark()
                        .stroke(palette.onAccent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                } else {
                    shape.fill(isHovered && isEnabled ? palette.hover : Color.clear)
                    shape.strokeBorder(palette.stroke, lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
        }
    }

    /// A plain button look: the label as it is.
    private struct BareButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { configuration.label }
    }
}

/// The tick, in a 16pt box: the AppKit Claude checkbox's 14pt tick scaled up.
private struct SAClaudeCheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 14
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 3.5 * s, y: rect.minY + 7.5 * s))
        path.addLine(to: CGPoint(x: rect.minX + 6 * s, y: rect.minY + 10 * s))
        path.addLine(to: CGPoint(x: rect.minX + 10.5 * s, y: rect.minY + 4.5 * s))
        return path
    }
}
