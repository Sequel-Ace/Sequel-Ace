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

- `type` (`tcpip`, `socket`, `ssh`, or `aws_iam`)
- `ssh_host`
- `ssh_port`
- `ssh_user`
- `ssh_password`
- `ssh_keyLocation`
- `ssh_keyLocationEnabled` (set to `1` to enable key-based auth; `0` or omission keeps password auth)
- `socket`
- `aws_profile`
- `aws_region`

If `type=ssh` or `ssh_host` is present, Sequel Ace opens the connection in SSH mode.
If `ssh_keyLocation` is provided but `ssh_keyLocationEnabled` is not `1`, Sequel Ace still uses password auth.
If `type=socket` is present, Sequel Ace opens the connection in Socket mode.
If `socket` is present, Sequel Ace also opens in Socket mode (even when `type` is omitted).
If `type=aws_iam` is present, Sequel Ace opens the connection in AWS IAM mode.
If `aws_profile` or `aws_region` is present, Sequel Ace also opens in AWS IAM mode (even when `type` is omitted).

`type=tcpip` forces a standard TCP/IP connection.

Examples:

```sh
# SSH connection using password auth
open 'mysql://db_user:db_password@127.0.0.1:3306/my_database?ssh_host=ssh.example.com&ssh_port=22&ssh_user=ssh_user&ssh_password=ssh_password'

# SSH connection using key auth
open 'mysql://db_user:db_password@127.0.0.1:3306/my_database?ssh_host=ssh.example.com&ssh_port=22&ssh_user=ssh_user&ssh_keyLocation=%2FUsers%2Fyou%2F.ssh%2Fid_rsa&ssh_keyLocationEnabled=1'

# `ssh_keyLocation` without enabling key auth still uses password auth
open 'mysql://db_user:db_password@127.0.0.1:3306/my_database?ssh_host=ssh.example.com&ssh_port=22&ssh_user=ssh_user&ssh_keyLocation=%2FUsers%2Fyou%2F.ssh%2Fid_rsa&ssh_keyLocationEnabled=0'

# Socket connection (explicit type)
open 'mysql://root@localhost/my_database?type=socket&socket=%2FUsers%2Fyou%2FLibrary%2FContainers%2Fcom.sequel-ace.sequel-ace%2FData%2Fmysql.sock'

# Socket connection (type inferred from socket query parameter)
open 'mysql://root@localhost/my_database?socket=%2FUsers%2Fyou%2FLibrary%2FContainers%2Fcom.sequel-ace.sequel-ace%2FData%2Fmysql.sock'

# AWS IAM connection (explicit type)
open 'mysql://db_user@mydb.cluster-abcdefghijkl.us-east-1.rds.amazonaws.com:3306/my_database?type=aws_iam&aws_profile=default&aws_region=us-east-1'

# AWS IAM connection (type inferred from AWS parameters)
open 'mysql://db_user@mydb.cluster-abcdefghijkl.us-east-1.rds.amazonaws.com:3306/my_database?aws_profile=default'
```

If any unsupported query parameter is included, Sequel Ace shows an error and does not process that URL.

#### Notes

- URL values should be percent-encoded when they contain special characters (`@`, `:`, `/`, `?`, `&`, spaces, etc.).
- If no host is provided, Sequel Ace uses `127.0.0.1`.
- The first path segment is treated as the database name.
- For socket URLs, use the `socket` query parameter for the Unix socket path. Socket files must be inside Sequel Ace's container path due to macOS sandboxing.
- AWS IAM URLs require Sequel Ace to already have sandbox access to your `~/.aws` directory. Grant access from the **AWS IAM** tab first.
- If you use `ssh_keyLocation`, Sequel Ace must already have sandbox access to that key path. Grant access in **Sequel Ace → Preferences → Files** (add the key file or its containing folder).

#### Related History

- [Issue #108](https://github.com/Sequel-Ace/Sequel-Ace/issues/108)
- [PR #1703](https://github.com/Sequel-Ace/Sequel-Ace/pull/1703)
