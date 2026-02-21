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

Apple's macOS sandboxing restrictions prevent Sequel Ace from accessing socket files outside the app container, even when Full Disk Access is enabled for Sequel Ace.

There are two common workarounds:

##### Option 1: Move the socket to a path Sequel Ace can access

Edit your MySQL configuration file (usually `my.cnf`, often `/usr/local/etc/my.cnf`) and set:
```
[mysqld]
socket=/Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data/mysql.sock
```

Then restart MySQL/MariaDB.

If other tools still expect the previous socket path (for example, `/tmp/mysql.sock`), create a symbolic link:
```
ln -s /Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data/mysql.sock /tmp/mysql.sock
```

##### Option 2: Use a standard TCP/IP connection instead of a socket connection

If your local server is configured socket-only, enable networking in your server config:
```
[mysqld]
skip_networking=0
bind_address=127.0.0.1
```

Then restart MySQL/MariaDB and connect in Sequel Ace using a **Standard** connection with:

- Host: `127.0.0.1` (not `localhost`)
- Username/password: same credentials you used before
- Port: `3306` unless you configured another port

For MacPorts installs:

1. Find your active MySQL/MariaDB variant:
```
port select --show mysql
```
2. Edit that variant's config file:
```
/opt/local/etc/{variant-version}/my.cnf
```
3. Restart it:
```
sudo port reload {variant-version}-server
```

If you run multiple versions at once, assign a different `port=<number>` to each version and use the same port in Sequel Ace.


#### Connecting via a standard connection

Open Sequel Ace. Choose a _Standard_ Connection. Enter 127.0.0.1 for the host. The default username for a new MySQL installation is root, with a blank password. You can leave the port field blank unless your server uses a different port than 3306.

**Note**: MAMP uses port 8889 per default, and root as the password. See [Connecting to MAMP or XAMPP](mamp-xampp.html "Connecting to MAMP or XAMPP")

**Note**: Don't try using localhost instead of 127.0.0.1. MySQL treats the hostname localhost specially. For details, see [MySQL manual.](https://dev.mysql.com/doc/refman/en/connecting.html)
