//
//  SAQueryFavoriteSaveWindowController.swift
//  Sequel Ace
//
//  SwiftUI replacement for the legacy Query Favorite Sheet in DBView.xib.
//


import Combine
import SwiftUI

@MainActor
private final class SAQueryFavoriteSaveViewModel: ObservableObject {
    @Published var name = "" {
        didSet { if name != oldValue { errorMessage = "" } }
    }
    @Published var saveGlobally: Bool
    @Published var selectedFavoriteID: String? {
        didSet {
            if let selectedFavorite {
                saveGlobally = selectedFavorite.scope == .global
            }
            if selectedFavoriteID != oldValue { errorMessage = "" }
        }
    }
    @Published var selections: [SAQueryFavoriteSelection]
    /// Shown under the form in the alert red until the name or the choice changes.
    @Published var errorMessage = ""

    init(saveGlobally: Bool, selections: [SAQueryFavoriteSelection]) {
        self.saveGlobally = saveGlobally
        self.selections = selections
    }

    var selectedFavorite: SAQueryFavoriteSelection? {
        selections.first { $0.id == selectedFavoriteID }
    }

    var canSave: Bool {
        selectedFavorite != nil || !name.isEmpty
    }

    func refreshSelections(_ selections: [SAQueryFavoriteSelection]) {
        self.selections = selections
        selectedFavoriteID = nil
    }

    func showError(_ message: String) {
        errorMessage = message
    }
}

/// The sheet in the Claude form look (the table sheets' step-3 form): the title, right-aligned labels beside a
/// column of controls, the footer with Cancel and the accent Save at its right.
private struct SAQueryFavoriteSaveView: View {
    @ObservedObject var model: SAQueryFavoriteSaveViewModel
    @ObservedObject var palette: SAClaudeSwiftUIPalette
    let title: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var isNameFocused: Bool

    static let width: CGFloat = 400
    private static let labelColumnWidth: CGFloat = 130
    private static let labelGap: CGFloat = 10
    private static let rowGap: CGFloat = 10

    private var isReplacing: Bool {
        model.selectedFavorite != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(palette.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 16)

            row(NSLocalizedString("Query Name:", comment: "Query favorite save sheet name label")) {
                TextField("", text: $model.name)
                    .textFieldStyle(SAClaudeFieldStyle(isFocused: isNameFocused))
                    .focused($isNameFocused)
                    .disabled(isReplacing)
                    .accessibilityLabel(Text(SAClaudeFormText.rowLabel(
                        NSLocalizedString("Query Name:", comment: "Query favorite save sheet name label"))))
            }
            .padding(.bottom, Self.rowGap)

            row(nil) {
                Toggle(
                    NSLocalizedString("Save globally", comment: "Query favorite save sheet global checkbox"),
                    isOn: $model.saveGlobally
                )
                .toggleStyle(SAClaudeCheckboxToggleStyle())
                .disabled(isReplacing)
            }
            .padding(.bottom, Self.rowGap + 4)

            row(NSLocalizedString("Or replace an existing favorite:", comment: "Query favorite replacement picker label")) {
                SAQueryFavoriteReplacePicker(model: model, title: selectionTitle)
            }

            if isReplacing {
                row(nil) {
                    Text(NSLocalizedString(
                        "The selected favorite keeps its name and location.",
                        comment: "Query favorite replacement explanation"
                    ))
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            }

            if !model.errorMessage.isEmpty {
                row(nil) {
                    Text(model.errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(Color(nsColor: palette.isDark ? SAClaudeAlertChrome.redGlyphDark : SAClaudeAlertChrome.red))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }

            HStack(spacing: 8) {
                Spacer()

                Button(NSLocalizedString("Cancel", comment: "Cancel query favorite save"), action: onCancel)
                    .buttonStyle(SAClaudeSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button(NSLocalizedString("Save", comment: "Save query favorite"), action: onSave)
                    .buttonStyle(SAClaudePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
            .padding(.top, 20)
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
        .frame(width: Self.width)
        .background(palette.surface)
        .environmentObject(palette)
        .onAppear {
            isNameFocused = true
        }
    }

    /// A form row: the label (its trailing colon dropped, as the AppKit form shows labels) right-aligned in the
    /// label column, wrapping when long; the control in the column beside it.
    private func row<Control: View>(_ label: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: Self.labelGap) {
            Group {
                if let label {
                    Text(SAClaudeFormText.rowLabel(label))
                        .font(.system(size: 12))
                        .foregroundColor(palette.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(height: 0)
                }
            }
            .frame(width: Self.labelColumnWidth, alignment: .trailing)

            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectionTitle(_ selection: SAQueryFavoriteSelection) -> String {
        let scope: String
        switch selection.scope {
        case .document:
            scope = NSLocalizedString("Document", comment: "Document query favorite scope")
        case .global:
            scope = NSLocalizedString("Global", comment: "Global query favorite scope")
        }
        return "[\(scope)] \(selection.name)"
    }
}

/// The replace-existing choice: a menu picker drawn as a Claude field (fill, hairline, 8pt radius) with the
/// current choice and an up-down chevron; the whole field opens the menu, which ticks the current choice. A
/// pop-up rather than a SwiftUI `Picker(.menu)`, whose bezel can't be removed.
private struct SAQueryFavoriteReplacePicker: View {
    @ObservedObject var model: SAQueryFavoriteSaveViewModel
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    let title: (SAQueryFavoriteSelection) -> String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SAClaudeSwiftUIMetrics.controlRadius, style: .continuous)
        let ids: [String?] = [nil] + model.selections.map { Optional($0.id) }
        SAClaudeMenuPopUp(
            titles: [NSLocalizedString("None", comment: "No query favorite replacement selection")] + model.selections.map(title),
            selectedIndex: ids.firstIndex(of: model.selectedFavoriteID) ?? 0,
            textColour: palette.text,
            accessibilityLabel: NSLocalizedString("Favorite to replace", comment: "Query favorite replacement picker accessibility label"),
            onSelect: { index in model.selectedFavoriteID = ids.indices.contains(index) ? ids[index] : nil }
        )
        .padding(.leading, SAClaudeSwiftUIMetrics.fieldHorizontalPadding - 2)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity)
        .frame(height: SAClaudeSwiftUIMetrics.controlHeight)
        .background(shape.fill(palette.fieldFill))
        .overlay(shape.strokeBorder(palette.hairline, lineWidth: 1).allowsHitTesting(false))
    }
}

/// A borderless NSPopUpButton (its own up-down chevron at the right) filling the field, its title and chevron in
/// `textColour` at 13pt: SwiftUI's own `Menu` opens only from its title's width, this from anywhere in the field.
/// VoiceOver sees a pop-up button; the menu follows the panel's appearance.
/// Items are added one by one (`addItems(withTitles:)` drops duplicate titles, and two favourites may share a name).
private struct SAClaudeMenuPopUp: NSViewRepresentable {
    let titles: [String]
    let selectedIndex: Int
    let textColour: Color
    let accessibilityLabel: String
    let onSelect: (Int) -> Void

    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void = { _ in }
        @objc func picked(_ sender: NSPopUpButton) { onSelect(sender.indexOfSelectedItem) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.font = .systemFont(ofSize: 13)
        button.lineBreakMode = .byTruncatingTail
        button.alignment = .left
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        if button.itemArray.map(\.title) != titles {
            button.removeAllItems()
            for title in titles { button.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
        }
        if button.indexOfSelectedItem != selectedIndex, button.itemArray.indices.contains(selectedIndex) {
            button.selectItem(at: selectedIndex)
        }
        button.contentTintColor = NSColor(textColour)
        button.setAccessibilityLabel(accessibilityLabel)
    }
}

@MainActor
@objc final class SAQueryFavoriteSaveWindowController: NSWindowController {
    private let query: String
    private let fileURL: URL
    private let model: SAQueryFavoriteSaveViewModel
    private let palette = SAClaudeSwiftUIPalette(source: .app)
    private var appearanceSubscription: AnyCancellable?
    private let preferences = UserDefaults.standard

    @objc(initWithQuery:fileURL:defaultSaveGlobally:)
    init(query: String, fileURL: URL, defaultSaveGlobally: Bool) {
        self.query = query
        self.fileURL = fileURL

        let selections = SAQueryFavoriteStore.selections(
            documentFavorites: Self.documentFavorites(for: fileURL),
            globalFavorites: Self.globalFavorites()
        )
        model = SAQueryFavoriteSaveViewModel(
            saveGlobally: defaultSaveGlobally,
            selections: selections
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: SAQueryFavoriteSaveView.width, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = NSLocalizedString("Save Query Favorite", comment: "Query favorite save sheet title")
        panel.isReleasedWhenClosed = false

        super.init(window: panel)

        panel.contentView = NSHostingView(
            rootView: SAQueryFavoriteSaveView(
                model: model,
                palette: palette,
                title: panel.title,
                onSave: { [weak self] in self?.save() },
                onCancel: { [weak self] in self?.finish(returnCode: .cancel) }
            )
        )
        // The theme's lightness, as every Claude sheet (the field's caret and the picker's menu follow it).
        appearanceSubscription = palette.$isDark.sink { [weak panel] isDark in
            panel?.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func save() {
        let documentFavorites = Self.documentFavorites(for: fileURL)
        let globalFavorites = Self.globalFavorites()

        do {
            let mutation = try SAQueryFavoriteStore.save(
                query: query,
                name: model.name,
                saveGlobally: model.saveGlobally,
                replacing: model.selectedFavorite,
                documentFavorites: documentFavorites,
                globalFavorites: globalFavorites
            )

            switch mutation.scope {
            case .document:
                SPQueryController.shared().replaceFavorites(
                    by: mutation.favorites,
                    forFileURL: fileURL
                )
            case .global:
                preferences.set(mutation.favorites, forKey: SPQueryFavorites)
            }

            NotificationCenter.default.post(
                name: .SPQueryFavoritesHaveBeenUpdated,
                object: self
            )
            finish(returnCode: .OK)
        } catch SAQueryFavoriteSaveError.selectedFavoriteChanged {
            model.refreshSelections(SAQueryFavoriteStore.selections(
                documentFavorites: documentFavorites,
                globalFavorites: globalFavorites
            ))
            model.showError(NSLocalizedString(
                "The selected favorite was changed or removed in another window. Choose it again before saving.",
                comment: "Stale query favorite replacement alert message"
            ))
        } catch {
            model.showError(NSLocalizedString(
                "Enter a query name or choose a favorite to replace.",
                comment: "Missing query favorite name alert message"
            ))
        }
    }

    private func finish(returnCode: NSApplication.ModalResponse) {
        guard let window else { return }
        if let sheetParent = window.sheetParent {
            sheetParent.endSheet(window, returnCode: returnCode)
        } else {
            window.close()
        }
    }

    private static func documentFavorites(for fileURL: URL) -> [Any] {
        guard let favorites = SPQueryController.shared().favorites(forFileURL: fileURL) else {
            return []
        }
        return favorites.map { $0 }
    }

    private static func globalFavorites() -> [Any] {
        UserDefaults.standard.array(forKey: SPQueryFavorites) ?? []
    }
}
