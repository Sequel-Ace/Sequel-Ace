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

Unfortunately, due to sandboxing nature, Sequel Ace is not allowed to connect to the sockets which are out of the Sandbox. As a workaround, you can create a socket in `~/Library/Containers/com.sequel-ace.sequel-ace/Data` and connect to it. This can be done by putting these lines to your MySQL configuration file (usually, `my.cnf`). First, make a note of the file already specified in this file, typically, `/tmp/mysql.sock`.
 ```
 [mysqld]
 socket=/Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data/mysql.sock
 ```
To allow other database applications to continue working, make a symbolic link from the new socket file to the one previously used, like this:
```
# ln -s /Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data/mysql.sock /tmp/mysql.sock
```

If you are still having trouble using the new socket connection, it may be a permission problem, which you can check and correct:
```
# ls -la /Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data/
drwx------  14 jan     staff    448 14 Jun 09:41 .
drwx------@  4 jan     staff    128 13 Jun 11:23 ..
lrwxr-xr-x   1 jan     staff     31 13 Jun 11:23 .CFUserTextEncoding -> ../../../../.CFUserTextEncoding
drwxr-xr-x@  2 jan     staff     64 13 Jun 11:23 .keys
lrwxr-xr-x   1 jan     staff     19 13 Jun 11:23 Desktop -> ../../../../Desktop
drwx------   2 jan     staff     64 13 Jun 11:23 Documents
lrwxr-xr-x   1 jan     staff     21 13 Jun 11:23 Downloads -> ../../../../Downloads
drwx------  32 jan     staff   1024 13 Jun 11:23 Library
lrwxr-xr-x   1 jan     staff     18 13 Jun 11:23 Movies -> ../../../../Movies
lrwxr-xr-x   1 jan     staff     17 13 Jun 11:23 Music -> ../../../../Music
lrwxr-xr-x   1 jan     staff     20 13 Jun 11:23 Pictures -> ../../../../Pictures
drwx------   2 jan     staff     64 13 Jun 11:23 SystemData
srwxrwxrwx   1 _mysql  _mysql     0 14 Jun 09:41 mysql.sock
drwx------   2 jan     staff     64 13 Jun 22:26 tmp
```
Note that neither the target directory nor its containing directory allow any access to user `_mysql`

You can change the group to `_mysql` and set group permissions accordingly:
```
# for d in \
  /Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/Data/ \
  /Users/YourUserName/Library/Containers/com.sequel-ace.sequel-ace/ \
  /Users/YourUserName/Library/Containers/ \
  /Users/YourUserName/Library/Containers/ \
  /Users/YourUserName/
do
  chgrp $d _mysql
  chmod g+rwx $d
done
```

**I'm having trouble connecting to a MySQL 4 or MySQL 5 database on localhost with a MAMP install.**

See [Connecting to MAMP or XAMPP](mamp-xampp.html "Connecting to MAMP or XAMPP").

**My SSH connection gives the error: SSH port forwarding failed and MySQL said: Lost connection to MySQL server at 'reading initial communication packet', system error: 0**

On the server, configure MySQL by editing /etc/my.cnf and comment or remove `skip-networking` from the `[mysqld]` section. Then, restart MySQL Server.

**Sequel Ace doesn't read my `~/.ssh/config` parameters.**

Sequel Ace runs in a sandboxed mode and by default cannot access your SSH config file. If you'd like to use a custom SSH config file, open Sequel Ace's preferences (from the menu bar), go to the "Network" settings tab, and select the SSH config file you would like to use. The same config file will be used for all connections. If your config file references other files in the filesystem, Sequel Ace will not be able to access these other files by default due to security constraints - to allow access to these files, please go to the "Files" tab in Sequel Ace's Preferences and grant access to these other support files.


#### General Notes

-   If you enter a database, it will be selected when the connection to the server is established. Otherwise you can select one of the databases on the server afterwards.
-   If you enter no port on a standard/SSH connection, Sequel Ace uses the default port for MySQL, port 3306.
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
