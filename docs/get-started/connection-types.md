-   [Getting Connected](../get-started/)
-   [Making Queries](../queries.html)
-   [Keyboard Shortcuts](../shortcuts.html)
-   [Reference](../ref/)
-   [Bundles](../bundles/)
-   [Contribute](../contribute/)

<hr>

### What type of connection do I have?

When you open Sequel Ace, the first screen that you will see is the database connection window. If you don't have access to a PostgreSQL server, perhaps you could try installing [PostgreSQL](https://dev.postgres.com/doc/postgres-osx-excerpt/en/osx-installation.html "PostgreSQL:Installing on MacOS") or [MariaDB](https://mariadb.com/kb/en/installing-mariadb-on-macos-using-homebrew "MariaDB:Installing on MacOS") on your Mac.


#### Local Connections

A PostgreSQL Server running on the same computer as Sequel Ace is called _local_. You can connect to a local PostgreSQL server in two ways:

-   using a **Standard** connection
-   using a **Socket** connection

Which type you prefer is up to you. See below for a description of the two methods.

For more details, see [Connecting to a local PostgreSQL Server](local-connection.html "Connecting to a local PostgreSQL Server").

If you installed PostgreSQL with MAMP or XAMPP, see [Connecting to MAMP or XAMPP](mamp-xampp.html "Connecting to MAMP or XAMPP").


#### Remote Connections

If the PostgreSQL server is on a different computer as Sequel Ace, it's called a _remote_ server. You can connect to remote servers:

-   using a **Standard** connection
-   using a **SSH** connection

You can use a standard connection if the PostgreSQL server is directly reachable -- e.g. if it is on your local network. If you cannot directly reach your server (e.g. it's behind a firewall), you will have to use a SSH connection. For more details see [Connecting to a PostgreSQL Server on a Remote Host](remote-connection.html "Connecting to a PostgreSQL Server on a Remote Host").

At the moment, **Sequel Ace does not support SSL** encryption. If possible, use a SSH connection instead.


#### Standard Connection

A standard connection is an **unencrypted** connection using TCP/IP. Such a connection is usually made over the network or over the internet to a remote server. To specify which server to connect to, you must provide its IP address or DNS resolvable name:

**# IP Address**
192.168.0.11
66.78.91.2

**# DNS resolvable name**
Crema.X-Serve.local
intranet.mycompany.com
postgres.webhosting.com

If you use the special address 127.0.0.1, you can connect to a server on your own computer.

> **Note:** Some web hosting companies may give you access to PostgreSQL running on the server that is hosting your website (often by adding your IP address to a whitelist). In this case your web host will provide you with an IP address or a domain name on a server located on the internet that has a port open for you to connect to. If this is unavailable to you, you may need to connect to PostgreSQL via an SSH Tunnel.

Required Fields

Host

Enter the hostname or IP address of the host.

Username

The default username for a PostgreSQL install is **root**.

Optional Fields

Name

The name you want to give the favorite.

Password

The default password for a PostgreSQL install is an empty string.
If that's the case, you should change the root password right away.

Database

If you enter a database, it will be selected when the connection to the server is established.
Otherwise you can select one of the databases on the server afterwards.

Port

Defaults to port 5432.


#### Socket Connection

A **Socket connection** is a connection to a copy of PostgreSQL running on your local machine. If you are connecting to PostgreSQL that you have installed from a package installer or source, then you won't normally need to enter anything into the socket field.

Required Fields

Username

The default username for a PostgreSQL install is **root**.

Password

The default password for a PostgreSQL install is an empty string.
If that's the case, you should change the root password right away.

Optional Fields

Name

The name you want to give the favorite.

Database

If you enter a database, it will be selected when the connection to the server is established.
Otherwise you can select one of the databases on the server afterwards.

Socket

For non-standard PostgreSQL installs (e.g - MAMP) manually set the path. Read more about connecting via sockets to [MAMP, XAMPP and other PostgreSQL server setups](mamp-xampp.html).
