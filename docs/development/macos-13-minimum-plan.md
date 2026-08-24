# Drop macOS 12, Raise the Minimum to macOS 13

> **Written 2026-08-24.** Answers the open question in
> `docs/development/ssh-tunnel-xpc-migration-plan.md` § Step 4 ("Decision
> needed: is bumping the deployment target to 13.0 acceptable?") and unblocks
> two items parked in `modernization-followup-plan.md`. Siblings:
> `warnings-elimination-plan.md`.

## Scope in one line

`MACOSX_DEPLOYMENT_TARGET` goes 12.0 → 13.0 in all four Xcode projects, the
macOS 12 fallback branches come out of the code, and the docs/templates that
advertise macOS 12 get corrected. Nothing else changes behaviour.

## Why do this

1. **The SSH tunnel XPC migration needs it.** `NSXPCListener`'s
   `setConnectionCodeSigningRequirement:` is `API_AVAILABLE(macos(13.0))`. On
   12.0 there is no supported peer-validation equivalent — `auditToken` is not
   public API and pid lookup is racy — so Step 4 of the XPC plan degrades to
   "keep the easily-bypassed environment hash". At 13.0 it becomes a real
   authenticated channel. This is the single biggest payoff and the reason to
   do the bump *before* the XPC work, not after.
2. **SwiftUI fallbacks disappear.** `formStyle(.grouped)` and
   `Table`'s `contextMenu(forSelectionType:primaryAction:)` are both macOS 13.
   Today each is wrapped in an availability gate with a hand-written macOS 12
   substitute — including a `ZStack` + `simultaneousGesture(TapGesture(count: 2))`
   re-implementation of double-click-to-edit in `SARecordView`. All of that
   deletes.
3. **Swift language features become usable**: `Regex`/regex literals,
   `Duration` + `ContinuousClock` + `Task.sleep(for:)`, the newer `URL`
   path APIs. None are needed today; they stop being off-limits for new code.
4. **macOS 12 has been out of Apple security support since September 2024.**
   We are shipping a database client — one that stores credentials in the
   Keychain and opens SSH tunnels — to an OS that no longer receives patches.

### What this does *not* unlock

Worth stating so nobody plans around it: **`@Observable` is macOS 14**, so the
per-property invalidation tracking noted in `modernization-followup-plan.md`
§ Phase C and `AGENTS.md` stays blocked. Same for `NSViewController.loadViewIfNeeded()`
(`SPMCPPreferencePane.swift:219`) and native menu section titles
(`SPTableContent.m:5135`). If the appetite exists for a bigger jump, **13 → 14
is where the SwiftUI modernization payoff actually is**; 13 buys the XPC
security win and tidies two views. Recommend proceeding with 13 as asked, but
the decision is worth taking with that comparison in hand.

### Decision inputs to gather before starting

- **macOS 12 install share from App Store Connect analytics.** Do not guess
  this — pull the real number. If it is non-trivial, the bump still happens but
  the release notes and the readme fallback line matter more.
- **Which release line lands it.** This is a user-visible compatibility break;
  it belongs in a minor bump (5.6.0), not a patch, and it needs a CHANGELOG
  entry and a release-note line.

## Inventory — everything that mentions 12.0

### Xcode build settings (36 occurrences, 4 projects)

| Project | Occurrences |
| --- | --- |
| `sequel-ace.xcodeproj/project.pbxproj` | 20 |
| `Frameworks/SPMySQLFramework/SPMySQLFramework.xcodeproj/project.pbxproj` | 10 |
| `Frameworks/QueryKit/QueryKit.xcodeproj/project.pbxproj` | 4 |
| `Frameworks/libmysqlclient/libmysqlclient.xcodeproj/project.pbxproj` | 2 |

These are project-level *and* per-target overrides across the Debug / Release /
Distribution / Beta configurations (app, Unit Tests, QLGenerator, tunnel
assistant, `xibLocalizationPostprocessor`, PSMTabBar). A blanket
`sed -i '' 's/MACOSX_DEPLOYMENT_TARGET = 12.0;/MACOSX_DEPLOYMENT_TARGET = 13.0;/g'`
over the four `project.pbxproj` files is correct here — there is no config that
should stay behind — but open the project in Xcode afterwards to confirm no
target silently picked up an inherited value instead.

### The standalone dylib build script (6 occurrences)

`Frameworks/libmysqlclient/build-libmysqlclient.sh` sets the minimum three
times per architecture — `MACOSX_DEPLOYMENT_TARGET`,
`-DCMAKE_OSX_DEPLOYMENT_TARGET`, and `-mmacosx-version-min` in
`CMAKE_CXX_FLAGS` — for the arm64 and x86_64 passes. It is not run by CI or by
any Xcode build; it is the recipe for regenerating the *committed*
`libmysqlclient.24.dylib`. Bump it anyway, or the next regeneration silently
produces a macOS 12 dylib again. The 11 → 12 bump moved this script for the
same reason.

This does **not** rebuild the dylib — see *Explicitly out of scope*. The
committed binary keeps whatever minimum it was built with until someone runs
the script; a dylib with a lower minimum loads fine on 13.

### Code that deletes

- `Source/Controllers/MainViewControllers/ConnectionView/SAConnectionFormView.swift:619-629`
  — the whole `SAGroupedFormStyle` `ViewModifier` goes; call sites apply
  `.formStyle(.grouped)` directly.
- `Source/Views/SARecordView.swift:202-216` — drop the `else` branch; the
  `contextMenu(forSelectionType:primaryAction:)` version becomes the only path.
- `Source/Views/SARecordView.swift:236-256` — drop the `ZStack` +
  `simultaneousGesture` double-click fallback in the "Value" `TableColumn`;
  keep the plain `Text` + `lineLimit`/`truncationMode` branch.
- `Source/Other/Data/SPConstants.h:756` — `is_big_sur()` has **no call sites**
  anywhere in the tree. Dead since the 11 → 12 bump; remove it in this sweep.

### Code that stays (do not over-delete)

- `SAPrintUtility.swift:63/99/182` and `UnitTests/SAPrintUtilityTests.swift:108/207`
  gate on **13.3**, not 13.0. macOS 13.0–13.2 are still in range, so every one
  of these checks remains live and correct.
- `SALocalNetworkPermissionChecker.swift:13` and `SPConnectionController.m:3947/3956`
  gate on 15.0. Untouched.

### Comments and prose

- `Source/Views/SPSplitView.m:475` — "this app targets macOS 12" → 13.
- `AGENTS.md:6` — "Deployment target is macOS 12+." → 13+, plus an explicit
  rule for agents: 13 APIs need no gate, and any `@available`/`#available`
  in this codebase should name 13.1 or later.
- `AGENTS.md:31` and `:40` — the `@Observable`/`@Bindable` notes say "blocked on
  the 12.0 target"; reword to 13.0 (still blocked, different number).
- `Source/Views/SARecordView.swift:141-142` — the `validatedEditDraft` comment
  calls itself "the macOS 12 equivalent of the `@Bindable` + subscript pattern".
  Same rewording.
- `docs/development/modernization-followup-plan.md:341, 499, 506` — the three
  "target is 12.0" notes.
- `docs/development/ssh-tunnel-xpc-migration-plan.md:72, 182, 189-190, 282` —
  rewrite Step 4 to require 13 unconditionally and delete the macOS 12
  degradation path and the open question.

### User-facing and process

- `readme.md:17` — `**macOS:** >= 12.0` → `>= 13.0`.
- `docs/index.md` — the public docs site states no system requirements at
  all today. Add a short Requirements block under Installation so the
  compatibility floor is visible somewhere other than the readme.
- `readme.md:25-27` — add a fallback line in the existing house style, naming
  the last *production* release that shipped with macOS 12 support. That is
  `production/5.4.0-20109`; 5.5.0 is still on a beta tag when this lands, so it
  is not a link to hand a Monterey user. Follow the shape of the existing
  4.1.7 / 3.5.2 / 2.3.2 notes.
- `.github/pull_request_template.md:23` — drop the `12.x (Monterey)` checkbox.
  The issue templates ask for a free-text "macOS Version" and `SECURITY.md`
  defers to the readme, so neither needs an edit.
- `fastlane/lib/sequel_ace_release/cli.rb:1478` — drop `12.x (Monterey)` from
  the generated release-PR body. **Note the drift**: this template still stops
  at `15.x (Sequoia)` while the PR template already lists 26.x and 27.x. Bring
  the two back in sync in the same edit. There are no fastlane tests asserting
  on the template text, so nothing to update under `fastlane/test/`.
- `CHANGELOG.md` — **do not hand-edit**. `Scripts/generate-changelog.sh` builds
  it from commit subjects at release time, and an `#infra` tag routes an entry
  into `### Changed`. The commit subject *is* the changelog line, so write it
  to read as one.

### Version policy

Dropping an OS is a breaking change, so the source version goes to **6.0.0**.

Do not hand-edit the version files. `SequelAceRelease::VersionFiles#update!`
owns all ten of them — the seven `CFBundleShortVersionString`/`CFBundleVersion`
plists, `CURRENT_PROJECT_VERSION`/`DYLIB_CURRENT_VERSION` in the three
`project.pbxproj` files, and the `SAGitHubReleaseTag` key in the app plist —
and it validates that they converge:

```sh
ruby -Ifastlane/lib -rsequel_ace_release \
  -e 'p SequelAceRelease::VersionFiles.new.update!(version: "6.0.0", build: 20111, channel: "beta")'
```

Two things make the tag key load-bearing rather than cosmetic:

- `Bundle.githubReleaseTag` (`BundleExtension.swift:66`) returns `nil` unless the
  tag's embedded version **equals** `CFBundleShortVersionString`. Bumping the
  version without the tag would silently disable the in-app update check's
  installed-release identity.
- The build moves with it (20110 → 20111) because the tag embeds the build, and
  20110 already belongs to `beta/5.5.0-20110`. Release preparation overwrites
  all of this with the Xcode Cloud-authoritative number anyway
  (`release_feasibility.yml` reads the source version back via
  `VersionFiles#current`).

**The major bump cannot be automatic.** `Version.bump` raises on anything but
`patch`/`minor`, and `Notes#recommended_bump` only ever returns those two, so
6.0.0 has to be typed explicitly at release time (`RELEASE <channel> 6.0.0`).

**Tag the PR `#removed`, not `#infra`.** Squash merging is disabled, so the
changelog and release notes classify one entry per PR from the merge commit's
PR title (`GitRepository#changes` walks `--first-parent`). `#infra` lands the
entry under Infrastructure *and* `Notes#app_store_draft` drops infra changes
entirely — so the one thing users must be told would appear nowhere in the App
Store notes. `#removed` puts it under Removed and keeps it in the draft.

The `## [5.5.0]` heading now at the top of `CHANGELOG.md` belongs to the already
tagged `beta/5.5.0-20110`. Whether that section is folded into 6.0.0 or left as
an orphan is a release-manager call, made when the release is prepared; the
changelog is regenerated then and must not be hand-edited here.

### Explicitly out of scope

- **Rebuilding the bundled dylibs.** The 11 → 12 bump rebuilt libmysqlclient /
  libssl / libcrypto in the same commit. It is not required here: a dylib with a
  12.0 minimum loads fine on 13. The existing linker warning (libssl.3/libcrypto
  built for macOS 15 against a 12 target, plus the install-name mismatch, see
  `warnings-elimination-plan.md` § Deferred) is **not fixed by this bump** and
  stays with the dependency refresh where it belongs.
- **CI.** `ci_pr_tests.yml` already runs on `macos-26` with Xcode 26.6, and
  `ci_scripts/ci_post_clone.sh` is a no-op stub. Nothing to change.
- **SPM dependencies.** Firebase 12.11, Alamofire 5.9, SnapKit 5.6, FMDB 2.7.9
  all support 12 and 13; no version moves are forced by this.
- **Adopting the new APIs.** The XPC code-signing requirement lands in the SSH
  tunnel plan, not here. This plan removes barriers; it does not build on them.

## Sequencing

**PR 1 — the bump (mechanical).** All 36 build-setting occurrences, plus
readme, AGENTS.md, PR template, fastlane template, CHANGELOG. No code deletions.
Ships green on its own; the availability gates are still valid, just redundant.

**PR 2 — the cleanup sweep.** `SAGroupedFormStyle`, both `SARecordView`
branches, `is_big_sur()`, the comment rewordings, and the three plan-doc
updates. Split from PR 1 because this one changes real view code paths in the
connection form and Record View, and deserves its own review and its own manual
pass over both screens.

**Later — adoption.** Tracked in `ssh-tunnel-xpc-migration-plan.md`; nothing to
do here beyond having removed the blocker.

Keeping these separate also means PR 1 alone is the revert target if App Store
Connect numbers come back worse than expected.

## Verification

1. **Let the compiler find the dead branches.** After PR 1, a clean build emits
   *"unnecessary check for 'macOS'; minimum deployment target ensures guard will
   always be true"* at exactly the macOS 13.0 gates. That warning list **is** the
   PR 2 work list — if it names a site this plan does not, investigate before
   deleting. It should not name any 13.3 or 15.0 site.
2. `./Scripts/build.sh tests` — full build plus unit tests, all schemes.
   `SAPrintUtilityTests` must still compile with its 13.3 guards intact.
3. Sweep for stragglers, excluding this plan (which quotes the old values
   throughout, so it matches itself):

   ```sh
   grep -rn "macOS 12\|Monterey\|12\.0" \
     --include="*.swift" --include="*.m" --include="*.h" --include="*.md" \
     --include="*.pbxproj" --include="*.sh" . \
     | grep -v "docs/development/macos-13-minimum-plan.md" \
     | grep -v "^./build/"
   ```

   What remains should be only intentional history — CHANGELOG entries, the
   readme fallback line, old release notes — plus unrelated `12.0` literals
   (view coordinates, font sizes, `compatibilityVersion = "Xcode 12.0"`).
   Note the `--include="*.sh"`: without it the sweep misses
   `build-libmysqlclient.sh`, whose `MACOSX_DEPLOYMENT_TARGET=12.0` has no
   space around the `=` and so escapes a "macOS 12" search.
4. **Manual pass on the two touched screens**, since PR 2 changes their real
   render path and neither is covered by a UI test: the connection form renders
   grouped, and Record View's context menu, double-click-to-edit, and value
   truncation all still behave.
5. Confirm the built app's `LC_BUILD_VERSION` minos is 13.0:
   `vtool -show-build-version <app>/Contents/MacOS/Sequel\ Ace | grep minos`.

## Risk

Low technically, and entirely reversible — PR 1 is a one-line-per-occurrence
revert. The real risk is user-facing and one-way in practice: macOS 12 users
stop receiving updates. The App Store handles this gracefully on its own
(Monterey users continue to be offered the last compatible build), so the only
mitigation needed is the readme fallback line and a clear release note.
