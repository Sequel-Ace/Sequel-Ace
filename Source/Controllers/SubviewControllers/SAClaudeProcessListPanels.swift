//
//  SAClaudeProcessListPanels.swift
//  Sequel Ace
//
//  The Process List window's SwiftUI parts: the header row (filter chips with counts, the threshold pill, search,
//  Refresh, the Auto refresh switch and the gear), the muted notes line under it, and the detail panel (the connection,
//  its whole query, Copy query / Open in editor / Kill query / Kill connection). Hosted by `SAClaudeProcessListContent`
//  (SAClaudeProcessListView.swift), which owns the list and feeds these models. App target only.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Tones

/// The status tones as SwiftUI colours, from the palette's lightness (the tones themselves: SAClaudeProcessListTones.swift).
extension SAClaudeProcessListTones {
    @MainActor
    static func colour(for group: SAClaudeProcessGroup, palette: SAClaudeSwiftUIPalette) -> Color {
        Color(nsColor: colour(for: group, dark: palette.isDark))
    }

    @MainActor
    static func tint(for group: SAClaudeProcessGroup, palette: SAClaudeSwiftUIPalette) -> Color {
        Color(nsColor: tint(for: group, dark: palette.isDark))
    }
}

// MARK: - Strings

enum SAClaudeProcessListStrings {
    static func chipTitle(_ filter: SAClaudeProcessListFilter) -> String {
        switch filter {
        case .all: return NSLocalizedString("All", value: "All", comment: "process list : filter chip showing every connection")
        case .needsAttention: return NSLocalizedString("Needs attention", value: "Needs attention", comment: "process list : filter chip and status of lock waits and long-running queries")
        case .running: return NSLocalizedString("Running", value: "Running", comment: "process list : filter chip and status of connections running a command")
        case .idle: return NSLocalizedString("Idle", value: "Idle", comment: "process list : filter chip and status of sleeping connections and background threads")
        case .mine: return NSLocalizedString("Mine", value: "Mine", comment: "process list : filter chip showing connections of this window's user")
        }
    }

    static func thresholdTitle(_ seconds: Int) -> String {
        switch seconds {
        case 10: return NSLocalizedString("Over 10 s", value: "Over 10 s", comment: "process list : threshold pill — a query running longer than 10 seconds needs attention")
        case 60: return NSLocalizedString("Over 1 min", value: "Over 1 min", comment: "process list : threshold pill — a query running longer than 1 minute needs attention")
        case 300: return NSLocalizedString("Over 5 min", value: "Over 5 min", comment: "process list : threshold pill — a query running longer than 5 minutes needs attention")
        default: return NSLocalizedString("Over 30 s", value: "Over 30 s", comment: "process list : threshold pill — a query running longer than 30 seconds needs attention")
        }
    }
}

// MARK: - Header

/// The header row's state. Writes go back to the window through the action closures (set by the content).
@MainActor
final class SAClaudeProcessListHeaderModel: ObservableObject {
    @Published var counts = SAClaudeProcessListCounts()
    @Published var filter: SAClaudeProcessListFilter = .all {
        didSet { if filter != oldValue { onChange() } }
    }
    @Published var search = "" {
        didSet { if search != oldValue { onChange() } }
    }
    @Published private(set) var thresholdIndex = 1
    /// The Auto refresh switch. A user toggle calls `onAutoRefresh`; the window sets `autoRefreshFromWindow`.
    @Published var autoRefresh = false {
        didSet { if autoRefresh != oldValue, !applyingFromWindow { onAutoRefresh(autoRefresh) } }
    }
    @Published var showsSpinner = false
    /// Bumped to put the caret in the search field (⌘F).
    @Published private(set) var searchFocusRequest = 0
    /// The notes line: the shared-connection note and the last refresh error.
    @Published var notes: [String] = []

    var onChange: () -> Void = {}
    var onAutoRefresh: (Bool) -> Void = { _ in }
    var onRefresh: () -> Void = {}
    var onGear: (NSView) -> Void = { _ in }
    var onThreshold: (Int) -> Void = { _ in }

    private var applyingFromWindow = false

    var thresholds: [Int] { SAClaudeProcessClassifier.thresholds }

    func setAutoRefreshFromWindow(_ on: Bool) {
        applyingFromWindow = true
        autoRefresh = on
        applyingFromWindow = false
    }

    func setThresholdIndex(_ index: Int) {
        guard thresholds.indices.contains(index) else { return }
        if thresholdIndex != index { thresholdIndex = index }
    }

    func pickThreshold(_ index: Int) {
        guard thresholds.indices.contains(index) else { return }
        setThresholdIndex(index)
        onThreshold(thresholds[index])
    }

    func focusSearch() { searchFocusRequest += 1 }
}

struct SAClaudeProcessListHeader: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @ObservedObject var model: SAClaudeProcessListHeaderModel

    static let height: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                chips(compact: false)
                chips(compact: true)
            }
            .layoutPriority(1)
            // No minimum: the HStack's spacing keeps the chips apart from the pill, so the named chips fit at the
            // window's usual width (≈925pt) with the search field at its 160pt minimum.
            Spacer(minLength: 0)
            SAClaudePopUpPill(titles: model.thresholds.map(SAClaudeProcessListStrings.thresholdTitle),
                              selectedIndex: model.thresholdIndex,
                              accessibilityLabel: NSLocalizedString("Needs attention after", value: "Needs attention after", comment: "process list : accessibility label of the threshold pill"),
                              onSelect: { model.pickThreshold($0) })
                .fixedSize()
                .help(NSLocalizedString("A command running longer than this needs attention", value: "A command running longer than this needs attention", comment: "process list : tooltip of the threshold pill"))
            SAClaudeProcessListSearchField(model: model)
                .frame(minWidth: 160, idealWidth: 220, maxWidth: 260)
            refreshButton
            Toggle(NSLocalizedString("Auto refresh", value: "Auto refresh", comment: "process list : auto refresh switch"), isOn: $model.autoRefresh)
                .toggleStyle(SAClaudeSwitchToggleStyle())
                .fixedSize()
                .help(NSLocalizedString("Auto refresh the list (⇧⌘R)", value: "Auto refresh the list (⇧⌘R)", comment: "process list : tooltip of the auto refresh switch"))
            SAClaudeProcessListGearButton(model: model)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.surface)
    }

    private func chips(compact: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(SAClaudeProcessListFilter.allCases, id: \.self) { filter in
                SAClaudeProcessListChip(filter: filter, count: model.counts.count(for: filter), compact: compact,
                                        isSelected: model.filter == filter) { model.filter = filter }
            }
        }
        .fixedSize()
    }

    private var refreshButton: some View {
        Button { model.onRefresh() } label: {
            ZStack {
                if model.showsSpinner {
                    ProgressView().controlSize(.small).scaleEffect(0.75)
                } else {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .regular))
                }
            }
        }
        .buttonStyle(SAClaudeGhostIconButtonStyle())
        .disabled(model.autoRefresh)
        .help(NSLocalizedString("Refresh the list (⌘R)", value: "Refresh the list (⌘R)", comment: "process list : tooltip of the refresh button"))
        .accessibilityLabel(NSLocalizedString("Refresh", comment: "Refresh"))
    }
}

/// A filter chip: a capsule with the status dot, the title and the live count; the selected chip filled.
struct SAClaudeProcessListChip: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @State private var isHovered = false
    let filter: SAClaudeProcessListFilter
    let count: Int
    let compact: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let ink = group.map { SAClaudeProcessListTones.colour(for: $0, palette: palette) }
        Button(action: action) {
            HStack(spacing: 4) {
                if let ink { Circle().fill(ink).frame(width: 7, height: 7) }
                if !compact || ink == nil {
                    Text(SAClaudeProcessListStrings.chipTitle(filter))
                        .foregroundColor(isSelected ? (ink ?? palette.text) : palette.secondary)
                }
                Text(verbatim: String(count))
                    .monospacedDigit()
                    .foregroundColor(countColour)
            }
            .font(.system(size: 12, weight: isSelected ? .medium : .regular))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(isSelected ? selectedFill : isHovered ? palette.hover : Color.clear))
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : palette.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(SAClaudeBareButtonStyle())
        .onHover { isHovered = $0 }
        .help(SAClaudeProcessListStrings.chipTitle(filter))
        .accessibilityLabel("\(SAClaudeProcessListStrings.chipTitle(filter)), \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The status group a status chip filters on; nil for All and Mine.
    private var group: SAClaudeProcessGroup? {
        switch filter {
        case .needsAttention: return .needsAttention
        case .running: return .running
        case .idle: return .idle
        case .all, .mine: return nil
        }
    }

    /// A status chip's count is in its group's ink while it counts something, muted at 0; All and Mine are muted.
    private var countColour: Color {
        guard let group, let colour = SAClaudeProcessListTones.countColour(for: group, count: count, dark: palette.isDark) else {
            return palette.muted
        }
        return Color(nsColor: colour)
    }

    /// A selected status chip is filled with its group's tint, the others with the selected fill.
    private var selectedFill: Color {
        group.map { SAClaudeProcessListTones.tint(for: $0, palette: palette) } ?? palette.selected
    }
}

/// The search field: magnifier, text, a clear button; Escape clears it.
struct SAClaudeProcessListSearchField: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @ObservedObject var model: SAClaudeProcessListHeaderModel
    @FocusState private var focused: Bool

    var body: some View {
        SAClaudeFieldChrome(isFocused: focused, size: .form) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
                TextField(NSLocalizedString("ClaudeProcessListSearchPlaceholder", value: "Search", comment: "process list : search field placeholder (short: the field may be 160pt wide; its tooltip names what it searches)"),
                          text: $model.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                    .onExitCommand { model.search = "" }
                    // On the text field itself (on the field's chrome it would also name the clear button).
                    .accessibilityLabel(NSLocalizedString("Search user, host, database, state, query", value: "Search user, host, database, state, query", comment: "process list : search field placeholder"))
                if !model.search.isEmpty {
                    Button { model.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(palette.muted)
                    }
                    .buttonStyle(SAClaudeBareButtonStyle())
                    .accessibilityLabel(NSLocalizedString("Clear search", value: "Clear search", comment: "process list : clear the search field"))
                }
            }
        }
        .help(NSLocalizedString("Search user, host, database, state, query", value: "Search user, host, database, state, query", comment: "process list : search field placeholder"))
        .onChange(of: model.searchFocusRequest) { _ in focused = true }
    }
}

/// The gear: a ghost icon that opens the window's gear menu (Auto Refresh Interval, Save As…) under itself.
struct SAClaudeProcessListGearButton: View {
    @ObservedObject var model: SAClaudeProcessListHeaderModel
    @State private var anchor = SAClaudeProcessListAnchor.Holder()

    var body: some View {
        Button {
            if let view = anchor.view { model.onGear(view) }
        } label: {
            Image(systemName: "gearshape").font(.system(size: 13, weight: .regular))
        }
        .buttonStyle(SAClaudeGhostIconButtonStyle())
        .background(SAClaudeProcessListAnchor(holder: anchor))
        .help(NSLocalizedString("More", value: "More", comment: "process list : tooltip of the gear menu"))
        .accessibilityLabel(NSLocalizedString("More", value: "More", comment: "process list : tooltip of the gear menu"))
    }
}

/// An empty AppKit view behind a SwiftUI control, for menus that open under it.
struct SAClaudeProcessListAnchor: NSViewRepresentable {
    final class Holder {
        weak var view: NSView?
    }

    let holder: Holder

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        holder.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        holder.view = view
    }
}

/// The muted line under the header: the shared-connection note and the last refresh error (the list is kept).
struct SAClaudeProcessListNotes: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @ObservedObject var model: SAClaudeProcessListHeaderModel

    static let height: CGFloat = 22

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 11))
            Text(model.notes.joined(separator: "  ·  "))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(model.notes.joined(separator: "\n"))
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundColor(palette.muted)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.surface)
    }
}

// MARK: - Detail panel

@MainActor
final class SAClaudeProcessDetailModel: ObservableObject {
    @Published var detail: SAClaudeProcessDetailState?
    @Published var threshold = SAClaudeProcessClassifier.defaultThreshold

    var onCopy: () -> Void = {}
    var onOpenInEditor: () -> Void = {}
    var onKillQuery: () -> Void = {}
    var onKillConnection: () -> Void = {}
    var onShowCurrent: () -> Void = {}
}

struct SAClaudeProcessDetailPanel: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @ObservedObject var model: SAClaudeProcessDetailModel

    var body: some View {
        Group {
            if let detail = model.detail {
                content(detail)
            } else {
                Text(NSLocalizedString("Select a connection to see its whole query.", value: "Select a connection to see its whole query.", comment: "process list : detail panel with nothing selected"))
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.surface)
    }

    private func content(_ detail: SAClaudeProcessDetailState) -> some View {
        let process = detail.shown
        let group = SAClaudeProcessClassifier.group(process, threshold: model.threshold)
        let tone = SAClaudeProcessListTones.colour(for: group, palette: palette)
        let attention = group == .needsAttention && !detail.hasEnded
        let background = SAClaudeProcessClassifier.isBackground(process)
        let state = SAClaudeProcessListModel.stateText(process, isBackground: background)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(detail.hasEnded ? palette.muted : tone).frame(width: 8, height: 8)
                Text(String(format: NSLocalizedString("Connection #%lld", value: "Connection #%lld", comment: "process list : detail panel title (connection id)"), detail.id))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.text)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                Text(SAClaudeProcessClassifier.timeText(process.time))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(attention ? tone : palette.muted)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                fact(NSLocalizedString("Connection", value: "Connection", comment: "process list : detail panel label of user@host"),
                     "\(process.user)@\(process.host)")
                fact(NSLocalizedString("Database", comment: "Database"), process.db ?? "—")
                fact(NSLocalizedString("State", value: "State", comment: "process list : detail panel label of the state and time"),
                     state + " · " + SAClaudeProcessClassifier.timeText(process.time), colour: attention ? tone : nil)
            }
            if detail.hasEnded {
                note(NSLocalizedString("This connection has ended.", value: "This connection has ended.", comment: "process list : detail panel of a connection no longer listed"))
            } else if detail.hasMovedOn {
                HStack(spacing: 8) {
                    note(NSLocalizedString("This connection has moved on — showing the query as it was", value: "This connection has moved on — showing the query as it was", comment: "process list : detail panel keeps the query it showed after the connection changed"))
                    Button(NSLocalizedString("Show current", value: "Show current", comment: "process list : show what the connection runs now")) { model.onShowCurrent() }
                        .buttonStyle(SAClaudeLinkButtonStyle())
                }
            }
            SAClaudeProcessQueryBox(query: detail.shownQuery, emptyText: SAClaudeProcessListModel.emptyQueryText(process))
            buttons(detail)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func fact(_ label: String, _ value: String, colour: Color? = nil) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(palette.muted)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(colour ?? palette.text)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundColor(palette.muted)
    }

    private func buttons(_ detail: SAClaudeProcessDetailState) -> some View {
        let hasQuery = detail.shownQuery != nil
        let canKill = detail.killTarget != nil
        let copy = Button(NSLocalizedString("Copy query", value: "Copy query", comment: "process list : copy the query shown in the detail panel")) { model.onCopy() }
            .buttonStyle(SAClaudeSecondaryButtonStyle(size: .form)).disabled(!hasQuery)
        let open = Button(NSLocalizedString("Open in editor", value: "Open in editor", comment: "process list : insert the query into the window's Query editor")) { model.onOpenInEditor() }
            .buttonStyle(SAClaudeSecondaryButtonStyle(size: .form)).disabled(!hasQuery)
            .help(NSLocalizedString("Insert this query into the window's Query editor", value: "Insert this query into the window's Query editor", comment: "process list : tooltip of Open in editor"))
        let killQuery = Button(NSLocalizedString("Kill query", value: "Kill query", comment: "process list : kill the query of the connection shown")) { model.onKillQuery() }
            .buttonStyle(SAClaudeDestructiveSecondaryButtonStyle()).disabled(!canKill)
        let killConnection = Button(NSLocalizedString("Kill connection", value: "Kill connection", comment: "process list : kill the connection shown")) { model.onKillConnection() }
            .buttonStyle(SAClaudeDestructiveSecondaryButtonStyle()).disabled(!canKill)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { copy; open; Spacer(minLength: 12); killQuery; killConnection }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { copy; open }
                HStack(spacing: 8) { killQuery; killConnection }
            }
        }
    }
}

/// The whole query: mono 12pt, wrapped, selectable, scrollable, in a field-like box; without one, `emptyText`
/// ("idle connection" for a sleeping client, "no query" otherwise).
struct SAClaudeProcessQueryBox: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    let query: String?
    let emptyText: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SAClaudeSheetColours.fieldRadius, style: .continuous)
        ZStack(alignment: .topLeading) {
            if let query {
                SAClaudeProcessQueryText(text: query, textColour: NSColor(palette.text))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
            } else {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(palette.fieldFill))
        .overlay(shape.strokeBorder(palette.hairline, lineWidth: 1))
        .clipShape(shape)
    }
}

/// A read-only, selectable NSTextView in a scroll view. The text is replaced only when it changes, so a refresh
/// showing the same query keeps the selection and the scroll position.
struct SAClaudeProcessQueryText: NSViewRepresentable {
    let text: String
    let textColour: NSColor

    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.drawsBackground = false
            textView.font = Self.font
            textView.textContainerInset = NSSize(width: 4, height: 2)
            textView.textContainer?.widthTracksTextView = true
            textView.isAutomaticLinkDetectionEnabled = false
            textView.setAccessibilityLabel(NSLocalizedString("Query", comment: "Query"))
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.scrollToBeginningOfDocument(nil)
        }
        if textView.textColor != textColour { textView.textColor = textColour }
        if textView.font != Self.font { textView.font = Self.font }
    }
}

/// A destructive secondary button (Kill query / Kill connection): the title in red on no fill, a red dashed outline —
/// the alert card's other delete-type button; pressed, filled with the red at 10%; 45% disabled.
struct SAClaudeDestructiveSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        @EnvironmentObject var palette: SAClaudeSwiftUIPalette
        @Environment(\.isEnabled) var isEnabled
        let configuration: ButtonStyleConfiguration

        var body: some View {
            let size = SAClaudeControlSize.form
            let red = Color(nsColor: SAClaudeProcessListTones.red(dark: palette.isDark))
            let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
            let inset = SAClaudeAlertChrome.destructiveOutlineInset
            configuration.label
                .font(SAClaudeSwiftUIMetrics.buttonFont)
                .foregroundColor(red)
                .lineLimit(1)
                .padding(.horizontal, SAClaudeSwiftUIMetrics.buttonHorizontalPadding)
                .frame(minWidth: SAClaudeSwiftUIMetrics.buttonMinWidth)
                .frame(height: size.buttonHeight)
                .background(shape.fill(configuration.isPressed && isEnabled ? red.opacity(Double(SAClaudeAlertChrome.destructiveOutlinePressedAlpha)) : Color.clear))
                .overlay(shape.inset(by: inset)
                    .stroke(red, style: StrokeStyle(lineWidth: SAClaudeAlertChrome.destructiveOutlineWidth,
                                                    dash: SAClaudeAlertChrome.destructiveOutlineDash)))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.disabledOpacity)
        }
    }
}
