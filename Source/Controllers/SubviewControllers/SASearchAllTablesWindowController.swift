//
//  SASearchAllTablesWindowController.swift
//  Sequel Ace
//
//  Created by Sequel-Ace contributors on 2026.09.19.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import SwiftUI

// "Search in All Tables" sheet (issue #152): finds a value in every table of
// the current database and opens a result as that table's filtered content.
// The pure parts (column selection, SQL, filters) live in SASearchAllTables.swift.

// MARK: - Runner

/// Runs a search on the document's connection from a background queue, one
/// table at a time. Queries on an `SPMySQLConnection` are serialized by the
/// connection itself, the same way the process list and the MCP server use it
/// off the main thread.
private final class SASearchAllTablesRunner {
    enum Event {
        case started(tableCount: Int)
        case searching(index: Int, table: String)
        case found(SASearchAllTablesMatch, SASearchAllTablesTable)
        case tableFailed(table: String, message: String)
        case finished(cancelled: Bool)
        case failed(message: String)
    }

    private let connection: SPMySQLConnection
    private let database: String
    private let queue = DispatchQueue(label: "com.sequel-ace.search-all-tables", qos: .userInitiated)
    private let lock = NSLock()
    private var isCancelled = false
    private var isQuerying = false

    init(connection: SPMySQLConnection, database: String) {
        self.connection = connection
        self.database = database
    }

    /// Starts the search; `handler` is called on the main queue.
    func start(options: SASearchAllTablesOptions, handler: @escaping (Event) -> Void) {
        let send: (Event) -> Void = { event in DispatchQueue.main.async { handler(event) } }
        queue.async { [self] in
            guard let rows = columnRows() else {
                send(.failed(message: connection.lastErrorMessage() ?? ""))
                return
            }
            let tables = SASearchAllTablesQueryBuilder.tables(fromColumnRows: rows, options: options)
            send(.started(tableCount: tables.count))

            let pattern = SASearchAllTablesQueryBuilder.likePattern(for: options.searchText, mode: options.matchMode)
            let quotedPattern = quoted(pattern)

            for (index, table) in tables.enumerated() {
                guard beginQuery() else { break }
                send(.searching(index: index, table: table.name))
                let result = connection.queryString(
                    SASearchAllTablesQueryBuilder.countQuery(database: database, table: table, quotedPattern: quotedPattern)
                )
                guard endQuery() else { break }

                if connection.queryErrored() || result == nil {
                    send(.tableFailed(table: table.name, message: connection.lastErrorMessage() ?? ""))
                    continue
                }
                result?.defaultRowReturnType = SPMySQLResultRowAsArray
                let row = (result?.getRowAsArray() ?? []).map { $0 is NSNull ? nil : $0 }
                if let match = SASearchAllTablesQueryBuilder.match(fromCountRow: row, table: table) {
                    send(.found(match, table))
                }
            }
            send(.finished(cancelled: cancelled))
        }
    }

    /// Stops the search before the next table and interrupts the running query.
    func cancel() {
        lock.lock()
        isCancelled = true
        let interrupt = isQuerying
        lock.unlock()
        // cancelCurrentQuery opens a short-lived connection to run KILL QUERY,
        // so keep it off the main thread.
        if interrupt {
            DispatchQueue.global(qos: .userInitiated).async { [connection] in connection.cancelCurrentQuery() }
        }
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    /// Marks a query as running; `false` when the search was cancelled.
    private func beginQuery() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        isQuerying = !isCancelled
        return isQuerying
    }

    /// Marks the query as done; `false` when the search was cancelled meanwhile.
    private func endQuery() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        isQuerying = false
        return !isCancelled
    }

    private func columnRows() -> [(table: String, column: String, dataType: String, tableType: String)]? {
        let result = connection.queryString(SASearchAllTablesQueryBuilder.columnsQuery(quotedDatabase: quoted(database)))
        if connection.queryErrored() { return nil }
        result?.defaultRowReturnType = SPMySQLResultRowAsArray
        var rows: [(table: String, column: String, dataType: String, tableType: String)] = []
        while let row = result?.getRowAsArray(), row.count >= 4 {
            guard let table = SASearchAllTablesQueryBuilder.string(from: row[0]),
                  let column = SASearchAllTablesQueryBuilder.string(from: row[1]),
                  let dataType = SASearchAllTablesQueryBuilder.string(from: row[2]),
                  let tableType = SASearchAllTablesQueryBuilder.string(from: row[3]) else { continue }
            rows.append((table, column, dataType, tableType))
        }
        return rows
    }

    /// Quotes a string literal with the connection's escaping rules.
    private func quoted(_ value: String) -> String {
        // escapeAndQuoteString imports as String! and is nil when disconnected.
        if let quoted = connection.escapeAndQuoteString(value) { return quoted }
        return "'" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "''") + "'"
    }
}

// MARK: - Model

/// One row of the results list.
private struct SASearchAllTablesResultRow: Identifiable {
    let id: String
    let table: SASearchAllTablesTable
    let match: SASearchAllTablesMatch?
    let errorMessage: String?

    var rowCount: String {
        match.map { NumberFormatter.localizedString(from: NSNumber(value: $0.matchingRows), number: .decimal) } ?? "—"
    }

    var columns: String {
        if let errorMessage { return errorMessage }
        return match?.columnMatches.map { "\($0.column) (\($0.rows))" }.joined(separator: ", ") ?? ""
    }
}

@MainActor
private final class SASearchAllTablesViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var matchMode = SASearchAllTablesMatchMode.contains
    @Published var textColumnsOnly = true
    @Published var includeViews = false
    @Published var tableNameFilter = ""

    @Published var results: [SASearchAllTablesResultRow] = []
    @Published var selection: SASearchAllTablesResultRow.ID?
    @Published var isSearching = false
    @Published var progress = 0.0
    @Published var status = ""

    /// Search text and mode of the results shown, used when opening one.
    var searchedText = ""
    var searchedMode = SASearchAllTablesMatchMode.contains

    let database: String

    init(database: String) {
        self.database = database
    }

    var canSearch: Bool {
        !isSearching && !searchText.isEmpty
    }

    var selectedRow: SASearchAllTablesResultRow? {
        results.first { $0.id == selection }
    }
}

// MARK: - View

private struct SASearchAllTablesView: View {
    @ObservedObject var model: SASearchAllTablesViewModel
    let onSearch: () -> Void
    let onStop: () -> Void
    let onOpen: (SASearchAllTablesResultRow.ID) -> Void
    let onClose: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: NSLocalizedString("Search all tables in “%@”", comment: "Search in All Tables sheet : title ($1 = database name)"), model.database))
                .font(.headline)

            SASearchAllTablesFormView(model: model, isSearchFieldFocused: $isSearchFieldFocused)
                .disabled(model.isSearching)

            SASearchAllTablesResultsView(model: model, onOpen: onOpen)

            HStack(spacing: 8) {
                if model.isSearching {
                    ProgressView(value: model.progress)
                        .frame(width: 120)
                }
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(NSLocalizedString("Close", comment: "Search in All Tables sheet : close button"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("Show", comment: "Search in All Tables sheet : show the selected result's table content")) {
                    if let id = model.selection { onOpen(id) }
                }
                .disabled(model.selectedRow?.match == nil || model.isSearching)
                if model.isSearching {
                    Button(NSLocalizedString("Stop", comment: "Search in All Tables sheet : stop the running search"), action: onStop)
                } else {
                    Button(NSLocalizedString("Search", comment: "Search in All Tables sheet : search button"), action: onSearch)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canSearch)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 420, idealHeight: 480)
        .onAppear { isSearchFieldFocused = true }
    }
}

private struct SASearchAllTablesFormView: View {
    @ObservedObject var model: SASearchAllTablesViewModel
    var isSearchFieldFocused: FocusState<Bool>.Binding

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text(NSLocalizedString("Find:", comment: "Search in All Tables sheet : search text label"))
                    .gridColumnAlignment(.trailing)
                TextField(NSLocalizedString("Value to search for", comment: "Search in All Tables sheet : search text placeholder"), text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused(isSearchFieldFocused)
            }
            GridRow {
                Text(NSLocalizedString("Match:", comment: "Search in All Tables sheet : match mode label"))
                Picker("", selection: $model.matchMode) {
                    Text(NSLocalizedString("Contains", comment: "Search in All Tables sheet : match values containing the text"))
                        .tag(SASearchAllTablesMatchMode.contains)
                    Text(NSLocalizedString("Whole value", comment: "Search in All Tables sheet : match values equal to the text"))
                        .tag(SASearchAllTablesMatchMode.exact)
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
            }
            GridRow {
                Text(NSLocalizedString("Tables:", comment: "Search in All Tables sheet : table name filter label"))
                TextField(NSLocalizedString("All tables (or only names containing…)", comment: "Search in All Tables sheet : table name filter placeholder"), text: $model.tableNameFilter)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                HStack(spacing: 16) {
                    Toggle(NSLocalizedString("Text columns only", comment: "Search in All Tables sheet : only search character and text columns"), isOn: $model.textColumnsOnly)
                    Toggle(NSLocalizedString("Include views", comment: "Search in All Tables sheet : also search views"), isOn: $model.includeViews)
                }
            }
        }
    }
}

private struct SASearchAllTablesResultsView: View {
    @ObservedObject var model: SASearchAllTablesViewModel
    let onOpen: (SASearchAllTablesResultRow.ID) -> Void

    var body: some View {
        Table(model.results, selection: $model.selection) {
            TableColumn(NSLocalizedString("Table", comment: "Search in All Tables sheet : results column : table name")) { row in
                Text(row.table.name)
            }
            .width(min: 120, ideal: 180)
            TableColumn(NSLocalizedString("Rows", comment: "Search in All Tables sheet : results column : number of matching rows")) { row in
                Text(row.rowCount)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 70, max: 110)
            TableColumn(NSLocalizedString("Matching Columns", comment: "Search in All Tables sheet : results column : columns with matches and their row counts")) { row in
                Text(row.columns)
                    .foregroundStyle(row.errorMessage == nil ? Color.primary : Color.red)
                    .help(row.columns)
            }
        }
        .contextMenu(forSelectionType: SASearchAllTablesResultRow.ID.self, menu: { _ in }, primaryAction: { ids in
            if let id = ids.first { onOpen(id) }
        })
    }
}

// MARK: - Window controller

@MainActor
@objc final class SASearchAllTablesWindowController: NSWindowController {
    private weak var databaseDocument: SPDatabaseDocument?
    private let model: SASearchAllTablesViewModel
    private var runner: SASearchAllTablesRunner?
    /// Switches to the content tab once the table opened from a result has loaded.
    private var pendingContentSwitch: NotificationToken?

    /// Controllers are kept per document so reopening the sheet shows the last
    /// search and its results.
    private static var associationKey: UInt8 = 0

    /// Shows the sheet for the document's current database.
    static func show(for document: SPDatabaseDocument) {
        guard let database = document.database(), let parentWindow = document.parentWindowControllerWindow(),
              parentWindow.attachedSheet == nil else { return }

        var controller = objc_getAssociatedObject(document, &associationKey) as? SASearchAllTablesWindowController
        if controller?.model.database != database {
            controller = SASearchAllTablesWindowController(document: document, database: database)
            objc_setAssociatedObject(document, &associationKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        guard let controller, let window = controller.window else { return }
        parentWindow.beginSheet(window)
    }

    private init(document: SPDatabaseDocument, database: String) {
        self.databaseDocument = document
        model = SASearchAllTablesViewModel(database: database)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = NSLocalizedString("Search in All Tables", comment: "Search in All Tables sheet : window title")
        panel.isReleasedWhenClosed = false

        super.init(window: panel)

        panel.contentView = NSHostingView(
            rootView: SASearchAllTablesView(
                model: model,
                onSearch: { [weak self] in self?.search() },
                onStop: { [weak self] in self?.runner?.cancel() },
                onOpen: { [weak self] id in self?.open(id) },
                onClose: { [weak self] in self?.dismissSheet() }
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func search() {
        guard model.canSearch, let document = databaseDocument, let connection = document.getConnection() else { return }
        // Don't queue behind (or race) a task the document is running on the same connection.
        guard !document.isWorking() else {
            model.status = NSLocalizedString("Sequel Ace is busy. Try again when the current task has finished.", comment: "Search in All Tables sheet : status when the connection is busy")
            NSSound.beep()
            return
        }

        let options = SASearchAllTablesOptions(
            searchText: model.searchText,
            matchMode: model.matchMode,
            textColumnsOnly: model.textColumnsOnly,
            includeViews: model.includeViews,
            tableNameFilter: model.tableNameFilter
        )
        model.searchedText = options.searchText
        model.searchedMode = options.matchMode
        model.results = []
        model.selection = nil
        model.progress = 0
        model.isSearching = true
        model.status = NSLocalizedString("Reading table columns…", comment: "Search in All Tables sheet : status while listing columns")

        let runner = SASearchAllTablesRunner(connection: connection, database: model.database)
        self.runner = runner
        var tableCount = 0
        var failedCount = 0
        runner.start(options: options) { [weak self] event in
            guard let self, self.runner === runner else { return }
            let model = self.model
            switch event {
            case .started(let count):
                tableCount = count
            case .searching(let index, let table):
                model.progress = tableCount > 0 ? Double(index) / Double(tableCount) : 0
                model.status = String(format: NSLocalizedString("Searching %1$@ (%2$ld of %3$ld)…", comment: "Search in All Tables sheet : progress status ($1 = table name, $2 = table number, $3 = table count)"), table, index + 1, tableCount)
            case .found(let match, let table):
                model.results.append(SASearchAllTablesResultRow(id: table.name, table: table, match: match, errorMessage: nil))
            case .tableFailed(let table, let message):
                failedCount += 1
                let row = SASearchAllTablesResultRow(id: table, table: SASearchAllTablesTable(name: table, isView: false, columns: []), match: nil, errorMessage: message)
                model.results.append(row)
            case .finished(let cancelled):
                model.isSearching = false
                self.runner = nil
                model.status = Self.summary(results: model.results, tableCount: tableCount, failedCount: failedCount, cancelled: cancelled)
            case .failed(let message):
                model.isSearching = false
                self.runner = nil
                model.status = String(format: NSLocalizedString("The search failed: %@", comment: "Search in All Tables sheet : status when the column list could not be read ($1 = MySQL error)"), message)
            }
        }
    }

    private static func summary(results: [SASearchAllTablesResultRow], tableCount: Int, failedCount: Int, cancelled: Bool) -> String {
        let matches = results.compactMap(\.match)
        var parts: [String] = []
        if cancelled {
            parts.append(NSLocalizedString("Search stopped.", comment: "Search in All Tables sheet : status after the search was stopped"))
        }
        if !matches.isEmpty {
            let rows = matches.reduce(0) { $0 + $1.matchingRows }
            parts.append(String(format: NSLocalizedString("%1$ld matching rows in %2$ld of %3$ld tables.", comment: "Search in All Tables sheet : status after a search ($1 = matching rows, $2 = tables with matches, $3 = tables searched)"), rows, matches.count, tableCount))
        } else if !cancelled {
            // After a stop, the tables not reached were never searched.
            parts.append(tableCount == 0
                ? NSLocalizedString("No tables with searchable columns.", comment: "Search in All Tables sheet : status when no table has a column to search")
                : String(format: NSLocalizedString("No matches in %ld tables.", comment: "Search in All Tables sheet : status when nothing matched ($1 = number of tables searched)"), tableCount))
        }
        if failedCount > 0 {
            parts.append(String(format: NSLocalizedString("%ld tables could not be searched.", comment: "Search in All Tables sheet : status when some tables returned an error ($1 = number of tables)"), failedCount))
        }
        return parts.joined(separator: " ")
    }

    /// Closes the sheet and shows the result's table content, filtered to the matching rows.
    private func open(_ id: SASearchAllTablesResultRow.ID) {
        guard !model.isSearching, let row = model.results.first(where: { $0.id == id }), let match = row.match else { return }
        let filter = SASearchAllTablesFilterBuilder.serializedFilter(for: match, table: row.table, text: model.searchedText, mode: model.searchedMode)
        dismissSheet()
        showContent(of: row.table.name, filter: filter)
    }

    private func dismissSheet() {
        runner?.cancel()
        guard let window, let parent = window.sheetParent else { return }
        parent.endSheet(window)
    }

    private func showContent(of table: String, filter: [String: Any]?) {
        pendingContentSwitch = nil
        guard let document = databaseDocument else { return }
        guard !document.isWorking() else {
            NSSound.beep()
            return
        }

        // Loading a table while another tab is showing clears the content tab,
        // including a filter staged for it. Select the table first and show its
        // content once it has loaded.
        if document.currentlySelectedView() != .content && document.table() != table {
            guard document.tableContentInstance.showTable(table, withSerializedFilter: nil) else {
                NSSound.beep()
                return
            }
            if document.isWorking() {
                pendingContentSwitch = NotificationCenter.default.observe(name: .SPDocumentTaskEnd, object: document, queue: .main) { [weak self] _ in
                    self?.pendingContentSwitch = nil
                    self?.showSelectedTableContent(table, filter: filter)
                }
                return
            }
        }
        showSelectedTableContent(table, filter: filter)
    }

    /// Applies the filter to `table` and switches to the content tab.
    private func showSelectedTableContent(_ table: String, filter: [String: Any]?) {
        guard let document = databaseDocument else { return }
        let wasShowingContent = document.currentlySelectedView() == .content
        guard document.tableContentInstance.showTable(table, withSerializedFilter: filter) else {
            NSSound.beep()
            return
        }
        guard !wasShowingContent, document.table() == table else { return }
        // The content tab reloads the table when it is shown, restoring the filter.
        document.setContentRequiresReload(true)
        document.viewContent()
    }
}

extension SPDatabaseDocument {
    /// Database → Search in All Tables…
    @MainActor @objc func showSearchAllTables() {
        SASearchAllTablesWindowController.show(for: self)
    }
}
