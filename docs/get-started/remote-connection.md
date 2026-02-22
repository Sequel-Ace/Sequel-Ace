-   [Getting Connected](../get-started/)
-   [Making Queries](../queries.html)
-   [Keyboard Shortcuts](../shortcuts.html)
-   [Reference](../ref/)
-   [Bundles](../bundles/)
-   [Contribute](../contribute/)

<hr>

### Connect to a Remote MySQL Server

This page explains how to connect to a MySQL Server running on a different computer than Sequel Ace.


#### Connection Types For Connecting to a Remote Host

At the moment, Sequel Ace supports two methods for connecting to remote MySQL servers:

-   **Standard** connection
-   **SSH** connection


##### Standard Connections

**Standard connections** are the simplest method to connect to a MySQL server. A standard connection in Sequel Ace is a connection over the local network or the internet. It uses the TCP/IP protocol. Standard connections are not encrypted.


##### SSH connections

You can use a **SSH connection** to circumvent some of the restrictions of standard conections. A SSH connection is actually not really a different kind of connection, but rather a standard connection made _through a SSH tunnel_. While a standard connection involves only two hosts (your computer and the host on which the MySQL server is running), a SSH connection involves a third host, the **SSH host**. The SSH host can be the same as the MySQL host, but it doesn't have to be.

_An SSH connection can be used to connect through a firewall (if the firewall allows SSH tunnels). `sshd` is a process that accepts SSH connections, and `mysqld` is the MySQL server process._

If you use a SSH connection, Sequel Ace first creates a SSH tunnel to the SSH host. Then it uses this tunnel to connect via a standard connection _from the SSH host_ to the MySQL host. This complicated procedure allows you to:

-   Connect to a server behind a firewall

_If a firewall prevents direct access to the MySQL server, you might still be able to connect via SSH to a computer behind the firewall (or the MySQL server itself), and from there to the MySQL server._

-   Encrypt the connection

_If you use a SSH connection, the connection between your computer and the SSH host are encrypted. Please note that the connection between the SSH host and the MySQL host is not encrypted._

Of course, SSH connections don't solve every problem. The following requirements are necessary:

-   like above, the MySQL server must accept network connections
-   the MySQL server must allow access from the SSH host
-   you must be able to reach the SSH host

_If the SSH host is behind a firewall, it must be configured to allow SSH connections. Also, if the SSH host is behind a NAT, it must also be configured correctly._


#### Choosing a SSH Host

The SSH host can basically be any computer that can access the MySQL server. You could for example use your desktop computer at work to connect to your company's MySQL server from home. A hosting provider might tell you to connect to their MySQL server via a specific SSH host. You need a username and a password for the computer you want to use as the SSH host, and it must support remote access via SSH. Almost all Unix/Linux systems and macOS have built-in SSH support. On Mac OS, SSH ist called _Remote Login_ and can be enabled in the _Sharing_ preferences. If you want to use a Microsoft Windows computer as a SSH host, you must install a SSH server first (this might be difficult).


#### Creating an SSH Connection from Terminal.app

Sequel Ace now sets up an SSH Tunnel for you when you choose the SSH connection type. However there still may be scenarios where you might wish to set one up yourself. You can setup an SSH tunnel using the following command from Terminal.app:

$ ssh -L 1234:mysqlhost:3306 sshuser@sshhost

Here `mysqlhost` is what you have to enter in Sequel Ace as the MySQL host, `sshuser` corresponds to the SSH user, and `sshhost` corresponds to the SSH host field, obviously. The first number, `1234`, is the local port of the SSH tunnel. Sequel Ace chooses this port automatically. The second number in the command, `3306`, is the port used by the MySQL server.

#### SSH Agent and ProxyCommand Limitations on macOS

Sequel Ace is sandboxed on macOS and uses the system SSH client. Some advanced SSH setups that work in Terminal may fail in Sequel Ace if they require direct access to sockets, helper binaries, or files outside what Sequel Ace can access.

Common failure messages include:

- `ssh_get_authentication_socket: Operation not permitted`
- `load pubkey "...": Operation not permitted`
- `.../zsh: Operation not permitted` (or similar errors for shell/helper paths)

This most often affects setups using `SSH_AUTH_SOCK`, `IdentityAgent`, `PKCS11Provider`, `ProxyCommand`, hardware keys (for example YubiKey/OpenSC), or non-system shell/tool paths.

Recommended troubleshooting steps:

1. In Sequel Ace, go to _Preferences_ > _Network_ and select your custom SSH config file.
2. In _Preferences_ > _Files_, grant access to all SSH support paths your config uses (for example `~/.ssh`, key files, `known_hosts`, include files, helper scripts, certificate files).
3. In your SSH config, prefer built-in macOS tools when possible (for example `/usr/bin/ssh`, `/usr/bin/nc`, `/bin/zsh`) instead of symlinked/non-system paths.
4. If agent-based auth still fails, create the SSH tunnel outside Sequel Ace and connect with a **Standard** connection to `127.0.0.1`.

Example external tunnel:

```bash
ssh -f -N -L 127.0.0.1:3307:mysql-host:3306 -o ExitOnForwardFailure=yes ssh-user@jump-host
```

Then connect in Sequel Ace with:

- Host: `127.0.0.1`
- Port: `3307`
- Username/password/database: your normal MySQL credentials

Advanced option: If your SSH agent supports a custom socket location, point `IdentityAgent` to a socket path inside `~/Library/Containers/com.sequel-ace.sequel-ace/Data/` and configure the agent itself to create that socket there.


#### Notes

-   the MySQL server must accept network connections

_Some server administrators forbid connections from other computers, by using the option --skip-networking. Then the MySQL server only accepts connection from processes running on the same server (e.g. PHP scripts), but not from remote clients (such as Sequel Ace). See [MySQL Manual](https://dev.mysql.com/doc/refman/en/server-options.html#option_mysqld_skip-networking)._

-   the MySQL server must be configured to accept connections from your address

Many administrators configure MySQL in a manner that it allows network connections only from specific IP addresses. If this is the case, they will probably ask you for your IP address. See [MySQL Manual](https://dev.mysql.com/doc/refman/en/connection-access.html) for details on how MySQL decides if you are allowed to connect.

If the server is behind a firewall, the firewall must be configured to accept MySQL connections.

The firewall must be configured to allow incoming TCP connections on the port used by MySQL. Per default, MySQL uses port 3306.

You must be able to reach the MySQL server directly.

If the MySQL server is behind a NAT gateway, you may not be able to reach the server.
