-   [Getting Connected](../get-started/)
-   [Making Queries](../queries.html)
-   [Keyboard Shortcuts](../shortcuts.html)
-   [Reference](../ref/)
-   [Bundles](../bundles/)
-   [Contribute](../contribute/)

<hr>

### Open a Connection via URL (`mysql://`)

Sequel Ace supports opening connection details via the `mysql://` URL scheme.

This is useful when launching Sequel Ace from shell scripts, automation tools, PAM tooling, and other desktop apps.

#### Quick Start

```sh
open 'mysql://user:password@db.example.com:3306/app_db'
```

Sequel Ace will open a new connection tab using the values from the URL.

#### URL Format

```text
mysql://[user[:password]@][host[:port]][/database][?query_parameters]
```

Examples:

```sh
# Standard TCP connection
open 'mysql://root:secret@127.0.0.1:3306/my_database'

# Host defaults to 127.0.0.1 when omitted
open 'mysql://root:secret@/my_database'
```

#### Supported Query Parameters

These query parameters are currently supported:

- `ssh_host`
- `ssh_port`
- `ssh_user`
- `ssh_password`
- `ssh_keyLocation`
- `ssh_keyLocationEnabled` (set to `1` to enable key-based auth; `0` or omission keeps password auth)

If `ssh_host` is present, Sequel Ace opens the connection in SSH mode.
If `ssh_keyLocation` is provided but `ssh_keyLocationEnabled` is not `1`, Sequel Ace still uses password auth.

Examples:

```sh
# SSH connection using password auth
open 'mysql://db_user:db_password@127.0.0.1:3306/my_database?ssh_host=ssh.example.com&ssh_port=22&ssh_user=ssh_user&ssh_password=ssh_password'

# SSH connection using key auth
open 'mysql://db_user:db_password@127.0.0.1:3306/my_database?ssh_host=ssh.example.com&ssh_port=22&ssh_user=ssh_user&ssh_keyLocation=%2FUsers%2Fyou%2F.ssh%2Fid_rsa&ssh_keyLocationEnabled=1'

# `ssh_keyLocation` without enabling key auth still uses password auth
open 'mysql://db_user:db_password@127.0.0.1:3306/my_database?ssh_host=ssh.example.com&ssh_port=22&ssh_user=ssh_user&ssh_keyLocation=%2FUsers%2Fyou%2F.ssh%2Fid_rsa&ssh_keyLocationEnabled=0'
```

If any unsupported query parameter is included, Sequel Ace shows an error and does not process that URL.

#### Notes

- URL values should be percent-encoded when they contain special characters (`@`, `:`, `/`, `?`, `&`, spaces, etc.).
- If no host is provided, Sequel Ace uses `127.0.0.1`.
- The first path segment is treated as the database name.
- Socket paths are not currently supported in `mysql://` URLs. For socket-based connections, use a regular socket favorite (see [Connect to a Local MySQL Server](local-connection.html)).
- If you use `ssh_keyLocation`, Sequel Ace must already have sandbox access to that key path. Grant access in **Sequel Ace → Preferences → Files** (add the key file or its containing folder).

#### Related History

- [Issue #108](https://github.com/Sequel-Ace/Sequel-Ace/issues/108)
- [PR #1703](https://github.com/Sequel-Ace/Sequel-Ace/pull/1703)
