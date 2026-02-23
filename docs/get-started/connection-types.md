-   [Getting Connected](../get-started/)
-   [Making Queries](../queries.html)
-   [Keyboard Shortcuts](../shortcuts.html)
-   [Reference](../ref/)
-   [Bundles](../bundles/)
-   [Contribute](../contribute/)

<hr>

### What type of connection do I have?

When you open Sequel Ace, the first screen that you will see is the database connection window. If you don't have access to a MySQL server, perhaps you could try installing [MySQL](https://dev.mysql.com/doc/mysql-osx-excerpt/en/osx-installation.html "MySQL:Installing on MacOS") or [MariaDB](https://mariadb.com/kb/en/installing-mariadb-on-macos-using-homebrew "MariaDB:Installing on MacOS") on your Mac.

If you want to launch Sequel Ace programmatically, see [Open a Connection via URL (`mysql://`)](connect-via-url.html).


#### Local Connections

A MySQL Server running on the same computer as Sequel Ace is called _local_. You can connect to a local MySQL server in two ways:

-   using a **Standard** connection
-   using a **Socket** connection

Which type you prefer is up to you. See below for a description of the two methods.

For more details, see [Connecting to a local MySQL Server](local-connection.html "Connecting to a local MySQL Server").

If you installed MySQL with MAMP or XAMPP, see [Connecting to MAMP or XAMPP](mamp-xampp.html "Connecting to MAMP or XAMPP").


#### Remote Connections

If the MySQL server is on a different computer as Sequel Ace, it's called a _remote_ server. You can connect to remote servers:

-   using a **Standard** connection
-   using a **SSH** connection

You can use a standard connection if the MySQL server is directly reachable -- e.g. if it is on your local network. If you cannot directly reach your server (e.g. it's behind a firewall), you will have to use a SSH connection. For more details see [Connecting to a MySQL Server on a Remote Host](remote-connection.html "Connecting to a MySQL Server on a Remote Host").

Sequel Ace supports **SSL/TLS encryption** for MySQL connections. For remote servers, prefer SSL/TLS (or use an SSH tunnel) instead of plain TCP whenever possible.


#### Standard Connection

A standard connection is an **unencrypted** connection using TCP/IP. Such a connection is usually made over the network or over the internet to a remote server. To specify which server to connect to, you must provide its IP address or DNS resolvable name:

**# IP Address**
192.168.0.11
66.78.91.2

**# DNS resolvable name**
Crema.X-Serve.local
intranet.mycompany.com
mysql.webhosting.com

If you use the special address 127.0.0.1, you can connect to a server on your own computer.

> **Note:** Some web hosting companies may give you access to MySQL running on the server that is hosting your website (often by adding your IP address to a whitelist). In this case your web host will provide you with an IP address or a domain name on a server located on the internet that has a port open for you to connect to. If this is unavailable to you, you may need to connect to MySQL via an SSH Tunnel.

Required Fields

Host

Enter the hostname or IP address of the host.

Username

The default username for a MySQL install is **root**.

Optional Fields

Name

The name you want to give the favorite.

Password

The default password for a MySQL install is an empty string.
If that's the case, you should change the root password right away.

Database

If you enter a database, it will be selected when the connection to the server is established.
Otherwise you can select one of the databases on the server afterwards.

Port

Defaults to port 3306.


#### Socket Connection

A **Socket connection** is a connection to a copy of MySQL running on your local machine. If you are connecting to MySQL that you have installed from a package installer or source, then you won't normally need to enter anything into the socket field.

On macOS, Sequel Ace may be blocked from accessing socket files outside its sandbox container (and Full Disk Access does not bypass this restriction). The socket file must be created inside Sequel Ace's container path, and a `/tmp` symlink alone is not enough for Sequel Ace. If you hit socket connection errors, see [Connect to a Local MySQL Server](local-connection.html#connecting-via-a-socket-connection) for the supported workarounds.

Required Fields

Username

The default username for a MySQL install is **root**.

Password

The default password for a MySQL install is an empty string.
If that's the case, you should change the root password right away.

Optional Fields

Name

The name you want to give the favorite.

Database

If you enter a database, it will be selected when the connection to the server is established.
Otherwise you can select one of the databases on the server afterwards.

Socket

For non-standard MySQL installs (e.g - MAMP) manually set the path. Read more about connecting via sockets to [MAMP, XAMPP and other MySQL server setups](mamp-xampp.html).


#### AWS IAM Authentication

If you're connecting to an **Amazon RDS** or **Aurora** MySQL database, you can use **AWS IAM Authentication** instead of a password. This uses your AWS credentials to generate a short-lived authentication token, providing enhanced security and easier credential management.

##### Prerequisites

1. Your RDS/Aurora instance must have IAM authentication enabled
2. You need an IAM user or role with the `rds-db:connect` permission
3. AWS credentials configured in `~/.aws/credentials` and/or `~/.aws/config` (usually via AWS CLI)
4. If your profile uses role assumption or MFA, make sure that flow already works in your local AWS CLI setup

##### Setup

1. Select **Standard** connection type
2. Enter your RDS endpoint as the **Host** (e.g., `mydb.123456789012.us-east-1.rds.amazonaws.com`)
3. Enter your database **Username** (must match the IAM user configured in your database)
4. Check **Use AWS IAM Authentication**
5. Click **Authorize Access to ~/.aws...** to grant Sequel Ace access to your AWS credentials folder
6. Select your **AWS Profile** (e.g., `default`) from the dropdown
7. Enter or select the **Region** (e.g., `us-east-1`), or leave empty to auto-detect from the hostname
8. Connect as normal; Sequel Ace generates and uses an IAM token in place of the password

##### How It Works

When you connect, Sequel Ace:
1. Reads your AWS credentials from the selected profile
2. Resolves role-assumption/MFA profiles when needed
3. Generates a temporary authentication token (valid for 15 minutes)
4. Uses this token instead of a password to connect to your database

The token is automatically refreshed as needed during your session.

##### AWS Credentials File

Your AWS profile files can look like this:

```ini
# ~/.aws/credentials
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

[production]
aws_access_key_id = AKIAI44QH8DHBEXAMPLE
aws_secret_access_key = je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY
```

```ini
# ~/.aws/config
[profile app-with-role]
role_arn = arn:aws:iam::123456789012:role/DatabaseRole
source_profile = default
mfa_serial = arn:aws:iam::123456789012:mfa/your-user
region = us-east-1
```

##### Sandbox Access

Sequel Ace is a sandboxed application and requires your permission to read the AWS credentials folder. When you first enable AWS IAM Authentication, click the **Authorize Access to ~/.aws...** button and select your `.aws` folder (usually located at `~/.aws` in your home directory). This permission is remembered for future sessions.

> **Note:** AWS IAM Authentication uses SSL/TLS encryption automatically. The SSL checkbox is disabled when IAM authentication is enabled since encryption is always used.

##### Network Paths and Tunnels (SSH, SSM, and Custom Setups)

Sequel Ace handles IAM token generation, but it does not create AWS SSM sessions or custom VPN/port-forward workflows for you. If your database is not directly reachable from your Mac, you can always open your own tunnel outside Sequel Ace and then connect through `127.0.0.1:<local-port>`.

Common approaches:

- SSH local port forward (through a bastion host)
- AWS Systems Manager Session Manager port forwarding
- Any other local port-forward workflow used in your environment

For example, AWS SSM supports forwarding a local port to a remote database host. See AWS documentation and announcement: [New Port Forwarding Using AWS System Manager Session Manager](https://aws.amazon.com/blogs/aws/new-port-forwarding-using-aws-system-manager-sessions-manager/).

Example SSM port forward command:

```bash
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["mydb.123456789012.us-east-1.rds.amazonaws.com"],"portNumber":["3306"],"localPortNumber":["13306"]}'
```

With the tunnel/session running, connect Sequel Ace to:

- Host: `127.0.0.1`
- Port: `13306` (or your chosen local port)
- Username: your DB/IAM-enabled username
- AWS IAM Authentication: enabled (if your DB auth model expects IAM tokens)

This pattern is often the most reliable option for bespoke enterprise networking, private subnets, and zero-trust environments.
