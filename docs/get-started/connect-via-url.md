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
- `ssh_remote_socket_path`
- `socket`
- `aws_profile`
- `aws_region`
- `enable_cleartext_plugin` (set to `1` to allow MySQL's cleartext authentication plugin, required by PAM, LDAP, and some IAM-style authenticators; `0` or omission keeps it disabled)
- `get_server_public_key` (set to `1` to request the server RSA public key for `caching_sha2_password` over non-SSL connections; `0` or omission keeps it disabled)
- `request_server_public_key` (alias for `get_server_public_key`)

`type` explicitly sets the connection mode (`tcpip`, `socket`, `ssh`, or `aws_iam`) and takes precedence over inferred mode.

When `type` is omitted, Sequel Ace infers mode in this order:

1. AWS IAM if `aws_profile` or `aws_region` is present
2. Socket if `socket` is present
3. SSH if `ssh_host` or `ssh_remote_socket_path` is present
4. TCP/IP otherwise

If `socket` is present with `ssh_host` or `ssh_remote_socket_path` but no `type`, Socket mode is used.
If `ssh_keyLocation` is provided but `ssh_keyLocationEnabled` is not `1`, Sequel Ace still uses password auth.

Examples:

```sh
# SSH connection using password auth
open 'mysql://db_user:db_password@127.0.0.1:3306/my_database?ssh_host=ssh.example.com&ssh_port=22&ssh_user=ssh_user&ssh_password=ssh_password'

# SSH connection using key auth
open 'mysql://db_user:db_password@127.0.0.1:3306/my_database?ssh_host=ssh.example.com&ssh_port=22&ssh_user=ssh_user&ssh_keyLocation=%2FUsers%2Fyou%2F.ssh%2Fid_rsa&ssh_keyLocationEnabled=1'

# SSH connection to a remote Unix socket on the SSH host
open 'mysql://db_user:db_password@127.0.0.1/my_database?ssh_host=ssh.example.com&ssh_port=22&ssh_user=ssh_user&ssh_remote_socket_path=%2Fvar%2Frun%2Fmysqld%2Fmysqld.sock'

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

# Enable MySQL's cleartext authentication plugin (e.g. for PAM/LDAP)
open 'mysql://db_user:db_password@db.example.com:3306/my_database?enable_cleartext_plugin=1'

# Request the server public key for caching_sha2_password over a non-SSL connection
open 'mysql://db_user:db_password@127.0.0.1:13306/my_database?get_server_public_key=1'
```

If any unsupported query parameter is included, Sequel Ace shows an error and does not process that URL.

#### Notes

- URL values should be percent-encoded when they contain special characters (`@`, `:`, `/`, `?`, `&`, spaces, etc.).
- If no host is provided, Sequel Ace uses `127.0.0.1`.
- The first path segment is treated as the database name.
- For socket URLs, use the `socket` query parameter for the Unix socket path. Socket files must be inside Sequel Ace's container path due to macOS sandboxing.
- For SSH remote socket URLs, use `ssh_remote_socket_path` for the Unix socket path on the SSH host.
- AWS IAM URLs require Sequel Ace to already have sandbox access to your `~/.aws` directory. Grant access from the **AWS IAM** tab first.
- If you use `ssh_keyLocation`, Sequel Ace must already have sandbox access to that key path. Grant access in **Sequel Ace → Preferences → Files** (add the key file or its containing folder).
- `enable_cleartext_plugin=1` lets the MySQL client transmit the password unobscured to plugins that require it (typically PAM or LDAP back-ends). Only enable it on TLS-encrypted or SSH-tunneled connections.
- `get_server_public_key=1` maps to MySQL's server public key request option and is intended for `caching_sha2_password` connections where TLS is not being used.

#### Related History

- [Issue #108](https://github.com/Sequel-Ace/Sequel-Ace/issues/108)
- [PR #1703](https://github.com/Sequel-Ace/Sequel-Ace/pull/1703)
