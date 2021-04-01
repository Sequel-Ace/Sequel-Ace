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

Unfortunately, due to sandboxing nature, Sequel Ace is not allowed to connect to the sockets which are out of the sandbox. As a workaround, you can create a socket in `~/Library/Containers/com.sequel-ace.sequel-ace/Data` and connect to it. This can be done by putting these lines to your MySQL configuration file (usually, `my.cnf`):
```
[mysqld]
socket=/Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data/mysql.sock
```


#### Connecting via a standard connection

Open Sequel Ace. Choose a _Standard_ Connection. Enter 127.0.0.1 for the host. The default username for a new MySQL installation is root, with a blank password. You can leave the port field blank unless your server uses a different port than 3306.

**Note**: MAMP uses port 8889 per default, and root as the password. See [Connecting to MAMP or XAMPP](mamp-xampp.html "Connecting to MAMP or XAMPP")

**Note**: Don't try using localhost instead of 127.0.0.1. MySQL treats the hostname localhost specially. For details, see [MySQL manual.](https://dev.mysql.com/doc/refman/en/connecting.html)
