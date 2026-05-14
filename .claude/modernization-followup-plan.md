# Sequel Ace Modernization — Follow-up Plan

## What's been done (decoupling branch)

32 commits, 28 files changed, +2630/-959 lines. PR: Sequel-Ace/Sequel-Ace#2375

Key deliverables:

- **Connection screen decoupled from document** — SPConnectionController depends on `SADatabaseDocumentProviding` protocol, not concrete SPDatabaseDocument
- **Connection logic extracted to Swift** — `SAConnectionService` handles TCP/IP, socket, SSH tunnel, AWS IAM connections (with SSH fallback retry, cancel support, cipher stripping). SPConnectionController uses it instead of inline ObjC.
- **Favorites sidebar extracted to Swift** — `SAFavoritesListDataSource` replaces 393 lines of ObjC outline view code
- **Standalone connection window** — `SAConnectionWindowController`, connection screen independent of document lifecycle (menu item deferred until it replaces the embedded flow)
- **Data-driven toolbar** — `SAViewMode` enum replaces repetitive toolbar item configuration
- **Protocols** — `SADatabaseDocumentProviding`, `SAConnectionDelegate`, `SAFavoritesProviding`, `SATaskManaging`, `SAFavoritesListDelegate`
- **SPConnectionController.m**: 4,375 → 3,755 lines (−14%)
- **18 unit tests** for SAConnectionInfoObjC
- **Bug fixes found during review**: Enter key crash (outline view sent action to delegate instead of target), `setIsProcessing:` infinite recursion, SSH tunnel idle state hang, tunnel port leak on MySQL failure, AWS IAM missing forced SSL

## Current codebase pain points

| File | Lines | Problem |
|------|-------|---------|
| SPDatabaseDocument.m | 6,592 | God object: connection, views, tasks, toolbar, database mgmt, state |
| SPTableContent.m | 5,027 | Table data display + editing, massive |
| SPExportController.m | 3,952 | Export logic tightly coupled to UI |
| SPCustomQuery.m | 3,870 | Query editor + result handling |
| SPTextView.m | 3,865 | SQL text view with autocompletion |
| SPConnectionController.m | 3,755 | Still large but much better |

## Follow-up work (prioritized)

### Phase A: SPDatabaseDocument decomposition (highest impact)

SPDatabaseDocument.m at 6,592 lines is the biggest bottleneck. Break it apart:

**A1. Extract database list management (~283 lines)**
- `setDatabases`, `chooseDatabase:`, `selectDatabase:item:`, `_selectDatabaseAndItem:`
- Create `SADatabaseListManager` in Swift
- Owns the database popup, database switching, history integration
- Files: `Source/Controllers/MainViewControllers/SPDatabaseDocument.m`, new `SADatabaseListManager.swift`

**A2. Extract task/progress management (~257 lines)**
- `startTaskWithDescription:`, `endTask`, `setTaskPercentage:`, `enableTaskCancellation:`, progress window fade, cancel button
- Already has `SATaskManaging` protocol — create `SATaskController` that implements it
- Move the progress window, indicators, and timer management out of the document
- Files: `SPDatabaseDocument.m`, new `SATaskController.swift`

**A3. Extract view state switching to use SAViewMode (~188 lines)**
- `viewStructure`, `viewContent`, `viewQuery`, `viewStatus`, `viewRelations`, `viewTriggers`
- Replace 6 repetitive methods with a single `switchToView(_ mode: SAViewMode)` that uses the enum
- `SAViewMode` already exists — just wire it into the document
- Files: `SPDatabaseDocument.m`, `SPDatabaseDocument+ViewMode.swift`

**A4. Extract window title management (~57 lines)**
- `updateWindowTitle:`, `displayName`
- Move to SPWindowController (where it logically belongs)
- Files: `SPDatabaseDocument.m`, `SPWindowController.swift`

### Phase B: Test coverage (foundation for safe refactoring)

**B1. Integration test for connection flow**
- Test that SAConnectionService can create a connection when given valid params
- Requires a test MySQL instance (Docker or local) — make it opt-in via env var
- Test TCP/IP, socket, SSL, database selection, timezone

**B2. Tests for SAFavoritesListDataSource**
- Mock SPTreeNode tree, verify outline view data source methods return correct values
- Test drag & drop acceptance/rejection logic
- Test Quick Connect item injection

**B3. Tests for SAViewMode**
- Round-trip preferences values
- Toolbar item factory produces correct identifiers/images
- All cases covered

### Phase C: SwiftUI migration starts

**C1. SwiftUI FavoritesListView**
- Wrap the existing `SAFavoritesListDataSource` in an `NSViewRepresentable` first
- Then iterate toward a pure SwiftUI `List` with `OutlineGroup`
- This is the first visible SwiftUI in the app
- Files: new `SAFavoritesListView.swift`

**C2. SwiftUI ConnectionFormView**
- The 55 IBOutlets in ConnectionView.xib are the target
- Start with a SwiftUI form for TCP/IP connection type only
- Bind to SAConnectionInfoObjC
- Files: new `SAConnectionFormView.swift`

**C3. Wire SwiftUI into SAConnectionWindowController + expose in menu**
- The standalone connection window is the ideal host for SwiftUI views
- Replace the embedded SPConnectionController with SwiftUI favorites list + connection form
- Use `SAConnectionService` directly for connection establishment
- Re-enable the "New Connection Window" menu item (currently deferred to avoid duplicate with XIB item)
- Eventually the XIB menu item (`newWindow:`) gets replaced by the standalone window flow

### Phase D: SPConnectionController further cleanup

**D1. Replace `updateFavoriteSelection:` with structured data flow**
- This 170+ line method reads the selected favorite and populates 50+ form fields
- Replace with: `SAConnectionInfoObjC` ↔ form field binding
- When a favorite is selected, create `SAConnectionInfoObjC` from the favorite dict, then populate fields from the info object

**D2. Extract favorites management actions**
- `addFavorite:`, `removeFavorite:`, `duplicateFavorite:`, `addGroup:`, `sortFavorites:`, `importFavorites:`, `exportFavorites:`
- Move to `SAFavoritesManager` that wraps `SAFavoritesProviding`

**D3. Extract form validation**
- File existence checks for SSH keys, SSL certificates
- Connection detail validation before connecting
- Move to `SAConnectionValidator`

### Phase E: SPTableContent / SPCustomQuery (long-term)

These are the next biggest files after SPDatabaseDocument. Lower priority but eventual targets:

- Extract table data loading into a service
- Extract query execution into a service
- Create protocols for table data source/delegate

## Recommended order

1. **Phase A3** (wire SAViewMode into view switching) — quick win, already has the enum
2. **Phase B3** (SAViewMode tests) — validate before and after
3. **Phase A1** (database list manager) — high value, moderate effort
4. **Phase A4** (window title) — quick, easy
5. **Phase B2** (favorites data source tests) — safety net
6. **Phase C1** (SwiftUI favorites list) — first visible SwiftUI
7. **Phase A2** (task controller) — large but impactful
8. **Phase D1-D3** (SPConnectionController cleanup) — ongoing
9. **Phase C2-C3** (SwiftUI connection form) — bigger effort
10. **Phase E** (table content/custom query) — long-term
