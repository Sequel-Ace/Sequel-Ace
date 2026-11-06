import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SASQLiteWorkspaceModel: NSObject, ObservableObject {
    enum Section {
        case data, structure, relations, triggers, status, query

        var mode: SAViewMode {
            switch self {
            case .data: return .content
            case .structure: return .structure
            case .relations: return .relations
            case .triggers: return .triggers
            case .status: return .status
            case .query: return .query
            }
        }
    }

    let session: SASQLiteSession
    let pageSize = 100
    @Published private(set) var objects: [SASQLiteObject]
    @Published var selection: Data? {
        didSet {
            if oldValue != selection { loadPage(at: 0, clear: true) }
        }
    }
    @Published var section = Section.data {
        didSet { window?.toolbar?.selectedItemIdentifier = section.mode.toolbarIdentifier }
    }
    @Published private(set) var page: SASQLitePage?
    @Published private(set) var offset = 0
    @Published var selectedRow: Int?
    @Published var selectedColumn: Int64?
    @Published var sql = ""
    @Published var selectedSQL = ""
    @Published private(set) var scriptResults: [SASQLiteScriptResult] = []
    @Published var selectedResult = 0
    @Published private(set) var operation: SASQLiteCancellation?
    @Published var showsError = false
    @Published private(set) var errorMessage = ""
    @Published var showsImport = false
    @Published var showsExport = false
    @Published var csvImport: SASQLiteCSVImport?
    weak var window: NSWindow?

    var busy: Bool { operation != nil }
    var canWrite: Bool { !busy && !session.readOnly }
    var currentObject: SASQLiteObject? { objects.first { $0.id == selection } }
    var currentRow: SASQLiteRow? {
        guard let selectedRow, let page, page.rows.indices.contains(selectedRow) else { return nil }
        return page.rows[selectedRow]
    }
    var canEditRow: Bool {
        guard canWrite, let structure = page?.structure, let row = currentRow else { return false }
        return (try? structure.selector(for: row)) != nil
    }
    var queryResult: SASQLiteScriptResult? {
        scriptResults.indices.contains(selectedResult) ? scriptResults[selectedResult] : nil
    }

    init(session: SASQLiteSession, objects: [SASQLiteObject]) {
        self.session = session
        self.objects = objects
        super.init()
    }

    func start() {
        if selection == nil { selection = objects.first?.id }
    }

    func reloadObjects(select name: String? = nil) {
        perform({ try $0.objects() }) { [weak self] objects in
            guard let self else { return }
            self.objects = objects
            let preferred = name.map { Data($0.utf8) } ?? self.selection
            let next = objects.first { $0.id == preferred }?.id ?? objects.first?.id
            if self.selection == next {
                self.loadPage(at: 0, clear: true)
            } else {
                self.selection = next
            }
        }
    }

    func loadPage(at offset: Int, clear: Bool = false) {
        if clear {
            page = nil
            selectedColumn = nil
            selectedRow = nil
            self.offset = 0
        }
        guard let object = currentObject else { return }
        let size = pageSize
        perform({ try $0.page(object, offset: offset, size: size) }) { [weak self] page in
            guard let self, self.selection == object.id else { return }
            if page.rows.isEmpty, offset > 0 {
                self.loadPage(at: max(0, offset - size))
            } else {
                self.page = page
                self.offset = offset
                self.selectedRow = nil
            }
        }
    }

    func runSQL(selectionOnly: Bool) {
        let query = selectionOnly ? selectedSQL : sql
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        perform({ database, cancellation in try database.runScript(query, cancellation: cancellation) }) { [weak self] results in
            guard let self else { return }
            self.scriptResults = results
            self.selectedResult = results.lastIndex { $0.error != nil } ?? results.lastIndex { $0.result?.columns.isEmpty == false } ?? 0
            self.reloadObjects()
        }
    }

    func apply(_ change: SASQLiteSchemaChange, select name: String? = nil) {
        perform({ try $0.apply(change) }) { [weak self] in self?.reloadObjects(select: name) }
    }

    func save(_ values: [Int64: SASQLiteValue], row: SASQLiteRow?, in structure: SASQLiteStructure) {
        guard row == nil || !values.isEmpty else { return }
        let offset = offset
        perform({ database in
            if let row {
                try database.update(values, row: row, in: structure)
            } else {
                try database.insert(values, into: structure)
            }
        }) { [weak self] in self?.loadPage(at: offset) }
    }

    func delete(_ row: SASQLiteRow, in structure: SASQLiteStructure) {
        let offset = offset
        perform({ try $0.delete(row, in: structure) }) { [weak self] in self?.loadPage(at: offset) }
    }

    func selectImport(csv: Bool) {
        guard canWrite else { return }
        SASQLiteFilePanels.open(types: csv ? [.commaSeparatedText] : [SASQLiteFilePanels.sqlType], in: window) { [weak self] url in
            guard let self else { return }
            let access = SASQLiteFileAccess([url])
            if csv {
                self.perform({ _, cancellation in
                    try withExtendedLifetime(access) { try SASQLiteCSV.preview(url, cancellation: cancellation) }
                }) { [weak self] fields in
                    self?.csvImport = SASQLiteCSVImport(url: url, access: access, fields: fields)
                }
            } else {
                self.perform({ database, cancellation in
                    try withExtendedLifetime(access) { try database.importSQL(url, cancellation: cancellation) }
                }) { [weak self] in self?.reloadObjects() }
            }
        }
    }

    func loadImportStructure(_ object: SASQLiteObject) async throws -> SASQLiteStructure {
        let cancellation = SASQLiteCancellation()
        return try await withTaskCancellationHandler {
            try await session.perform(cancellation) { try $0.structure(object) }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func importCSV(_ request: SASQLiteCSVImport, into target: SASQLiteCSVTarget, hasHeader: Bool) {
        perform({ database, cancellation in
            try withExtendedLifetime(request.access) {
                try database.importCSV(request.url, into: target, hasHeader: hasHeader, cancellation: cancellation)
            }
        }) { [weak self] in
            if case let .newTable(name, _) = target {
                self?.reloadObjects(select: name)
            } else {
                self?.reloadObjects()
            }
        }
    }

    func exportSQL() {
        export(type: SASQLiteFilePanels.sqlType, name: outputName + ".sql") { database, url, cancellation in
            try database.exportSQL(to: url, cancellation: cancellation)
        }
    }

    func exportTable() {
        guard let object = currentObject else { return }
        export(type: .commaSeparatedText, name: object.name.replacingOccurrences(of: "/", with: "_") + ".csv") { database, url, cancellation in
            try database.exportCSV(object, to: url, cancellation: cancellation)
        }
    }

    func exportResult() {
        guard let result = queryResult?.result, !result.columns.isEmpty else { return }
        export(type: .commaSeparatedText, name: outputName + "-result.csv") { _, url, cancellation in
            try SASQLiteOutput.text(at: url) { write in
                try write(SASQLiteCSV.line(result.columns.map { SASQLiteValue($0) }))
                for row in result.rows {
                    try cancellation.check()
                    try write(SASQLiteCSV.line(row))
                }
            }
        }
    }

    func backup(restore: Bool) {
        let suffix = restore ? "-restored.sqlite" : "-backup.sqlite"
        export(type: SASQLiteFilePanels.sqliteType, name: outputName + suffix, onSuccess: { [weak self] url, access in
            if restore {
                SASQLiteOpening.open(url, readOnly: false, create: false, access: access, in: self?.window)
            }
        }) { database, url, cancellation in
            try database.backup(to: url, cancellation: cancellation)
        }
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
        showsError = true
    }

    private var outputName: String { session.url.deletingPathExtension().lastPathComponent }

    private func export(type: UTType, name: String, onSuccess: ((URL, SASQLiteFileAccess) -> Void)? = nil,
                        write: @escaping @Sendable (SASQLiteConnection, URL, SASQLiteCancellation) throws -> Void) {
        guard !busy else { return }
        SASQLiteFilePanels.save(type: type, name: name, in: window) { [weak self] url in
            guard let self else { return }
            SASQLiteFilePanels.writableAccess(for: url, in: self.window, onError: self.report) { [weak self] access in
                self?.perform({ database, cancellation in
                    try withExtendedLifetime(access) { try write(database, url, cancellation) }
                }) { onSuccess?(url, access) }
            }
        }
    }

    private func perform<T: Sendable>(_ work: @escaping @Sendable (SASQLiteConnection) throws -> T,
                                     success: @escaping (T) -> Void) {
        perform({ database, _ in try work(database) }, success: success)
    }

    private func perform<T: Sendable>(_ work: @escaping @Sendable (SASQLiteConnection, SASQLiteCancellation) throws -> T,
                                     success: @escaping (T) -> Void) {
        guard !busy else { return }
        let cancellation = SASQLiteCancellation()
        operation = cancellation
        let session = session
        Task { [weak self] in
            do {
                let result = try await session.perform(cancellation) { try work($0, cancellation) }
                self?.operation = nil
                success(result)
            } catch {
                self?.operation = nil
                if !cancellation.isCancelled { self?.report(error) }
            }
        }
    }
}

extension SASQLiteWorkspaceModel: NSToolbarDelegate {
    private static let modes: [SAViewMode] = [.structure, .content, .relations, .triggers, .status, .query]
    private static let refreshItem = NSToolbarItem.Identifier("SASQLiteRefresh")
    private static let importItem = NSToolbarItem.Identifier("SASQLiteImport")
    private static let exportItem = NSToolbarItem.Identifier("SASQLiteExport")

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "SQLiteTableWindowToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = section.mode.toolbarIdentifier
        return toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.modes.map(\.toolbarIdentifier) + [.flexibleSpace, Self.refreshItem, Self.importItem, Self.exportItem]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.modes.map(\.toolbarIdentifier)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if let mode = Self.modes.first(where: { $0.toolbarIdentifier == identifier }) {
            return mode.makeToolbarItem(target: self)
        }
        let label: String
        let symbol: String
        let action: Selector
        switch identifier {
        case Self.refreshItem:
            label = NSLocalizedString("Refresh", comment: "SQLite toolbar action")
            symbol = "arrow.clockwise"
            action = #selector(refresh)
        case Self.importItem:
            label = NSLocalizedString("Import", comment: "SQLite toolbar action")
            symbol = "square.and.arrow.down"
            action = #selector(importFromFile)
        case Self.exportItem:
            label = NSLocalizedString("Export", comment: "SQLite toolbar action")
            symbol = "square.and.arrow.up"
            action = #selector(exportToFile)
        default:
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self
        item.action = action
        return item
    }

    @objc private func viewContent() { section = .data }
    @objc private func viewStructure() { section = .structure }
    @objc private func viewRelations() { section = .relations }
    @objc private func viewTriggers() { section = .triggers }
    @objc private func viewStatus() { section = .status }
    @objc private func viewQuery() { section = .query }
    @objc private func refresh() { reloadObjects() }
    @objc private func importFromFile() { if canWrite { showsImport = true } }
    @objc private func exportToFile() { if !busy { showsExport = true } }
}

extension SASQLiteWorkspaceModel: NSToolbarItemValidation {
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.importItem: return canWrite
        case Self.refreshItem, Self.exportItem: return !busy
        default: return true
        }
    }
}

struct SASQLiteCSVImport: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let access: SASQLiteFileAccess
    let fields: [String?]
}
