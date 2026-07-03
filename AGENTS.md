# AGENTS.md — guidance for AI coding agents

Sequel Ace is a native macOS GUI client for MySQL and MariaDB (a maintained fork
of Sequel Pro). It is an AppKit application with a large Objective-C legacy
codebase undergoing a gradual, deliberate modernization to Swift and SwiftUI.
Deployment target is macOS 12+.

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
  `SAPrintUtility` / `SAHTMLPrintRenderer` for print flows. The last legacy
  `WebView` island is `SPHelpViewerController` (migration planned).
- **Persisted-format compatibility:** favorites plist, `.spf` documents, and
  NSUserDefaults blobs written by old versions must stay readable. When
  touching serialization (e.g. migrating the remaining deprecated
  `NSKeyedArchiver initForWritingWithMutableData:` sites), prove old data
  still decodes.
- Known remaining deprecation groups (each deserves its own PR):
  `NSUserNotification` → UserNotifications.framework (4 files), and the
  deprecated `NSKeyedArchiver`/`NSKeyedUnarchiver` initializers listed above.

## Repo layout (abridged)

- `Source/Controllers/` — window/view controllers (the bulk of the app)
- `Source/Model/`, `Source/Other/` — models, extensions, utilities
- `Source/Views/` — custom views incl. `SAWebView.swift`
- `Source/Interfaces/` — XIBs (legacy UI)
- `UnitTests/` — the "Unit Tests" target's sources
- `Frameworks/SPMySQLFramework/` — the MySQL wire-protocol framework (separate
  Xcode project, its own tests)
- `.claude/modernization-followup-plan.md` — the detailed modernization
  roadmap: what's done (with rationale), what's next, and known sharp edges.
  Read it before starting refactoring work.

Biggest legacy files (approx.): `SPDatabaseDocument.m` (~6.3k lines, god
object being decomposed), `SPTableContent.m` (~5k), `SPExportController.m`
(~4k), `SPCustomQuery.m` (~3.9k), `SPTextView.m` (~3.9k).

## Building and testing

- Open `sequel-ace.xcodeproj`; build scheme **"Sequel Ace Debug"**. "Sequel Ace
  Beta" is a build configuration of the same target, not a separate target.
- Dependencies come via SPM (Firebase, Alamofire, SnapKit, OCMock, FMDB, …);
  first resolve needs network access.
- Run the "Unit Tests" target's tests for any change. The full suite is ~700+
  tests and should be fully green.

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

## Xcode project file (pbxproj) rules

- The project uses **classic groups**, not filesystem-synchronized folders.
  Files must be registered in `project.pbxproj` with target membership.
- **Never hand-edit `project.pbxproj` while Xcode has the project open** —
  Xcode clobbers on-disk edits with its in-memory model, and conversely a
  behind-Xcode's-back change (branch switch, merge) leaves Xcode's in-memory
  model stale: builds then silently compile the *old* file set while reporting
  success. If the pbxproj changed outside Xcode, close and reopen the project
  (or verify the build log actually compiled your files) before trusting any
  build.
- Agents with Xcode automation (MCP `XcodeWrite`/`XcodeRM`): use it to
  add/remove files — it updates Xcode's live model with real IDs. Otherwise,
  ask the user to add the file in Xcode rather than editing the pbxproj by
  hand.
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
