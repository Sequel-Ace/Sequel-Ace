- [Getting Connected](../get-started/)
- [Making Queries](../queries.html)
- [Keyboard Shortcuts](../shortcuts.html)
- [Reference](../ref/)
- [Bundles](../bundles/)
- [Contribute](../contribute/)

<hr>

### Connecting to MAMP or XAMPP

This page describes how to connect to the MySQL Server of [MAMP](http://www.mamp.info/) or [XAMPP](http://www.apachefriends.org/en/xampp-macosx.html) running on the same computer as Sequel Ace. If you want to connect to MAMP/XAMPP running on a different computer, please see [Connecting to a MySQL Server on a Remote Host](remote-connection.html "Connecting to a MySQL Server on a Remote Host").

#### MAMP

##### CONNECT TO MAMP VIA A UNIX SOCKET

This is the recommended way of connecting to [MAMP](http://www.mamp.info/ "http://www.mamp.info").

In the Sequel Ace connection dialog, choose a socket connection.

Usually, socket path will be checked automatically if the field is left empty. Try to use full socket path in case of troubles: `/Applications/MAMP/tmp/mysql/mysql.sock`

Type root into the username field. The default password is also root. Optionally enter a name for the connection.

Make sure that MAMP is running and click connect.

##### Connect to MAMP via a standard TCP/IP connection

You can also connect via a TCP/IP connection.

Enter 127.0.0.1 for the Host. Enter root for the username and for the password. The default MySQL port used by MAMP is 8889.

**Important**: Regardless of the connection method, a preference needs changing in the MAMP Pro settings. Under Server & Services -> MySQL, check `Allow network access to MySQL` and select `only from this Mac`.

#### XAMPP

Just like with MAMP, you can also connect to [XAMPP](http://www.apachefriends.org/en/xampp-macosx.html "http://www.apachefriends.org/en/xampp-macosx.html") via a socket connection or a standard connection. Only the default settings are a little bit different:

##### Connect to XAMPP via a unix socket

Usually, socket path will be checked automatically if the field is left empty. Try to use full socket path in case of troubles: `/Applications/XAMPP/xamppfiles/var/mysql/mysql.sock`

Use root as username, and leave the password field blank.

##### Connect to XAMPP via a standard TCP/IP connection

Type 127.0.0.1 into the host field. Since XAMPP uses the standard MySQL port 3306, you can leave the port field blank. The user name is root, the default password is blank.
