# Sequel Ace Modernization — Follow-up Plan

> **Revised 2026-08-24.** Sibling tracks: the build-warning burn-down in
> `docs/development/warnings-elimination-plan.md` (steps 0-9 merged; the last
> two reduction PRs are in review), the help-viewer rewrite in
> `docs/development/help-viewer-rewrite-plan.md` (executed), the platform floor
> in `docs/development/macos-13-minimum-plan.md` (executed, merged as #2587),
> the SSH-tunnel IPC design in `docs/development/ssh-tunnel-xpc-migration-plan.md`
> (not started), the keychain `SecItem*` design in
> `docs/development/keychain-secitem-migration-plan.md` (design complete;
> execution starting with its Steps 0-1), agent ground rules in `AGENTS.md`.

## State of the world (2026-08-24 revision)

Everything in this section was re-derived from `main` at `3763d5247` on the
revision date, not carried forward from the previous pass.

- **Phases A1-A4, B3, C1a/C1b, C2a/C2b, C3, D1-D3**: done as detailed below.
  The SwiftUI connection screen is no longer scaffolding — see the C3 note.
- **The platform floor moved to macOS 13.5 and the app is now 6.0.0**
  (#2587, merged 2026-08-24). What that changed for this plan:
  - `SAGroupedFormStyle`, both `SARecordView` macOS 12 fallbacks and the
    `SAPrintUtility` 13.3 fallbacks are gone — the second, untested
    print-background rendering path with them.
  - **`@Observable` is still blocked.** It needs macOS 14, so the
    invalidation-granularity work below stays parked; 13.5 did not move it.
    Availability gates in this codebase should now name **13.6 or later** or
    they are dead code (`AGENTS.md`).
  - It unblocked Step 4 of the SSH-tunnel XPC plan, which was the actual reason
    for the bump: `-[NSXPCListener setConnectionCodeSigningRequirement:]` is
    13+ and had no supported equivalent on 12.
- **Modernization arcs completed** (see warnings plan for details):
  NSArchiver -> keyed archiving (SAArchiving, all call sites), WebView ->
  WKWebView for bundle output, all print flows (SAPrintUtility +
  SAHTMLPrintRenderer + SAPrintAccessoryController) *and* the MySQL help viewer
  (SAHelpViewer*) — no legacy WebKit left, NSUserNotification ->
  SANotificationCenter, keyed-archiver initializer migration (spf wire format
  pinned by SAKeyedArchiveCompatTests), AppKit deprecation batch 3,
  SPDatabaseDocument.h nullability audit, Swift 6 concurrency readiness
  (step 8), the AppKit validation/editing protocols and both drag-API
  migrations (steps 9a/9b).
- **Community/parallel work**: MCP server (SPMCPServer + HTTP + pref pane),
  Vault auth (`SAVault*` + VaultAuthManager), AWS IAM/SSO, cell-filter suite
  (`SACellFilter*`), SAHelpViewerOnlineURLBuilder (+tests), connection-string
  import + duplicate detection, PHP-serialized field editor support, editable
  Record View (`SARecordView`), column-value copy in result tables.
- **C3 is real.** `SAConnectionWindowController` is 755 lines (was 221) and
  hosts `SAFavoritesList` + `SAConnectionFormView` over `SAConnectionService`;
  the "New Connection Window" menu item is enabled and runs the SwiftUI screen
  beside the XIB flow. Still with the AppKit form: keychain password
  auto-fill, favorites CRUD, and the Vault role-list fetch.
- **Swift/ObjC balance**: 125 Swift files / 28.4k lines against 143 `.m` files
  / 94.0k lines under `Source/` (excluding `ThirdParty/`) — roughly 23% Swift
  by line count. Useful as a trend line; re-measure with
  `find Source -name "*.swift" -not -path "*ThirdParty*" -exec cat {} + | wc -l`.
- **PostgreSQL abstraction is stalled, not pending.** #2482 (Rust FFI driver)
  and #2493 (Swift abstraction) are both still **drafts**, last touched
  2026-08-03. Phase E is gated on them (see Recommended order), so that gate
  has not moved in three weeks — worth an explicit decision rather than
  continued waiting.
- **⚠️ SPConnectionController.m is 5,431 lines** (was 3,755 after the
  decoupling branch, 5,426 at the previous revision): the connection-string
  import, duplicate detection, Vault and AWS features landed as new ObjC
  directly in the controller, outpacing extraction. The AGENTS.md Swift-only
  rule postdates most of that code, and the #2491 keychain-handoff regression
  is evidence of the integration risk here. **First slice of the fix is in
  review**: #2583 extracts duplicate detection into `SAFavoriteDuplicateMatcher`.

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

Measured on `main` at `3763d5247` (2026-08-24) with `wc -l`. The middle column
is the 2026-08-11 revision, so the delta is two weeks of feature work.

| File | Jun 2026 | Aug 11 | **Aug 24** | Problem |
|------|------|------|------|---------|
| SPDatabaseDocument.m | 6,592 | 6,349 | **6,369** | God object; roughly flat, still the biggest |
| SPConnectionController.m | 3,755 | 5,426 | **5,431** | REGRESSED: import/Vault/AWS ObjC landed here. #2583 starts the clawback |
| SPTableContent.m | 5,027 | 5,145 | **5,351** | +206 in two weeks — fastest-growing file in the app |
| SPCustomQuery.m | 3,870 | 3,904 | **4,106** | +202 in two weeks; crossed 4k |
| SPExportController.m | 3,952 | 3,958 | **3,959** | Export logic tightly coupled to UI |
| SPTextView.m | 3,865 | 3,878 | **3,879** | SQL text view with autocompletion |

Read the trend, not the absolute numbers: decomposition (A1-A4, D1-D3) is
holding `SPDatabaseDocument.m` roughly flat against continuous feature work,
which is the win. The two Phase E files are now the ones actually accelerating
— together +408 lines in a fortnight — which strengthens the case for not
leaving Phase E indefinitely parked behind a stalled draft.

## Follow-up work (prioritized)

### Phase A: SPDatabaseDocument decomposition (highest impact)

SPDatabaseDocument.m at 6,592 lines is the biggest bottleneck. Break it apart:

**A1. Extract database list management (~283 lines)** — ✅ Done

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

A1c — `-_selectDatabaseAndItem:` (background-thread selection flow) + callback protocol — ✅ Done (scoped down)
- New `SADatabaseSelectionDelegate` (Swift `@objc protocol`) exposes
  the ~23 hooks the background-thread flow needs (selection ivars,
  history-state read/write, `mySQLConnection` bridge,
  `chooseDatabaseButton`, popup rebuild, task end, tables-list focus
  ops, alert, bundle-trigger fan-out). The manager file stays free of
  project-specific ObjC types so it still compiles into the Unit
  Tests target without a bridging header.
- `SADatabaseListManager.performSelection(database:item:delegate:)`
  owns the orchestration (popup-rebuild-and-retry, focus restore,
  history-state restore). The `@autoreleasepool` stays in the document
  trampoline so the Swift body can use clean early returns.
- `-[SPDatabaseDocument _selectDatabaseAndItem:]` shrinks from ~100
  lines to a single forwarding call. The conformance + 22 short
  bridge methods live alongside it under a `SADatabaseSelectionDelegate`
  pragma section.
- `-chooseDatabase:` and `-selectDatabase:item:` stay on the document:
  they're already small, reference `_isWorkingLevel` /
  `databaseListIsSelectable` ivars, and a clean carve would have
  doubled the protocol surface for thin wins. Out-of-scope for A1c.
- `allDatabases` / `allSystemDatabases` ivars also stay on the document
  for now — they have callers in the add/copy/rename enablement
  (`controlTextDidChange:`) and the delete path that aren't touched by
  A1c. Moving them is its own task.
- No new tests — the carved-out method is pure orchestration that
  would need a heavy fake delegate to exercise. Existing
  `SADatabaseListManagerTests` (21 tests) still pass.
- Files: `Source/Controllers/MainViewControllers/SPDatabaseDocument.m`, `SADatabaseListManager.swift`

**A2. Extract task/progress management (~257 lines)** — ✅ Done (scoped to the progress UI)
- New `SATaskController` (Swift, app-target only) owns the task *progress
  UI*: the borderless progress window (created + configured in its init
  from `ProgressIndicatorLayer.xib`, now File's-Owner = `SATaskController`),
  the `YRKSpinningProgressIndicator`, the description / query-duration
  labels, the cancel button, and the fade-in / query-execution-time
  timers. It also owns the determinate/indeterminate display state, the
  percentage-throttling, and the cancellation callback state.
- `SATaskControllerDelegate` (Swift `@objc protocol`, defined alongside the
  controller) exposes the two hooks the controller can't own:
  `taskParentWindow()` (parent window to centre over / parent the panel to)
  and `taskControllerDidRequestCancellation()` (kills the running query via
  the database-structure connection where available). Both implemented in
  `SPDatabaseDocument.m`; conformance declared in `SPDatabaseDocument.swift`.
  The delegate requirements are *methods* (not a property) so the existing
  ObjC method `-taskParentWindow` satisfies the @objc protocol — a `{ get }`
  property requirement would import the ObjC getter as a method and fail to
  conform.
- The document keeps the working-level counter (`_isWorkingLevel`) and the
  document-wide orchestration around it (`SPDocumentTaskStart/EndNotification`,
  toolbar `validateVisibleItems`, `databaseListIsSelectable`,
  `chooseDatabaseButton` enablement). `_isWorkingLevel` gates behaviour in
  ~8 unrelated document methods, so it stays on the document; only the
  progress *UI* moved. `SPDatabaseDocument`'s `SATaskManaging` methods are
  now thin trampolines: they manage that document-wide state and forward
  the presentation to `taskController` (`beginTaskIsFirstLevel:`,
  `endTaskDisplay`, `setTaskPercentage:`, `enableTaskCancellation…`, etc.).
  `cancelTask:` / `centerTaskWindow` / `fadeInTaskProgressWindow:` /
  `showQueryExecutionTime` moved entirely to the controller; the document's
  12 task ivars + 5 task IBOutlets are gone.
- No unit tests: the controller is AppKit/nib/timer plumbing that needs a
  live `NSWindow` + nib load + `YRKSpinningProgressIndicator` to exercise;
  the only branchy logic (percentage throttling) is trivial. Same rationale
  as A1c. Verified by a clean app build + the existing suite (522 pass; the
  one pre-existing `PreferenceDefaults.plist` bundle failure is unrelated).
- Files: `Source/Controllers/MainViewControllers/SATaskController.swift`,
  `SPDatabaseDocument.{h,m,swift}`, `Source/Protocols` (none — delegate
  lives with the controller), `Source/Sequel-Ace-Bridging-Header.h`
  (imports `YRKSpinningProgressIndicator.h` for Swift), and
  `Source/Interfaces/ProgressIndicatorLayer.xib` (File's Owner class).

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
still pending. Test target plumbing for this is non-trivial; see the
"Test-target ObjC visibility — known sharp edge" section below.

B2c — Tree-walking filter helper (`SAFavoriteSearchTreeWalker`) — ✅ Extracted (no tests yet)
- The recursive `collectMatchingNodes` walk inside
  `SAFavoritesListDataSource` moved into its own Swift file. The
  data source now just calls `SAFavoriteSearchTreeWalker.visibleNodes(in:matcher:)`.
- Direct tests for the walker are blocked on the same test-target
  ObjC visibility issue as B2b (needs `SPTreeNode` / `SPFavoriteNode` /
  `SPGroupNode` constructable from the test target). End-to-end
  coverage of the per-leaf matching rule still comes from
  `SAFavoriteSearchMatcherTests` (B2a).
- Files: `Source/Controllers/MainViewControllers/ConnectionView/SAFavoriteSearchTreeWalker.swift`, `SAFavoritesListDataSource.swift`

#### Test-target ObjC visibility — known sharp edge

Adding `SWIFT_OBJC_BRIDGING_HEADER` to the Unit Tests target so that
Swift tests can construct `SPTreeNode` / `SPFavoriteNode` /
`SPGroupNode` is the obvious move, but it interacts badly with the
auto-generated Swift→ObjC interface header (`sequel-ace-Swift.h`)
that the test target produces. Specifically:

  - Without a bridging header, the test target's
    `sequel-ace-Swift.h` happens to be benign and shared `.m` files
    that get compiled into the test target (e.g.
    `SPStringAdditions.m`, which does `#import "sequel-ace-Swift.h"`)
    compile fine.
  - With a bridging header added, the generated `sequel-ace-Swift.h`
    starts to emit `@import XCTest;` plus `@interface XxxTests :
    XCTestCase` for the test-only Swift test classes. The shared `.m`
    files don't have `XCTest` visible during their ObjC compile, so
    they fail with "Cannot find interface declaration for
    'XCTestCase'".
  - Renaming the test target's Swift→ObjC header to
    `Unit-Tests-Swift.h` removes the collision but then
    `sequel-ace-Swift.h` no longer resolves at all from the test
    target's ObjC compile (the app target's copy isn't on the
    effective search path during incremental test-only builds).

A real fix likely needs one of: (a) reworking which `.m` files get
shared with the test target, (b) splitting Swift-bridged ObjC code
out of those `.m` files, or (c) restructuring the test target with a
proper TEST_HOST/BUNDLE_LOADER linking against the app rather than
re-compiling everything standalone. None are small — worth their own
PR with deliberate scope. Until then, B2b and B2c tests stay in the
backlog.

**B3. Tests for SAViewMode** — ✅ Done
- 16 unit tests in `UnitTests/SAViewModeTests.swift` covering tab indexes, toolbar identifiers (literal match against the SPConstants wire format), preferences round-trip + unknown-value fallback, action selector names, the `SAViewModeHelper` ObjC bridges, and the toolbar item factory configuration
- `SPDatabaseDocument+ViewMode.swift` had its `SPMainToolbar*` extern references inlined so the file has no ObjC dependency and can be compiled into the Unit Tests target without giving it a bridging header (the inlined strings must stay in sync with `SPConstants.m` — documented in the source)
- Exhaustive-case guard test that fails if a new `SAViewMode` case is added without updating the suite

### Phase C: SwiftUI migration starts

**C1. SwiftUI FavoritesListView** — 🟡 In progress (NSViewRepresentable wrap done)

C1a — `NSViewRepresentable` wrap — ✅ Done
- New `SAFavoritesListView` (Swift, SwiftUI) wraps an
  `SPFavoritesOutlineView` driven by the existing
  `SAFavoritesListDataSource` inside an `NSScrollView`. It applies the
  same column / font / row-height / source-list config that
  `-[SPConnectionController setUpFavoritesOutlineView]` applies, and
  keeps the data source's `searchQuery` / `delegate` in sync across
  `updateNSView`.
- The delegate is captured as a `() -> SAFavoritesListDelegate?`
  closure over a `weak` local rather than a stored property, since
  `NSViewRepresentable` is a value type that SwiftUI keeps alive for
  the view's lifetime (avoids a retain cycle once C3 hosts it inside
  its owner).
- A `Coordinator` (NSObject) holds the data source + outline view
  across SwiftUI view-value churn and forwards the cell-based
  double-click to the delegate (mirrors
  `-[SPConnectionController nodeDoubleClicked:]`: ignore Quick
  Connect, edit groups, connect on leaf).
- App-target only (wired into pbxproj by hand, mirroring
  `SAFavoritesListDataSource.swift`); not yet hosted anywhere —
  Phase C3 (standalone connection window) is the intended host.
- No tests: the wrapper is AppKit plumbing that needs a live
  `NSOutlineView`; the filtering / data-source logic it drives is
  already covered by `SAFavoriteSearchMatcherTests`.
- Files: new `Source/Controllers/MainViewControllers/ConnectionView/SAFavoritesListView.swift`

C1b — pure SwiftUI `List` / `OutlineGroup` — ✅ Done (display/search/select; reorder+rename deferred)
- New `SAFavoriteItem` (Swift value model, Identifiable/Hashable) is a
  tree of `.quickConnect` / `.group` / `.favorite` nodes. Pure — no
  AppKit / project ObjC types — so it compiles into the Unit Tests
  target (same constraint as `SAFavoriteSearchMatcher`). Carries a
  stable `id` plus the real `favoriteID` so a selection resolves back
  to the underlying favorite. Ids come from the persistent
  `SPTreeNode` instance address (favorites prefer their `favoriteID`),
  so identity is stable + unique across sibling reorder/insert/remove
  — index-path ids would shift and clear SwiftUI's selection (Codex,
  PR #2416).
- `SAFavoriteItem.filtered(using:)` + `[SAFavoriteItem].filtered(query:)`
  reuse `SAFavoriteSearchMatcher` and reproduce the AppKit walker
  semantics exactly: Quick Connect always kept, favorites matched on
  name+host, groups kept only when a descendant favorite matches
  (group name itself not matched), empty groups pruned under an active
  query. Plus `flattened()` / `first(byID:)` lookups.
- `SAFavoriteItem+Tree.swift` (app-target only) builds the model from
  the live `SPTreeNode` tree via the `SPFavorite*Key` constants —
  isolated here so the model file stays test-eligible. (Builder itself
  is untested: constructing `SPTreeNode` from the test target hits the
  B2b sharp edge.)
- `SAFavoritesList` (SwiftUI) renders `List(selection:)` +
  `OutlineGroup(children:)` with `.sidebar` style, per-row icons
  (quick-connect / folder / database-small) and color-tinted favorite
  labels via `SPFavoriteColorSupport`, live search filtering, and
  double-click-to-connect on leaves (mirrors `-nodeDoubleClicked:`).
- 13 unit tests in `UnitTests/SAFavoriteItemTests.swift` covering
  flatten/lookup, inactive-query passthrough, name/host matching,
  group keep/prune rules, group-name-not-matched, quick-connect
  survival, and multi-token AND.
- Still deferred before this can replace the C1a wrap: drag & drop
  reordering, inline rename, and expand/collapse persistence (all
  still in the AppKit data source). Nothing hosts this view yet
  (Phase C3).
- Files: new `SAFavoriteItem.swift`, `SAFavoriteItem+Tree.swift`,
  `SAFavoritesList.swift`, `UnitTests/SAFavoriteItemTests.swift`

**C2. SwiftUI ConnectionFormView** — 🟡 All types + SSL/colour/time zone done (C2a+C2b); hosting pending (C3)
- The 55 IBOutlets in ConnectionView.xib are the eventual target.

C2a — TCP/IP form + observable model — ✅ Done
- New `SAConnectionFormModel` (Swift, ObservableObject, pure
  Foundation+Combine, BOTH targets) wraps the value-type
  `SAConnectionInfo` so SwiftUI binds straight into it
  (`$model.info.host`). It funnels the earlier extractions:
  `validate()` → `SAConnectionDetailsValidator` (D3), `effectiveName` →
  `SAConnectionFormHelpers.generateName` (user-entered name wins,
  whitespace-only names ignored), `canAttemptConnection` gate (socket:
  always; SSH tunnel: non-blank host OR remote socket path, mirroring
  the validator; TCP/AWS/Vault: non-blank host — Codex P2 caught the
  original gate blocking valid remote-socket tunnels), and ObjC
  bridging via `init(objc:)` / `apply(to:)` (value-copy semantics —
  edits don't leak back until applied).
- New `SAConnectionFormView` (SwiftUI, app-target only) renders the
  XIB's TCP/IP tab fields (Name w/ auto-generated-name placeholder,
  Host, Username, Password as SecureField, Database, Port w/ "3306"
  placeholder) + a Connect button (default action, gated) that runs
  D3 validation and surfaces the failure's alertTitle/alertMessage
  via `.alert`; on success calls the `onConnect` closure (C3 will pass
  SAConnectionService there). `formStyle(.grouped)` applied via an
  availability-gated modifier (macOS 13+; target was 12.0 at the time — the
  gate was removed when the target moved to 13.5). Like C1b,
  nothing hosts the view yet — C3 is the host.
- 14 unit tests in `UnitTests/SAConnectionFormModelTests.swift`:
  defaults, ObjC round-trip both ways, value-copy isolation,
  effectiveName matrix (name wins / host / host+db / empty / whitespace
  name), connect gate (TCP/IP host required incl. whitespace-only,
  socket always true), validation wiring (hostMissing + pass), and
  objectWillChange publishing on field mutation.
- Files were added via Xcode MCP `XcodeWrite` (real Xcode IDs); only
  the model's second (Unit Tests) membership was a manual pbxproj edit.
- C2b superseded this: see below.
- Files: `Source/Controllers/MainViewControllers/ConnectionView/SAConnectionFormModel.swift`,
  `SAConnectionFormView.swift`, `UnitTests/SAConnectionFormModelTests.swift`

C2b — all connection types + SSL, colour, time zone — ✅ Done
- `SAConnectionFormView` now renders every type `ConnectionView.xib`
  offers. A `Picker` replaces the tab bar; the detail fields switch on
  `info.type`. Field sets, labels and placeholders were read off the XIB
  container by container (TCP/IP, socket, SSH, AWS IAM, Vault), so e.g.
  the socket tab has no Port field and the SSH tab keeps its two groups
  (tunnel credentials, then MySQL-side details + remote socket).
- Shared sections added: colour (`SPFavoriteColorSupport`'s 7 swatches
  plus the -1 "none" sentinel the favorites plist uses), the time-zone
  picker, the security toggles, and the SSL file rows.
- `SATimeZoneChoice` (Swift, pure) collapses the stored
  (`timeZoneMode`, `timeZoneIdentifier`) pair into one selectable value,
  making the invalid combinations unrepresentable; `SATimeZoneMenuEntry.menu()`
  reproduces `-generateTimeZoneMenuItems` (two relative entries, then every
  identifier sorted case-insensitively, separator on each region-prefix
  change). Setting the choice clears the identifier outside the fixed
  mode, matching `-didChangeSelectedTimeZone:`.
- Per-type form shape lives on the model (`forcesSSL`, `showsSSLToggle`,
  `showsSSLFileOptions`, …) so it is testable: AWS IAM turns SSL and the
  cleartext plugin on itself, so its tab shows neither toggle nor an SSL
  container — it shows the explanatory label instead, which is exactly
  what the XIB does.
- Bool bridges for the `Int`-typed flags (`useSSL`, `allowDataLocalInfile`,
  …) so Toggles can bind; non-zero reads as on, matching the ObjC
  `-boolValue` the favorites plist is read with.
- ⚠️ **`vaultCredentialsPath` is a computed join, not a field.** The first
  cut bound a single "Vault mount" text field straight to it; the AppKit
  controller actually keeps `vaultMount` + `vaultCredentialsRole` ivars and
  computes the path via `SAVaultCredentialsPath`. The model now mirrors
  that with two stored halves — they cannot be derived from the path,
  because `credPath(mount:role:)` returns "" while the role is blank, so a
  mount typed first would vanish. Writing the tests for it caught a real
  bug: the resplit assigned `vaultMount` and then re-read
  `info.vaultCredentialsPath` for the role, but the first assignment had
  already rewritten that path from the half-updated pair, so loading a
  favorite kept the previous role.
- 25 new tests in `SAConnectionFormModelTests` (42 total): time-zone
  round-trip and menu shape, the flag bridges, per-type form shape, the
  connect gate and generated name across all five types, and the Vault
  mount/role split including the resplit-on-load case.
- Review follow-up (Codex P1/P2, CodeRabbit): three gaps against the AppKit
  form, all confirmed against `SPConnectionController` before fixing.
  - The file chooser stored only the path. `-chooseKeyLocation:` also writes a
    read-only security-scoped bookmark, without which a saved favorite cannot
    reach its key or certificate after the next launch — the panel grants
    access for the current launch only. The SwiftUI row now writes the same
    bookmark, and clears the row on cancel as the AppKit flow does.
  - It also accepted any existing file. `-chooseKeyLocation:` runs
    `validateKeyFile:`/`validateCertFile:` on the SSL key and client
    certificate (and, deliberately, on neither the SSH key nor the CA cert).
    Those checks moved into `SAConnectionFileValidator` + `SAConnectionFileKind`
    — pure, so they are tested on strings rather than needing a controller.
  - Vault could reach `onConnect` with an unusable configuration:
    `-initiateConnection:` rejects a blank vault host, credentials path or
    database host, and none of those were checked. They now gate both the
    Connect button and `validate()`, in the controller's order, via two new
    `SAConnectionValidationFailureKind` cases.
  - Also: the time-zone menu is built once rather than re-sorted on every
    `body` evaluation (which is every keystroke), and the colour swatch labels
    are derived from position and localized instead of a hardcoded English
    name list.
- Not covered here, deliberately: the AWS "Authorize Access to ~/.aws…"
  bookmark flow (needs Security-framework state, same reason D3 left it
  inline), the Vault role *list* fetch behind the XIB's combo box and its
  Refresh button (`SAVaultRoleListController`) — the Role field is plain
  text for now — and favorites save parity. All three want a live host,
  so they belong to C3.
- Files: `SAConnectionFormModel.swift`, `SAConnectionFormView.swift`,
  `UnitTests/SAConnectionFormModelTests.swift`

**C3. Wire SwiftUI into SAConnectionWindowController + expose in menu** — ✅ Done (favorites CRUD + keychain still with the AppKit form)
- ✅ Done: `SAConnectionWindowController` now hosts `SAConnectionWindowView`
  (an `NSHostingView` over `SAFavoritesList` + `SAConnectionFormView` in an
  `HSplitView`) instead of instantiating `SPConnectionController`. This is the
  first place the C1b/C2 views actually run — until now both compiled but
  nothing created them.
- ✅ Selecting a favorite populates the form through the D1 decoder
  (`SAConnectionFormModel.load(favorite:)`); Quick Connect resets it. Connecting
  validates via D3/C2b and goes through the existing `connectDirectly`, i.e.
  `SAConnectionService`, with no `SPConnectionController` involved.
- ✅ The "New Connection Window" menu item is enabled. It sits alongside the
  XIB's document-based flow rather than replacing it.
- ✅ **The handoff is complete** (three gaps found by Codex on #2572; hosting the
  views turned them from dead scaffolding into live code):
  - `SAConnectionInfoObjC.apply(to:)` populates the destination document's
    `SPConnectionController` before the connection is handed over, so the new
    tab's title, database, host, user, port and colour are right and `.spf`
    serialization carries real details. It is written as the exact inverse of
    `-_buildConnectionInfo`, field for field in the same order; the two were
    diffed mechanically to confirm 41/41 coverage both ways, which is a stronger
    check than a hand-written test since the risk here is omission, not logic.
  - AWS IAM and Vault now resolve their credentials before connecting.
    `SAConnectionService` only configures transport flags, so the window calls
    `AWSIAMAuthManager.generateAuthToken` for the RDS token (on the main queue,
    since the profile flow can raise an MFA sheet) and `VaultAuthManager`
    for ephemeral credentials (off the main queue — the OIDC leg can open a
    browser for up to two minutes — clearing the cached pair on failure so a
    retry re-runs it).
  - The established connection is given the destination document as its
    delegate; without it the framework fell back to bare automatic retry with no
    query-error logging, no no-connection alert, no keychain prompt on reconnect
    and no connection-loss UI.
- ✅ Second review round on the connect path (Codex, #2572), all seven fixed:
  Vault favorites keep a custom `vaultPort` / `vaultOIDCMount` (D1 omits them
  because the AppKit controller reads them raw for its placeholders, so this
  path carries them itself); Quick Connect resets through the nil-favorite
  decoder rather than `SAConnectionInfo()`, restoring colour -1 / compression
  on / profile "default"; the connection details are snapshotted before the
  asynchronous Vault leg so one endpoint's credentials cannot pair with
  another's details; an in-flight Vault OIDC login is cancelled on window close
  instead of holding its exclusive slot for two minutes; AWS IAM checks and
  prompts for `~/.aws` authorization before generating a token, which the
  sandbox needs and only `-authorizeAWSDirectory:` used to offer; a cancelled
  SSH password prompt no longer shows a spurious "Connection failed"; and the
  handoff asks TabManager for a *window* rather than a tab, since
  `newWindowForTab()` resolves through `mainWindow`, whose assertion that a
  managed database window is main would fire — and crash Debug — with the
  standalone window frontmost.
- ⚠️ Also still owned by the AppKit form:
  keychain password retrieval for a selected favorite (the D1 decoder never
  carried passwords, and the lookup needs the account/service naming still in
  `SPConnectionController`), favorites CRUD from this window (add / duplicate /
  delete / rename / reorder), and the Vault role-list fetch. Typing a password
  into the form works; a saved favorite's password does not auto-fill.
- 5 new model tests (73 in `SAConnectionFormModelTests`) covering favorite load,
  password non-carry, the Vault re-split on load, nil favorites and Quick Connect.
- **Remaining before the SwiftUI screen can replace the XIB flow** (this is
  what actually stops new connection UI landing in `SPConnectionController.m`,
  so it is on the recommended order): keychain password auto-fill for a
  selected favorite, favorites CRUD from this window (add / duplicate / delete
  / rename / reorder), and the Vault role-list fetch. Only once those exist
  does replacing the XIB's `newWindow:` become a question of switching a menu
  item rather than a feature gap.

**C2/C3 follow-up — SwiftUI invalidation boundaries** — 🟡 Time-zone picker done
- Apple's guidance: computed-property sections share their view's invalidation
  boundary, so `SAConnectionFormView`'s sections all re-evaluate on every
  keystroke (any `info` mutation publishes). The one expensive section — the
  ~600-entry time-zone menu — is now `SATimeZonePicker`, a separate `View`
  struct with an explicit `Equatable` conformance keyed on the selection and
  `.equatable()` at the call site. The conformance is load-bearing: the
  `onSelect` closure defeats SwiftUI's memberwise comparison, so a plain child
  struct would have re-evaluated anyway.
- Splitting the remaining sections is deliberately not done: each holds
  `Binding`s into the shared model, so extra structs would add boundaries that
  never skip. The real granularity fix is `@Observable`'s per-property
  tracking — **macOS 14+, blocked on the 13.5 deployment target**. Revisit when
  the target moves; until then treat `SATimeZonePicker` as the pattern for any
  genuinely expensive section (guidance recorded in AGENTS.md).
- Companion rule, same source: no closure-built `Binding(get:set:)` as a
  child-view input — SwiftUI cannot compare the closures, so the child
  re-evaluates regardless. The three shipped instances were converted:
  `SARecordView`'s edit field now binds `$model.validatedEditDraft`, a computed
  accessor routing writes through validation (the stand-in for
  `@Bindable` + subscript, which needs macOS 14), and both connection-form alerts present via a
  dedicated `@State` Bool instead of a Bool binding derived from the optional.
  `SATimeZonePicker.selection` stays closure-built on purpose — built inside
  the `.equatable()` gate from a snapshot, it never crosses a boundary; its
  comment explains why a live keypath Binding there would break the gate.

### Phase D: SPConnectionController further cleanup

**D1. Replace `updateFavoriteSelection:` with structured data flow** — ✅ Done
- New `SAConnectionInfo+Favorite.swift` (Swift, pure Foundation, compiles
  into BOTH targets): `SAConnectionInfo.fromFavoriteDictionary(_:)` +
  `SAConnectionInfoObjC.info(fromFavoriteDictionary:)` own the defaulting
  rules previously inline in `-updateFavoriteSelection:` (missing name →
  `""`, colorIndex → `-1`, useCompression → `YES`, awsProfile →
  `"default"`, tz-identifier only in fixed mode, `useAWSIAMAuth` derived
  from type, unknown type/tz-mode → tcpIP/server). Favorite keys are
  inlined string literals (documented sync-with-SPConstants.m caveat, same
  pattern as SAViewMode) so the file stays test-eligible. Value readers
  mirror ObjC `-integerValue`/`-boolValue` leniency (NSNumber or numeric
  NSString).
- `-updateFavoriteSelection:` now decodes once and populates the form from
  the typed info; ~70 lines of `?:`-defaulting gone. Keychain lookups and
  the per-type time-zone popup updates stay in the controller (side
  effects / AppKit).
- Deliberately NOT decoded: passwords/keychain items (keychain side
  effects), and `vaultPort`/`vaultOIDCMount` — those two stay as raw
  `objectForKey:` reads in the controller because nil (key absent) drives
  the form's NSNullPlaceholder ("443"/"oidc") and the info's non-optional
  strings can't represent the nil-vs-empty distinction.
- 20 unit tests in `UnitTests/SAConnectionInfoFavoriteTests.swift` pin:
  nil/empty-dict defaults, every section's decode (standard/SSL/SSH/
  AWS/Vault), all 5 type raw values + unknown fallback, tz-mode matrix
  (identifier cleared outside fixed mode), AWS toggle derivation (stored
  toggle never overrides), numeric-string leniency, NSNumber→String port,
  passwords-never-decoded, and the ObjC bridge.
- Files: `Source/Model/SAConnectionInfo+Favorite.swift`,
  `UnitTests/SAConnectionInfoFavoriteTests.swift`, `SPConnectionController.m`

**D2. Extract favorites management actions** — ✅ Done (scoped to the pure cores)
- The full "SAFavoritesManager wrapping SAFavoritesProviding" vision was
  too big for one behaviour-preserving PR — the actions are sheet/panel/
  outline-view orchestration. Extracted the pure cores instead:
- `SAConnectionInfo+Favorite.swift` gains the encode-side counterparts of
  the D1 decoder (same private `FavoriteKey` literals):
  - `defaultNewFavoriteDictionary(withID:)` — the 30-key new-favorite
    template previously built inline as parallel objects/keys arrays in
    `-addFavorite:`. Historical wire-format quirks preserved and pinned:
    no `useCompression` key, no SSL *path* keys (only enabled flags),
    vaultPort/vaultOIDCMount stored as `""` (not absent).
  - `duplicatedFavoriteDictionary(fromFavorite:withID:)` — fresh ID +
    localized "<name> Copy", source dict untouched; nil-tolerant (a group
    selection makes `-selectedFavorite` return nil).
- New `SAFavoriteDeletionPrompt` (Swift, pure Foundation, ConnectionView)
  owns the three-way delete-confirmation rule from `-removeNode:`:
  favorite → confirm w/ favorite wording, group w/ children → confirm w/
  group wording, empty group → delete with no alert.
- The three controller actions are now thin: `-addFavorite:` lost its ~70
  template lines, `-duplicateFavorite:` its ID/name mutation,
  `-removeNode:` its message composition.
- 11 new unit tests: 6 in `SAConnectionInfoFavoriteTests` (template key
  set + values + decoder round-trip ≈ blank-form equivalence; duplicate
  ID/suffix/no-mutation + nil source) and 5 in
  `SAFavoriteDeletionPromptTests` (three-way rule, childCount ignored for
  favorites, nil name).
- Import/export (`importFavorites:`/`exportFavorites:`) and `sortFavorites:`
  stay — heavy UI flows, and the import path was just rewritten by the
  connection-string PR (#2398). Revisit once that settles.
- ⚠️ Tooling note: hand-editing project.pbxproj while Xcode has the project
  open is an edit war — Xcode clobbers on-disk changes with its in-memory
  model when it saves (lost several Unit-Tests build entries twice). New
  files should be added via the Xcode MCP `XcodeWrite` (registers them in
  Xcode's live model with real IDs); extra target memberships can be
  added on disk immediately after an Xcode save, then committed promptly.
- Files: `Source/Model/SAConnectionInfo+Favorite.swift`,
  `Source/Controllers/MainViewControllers/ConnectionView/SAFavoriteDeletionPrompt.swift`,
  `UnitTests/SAConnectionInfoFavoriteTests.swift`,
  `UnitTests/SAFavoriteDeletionPromptTests.swift`, `SPConnectionController.m`

**D3. Extract form validation** — ✅ Done
- New `SAConnectionDetailsValidator` (Swift, no AppKit) owns the
  pre-connection rules previously inline at the top of
  `-[SPConnectionController initiateConnection:]`: host non-empty
  (TCP/SSH/AWS), ssh host non-empty (SSH only), SSH key file exists,
  SSL key/cert/CA files exist (TCP/socket + useSSL only).
- `SAConnectionValidationFailure` bundles the kind, alert title, and
  alert message — the controller pattern-matches the kind for per-
  failure side effects (clearing toggles, resetting paths) and shows
  the alert. AWS-directory authorization stays inline (needs Security
  framework bookmark state the validator can't represent).
- 29 unit tests in `UnitTests/SAConnectionDetailsValidatorTests.swift`
  cover happy paths for all four connection types, each individual
  failure trigger, the skip-when-disabled / skip-when-wrong-type
  cases, failure ordering (host → ssh host → ssh key → ssl key →
  cert → CA), and `fileExistsExpandingTilde` (real file, missing
  path, tilde expansion).
- Files: `Source/Controllers/MainViewControllers/ConnectionView/SAConnectionDetailsValidator.swift`, `SPConnectionController.m`

**Additional connection-form helpers (separate from D3)** — ✅ Done
- New `SAConnectionFormHelpers` (Swift) consolidates three small pure
  helpers that were private methods on `SPConnectionController`:
  - `newFavoriteID()` — hash-of-`%f`-timestamp ID factory used in
    `addFavorite:`, `duplicateFavorite:`, and import paths. The
    "stringify-then-hash" shape is pinned by a test so the favorites
    plist format stays stable on upgrade.
  - `stripInvalidCharacters(_:)` — trim outer whitespace + strip
    embedded newlines from user input.
  - `generateName(type:host:database:)` — auto-name for a connection
    (socket → "localhost", others require host, optional db suffix).
- The three controller methods become thin trampolines.
- 18 unit tests in `UnitTests/SAConnectionFormHelpersTests.swift`
  pin: ID non-zero + monotonic over time, strip semantics
  (no-op clean, leading/trailing whitespace + newlines, embedded
  newlines, embedded whitespace preserved, empty/whitespace-only),
  and `generateName` for all four connection types (host required
  for non-socket, socket always "localhost", db appended with `/`).
- Files: `Source/Controllers/MainViewControllers/ConnectionView/SAConnectionFormHelpers.swift`, `SPConnectionController.m`

### Phase E: SPTableContent / SPCustomQuery (long-term)

These are the next biggest files after SPDatabaseDocument. Lower priority but eventual targets:

- Extract table data loading into a service
- Extract query execution into a service
- Create protocols for table data source/delegate

## Recommended order (2026-08-24 revision)

Items 1-3 of the previous revision are done; the list below is what is actually
next. (#2583, #2584 and #2586, in review when this revision was drafted, have
all landed since.)

1. **SPConnectionController re-containment** — 🟡 first slice landed.
   #2583 (merged) extracts connection-import duplicate detection into
   `SAFavoriteDuplicateMatcher` (pure Swift, both targets), leaving the
   `SPTreeNode` walk, alert UI and keychain side effects behind. The rest of
   the freshly-added import logic (the `candidate*`/`detail*`/`imported*`
   naming from the shadow-rename pass) is the same shape of work and is best
   done while the code is young. This is the file that regressed; it is the
   highest-value target on the list.
2. **Finish the warnings burn-down** — ✅ sweeps done. #2584 (532 -> 358) and
   #2586 (358 -> 162) have both landed. What remains is the *deferred* set,
   which is project work rather than a sweep: SPKeychain `SecItem*` (now
   designed — `keychain-secitem-migration-plan.md`), the NSConnection -> XPC
   migration, and the bundled OpenSSL rebuild. See the warnings plan.
3. **SSH tunnel IPC: NSConnection -> NSXPCConnection** — now unblocked. The
   macOS 13.5 floor was adopted specifically so Step 4 (peer validation via
   `setConnectionCodeSigningRequirement:`) is a real security win rather than a
   partial one. Design is written up in `ssh-tunnel-xpc-migration-plan.md`,
   including a spike (Step 0) that decides the whole approach and a Step 1
   (narrow the vended surface) that is worth landing on its own merits either
   way. Highest blast radius in the codebase — SSH connections break if it is
   wrong — so it stays spike-first and behind a flag.
4. **Decide the PostgreSQL question rather than wait on it.** #2482 and #2493
   are drafts that have not moved since 2026-08-03, and Phase E has been gated
   on them. Meanwhile `SPTableContent.m` and `SPCustomQuery.m` grew 408 lines
   in a fortnight. Either the abstraction is going to land — in which case
   Phase E extractions should target `id<SPDatabaseConnection>` — or it is not,
   and Phase E should start against `SPMySQLConnection` with the seams drawn so
   an abstraction can slot in later. Continuing to wait is the one option that
   costs something every week.
5. **Phase E (table content / custom query services)** — see item 4. The
   extraction shape is unchanged: pull data loading and query execution into
   services, define protocols for the table data source/delegate.
6. **C3 remainder: keychain, favorites CRUD, Vault role list.** The standalone
   window works but a saved favorite's password does not auto-fill, favorites
   cannot be added/renamed/reordered from it, and the Vault Role field is plain
   text. Until these land the SwiftUI screen cannot replace the XIB flow, which
   is what actually stops new connection UI from landing in
   `SPConnectionController.m`.
7. **B1/B2b** (connection integration tests, test-target restructure) —
   unchanged backlog, pick up opportunistically. B2b is still blocked behind
   the test-target ObjC visibility sharp edge documented above.
8. **Invalidation granularity** — parked until the deployment target reaches
   macOS 14 for `@Observable`. 13.5 did not unlock it. `SATimeZonePicker`
   remains the pattern for any genuinely expensive section in the meantime.
