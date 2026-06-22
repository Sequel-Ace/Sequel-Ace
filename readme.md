Sequel Ace <img alt="Logo" src="https://sequel-ace.com/images/appIcon-1024.png" align="right" height="80">
=======
[![Crowdin](https://badges.crowdin.net/sequel-ace/localized.svg)](https://crowdin.com/project/sequel-ace)

Sequel Ace is the "sequel" to the longtime macOS tool Sequel Pro.
Sequel Ace is a fast, easy-to-use Mac database management application for working with MySQL & MariaDB databases.

If you would like to sponsor Sequel Ace, please check out our [Open Collective](https://opencollective.com/sequel-ace) or sponsor one of our maintainers via GitHub Sponsors!

Documentation can be found at the website [sequel-ace.com](https://sequel-ace.com).

<img width="1440" height="900" alt="1" src="https://github.com/user-attachments/assets/1ed88ef5-c89d-4dca-95d5-0a567aa1409b" />


## Compatibility

- **macOS:** >= 12.0
- **Processors:** Intel & Apple Silicon
- **Databases:**
  - **MySQL:** >= 5.7
  - **MariaDB:** >= 10.0


### Previous Versions:
_If you have an unsupported version of macOS or MySQL, you can download a previous release of Sequel Ace. No support is provided for old versions and compatiblity is not guaranteed. Use at your own risk._
- For macOS 10.15-11 - [Sequel Ace (version 4.1.7)](https://github.com/Sequel-Ace/Sequel-Ace/releases/tag/production%2F4.1.7-20080)
- For macOS 10.13-10.14 - [Sequel Ace (version 4.1.7)](https://github.com/Sequel-Ace/Sequel-Ace/releases/tag/production%2F4.1.7-20080)
  - To run Sequel Ace on Mac OS X 10.13-10.14.4, you need to install Apple's Swift Standard Libraries for the app to work as expected. You can download this support package free of charge from [here (this repository)](https://github.com/Sequel-Ace/Sequel-Ace/blob/main/Scripts/) or [here (Apple directly)](https://support.apple.com/kb/DL1998?locale=en_GB).
- For Mac OS X 10.12 or for MySQL 5.6 support - [Sequel Ace (version 3.5.2)](https://github.com/Sequel-Ace/Sequel-Ace/releases/tag/production%2F3.5.2-20033)
- For Mac OS X 10.10-10.11 - [Sequel Ace (version 2.3.2)](https://github.com/Sequel-Ace/Sequel-Ace/releases/tag/production%2F2.3.2-2121)


## Installation

### Mac AppStore <a href="https://apps.apple.com/us/app/sequel-ace/id1518036000?ls=1"><img alt="Download on the Mac AppStore" src="https://sequel-ace.com/images/download_on_mas.png" align="right" height="60"></a>

Download Sequel Ace today from the [macOS App Store](https://apps.apple.com/us/app/sequel-ace/id1518036000?ls=1)!

### MAS CLI

To install via `mas` [MAS CLI](https://github.com/mas-cli/mas) use Sequel Ace id `1518036000`

```sh
mas install 1518036000 # Sequel Ace
```

### Homebrew

To install an unofficial community maintained [Homebrew](https://brew.sh) [Cask](https://github.com/Homebrew/homebrew-cask) of the [GitHub Release](https://github.com/sequel-ace/sequel-ace/releases)

```sh
brew install --cask sequel-ace
```

## MCP Server (AI Agent Integration)

Sequel Ace includes a built-in [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server that lets AI agents — such as Claude Code, Claude Desktop, Cursor, and others — query your databases directly through Sequel Ace's existing connections.

### Enabling the MCP Server

1. Open **Sequel Ace → Preferences** (⌘,)
2. Click the **MCP Server** tab
3. Check **Enable MCP Server (localhost only)**
4. Optionally change the port (default: `8765`)
5. Leave **Read-only mode** enabled (default) to reject queries that modify data, or uncheck it to allow writes

The server listens only on `127.0.0.1` and is not accessible from other machines.

### Available Tools

| Tool | Description |
|---|---|
| `list_connections` | List the connections open in Sequel Ace (id, host, current database, which is active) |
| `list_databases` | List databases on a connection |
| `list_tables` | List tables and views in a database |
| `describe_table` | Show columns, indexes, and foreign keys |
| `get_table_ddl` | Return the `CREATE TABLE` statement |
| `list_views` / `list_procedures` / `list_functions` / `list_triggers` | List routines in a database |
| `get_routine_definition` | Return the `CREATE` statement for a view/procedure/function/trigger/event |
| `run_query` | Execute SQL and return results as JSON |
| `explain_query` | Return the `EXPLAIN` plan without executing |
| `sample_table` | Return up to N rows from a table |
| `count_rows` | Exact row count of a table |
| `export_results` | Run a query and save results to a JSON or CSV file |
| `server_info` | Server version and key configuration variables |
| `table_sizes` | Per-table row estimates and storage sizes |
| `process_list` | `SHOW FULL PROCESSLIST` |

Every database tool takes an optional `connection` id (from `list_connections`) to
target a specific open tab; it defaults to the active tab. The server also exposes
table schemas as **MCP resources** and provides **argument completion** for database,
table, and connection names.

The server supports two transports. Prefer the modern **Streamable HTTP**
endpoint (`/mcp`); the **HTTP+SSE** endpoint (`/sse`) is kept for older clients.

### Connecting Claude Desktop

Add the following to your `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "sequel-ace": {
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

Then restart Claude Desktop.

### Connecting Claude Code

```sh
claude mcp add --transport http sequel-ace http://127.0.0.1:8765/mcp
```

Or add to your project's `.claude/mcp.json`:

```json
{
  "mcpServers": {
    "sequel-ace": {
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

### Example Usage

Once connected, you can ask your AI agent natural-language questions like:

- *"What tables are in the `production` database?"*
- *"Show me the last 10 orders from the orders table"*
- *"Describe the schema of the `users` table"*
- *"Export all products with stock < 10 to a CSV file"*

### Security Notes

- The server **only** accepts connections from `127.0.0.1` (localhost). Remote connections are rejected.
- Requests carrying a non-loopback `Origin` header are rejected, so a web page cannot reach the server through your browser.
- **Read-only mode** is on by default and rejects any query that is not a SELECT/SHOW/DESCRIBE/EXPLAIN. For defence in depth, also use a read-only database user.
- The server exposes whatever databases and permissions the active Sequel Ace connection has.
- Disable the server in Preferences when not in use.

---

## Moving Saved Connections from Sequel Pro

To migrate your favorites, please check the [migration guide](https://sequel-ace.com/get-started/migrating-from-sequel-pro.html).

## Contributing

Please refer to [this](https://github.com/Sequel-Ace/Sequel-Ace/blob/main/Guides/Contributing.md) doc.

### Translations

If you would like to help with translations, please sign up for Crowdin and join our [Crowdin project](https://crowdin.com/project/sequel-ace) to translate Sequel Ace into supported languages. Also, if you want to add a new language, please [create a new issue](https://github.com/Sequel-Ace/Sequel-Ace/issues/new/choose), and we will be happy to enable that language for you to translate!

### Development

If you would like to help with code and development, please see either our [projects page](https://github.com/sequel-ace/sequel-ace/projects) or [issues](https://github.com/Sequel-Ace/Sequel-Ace/issues/new/choose) with relevant labels such as [Help Wanted](https://github.com/Sequel-Ace/Sequel-Ace/issues?q=is%3Aopen+is%3Aissue+label%3A%22Help+wanted%22), [Bug](https://github.com/Sequel-Ace/Sequel-Ace/issues?q=is%3Aopen+is%3Aissue+label%3ABug), [Feature Request](https://github.com/Sequel-Ace/Sequel-Ace/labels/Feature%20Request), and [PR Welcome](https://github.com/Sequel-Ace/Sequel-Ace/labels/PR%20Welcome). These lists contain the issues where we would most like your help. There are both challenging and straightforward tasks there, so new contributors should be able to get started. For more technical information see [the developer guide](https://github.com/Sequel-Ace/Sequel-Ace/blob/main/Guides/Developing.md)

## Branches

- main: Main is our active development branch. All contribution PRs should be pointed at main!

## Tags & Releases

- production/ tags represent submissions to the macOS App Store. These are marked as "Pre-Release" until approved by Apple and officially released by the team. Both release candidates and final releases use production/ tags. Release candidates will have RC or Release Candidate in their title.
- beta/ tags represent pre-release versions of Sequel Ace intended to test new features and bug fixes. The downloadable app in a beta/ tag has a different name and identifier (Sequel Ace Beta), meaning you can install it side-by-side with the latest App Store release. Beta releases also have increased logging turned on to help us identify critical issues.

## Code of Conduct

Please refer [here](https://github.com/Sequel-Ace/Sequel-Ace/blob/main/Guides/Code_of_conduct.md)

## License

Copyright (c) 2020-2026 Moballo, LLC.  All rights reserved.
Forked from Sequel Pro: Copyright (c) 2002-2019 Sequel Pro & CocoaMySQL Teams. All rights reserved.

Sequel Ace is free and open-source software licensed under [MIT](https://opensource.org/licenses/MIT). See [LICENSE](https://github.com/sequel-ace/sequel-ace/blob/master/LICENSE) for complete details.
