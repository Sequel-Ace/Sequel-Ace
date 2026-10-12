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

Sequel Ace supports three methods for connecting to remote MySQL servers:

-   **Standard** connection
-   **SSH** connection
-   **AWS IAM** connection (Amazon RDS/Aurora)

For AWS IAM setup details, see [What type of connection do I have?](connection-types.html#aws-iam-authentication).


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

#### Using an SSH Agent (1Password, Secretive, the macOS agent, …)

Sequel Ace can authenticate an SSH connection with keys held by an SSH agent, so the private key never has to be exported to a file.

Sequel Ace is sandboxed, and the sandbox does not let it (or the `ssh` it runs) open an agent's socket. To bridge that gap Sequel Ace uses a small helper script that you install once. The helper runs outside the sandbox and passes connections from Sequel Ace on to your agent. It does nothing else, and you can read it: it is a short `zsh` script.

**Set it up**

1. Open _Preferences_ > _Network_ and click _Configure…_ next to _SSH Agent_.
2. Click _Install Helper…_. A file panel opens on Sequel Ace's _Application Scripts_ folder; leave the folder as it is and click _Install_. Sequel Ace needs this one-time permission because it cannot write to that folder by itself.
3. Click _Relaunch_. Sequel Ace will not use the helper until it has been relaunched, because the permission from step 2 lasts until the app quits.
4. Choose a _Default agent_, or leave the default _Off_ and choose an agent per connection with the _SSH Agent_ option in the connection's SSH settings.

**Agent choices**

| Choice | What it uses |
| --- | --- |
| Off | No agent. Sequel Ace behaves as it always has. |
| Automatic (from SSH config) | Whatever `ssh` would use for that host: `IdentityAgent` from your SSH config file, otherwise the macOS agent. |
| System Agent | The macOS `ssh-agent` (`SSH_AUTH_SOCK`). |
| 1Password | 1Password's SSH agent. |
| Custom Socket | An agent socket path you enter, for example Secretive's or Bitwarden's. |

**What to expect**

- Your agent decides whether to allow each use of a key. With 1Password the approval prompt names the requester as `com.apple.foundation.UserScriptService`, not Sequel Ace. That is the macOS service that runs the helper; it is the name every app's user scripts appear under.
- After a Sequel Ace update that changes the helper, _Preferences_ > _Network_ > _SSH Agent_ shows _Update required_ and agent connections fail with a message saying so until you click _Update Helper…_ and relaunch.
- To offer one specific key from an agent that holds many, turn on _SSH Key_ for the connection and choose that key's public key (`.pub`) file. Servers limit how many keys a client may try.
- With your own SSH config file, your config's `IdentitiesOnly` and `AddKeysToAgent` settings apply as written. With Sequel Ace's built-in config, key files are never added to your agent.

**Which sockets the helper may reach**

The helper only connects to sockets listed in `ssh-agent-relay.allow`, a text file installed next to it (_Show in Finder_ in the SSH Agent settings reveals both). It comes with the usual 1Password, macOS agent, Secretive and Bitwarden locations. Sequel Ace cannot change this file; you can. If you use _Custom Socket_ or _Automatic_ with an agent that is not listed, the connection fails with a message that quotes the exact line to add. Links are followed before a socket is checked against the list, so what must be listed is the socket's real location, and the socket must belong to your user account.

**Limitations**

- A jump host (`ProxyJump`) uses the same agent as the destination. A jump host whose config entry names its own `IdentityAgent` is not redirected and cannot use an agent from within Sequel Ace.
- `IdentityAgent` set to an environment variable (`$NAME`) is not supported by _Automatic_; choose the agent explicitly.
- A connection opened from a `mysql://` connection string never uses an SSH agent, not even your default one, because such a link can connect without asking. After importing it, choose an agent in the connection's SSH settings.
- `PKCS11Provider` and hardware-key setups that do not go through an agent socket are not covered by the helper. See the next section.

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
4. For agent-based auth, set up the SSH agent helper described above.
5. If that is not an option, create the SSH tunnel outside Sequel Ace and connect with a **Standard** connection to `127.0.0.1`.

Example external tunnel:

```bash
ssh -f -N -L 127.0.0.1:3307:mysql-host:3306 -o ExitOnForwardFailure=yes ssh-user@jump-host
```

Then connect in Sequel Ace with:

- Host: `127.0.0.1`
- Port: `3307`
- Username/password/database: your normal MySQL credentials

Alternative without the helper: if your SSH agent supports a custom socket location, point `IdentityAgent` to a socket path inside `~/Library/Containers/com.sequel-ace.sequel-ace/Data/` and configure the agent itself to create that socket there.


#### Notes

-   the MySQL server must accept network connections

_Some server administrators forbid connections from other computers, by using the option --skip-networking. Then the MySQL server only accepts connection from processes running on the same server (e.g. PHP scripts), but not from remote clients (such as Sequel Ace). See [MySQL Manual](https://dev.mysql.com/doc/refman/en/server-options.html#option_mysqld_skip-networking)._

-   the MySQL server must be configured to accept connections from your address

Many administrators configure MySQL in a manner that it allows network connections only from specific IP addresses. If this is the case, they will probably ask you for your IP address. See [MySQL Manual](https://dev.mysql.com/doc/refman/en/connection-access.html) for details on how MySQL decides if you are allowed to connect.

If the server is behind a firewall, the firewall must be configured to accept MySQL connections.

The firewall must be configured to allow incoming TCP connections on the port used by MySQL. Per default, MySQL uses port 3306.

You must be able to reach the MySQL server directly.

If the MySQL server is behind a NAT gateway, you may not be able to reach the server.
