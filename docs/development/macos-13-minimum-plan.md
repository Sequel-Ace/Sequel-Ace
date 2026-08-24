# Drop macOS 12, Raise the Minimum to macOS 13.5

> **Written 2026-08-24.** Answers the open question in
> `docs/development/ssh-tunnel-xpc-migration-plan.md` § Step 4 ("Decision
> needed: is bumping the deployment target to 13.0 acceptable?") and unblocks
> two items parked in `modernization-followup-plan.md`. Siblings:
> `warnings-elimination-plan.md`.

## Scope in one line

`MACOSX_DEPLOYMENT_TARGET` goes 12.0 → 13.5 in all four Xcode projects, the
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
4. **macOS 12 is outside Apple's security-update window.** Apple publishes no
   end-of-support dates for macOS; what it does in practice is ship security
   updates for the current major and the two before it. With macOS 26 current,
   that window is 14/15/26 — macOS 12 has been outside it for two majors, and
   macOS 13 is outside it too. Treat that as the documented *practice* it is,
   not a published cutoff; if a release note needs a specific date, check
   Apple's security-releases page rather than quoting this plan. Either way we
   are shipping a database client — one that stores credentials in the Keychain
   and opens SSH tunnels — to an OS that no longer receives patches.

### Why 13.5 and not 13.0

The floor is a point release, which is unusual, and it buys one concrete thing:
**every `#available(macOS 13.3)` gate dies too.** `WKWebView.shouldPrintBackgrounds`
landed in 13.3, so `SAPrintUtility` carried both the modern path and a
pre-13.3 stand-in that injected `-webkit-print-color-adjust: exact` as a user
script — two code paths for one checkbox, only one of which anyone tests. At a
13.0 floor both survive; at 13.5 the fallback and its tests go.

The rationale is that gate removal, not adoption data. This plan deliberately
did not collect install-share numbers (see *Decisions taken*), so it makes no
claim about how many machines sit on 13.0–13.4, nor about which point release
Ventura users have settled on. The rest of the argument is simply that 13.x as
a whole is already outside Apple's security-update window (point 4 above), so
the choice between 13.0 and 13.5 does not move anyone from a supported OS to an
unsupported one — and users below 13.5 land on the same
`production/5.4.0-20109` fallback as macOS 12 users.

### What this does *not* unlock

Worth stating so nobody plans around it: **`@Observable` is macOS 14**, so the
per-property invalidation tracking noted in `modernization-followup-plan.md`
§ Phase C and `AGENTS.md` stays blocked. Same for `NSViewController.loadViewIfNeeded()`
(`SPMCPPreferencePane.swift:219`) and native menu section titles
(`SPTableContent.m:5135`). If the appetite exists for a bigger jump, **13 → 14
is where the SwiftUI modernization payoff actually is**; 13 buys the XPC
security win and tidies two views. Recommend proceeding with 13 as asked, but
the decision is worth taking with that comparison in hand.

### Decisions taken

- **macOS 12 install share: deliberately not gathered.** The obvious input is
  App Store Connect analytics; the call was to proceed without it. An OS two
  years past its last security update gets dropped on that basis alone, and
  the number would not have changed the outcome — only how loudly the release
  notes said it. The readme fallback line and the release note carry the
  affected users either way.
- **Which release line lands it.** A user-visible compatibility break, so a
  major bump — 6.0.0. See *Version policy* below.

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
assistant, `xibLocalizationPostprocessor`, PSMTabBar). A
blanket `sed` over the four `project.pbxproj` files is correct here — there is
no config that should stay behind:

```sh
sed -i '' 's/MACOSX_DEPLOYMENT_TARGET = 12.0;/MACOSX_DEPLOYMENT_TARGET = 13.5;/g' \
  sequel-ace.xcodeproj/project.pbxproj \
  Frameworks/SPMySQLFramework/SPMySQLFramework.xcodeproj/project.pbxproj \
  Frameworks/QueryKit/QueryKit.xcodeproj/project.pbxproj \
  Frameworks/libmysqlclient/libmysqlclient.xcodeproj/project.pbxproj
```

Pass the paths explicitly — with no file arguments BSD `sed` reads stdin and
silently changes nothing. Afterwards, open the project in Xcode to confirm no
target picked up an inherited value instead.

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
- `Source/Other/Utility/SAPrintUtility.swift` — the three **13.3** gates go
  with the 13.5 floor: `shouldPrintBackgrounds` is set unconditionally in both
  `printOperation(for:)` and the accessory's `didSet`, and the
  `#unavailable(macOS 13.3)` block that injected
  `-webkit-print-color-adjust: exact` as a `WKUserScript` is deleted outright.
  That removes the second, untested rendering path for the same checkbox.
- `UnitTests/SAPrintUtilityTests.swift:108/207` — the matching `guard #available`
  and `if #available` come out, so both assertions now always run rather than
  silently passing on older systems.

### Code that stays (do not over-delete)

- `SALocalNetworkPermissionChecker.swift:13` and `SPConnectionController.m:3947/3956`
  gate on 15.0. Untouched.

### Comments and prose

- `Source/Views/SPSplitView.m:475` — "this app targets macOS 12" → 13.
- `AGENTS.md:6` — "Deployment target is macOS 12+." → 13+, plus an explicit
  rule for agents: 13 APIs need no gate, and any `@available`/`#available`
  in this codebase should name 13.1 or later.
- `AGENTS.md:31` and `:40` — the `@Observable`/`@Bindable` notes say "blocked on
  the 12.0 target"; reword to 13.5 (still blocked, different number).
- `Source/Views/SARecordView.swift:141-142` — the `validatedEditDraft` comment
  calls itself "the macOS 12 equivalent of the `@Bindable` + subscript pattern".
  Same rewording.
- `docs/development/modernization-followup-plan.md:341, 499, 506` — the three
  "target is 12.0" notes.
- `docs/development/ssh-tunnel-xpc-migration-plan.md:72, 182, 189-190, 282` —
  rewrite Step 4 to require 13 unconditionally and delete the macOS 12
  degradation path and the open question.

### User-facing and process

- `readme.md:17` — `**macOS:** >= 12.0` → `>= 13.5`, and the Previous Versions
  fallback line covers macOS 12 *and* 13.0–13.4.
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
   always be true"* at exactly the macOS 13.0 and 13.3 gates. That warning list **is** the
   PR 2 work list — if it names a site this plan does not, investigate before
   deleting. It should not name any 15.0 site.
2. `./Scripts/build.sh tests` — full build plus unit tests, all schemes.
   `SAPrintUtilityTests` compiles with its 13.3 guards removed.
3. Sweep for stragglers, excluding this plan (which quotes the old values
   throughout, so it matches itself):

   ```sh
   grep -rn "macOS 12\|Monterey\|12\.0\|13\.0\|13\.3" \
     --include="*.swift" --include="*.m" --include="*.h" --include="*.md" \
     --include="*.pbxproj" --include="*.sh" --include="*.rb" . \
     | grep -v "docs/development/macos-13-minimum-plan.md" \
     | grep -v "^./build/"
   ```

   What remains should be only intentional history — CHANGELOG entries, the
   readme fallback line, old release notes — plus unrelated literals (view
   coordinates, font sizes, `compatibilityVersion = "Xcode 12.0"`, the
   `API_AVAILABLE(macos(13.0))` fact about `setConnectionCodeSigningRequirement:`).

   The file filters matter more than they look. `--include="*.sh"` catches
   `build-libmysqlclient.sh`, whose `MACOSX_DEPLOYMENT_TARGET=12.0` has no
   space around the `=` and so escapes a `"macOS 12"` search entirely.
   `--include="*.rb"` catches the release tool's generated PR checklist in
   `fastlane/lib/sequel_ace_release/cli.rb`, which is a required update and
   which no other filter reaches.
4. **Manual pass on the two touched screens**, since PR 2 changes their real
   render path and neither is covered by a UI test: the connection form renders
   grouped, and Record View's context menu, double-click-to-edit, and value
   truncation all still behave.
5. Confirm the built app's `LC_BUILD_VERSION` minos is 13.5:
   `vtool -show-build-version <app>/Contents/MacOS/Sequel\ Ace | grep minos`.

## Risk

Low technically, and entirely reversible — PR 1 is a one-line-per-occurrence
revert. The real risk is user-facing and one-way in practice: macOS 12 users
stop receiving updates. The App Store handles this gracefully on its own
(Monterey users continue to be offered the last compatible build), so the only
mitigation needed is the readme fallback line and a clear release note.
