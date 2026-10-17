//
//  SAClaudeRecordPanel.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  The Record View panel's Claude body: a header (row position, table, ↑ ↓), the search field, one block per field
//  (name, type, the value wrapped in full, long values collapsed to 6 lines) and a hint footer, drawn in the editor
//  theme's palette (SAClaudeSwiftUIStyle.swift). The model, the overlay, the resize handle and the key monitor stay in
//  SARecordView.swift (shared with Unit Tests, which use a stand-in for `SARecordViewPanelHost`). App target only.
//

import AppKit
import Combine
import CoreText
import SwiftUI

// MARK: - Host

/// Owns what the panel draws with and hosts it: the editor-theme palette, the measured-lines cache and the hosting
/// view; styles the overlay container (surface, left hairline, the theme's lightness) and keeps it live.
@MainActor
final class SARecordViewPanelHost {
    let view: NSView
    private let palette = SAClaudeSwiftUIPalette(source: .editorTheme)
    private var subscriptions: Set<AnyCancellable> = []

    init(model: SARecordViewModel) {
        view = SARecordPanelHostingView(rootView: SARecordPanelRoot(model: model, palette: palette, lines: SAClaudeRecordLineCache()))
    }

    /// The palette's surface behind the panel (no gap shows while it resizes), a 1pt hairline down its left edge
    /// (the edge it shares with the grid), and the theme's lightness (the search field's caret, context menus).
    func style(_ container: NSView) {
        let edge = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: container.bounds.height))
        edge.wantsLayer = true
        edge.autoresizingMask = [.height]
        container.addSubview(edge, positioned: .above, relativeTo: nil)
        container.wantsLayer = true
        palette.$hairline.combineLatest(palette.$surface, palette.$isDark)
            .sink { [weak container, weak edge] hairline, surface, isDark in
                edge?.layer?.backgroundColor = NSColor(hairline).cgColor
                container?.layer?.backgroundColor = NSColor(surface).cgColor
                container?.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            }
            .store(in: &subscriptions)
    }
}

/// The panel takes the keyboard itself when its field blocks are focused (they are drawn, not AppKit views); the key
/// monitor then routes ↑/↓, Return, ⌥↑/⌥↓ and typing to the model.
private final class SARecordPanelHostingView: NSHostingView<SARecordPanelRoot> {
    override var acceptsFirstResponder: Bool { true }
}

private struct SARecordPanelRoot: View {
    let model: SARecordViewModel
    let palette: SAClaudeSwiftUIPalette
    let lines: SAClaudeRecordLineCache

    var body: some View {
        SAClaudeRecordPanelView(model: model, lines: lines)
            .environmentObject(palette)
    }
}

// MARK: - Measured lines

/// Where a value wraps in the panel. The panel draws values with SwiftUI `Text` (Core Text); this measures with Core
/// Text's own line breaking (`CTTypesetterSuggestLineBreak`) in the same font and width, so the count and the 6-line
/// cut match what is drawn. Lines here are wrapped lines, not "\n"-separated ones: the collapse, the "Show all N
/// lines" count and "a match below the 6th line" all use them.
struct SAClaudeRecordLineLayout: Equatable {
    /// Wrapped lines the whole value takes.
    var lineCount: Int
    /// UTF-16 offset where the first line past the collapsed limit starts (the text's length when it fits).
    var collapsedEnd: Int

    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    static func measure(_ text: String, width: CGFloat, limit: Int = SAClaudeRecordFields.collapsedLineLimit) -> SAClaudeRecordLineLayout {
        let string = text as NSString
        let length = string.length
        guard length > 0, width > 1 else {
            return SAClaudeRecordLineLayout(lineCount: 1, collapsedEnd: length)
        }
        // A typesetter over a whole long paragraph makes each suggested break cost the rest of the paragraph
        // (quadratic: ~0.8s for one 100,000-character line). Breaking within a window from the line's start gives the
        // same breaks while the window is far longer than a line can hold (even 1pt-wide characters): linear.
        let window = max(1_024, Int(width.rounded(.up)) * 2)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var start = 0
        var lineCount = 0
        var collapsedEnd = length
        while start < length {
            var end = min(length, start + window)
            if end < length {
                end = NSMaxRange(string.rangeOfComposedCharacterSequence(at: end - 1))
            }
            let chunk = NSAttributedString(string: string.substring(with: NSRange(location: start, length: end - start)), attributes: attributes)
            let typesetter = CTTypesetterCreateWithAttributedString(chunk)
            start += max(CTTypesetterSuggestLineBreak(typesetter, 0, Double(width)), 1)
            lineCount += 1
            if lineCount == limit {
                collapsedEnd = start
            }
        }
        // A trailing line break draws one more (empty) line.
        if string.character(at: length - 1) == 0x0A {
            lineCount += 1
        }
        return SAClaudeRecordLineLayout(lineCount: lineCount, collapsedEnd: min(collapsedEnd, length))
    }
}

/// Measured lines per field and width for the shown snapshot (`SARecordViewModel.generation`): a value is measured
/// once per width, not on every body pass; a new snapshot (row change, refresh) starts over.
final class SAClaudeRecordLineCache {
    private struct Key: Hashable {
        var fieldID: Int
        var width: CGFloat
    }

    private var generation = -1
    private var layouts: [Key: SAClaudeRecordLineLayout] = [:]

    func layout(fieldID: Int, generation: Int, text: String, width: CGFloat) -> SAClaudeRecordLineLayout {
        if generation != self.generation {
            self.generation = generation
            layouts = [:]
        }
        let key = Key(fieldID: fieldID, width: width)
        if let layout = layouts[key] {
            return layout
        }
        let layout = SAClaudeRecordLineLayout.measure(text, width: width)
        layouts[key] = layout
        return layout
    }
}

// MARK: - Panel

private enum SARecordPanelMetrics {
    static let horizontalPadding: CGFloat = 12
    static let blockVerticalPadding: CGFloat = 8
    static let selectionInset: CGFloat = 4
    static let selectionRadius: CGFloat = 8
    static let hairline: CGFloat = 1
    static let nameFont = Font.system(size: 12)
    static let typeFont = Font.system(size: 10)
    static let valueFont = Font.system(size: 12, design: .monospaced)
    static let chipFont = Font.system(size: 11)
    static let hintFont = Font.system(size: 11)
    static let headerFont = Font.system(size: 13, weight: .medium)
    static let emptyFont = Font.system(size: 13)
    static let footerHeight: CGFloat = 28
    /// The copy icon's room at the end of the name line.
    static let copyRoom: CGFloat = 22
}

private struct SARecordListWidthKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

private struct SAClaudeRecordPanelView: View {
    @ObservedObject var model: SARecordViewModel
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    let lines: SAClaudeRecordLineCache
    @FocusState private var searchFocused: Bool
    @FocusState private var editorFocus: SARecordField.ID?
    /// How much narrower the laid-out list is than the panel (the scroll view keeps a scroller's width clear), as
    /// last measured; values wrap in the list's width, so measuring them needs it before the list is laid out.
    @State var listInset = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                if model.selectedRowCount == 0 {
                    emptyState("Select one row to view it", systemImage: "rectangle.and.hand.point.up.left")
                } else if model.selectedRowCount > 1 {
                    emptyState("Select only one row", systemImage: "rectangle.stack")
                } else if model.fields.isEmpty {
                    emptyState("This record has no fields", systemImage: "list.bullet.rectangle")
                } else {
                    let result = model.searchResult
                    searchField(result)
                    hairline
                    fieldList(result, textWidth: textWidth(panelWidth: proxy.size.width))
                        .onPreferenceChange(SARecordListWidthKey.self) { width in
                            if let width, abs(proxy.size.width - width - listInset) > 0.5 {
                                listInset = max(proxy.size.width - width, 0)
                            }
                        }
                    hairline
                    footer
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(minWidth: 240, idealWidth: 320)
        .background(palette.surface)
        .onChange(of: model.focusedFieldID) { editorFocus = $0 }
        .onChange(of: editorFocus) { model.editorFocusChanged($0) }
        .onChange(of: model.focusRequestID) { _ in
            if model.focusTarget == .filter {
                searchFocused = true
            }
        }
    }

    /// The width a value wraps in: the list's width less the block padding.
    private func textWidth(panelWidth: CGFloat) -> CGFloat {
        max(panelWidth - listInset - SARecordPanelMetrics.horizontalPadding * 2, 1)
    }

    // MARK: Header

    private var header: some View {
        let step = SAClaudeRecordFields.rowStep(index: model.rowIndex, count: model.rowCount)
        return HStack(spacing: 2) {
            headerTitle
                .font(SARecordPanelMetrics.headerFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.stepRow(-1) } label: {
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(SAClaudeGhostIconButtonStyle())
            .disabled(!step.previous)
            .help(NSLocalizedString("ClaudeRecordPreviousRow", value: "Previous row (⌥↑)", comment: "Record View: tooltip of the header button that shows the previous row"))
            .accessibilityLabel(Text(NSLocalizedString("ClaudeRecordPreviousRow", value: "Previous row (⌥↑)", comment: "Record View: tooltip of the header button that shows the previous row")))
            Button { model.stepRow(1) } label: {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(SAClaudeGhostIconButtonStyle())
            .disabled(!step.next)
            .help(NSLocalizedString("ClaudeRecordNextRow", value: "Next row (⌥↓)", comment: "Record View: tooltip of the header button that shows the next row"))
            .accessibilityLabel(Text(NSLocalizedString("ClaudeRecordNextRow", value: "Next row (⌥↓)", comment: "Record View: tooltip of the header button that shows the next row")))
        }
        .padding(.leading, SARecordPanelMetrics.horizontalPadding)
        .padding(.trailing, SARecordPanelMetrics.horizontalPadding - 4)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// "Row N of M" in the text colour, then " · <title>" muted; the title alone when the row isn't known.
    private var headerTitle: Text {
        let hasRow = model.rowIndex >= 0 && model.rowCount > 0
        let row = hasRow
            ? String(format: NSLocalizedString("ClaudeRecordRowPosition", value: "Row %1$ld of %2$ld", comment: "Record View header: the shown row's position in the grid; %1$ld is the row number, %2$ld the number of rows"),
                     model.rowIndex + 1, model.rowCount)
            : ""
        switch (row.isEmpty, model.title.isEmpty) {
        case (false, false):
            return Text(verbatim: row).foregroundColor(palette.text)
                + Text(verbatim: " · " + model.title).foregroundColor(palette.muted).fontWeight(.regular)
        case (false, true):
            return Text(verbatim: row).foregroundColor(palette.text)
        case (true, false):
            return Text(verbatim: model.title).foregroundColor(palette.text)
        case (true, true):
            return Text(verbatim: "")
        }
    }

    // MARK: Search

    private func searchField(_ result: SARecordViewSearchResult) -> some View {
        let hasQuery = !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return SAClaudeFieldChrome(isFocused: searchFocused, size: .panel) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.muted)
                TextField(NSLocalizedString("ClaudeRecordSearchPlaceholder", value: "Search fields and values", comment: "Record View: placeholder of the search field above the fields"),
                          text: $model.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onExitCommand(perform: model.escapeInSearch)
                    .accessibilityLabel(Text(NSLocalizedString("ClaudeRecordSearchPlaceholder", value: "Search fields and values", comment: "Record View: placeholder of the search field above the fields")))
                if hasQuery {
                    Text(verbatim: SAClaudeRecordFields.matchCountText(result.matchCount))
                        .font(SARecordPanelMetrics.hintFont)
                        .foregroundColor(palette.muted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, SARecordPanelMetrics.horizontalPadding)
        .padding(.bottom, 10)
    }

    // MARK: Fields

    private func fieldList(_ result: SARecordViewSearchResult, textWidth: CGFloat) -> some View {
        let firstID = result.fields.first?.id
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(result.fields) { field in
                        SAClaudeRecordBlock(
                            model: model,
                            field: field,
                            display: model.display(for: field),
                            match: result.matches[field.id],
                            isSelected: model.selectedFieldID == field.id,
                            isEditing: model.editingFieldID == field.id,
                            isExpanded: model.isExpanded(field.id),
                            showsSeparator: field.id != firstID,
                            textWidth: textWidth,
                            lines: lines,
                            generation: model.generation,
                            editorFocus: $editorFocus
                        )
                        .id(field.id)
                    }
                }
                .background(GeometryReader { Color.clear.preference(key: SARecordListWidthKey.self, value: $0.size.width) })
            }
            .onChange(of: model.selectedFieldID) { fieldID in
                if let fieldID {
                    proxy.scrollTo(fieldID)
                }
            }
            .onAppear {
                if let fieldID = model.selectedFieldID {
                    proxy.scrollTo(fieldID)
                }
            }
        }
        // A fresh list per row: a lazy stack keeps the heights it measured for an ID and estimates the rest from
        // them, so a 5 MB value seen in one row would skew the next row's scroll extent and scroll-to positions (and
        // leave the list blank after a jump). Within a row (refreshes after an edit) the list and its scroll stay;
        // on a new row the selected field is scrolled back into view.
        .id(model.listKey)
    }

    private var hairline: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(height: SARecordPanelMetrics.hairline)
    }

    // MARK: Footer and empty states

    private var footer: some View {
        HStack(spacing: 8) {
            Text(verbatim: NSLocalizedString("ClaudeRecordEditHint", value: "Double-click a value to edit", comment: "Record View footer: how to edit a value"))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(verbatim: NSLocalizedString("ClaudeRecordRowsHint", value: "⌥↑↓ rows", comment: "Record View footer: the keys that show the previous / next row"))
                .lineLimit(1)
                .fixedSize()
        }
        .font(SARecordPanelMetrics.hintFont)
        .foregroundColor(palette.muted)
        .padding(.horizontal, SARecordPanelMetrics.horizontalPadding)
        .frame(height: SARecordPanelMetrics.footerHeight)
    }

    private func emptyState(_ title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
            Text(title)
                .font(SARecordPanelMetrics.emptyFont)
                .multilineTextAlignment(.center)
        }
        .foregroundColor(palette.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Field block

/// One field: the name (search hits highlighted) and its column type on the first line, the copy icon at that line's
/// end on hover; the value below — the NULL chip, "(not loaded)", or the text wrapped in full, collapsed past 6 lines
/// with "Show all N lines" / "Show less" — or the inline editor while it is being edited.
private struct SAClaudeRecordBlock: View {
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    let model: SARecordViewModel
    let field: SARecordField
    let display: SAClaudeRecordDisplayValue
    let match: SAClaudeRecordMatch?
    let isSelected: Bool
    let isEditing: Bool
    let isExpanded: Bool
    let showsSeparator: Bool
    let textWidth: CGFloat
    let lines: SAClaudeRecordLineCache
    let generation: Int
    var editorFocus: FocusState<SARecordField.ID?>.Binding
    @State var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            nameLine
            if isEditing {
                SAClaudeRecordEditor(model: model, fieldID: field.id, editorFocus: editorFocus)
            } else {
                value
            }
        }
        .padding(.vertical, SARecordPanelMetrics.blockVerticalPadding)
        .padding(.horizontal, SARecordPanelMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selection)
        .overlay(alignment: .top) {
            if showsSeparator {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: SARecordPanelMetrics.hairline)
            }
        }
        .overlay(alignment: .topTrailing) { copyButton }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .modifier(SAClaudeRecordBlockClicks(isEnabled: !isEditing,
                                            select: { model.selectField(field.id) },
                                            edit: { model.selectField(field.id); model.requestEdit(field) }))
        .contextMenu {
            Button("Copy Value") { copy() }
            Button("Edit Value") { model.requestEdit(field) }
        }
    }

    @ViewBuilder
    private var selection: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: SARecordPanelMetrics.selectionRadius, style: .continuous)
                .fill(palette.selected)
                .padding(SARecordPanelMetrics.selectionInset)
        }
    }

    private var nameLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(SAClaudeRecordHighlight.attributed(field.name, ranges: match?.nameRanges ?? [], highlight: palette.highlight))
                .font(SARecordPanelMetrics.nameFont)
                .foregroundColor(palette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(field.name)
            if !field.type.isEmpty {
                Text(verbatim: field.type.uppercased())
                    .font(SARecordPanelMetrics.typeFont)
                    .foregroundColor(palette.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.trailing, SARecordPanelMetrics.copyRoom)
    }

    @ViewBuilder
    private var copyButton: some View {
        if isHovered && !isEditing {
            Button(action: copy) {
                Image(systemName: "doc.on.doc").font(.system(size: 11))
            }
            .buttonStyle(SAClaudeGhostIconButtonStyle())
            .help(Text("Copy Value"))
            .accessibilityLabel(Text("Copy Value"))
            // Centred on the name line (12pt text, ~15pt tall) at the block's top padding.
            .padding(.top, SARecordPanelMetrics.blockVerticalPadding - 4)
            .padding(.trailing, SARecordPanelMetrics.horizontalPadding - 6)
        }
    }

    @ViewBuilder
    private var value: some View {
        switch display {
        case .null:
            Text(SAClaudeRecordHighlight.attributed("NULL", ranges: match?.valueRanges ?? [], highlight: palette.highlight))
                .font(SARecordPanelMetrics.chipFont)
                .foregroundColor(palette.muted)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(palette.muted.opacity(0.6), lineWidth: 1))
        case .notLoaded:
            Text("(not loaded)")
                .font(SARecordPanelMetrics.nameFont.italic())
                .foregroundColor(palette.muted)
        case .text(let text):
            textValue(text)
        }
    }

    @ViewBuilder
    private func textValue(_ text: String) -> some View {
        let layout = lines.layout(fieldID: field.id, generation: generation, text: text, width: textWidth)
        let ranges = match?.valueRanges ?? []
        let matchBelow = ranges.contains { $0.location >= layout.collapsedEnd }
        let collapsed = SAClaudeRecordFields.isCollapsed(lineCount: layout.lineCount, expanded: isExpanded, matchStartsBelowLimit: matchBelow)
        // Collapsed, only the first 6 lines' text is laid out at all (a 5 MB value draws as fast as a short one).
        let shown = collapsed ? Self.collapsedText(text, end: layout.collapsedEnd) : text
        Text(SAClaudeRecordHighlight.attributed(shown.isEmpty ? " " : shown, ranges: ranges, highlight: palette.highlight))
            .font(SARecordPanelMetrics.valueFont)
            .foregroundColor(palette.text)
            .lineLimit(collapsed ? SAClaudeRecordFields.collapsedLineLimit : nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        // A value a search hit forced open has nothing to fold back while it matches.
        if layout.lineCount > SAClaudeRecordFields.collapsedLineLimit && (collapsed || isExpanded) {
            Button {
                model.toggleExpanded(field.id)
            } label: {
                Text(verbatim: collapsed
                     ? String(format: NSLocalizedString("ClaudeRecordShowAllLines", value: "Show all %d lines", comment: "Record View: link under a collapsed long value; %d is the number of lines the value takes"), layout.lineCount)
                     : NSLocalizedString("ClaudeRecordShowLess", value: "Show less", comment: "Record View: link under an expanded long value that collapses it again"))
            }
            .buttonStyle(SAClaudeLinkButtonStyle())
        }
    }

    private static func collapsedText(_ text: String, end: Int) -> String {
        var head = (text as NSString).substring(to: end)
        if head.hasSuffix("\n") {
            head.removeLast()
        }
        return head
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(field.value, forType: .string)
    }
}

/// Click selects the block, double-click edits it — off while it is being edited, so clicks in the editor stay the
/// editor's. The single click is simultaneous, so selecting doesn't wait out the double-click interval.
private struct SAClaudeRecordBlockClicks: ViewModifier {
    let isEnabled: Bool
    let select: () -> Void
    let edit: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onTapGesture(count: 2, perform: edit)
                .simultaneousGesture(TapGesture().onEnded(select))
        } else {
            content
        }
    }
}

/// The inline value editor (today's semantics): Return commits, Escape cancels, losing focus commits; Return or
/// Escape hands the keyboard back to the blocks.
private struct SAClaudeRecordEditor: View {
    @ObservedObject var model: SARecordViewModel
    let fieldID: SARecordField.ID
    var editorFocus: FocusState<SARecordField.ID?>.Binding

    var body: some View {
        TextField("Value", text: $model.validatedEditDraft)
            .textFieldStyle(SAClaudeFieldStyle(isFocused: editorFocus.wrappedValue == fieldID, size: .panel))
            .focused(editorFocus, equals: fieldID)
            .onSubmit {
                model.commitEdit()
                if model.editingFieldID == nil {
                    returnToBlocks()
                }
            }
            .onExitCommand {
                model.cancelEdit()
                returnToBlocks()
            }
            .onAppear {
                DispatchQueue.main.async {
                    editorFocus.wrappedValue = fieldID
                }
            }
    }

    /// After SwiftUI has taken the editor down (it hands the first responder to the window as it goes).
    private func returnToBlocks() {
        DispatchQueue.main.async { [model] in
            model.requestFocus(.table)
        }
    }
}

// MARK: - Highlight

enum SAClaudeRecordHighlight {
    /// `text` with a highlight wash under each range (UTF-16, as `SAClaudeRecordFields.match` gives them); ranges past
    /// the end of `text` (a collapsed value's cut) are dropped or clipped. Built piecewise, linear in the text.
    static func attributed(_ text: String, ranges: [NSRange], highlight: Color) -> AttributedString {
        let string = text as NSString
        let length = string.length
        guard !ranges.isEmpty else {
            return AttributedString(text)
        }
        var result = AttributedString()
        var cursor = 0
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            let start = max(range.location, cursor)
            let end = min(NSMaxRange(range), length)
            guard start < end else {
                continue
            }
            if start > cursor {
                result += AttributedString(string.substring(with: NSRange(location: cursor, length: start - cursor)))
            }
            var hit = AttributedString(string.substring(with: NSRange(location: start, length: end - start)))
            hit.backgroundColor = highlight
            result += hit
            cursor = end
        }
        if cursor < length {
            result += AttributedString(string.substring(from: cursor))
        }
        return result
    }
}
