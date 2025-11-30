# Sequel PAce

**Sequel PAce** is a PostgreSQL-focused fork of [Sequel Ace](https://github.com/Sequel-Ace/Sequel-Ace), which itself is a fork of the beloved [Sequel Pro](https://github.com/sequelpro/sequelpro).

## Motivation

I have always loved the UI and UX of Sequel Pro (and subsequently Sequel Ace). However, my primary database needs have shifted to **PostgreSQL**, and I wanted to bring that same delightful user experience to the Postgres world.

This project, **Sequel PAce**, is the result of that desire. It replaces the MySQL backend with a PostgreSQL driver (libpq) while preserving the native macOS interface that makes Sequel Pro/Ace so great.

## Features

- **PostgreSQL Support**: Native connection to PostgreSQL databases.
- **Classic UI**: The familiar Sequel Pro/Ace interface.
- **Table Management**: View, edit, and manage tables and views.
- **Query Editor**: Execute custom SQL queries.
- **Data Export/Import**: Support for CSV, SQL, and XML exports.

## Credits

- **Original Project**: [Sequel Pro](https://github.com/sequelpro/sequelpro)
- **Parent Project**: [Sequel Ace](https://github.com/Sequel-Ace/Sequel-Ace)
- **Sequel PAce Developer**: Mehmet Karabulut <mehmetik@gmail.com>

## License

Sequel PAce is released under the **GPL License**, same as the projects it is derived from.
This is a free and open-source project.


## 🚀 How to Run (macOS)

### Prerequisites

#### 1. PostgreSQL Library (libpq) Installation
PostgreSQL client library is required. You can install it via Homebrew:

```bash
# Install PostgreSQL (includes libpq)
brew install postgresql@15

# Verify libpq installation
which pg_config
# Output: /opt/homebrew/opt/postgresql@15/bin/pg_config (Apple Silicon)
# or: /usr/local/opt/postgresql@15/bin/pg_config (Intel Mac)
```

#### 2. Xcode and Command Line Tools
- **Xcode 15+** must be installed
- Command Line Tools must be installed:
```bash
xcode-select --install
```

### Step-by-Step Setup

#### 1. Clone the Repository
```bash
git clone https://github.com/mehmetik/Sequel-PAce.git
cd Sequel-PAce
```

#### 2. Open in Xcode
```bash
open sequel-pace.xcodeproj
```

#### 3. Configure Build Settings

After opening the project in Xcode:

1. Select **sequel-pace** project from the left panel
2. Select **Sequel PAce** target under **TARGETS**
3. Click on **Build Settings** tab
4. Search for **"header search"**
5. Add to **Header Search Paths**:
   ```
   /opt/homebrew/opt/postgresql@15/include  (for Apple Silicon)
   /usr/local/opt/postgresql@15/include      (for Intel Mac)
   ```
   - Add below `$(inherited)`
   - Check **Recursive** checkbox

6. Search for **"library search"**
7. Add to **Library Search Paths**:
   ```
   /opt/homebrew/opt/postgresql@15/lib  (for Apple Silicon)
   /usr/local/opt/postgresql@15/lib      (for Intel Mac)
   ```

8. Search for **"other linker"**
9. Add to **Other Linker Flags**:
   ```
   -lpq
   ```

#### 4. Select Scheme
- Üst bar'dan scheme seçiciden **"Sequel Ace"** veya **"Sequel PAce Debug"** seçin
- Choose **"My Mac"** as destination

#### 5. Build and Run
```
⌘ + B  → Build
⌘ + R  → Run
```

### First Launch

When the application opens:

1. **Create PostgreSQL Connection**
   - Host: `localhost` (or remote server IP)
   - Port: `5432` (default PostgreSQL port)
   - User: Your PostgreSQL username
   - Password: Your password
   - Database: `postgres` (default) or another database

2. **Test Connection**
   - Click "Test Connection" button
   - On success, you'll see ✅ "Connection succeeded" message

3. **SSH Tunnel (Optional)**
   - SSH tunnel support is available for remote servers
   - Select "SSH" as Connection Type
   - Enter SSH host, user, and key information

### Troubleshooting

#### Build Error: "libpq-fe.h not found"
```bash
# Verify PostgreSQL is installed correctly
brew list postgresql@15

# Add header path manually (see step 3 above)
```

#### Build Error: "library not found for -lpq"
```bash
# Add library search path
# Xcode Build Settings → Library Search Paths
/opt/homebrew/opt/postgresql@15/lib  # Apple Silicon
# or
/usr/local/opt/postgresql@15/lib      # Intel Mac
```

#### Runtime Error: "Cannot connect to PostgreSQL"
```bash
# Ensure PostgreSQL is running
brew services start postgresql@15

# Test connection
psql -h localhost -U your_username -d postgres
```

#### PostGIS Geometry Support
```sql
-- Enable PostGIS extension in PostgreSQL
CREATE EXTENSION IF NOT EXISTS postgis;

-- Test geometry functions
SELECT ST_GeomFromText('POINT(1 2)');
```

### Development Notes

- **Debug Build**: Use `Sequel PAce Debug` scheme for development
- **Release Build**: Use `Sequel PAce Release` scheme for production
- **Unit Tests**: Run tests with `⌘ + U`

---
*Developed with ❤️ by Mehmet Karabulut.*
