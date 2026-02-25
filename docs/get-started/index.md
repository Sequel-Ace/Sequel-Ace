-   [Getting Connected](../get-started/)
-   [Making Queries](../queries.html)
-   [Keyboard Shortcuts](../shortcuts.html)
-   [Reference](../ref/)
-   [Bundles](../bundles/)
-   [Contribute](../contribute/)

<hr>

### Getting Connected

When you open Sequel Ace, the first screen that you will see is the database connection window. If you don't have access to a MySQL server, perhaps you could try installing [MySQL](https://dev.mysql.com/doc/mysql-osx-excerpt/en/osx-installation.html "MySQL:Installing on MacOS") or [MariaDB](https://mariadb.com/kb/en/installing-mariadb-on-macos-using-homebrew "MariaDB:Installing on MacOS") on your Mac.


#### Frequently Asked Questions

**How do I migrate my favorites from Sequel Pro to Sequel Ace?**

Please check out [this page](migrating-from-sequel-pro.html) for info on how to migrate from Sequel Pro!

**Can I open a Sequel Ace connection via URL (for automation or PAM tools)?**

Yes. Sequel Ace supports `mysql://` URLs including SSH query parameters. See [Open a Connection via URL (`mysql://`)](connect-via-url.html).

**I am having trouble connecting to a database. It says: Can't connect to local MySQL server through socket '/tmp/mysql.sock' (2)**

This is a known macOS sandboxing limitation. Sequel Ace cannot access socket files outside its container, even with Full Disk Access enabled.

Use one of these workarounds:

1. Configure MySQL/MariaDB so it creates the socket directly inside `~/Library/Containers/com.sequel-ace.sequel-ace/Data/` (for example, `.../Data/mysql.sock`).
2. Switch to a standard TCP/IP connection (`127.0.0.1`) and enable networking in `my.cnf` if needed.

Important: a symlink from `/tmp/mysql.sock` to the Sequel Ace path does not fix Sequel Ace by itself. The socket's core location must be in Sequel Ace's container.

For full step-by-step instructions (including Homebrew/MacPorts/Oracle package context and multi-version port setup), see [Connect to a Local MySQL Server](local-connection.html#connecting-via-a-socket-connection).

**I'm having trouble connecting to a MySQL 4 or MySQL 5 database on localhost with a MAMP install.**

See [Connecting to MAMP or XAMPP](mamp-xampp.html "Connecting to MAMP or XAMPP").

**My SSH connection gives the error: SSH port forwarding failed and MySQL said: Lost connection to MySQL server at 'reading initial communication packet', system error: 0**

On the server, configure MySQL by editing /etc/my.cnf and comment or remove `skip-networking` from the `[mysqld]` section. Then, restart MySQL Server.

**How do I connect to AWS RDS/Aurora with IAM authentication and tunnels (including SSM)?**

See [What type of connection do I have?](connection-types.html#aws-iam-authentication) for the full AWS IAM setup, sandbox permission details, and external tunnel options (SSH/SSM/custom port forwarding).

**Sequel Ace doesn't read my `~/.ssh/config` parameters.**

Sequel Ace runs in a sandboxed mode and by default cannot access your SSH config file. If you'd like to use a custom SSH config file, open Sequel Ace's preferences (from the menu bar), go to the "Network" settings tab, and select the SSH config file you would like to use. The same config file will be used for all connections. If your config file references other files in the filesystem, Sequel Ace will not be able to access these other files by default due to security constraints - to allow access to these files, please go to the "Files" tab in Sequel Ace's Preferences and grant access to these other support files.

If SSH works in Terminal but fails in Sequel Ace with errors like `ssh_get_authentication_socket: Operation not permitted`, `load pubkey ...: Operation not permitted`, or ProxyCommand helper failures, see [Connect to a Remote MySQL Server](remote-connection.html#ssh-agent-and-proxycommand-limitations-on-macos) for supported workarounds (including external tunnel setup).


#### General Notes

-   If you enter a database, it will be selected when the connection to the server is established. Otherwise you can select one of the databases on the server afterwards.
-   If you enter no port on a standard/SSH/AWS IAM connection, Sequel Ace uses the default port for MySQL, port 3306.
-   If you enter no **SSH port** on a SSH connection, Sequel Ace uses the default port for SSH, port 22.
-   Click "'Add to Favorites"' to save the connection for use next time you open Sequel Ace. Passwords are stored in the Keychain. To re-order favourites click the pencil in the bottom left of the connection window, (or choose Preferences > Favorites from the Sequel Ace menu) then drag the favourites in the list.
-   You can connect to multiple databases simultaneously by opening a new window (File > New) or ⌘ + N


#### Articles

-   [What type of connection do I have?](connection-types.html)
-   [Connect to a Local MySQL Server](local-connection.html)
-   [Connect to a Remote MySQL Server](remote-connection.html)
-   [Open a Connection via URL (`mysql://`)](connect-via-url.html)
-   [Connecting to MAMP or XAMPP](mamp-xampp.html)
-   [Migrating from Sequel Pro](migrating-from-sequel-pro.html)
