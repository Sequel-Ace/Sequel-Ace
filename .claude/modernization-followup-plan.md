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

**A1. Extract database list management (~283 lines)** — 🟡 In progress (A1a done)

A1a — `-setDatabases` (popup rebuild) — ✅ Done
- New `SADatabaseListManager.configurePopup(_:databases:currentDatabase:addDatabaseSelector:refreshDatabasesSelector:)` rebuilds the choose-database popup (header items, system/user partition, separator, selection)
- New `SADatabaseListManager.partition(databases:)` + `SADatabasePartition` ObjC bridge class for the system-vs-user split
- `-[SPDatabaseDocument setDatabases]` now a thin trampoline that calls the manager and stores the partition into the existing `allDatabases` / `allSystemDatabases` ivars (those still have callers outside this method — A1b/A1c will absorb them)
- System database name literals inlined (mysql, information_schema, performance_schema, sys) so the file compiles into the Unit Tests target without a bridging header (same pattern as SAViewMode)
- 17 unit tests in `SADatabaseListManagerTests.swift` covering partition (mixed/empty/all-system/all-user/case-sensitivity), popup header items + nil-target invariant, section ordering, separator omission when no system DBs, selection (current/placeholder/empty), and idempotent rebuild

A1b — Navigator schema path extraction — ✅ Done (scoped down)
- `SADatabaseListManager.navigatorSchemaPath(connectionID:selectedDatabaseTitle:)` + `schemaPathDelimiter` constant (U+FFF8, mirroring `SPUniqueSchemaDelimiter` in SPConstants.m)
- `-[SPDatabaseDocument selectDatabase:item:]` shrinks by 7 lines of NSMutableString juggling
- 4 new tests for path shape + edge cases
- Originally planned to extract `-chooseDatabase:` and `-selectDatabase:item:` wholesale, but on inspection both methods need a callback protocol back to the document for tablesList edit-commit checks, task start/end, and thread dispatch — properly belongs in A1c

A1c — `-_selectDatabaseAndItem:` (background-thread selection flow) + callback protocol — pending
- Also absorbs the remaining `-chooseDatabase:` and `-selectDatabase:item:` document-coupled logic
- Will let `allDatabases` / `allSystemDatabases` ivars move off SPDatabaseDocument
- Files: `Source/Controllers/MainViewControllers/SPDatabaseDocument.m`, `SADatabaseListManager.swift`

**A2. Extract task/progress management (~257 lines)**
- `startTaskWithDescription:`, `endTask`, `setTaskPercentage:`, `enableTaskCancellation:`, progress window fade, cancel button
- Already has `SATaskManaging` protocol — create `SATaskController` that implements it
- Move the progress window, indicators, and timer management out of the document
- Files: `SPDatabaseDocument.m`, new `SATaskController.swift`

**A3. Extract view state switching to use SAViewMode (~188 lines)** — ✅ Done
- `viewStructure`, `viewContent`, `viewQuery`, `viewStatus`, `viewRelations`, `viewTriggers`
- Replaced 6 repetitive method bodies with a shared `-[SPDatabaseDocument switchToViewMode:]` that consults `SAViewMode` for tab index, toolbar identifier, and prefs value
- Added ObjC accessors on `SAViewModeHelper` (`tabIndexFor:`, `toolbarIdentifierFor:`, `preferencesValueFor:`)
- View-specific extras (focus change for query, table load + focus for status) stay in the per-mode wrappers
- Files: `SPDatabaseDocument.m`, `SPDatabaseDocument+ViewMode.swift`

**A4. Extract window title management (~57 lines)** — ✅ Done
- New `SAWindowTitleBuilder` (Swift, pure, no AppKit) composes both window and tab titles from the document's current state. Three-branch state enum (`connecting`, `disconnected`, `connected`) mirrors the original ObjC code.
- `displayNameWithIsConnected:…` ObjC bridge replaces the duplicated path-prefix logic in `-[SPDatabaseDocument displayName]`.
- `-[SPDatabaseDocument updateWindowTitle:]` shrinks from ~50 lines of NSMutableString juggling to ~20 lines of state-gathering and a single forward call into the builder.
- Accessory color update stays gated on `connected` (unchanged behavior).
- 15 unit tests in `UnitTests/SAWindowTitleBuilderTests.swift` pin byte-exact output: connecting state, disconnected with/without path prefix, untitled-flag suppression, connected variants (host only, +db, +db+table), server-version preamble (window-only, nil version omitted), file-prefix + version stacking order, empty db/table normalization, and `displayName` parity.
- Files: `Source/Controllers/Window/SAWindowTitleBuilder.swift`, `SPDatabaseDocument.m`

### Phase B: Test coverage (foundation for safe refactoring)

**B1. Integration test for connection flow**
- Test that SAConnectionService can create a connection when given valid params
- Requires a test MySQL instance (Docker or local) — make it opt-in via env var
- Test TCP/IP, socket, SSL, database selection, timezone

**B2. Tests for SAFavoritesListDataSource** — 🟡 Partial (search matcher done)

B2a — Extract + test the favorites-search matcher — ✅ Done
- New `SAFavoriteSearchMatcher` (Swift, pure, no AppKit) owns the
  whitespace tokenize → AND-across-tokens → substring-in-name-or-host
  rule, lifted out of `SAFavoritesListDataSource.rebuildVisibleNodes` /
  `collectMatchingNodes` (which now delegate to it). The tree walk
  itself stays in the data source.
- 17 unit tests in `UnitTests/SAFavoriteSearchMatcherTests.swift`
  covering: `isActive` for empty/whitespace/single/multi queries,
  inactive-matcher-matches-everything, token lowercasing, adjacent-
  whitespace collapse, mixed whitespace splitting (`\t`, `\n`, space),
  single-token name/host hits, case-insensitivity on both sides,
  multi-token AND across mixed name/host fields, single-token miss,
  empty-name-and-host fail, and substring vs word-boundary semantics.
- Files: `Source/Controllers/MainViewControllers/ConnectionView/SAFavoriteSearchMatcher.swift`, `SAFavoritesListDataSource.swift`

B2b — Outline-view data-source tests (numberOfChildren, child(at:),
Quick Connect injection, drag/drop validation, isGroupItem, etc.) —
pending. Blocked on getting `SPTreeNode`, `SPFavoriteNode`,
`SPGroupNode`, `SPFavoritesController`, `SPFavoriteTextFieldCell`,
`SPFavoriteColorSupport`, and the relevant `SPConstants` strings
visible to the Unit Tests target (none currently are — the test target
is standalone, no bridging header). Likely needs either an ObjC test
file that `#imports` the .m files directly (existing pattern in
`SPDatabaseActionTest.m`) or a small bridging header for the test
target. Worth its own PR.

**B3. Tests for SAViewMode** — ✅ Done
- 16 unit tests in `UnitTests/SAViewModeTests.swift` covering tab indexes, toolbar identifiers (literal match against the SPConstants wire format), preferences round-trip + unknown-value fallback, action selector names, the `SAViewModeHelper` ObjC bridges, and the toolbar item factory configuration
- `SPDatabaseDocument+ViewMode.swift` had its `SPMainToolbar*` extern references inlined so the file has no ObjC dependency and can be compiled into the Unit Tests target without giving it a bridging header (the inlined strings must stay in sync with `SPConstants.m` — documented in the source)
- Exhaustive-case guard test that fails if a new `SAViewMode` case is added without updating the suite

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

1. ~~**Phase A3** (wire SAViewMode into view switching) — quick win, already has the enum~~ ✅ Done
2. ~~**Phase B3** (SAViewMode tests) — validate before and after~~ ✅ Done
3. **Phase A1** (database list manager) — high value, moderate effort — 🟡 A1a/A1b done, A1c pending
4. ~~**Phase A4** (window title) — quick, easy~~ ✅ Done
5. **Phase B2** (favorites data source tests) — 🟡 B2a done (search matcher), B2b pending (needs test-target ObjC plumbing)
6. **Phase C1** (SwiftUI favorites list) — first visible SwiftUI
7. **Phase A2** (task controller) — large but impactful
8. **Phase D1-D3** (SPConnectionController cleanup) — ongoing
9. **Phase C2-C3** (SwiftUI connection form) — bigger effort
10. **Phase E** (table content/custom query) — long-term
