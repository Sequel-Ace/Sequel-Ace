-   [Getting Connected](../get-started/)
-   [Making Queries](../queries.html)
-   [Keyboard Shortcuts](../shortcuts.html)
-   [Reference](../ref/)
-   [Bundles](../bundles/)
-   [Contribute](../contribute/)

<hr>

### Connect to a Local MySQL Server

This document describes how to connect to a server running on the same computer as Sequel Ace.


#### Making sure your MySQL server is running

If you are not sure if the MySQL server is running, open _Activity Viewer_ (from _Applications_ » _Utilities_). Choose _All Processes_ in the popup menu. Type mysqld into the search field. If you see a mysqld process, MySQL is running.


#### Connecting via a socket connection

On macOS, Sequel Ace is sandboxed. It can only use a socket if the database server creates the socket file inside Sequel Ace's container path.

Important notes:

- Full Disk Access does **not** bypass this sandbox restriction.
- The socket's real path must be inside Sequel Ace's container.
- A symlink-based workaround by itself is not enough. In particular, a symlink from `/tmp/mysql.sock` to a Sequel Ace path does not fix Sequel Ace unless the server itself is configured to create the socket in Sequel Ace's container.

There are two supported approaches:

##### Option 1: Keep using a socket (set socket path inside Sequel Ace)

1. Find which config file your server actually reads.

Use whichever server binary you have:
```bash
mysqld --verbose --help | sed -n '/Default options are read from the following files in the given order:/,/^$/p'
mariadbd --verbose --help | sed -n '/Default options are read from the following files in the given order:/,/^$/p'
```

You can also check the current socket setting:
```bash
my_print_defaults mysqld | tr ' ' '\n' | grep '^--socket='
my_print_defaults mariadbd | tr ' ' '\n' | grep '^--socket='
```

Common locations on macOS:
- Homebrew (Apple Silicon): `/opt/homebrew/etc/my.cnf`
- Homebrew (Intel): `/usr/local/etc/my.cnf`
- MacPorts: `/opt/local/etc/<variant>/my.cnf`
- Oracle MySQL packages: often `/etc/my.cnf` (or files included from there)
- MAMP / MAMP PRO / XAMPP: app-managed config files

2. Set the socket path to a Sequel Ace container location, for example:
```text
/Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data/mysql.sock
```

Add or update:
```ini
[mysqld]
socket=/Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data/mysql.sock

[client]
socket=/Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data/mysql.sock
```

3. Restart MySQL/MariaDB.

4. If startup fails with an error like `Could not create unix socket lock file`, verify permissions so the server process user can write in that directory:
```bash
ps -Ao user,comm | grep -E 'mariadbd|mysqld'
ls -ld /Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data
```

5. In Sequel Ace, use a **Socket** connection with the same socket path.

##### Option 2: Use standard TCP/IP instead of a socket

If socket setup is not practical on your install, enable local TCP networking:
```ini
[mysqld]
skip_networking=0
bind_address=127.0.0.1
```

Then restart MySQL/MariaDB and connect in Sequel Ace using a **Standard** connection with:

- Host: `127.0.0.1` (not `localhost`)
- Username/password: same credentials you used before
- Port: `3306` unless you configured another port

For MacPorts installs:

1. Find your active variant:
```bash
port select --show mysql    # MySQL
port select --show mariadb  # MariaDB
```
2. Edit that variant's config file:
```text
/opt/local/etc/{variant-version}/my.cnf
```
3. Restart it:
```bash
sudo port reload {variant-version}-server
```

If you run multiple versions at once, assign a different `port=<number>` to each version and use the same port in Sequel Ace.

References:
- [MySQL Option Files](https://dev.mysql.com/doc/refman/8.0/en/option-files.html)
- [MariaDB: Configuring MariaDB with Option Files](https://mariadb.com/docs/server/server-management/install-and-upgrade-mariadb/configuring-mariadb/configuring-mariadb-with-option-files)
- [MySQL: Can't connect to local MySQL server](https://dev.mysql.com/doc/refman/8.0/en/can-not-connect-to-server.html)


#### Connecting via a standard connection

Open Sequel Ace. Choose a _Standard_ Connection. Enter 127.0.0.1 for the host. The default username for a new MySQL installation is root, with a blank password. You can leave the port field blank unless your server uses a different port than 3306.

**Note**: MAMP uses port 8889 per default, and root as the password. See [Connecting to MAMP or XAMPP](mamp-xampp.html "Connecting to MAMP or XAMPP")

**Note**: Don't try using localhost instead of 127.0.0.1. MySQL treats the hostname localhost specially. For details, see [MySQL manual.](https://dev.mysql.com/doc/refman/en/connecting.html)
