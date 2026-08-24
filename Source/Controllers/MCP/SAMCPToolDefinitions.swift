//
//  SAMCPToolDefinitions.swift
//  Sequel Ace
//
//  The tool definitions the MCP server advertises from tools/list. Kept free
//  of app dependencies so it can be unit-tested in isolation.
//

import Foundation

/// The MCP tool catalogue: one definition per tool, each with its JSON Schema
/// input schema and MCP annotations.
enum SAMCPToolDefinitions {

    /// Returns the tool definitions advertised by tools/list.
    static func all() -> [[String: Any]] {
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
                        "params": ["type": "array", "items": ["type": ["string", "number", "boolean", "null"]], "description": "Values bound to ? placeholders, in order"],
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
    private static func makeTool(name: String, description: String, properties: [String: Any], required: [String], readOnly: Bool = true) -> [String: Any] {
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
