import AppKit
import SPMySQL

/// A connection the Process List runs its statements on. Every call blocks and is made off the main thread, on the
/// session's serial queue, one at a time.
protocol SAClaudeProcessListBackend: AnyObject {
    /// `SHOW FULL PROCESSLIST` rows as SPMySQL returns them (column name → String or NSNull), or the error message.
    func fetchProcessRows() -> Result<[[String: Any]], SAClaudeProcessListError>
    func execute(_ statement: String) -> SAClaudeProcessStatementResult
    var serverVersion: String? { get }
    /// This backend's own server connection id (0 when unknown).
    var connectionId: Int64 { get }
    func close()
}

struct SAClaudeProcessListError: Error, Equatable {
    let message: String
}

/// One refresh, delivered on the main thread.
enum SAClaudeProcessListRefresh {
    /// `rows` keep today's dictionary shape (`Id`/`Time` as NSNumber) for the table, Copy and Save As…;
    /// `processes` are the same rows typed, in server order.
    case fetched(processes: [SAClaudeProcess], rows: [[String: Any]])
    /// Not run: a refresh was already running, the session is closed, or (shared fallback only) the document is busy.
    case skipped
    case failed(message: String)
}

/// The Process List's connection. On `open()` it copies the owning document's connection (SPMySQL's `-copy`: same
/// host/port/socket/user/SSL/timeouts, no session state, no proxy) and connects it off the main thread, so a long query
/// in the document never blocks refreshes or kills. Through an SSH tunnel the copy's host/port already are the tunnel's
/// local end, so it rides the existing tunnel (no second SSH session) — the approach `SPDatabaseStructure` uses. If the
/// copy can't connect, the session falls back to the document's own connection with today's rule (no refresh while the
/// document is working) and `usesSharedConnection` is set so the window can say so.
///
/// All statements run on one serial queue; every completion and callback arrives on the main thread.
@objc final class SAClaudeProcessListSession: NSObject {
    private enum State { case idle, open, closed }

    private let queue = DispatchQueue(label: "com.sequel-ace.process-list-session", qos: .userInitiated)
    private let makeDedicated: () -> SAClaudeProcessListBackend?
    private let shared: SAClaudeProcessListBackend
    private let sharedIsBusy: () -> Bool
    private var backend: SAClaudeProcessListBackend?   // queue only

    // Main thread only.
    private var state: State = .idle
    private var refreshInFlight = false

    /// Set (on main) once `open()` has decided; false until then.
    @objc private(set) var usesSharedConnection = false
    /// The dedicated connection's own server id (its row runs SHOW FULL PROCESSLIST); 0 on the shared fallback.
    @objc private(set) var ownConnectionId: Int64 = 0
    /// The latest fetched list, in server order.
    private(set) var processes: [SAClaudeProcess] = []
    private(set) var lastRefreshError: String?
    /// Called on main with every refresh result (after `processes` is updated), before the refresh's own completion.
    var onRefresh: ((SAClaudeProcessListRefresh) -> Void)?

    init(dedicated: @escaping () -> SAClaudeProcessListBackend?, shared: SAClaudeProcessListBackend, sharedIsBusy: @escaping () -> Bool) {
        self.makeDedicated = dedicated
        self.shared = shared
        self.sharedIsBusy = sharedIsBusy
        super.init()
    }

    /// The app's session for a document connection. `documentIsBusy` is asked on the main thread and only matters on
    /// the shared fallback.
    @objc convenience init(documentConnection: SPMySQLConnection, documentIsBusy: @escaping () -> Bool) {
        self.init(dedicated: { SAClaudeProcessListMySQLBackend.openDedicated(copying: documentConnection) },
                  shared: SAClaudeProcessListMySQLBackend(shared: documentConnection),
                  sharedIsBusy: documentIsBusy)
    }

    /// Muted note for the window when the dedicated connection couldn't be opened; nil otherwise.
    @objc var sharedConnectionNote: String? {
        usesSharedConnection
            ? NSLocalizedString("Using this window's connection — the list can't refresh while it's busy.",
                                value: "Using this window's connection — the list can't refresh while it's busy.",
                                comment: "process list : note shown when its own connection could not be opened")
            : nil
    }

    // MARK: Lifecycle

    /// Opens the dedicated connection (or settles on the shared fallback) off the main thread. Refreshes and kills
    /// queue behind it. Called implicitly by `refresh`/`kill`; a closed session stays closed.
    @objc func open() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard state == .idle else { return }
        state = .open
        queue.async {
            let dedicated = self.makeDedicated()
            self.backend = dedicated ?? self.shared
            let ownId = dedicated?.connectionId ?? 0
            DispatchQueue.main.async {
                self.usesSharedConnection = (dedicated == nil)
                self.ownConnectionId = ownId
            }
        }
    }

    /// Closes the dedicated connection (never the document's). Pending work finishes first; later calls are skipped.
    @objc func close() {
        guard Thread.isMainThread else {   // e.g. a controller released off main
            DispatchQueue.main.async { self.close() }
            return
        }
        state = .closed
        onRefresh = nil
        queue.async {
            if let backend = self.backend, backend !== self.shared { backend.close() }
            self.backend = nil
        }
    }

    // MARK: Refresh

    func refresh(_ completion: ((SAClaudeProcessListRefresh) -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        open()
        guard state == .open, !refreshInFlight else {
            DispatchQueue.main.async { completion?(.skipped) }
            return
        }
        refreshInFlight = true
        let busyNow = sharedIsBusy()
        queue.async {
            let result = self.fetchOnQueue(sharedBusy: busyNow)
            DispatchQueue.main.async {
                self.refreshInFlight = false
                self.deliver(result)
                completion?(result)
            }
        }
    }

    /// ObjC entry for `SPProcessListController`: `rows` is nil when the refresh was skipped or failed (keep the list).
    @objc(refreshWithCompletion:)
    func refreshRows(_ completion: @escaping ([[String: Any]]?) -> Void) {
        refresh { result in
            if case let .fetched(_, rows) = result { completion(rows) } else { completion(nil) }
        }
    }

    private func fetchOnQueue(sharedBusy: Bool) -> SAClaudeProcessListRefresh {
        guard let backend else { return .skipped }
        if backend === shared, sharedBusy { return .skipped }
        switch backend.fetchProcessRows() {
        case let .failure(error):
            return .failed(message: error.message)
        case let .success(raw):
            let rows = raw.map(SAClaudeProcessKillDecision.normalizedRow)
            return .fetched(processes: rows.compactMap { SAClaudeProcess(row: $0) }, rows: rows)
        }
    }

    private func deliver(_ result: SAClaudeProcessListRefresh) {
        guard state == .open else { return }
        switch result {
        case let .fetched(processes, _):
            self.processes = processes
            lastRefreshError = nil
        case let .failed(message):
            lastRefreshError = message
        case .skipped:
            break
        }
        onRefresh?(result)
    }

    // MARK: Kill

    /// Kills on the session's connection, never blocking main. `connectionId` is the id the caller showed (never a row
    /// index). Kill query re-reads the list first and only kills while the connection still runs `expectedQuery`;
    /// otherwise it reports `.changed(current:)` and kills nothing — confirm, then call again with `current.info`.
    /// Kill connection doesn't re-read (it confirms as today). An unknown thread id reports `.ended`.
    func kill(_ kind: SAClaudeProcessKillKind, connectionId: Int64, expectedQuery: String?,
              completion: @escaping (SAClaudeProcessKillOutcome) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        open()
        guard state == .open else {
            DispatchQueue.main.async { completion(.failed(message: Self.closedMessage)) }
            return
        }
        queue.async {
            let outcome = self.killOnQueue(kind, connectionId: connectionId, expectedQuery: expectedQuery)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    private func killOnQueue(_ kind: SAClaudeProcessKillKind, connectionId: Int64, expectedQuery: String?) -> SAClaudeProcessKillOutcome {
        guard let backend else { return .failed(message: Self.closedMessage) }
        if kind == .query {
            switch backend.fetchProcessRows() {
            case let .failure(error):
                return .failed(message: error.message)
            case let .success(raw):
                let current = raw.compactMap { SAClaudeProcess(row: SAClaudeProcessKillDecision.normalizedRow($0)) }
                switch SAClaudeProcessKillDecision.preflight(kind: kind, id: connectionId, expectedQuery: expectedQuery, current: current) {
                case .ended: return .ended
                case let .changed(process): return .changed(current: process)
                case .proceed: break
                }
            }
        }
        let isTiDB = SAClaudeProcessKillDecision.isTiDB(serverVersion: backend.serverVersion)
        let statement = SAClaudeProcessKillDecision.statement(kind: kind, id: connectionId, isTiDB: isTiDB)
        return SAClaudeProcessKillDecision.outcome(of: backend.execute(statement))
    }

    private static var closedMessage: String {
        NSLocalizedString("The process list's connection is closed.", value: "The process list's connection is closed.",
                          comment: "process list : kill attempted after its connection was closed")
    }
}

// MARK: - Kill with confirmations (UI)

extension SAClaudeProcessListSession {
    /// Kill query as the window does it: today's confirmation; then the re-read; if the connection moved on, the
    /// spec's question (and, on Kill, the same check against the query now shown); failures alert as today.
    /// `didFinish` runs on main once the flow is over (refresh there).
    @objc(confirmAndKillQueryOnConnectionId:shownQuery:didFinish:)
    func confirmAndKillQuery(connectionId: Int64, shownQuery: String?, didFinish: @escaping () -> Void) {
        NSAlert.createDefaultAlert(
            title: NSLocalizedString("Kill query?", comment: "kill query message"),
            message: String(format: NSLocalizedString("Are you sure you want to kill the current query executing on connection ID %lld?\n\nPlease be aware that continuing to kill this query may result in data corruption. Please proceed with caution.", comment: "kill query informative message"), connectionId),
            primaryButtonTitle: NSLocalizedString("Kill", comment: "kill button"),
            primaryButtonHandler: { self.killQueryCheckingFirst(connectionId: connectionId, expectedQuery: shownQuery, didFinish: didFinish) })
    }

    /// Kill connection as the window does it: today's confirmation, then the kill on the session's connection.
    @objc(confirmAndKillConnectionWithId:didFinish:)
    func confirmAndKillConnection(connectionId: Int64, didFinish: @escaping () -> Void) {
        NSAlert.createDefaultAlert(
            title: NSLocalizedString("Kill connection?", comment: "kill connection message"),
            message: String(format: NSLocalizedString("Are you sure you want to kill connection ID %lld?\n\nPlease be aware that continuing to kill this connection may result in data corruption. Please proceed with caution.", comment: "kill connection informative message"), connectionId),
            primaryButtonTitle: NSLocalizedString("Kill", comment: "kill button"),
            primaryButtonHandler: {
                self.kill(.connection, connectionId: connectionId, expectedQuery: nil) { outcome in
                    let title = NSLocalizedString("Unable to kill connection", comment: "error killing connection message")
                    switch outcome {
                    case let .failed(message):
                        NSAlert.createWarningAlert(title: title, message: String(format: NSLocalizedString("An error occurred while attempting to kill connection %lld.\n\nMySQL said: %@", comment: "error killing query informative message"), connectionId, message))
                    case .ended:
                        NSAlert.createWarningAlert(title: title, message: Self.endedMessage(connectionId: connectionId))
                    case .killed, .changed:
                        break
                    }
                    didFinish()
                }
            })
    }

    private func killQueryCheckingFirst(connectionId: Int64, expectedQuery: String?, didFinish: @escaping () -> Void) {
        kill(.query, connectionId: connectionId, expectedQuery: expectedQuery) { outcome in
            let title = NSLocalizedString("Unable to kill query", comment: "error killing query message")
            switch outcome {
            case .killed:
                didFinish()
            case let .failed(message):
                NSAlert.createWarningAlert(title: title, message: String(format: NSLocalizedString("An error occurred while attempting to kill the query associated with connection %lld.\n\nMySQL said: %@", comment: "error killing query informative message"), connectionId, message))
                didFinish()
            case .ended:
                NSAlert.createWarningAlert(title: title, message: Self.endedMessage(connectionId: connectionId))
                didFinish()
            case let .changed(current):
                guard let query = current.info, !query.isEmpty else {
                    NSAlert.createInfoAlert(title: NSLocalizedString("Kill query?", comment: "kill query message"),
                                            message: Self.finishedMessage(connectionId: connectionId))
                    didFinish()
                    return
                }
                NSAlert.createDefaultAlert(
                    title: NSLocalizedString("Kill query?", comment: "kill query message"),
                    message: Self.changedMessage(connectionId: connectionId, currentQuery: query),
                    primaryButtonTitle: NSLocalizedString("Kill", comment: "kill button"),
                    primaryButtonHandler: { self.killQueryCheckingFirst(connectionId: connectionId, expectedQuery: query, didFinish: didFinish) },
                    cancelButtonHandler: didFinish)
            }
        }
    }

    /// "Connection #4812 is now running a different query: … Kill it anyway?" (the query clipped for the alert).
    static func changedMessage(connectionId: Int64, currentQuery: String) -> String {
        String(format: NSLocalizedString("Connection #%lld is now running a different query:\n\n%@\n\nKill it anyway?",
                                         value: "Connection #%lld is now running a different query:\n\n%@\n\nKill it anyway?",
                                         comment: "process list : kill query found the connection running another query (id, that query)"),
               connectionId, SAClaudeProcessKillDecision.alertExcerpt(currentQuery))
    }

    static func finishedMessage(connectionId: Int64) -> String {
        String(format: NSLocalizedString("Connection #%lld has finished that query and is now idle — nothing was killed.",
                                         value: "Connection #%lld has finished that query and is now idle — nothing was killed.",
                                         comment: "process list : kill query found the connection idle (id)"),
               connectionId)
    }

    static func endedMessage(connectionId: Int64) -> String {
        String(format: NSLocalizedString("Connection #%lld has ended.", value: "Connection #%lld has ended.",
                                         comment: "process list : kill found the connection gone (id)"),
               connectionId)
    }
}

// MARK: - SPMySQL backend

/// Runs the Process List's statements on an SPMySQL connection: either a dedicated copy it owns, or the document's
/// shared connection (fallback; never disconnected here).
final class SAClaudeProcessListMySQLBackend: SAClaudeProcessListBackend {
    private let connection: SPMySQLConnection
    private let ownsConnection: Bool
    private weak var parent: SPMySQLConnection?
    private let passwordDelegate: SAClaudeProcessListPasswordDelegate?   // SPMySQL holds its delegate weakly

    init(shared connection: SPMySQLConnection) {
        self.connection = connection
        self.ownsConnection = false
        self.parent = nil
        self.passwordDelegate = nil
    }

    private init(dedicated connection: SPMySQLConnection, parent: SPMySQLConnection, passwordDelegate: SAClaudeProcessListPasswordDelegate) {
        self.connection = connection
        self.ownsConnection = true
        self.parent = parent
        self.passwordDelegate = passwordDelegate
    }

    /// Copies `parent` and connects the copy (blocking — call off main). nil when the parent isn't connected or the
    /// copy can't connect. The copy keeps SSL, socket, timeout and keep-alive settings, gets the password the way the
    /// document does (its keychain/AWS IAM delegate, forwarded), logs nothing to the document's console and has no
    /// proxy: with an SSH tunnel it connects to the tunnel's local port like the document.
    static func openDedicated(copying parent: SPMySQLConnection) -> SAClaudeProcessListMySQLBackend? {
        guard parent.isConnected(), let copy = parent.copy() as? SPMySQLConnection else { return nil }
        let delegate = SAClaudeProcessListPasswordDelegate(forwardingTo: parent.delegate())
        copy.setDelegate(delegate)
        copy.delegateQueryLogging = false
        copy.port = parent.port   // the tunnel's current local port, in case it moved since the copy's source was set up
        guard copy.connect() else {
            copy.setDelegate(nil)
            return nil
        }
        if !copy.setEncoding("utf8mb4") { _ = copy.setEncoding("utf8") }
        return SAClaudeProcessListMySQLBackend(dedicated: copy, parent: parent, passwordDelegate: delegate)
    }

    func fetchProcessRows() -> Result<[[String: Any]], SAClaudeProcessListError> {
        guard ensureConnected() else {
            return .failure(SAClaudeProcessListError(message: connection.lastErrorMessage() ?? Self.notConnectedMessage))
        }
        let result = connection.queryString("SHOW FULL PROCESSLIST")
        if connection.queryErrored() {
            return .failure(SAClaudeProcessListError(message: connection.lastErrorMessage() ?? ""))
        }
        guard let result else { return .success([]) }
        result.returnDataAsStrings = true
        var rows: [[String: Any]] = []
        rows.reserveCapacity(Int(clamping: result.numberOfRows()))
        while let row = result.getRowAsDictionary() as? [String: Any] { rows.append(row) }
        return .success(rows)
    }

    func execute(_ statement: String) -> SAClaudeProcessStatementResult {
        guard ensureConnected() else { return .error(id: 0, message: connection.lastErrorMessage() ?? Self.notConnectedMessage) }
        connection.queryString(statement)
        return connection.queryErrored() ? .error(id: connection.lastErrorID(), message: connection.lastErrorMessage() ?? "") : .ok
    }

    var serverVersion: String? { connection.serverVersionString() }

    var connectionId: Int64 { Int64(clamping: connection.mysqlConnectionThreadId) }

    func close() {
        guard ownsConnection else { return }
        connection.disconnect()
        connection.setDelegate(nil)
    }

    /// The dedicated copy reconnects (to the parent's current port) when it dropped; the shared one is left alone.
    private func ensureConnected() -> Bool {
        if connection.isConnected() { return true }
        guard ownsConnection, let parent, parent.isConnected() else { return false }
        connection.port = parent.port
        guard connection.connect() else { return false }
        if !connection.setEncoding("utf8mb4") { _ = connection.setEncoding("utf8") }
        return true
    }

    private static var notConnectedMessage: String {
        NSLocalizedString("Not connected", value: "Not connected", comment: "process list : its connection is not connected")
    }
}

/// The dedicated connection's delegate: supplies the password exactly as the document does (keychain, AWS IAM token)
/// and nothing else — no console logging, no reconnect sheets, no error alerts.
final class SAClaudeProcessListPasswordDelegate: NSObject, SPMySQLConnectionDelegate {
    private weak var target: (NSObjectProtocol & SPMySQLConnectionDelegate)?

    init(forwardingTo target: (NSObjectProtocol & SPMySQLConnectionDelegate)?) {
        self.target = target
    }

    @objc(keychainPasswordForConnection:)
    func keychainPassword(forConnection connection: Any!) -> String! {
        target?.keychainPassword?(forConnection: connection)
    }

    @objc(credentialErrorMessageForConnection:)
    func credentialErrorMessage(forConnection connection: Any!) -> String! {
        target?.credentialErrorMessage?(forConnection: connection)
    }
}
