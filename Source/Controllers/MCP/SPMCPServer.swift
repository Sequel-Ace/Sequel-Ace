//
//  SPMCPServer.swift
//  Sequel Ace
//
//  Created for Sequel Ace by contributors.
//  See https://github.com/Sequel-Ace/Sequel-Ace/issues/2314
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.

import Foundation
import Network

// MARK: - Data Source Protocol

/// Provides database operations to the MCP server. Implemented by SPAppController.
/// All methods may be called from a background queue.
@objc public protocol SPMCPDataSource: AnyObject {
    /// Open connections (one per Sequel Ace tab): id, name, host, database, active.
    func mcpListConnections() -> [[String: Any]]

    /// Databases on the given connection (empty id = front tab).
    func mcpListDatabases(onConnection connID: String) -> [String: Any]

    /// Tables and views in a database.
    func mcpListTables(inDatabase database: String, connection connID: String) -> [String: Any]

    /// Columns, indexes and foreign keys for a table.
    func mcpDescribeTable(_ table: String, inDatabase database: String, connection connID: String) -> [String: Any]

    /// The CREATE TABLE statement for a table.
    func mcpTableDDL(_ table: String, inDatabase database: String, connection connID: String) -> [String: Any]

    /// Routines of a type ("view"/"procedure"/"function"/"trigger"/"event") in a database.
    func mcpListRoutines(ofType type: String, inDatabase database: String, connection connID: String) -> [String: Any]

    /// The CREATE statement for a routine.
    func mcpRoutineDefinition(ofType type: String, name: String, inDatabase database: String, connection connID: String) -> [String: Any]

    /// Runs an arbitrary SQL statement, binding `params` to ? placeholders and
    /// optionally paginating a read query with limit/offset (limit 0 = no paging).
    func mcpRunQuery(_ sql: String, params: [Any], limit: Int, offset: Int, connection connID: String) -> [String: Any]

    /// Returns the EXPLAIN plan for a query (does not execute it).
    func mcpExplainQuery(_ sql: String, connection connID: String) -> [String: Any]

    /// Returns up to `limit` rows from a table, starting at `offset`.
    func mcpSampleTable(_ table: String, inDatabase database: String, limit: Int, offset: Int, connection connID: String) -> [String: Any]

    /// Terminates a server-side query/connection by process id.
    func mcpKillProcessID(_ processID: String, connection connID: String) -> [String: Any]

    /// Returns the exact row count of a table.
    func mcpCountRows(inTable table: String, inDatabase database: String, connection connID: String) -> [String: Any]

    /// Runs a query and writes results to disk.
    func mcpExportResults(_ sql: String, format: String, path: String, connection connID: String) -> [String: Any]

    /// Server version and key variables.
    func mcpServerInfo(onConnection connID: String) -> [String: Any]

    /// Per-table row estimates and storage sizes for a database.
    func mcpTableSizes(inDatabase database: String, connection connID: String) -> [String: Any]

    /// The server process list (SHOW FULL PROCESSLIST).
    func mcpProcessList(onConnection connID: String) -> [String: Any]
}

// MARK: - MCP Server

/// SPMCPServer runs a local HTTP server implementing the Model Context Protocol (MCP):
/// tools, resources, prompts and argument completions over JSON-RPC.
///
/// The server listens only on 127.0.0.1, making it inaccessible to remote hosts.
///
/// Transports: the modern Streamable HTTP transport at POST /mcp (MCP 2025-03-26) and
/// the legacy HTTP+SSE transport at GET /sse + POST /message (MCP 2024-11-05). The
/// protocol version is negotiated from `supportedProtocolVersions`.
/// Reference: https://modelcontextprotocol.io/specification
@objc public final class SPMCPServer: NSObject {

    // MARK: - Singleton

    @objc public static let shared = SPMCPServer()
    private override init() { super.init() }

    // MARK: - Public interface

    @objc public weak var dataSource: SPMCPDataSource?

    /// `true` while the listener is running and accepting connections.
    @objc public var isRunning: Bool {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        return listener != nil
    }

    /// Start the server on `port`. Completion fires on the main queue.
    @objc public func start(port: UInt16, completion: @escaping (Bool, String?) -> Void) {
        // Tear down any existing listener, then bind the new one once the old port is released.
        stop {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                DispatchQueue.main.async { completion(false, "Invalid port number") }
                return
            }

            // Restrict to loopback only for security. The port comes from
            // requiredLocalEndpoint; passing `on:` as well is rejected with EINVAL.
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"), port: nwPort)

            let newListener: NWListener
            do {
                newListener = try NWListener(using: params)
            } catch {
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
                return
            }

            newListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async { completion(true, nil) }
                case .failed(let error):
                    DispatchQueue.main.async { completion(false, error.localizedDescription) }
                    self?.stop()
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] conn in
                self?.accept(connection: conn)
            }

            self.listenerLock.lock()
            self.listener = newListener
            self.listenerLock.unlock()

            newListener.start(queue: self.serverQueue)
        }
    }

    /// Stop the server and close all open SSE connections.
    @objc public func stop() {
        stop(completion: nil)
    }

    /// Stop the server and close all open SSE connections.
    /// `completion` fires on the main queue once the listener has fully cancelled.
    public func stop(completion: (() -> Void)?) {
        listenerLock.lock()
        let l = listener
        listener = nil
        listenerLock.unlock()

        clientsLock.lock()
        let all = sseClients
        sseClients.removeAll()
        clientsLock.unlock()
        for client in all.values { client.connection.cancel() }

        guard let l = l else {
            DispatchQueue.main.async { completion?() }
            return
        }

        // Signal completion once the listener reports .cancelled.
        l.stateUpdateHandler = { state in
            if case .cancelled = state {
                DispatchQueue.main.async { completion?() }
            }
        }
        l.cancel()
    }

    // MARK: - Private state

    /// Maximum accepted size of a single HTTP request before the connection is
    /// rejected with 413, to bound memory use on a never-completing request.
    static let maxRequestBytes = 16 * 1024 * 1024

    private var listener: NWListener?
    private let listenerLock = NSLock()

    private let serverQueue = DispatchQueue(label: "com.sequel-ace.mcp.server", qos: .utility)
    private let dbQueue    = DispatchQueue(label: "com.sequel-ace.mcp.db",     qos: .userInitiated)

    private struct SSEClient {
        let connection: NWConnection
        let sessionID: String
    }
    private var sseClients = [UUID: SSEClient]()
    private let clientsLock = NSLock()
}

// MARK: - Connection handling

private extension SPMCPServer {

    /// Accepts a new connection and begins reading its first request.
    func accept(connection: NWConnection) {
        connection.start(queue: serverQueue)
        receiveRequest(on: connection, buffer: Data())
    }

    // Accumulate data until we have a complete HTTP request, then dispatch.
    func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                connection.cancel()
                print("MCP: receive error: \(error)")
                return
            }
            var buf = buffer
            if let data { buf.append(data) }

            // Bound the buffer so a client cannot grow memory without end by never
            // completing a request (no header terminator, or an absurd Content-Length).
            if buf.count > SPMCPServer.maxRequestBytes {
                self.sendHTTPResponse(connection: connection, status: 413, body: "Request too large")
                return
            }

            guard let request = HTTPRequest(data: buf) else {
                // The peer closed (EOF) before sending a complete request: cancel
                // rather than re-arm, otherwise receive keeps completing immediately
                // on the closed connection and spins the server.
                if isComplete {
                    connection.cancel()
                    return
                }
                // Need more data
                self.receiveRequest(on: connection, buffer: buf)
                return
            }
            self.handle(request: request, on: connection)
        }
    }

    /// Routes a parsed request to the matching endpoint after loopback and Origin checks.
    func handle(request: HTTPRequest, on connection: NWConnection) {
        // Safety: only accept loopback connections.
        if case let .hostPort(host, _) = connection.endpoint {
            let hostStr = "\(host)"
            guard hostStr == "127.0.0.1" || hostStr == "::1" || hostStr == "localhost" else {
                sendHTTPResponse(connection: connection, status: 403, body: "Forbidden")
                return
            }
        }

        // Reject cross-origin browser requests so a web page cannot reach the
        // server through the user's browser (DNS-rebinding protection).
        if let origin = request.headers["origin"], !SPMCPHTTP.isLoopbackOrigin(origin) {
            sendHTTPResponse(connection: connection, status: 403, body: "Forbidden origin")
            return
        }

        switch SPMCPHTTP.route(method: request.method, path: request.path) {
        case .streamableHTTP:
            handleStreamableHTTP(request: request, connection: connection)
        case .sse:
            handleSSE(request: request, connection: connection)
        case .message:
            handleMessage(request: request, connection: connection)
        case .health:
            sendHTTPResponse(connection: connection, status: 200, body: "OK", keepAlive: false)
        case .methodNotAllowed:
            sendHTTPResponse(connection: connection, status: 405,
                             body: "Method Not Allowed. POST to /mcp for the Streamable HTTP transport, or use GET /sse for the legacy SSE transport.",
                             extraHeaders: ["Allow: POST"], keepAlive: false)
        case .notFound:
            sendHTTPResponse(connection: connection, status: 404, body: "Not Found", keepAlive: false)
        }
    }
}

// MARK: - SSE endpoint

private extension SPMCPServer {

    /// Opens an SSE stream (legacy transport) and advertises the per-session message endpoint.
    func handleSSE(request: HTTPRequest, connection: NWConnection) {
        let sessionID = UUID().uuidString
        let clientID  = UUID()

        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "", ""
        ].joined(separator: "\r\n")

        send(text: headers, on: connection) { [weak self] error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            self.clientsLock.lock()
            self.sseClients[clientID] = SSEClient(connection: connection, sessionID: sessionID)
            self.clientsLock.unlock()

            // Drop the client when its connection closes, so sseClients does not leak
            // entries or hand out a stale session.
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled:
                    self?.clientsLock.lock()
                    self?.sseClients.removeValue(forKey: clientID)
                    self?.clientsLock.unlock()
                default:
                    break
                }
            }

            // Advertise the message endpoint for this session.
            let msgURL = "http://127.0.0.1:\(self.listeningPort)/message?sessionId=\(sessionID)"
            self.sendSSEEvent("endpoint", data: msgURL, to: connection)
        }
    }

    var listeningPort: UInt16 {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        if let port = listener?.port?.rawValue { return port }
        return UInt16(UserDefaults.standard.integer(forKey: SPMCPServerPort))
    }

    /// Sends a named SSE event with a data payload.
    func sendSSEEvent(_ event: String, data: String, to connection: NWConnection, completion: ((NWError?) -> Void)? = nil) {
        let text = "event: \(event)\ndata: \(data)\n\n"
        send(text: text, on: connection, completion: completion)
    }

    /// Sends a JSON-RPC message to a client as an SSE event.
    func sendSSEMessage(_ object: Any, to connection: NWConnection) {
        guard let json = try? JSONSerialization.data(withJSONObject: object),
              let jsonStr = String(data: json, encoding: .utf8) else { return }
        sendSSEEvent("message", data: jsonStr, to: connection)
    }

    /// Writes raw text to a connection, invoking completion when sent.
    func send(text: String, on connection: NWConnection, completion: ((NWError?) -> Void)? = nil) {
        guard let data = text.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { completion?($0) })
    }
}

// MARK: - Message (JSON-RPC) endpoint

private extension SPMCPServer {

    /// Streamable HTTP transport (MCP 2025-03-26): a single POST endpoint that
    /// returns the JSON-RPC response directly as application/json.
    func handleStreamableHTTP(request: HTTPRequest, connection: NWConnection) {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            sendHTTPResponse(connection: connection, status: 400, body: "Invalid JSON body")
            return
        }

        let sessionID = request.headers["mcp-session-id"] ?? UUID().uuidString

        dbQueue.async { [weak self] in
            guard let self else { return }
            let response = self.dispatch(jsonRPC: json)
            if response.isEmpty {
                // Notification: acknowledge with no body.
                self.sendHTTPResponse(connection: connection, status: 202, body: "", keepAlive: false)
                return
            }
            let data = (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
            self.sendJSONResponse(connection: connection, jsonData: data, sessionID: sessionID)
        }
    }

    /// Handles a legacy POST /message: dispatches the body and replies over SSE.
    func handleMessage(request: HTTPRequest, connection: NWConnection) {
        guard let sessionID = request.queryParam("sessionId"), !sessionID.isEmpty else {
            sendHTTPResponse(connection: connection, status: 400, body: "Missing sessionId")
            return
        }
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            sendHTTPResponse(connection: connection, status: 400, body: "Invalid JSON body")
            return
        }

        // Acknowledge immediately; actual response comes via SSE.
        sendHTTPResponse(connection: connection, status: 202, body: "Accepted", keepAlive: false)

        dbQueue.async { [weak self] in
            guard let self else { return }
            let response = self.dispatch(jsonRPC: json)
            // An empty dict means there is no response to send (e.g. notifications).
            if !response.isEmpty {
                self.sendToSSEClient(sessionID: sessionID, message: response)
            }
        }
    }

    /// Delivers a message to the SSE client for the given session id.
    func sendToSSEClient(sessionID: String, message: Any) {
        clientsLock.lock()
        let client = sseClients.values.first { $0.sessionID == sessionID }
        clientsLock.unlock()
        guard let client else {
            print("MCP: No SSE client found for sessionId \(sessionID)")
            return
        }
        sendSSEMessage(message, to: client.connection)
    }
}

// MARK: - JSON-RPC dispatch

private extension SPMCPServer {

    /// Dispatches one JSON-RPC request to its handler and returns the response.
    func dispatch(jsonRPC json: [String: Any]) -> [String: Any] {
        let id     = json["id"]
        let method = json["method"] as? String ?? ""
        let params = json["params"] as? [String: Any]

        // A JSON-RPC request without an `id` is a notification: the server must not
        // reply at all. Returning an empty dict suppresses the response (the caller
        // skips empty dicts) rather than sending an invalid id-less response.
        if id == nil { return [:] }

        switch method {
        case "initialize":
            let clientVersion = params?["protocolVersion"] as? String
            return jsonRPCSuccess(id: id, result: initializeResult(protocolVersion: clientVersion))

        case "tools/list":
            return jsonRPCSuccess(id: id, result: ["tools": toolDefinitions()])

        case "tools/call":
            let toolName  = params?["name"] as? String ?? ""
            let arguments = params?["arguments"] as? [String: Any] ?? [:]
            let callResult = callTool(name: toolName, arguments: arguments)
            return jsonRPCSuccess(id: id, result: callResult)

        case "resources/list":
            return jsonRPCSuccess(id: id, result: ["resources": resourceList()])

        case "resources/read":
            let uri = params?["uri"] as? String ?? ""
            return jsonRPCSuccess(id: id, result: ["contents": resourceRead(uri: uri)])

        case "completion/complete":
            return jsonRPCSuccess(id: id, result: ["completion": completion(params: params)])

        case "prompts/list":
            return jsonRPCSuccess(id: id, result: ["prompts": promptDefinitions()])

        case "prompts/get":
            return jsonRPCSuccess(id: id, result: promptGet(params: params))

        case "ping":
            return jsonRPCSuccess(id: id, result: [:])

        case let m where m.hasPrefix("notifications/"):
            return [:]   // a notification carrying an id: still no response

        default:
            return jsonRPCError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    /// MCP protocol versions this server actually implements.
    static let supportedProtocolVersions = ["2025-03-26", "2024-11-05"]

    /// Builds the initialize result: protocol version, capabilities, server info and usage instructions.
    func initializeResult(protocolVersion: String? = nil) -> [String: Any] {
        // Only echo a version we support; otherwise advertise our newest supported one.
        let negotiated = SPMCPServer.supportedProtocolVersions.contains(protocolVersion ?? "")
            ? protocolVersion!
            : SPMCPServer.supportedProtocolVersions[0]
        return [
            "protocolVersion": negotiated,
            "capabilities": [
                "tools": ["listChanged": false],
                "resources": ["subscribe": false, "listChanged": false],
                "completions": [:],
                "prompts": ["listChanged": false]
            ],
            "serverInfo": [
                "name": "sequel-ace-mcp",
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            ],
            "instructions": "This server exposes the MySQL/MariaDB connections open in Sequel Ace's tabs. "
                + "Call list_connections first to see the open connections; each has an id. Every database "
                + "tool takes an optional `connection` id and otherwise runs against the active tab. Explore "
                + "schema with list_databases, list_tables and describe_table, read data with run_query or "
                + "sample_table, and inspect a plan with explain_query. When read-only mode is enabled, only "
                + "SELECT/SHOW/DESCRIBE/EXPLAIN statements are accepted."
        ]
    }

    /// Wraps a result in a JSON-RPC success envelope.
    func jsonRPCSuccess(id: Any?, result: [String: Any]) -> [String: Any] {
        var response: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { response["id"] = id }
        return response
    }

    /// Wraps a code and message in a JSON-RPC error envelope.
    func jsonRPCError(id: Any?, code: Int, message: String) -> [String: Any] {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message]
        ]
        if let id { response["id"] = id }
        return response
    }
}

// MARK: - Tool definitions

private extension SPMCPServer {

    /// Returns the tool definitions advertised by tools/list.
    func toolDefinitions() -> [[String: Any]] {
        let conn: [String: Any] = ["type": "string", "description": "Optional connection id from list_connections; defaults to the active Sequel Ace tab."]
        let db:   [String: Any] = ["type": "string", "description": "Database name"]
        let tbl:  [String: Any] = ["type": "string", "description": "Table name"]

        return [
            makeTool(name: "list_connections",
                     description: "List the database connections currently open in Sequel Ace (one per tab), with their id, host, current database, and which one is active.",
                     properties: [:], required: []),
            makeTool(name: "list_databases",
                     description: "List all databases on a connection.",
                     properties: ["connection": conn], required: []),
            makeTool(name: "list_tables",
                     description: "List all tables and views in a database.",
                     properties: ["database": db, "connection": conn], required: ["database"]),
            makeTool(name: "describe_table",
                     description: "Return the columns, indexes, and foreign keys for a table.",
                     properties: ["database": db, "table": tbl, "connection": conn], required: ["database", "table"]),
            makeTool(name: "get_table_ddl",
                     description: "Return the CREATE TABLE statement for a table.",
                     properties: ["database": db, "table": tbl, "connection": conn], required: ["database", "table"]),
            makeTool(name: "list_views",
                     description: "List the views in a database.",
                     properties: ["database": db, "connection": conn], required: ["database"]),
            makeTool(name: "list_procedures",
                     description: "List the stored procedures in a database.",
                     properties: ["database": db, "connection": conn], required: ["database"]),
            makeTool(name: "list_functions",
                     description: "List the stored functions in a database.",
                     properties: ["database": db, "connection": conn], required: ["database"]),
            makeTool(name: "list_triggers",
                     description: "List the triggers in a database.",
                     properties: ["database": db, "connection": conn], required: ["database"]),
            makeTool(name: "get_routine_definition",
                     description: "Return the CREATE statement for a view, procedure, function, trigger, or event.",
                     properties: [
                        "database": db,
                        "type": ["type": "string", "description": "One of: view, procedure, function, trigger, event"],
                        "name": ["type": "string", "description": "Routine name"],
                        "connection": conn
                     ], required: ["database", "type", "name"]),
            makeTool(name: "run_query",
                     description: "Execute an SQL statement and return the results as JSON. Use ? placeholders with `params` for values (safer than string-building). For read queries you can paginate with `limit`/`offset`. When read-only mode is enabled in Sequel Ace preferences, only single non-destructive read statements (SELECT/SHOW/DESCRIBE/EXPLAIN) are accepted; otherwise write queries are permitted if the connection allows them.",
                     properties: [
                        "sql": ["type": "string", "description": "SQL statement; use ? for bound parameters"],
                        "params": ["type": "array", "description": "Values bound to ? placeholders, in order"],
                        "limit": ["type": "integer", "description": "Optional row limit for read queries (paginates by wrapping the query)"],
                        "offset": ["type": "integer", "description": "Optional row offset, used with limit"],
                        "connection": conn
                     ],
                     required: ["sql"], readOnly: false),
            makeTool(name: "explain_query",
                     description: "Return the EXPLAIN plan for a query without executing it.",
                     properties: ["sql": ["type": "string", "description": "SQL statement to explain"], "connection": conn],
                     required: ["sql"]),
            makeTool(name: "sample_table",
                     description: "Return up to `limit` rows from a table (default 10, max 1000), starting at `offset`.",
                     properties: [
                        "database": db, "table": tbl,
                        "limit": ["type": "integer", "description": "Maximum number of rows (default 10, max 1000)"],
                        "offset": ["type": "integer", "description": "Row offset to start from (default 0)"],
                        "connection": conn
                     ], required: ["database", "table"]),
            makeTool(name: "count_rows",
                     description: "Return the exact row count of a table.",
                     properties: ["database": db, "table": tbl, "connection": conn], required: ["database", "table"]),
            makeTool(name: "kill_query",
                     description: "Terminate a running server-side query or connection by its process id (from process_list). Not allowed in read-only mode.",
                     properties: ["process_id": ["type": "integer", "description": "Process id to kill"], "connection": conn],
                     required: ["process_id"], readOnly: false),
            makeTool(name: "export_results",
                     description: "Execute an SQL query and save the results to a file on the local machine.",
                     properties: [
                        "sql":    ["type": "string", "description": "SQL statement to execute"],
                        "format": ["type": "string", "description": "Output format: 'json' (default) or 'csv'"],
                        "path":   ["type": "string", "description": "Optional absolute file path. Defaults to the export folder in Sequel Ace preferences."],
                        "connection": conn
                     ], required: ["sql"], readOnly: false),
            makeTool(name: "server_info",
                     description: "Return the server version and key configuration variables for a connection.",
                     properties: ["connection": conn], required: []),
            makeTool(name: "table_sizes",
                     description: "Return per-table row estimates and storage sizes for a database.",
                     properties: ["database": db, "connection": conn], required: ["database"]),
            makeTool(name: "process_list",
                     description: "Return the server process list (SHOW FULL PROCESSLIST).",
                     properties: ["connection": conn], required: [])
        ]
    }

    /// Builds one tool definition with its input schema and annotations.
    func makeTool(name: String, description: String, properties: [String: Any], required: [String], readOnly: Bool = true) -> [String: Any] {
        // MCP tool annotations (2025-03-26): all tools are closed-world (they only
        // touch the connected database); reads are non-destructive, run_query and
        // export_results may modify data.
        return [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required
            ],
            "annotations": [
                "title": name.replacingOccurrences(of: "_", with: " ").capitalized,
                "readOnlyHint": readOnly,
                "destructiveHint": !readOnly,
                "openWorldHint": false
            ]
        ]
    }
}

// MARK: - Tool execution

private extension SPMCPServer {

    /// Executes a tool call by name and returns its MCP tool result.
    func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        guard let ds = dataSource else {
            return toolError("No active database connection. Please connect to a database in Sequel Ace first.")
        }

        let conn = arguments["connection"] as? String ?? ""

        func requireString(_ key: String) -> String? { arguments[key] as? String }

        switch name {
        case "list_connections":
            return toolResult(text: jsonString(ds.mcpListConnections()) ?? "[]")

        case "list_databases":
            return dictResult(ds.mcpListDatabases(onConnection: conn))

        case "list_tables":
            guard let db = requireString("database") else { return toolError("Missing required argument: database") }
            return dictResult(ds.mcpListTables(inDatabase: db, connection: conn))

        case "describe_table":
            guard let db = requireString("database"), let table = requireString("table") else {
                return toolError("Missing required arguments: database, table")
            }
            return dictResult(ds.mcpDescribeTable(table, inDatabase: db, connection: conn))

        case "get_table_ddl":
            guard let db = requireString("database"), let table = requireString("table") else {
                return toolError("Missing required arguments: database, table")
            }
            return dictResult(ds.mcpTableDDL(table, inDatabase: db, connection: conn))

        case "list_views", "list_procedures", "list_functions", "list_triggers":
            guard let db = requireString("database") else { return toolError("Missing required argument: database") }
            let type = ["list_views": "view", "list_procedures": "procedure",
                        "list_functions": "function", "list_triggers": "trigger"][name] ?? "view"
            return dictResult(ds.mcpListRoutines(ofType: type, inDatabase: db, connection: conn))

        case "get_routine_definition":
            guard let db = requireString("database"), let type = requireString("type"), let rname = requireString("name") else {
                return toolError("Missing required arguments: database, type, name")
            }
            return dictResult(ds.mcpRoutineDefinition(ofType: type, name: rname, inDatabase: db, connection: conn))

        case "run_query":
            guard let sql = requireString("sql") else { return toolError("Missing required argument: sql") }
            if let rejection = readOnlyRejection(for: sql) { return rejection }
            let params = arguments["params"] as? [Any] ?? []
            let limit  = (arguments["limit"] as? NSNumber)?.intValue ?? 0
            let offset = (arguments["offset"] as? NSNumber)?.intValue ?? 0
            return dictResult(ds.mcpRunQuery(sql, params: params, limit: limit, offset: offset, connection: conn))

        case "explain_query":
            guard let sql = requireString("sql") else { return toolError("Missing required argument: sql") }
            // EXPLAIN ANALYZE executes the statement, and the ANALYZE modifier may sit
            // behind other EXPLAIN modifiers (e.g. FORMAT=TREE ANALYZE ...) or a /*! */
            // comment. Block all of those, since explain is allowed in read-only mode.
            if SPMCPReadOnlyGuard.explainWouldExecute(sql) {
                return toolError("EXPLAIN ANALYZE is not allowed; it would execute the statement.")
            }
            return dictResult(ds.mcpExplainQuery(sql, connection: conn))

        case "sample_table":
            guard let db = requireString("database"), let table = requireString("table") else {
                return toolError("Missing required arguments: database, table")
            }
            let limit  = (arguments["limit"] as? NSNumber)?.intValue ?? 10
            let offset = (arguments["offset"] as? NSNumber)?.intValue ?? 0
            return dictResult(ds.mcpSampleTable(table, inDatabase: db, limit: limit, offset: offset, connection: conn))

        case "kill_query":
            if UserDefaults.standard.bool(forKey: SPMCPReadOnly) {
                return toolError("Read-only mode is enabled; kill_query is not allowed. Disable read-only mode in Sequel Ace Preferences > MCP Server.")
            }
            guard let pid = arguments["process_id"] else { return toolError("Missing required argument: process_id") }
            return dictResult(ds.mcpKillProcessID("\(pid)", connection: conn))

        case "count_rows":
            guard let db = requireString("database"), let table = requireString("table") else {
                return toolError("Missing required arguments: database, table")
            }
            return dictResult(ds.mcpCountRows(inTable: table, inDatabase: db, connection: conn))

        case "export_results":
            guard let sql = requireString("sql") else { return toolError("Missing required argument: sql") }
            if let rejection = readOnlyRejection(for: sql) { return rejection }
            // Normalise format so the chosen extension and the written content agree.
            let format = (requireString("format") ?? "json").lowercased()
            let path   = requireString("path") ?? defaultExportPath(format: format)
            return dictResult(ds.mcpExportResults(sql, format: format, path: path, connection: conn))

        case "server_info":
            return dictResult(ds.mcpServerInfo(onConnection: conn))

        case "table_sizes":
            guard let db = requireString("database") else { return toolError("Missing required argument: database") }
            return dictResult(ds.mcpTableSizes(inDatabase: db, connection: conn))

        case "process_list":
            return dictResult(ds.mcpProcessList(onConnection: conn))

        default:
            return toolError("Unknown tool: \(name)")
        }
    }

    // MARK: - Resources

    private func uriEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    /// Lists the tables of the active connection's current database as MCP resources.
    func resourceList() -> [[String: Any]] {
        guard let ds = dataSource else { return [] }
        let conns = ds.mcpListConnections()
        guard let active = conns.first(where: { ($0["active"] as? Bool) ?? false }) ?? conns.first else { return [] }
        let connID = active["id"] as? String ?? ""
        guard let database = active["database"] as? String, !database.isEmpty else { return [] }

        let result = ds.mcpListTables(inDatabase: database, connection: connID)
        guard let tables = result["tables"] as? [[String: Any]] else { return [] }

        return tables.compactMap { t in
            guard let name = t["name"] as? String else { return nil }
            let uri = "sequelace://\(uriEncode(connID))/\(uriEncode(database))/\(uriEncode(name))"
            return [
                "uri": uri,
                "name": "\(database).\(name)",
                "description": "Schema (columns, indexes, foreign keys) for \(database).\(name)",
                "mimeType": "application/json"
            ]
        }
    }

    /// Reads a `sequelace://<connId>/<database>/<table>` resource as the table schema.
    func resourceRead(uri: String) -> [[String: Any]] {
        guard let ds = dataSource else { return [] }
        let trimmed = uri.replacingOccurrences(of: "sequelace://", with: "")
        let parts = trimmed.components(separatedBy: "/").map { $0.removingPercentEncoding ?? $0 }
        guard parts.count == 3 else { return [] }
        let (connID, database, table) = (parts[0], parts[1], parts[2])
        let schema = ds.mcpDescribeTable(table, inDatabase: database, connection: connID)
        return [[
            "uri": uri,
            "mimeType": "application/json",
            "text": jsonString(schema) ?? "{}"
        ]]
    }

    // MARK: - Argument completion

    func completion(params: [String: Any]?) -> [String: Any] {
        let argument = params?["argument"] as? [String: Any]
        let argName  = argument?["name"] as? String ?? ""
        let typed    = (argument?["value"] as? String ?? "").lowercased()
        let context  = (params?["context"] as? [String: Any])?["arguments"] as? [String: Any] ?? [:]
        let connID   = context["connection"] as? String ?? ""

        var values: [String] = []
        guard let ds = dataSource else { return completionResult([]) }

        switch argName {
        case "connection":
            values = ds.mcpListConnections().compactMap { $0["id"] as? String }
        case "type":
            values = ["view", "procedure", "function", "trigger", "event"]
        case "database":
            if let dbs = ds.mcpListDatabases(onConnection: connID)["databases"] as? [String] { values = dbs }
        case "table":
            if let db = context["database"] as? String, !db.isEmpty,
               let tables = ds.mcpListTables(inDatabase: db, connection: connID)["tables"] as? [[String: Any]] {
                values = tables.compactMap { $0["name"] as? String }
            }
        default:
            values = []
        }

        if !typed.isEmpty {
            values = values.filter { $0.lowercased().hasPrefix(typed) }
        }
        return completionResult(values)
    }

    /// Caps and packages completion values into a completion result.
    private func completionResult(_ values: [String]) -> [String: Any] {
        let capped = Array(values.prefix(100))
        return ["values": capped, "total": capped.count, "hasMore": values.count > capped.count]
    }

    // MARK: - Prompts

    /// Reusable prompt templates advertised via prompts/list.
    func promptDefinitions() -> [[String: Any]] {
        return [
            ["name": "analyze_schema",
             "description": "Explore and summarise the structure of a database.",
             "arguments": [["name": "database", "description": "Database to analyse", "required": true]]],
            ["name": "summarize_table",
             "description": "Describe and sample a table, then summarise what it stores.",
             "arguments": [["name": "database", "description": "Database name", "required": true],
                           ["name": "table", "description": "Table name", "required": true]]],
            ["name": "optimize_query",
             "description": "Analyse a query's plan and suggest optimisations or indexes.",
             "arguments": [["name": "sql", "description": "SQL query to optimise", "required": true]]]
        ]
    }

    /// Builds a prompts/get result: a single user message from the named template.
    func promptGet(params: [String: Any]?) -> [String: Any] {
        let name = params?["name"] as? String ?? ""
        let args = params?["arguments"] as? [String: Any] ?? [:]
        let database = args["database"] as? String ?? ""
        let table    = args["table"] as? String ?? ""
        let sql      = args["sql"] as? String ?? ""

        let text: String
        switch name {
        case "analyze_schema":
            text = "Analyse the `\(database)` database. Use list_tables to enumerate its tables, describe_table on the important ones, and summarise the data model and the key relationships between tables."
        case "summarize_table":
            text = "Describe `\(database)`.`\(table)` with describe_table and fetch a few rows with sample_table, then summarise what the table stores, its notable columns, and how it relates to other tables."
        case "optimize_query":
            text = "Use explain_query to analyse the plan for this query, then suggest optimisations (rewrites, indexes) with reasoning:\n\n\(sql)"
        default:
            text = "Unknown prompt: \(name)"
        }

        return [
            "description": "Sequel Ace MCP prompt: \(name)",
            "messages": [[
                "role": "user",
                "content": ["type": "text", "text": text]
            ]]
        ]
    }

    /// Returns a tool error when read-only mode is on and `sql` is not a
    /// non-destructive read, otherwise nil.
    func readOnlyRejection(for sql: String) -> [String: Any]? {
        guard UserDefaults.standard.bool(forKey: SPMCPReadOnly) else { return nil }
        guard SPMCPReadOnlyGuard.isReadOnly(sql) else {
            return toolError("Read-only mode is enabled. Only single, non-destructive read statements (SELECT, SHOW, DESCRIBE, EXPLAIN) are allowed. Turn off read-only mode in Sequel Ace Preferences > MCP Server to run write queries.")
        }
        return nil
    }

    // Builds an MCP tool result from a data-source dict: surfaces an "error" key
    // as a tool error, otherwise serialises the whole dict as the tool output.
    func dictResult(_ dict: [String: Any]) -> [String: Any] {
        if let err = dict["error"] as? String { return toolError(err) }
        return toolResult(text: jsonString(dict) ?? "{}")
    }

    /// Builds a successful tool result containing text content.
    func toolResult(text: String) -> [String: Any] {
        return ["content": [["type": "text", "text": text]], "isError": false]
    }

    /// Builds a tool result flagged as an error.
    func toolError(_ message: String) -> [String: Any] {
        return ["content": [["type": "text", "text": message]], "isError": true]
    }

    /// Serialises a JSON value to a pretty-printed, key-sorted string.
    func jsonString(_ value: Any?) -> String? {
        return SPMCPJSON.string(from: value)
    }

    /// Returns the default export file path for the given format.
    func defaultExportPath(format: String) -> String {
        let folder = UserDefaults.standard.string(forKey: SPMCPExportPath)
            ?? NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        let ext = format == "csv" ? "csv" : "json"
        let ts  = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return (folder as NSString).appendingPathComponent("sequel-ace-export-\(ts).\(ext)")
    }
}

// MARK: - HTTP helpers

private extension SPMCPServer {

    /// Sends a plain-text HTTP response with the given status code.
    func sendHTTPResponse(connection: NWConnection, status: Int, body: String, extraHeaders: [String] = [], keepAlive: Bool = false) {
        let statusLine: String
        switch status {
        case 200: statusLine = "HTTP/1.1 200 OK"
        case 202: statusLine = "HTTP/1.1 202 Accepted"
        case 400: statusLine = "HTTP/1.1 400 Bad Request"
        case 403: statusLine = "HTTP/1.1 403 Forbidden"
        case 404: statusLine = "HTTP/1.1 404 Not Found"
        case 405: statusLine = "HTTP/1.1 405 Method Not Allowed"
        case 413: statusLine = "HTTP/1.1 413 Payload Too Large"
        default:  statusLine = "HTTP/1.1 \(status)"
        }
        let bodyData  = body.data(using: .utf8) ?? Data()
        let connValue = keepAlive ? "keep-alive" : "close"
        let response  = ([
            statusLine,
            "Content-Type: text/plain; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Connection: \(connValue)"
        ] + extraHeaders + ["", ""]).joined(separator: "\r\n")

        var responseData = response.data(using: .utf8)!
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            if !keepAlive { connection.cancel() }
        })
    }

    /// Sends an application/json response (Streamable HTTP), echoing the session id.
    func sendJSONResponse(connection: NWConnection, jsonData: Data, sessionID: String?) {
        var lines = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/json",
            "Content-Length: \(jsonData.count)",
            "Connection: close"
        ]
        if let sessionID { lines.append("Mcp-Session-Id: \(sessionID)") }
        lines.append("")
        lines.append("")

        var responseData = lines.joined(separator: "\r\n").data(using: .utf8)!
        responseData.append(jsonData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
