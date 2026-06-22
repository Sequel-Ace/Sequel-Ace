-   [Getting Connected](../get-started/)
-   [Making Queries](../queries.html)
-   [Keyboard Shortcuts](../shortcuts.html)
-   [Reference](../ref/)
-   [Bundles](../bundles/)
-   [Contribute](../contribute/)

<hr>

### MCP Server (AI Agent Integration)

Sequel Ace includes a built-in [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server. It lets AI agents such as Claude Code, Claude Desktop, and Cursor query your databases through Sequel Ace's existing connections, without any extra tooling or credentials.

The server is **disabled by default**, listens only on `127.0.0.1`, and is never reachable from another machine.

#### Enabling the server

1. Open Sequel Ace Preferences (Cmd-,)
2. Select the **MCP Server** tab
3. Check **Enable MCP Server (localhost only)**
4. Optionally change the port (default `8765`)
5. Leave **Read-only mode** enabled (the default) to reject queries that modify data, or uncheck it to allow writes

The preference pane shows a live status line and an auto-generated config snippet you can copy.

#### Available tools

| Tool | Description |
|---|---|
| `list_connections` | List saved connection favourites (names and hosts only; never passwords) |
| `list_databases` | List databases on the active connection |
| `list_tables` | List tables and views in a database |
| `describe_table` | Return columns, indexes, and foreign keys for a table |
| `run_query` | Execute SQL and return results as JSON (capped at 10,000 rows) |
| `export_results` | Run a query and write the results to a JSON or CSV file |

#### Transports

The server speaks two transports on the same port:

- **Streamable HTTP** at `/mcp` - the current MCP transport. Prefer this.
- **HTTP+SSE** at `/sse` - the older transport, kept for clients that do not yet support Streamable HTTP.

#### Connecting Claude Code

```sh
claude mcp add --transport http sequel-ace http://127.0.0.1:8765/mcp
```

Or add it to your project's `.claude/mcp.json`:

```json
{
  "mcpServers": {
    "sequel-ace": {
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

#### Connecting Claude Desktop

Add the following to `~/Library/Application Support/Claude/claude_desktop_config.json`, then restart Claude Desktop:

```json
{
  "mcpServers": {
    "sequel-ace": {
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

#### Example prompts

Once connected, you can ask your agent things like:

- *"What tables are in the `production` database?"*
- *"Show me the last 10 orders from the orders table"*
- *"Describe the schema of the `users` table"*
- *"Export all products with stock below 10 to a CSV file"*

#### Security notes

- The server only accepts connections from `127.0.0.1`. Connections from any other address receive HTTP 403.
- Requests that carry a non-loopback `Origin` header are rejected, so a web page cannot reach the server through your browser (DNS-rebinding protection).
- **Read-only mode** is on by default and rejects any statement that is not a `SELECT`, `SHOW`, `DESCRIBE`, or `EXPLAIN`. For defence in depth, also connect with a read-only database user.
- The server exposes whatever databases and privileges the active Sequel Ace connection has.
- Disable the server in Preferences when you are not using it.

#### Related History

- [Issue #2314](https://github.com/Sequel-Ace/Sequel-Ace/issues/2314)
- [PR #2372](https://github.com/Sequel-Ace/Sequel-Ace/pull/2372)
