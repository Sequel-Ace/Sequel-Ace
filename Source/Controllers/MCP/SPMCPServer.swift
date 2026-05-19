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
    /// Returns an array of connection-favourite dictionaries (name, host, port, user, database, type).
    func mcpListConnections() -> [[String: String]]

    /// Returns names of all databases on the active connection, or an error.
    func mcpListDatabases() -> [String: Any]

    /// Lists tables in the given database. Returns {"tables": [...]} or {"error": "..."}.
    func mcpListTables(inDatabase database: String) -> [String: Any]

    /// Describes a table's columns, indexes and foreign keys. Returns {"columns": [...], "indexes": [...]} or {"error": "..."}.
    func mcpDescribeTable(_ table: String, inDatabase database: String) -> [String: Any]

    /// Runs an arbitrary SQL statement. Returns {"columns": [...], "rows": [...], "rowsAffected": N} or {"error": "..."}.
    func mcpRunQuery(_ sql: String) -> [String: Any]

    /// Runs a query and writes results to disk. Returns {"path": "...", "rowCount": N} or {"error": "..."}.
    func mcpExportResults(_ sql: String, format: String, path: String) -> [String: Any]
}

// MARK: - MCP Server

/// SPMCPServer runs a local HTTP+SSE server that implements the Model Context Protocol (MCP).
///
/// The server listens only on 127.0.0.1, making it inaccessible to remote hosts.
/// It exposes the following MCP tools to AI agents:
///   - list_connections, list_databases, list_tables, describe_table, run_query, export_results
///
/// Transport: HTTP with Server-Sent Events (SSE), per the MCP 2024-11-05 specification.
/// Reference: https://modelcontextprotocol.io/specification/2024-11-05/basic/transports#http-with-sse
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
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            DispatchQueue.main.async { completion(false, "Invalid port number") }
            return
        }

        // Restrict to loopback only for security.
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"), port: nwPort)

        let newListener: NWListener
        do {
            newListener = try NWListener(using: params, on: nwPort)
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

        listenerLock.lock()
        listener = newListener
        listenerLock.unlock()

        newListener.start(queue: serverQueue)
    }

    /// Stop the server and close all open SSE connections.
    @objc public func stop() {
        listenerLock.lock()
        let l = listener
        listener = nil
        listenerLock.unlock()
        l?.cancel()

        clientsLock.lock()
        let all = sseClients
        sseClients.removeAll()
        clientsLock.unlock()
        for client in all.values { client.connection.cancel() }
    }

    // MARK: - Private state

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

    func accept(connection: NWConnection) {
        connection.start(queue: serverQueue)
        receiveRequest(on: connection, buffer: Data())
    }

    // Accumulate data until we have a complete HTTP request, then dispatch.
    func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                connection.cancel()
                print("MCP: receive error: \(error)")
                return
            }
            var buf = buffer
            if let data { buf.append(data) }

            guard let request = HTTPRequest(data: buf) else {
                // Need more data
                self.receiveRequest(on: connection, buffer: buf)
                return
            }
            self.handle(request: request, on: connection)
        }
    }

    func handle(request: HTTPRequest, on connection: NWConnection) {
        // Safety: only accept loopback connections.
        if case let .hostPort(host, _) = connection.endpoint {
            let hostStr = "\(host)"
            guard hostStr == "127.0.0.1" || hostStr == "::1" || hostStr == "localhost" else {
                sendHTTPResponse(connection: connection, status: 403, body: "Forbidden")
                return
            }
        }

        switch (request.method, request.path) {
        case ("GET", "/sse"):
            handleSSE(request: request, connection: connection)
        case ("POST", "/message"):
            handleMessage(request: request, connection: connection)
        case ("GET", "/health"):
            sendHTTPResponse(connection: connection, status: 200, body: "OK", keepAlive: false)
        default:
            sendHTTPResponse(connection: connection, status: 404, body: "Not Found", keepAlive: false)
        }
    }
}

// MARK: - SSE endpoint

private extension SPMCPServer {

    func handleSSE(request: HTTPRequest, connection: NWConnection) {
        let sessionID = UUID().uuidString
        let clientID  = UUID()

        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "Access-Control-Allow-Origin: *",
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

    func sendSSEEvent(_ event: String, data: String, to connection: NWConnection, completion: ((NWError?) -> Void)? = nil) {
        let text = "event: \(event)\ndata: \(data)\n\n"
        send(text: text, on: connection, completion: completion)
    }

    func sendSSEMessage(_ object: Any, to connection: NWConnection) {
        guard let json = try? JSONSerialization.data(withJSONObject: object),
              let jsonStr = String(data: json, encoding: .utf8) else { return }
        sendSSEEvent("message", data: jsonStr, to: connection)
    }

    func send(text: String, on connection: NWConnection, completion: ((NWError?) -> Void)? = nil) {
        guard let data = text.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { completion?($0) })
    }
}

// MARK: - Message (JSON-RPC) endpoint

private extension SPMCPServer {

    func handleMessage(request: HTTPRequest, connection: NWConnection) {
        guard let sessionID = request.queryParam("sessionId") else {
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
            self.sendToSSEClient(sessionID: sessionID, message: response)
        }
    }

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

    func dispatch(jsonRPC json: [String: Any]) -> [String: Any] {
        let id     = json["id"]
        let method = json["method"] as? String ?? ""
        let params = json["params"] as? [String: Any]

        switch method {
        case "initialize":
            return jsonRPCSuccess(id: id, result: initializeResult())

        case "notifications/initialized":
            // No response required for notifications, but we return an empty result.
            return [:]  // Caller will skip empty dicts.

        case "tools/list":
            return jsonRPCSuccess(id: id, result: ["tools": toolDefinitions()])

        case "tools/call":
            let toolName  = params?["name"] as? String ?? ""
            let arguments = params?["arguments"] as? [String: Any] ?? [:]
            let callResult = callTool(name: toolName, arguments: arguments)
            return jsonRPCSuccess(id: id, result: callResult)

        case "ping":
            return jsonRPCSuccess(id: id, result: [:])

        default:
            return jsonRPCError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    func initializeResult() -> [String: Any] {
        return [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": ["listChanged": false]
            ],
            "serverInfo": [
                "name": "sequel-ace-mcp",
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            ]
        ]
    }

    func jsonRPCSuccess(id: Any?, result: [String: Any]) -> [String: Any] {
        var response: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { response["id"] = id }
        return response
    }

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

    func toolDefinitions() -> [[String: Any]] {
        return [
            makeTool(
                name: "list_connections",
                description: "List all saved database connections (favourites) configured in Sequel Ace.",
                properties: [:],
                required: []
            ),
            makeTool(
                name: "list_databases",
                description: "List all databases on the currently active connection.",
                properties: [:],
                required: []
            ),
            makeTool(
                name: "list_tables",
                description: "List all tables (and views) in a specific database.",
                properties: [
                    "database": ["type": "string", "description": "Database name"]
                ],
                required: ["database"]
            ),
            makeTool(
                name: "describe_table",
                description: "Return the column definitions, indexes, and foreign keys for a table.",
                properties: [
                    "database": ["type": "string", "description": "Database name"],
                    "table":    ["type": "string", "description": "Table name"]
                ],
                required: ["database", "table"]
            ),
            makeTool(
                name: "run_query",
                description: "Execute an SQL statement and return the results as JSON. Read-only queries are strongly recommended; write queries are permitted if the connection allows them.",
                properties: [
                    "sql": ["type": "string", "description": "SQL statement to execute"]
                ],
                required: ["sql"]
            ),
            makeTool(
                name: "export_results",
                description: "Execute an SQL query and save the results to a file on the local machine.",
                properties: [
                    "sql":    ["type": "string",  "description": "SQL statement to execute"],
                    "format": ["type": "string",  "description": "Output format: 'json' (default) or 'csv'"],
                    "path":   ["type": "string",  "description": "Optional absolute file path. Defaults to the export folder configured in Sequel Ace preferences."]
                ],
                required: ["sql"]
            )
        ]
    }

    func makeTool(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        return [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required
            ]
        ]
    }
}

// MARK: - Tool execution

private extension SPMCPServer {

    func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        guard let ds = dataSource else {
            return toolError("No active database connection. Please connect to a database in Sequel Ace first.")
        }

        switch name {
        case "list_connections":
            let conns = ds.mcpListConnections()
            return toolResult(text: jsonString(conns) ?? "[]")

        case "list_databases":
            let result = ds.mcpListDatabases()
            return toolResultFromDict(result, key: "databases")

        case "list_tables":
            guard let db = arguments["database"] as? String else {
                return toolError("Missing required argument: database")
            }
            let result = ds.mcpListTables(inDatabase: db)
            return toolResultFromDict(result, key: "tables")

        case "describe_table":
            guard let db    = arguments["database"] as? String,
                  let table = arguments["table"]    as? String else {
                return toolError("Missing required arguments: database, table")
            }
            let result = ds.mcpDescribeTable(table, inDatabase: db)
            if let err = result["error"] as? String { return toolError(err) }
            return toolResult(text: jsonString(result) ?? "{}")

        case "run_query":
            guard let sql = arguments["sql"] as? String else {
                return toolError("Missing required argument: sql")
            }
            let result = ds.mcpRunQuery(sql)
            if let err = result["error"] as? String { return toolError(err) }
            return toolResult(text: jsonString(result) ?? "{}")

        case "export_results":
            guard let sql = arguments["sql"] as? String else {
                return toolError("Missing required argument: sql")
            }
            let format = arguments["format"] as? String ?? "json"
            let path   = arguments["path"]   as? String ?? defaultExportPath(format: format)
            let result = ds.mcpExportResults(sql, format: format, path: path)
            if let err = result["error"] as? String { return toolError(err) }
            return toolResult(text: jsonString(result) ?? "{}")

        default:
            return toolError("Unknown tool: \(name)")
        }
    }

    // Builds an MCP tool result from a dict that may contain an "error" key.
    func toolResultFromDict(_ dict: [String: Any], key: String) -> [String: Any] {
        if let err = dict["error"] as? String { return toolError(err) }
        let value = dict[key]
        return toolResult(text: jsonString(value) ?? "[]")
    }

    func toolResult(text: String) -> [String: Any] {
        return ["content": [["type": "text", "text": text]], "isError": false]
    }

    func toolError(_ message: String) -> [String: Any] {
        return ["content": [["type": "text", "text": message]], "isError": true]
    }

    func jsonString(_ value: Any?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

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

    func sendHTTPResponse(connection: NWConnection, status: Int, body: String, keepAlive: Bool = false) {
        let statusLine: String
        switch status {
        case 200: statusLine = "HTTP/1.1 200 OK"
        case 202: statusLine = "HTTP/1.1 202 Accepted"
        case 400: statusLine = "HTTP/1.1 400 Bad Request"
        case 403: statusLine = "HTTP/1.1 403 Forbidden"
        case 404: statusLine = "HTTP/1.1 404 Not Found"
        default:  statusLine = "HTTP/1.1 \(status)"
        }
        let bodyData  = body.data(using: .utf8) ?? Data()
        let connValue = keepAlive ? "keep-alive" : "close"
        let response  = [
            statusLine,
            "Content-Type: text/plain; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Connection: \(connValue)",
            "Access-Control-Allow-Origin: *",
            "", ""
        ].joined(separator: "\r\n")

        var responseData = response.data(using: .utf8)!
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            if !keepAlive { connection.cancel() }
        })
    }
}

// MARK: - HTTPRequest parser

private struct HTTPRequest {
    let method:  String
    let path:    String
    let headers: [String: String]
    let body:    Data?

    /// Returns a parsed request if `data` contains a complete HTTP/1.1 request,
    /// or `nil` if more data is needed.
    init?(data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil   // Incomplete headers.
        }

        let headerData = data[data.startIndex..<headerEnd.lowerBound]
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        method = parts[0]

        // Split path and query string.
        let fullPath = parts[1]
        path = fullPath.components(separatedBy: "?").first ?? fullPath

        var hdrs = [String: String]()
        for line in lines.dropFirst() {
            let kv = line.components(separatedBy: ": ")
            if kv.count >= 2 {
                hdrs[kv[0].lowercased()] = kv.dropFirst().joined(separator: ": ")
            }
        }
        headers = hdrs

        // Parse query string from the full path.
        if fullPath.contains("?") {
            let qs = fullPath.components(separatedBy: "?").dropFirst().joined(separator: "?")
            queryString = qs
        } else {
            queryString = nil
        }

        let bodyStart = data.index(headerEnd.upperBound, offsetBy: 0)
        let expectedLength = Int(hdrs["content-length"] ?? "0") ?? 0
        let remaining = data.distance(from: bodyStart, to: data.endIndex)

        if expectedLength > 0 {
            if remaining < expectedLength { return nil }   // Body not fully arrived.
            body = Data(data[bodyStart..<data.index(bodyStart, offsetBy: expectedLength)])
        } else {
            body = nil
        }
    }

    private let queryString: String?

    func queryParam(_ key: String) -> String? {
        guard let qs = queryString else { return nil }
        for pair in qs.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2, kv[0] == key {
                return kv[1].removingPercentEncoding
            }
        }
        return nil
    }
}
