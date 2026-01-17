# Project Index: Sequel PAce

Generated: 2026-01-17

## Overview

**Sequel PAce** is a PostgreSQL-focused native macOS database client, forked from Sequel Ace (which was forked from Sequel Pro). It replaces the MySQL backend with PostgreSQL (libpq) while preserving the familiar macOS-native UI.

- **Version**: 5.0.9 (Build 20095)
- **Platform**: macOS (Cocoa/AppKit)
- **Languages**: Objective-C (~85%), Swift (~15%)
- **Database**: PostgreSQL (via libpq)
- **License**: GPL

## Project Structure

```
Sequel-PAce/
├── Source/                     # Main application source code
│   ├── main.m                  # Application entry point
│   ├── Controllers/            # View controllers and logic
│   │   ├── SPAppController     # Main app delegate
│   │   ├── MainViewControllers/# Core database views
│   │   ├── DataExport/         # Export functionality
│   │   ├── DataImport/         # Import functionality
│   │   ├── Preferences/        # Preferences panels
│   │   ├── BundleSupport/      # Custom bundle/script support
│   │   ├── SubviewControllers/ # Helper view controllers
│   │   ├── Window/             # Window management
│   │   └── Other/              # Misc controllers
│   ├── Model/                  # Data models
│   │   ├── TreeNodes/          # Outline view nodes
│   │   └── CoreData/           # User management models
│   ├── Views/                  # Custom UI views
│   │   ├── TableViews/         # Table display views
│   │   ├── TextViews/          # SQL editor views
│   │   ├── OutlineViews/       # Tree views
│   │   ├── Cells/              # Custom cells
│   │   ├── Controls/           # Custom controls
│   │   └── AccessoryViews/     # Accessory panels
│   ├── Interfaces/             # XIB/NIB files (30 files)
│   ├── Other/                  # Utilities and helpers
│   │   ├── Parsing/            # SQL/CSV/JSON parsers
│   │   ├── CategoryAdditions/  # ObjC categories
│   │   ├── SSHTunnel/          # SSH tunnel support
│   │   ├── DatabaseActions/    # DB operations
│   │   ├── Keychain/           # Keychain access
│   │   ├── FileCompression/    # File handling
│   │   └── Utility/            # General utilities
│   └── ThirdParty/             # Vendored libraries
├── Frameworks/                 # Framework dependencies
│   ├── SPPostgresFramework/    # PostgreSQL driver (custom)
│   ├── PostgreSQL.framework/   # Embedded libpq
│   ├── QueryKit/               # SQL query builder
│   └── ShortcutRecorder.framework/
├── Resources/                  # Assets and configs
│   ├── Plists/                 # Property lists
│   ├── Images.xcassets/        # Image assets
│   ├── Colors.xcassets/        # Color assets
│   ├── Localization/           # i18n strings
│   └── Templates/              # Export templates
├── SharedSupport/              # Bundled resources
│   ├── Default Bundles/        # Built-in bundles (17 items)
│   └── Default Themes/         # Color themes (7 items)
├── UnitTests/                  # Test suite
├── Scripts/                    # Build scripts
├── docs/                       # Documentation
├── Guides/                     # Developer guides
└── sequel-pace.xcodeproj/      # Xcode project
```

## Entry Points

| Entry | Path | Purpose |
|-------|------|---------|
| App Entry | `Source/main.m` | NSApplicationMain entry |
| App Controller | `Source/Controllers/SPAppController.m` | Main app delegate |
| Document Controller | `Source/Controllers/Other/SPDocumentController.m` | Document handling |
| Main Window | `Source/Interfaces/MainWindow.xib` | Primary UI |
| Main Menu | `Source/Interfaces/MainMenu.xib` | Menu bar |

## Core Modules

### PostgreSQL Connection Layer
- **Path**: `Frameworks/SPPostgresFramework/Source/`
- **Files**: 16 (8 .h, 8 .m)
- **Key Classes**:
  - `SPPostgresConnection` - Main connection class (wraps libpq)
  - `SPPostgresResult` - Query results
  - `SPPostgresStreamingResult` - Large result streaming
  - `SPPostgresStreamingResultStore` - Memory-efficient result store
  - `SPPostgresGeometryData` - PostGIS support

### Main View Controllers
- **Path**: `Source/Controllers/MainViewControllers/`
- **Key Classes**:
  - `SPDatabaseDocument` - Main document controller
  - `SPConnectionController` - Connection management
  - `SPCustomQuery` - Query editor
  - `SPTableContent` - Table data viewing
  - `SPTableStructure` - Table schema editing
  - `SPExtendedTableInfo` - Table metadata
  - `SPTableRelations` - Foreign key management
  - `SPTableTriggers` - Trigger management

### Data Export/Import
- **Export Path**: `Source/Controllers/DataExport/`
- **Import Path**: `Source/Controllers/DataImport/`
- **Supported Formats**: SQL, CSV, XML, HTML, PDF, DOT (GraphViz)
- **Key Classes**:
  - `SPExportController` - Export coordination
  - `SPDataImport` - Import handling
  - `SPFieldMapperController` - Field mapping UI

### Views
- **Path**: `Source/Views/`
- **Files**: 61
- **Key Classes**:
  - `SPTextView` - SQL editor with syntax highlighting
  - `SPCopyTable` - Table view with copy support
  - `SPTableView` - Custom table view
  - `SPGeometryDataView` - PostGIS geometry visualization
  - `SPSplitView` - Split view container

### Parsing
- **Path**: `Source/Other/Parsing/`
- **Key Classes**:
  - `SPSQLParser` - SQL statement parser
  - `SPCSVParser` - CSV file parser
  - `SPJSONFormatter` - JSON formatting
  - `SPTableFilterParser` - Filter expression parser
  - `SPSyntaxParser` - Syntax highlighting

## Configuration Files

| File | Purpose |
|------|---------|
| `Resources/Plists/Info.plist` | App bundle configuration |
| `Resources/Plists/PreferenceDefaults.plist` | Default preferences |
| `Resources/Plists/ContentFilters.plist` | Content filter definitions |
| `Resources/Plists/CompletionTokens.plist` | Autocomplete tokens |
| `Entitlements/*.entitlements` | macOS entitlements |

## Build Scripts

| Script | Purpose |
|--------|---------|
| `Scripts/build.sh` | Main build script |
| `Scripts/embed_libpq.sh` | Embed libpq in app bundle |
| `Scripts/setup_libpq.sh` | Configure libpq paths |
| `Scripts/generate-changelog.sh` | Generate changelog |

## Test Coverage

- **Path**: `UnitTests/`
- **Test Files**: 21
- **Key Test Classes**:
  - `SPTableCopyTest` - Table copy operations
  - `SPDatabaseCopyTest` - Database copy operations
  - `SPStringAdditionsTests` - String extensions
  - `SPJSONFormatterTests` - JSON formatting
  - `SPTableFilterParserTest` - Filter parsing
  - `TableSortHelperTests` - Table sorting

## Key Dependencies

| Dependency | Purpose |
|------------|---------|
| libpq (PostgreSQL) | PostgreSQL client library |
| ShortcutRecorder | Keyboard shortcut recording |
| QueryKit | SQL query building |
| SnapKit | Auto Layout (Swift) |
| FMDB | SQLite (for local storage) |
| Alamofire | HTTP networking |
| PLCrashReporter | Crash reporting |
| AppCenter | Analytics |

## URL Schemes

- `sequelpace://` - Custom URL scheme
- `mysql://` - MySQL URL scheme (legacy compatibility)

## Document Types

| Extension | Type |
|-----------|------|
| `.spf` | Connection file |
| `.spfs` | Session file |
| `.saBundle` | Bundle/script package |
| `.spTheme` | Color theme |
| `.sql` | SQL file |

## Quick Start

```bash
# Prerequisites
brew install postgresql@15

# Clone and open
git clone https://github.com/mehmetik/Sequel-PAce.git
cd Sequel-PAce
open sequel-pace.xcodeproj

# Configure in Xcode:
# 1. Header Search Paths: /opt/homebrew/opt/postgresql@15/include
# 2. Library Search Paths: /opt/homebrew/opt/postgresql@15/lib
# 3. Other Linker Flags: -lpq

# Build and Run
# Cmd+R
```

## Source Statistics

| Category | Count |
|----------|-------|
| Source Files (.m/.h/.swift) | 383 |
| Interface Files (.xib) | 30 |
| Test Files | 21 |
| Default Bundles | 17 |
| Color Themes | 7 |

## Architecture Notes

1. **MVC Pattern**: Traditional Cocoa MVC with document-based architecture
2. **PostgreSQL Layer**: Custom `SPPostgresFramework` wrapping libpq
3. **Streaming Results**: Memory-efficient handling of large result sets
4. **SSH Tunneling**: Built-in SSH tunnel support via `SPSSHTunnel`
5. **Bundle System**: Extensible via `.saBundle` scripts
6. **Theming**: Customizable SQL editor themes

## Key File Locations for Common Tasks

| Task | Primary Files |
|------|---------------|
| Connection Logic | `Frameworks/SPPostgresFramework/Source/SPPostgresConnection.m` |
| Query Execution | `Source/Controllers/MainViewControllers/SPCustomQuery.h` |
| Table Data Display | `Source/Controllers/MainViewControllers/TableContent/SPTableContent.h` |
| SQL Syntax Highlighting | `Source/Views/TextViews/SPTextView.m` |
| Export Logic | `Source/Controllers/DataExport/SPExportController.h` |
| Preferences | `Source/Controllers/Preferences/SPPreferenceController.m` |
| Main Window Layout | `Source/Interfaces/MainWindow.xib` |
