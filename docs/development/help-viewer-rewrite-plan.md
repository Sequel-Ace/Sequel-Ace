# Help Viewer WKWebView Rewrite (warnings plan step 6 / roadmap "PR B")

The last legacy WebKit (`WebView`) code in the app: `SPHelpViewerController`
(453 lines ObjC + HelpViewer.xib). After this lands, deprecated WebKit is gone
from the codebase (~20 warnings). Branch fresh off main once the step 4/5/7
stack (#2509-#2511) merges.

## Recon facts (verified against the code)

- **The legacy history is synthetic.** `showHelpFor:` adds fake
  `WebHistoryItem`s (`applewebdata://<term>`) to the `backForwardList`, and the
  policy delegate intercepts `WebNavigationTypeBackForward` to re-render via
  `showHelpFor:… addToHistory:NO`. Every render is `loadHTMLString`. So the
  WKWebView port needs only a plain term-stack (array + index) — no
  `WKBackForwardList` gymnastics. **The legacy list is capped at 20 entries**
  (`setCapacity:20` in `windowDidLoad`, SPHelpViewerController.m:98) — the
  model must evict the oldest entry past 20, or history becomes unbounded.
- **Three help targets** (segmented control): MySQL (HELP lookup via data
  source), Page (find-in-page), Web (online docs via data source →
  `SAHelpViewerOnlineURLBuilder`, already on main + tested).
- **Policy routing**: `applewebdata://` link click → internal HELP lookup;
  real http(s) link click → `NSWorkspace` open externally; everything else
  denied except "other" (the loadHTMLString itself).
- **Context menu**: prunes ~17 default WebView items, adds "Search in MySQL
  Help" / "Search in MySQL Documentation" when there is a selection and no
  live link.
- **Title**: "MySQL Help (<page title>)" via `mainFrameTitle` KVO.
- **Dark mode**: on `effectiveAppearance` change, calls the template's
  `window.onThemeChange('light'|'dark')` JS hook.
- **Selection**: context-menu actions read `selectedDOMRange.text`.
- **Close semantics**: `windowShouldClose:` posts
  `SPUserClosedHelpViewerNotification` (SPCustomQuery listens to disable
  auto-help; consts also used by SPDatabaseDocument — they must stay
  ObjC-visible).
- **SPHelpViewerClient** (309 lines ObjC) is the data source: runs
  `HELP '<term>'` on the connection, renders HTML via MGTemplateEngine,
  handles the SPHelpViewerSearchTOC magic string. It stays ObjC with minimal
  edits (thin client, recently touched by SAHelpViewerOnlineURLBuilder work).

## New components (Swift, SA prefix)

1. **`SAHelpViewerModel`** (ObservableObject; pure parts test-eligible)
   - term history: `[String]` + index, `goBack/goForward/canGoBack/canGoForward`,
     `visit(term:)`, **capacity 20 with oldest-entry eviction** (legacy
     parity) — unit-testable without AppKit
   - **pure navigation-policy function** `policy(for: URL?, type:)` returning
     an enum (`.lookupTerm(String)` / `.openExternally(URL)` / `.allow` /
     `.deny`) so the decidePolicy matrix is unit-testable; the
     WKNavigationDelegate just executes the returned decision
   - `helpTarget` enum (mysql/page/web) + "sends whole search string" rule
   - window-title composition from page title — unit-testable
2. **`SAHelpViewerView`** (SwiftUI): search field + target segmented control +
   back/TOC/forward segmented control + `SAWebView` (reuse `SAWebViewModel`,
   incl. its existing `$pageTitle` publisher for the title).
3. **`SAHelpViewerWindowController`** (`@objc final` NSWindowController,
   NSHostingView — the established pattern): ObjC API surface
   (`showHelpFor:addToHistory:calledByAutoHelp:`, dataSource), posts the
   user-closed notification from `windowShouldClose:`, forwards
   `effectiveAppearance` changes to the JS theme hook.
4. **Context menu**: WKWebView on macOS has no public element-based menu API —
   subclass (`SAHelpViewerWebView`) overriding `willOpenMenu:withEvent:`;
   prune by `NSUserInterfaceItemIdentifier` (`WKMenuItemIdentifier…`), insert
   the two search items when a selection exists. Track selection via an
   injected `document.onselectionchange` user script posting the selected text
   to a message handler (cached in the model — also replaces
   `selectedDOMRange`).
5. **Find-in-page**: `WKWebView.find(_:configuration:)` with
   `WKFindConfiguration` (backwards flag for previous). Verify availability at
   build time; fallback is JS `window.find()`.
6. **Navigation policy**: extend SAWebView/SAWebViewModel with a
   decidePolicy hook (closure) if it doesn't have one yet; implement the
   three-way routing above with `WKNavigationType.linkActivated`.

## Migration mechanics

- Move `SPHelpViewerSearchTOC` + `SPUserClosedHelpViewerNotification` consts
  and the `SPHelpViewerDataSource` protocol into SPHelpViewerClient.h/.m (they
  must stay visible to ObjC callers; the controller header is deleted).
- SPHelpViewerClient: instantiate `SAHelpViewerWindowController` instead;
  everything else (HELP query, template engine, TOC) unchanged.
- Delete `SPHelpViewerController.h/.m` + `HelpViewer.xib` (XcodeRM / XcodeWrite
  through the Xcode MCP per AGENTS.md).
- Check the xib/menu for find-next/previous key routing and rewire via the
  window controller.

## Tests

- `SAHelpViewerModelTests`: history push/back/forward/truncate-on-new-visit,
  **20-entry capacity eviction**, no-dupe-adjacent behavior parity,
  target/sends-whole-string rule, title composition, and the
  **navigation-policy matrix** (`applewebdata://` link → term lookup, http(s)
  link → external open, `.other` → allow, everything else → deny). (Model
  file must stay free of project ObjC types.)
- URL routing already covered by `SAHelpViewerOnlineURLBuilderTests` on main.

## Manual verification checklist (needs a live MySQL connection)

TOC opens (Help ▸ MySQL Help), term search, internal link click, external
http link opens in browser, back/TOC/forward enablement + navigation,
find-in-page next/previous, selection context menu (both items, and their
absence without selection), dark/light switch re-themes the page, auto-help
from the query editor, closing the window disables auto-help
(notification), reopen works.

## Estimate & sequencing

One PR, ~600-700 lines Swift added, ~550 lines ObjC + xib deleted. Start
after #2509-#2511 merge so the warning delta is measured against a clean
baseline. SPHelpViewerClient Swift-ification is explicitly out of scope
(separate later PR if ever — it is working, tested-adjacent code).
