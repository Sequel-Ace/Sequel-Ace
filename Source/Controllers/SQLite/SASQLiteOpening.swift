import AppKit
import SQLite3
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum SASQLiteFilePanels {
    static let sqliteType = UTType(filenameExtension: "sqlite") ?? .database
    static let sqlType = UTType(filenameExtension: "sql") ?? .plainText

    static func open(types: [UTType] = [], in window: NSWindow?, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        present(panel, in: window) {
            if let url = panel.url { completion(url) }
        }
    }

    static func save(type: UTType, name: String, in window: NSWindow?, completion: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = name
        present(panel, in: window) {
            if let url = panel.url { completion(url) }
        }
    }

    static func present(_ panel: NSSavePanel, in window: NSWindow?, accept: @escaping () -> Void) {
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK { accept() }
        }
        if let window, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    static func writableAccess(for url: URL, in window: NSWindow?, onError: @escaping (Error) -> Void,
                               completion: @escaping (SASQLiteFileAccess) -> Void) {
        let access = SASQLiteFileAccess([url])
        Task {
            let directory = url.deletingLastPathComponent()
            let canWrite = await Task.detached {
                withExtendedLifetime(access) {
                    let probe = directory.appendingPathComponent(".sequel-ace-\(UUID().uuidString)")
                    do {
                        try Data().write(to: probe, options: .withoutOverwriting)
                        try FileManager.default.removeItem(at: probe)
                        return true
                    } catch {
                        return false
                    }
                }
            }.value
            if canWrite {
                completion(access)
            } else {
                chooseFolder(for: url, in: window, onError: onError, completion: completion)
            }
        }
    }

    static func chooseFolder(for url: URL, in window: NSWindow?, onError: @escaping (Error) -> Void,
                             completion: @escaping (SASQLiteFileAccess) -> Void) {
        let directory = url.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        panel.prompt = NSLocalizedString("Grant Access", comment: "SQLite folder permission confirmation")
        panel.message = NSLocalizedString("Choose the containing folder so SQLite can access files next to the database.", comment: "SQLite folder permission explanation")
        present(panel, in: window) {
            guard let folder = panel.url,
                  folder.resolvingSymlinksInPath().standardizedFileURL.path == directory.resolvingSymlinksInPath().standardizedFileURL.path else {
                onError(CocoaError(.fileReadNoPermission))
                return
            }
            completion(SASQLiteFileAccess([url, folder]))
        }
    }
}

@MainActor
enum SASQLiteOpening {
    static func chooseDatabase(from parent: NSWindow?, replaceConnection: Bool = false, readOnly mode: Bool? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let readOnly = NSButton(checkboxWithTitle: NSLocalizedString("Open Read-Only", comment: "SQLite open mode"),
                                target: nil, action: nil)
        if mode == nil {
            panel.accessoryView = readOnly
            panel.isAccessoryViewDisclosed = true
        }
        SASQLiteFilePanels.present(panel, in: parent) {
            guard let url = panel.url else { return }
            if mode ?? (readOnly.state == .on) {
                open(url, readOnly: true, create: false, access: SASQLiteFileAccess([url]), in: parent,
                     replaceConnection: replaceConnection)
            } else {
                SASQLiteFilePanels.writableAccess(for: url, in: parent, onError: { present($0, in: parent) }) { access in
                    open(url, readOnly: false, create: false, access: access, in: parent, replaceConnection: replaceConnection)
                }
            }
        }
    }

    static func createDatabase(from parent: NSWindow?, replaceConnection: Bool = false) {
        let name = NSLocalizedString("Untitled.sqlite", comment: "Default SQLite filename")
        SASQLiteFilePanels.save(type: SASQLiteFilePanels.sqliteType, name: name, in: parent) { url in
            SASQLiteFilePanels.writableAccess(for: url, in: parent, onError: { present($0, in: parent) }) { access in
                open(url, readOnly: false, create: true, access: access, in: parent, replaceConnection: replaceConnection)
            }
        }
    }

    static func open(_ url: URL, readOnly: Bool, create: Bool, access: SASQLiteFileAccess, in parent: NSWindow?,
                     replaceConnection: Bool = false, mayRequestReadAccess: Bool = true) {
        let session = SASQLiteSession(url: url, readOnly: readOnly, create: create, access: access)
        Task {
            guard let tabManager = (NSApp.delegate as? SPAppController)?.tabManager else { return }
            do {
                let objects = try await session.perform(SASQLiteCancellation()) { try $0.objects() }
                let model = SASQLiteWorkspaceModel(session: session, objects: objects)
                tabManager.openSQLiteWorkspace(model, beside: parent)
                if replaceConnection { parent?.performClose(nil) }
            } catch SASQLiteError.engine(let code, _) where readOnly && mayRequestReadAccess &&
                [SQLITE_CANTOPEN, SQLITE_READONLY, SQLITE_IOERR].contains(code & 0xff) {
                SASQLiteFilePanels.chooseFolder(for: url, in: parent, onError: { present($0, in: parent) }) { access in
                    open(url, readOnly: true, create: false, access: access, in: parent,
                         replaceConnection: replaceConnection, mayRequestReadAccess: false)
                }
            } catch {
                present(error, in: parent)
            }
        }
    }

    private static func present(_ error: Error, in window: NSWindow?) {
        let alert = NSAlert(error: error)
        if let window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

@MainActor
@objc final class SASQLiteConnectionTab: NSObject {
    private static let identifier = "SASQLiteConnection"

    @objc(installIn:)
    static func install(in tabs: NSTabView) {
        let item = NSTabViewItem(identifier: identifier)
        item.label = NSLocalizedString("SQLite", comment: "Connection tab for SQLite database files")
        item.view = NSHostingView(rootView: SASQLiteConnectionPane())
        tabs.addTabViewItem(item)
    }

    @objc(isSelectedIn:)
    static func isSelected(in tabs: NSTabView) -> Bool {
        tabs.selectedTabViewItem?.identifier as? String == identifier
    }
}

struct SASQLiteConnectionPane: View {
    @State private var readOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SQLite Database File", systemImage: "externaldrive")
                .font(.headline)
            Text("Choose an existing SQLite file or create a new database.")
                .foregroundStyle(.secondary)
            Toggle("Open Read-Only", isOn: $readOnly)
            HStack {
                Button("New SQLite Database…") {
                    SASQLiteOpening.createDatabase(from: NSApp.mainWindow, replaceConnection: true)
                }
                Button("Open SQLite Database…") {
                    SASQLiteOpening.chooseDatabase(from: NSApp.mainWindow, replaceConnection: true, readOnly: readOnly)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}
