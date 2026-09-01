# Build Warnings Elimination Plan

Baseline: **413 warnings** in Xcode's issue navigator on `main` (2026-07-03,
Xcode 26.5). Counts include duplicates from files compiled into multiple
targets (e.g. SPKeychain.m → app + SequelAceTunnelAssistant) and headers
included by several targets.

> **Status 2026-08-24 (updated on rebase).** Steps 0-9 are merged, and the two
> reduction sweeps have landed since this revision was drafted — **#2584**
> (532 → 358 occurrences) and **#2586** (358 → 162) are both on `main` now, so
> the sweep phase is complete and what remains is the deferred project set
> (SPKeychain `SecItem*`, NSConnection → XPC, bundled OpenSSL).
>
> The measurement below predates those two merges: taken on `main` at
> `3763d5247`, **"Unit Tests" scheme**, fresh derived data. Re-baseline with
> the same command before claiming any post-sweep delta:
>
> ```sh
> xcodebuild test -project sequel-ace.xcodeproj -scheme "Unit Tests" \
>   -destination "platform=macOS,arch=arm64" -derivedDataPath /tmp/dd \
>   CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO > build.log 2>&1
> grep -c " warning: " build.log                    # 352 raw occurrences
> grep -oE "/[^ ]+:[0-9]+:[0-9]+: warning: .*" build.log | sort -u | wc -l   # 146
> ```
>
> ⚠️ **Not comparable to the trajectory table below**, which was measured with
> the **"Sequel Ace Debug"** scheme — a smaller compile than the test scheme,
> so its numbers are lower for the same tree. The sweep PRs' occurrence counts
> (#2584/#2586) are a third basis again. No attempt is made here to convert between them:
> this plan already warns *compare like with like when claiming a delta*, and
> the scheme is the part most easily forgotten, so it is now recorded next to
> the number.
>
> The macOS 13.5 bump (#2587) changed none of this: normalizing both logs the
> same way, the warning sets before and after are identical, with no new
> deprecations from 13.1-13.5 despite the floor crossing those releases.

Ground rules (per AGENTS.md): all new code Swift, one focused PR per step,
behavior-preserving unless the step says otherwise, full test suite green,
`#infra` PR tag.

## Step 0 — Land what's in flight — ✅ Done (PR #2484 merged)

WKWebView print migration merged (54fac1aa3), including review follow-ups:
SAPrintUtility unit tests (via a pure `configuredPrintInfo()`), the restored
"Print Backgrounds" accessory (`SAPrintAccessoryController`), old-macOS
background preservation via `-webkit-print-color-adjust` injection, and the
`webViewWebContentProcessDidTerminate` stuck-print fix. This also completed
the NSArchiver → NSKeyedArchiver migration at all call sites.

## Step 1 — Hygiene sweep (trivial, zero behavior change) — ✅ Done (PR #2486)

Landed as `feature/warnings-step1-hygiene`. Notes from execution: the issue
navigator's truncated list hid a second redundant cast
(SAFavoritesListDataSource:144) and three more performSelector sites
(SPRuleFilterController 1020/1033/1068) — all fixed; the four target/action
invocations now funnel through one pragma-suppressed helper. `editImage` fix
ended up as typing the outlet (`IBOutlet SPImageView *`, was `id`) rather than
a call-site guard. ~16 warnings total.

- **SPMySQLConnection.m** ×4 "method definition not found": the class methods
  (`defaultSSLCipherList`, `_defaultSSLCipherListString`,
  `_defaultTLSSuiteListString`, `_mergedSSLCipherPreferenceList…`,
  `_reachabilityProbeHostForHost…`) are implemented in the main
  `@implementation` but declared in the `(PrivateAPI)` category
  (`SPMySQL Private APIs.h:57-62`). Move the declarations into a main-class
  category/extension that matches where they're implemented (verified: NOT a
  real bug — implementations exist at SPMySQLConnection.m:140-301).
- **VaultAuthManager.swift:182/320** — dead right-hand side of `??` on
  non-optional String ×2.
- **SAFavoritesListDataSource.swift:134** — `as?` cast that always succeeds.
- **SPConnectionController.m:1327** — block implicitly retains self →
  `self->ivar`.
- **SPFieldEditorController.m:1360** — null passed to nonnull parameter →
  add a guard.
- **SPRuleFilterController.m:892** — `performSelector` leak warning → wrap in
  `#pragma clang diagnostic` with a comment, or convert to `IMP`/`NSInvocation`.

## Step 2 — Ivar-shadowing renames — ✅ Done (PR #2496)

Executed as scripted per-method renames (quoted strings and selector keywords
protected) so all uses within a scope moved together. Naming scheme by value
origin: `favorite*`, `detail*`, `candidate*`, `new*`, and `imported*`, plus
dataColumnDefinitions in SPCopyTable. 50 warnings → 0; 76/76 line-for-line.

- **SPConnectionController.m** (~47): locals named `host`, `user`, `password`,
  `sshPassword`, `type`, `port`, `database` shadow ivars. Rename locals
  (`resolvedHost`, `keychainPassword`, …). Pure mechanical, but this file
  handles credentials — review each hunk carefully; no logic changes.
- **SPCopyTable.m** (2): `columnDefinitions` locals.
- Consider enabling `-Wshadow-ivar` as error afterwards to prevent regression
  (only once clean).

## Step 3 — Nullability audit of SPDatabaseDocument.h — ✅ Done (PR #2498)

Execution notes: partial annotation of the two small headers cascaded
completeness warnings (SPFavoriteNode.h is widely included — 264 raw), so all
three headers got full NS_ASSUME_NONNULL wraps. The audit surfaced and fixed
two latent issues beyond the plan: both SADatabaseDocumentProviding
protocol-optionality mismatches, and an untyped -color sender in
SPEditorPreferencePane resolving against CGColorRef. Swift fix-ups were
confined to accessory outlets, the MCP extension, and SPWindowController.

- Wrap **SPDatabaseDocument.h** in `NS_ASSUME_NONNULL_BEGIN/END` and annotate
  the genuinely nullable declarations `nullable` (~72 warnings). Same for
  **SPRuleFilterController.h** (3) and **SPFavoriteNode.h** (1).
- ⚠️ This changes the Swift-imported optionality of every touched API —
  expect Swift compile errors in `SPDatabaseDocument.swift`,
  SADatabaseSelectionDelegate bridges, SATaskController delegate, etc. Fix-ups
  are part of this PR. Also resolves the existing
  "`contentViewSplitter` has different optionality than expected by protocol
  `SADatabaseDocumentProviding`" warning — align the protocol while at it.
- Verify each `nonnull` judgement against the .m (many getters can return nil
  during connection teardown — when in doubt, `nullable`).

## Step 4 — NSKeyedArchiver/Unarchiver secure-coding initializers — ✅ Done

12 sites across 6 files. Drag-pasteboard pairs (query favorites, content
filters, navigator→textview, SSL ciphers) moved to secure root-object
archiving (`archivedDataWithRootObject:requiringSecureCoding:YES` +
`unarchivedObjectOfClass(es):`) — same-process round-trips, format change
safe. The `.spf` session read/write kept the exact non-secure keyed
`"data"`-key wire format for cross-version file compatibility, proven by
`UnitTests/SAKeyedArchiveCompatTests.swift` (legacy fixture decode,
round-trip, wire-format pin for old readers, garbage rejection). Failure
paths hardened: nil decodes now degrade gracefully instead of throwing.

## Step 5 — NSUserNotification → UserNotifications.framework — ✅ Done

New `SANotificationCenter` (Source/Other/Utility/, app target) replaces all
9 legacy post sites across SPDatabaseDocument / SPCustomQuery / SPDataImport /
SPExportController. Simpler than planned: NO legacy delegate existed, so there
was no click-to-focus behavior to port, and both old and new centers suppress
banners while the app is frontmost by default. Authorization is requested
lazily on first post (permission prompt appears in context); a
bundle-identifier guard keeps test runners from trapping. User-visible change:
first notification asks for permission — release-notes worthy.

## Step 6 — Help viewer WKWebView migration (roadmap "PR B") — ✅ Done

`SPHelpViewerController.m/.h` + `HelpViewer.xib` (~550 lines) replaced by three
Swift files per `docs/development/help-viewer-rewrite-plan.md`:
`SAHelpViewerModel` (state + pure decisions, app **and** Unit Tests target),
`SAHelpViewerView` (SwiftUI), `SAHelpViewerWindowController` (`@objc final`
NSWindowController + NSHostingView). **33 legacy WebKit warnings gone (unique;
206 → 173 in a clean build) — legacy WebKit no longer exists in the codebase.**

Execution notes:

- The plan's estimate of "~20 warnings" was low: 33 unique (36 raw) came out,
  because the `WebActionNavigationTypeKey` / `WebNavigationType*` constants
  aren't matched by a `WebView|WebMenuItem` grep.
- `SPHelpViewerClient` stayed ObjC as planned; it gained the two constants and
  the `SPHelpViewerDataSource` protocol from the deleted controller header, and
  is now exposed to Swift via the bridging header (the window controller is
  app-target-only, so the test target is unaffected).
- No new subclass was needed for the context menu: `SAWKWebView` grew a
  `customizeMenu` hook, and `SAWebViewModel` grew `decideNavigationPolicy`,
  `find(_:forward:)` (WKFindConfiguration) and `evaluateJavaScript` — all three
  reusable by future WKWebView hosts.
- ⚠️ **The plan's `applewebdata://` recon fact does not carry over to WKWebView.**
  Those URLs came from WebView's synthetic base plus the hand-made
  `WebHistoryItem`s; WKWebView loads a `baseURL: nil` document as `about:blank`,
  and a relative topic link (`<a href='SELECT'>`) then reaches the delegate as a
  *scheme-less relative* URL. Caught in review (Codex), verified with a
  standalone WKWebView probe, fixed by rendering with an explicit
  `sequelace-help://help/` base URL — nothing ever loads that scheme, the policy
  always cancels. A unit test pins the resolution so the coupling can't rot.
- Menu pruning matches WebKit's `WKMenuItemIdentifier…` values as **literal
  strings**: those constants exist in the WebKit binary but not in the public
  SDK headers, so linking them would mean adopting SPI. Unknown items are left
  alone. WebKit's own Back/Forward items are pruned too — this window navigates
  its own term history, so they would be dead.
- Two deliberate behaviour changes, both noted in the PR: clicked links are
  only opened externally for `http`/`https`/`ftp` (help HTML is generated from
  server-supplied text, and the legacy code handed any scheme to NSWorkspace),
  and re-visiting the currently displayed term no longer pushes a duplicate
  history entry.
- 25 unit tests in `SAHelpViewerModelTests` (history incl. the 20-entry
  eviction, navigation-policy matrix, title, theme hook, context-menu rules,
  key equivalents). Full suite: 882 tests, 0 failures.
- ⚠️ Not verified against a live server: the manual checklist in the rewrite
  plan (TOC, link routing, find-in-page, selection menu, dark-mode re-theme,
  auto-help) still needs a pass against a real MySQL/MariaDB connection.

## Step 7 — Safe AppKit deprecation batch 3 — ✅ Done

20 sites / 10 files. Mostly renamed-constant swaps; three structural:
SPTooltip moved to `defaultWebpagePreferences.allowsContentJavaScript`,
GitHubReleaseManager to Alamofire `responseData` + direct Codable decode
(the JSONSerialization roundtrip was a no-op), and SPImageView's PICT
snapshot now renders into a bitmap-backed context (also retiring a
lockFocus that would deprecate at macOS 14). Deprecated toolbar
identifiers (Customize/Separator) deleted — ignored since 10.7.

One-line-ish constant/API swaps, same shape as merged batches #2441/#2443:

- `NSPNGFileType` → `NSBitmapImageFileTypePNG`;
  `initWithFocusedViewRect:` → `cacheDisplayInRect:toBitmapImageRep:`
  (SPImageView.m)
- `NSRTFPboardType` → `NSPasteboardTypeRTF`; `NSFitPagination` →
  `NSPrintInfo` pagination enum (SPTextView.m)
- `NSEvenOddWindingRule` → `.evenOdd` (SPColorSelectorView.m)
- `NSPlainTextTokenStyle` → `.none` (SPExportController.m)
- `pathComponentCells` → `pathItems` (SPFieldMapperController.m)
- `NSToolbarSeparatorItemIdentifier` / `NSToolbarCustomizeToolbarItemIdentifier`
  → delete (ignored since 10.7) (SPDatabaseDocument.m)
- `javaScriptEnabled` → `WKWebpagePreferences.allowsContentJavaScript`
  (SPTooltip.m)
- Alamofire `responseJSON` → `responseDecodable` + Codable model
  (GitHubReleaseManager.swift)
- YRKSpinningProgressIndicator (`NSProgressIndicatorSpinningStyle`,
  `graphicsPort`, `NSRoundLineCapStyle`) — third-party but vendored; patch the
  three constants in place.

## Step 8 — Swift 6 readiness — ✅ Done

5 warnings across 3 sites (the plan listed 2 — see below), all of the
"mutation of captured var in concurrently-executing code" family that becomes
a hard error in the Swift 6 language mode. Zero concurrency warnings left;
clean build 173 → 165 (the extra 3 lines are the compiler's caret-continuation
output for the same 5 warnings, which the grep counts separately).

Execution notes:

- ⚠️ **The plan missed a site.** `AWSSTSClient.swift:300/310` has the identical
  blocking-wrapper pattern as AWSSSOClient — same failure mode as step 1, where
  the truncated issue navigator hid siblings. Fixed too; a step that leaves an
  identical Swift-6 hard error behind isn't done.
- Both AWS clients now hand their outcome back through one shared
  `SAAsyncResultBox<Success>` (`Source/Other/Utility/`, app + Unit Tests
  targets) instead of writing into captured `var`s. It is a lock-protected
  `Result` box: the lock is not ceremony, because the waiter abandons the call
  on timeout while the task keeps running and writing. 5 unit tests, including
  a concurrent-completion smoke test.
- `SPAppController.openStandaloneConnectionWindow` needed no box at all: the
  captured var only existed so the observer could unregister itself. Switching
  to the repo's existing `NotificationToken` (which unregisters in `deinit`)
  and storing it next to the controller — the same ownership shape as
  `TabManager.ManagedWindow` — removes the self-reference entirely.
- Behavior preserved at all three sites, including the AWSSTSClient path where
  neither a result nor an error is recorded: it still returns nil without
  touching the caller's error pointer.

## Step 9a — Informal-protocol conformance — ✅ Done (36 of the 42)

⚠️ **The plan mis-described this batch.** It assumed "mostly the pre-10.7
NSTableView drag API … each needs manual drag-drop verification — slowest batch".
Reading the actual method behind each of the 42 warnings says otherwise:

| Method | Count | Formal protocol |
|---|---|---|
| `validateMenuItem:` | 18 | `NSMenuItemValidation` |
| `controlTextDidChange:` / `…EndEditing:` | 14 | `NSControlTextEditingDelegate` |
| `validModesForFontPanel:` | 3 | `NSFontChanging` |
| `validateToolbarItem:` | 1 | `NSToolbarItemValidation` |
| `tableView:` / `outlineView:` / `splitView:` | 6 | see step 9b |

36 of them are AppKit informal `NSObject` category methods that became members
of formal protocols (`API_DEPRECATED("This is now … of the X protocol")`), so
the fix is one conformance declaration per class — method bodies untouched, no
behavior change, nothing to drag-test. Landed as a single sweep over 21 files,
following the conformance style already used by `SPFilterTableController` and
`SPGotoDatabaseController`.

## Step 9b — Genuinely deprecated delegate methods — ✅ Done (6 of 6)

Split by who consumes the dragged payload, because that decides the risk.

**Done — payload stays inside the app (both ends ours), plus one dead method:**

- `splitView:shouldCollapseSubview:forDoubleClickOnDividerAtIndex:` —
  SPSplitView. **Not a migration: deleted.** The SDK says "NSSplitView no
  longer supports collapsing sections via double-click. This delegate method is
  never called." (deprecated 10.15, app targets 12), so the animated-collapse
  branch it guarded had been unreachable for years. Collapsing still works via
  `-toggleCollapse:` / `-setCollapsibleSubviewCollapsed:animate:`.
- `tableView:pasteboardWriterForRow:` — SPTableStructure (field reorder) and
  SPNetworkPreferencePane (SSL cipher reorder). Both write and read their own
  pasteboard, so both ends moved together, via the new Swift `SADragPasteboard`
  (items, item-order reads, and the refusal rules the per-row API can no longer
  express on its own — 15 unit tests).

⚠️ **The modern API requires UTI-conformant pasteboard type names, and this is
silent.** `NSPasteboardItem.setString:forType:` and `NSPasteboardWriting`'s
`writableTypesForPasteboard:` both reject anything that is not a valid UTI:
AppKit logs *"'SequelProPasteboard' is not a valid UTI string. Cannot set data
for an invalid UTI."*, the item carries nothing, and `writeObjects:` still
returns YES. The deprecated `-declareTypes:`/`-setString:forType:` path accepted
the app's legacy names, so a like-for-like migration compiles, runs, and drags
nothing. Caught here only because the extraction came with unit tests.

The two migrated sites therefore use new types owned by `SADragPasteboard`
(`com.sequel-ace.pasteboard.table-row`, `…ssl-cipher`), with both ends updated
together. `SPDefaultPasteboardDragType` ("SequelProPasteboard") now has no live
readers — its remaining references are inside SPCustomQuery's commented-out
drop handlers.

**Done (part 2) — the payload leaves the view, so it kept its current shape:**

- `tableView:writeRowsWithIndexes:toPasteboard:` — SPCustomQuery, SPTableContent.
- `outlineView:writeItems:toPasteboard:` — SPNavigatorController.

Each is now `-pasteboardWriterForRow:`/`-pasteboardWriterForItem:` returning a
marker-only item per row, plus `-draggingSession:willBeginAtPoint:for…:` which
attaches the whole-drag payload through `SADragPasteboard`. The navigator's two
legacy type names were renamed to UTIs alongside their readers (SPTextView,
SPTablesList), and `SPNavigatorPasteboardDragType` /
`SPNavigatorTableDataPasteboardDragType` were retired from SPConstants.

⚠️ **This plan's stated reason for the design was wrong, and the correction is
what makes the migration safe.** It said "per-row writers would put N items on
the pasteboard, and a receiver reading `-stringForType:` gets only the first".
Measured against AppKit, `NSPasteboard` does not treat the types alike:

| Type | Multi-item read |
|---|---|
| `.string` | **concatenated across all items, joined with `\n`** |
| `.tabularText` | first item only |
| custom UTI types, property lists | first item only |

So the danger was the opposite of the one described: had each row's item carried
its own `.string`, a receiver would have read the whole-drag blob *followed by
every row's fragment*. Keeping the per-row items marker-only is what holds
`-stringForType:` byte-identical to the deprecated writer's output.
`SADragPasteboardTests` pins both halves, including the contaminated shape.

Two smaller behaviour notes:

- The old writers refused a drag by returning NO when the combined payload came
  out empty. The per-row writer cannot see the payload, so it refuses on the
  cheap precondition instead (empty selection; no resolvable schema path), and
  the session hook skips attaching an empty blob. A non-empty selection whose
  text renders empty now starts a drag that carries nothing rather than not
  starting — unreachable in practice, since `-draggedRowsAsTabString` emits
  delimiters even for empty cells.
- SPTableContent's rule-filter cell payload moved its publish/refuse rule into
  `SPCellValuePasteboard.rowPayload(columnName:value:isNull:)` (Swift, 6 tests).

Review follow-up (CodeRabbit): the two pure lookups the migration left in ObjC
moved to `SADragPasteboard` — `schemaPath(fromKey:delimiter:)` (strip the
navigator's leading connection ID) and `columnName(forClickedColumn:…)` (map a
clicked table column through its storage index). Both are now tested, and the
schema-path split fixes a latent quirk in the regex it replaced: `.` does not
match newlines in ICU, so `^.*?<delim>` left a key containing one unstripped.
The rest of the flagged ObjC is pre-existing logic that *moved* between delegate
methods rather than new code — the net ObjC across the three files is +33 lines,
mostly doc comments and the two delegate signatures each site needs, against
+462 lines of Swift. The remaining ObjC (outline-view traversal, the cell
display/NULL reads) needs live AppKit objects and would only gain indirection.

One worry checked and dismissed: `SPCopyTable` grants drag-out permission by
overriding the pre-10.7 `-draggingSourceOperationMaskForLocal:` rather than
calling `-setDraggingSourceOperationMask:forLocal:`, and the session-based drag
path might plausibly have stopped consulting it — which would have left external
drags with the `NSDragOperationNone` default and broken them silently. Measured
against AppKit: a table view with only that override still reports
`NSDragOperationCopy` for `NSDraggingContextOutsideApplication` (one without it
reports 0), so the override is still honoured and needs no change. The navigator
sets its mask explicitly already.

Verify by hand: drag rows from the query result and content views into TextEdit
(with and without ⌘/⇧/⌥), a cell onto a rule-filter field, and a navigator item
into the query editor.

## Step 10 — Test-scheme residue sweep — ✅ Done

Measured on the **"Unit Tests" scheme** (`xcodebuild build-for-testing`, fresh
derived data): **165 → 104 raw occurrences, 119 → 60 unique lines**, zero new
warnings (`comm` over normalized sorted logs). This scheme compiles the test
sources the "Sequel Ace Debug" numbers above never saw, which is where most of
this batch lived:

- **SACellFilterRuleControllerStubs.m (46)** — the file's existing
  `-Wincomplete-implementation`/`-Wprotocol` suppression only covered the third
  of its three deliberately-partial stub classes; the pragma block now wraps
  all three, plus `-Wobjc-autosynthesis-property-ivar-name-match` for the
  stubs' autosynthesized properties next to the real classes' ivars.
- **`performSelector` leak warnings (7, the full set)** — five are void
  target/action- or setter-style invocations (keepalive ping,
  pagination/filter-table actions, link cell, SPTextView's color-setter
  table), where no +1 object can exist to leak. The other two are the
  forwarding shims in SPMainThreadTrampoline, which forward *arbitrary*
  selectors: the superclass path returns the value unchanged and the
  trampolined path intentionally discards it, so selector ownership is the
  caller's contract — the same contract as the NSObject `performSelector:`
  API they override. Each site wrapped in the `-Warc-performSelector-leaks`
  pragma per the SPRuleFilterController precedent, with a per-site
  justification comment.
- **SPFieldEditorController.m:1302 sign-compare** — the underflow flagged in
  #2584: `adjTextMaxTextLength - textLength` is unsigned, so when the existing
  text already exceeds the field maximum the remaining capacity underflowed
  huge, silently skipping the too-long tooltip. Now computed in signed
  `long long`; the truncated-insert append is additionally guarded to run only
  for positive capacity (previously it appended an empty string at exactly 0,
  and would have thrown had the underflow branch ever reached it).
- **Unused-but-set test variables (3)** — `__unused` on perf-test loop locals.
- **`-Wshadow` (2)** — the two inner `dispatch_async` re-resolutions of
  `weakSelf` in SPConnectionController's Vault flow shadowed the outer
  `strongSelf`; renamed to `mainSelf` (the deliberate re-resolve-after-hop
  semantics are unchanged).

Left alone, unchanged from the analysis above: Firebase's
`-Wquoted-include-in-framework-header` (21, prebuilt third-party framework
headers), SecKeychain (11) and NSConnection (6) deferred migrations, the
intentional `#warning` markers (14), `preparedCellAtColumn:` ×2 (wants the
view-based-tableview migration, not a cast), generated lexer unreachable-code
(2), RegexKitLite (1, vendored), `selectionHighlightStyle = .sourceList` and
the three intentional `legacyUnarchive`/`legacyArchivedData` markers.

## Step 11 — Third-party / generated-code containment — ✅ Done

Same basis as step 10 ("Unit Tests" scheme, clean `build-for-testing`, fresh
derived data): **104 → 78 raw occurrences, 60 → 34 unique lines** — exactly the
−26 predicted, zero new warnings. What remains is now *only* the deferred
migrations and the intentional markers (see below).

- **Firebase `-Wquoted-include-in-framework-header` (21)** — the prebuilt
  FirebaseAnalytics xcframework's own headers, unfixable from here. Silenced
  with per-file `-Wno-quoted-include-in-framework-header` on the only two TUs
  that `@import` Firebase modules (SPAppController.m,
  ReportExceptionApplication.m), set via the Xcode MCP. Deliberately *not* the
  target-wide `CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = NO`, so the
  check still guards our own framework headers. Verified the per-file flags do
  reach the module builds on Xcode 26.
- **`preparedCellAtColumn:row:` (2)** — containment, not migration: both
  tables (SPCopyTable, SPFieldMapperController's field mapper) are still
  cell-based, so the deprecated cell API is the only correct one until the
  view-based rewrite their existing 2020 TODOs already call for. Pragma-wrapped
  with a comment saying exactly that.
- **Generated lexer `-Wunreachable-code` (2)** — the unreachable code is
  flex's boilerplate in the generated `.yy.c`, so each `.l` prologue now
  carries a file-scope `#pragma clang diagnostic ignored` (a scoped push/pop
  can't reach generated code).
- **RegexKitLite `-Wobjc-multiple-method-names` (1)** — vendored third-party,
  patched in place per the step 7 precedent: the ambiguous `id` receiver is
  inside an `isKindOfClass:[NSException class]` branch, so it now casts to
  `NSException *` (also de-ambiguating `reason`/`userInfo` on the same line).

The remaining 34 unique lines are the floor this plan predicted: SecKeychain
(10) + NSConnection (6) deferred migrations, the intentional `#warning`
markers (14), and the intentional Swift deprecation markers (4:
`selectionHighlightStyle = .sourceList`, `legacyUnarchive`,
`legacyArchivedData` ×2).

## Step 12 — `#warning` markers → GitHub issues — ✅ Done

Same basis as steps 10-11: **78 → 52 raw occurrences, 34 → 20 unique lines**.
Every `#warning` in the codebase (15 sites — the build showed 14 because the
`Querying & Preparation.m` one had the same normalized text as a sibling) is
now a `// TODO (#issue):` comment pointing at a tracked Sequel-Ace issue:

| Issue | Markers |
|---|---|
| #2603 cross-class ivar access via KVC | SPWindowAdditions:79, SPImageView:52/118 |
| #2604 SPMySQLFramework encoding/dup conversion | Conversion.m:46, Querying & Preparation.m:130, SPMySQLResult.m:316 |
| #2605 CSV EOL detection vs multibyte encodings | SPDataImport.m:934 |
| #2606 SPDataImport cleanup (per-row UI, dup code, xib outlets) | SPDataImport.m:1170/1208/1222, SPDataImport.h:49 |
| #2607 dedupe result-cell lookup with SPTableContent | SPCustomQuery.m:3875 |
| #2608 collation menu rebuilt per cell-display | SPTableStructure.m:1997 |
| #2609 exporter encoding audit (writeUTF8String / NSData decode) | SPExporter.h:156, SPSQLExporter.m:345 |

The old markers' `#2978`/`#2700` references were **upstream sequel-pro issue
numbers**, not Sequel-Ace ones (they resolve to unrelated PRs here); the new
issues cite `sequelpro/sequelpro#2978` / `#2700` explicitly for history.

Remaining after this step: **20 unique lines**, all of them the two deferred
migrations — SecKeychain (10) and NSConnection (6) — plus the 4 intentional
Swift deprecation markers (`selectionHighlightStyle = .sourceList`,
`legacyUnarchive`, `legacyArchivedData` ×2). Zero is now gated purely on the
deferred projects below. *(Both migrations have since executed; with the
NSConnection Step 5b draft merged, the compiler-warning floor is the 4
intentional markers.)*

## Deferred (own projects, not part of this burn-down)

- **SPKeychain SecKeychain* API** — ✅ **executed**: see
  `docs/development/keychain-secitem-migration-plan.md` (characterize-first,
  stayed on the file-based login keychain so no data migration, retired the
  tunnel assistant's direct keychain read — which also resolved the pairing
  with the NSConnection item below). SPKeychain is deleted; `SAKeychain`
  (SecItem*) replaced it behind `SAKeychainProviding`, proven by a
  cross-implementation test matrix. All 10 SecKeychain unique warning lines
  are gone; the floor is now NSConnection (5) + the 4 intentional markers.
- **NSConnection → socket IPC** — ✅ **executed** (stacked PRs #2618-#2623,
  the last one a draft that waits for a release of soak): see
  `docs/development/ssh-tunnel-xpc-migration-plan.md`. The Step 0 spike
  (2026-09-01) showed a sandboxed app cannot vend `NSXPCListener` without
  launchd, so the project ran on the plan's fallback — a UNIX socket in the
  container with audit-token peer validation both ways. Step 5b deletes DO
  and the assistant's `.m`: the 5 `NSConnection` warning lines go to **0**,
  leaving the floor at the 4 intentional markers plus the bundled-OpenSSL
  linker warnings below.
- **Linker warnings** (libssl.3/libcrypto built for macOS 15 vs the app's
  target, install-name mismatch) — fixed by rebuilding the bundled OpenSSL in
  SPMySQLFramework with the right deployment target; belongs to a dependency
  refresh. **Unchanged by #2587**: the deployment target moved to 13.5 and the
  message now reads "building for macOS-13.5", but the committed dylibs were
  not rebuilt. `build-libmysqlclient.sh` *was* updated to 13.5, so whenever the
  rebuild happens it will produce a consistent binary.
- **Intentional markers, keep**: SAArchiving `legacyUnarchive` /
  `legacyArchivedData` (by design — the deprecation attribute *is* the
  guard-rail) and `selectionHighlightStyle = .sourceList` (replacement changes
  row metrics; wants a visual pass). The `#warning` TODOs were converted to
  tracked issues in step 12.

## Expected trajectory

| After step | Approx. remaining |
|---|---|
| 0 (merge #2484) | ~400 |
| 1-2 (hygiene + shadows) | ~340 |
| 3 (nullability) | ~260 |
| 4-5 (archiver + notifications) | ~225 |
| 6 + 7 (help viewer + AppKit batch) | **173 (measured, clean build)** |
| 8 (Swift 6) | **165 (measured, clean build)** |
| 9a (informal-protocol conformance) | **129 (measured, clean build)** |
| 9b part 1 (internal reorders + dead split-view method) | **125 (measured, clean build)** |
| 9b part 2 (3 drag-out payloads) | **128 -> 125 (-3); own basis, see below** |
| #2587 (macOS 13.5 floor + 6.0.0) | **no change** — sets identical before/after |

⚠️ The 9b-part-2 row is a *delta*, not a level, because it could not be made
comparable to the rows above it. Measured with `xcodebuild -scheme "Sequel Ace
Debug" ... clean build`, the same tree that the 9b-part-1 row records as 125
counts **128** unique `warning:` lines — the scheme or configuration used for
the earlier rows is not recorded, and two of the 128 are timestamped
`appintentsmetadataprocessor` lines that are build noise rather than code
warnings. What is solid is the before/after diff on one basis: 128 -> 125, and
`comm` over the two sorted logs shows the only substantive change is the three
`-Wdeprecated-implementations` lines disappearing (the other diff entries are
the same warnings at line numbers shifted by the edit). Re-baseline this column
with a recorded command before trusting the absolute numbers again.

**How these are counted.** Rows through step 5 are the original estimates, read
off Xcode's issue navigator (which counts a file compiled into several targets
several times). Rows from step 6 on are measured: `warning:` lines in a clean
`xcodebuild` log, deduplicated (`sort -u`) — 165 unique lines / 318 raw. Note
the unique count includes the compiler's caret-continuation lines, which repeat
a warning's text under the source excerpt: 16 of the 165 are those, so the
distinct-diagnostic count is nearer **149**. Compare like with like when
claiming a delta.

After step 9 the remainder is dominated by the deferred projects, measured on
the same build: SecKeychain 10, tunnel assistant / NSConnection 4, bundled
OpenSSL + linker 7. That is the realistic floor without taking one of those on.
