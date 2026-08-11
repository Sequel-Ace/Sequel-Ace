# Build Warnings Elimination Plan

Baseline: **413 warnings** in Xcode's issue navigator on `main` (2026-07-03,
Xcode 26.5). Counts include duplicates from files compiled into multiple
targets (e.g. SPKeychain.m → app + SequelAceTunnelAssistant) and headers
included by several targets.

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

## Step 6 — Help viewer WKWebView migration (roadmap "PR B") — ~20 warnings

- Rewrite `SPHelpViewerController` (only — `SPHelpViewerClient` stays ObjC
  with minimal edits) per `docs/development/help-viewer-rewrite-plan.md`:
  term-history model (capped at 20 entries, matching the legacy
  `backForwardList` capacity), WKWebView find API, JS selection bridge;
  reuse `SAHelpViewerOnlineURLBuilder` (already on main, tested).
- Kills all remaining WebView/WebPolicyDelegate/WebUIDelegate/WebHistoryItem/
  WebMenuItemTag* warnings. After this + Step 0, **legacy WebKit is gone**
  from the codebase.

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

## Step 8 — Swift 6 readiness — ~3 warnings

- **AWSSSOClient.swift:252** — captured-var mutation in concurrent code
  (hard error in Swift 6 mode): restructure with a continuation/actor.
- **SPAppController.swift:38** — `token` mutated after sendable capture:
  standard NotificationCenter-observer-token dance; use a box or
  `withExtendedLifetime` pattern.

## Step 9 — "Implementing deprecated method" batch — ~25 warnings

Implementations of deprecated delegate signatures (mostly the pre-10.7
NSTableView drag API `tableView:writeRowsWithIndexes:toPasteboard:` and
friends) across SPFieldMapperController, SPQueryFavoriteManager,
SPContentFilterManager, SPProcessListController, SPQueryController,
SPServerVariablesController, SPBundleEditorController, SPNavigatorController,
SPConnectionController, SPCustomQuery, SPTableTriggers, SPTableRelations,
SPExportController, SPAppController, SPEditorPreferencePane.
Adopt `NSPasteboardWriting`/`tableView:pasteboardWriterForRow:` per file;
chunk into 2-3 PRs by area (managers / table views / misc). Each needs manual
drag-drop verification — slowest batch, do last of the mechanical ones.

## Deferred (own projects, not part of this burn-down)

- **SPKeychain SecKeychain* API (~15)** — migrate to `SecItem*` with in-place
  migration of users' stored passwords. Highest risk item in the codebase;
  needs its own design (and pairs with the NSConnection item below since the
  tunnel assistant reads passwords).
- **NSConnection → NSXPCConnection** (SequelAceTunnelAssistant.m:117/168) —
  reworks the SSH-password IPC between app and helper tool.
- **Linker warnings** (libssl.3/libcrypto built for macOS 15 vs 12 target,
  install-name mismatch) — fixed by rebuilding the bundled OpenSSL in
  SPMySQLFramework with the right deployment target; belongs to a dependency
  refresh.
- **Intentional markers, keep**: SAArchiving `legacyUnarchive` (by design),
  `#warning` TODOs (collation-menu perf hog SPTableStructure:1994, duplicate
  code SPDataImport:1167 / SPCustomQuery:3761, private-ivar note
  SPImageView:50 (#2978)) — convert to GitHub issues if we want a clean zero.

## Expected trajectory

| After step | Approx. remaining |
|---|---|
| 0 (merge #2484) | ~400 |
| 1-2 (hygiene + shadows) | ~340 |
| 3 (nullability) | ~260 |
| 4-5 (archiver + notifications) | ~225 |
| 6 (help viewer) | ~205 |
| 7-8 (AppKit batch + Swift 6) | ~185 |
| 9 (deprecated delegate methods) | ~160* |

\* Remainder is dominated by SPKeychain/NSConnection/linker (deferred) and
multi-target duplicate counting; the issue-navigator number after step 9
should land near the duplicates-adjusted floor of the deferred items.
