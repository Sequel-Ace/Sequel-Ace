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

/// The sheet in the Claude form look, at the AppKit form sheets' metrics (`SAClaudeFormLayout`, `.form` controls):
/// the title, right-aligned labels beside a column of controls, the footer with Cancel and the accent Save at its right.
private struct SAQueryFavoriteSaveView: View {
    @ObservedObject var model: SAQueryFavoriteSaveViewModel
    @ObservedObject var palette: SAClaudeSwiftUIPalette
    let title: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var isNameFocused: Bool

    private typealias Layout = SAClaudeFormLayout

    static let nameLabel = NSLocalizedString("Query Name:", comment: "Query favorite save sheet name label")
    static let replaceLabel = NSLocalizedString("Or replace an existing favorite:", comment: "Query favorite replacement picker label")

    /// The label column and sheet width, as the AppKit form engine sizes them: the widest label (on one line) beside
    /// a control column of at least 200pt, 360–560pt wide.
    static let frames: SAClaudeFormLayout.Frames = {
        func labelWidth(_ text: String) -> CGFloat {
            // A label's one-line width plus the text cell's 2pt insets, as the AppKit form measures its labels.
            let string = NSAttributedString(string: SAClaudeFormText.rowLabel(text), attributes: [.font: SAClaudeFormSheet.labelFont])
            return ceil(string.size().width) + 4
        }
        let button = SAClaudeFormLayout.FooterItem(width: SAClaudeSwiftUIMetrics.buttonMinWidth,
                                                   height: SAClaudeControlSize.form.buttonHeight)
        return SAClaudeFormLayout.frames(SAClaudeFormLayout.Spec(
            items: [.row(labelWidth: labelWidth(nameLabel), control: .field),
                    .control(.checkbox),
                    .row(labelWidth: labelWidth(replaceLabel), control: .popUp)],
            hasContext: false,
            footerTrailing: [button, button],
            currentSize: .zero))
    }()

    static var width: CGFloat { frames.size.width }

    private var isReplacing: Bool {
        model.selectedFavorite != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Font(SAClaudeFormSheet.titleFont))
                .foregroundColor(palette.text)
                .lineLimit(1)
                .frame(height: Layout.titleHeight)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, Layout.headerGap)

            row(Self.nameLabel) {
                TextField("", text: $model.name)
                    .textFieldStyle(SAClaudeFieldStyle(isFocused: isNameFocused, size: .form))
                    .focused($isNameFocused)
                    .disabled(isReplacing)
                    .accessibilityLabel(Text(SAClaudeFormText.rowLabel(Self.nameLabel)))
            }
            .padding(.bottom, Layout.rowGap)

            row(nil) {
                Toggle(
                    NSLocalizedString("Save globally", comment: "Query favorite save sheet global checkbox"),
                    isOn: $model.saveGlobally
                )
                .toggleStyle(SAClaudeCheckboxToggleStyle(size: .form))
                .disabled(isReplacing)
            }
            .padding(.bottom, Layout.rowGap)

            row(Self.replaceLabel) {
                SAQueryFavoriteReplacePicker(model: model, title: selectionTitle)
            }

            if isReplacing {
                note(NSLocalizedString(
                    "The selected favorite keeps its name and location.",
                    comment: "Query favorite replacement explanation"
                ), colour: palette.muted)
            }

            if !model.errorMessage.isEmpty {
                note(model.errorMessage,
                     colour: Color(nsColor: palette.isDark ? SAClaudeAlertChrome.redGlyphDark : SAClaudeAlertChrome.red))
            }

            HStack(spacing: Layout.footerItemGap) {
                Spacer()

                Button(NSLocalizedString("Cancel", comment: "Cancel query favorite save"), action: onCancel)
                    .buttonStyle(SAClaudeSecondaryButtonStyle(size: .form))
                    .keyboardShortcut(.cancelAction)

                Button(NSLocalizedString("Save", comment: "Save query favorite"), action: onSave)
                    .buttonStyle(SAClaudePrimaryButtonStyle(size: .form))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
            .frame(height: Layout.footerHeight)
            .padding(.top, Layout.footerGap)
        }
        .padding(EdgeInsets(top: Layout.topMargin, leading: Layout.sideMargin, bottom: Layout.bottomMargin, trailing: Layout.sideMargin))
        .frame(width: Self.width)
        .background(palette.surface)
        .environmentObject(palette)
        .onAppear {
            isNameFocused = true
        }
    }

    /// A form row, at least the form's 28pt: the label (its trailing colon dropped, as the AppKit form shows labels)
    /// right-aligned on one line in the label column, the control centred beside it.
    private func row<Control: View>(_ label: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: Layout.labelGap) {
            Group {
                if let label {
                    Text(SAClaudeFormText.rowLabel(label))
                        .font(Font(SAClaudeFormSheet.labelFont))
                        .foregroundColor(palette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(height: 0)
                }
            }
            .frame(width: Self.frames.labelColumnWidth, alignment: .trailing)

            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Layout.rowHeight)
    }

    /// A note under the rows, in the control column (the replacement explanation, the error).
    private func note(_ text: String, colour: Color) -> some View {
        HStack(spacing: Layout.labelGap) {
            Color.clear.frame(width: Self.frames.labelColumnWidth, height: 0)
            Text(text)
                .font(Font(SAClaudeFormSheet.contextFont))
                .foregroundColor(colour)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 6)
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

/// The replace-existing choice as the AppKit form's Claude pill (`SAClaudePillPopUpButtonCell`): a 24pt hover-filled
/// pill with a 7pt radius, the current choice at 12pt and an up-down chevron; the whole pill opens the menu, which
/// ticks the current choice. A pop-up rather than a SwiftUI `Picker(.menu)`, whose bezel can't be removed.
private struct SAQueryFavoriteReplacePicker: View {
    @ObservedObject var model: SAQueryFavoriteSaveViewModel
    @EnvironmentObject var palette: SAClaudeSwiftUIPalette
    @Environment(\.isEnabled) private var isEnabled
    let title: (SAQueryFavoriteSelection) -> String

    private let size = SAClaudeControlSize.form

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        let ids: [String?] = [nil] + model.selections.map { Optional($0.id) }
        SAClaudeMenuPopUp(
            titles: [NSLocalizedString("None", comment: "No query favorite replacement selection")] + model.selections.map(title),
            selectedIndex: ids.firstIndex(of: model.selectedFavoriteID) ?? 0,
            font: size.popUpFont,
            textColour: palette.text,
            accessibilityLabel: NSLocalizedString("Favorite to replace", comment: "Query favorite replacement picker accessibility label"),
            onSelect: { index in model.selectedFavoriteID = ids.indices.contains(index) ? ids[index] : nil }
        )
        .padding(.leading, SAClaudeFilterChrome.pillPadding - 3)
        .padding(.trailing, 2)
        .frame(maxWidth: .infinity)
        .frame(height: size.popUpHeight)
        .background(shape.fill(palette.hover))
        .opacity(isEnabled ? 1 : SAClaudeSwiftUIMetrics.checkboxDisabledOpacity)
    }
}

/// A borderless NSPopUpButton (its own up-down chevron at the right) filling the pill, its title and chevron in
/// `textColour`, in `font`: SwiftUI's own `Menu` opens only from its title's width, this from anywhere in the field.
/// VoiceOver sees a pop-up button; the menu follows the panel's appearance.
/// Items are added one by one (`addItems(withTitles:)` drops duplicate titles, and two favourites may share a name).
private struct SAClaudeMenuPopUp: NSViewRepresentable {
    let titles: [String]
    let selectedIndex: Int
    let font: NSFont
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
        if button.font != font { button.font = font }
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
            showError(NSLocalizedString(
                "The selected favorite was changed or removed in another window. Choose it again before saving.",
                comment: "Stale query favorite replacement alert message"
            ))
        } catch {
            showError(NSLocalizedString(
                "Enter a query name or choose a favorite to replace.",
                comment: "Missing query favorite name alert message"
            ))
        }
    }

    /// Shows `message` under the form and has VoiceOver read it (the alert it replaced was read out).
    private func showError(_ message: String) {
        model.showError(message)
        NSAccessibility.post(element: window as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
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
