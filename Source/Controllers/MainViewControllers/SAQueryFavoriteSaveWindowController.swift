//
//  SAQueryFavoriteSaveWindowController.swift
//  Sequel Ace
//
//  SwiftUI replacement for the legacy Query Favorite Sheet in DBView.xib.
//


import SwiftUI

@MainActor
private final class SAQueryFavoriteSaveViewModel: ObservableObject {
    @Published var name = ""
    @Published var saveGlobally: Bool
    @Published var selectedFavoriteID: String? {
        didSet {
            if let selectedFavorite {
                saveGlobally = selectedFavorite.scope == .global
            }
        }
    }
    @Published var selections: [SAQueryFavoriteSelection]
    @Published var errorMessage = ""
    @Published var isShowingError = false

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
        isShowingError = true
    }
}

private struct SAQueryFavoriteSaveView: View {
    @ObservedObject var model: SAQueryFavoriteSaveViewModel
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var isNameFocused: Bool

    private var isReplacing: Bool {
        model.selectedFavorite != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Query Name:", comment: "Query favorite save sheet name label"))
                .font(.headline)

            TextField("", text: $model.name)
                .textFieldStyle(.roundedBorder)
                .disabled(isReplacing)
                .focused($isNameFocused)

            Toggle(
                NSLocalizedString("Save globally", comment: "Query favorite save sheet global checkbox"),
                isOn: $model.saveGlobally
            )
            .disabled(isReplacing)

            Divider()

            Text(NSLocalizedString("Or replace an existing favorite:", comment: "Query favorite replacement picker label"))
                .font(.headline)

            Picker("", selection: $model.selectedFavoriteID) {
                Text(NSLocalizedString("None", comment: "No query favorite replacement selection"))
                    .tag(String?.none)

                ForEach(model.selections) { selection in
                    Text(selectionTitle(selection))
                        .tag(Optional(selection.id))
                }
            }
            .labelsHidden()
            .accessibilityLabel(
                Text(NSLocalizedString("Favorite to replace", comment: "Query favorite replacement picker accessibility label"))
            )

            if isReplacing {
                Text(NSLocalizedString(
                    "The selected favorite keeps its name and location.",
                    comment: "Query favorite replacement explanation"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()

                Button(NSLocalizedString("Cancel", comment: "Cancel query favorite save"), action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(NSLocalizedString("Save", comment: "Save query favorite"), action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            isNameFocused = true
        }
        .alert(
            NSLocalizedString("Favorite Changed", comment: "Stale query favorite replacement alert title"),
            isPresented: $model.isShowingError
        ) {
            Button(NSLocalizedString("OK", comment: "Dismiss query favorite replacement error"), role: .cancel) {}
        } message: {
            Text(model.errorMessage)
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

@MainActor
@objc final class SAQueryFavoriteSaveWindowController: NSWindowController {
    private let query: String
    private let fileURL: URL
    private let model: SAQueryFavoriteSaveViewModel
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
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
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
                onSave: { [weak self] in self?.save() },
                onCancel: { [weak self] in self?.finish(returnCode: .cancel) }
            )
        )
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
