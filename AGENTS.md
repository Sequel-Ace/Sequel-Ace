# AGENTS.md — guidance for AI coding agents

Sequel Ace is a native macOS GUI client for MySQL and MariaDB (a maintained fork
of Sequel Pro). It is an AppKit application with a large Objective-C legacy
codebase undergoing a gradual, deliberate modernization to Swift and SwiftUI.
Deployment target is macOS 13.5+ (Ventura). Anything introduced up to and
including 13.5 needs no availability gate; 14+ APIs still do — so
`@available`/`#available` in this codebase should only ever name 13.6 or
later.

## Language policy — the most important rule

- **All new code is Swift. No new Objective-C.** No new `.h`/`.m` files, and no
  significant new ObjC code added to existing files. When a change touches
  legacy ObjC, prefer extracting the logic into a new Swift type and leaving a
  thin trampoline/bridge behind in the `.m` file.
- **New Swift types use the `SA` prefix** (`SAPrintUtility`, `SAArchiving`,
  `SAConnectionService`). The `SP` prefix marks legacy Sequel Pro-era code.
- **New UI is SwiftUI** where feasible. Established hosting pattern:
  `@objc final` `NSWindowController` subclass + `NSHostingView` + SwiftUI root
  view — see `SAAboutWindowController`, `SABundleHTMLOutputWindowController`.
- **Localization:** every new or changed localized UI string — whether added in
  code, a XIB, or another language catalog — must have a matching key and
  English value in `Resources/Localization/en.lproj/Localizable.strings` in the
  same PR. Reuse an existing exact-text key where possible, include a useful
  translator comment for new entries, and run
  `plutil -lint Resources/Localization/en.lproj/Localizable.strings`.
- **SwiftUI view boundaries** (per Apple's performance guidance): splitting a
  `body` into computed properties is *not* factoring for invalidation — every
  section still shares the view's boundary and re-evaluates on any state
  change. Give an expensive section its own `View` struct. Two caveats before
  assuming a split helps here:
  - A child holding `@ObservedObject`, a `Binding`, or a closure re-evaluates
    anyway (the object publishes to it; non-equatable fields defeat SwiftUI's
    memberwise comparison). Gate such a child with an explicit `Equatable`
    conformance comparing only its meaningful inputs, plus `.equatable()` at
    the call site — see `SATimeZonePicker` in `SAConnectionFormView.swift`.
  - The connection form's single `@Published var info` makes every keystroke
    publish model-wide; that granularity is fixed by `@Observable`
    (macOS 14+), not by splitting views — blocked on the 13.5 target.
- **No closure-built `Binding(get:set:)` as a child-view input** (same Apple
  guidance): the closure pair is recreated every body evaluation and SwiftUI
  cannot compare it, so the child re-evaluates even when nothing changed.
  Bind through a stable key path instead — `$model.<property>` works on
  `@ObservedObject`/`@State` even for *computed* read-write properties, so a
  write that needs routing (validation, side effects) gets a computed accessor
  on the model rather than a `set:` closure — see
  `SARecordViewModel.validatedEditDraft`. (`@Bindable` + subscript is the
  macOS 14+ form of the same idea.) Presentation flags for `.alert` get their
  own `@State` Bool next to the presented optional rather than a Bool binding
  derived from it. One sanctioned exception: a binding built *inside* an
  `.equatable()`-gated child from its own snapshot, which never crosses the
  boundary as an input — see `SATimeZonePicker.selection` and its comment for
  why holding a live Binding there instead would break the gate.
- **ObjC interop:** mark classes `@objc final class X: NSObject`. When a Swift
  method's internal argument label would be dropped in the generated selector,
  spell the selector explicitly — e.g. `func font(from data: Data?)` bridges to
  `fontFrom:` and silently breaks ObjC call sites; declare it
  `@objc(fontFromData:)`.
- **Refactors are behavior-preserving** and land as small, focused PRs. Pin
  existing behavior with unit tests before/while extracting (several suites
  assert byte-exact output of the code they replaced).

## Modernization conventions (do / don't)

- **Archiving:** never call `NSArchiver`/`NSUnarchiver` or the deprecated
  `NSKeyedUnarchiver.unarchiveObject(with:)`. Use `SAArchiving`
  (`Source/Other/Extensions/SAArchiving.swift`) — it writes keyed+secure and
  reads keyed-first with a legacy non-keyed fallback. That fallback is the one
  intentional deprecated call in the codebase; don't "fix" it — legacy user
  data (fonts, colours in NSUserDefaults) is non-keyed and unreadable by
  `NSKeyedUnarchiver`, so removing the fallback silently wipes user settings.
- **Web content:** never use legacy WebKit (`WebView`). Use `WKWebView` — via
  `SAWebView` (SwiftUI `NSViewRepresentable` wrapper) for embedded views, and
  `SAPrintUtility` / `SAHTMLPrintRenderer` for print flows. No legacy `WebView`
  remains: the last island, the MySQL help viewer, is now `SAHelpViewer*`.
- **Persisted-format compatibility:** favorites plist, `.spf` documents, and
  NSUserDefaults blobs written by old versions must stay readable. When
  touching serialization, prove old data still decodes with a fixture test —
  see `UnitTests/SAKeyedArchiveCompatTests.swift` for the pattern (embedded
  legacy blob + wire-format assertion protecting old readers).
- **Keyed archiving:** use `archivedDataWithRootObject:requiringSecureCoding:`
  / `unarchivedObjectOfClass(es):fromData:` for session-local data (drag
  pasteboards etc.); the `.spf` session paths in SPDatabaseDocument
  deliberately use non-secure keyed archiving under the `"data"` key — that is
  the cross-version wire format, don't "upgrade" it without a migration plan.
- **User notifications:** post via `SANotificationCenter`
  (`Source/Other/Utility/SANotificationCenter.swift`), never the deprecated
  `NSUserNotification` API. The wider warning burn-down (remaining: AppKit
  deprecation batch, Swift 6 readiness, old drag-API delegate methods, and
  the deferred SecKeychain/NSConnection projects) is tracked in
  `docs/development/warnings-elimination-plan.md`. The NSConnection item is
  executed per `docs/development/ssh-tunnel-xpc-migration-plan.md`: the SSH
  tunnel talks to its askpass assistant over a UNIX socket in the container
  with audit-token peer validation (the spike showed a sandboxed app cannot
  vend `NSXPCListener` without launchd). `SPSSHTunnel` exposes
  `SASSHTunnelAuthService` and nothing else; the assistant is Swift
  (`main.swift` + `SASSHTunnelAskpass`), and its target has **no bridging
  header**, so only `public` Swift would reach an Objective-C file there.

## Repo layout (abridged)

- `Source/Controllers/` — window/view controllers (the bulk of the app)
- `Source/Model/`, `Source/Other/` — models, extensions, utilities
- `Source/Views/` — custom views incl. `SAWebView.swift`
- `Source/Interfaces/` — XIBs (legacy UI)
- `UnitTests/` — the "Unit Tests" target's sources
- `Frameworks/SPMySQLFramework/` — the MySQL wire-protocol framework (separate
  Xcode project, its own tests)
- `docs/development/modernization-followup-plan.md` — the detailed modernization
  roadmap: what's done (with rationale), what's next, and known sharp edges.
  Read it before starting refactoring work.

Biggest legacy files (2026-08-24): `SPDatabaseDocument.m` (~6.4k lines, god
object being decomposed), `SPConnectionController.m` (~5.4k — *growing*, new
connection features keep landing here as ObjC; see the modernization plan),
`SPTableContent.m` (~5.4k), `SPCustomQuery.m` (~4.1k), `SPExportController.m`
(~4.0k), `SPTextView.m` (~3.9k). Roughly 23% of `Source/` is Swift by line
count.

## Building and testing

- Open `sequel-ace.xcodeproj`; build scheme **"Sequel Ace Debug"**. "Sequel Ace
  Beta" is a build configuration of the same target, not a separate target.
- Dependencies come via SPM (Firebase, Alamofire, SnapKit, OCMock, FMDB, …);
  first resolve needs network access.
- Run the "Unit Tests" target's tests for any change. The full suite is ~1,080
  tests (63 environment-skipped) and should be fully green.
- Agents: prefer the Xcode MCP (`BuildProject`, `GetTestList`, `RunSomeTests`,
  `RunAllTests`, `GetBuildLog`) over shelling out to `xcodebuild` — see
  [Xcode automation (MCP)](#xcode-automation-mcp) below.

### Unit Tests target — sharp edges

- The target has **no TEST_HOST**: it compiles app sources directly into the
  test bundle. There is no `@testable import` — tests reference app types
  directly.
- A Swift file exercised by tests must be a member of **both** the "Sequel Ace"
  and "Unit Tests" targets.
- Keep test-eligible Swift files **free of project ObjC types** (no bridging
  header in the test target — adding one breaks shared `.m` files via the
  generated `sequel-ace-Swift.h`; see the plan doc for the full analysis).
  Established workaround: inline needed string constants as private literals
  with a "keep in sync with SPConstants.m" comment, and put ObjC-touching
  bridge code in a separate app-target-only file (e.g. `SAFavoriteItem.swift`
  vs `SAFavoriteItem+Tree.swift`).

## Xcode automation (MCP)

- The repo ships an `xcode` MCP server in `.mcp.json`. It runs `xcrun
  mcpbridge`, which is bundled with Xcode 26+ — no install step, and because it
  is committed it works from any clone path. Approve it once per checkout when
  the client prompts. On an older Xcode the server simply fails to start; fall
  back to `xcodebuild` and the notes below.
- It is **windowless**. `XcodeOpenWorkspace` does not launch the Xcode UI — a
  background `XcodeService` does the work and nothing appears on screen. Do not
  tell the user "I opened Xcode".
- **Open the project first, every session.** Call `XcodeOpenWorkspace` with the
  absolute path to `sequel-ace.xcodeproj` and pass the returned
  `workspaceIdentifier` to the other tools. That identifier is minted per open
  and is not stable across opens; handing a path to a workspace that is not
  open fails with "Unknown workspace identifier".
- Beyond file management it covers builds and tests (`BuildProject`,
  `GetBuildLog`, `GetTestList`, `RunSomeTests`, `RunAllTests`) and reads the
  project tree with `XcodeLS` / `XcodeGrep`, which reflect *project*
  organization and target membership rather than the filesystem — which is what
  you want when verifying a file was registered.

## Xcode project file (pbxproj) rules

- The project uses **classic groups**, not filesystem-synchronized folders.
  Files must be registered in `project.pbxproj` with target membership.
- **Add and remove files with `XcodeWrite` / `XcodeRM`** — they register real
  IDs and target membership. A Swift file exercised by tests needs to land in
  **both** "Sequel Ace" and "Unit Tests"; confirm with `XcodeLS` plus a test run
  that shows the new tests, not by reading the pbxproj diff.
- **Never hand-edit `project.pbxproj` while the Xcode UI has the project
  open** — Xcode clobbers on-disk edits with its in-memory model, and
  conversely a behind-Xcode's-back change (branch switch, merge) leaves its
  model stale: builds then silently compile the *old* file set while reporting
  success. The MCP bridge does **not** share this hazard — it tracks the
  pbxproj on disk, so a `git checkout` under a workspace opened by the bridge is
  picked up with no close/reopen. Either way, after any out-of-band pbxproj
  change, verify the build actually compiled your files before trusting it.
- Without the MCP and without Xcode, the `xcodeproj` Ruby gem (already present
  transitively via fastlane) writes a valid additions-only diff. Verify with
  `plutil -lint` and a build that compiles the new files. Note it drops a couple
  of cosmetic `/* comment */` annotations on the main group; restore them to
  keep the diff additions-only.
- Prefer resolving pbxproj merge conflicts by replaying the add/remove
  operations on a fresh branch instead of hand-merging conflict hunks.

## Pull request conventions

- One focused change per PR; branch off `main` (e.g.
  `feature/modernization-…`, `bugfix/…`).
- PR titles carry a hashtag: `#added`, `#fixed`, `#changed`, `#removed`, or
  `#infra` (most modernization work is `#infra`).
- Fill the PR template sections: Changes / Closes following issues / Tested
  (processor, macOS version, Xcode version) / Screenshots / Additional notes.
- CodeRabbit reviews every PR — its "Major" findings are usually worth
  addressing; note behavior-parity decisions in the PR body so reviewers know
  a risk is pre-existing rather than introduced.
- UI-affecting changes (printing, help viewer, connection flow) need a manual
  verification pass against a live MySQL/MariaDB server; say so in the PR if
  it hasn't happened yet.
