# PostgreSQL Framework for Sequel PAce

This framework provides libpq (PostgreSQL client library) embedded within the application bundle.

## Setup Instructions

### For Development (macOS with Homebrew)

1. Install libpq via Homebrew:
   ```bash
   brew install libpq
   ```

2. The build system will automatically find and link libpq from Homebrew.

### For Distribution (Embedded Framework)

To create a fully self-contained application bundle:

1. Build libpq for ARM64 (Apple Silicon):
   ```bash
   # Download PostgreSQL source
   curl -O https://ftp.postgresql.org/pub/source/v16.1/postgresql-16.1.tar.gz
   tar xzf postgresql-16.1.tar.gz
   cd postgresql-16.1

   # Configure for ARM64
   ./configure --prefix=/tmp/pg-arm64 \
               --without-readline \
               --without-zlib \
               --with-openssl

   # Build only libpq
   make -C src/interfaces/libpq
   make -C src/interfaces/libpq install
   ```

2. Copy the built library:
   ```bash
   cp /tmp/pg-arm64/lib/libpq.5.dylib \
      Frameworks/PostgreSQL.framework/Versions/A/PostgreSQL
   ```

3. Update install names:
   ```bash
   install_name_tool -id "@rpath/PostgreSQL.framework/Versions/A/PostgreSQL" \
      Frameworks/PostgreSQL.framework/Versions/A/PostgreSQL
   ```

### Using Pre-built Libraries

Alternatively, copy libpq from Homebrew:

```bash
# For Apple Silicon (ARM64)
cp /opt/homebrew/opt/libpq/lib/libpq.5.dylib \
   Frameworks/PostgreSQL.framework/Versions/A/PostgreSQL

# For Intel Macs
cp /usr/local/opt/libpq/lib/libpq.5.dylib \
   Frameworks/PostgreSQL.framework/Versions/A/PostgreSQL

# Update install name
install_name_tool -id "@rpath/PostgreSQL.framework/Versions/A/PostgreSQL" \
   Frameworks/PostgreSQL.framework/Versions/A/PostgreSQL
```

## Framework Structure

```
PostgreSQL.framework/
├── Headers/
│   ├── libpq-fe.h
│   └── postgres_ext.h
├── Resources/
│   └── Info.plist
├── Versions/
│   ├── A/
│   │   ├── PostgreSQL (libpq dylib)
│   │   ├── Headers/
│   │   └── Resources/
│   └── Current -> A
└── PostgreSQL -> Versions/Current/PostgreSQL
```

## Build Configuration

The Xcode project is configured with:

- **HEADER_SEARCH_PATHS**: `$(PROJECT_DIR)/Frameworks/PostgreSQL.framework/Headers`
- **LIBRARY_SEARCH_PATHS**: `$(PROJECT_DIR)/Frameworks/PostgreSQL.framework/Versions/A`
- **LD_RUNPATH_SEARCH_PATHS**: `@executable_path/../Frameworks`
- **OTHER_LDFLAGS**: `-lpq`

## Supported Architectures

- ARM64 (Apple Silicon M1/M2/M3)
- x86_64 (Intel) - for universal binaries

## Minimum macOS Version

- macOS 12.0 (Monterey) or later
