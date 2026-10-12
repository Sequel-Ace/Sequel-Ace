//
//  SADatabasePicker.swift
//  Sequel Ace
//
//  Searchable replacement for the "choose database" popup's menu. The
//  popup (`SADatabasePopUpButton`) stays the source of truth — every
//  existing ObjC path keeps reading and writing its items — and this
//  picker is just a filterable view over those items: it is rebuilt from
//  the popup's menu each time it opens and reports the chosen database or
//  command back by title.
//
//  Kept free of project ObjC types so the Unit Tests target can compile it.
//

import AppKit
import SwiftUI

/// One database row in the picker.
struct SADatabasePickerEntry: Identifiable, Equatable {
    /// The database name, which is also the popup item's title.
    let name: String
    /// Index of the separator-delimited group the item sits in (system
    /// databases first, then user databases), used to draw dividers.
    let section: Int

    var id: String { name }
}

/// A header action from the popup ("Add Database...", "Refresh Databases").
struct SADatabasePickerCommand: Identifiable, Equatable {
    let title: String

    var id: String { title }
}

final class SADatabasePickerModel: ObservableObject {

    let entries: [SADatabasePickerEntry]
    let commands: [SADatabasePickerCommand]
    let currentDatabase: String?

    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            visibleEntries = Self.filter(entries, query: query)
            highlightedName = Self.initialHighlight(in: visibleEntries,
                                                    query: query,
                                                    currentDatabase: currentDatabase)
            scrollTarget = highlightedName
        }
    }
    @Published private(set) var visibleEntries: [SADatabasePickerEntry]
    @Published var highlightedName: String?
    /// Row to scroll into view. Only keyboard moves and searches set it, so
    /// hovering a row near the edge doesn't scroll the list under the mouse.
    @Published private(set) var scrollTarget: String?

    var onChooseDatabase: (String) -> Void = { _ in }
    var onCommand: (SADatabasePickerCommand) -> Void = { _ in }
    var onCancel: () -> Void = {}

    init(entries: [SADatabasePickerEntry],
         commands: [SADatabasePickerCommand],
         currentDatabase: String?) {
        self.entries = entries
        self.commands = commands
        self.currentDatabase = currentDatabase
        self.visibleEntries = entries
        self.highlightedName = Self.initialHighlight(in: entries, query: "", currentDatabase: currentDatabase)
    }

    /// Reads the popup's menu as `SADatabaseListManager.configurePopup`
    /// lays it out: the placeholder at index 0 is skipped, items tagged
    /// `commandMenuItemTag` become commands, and every other titled item
    /// is a database — including ones `performSelection` appends later.
    convenience init(menu: NSMenu?, currentDatabase: String?) {
        var entries: [SADatabasePickerEntry] = []
        var commands: [SADatabasePickerCommand] = []
        var section = 0

        for (index, item) in (menu?.items ?? []).enumerated() where index > 0 && !item.isHidden {
            if item.isSeparatorItem {
                if entries.last?.section == section {
                    section += 1
                }
            } else if item.tag == SADatabaseListManager.commandMenuItemTag {
                commands.append(SADatabasePickerCommand(title: item.title))
            } else if !item.title.isEmpty {
                entries.append(SADatabasePickerEntry(name: item.title, section: section))
            }
        }

        self.init(entries: entries, commands: commands, currentDatabase: currentDatabase)
    }

    /// Substring match ignoring case, diacritics and width — the same
    /// options as the "Go to Database" dialog. Order is preserved.
    static func filter(_ entries: [SADatabasePickerEntry], query: String) -> [SADatabasePickerEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
        }
    }

    /// With no query the current database is highlighted so the list opens
    /// on it; while searching, an exact match wins, then the first result.
    static func initialHighlight(in visible: [SADatabasePickerEntry],
                                 query: String,
                                 currentDatabase: String?) -> String? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty {
            if let current = currentDatabase, visible.contains(where: { $0.name == current }) {
                return current
            }
            return visible.first?.name
        }
        let exact = visible.first {
            $0.name.compare(needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
        }
        return (exact ?? visible.first)?.name
    }

    /// Moves the highlight by `offset` rows, clamped to the visible list.
    func moveHighlight(by offset: Int) {
        guard !visibleEntries.isEmpty else {
            highlightedName = nil
            return
        }
        let currentIndex = visibleEntries.firstIndex { $0.name == highlightedName }
        let target: Int
        if let currentIndex {
            target = min(max(currentIndex + offset, 0), visibleEntries.count - 1)
        } else {
            target = offset < 0 ? visibleEntries.count - 1 : 0
        }
        highlightedName = visibleEntries[target].name
        scrollTarget = highlightedName
    }

    func chooseHighlighted() {
        guard let name = highlightedName, visibleEntries.contains(where: { $0.name == name }) else { return }
        onChooseDatabase(name)
    }

    /// Escape clears a non-empty search first, then dismisses.
    func cancel() {
        if query.isEmpty {
            onCancel()
        } else {
            query = ""
        }
    }
}

// MARK: - Views

struct SADatabasePickerView: View {

    @ObservedObject var model: SADatabasePickerModel

    private static let rowHeight: CGFloat = 22
    private static let maxListHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            SADatabasePickerSearchField(text: $model.query,
                                        placeholder: Self.searchPlaceholder,
                                        onMove: { model.moveHighlight(by: $0) },
                                        onSubmit: { model.chooseHighlighted() },
                                        onCancel: { model.cancel() })
                .padding(8)

            Divider()

            SADatabasePickerList(model: model, listHeight: listHeight)

            if !model.commands.isEmpty {
                Divider()
                HStack(spacing: 12) {
                    ForEach(model.commands) { command in
                        Button(command.title) { model.onCommand(command) }
                            .buttonStyle(.link)
                    }
                    Spacer()
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 300)
    }

    /// Sized to the full list (so short lists don't leave a gap) and kept
    /// fixed while searching so the popover doesn't jump under the cursor.
    private var listHeight: CGFloat {
        let rows = max(model.entries.count, 3)
        return min(CGFloat(rows) * Self.rowHeight + 8, Self.maxListHeight)
    }

    private static let searchPlaceholder = NSLocalizedString("Search Databases", comment: "database picker : search field placeholder")
}

private struct SADatabasePickerList: View {

    @ObservedObject var model: SADatabasePickerModel
    let listHeight: CGFloat

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.visibleEntries.enumerated()), id: \.element.id) { offset, entry in
                        if offset > 0, model.visibleEntries[offset - 1].section != entry.section {
                            Divider().padding(.vertical, 4)
                        }
                        Button {
                            model.onChooseDatabase(entry.name)
                        } label: {
                            SADatabasePickerRow(name: entry.name,
                                                isCurrent: entry.name == model.currentDatabase,
                                                isHighlighted: entry.name == model.highlightedName)
                                .equatable()
                        }
                        .buttonStyle(.plain)
                        .id(entry.id)
                        .onHover { hovering in
                            if hovering { model.highlightedName = entry.name }
                        }
                    }
                }
                .padding(4)
            }
            .overlay {
                if model.visibleEntries.isEmpty {
                    Text(Self.noMatchesTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: listHeight)
            .onAppear {
                if let name = model.highlightedName {
                    proxy.scrollTo(name, anchor: .center)
                }
            }
            .onChange(of: model.scrollTarget) { name in
                if let name {
                    proxy.scrollTo(name)
                }
            }
        }
    }

    private static let noMatchesTitle = NSLocalizedString("No Matching Databases", comment: "database picker : shown when the search matches no database")
}

private struct SADatabasePickerRow: View, Equatable {

    let name: String
    let isCurrent: Bool
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .opacity(isCurrent ? 1 : 0)
                .accessibilityHidden(!isCurrent)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .foregroundStyle(isHighlighted ? Color(nsColor: .selectedMenuItemTextColor) : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHighlighted ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// NSSearchField wrapper: SwiftUI on macOS 13 can't intercept arrow keys or
/// Return in a focused text field (`onKeyPress` is macOS 14+), and the picker
/// needs them to move through and choose from the list without leaving the
/// search field.
private struct SADatabasePickerSearchField: NSViewRepresentable {

    @Binding var text: String
    var placeholder: String
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.focusRingType = .none
        // The window isn't attached yet on the first update.
        DispatchQueue.main.async {
            searchField.window?.makeFirstResponder(searchField)
        }
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {

        var parent: SADatabasePickerSearchField

        init(_ parent: SADatabasePickerSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let searchField = obj.object as? NSSearchField else { return }
            parent.text = searchField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            default:
                return false
            }
            return true
        }
    }
}
