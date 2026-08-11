# Sequel Ace release operations

This directory contains release infrastructure only. It is not part of any
Xcode target, app bundle, Swift package, or shipped runtime. The canonical
entry point is:

```sh
Scripts/release-tool help
```

The GitHub workflows call the same Ruby library and locked gems. Fastlane is a
thin adapter for the App Store operations it already supports; it never chooses
a build number, creates a git branch, stages files, commits, pushes, opens a PR,
or creates a GitHub release.

## Safety model

- `main` is frozen at the approved SHA. Any movement requires a new plan.
- Only `Jason-Morcos` and `Kaspik` may dispatch a release.
- The typed confirmation is `RELEASE <channel> <version>`.
- `SA_RELEASE_AUTOMATION_ENABLED` remains `false` until every feasibility gate
  passes.
- One `sequel-ace-release` concurrency group prevents overlapping preparation,
  deployment, artifact publication, Alpha recovery, and finalization.
- The GitHub App may bypass the release PR's human-review requirement, but the
  workflow still waits for the exact release commit's `Run Tests`,
  `Release Tool Tests`, and every other observed check to finish acceptably.
- A failed tag or prerelease is preserved. Never delete, move, or reuse it.
- Secrets, App Review credentials, private-key material, and full sensitive ASC
  responses must never be written to a manifest or workflow log.
- Hosted workflows put their transient JSON/evidence paths in the checkout's
  private git exclude file, so only the allowlisted version files and changelog
  can enter a generated release commit.

## One-time GitHub setup

1. Create a dedicated GitHub App owned by the Sequel Ace organization and
   install it only on `Sequel-Ace/Sequel-Ace`.
2. Grant repository permissions: Contents read/write, Pull requests read/write,
   Actions read, Checks read, and Metadata read. Do not grant organization-wide
   access or subscribe it to events.
3. Add the App as the release PR bypass actor. Keep required status checks in
   force. If the repository cannot separately enforce checks for a bypass
   actor, the workflow's exact-head check gate is mandatory and must not be
   removed.
4. Create environment `sequel-ace-release`, restrict its deployment branch to
   `main`, and do not add a routine second approval.
5. Restrict every manual dispatch and rerun to `Jason-Morcos` or `Kaspik`.
   The workflows validate both GitHub's original `actor` and the current
   `triggering_actor`; scheduled-finalizer reruns validate the latter as well.
6. Add environment secrets:

   | Name | Value |
   | --- | --- |
   | `SA_RELEASE_GITHUB_APP_PRIVATE_KEY` | Dedicated App PEM |
   | `SA_ASC_KEY_ID` | Dedicated Team ASC key ID with the App Manager role |
   | `SA_ASC_PRIVATE_KEY` | Base64-encoded `.p8` bytes |
   | `SA_ASC_ISSUER_ID` | Team API issuer ID shown on App Store Connect's Integrations page |

   The workflows set the non-secret environment flag
   `SA_ASC_PRIVATE_KEY_BASE64=1` so `SA_ASC_PRIVATE_KEY` is decoded before use,
   and `SA_ASC_REQUIRE_ISSUER=1` so a missing Team issuer fails closed instead
   of being interpreted as an individual key. Set both flags for any guarded
   local fallback that uses the encoded Team key.

   The release App private key must remain exclusive to this protected
   environment.

7. Add protected release-environment variables:

   | Name | Initial value |
   | --- | --- |
   | `SA_RELEASE_GITHUB_APP_CLIENT_ID` | Dedicated release App client ID |
   | `SA_RELEASE_AUTOMATION_ENABLED` | `false` |
   | `SA_PRODUCTION_CLOUD_WORKFLOW_ID` | Production Xcode Cloud workflow ID |
   | `SA_ALPHA_CLOUD_WORKFLOW_ID` | Alpha Xcode Cloud workflow ID |
   | `SA_GHCR_ARCHIVE` | `ghcr.io/sequel-ace/sequel-ace-release-archive` |

8. Require both `Run Tests` and `Release Tool Tests` on `main`.
9. Confirm the GHCR package is private and linked to this repository. The
   feasibility workflow verifies this again before enabling publishing.

The GitHub App first creates the release branch at the frozen base SHA, then
uses GraphQL `createCommitOnBranch` to make the complete release commit without
custom author, committer, or signature fields. GitHub documents that commits
created by this mutation are automatically signed; the tool requires a valid
GitHub-generated signature before the PR is opened. See GitHub's documentation
for [`createCommitOnBranch`](https://docs.github.com/en/graphql/reference/mutations#createcommitonbranch),
[GitHub App workflow authentication](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow)
and [bot signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification#signature-verification-for-bots).

The shared HTTP transport automatically retries read-only `GET` requests only.
It never replays `POST`, `PATCH`, `PUT`, or `DELETE` mutations after a server or
network failure because their remote outcome may be ambiguous.

Long release-PR and feasibility-probe check polling uses the job-scoped
`GITHUB_TOKEN`. Each workflow mints a fresh release App installation token
immediately before an App-only mutation and independently refreshes it for
failure cleanup. This prevents the one-hour App-token lifetime from stranding a
PR or deterministic release branch during the two-hour check window.

Release starts require the frozen SHA to equal the workflow-dispatch `main`
SHA. Resume runs may use an older frozen SHA only after GitHub's compare API
proves that complete object ID is an ancestor of dispatch `main`; this proof
happens before any caller-selected commit is checked out or executed. The
scheduled and manually dispatched finalizer checks out the immutable trigger
SHA rather than resolving the mutable `main` branch after authorization.

All release workflows that use the private archive install ORAS 1.3.3 through
`oras-project/setup-oras` v2.0.1 pinned to commit
`1d808f7d7f6995cc68b7bf507bfe5c5446e1dc9d`. Linux-only orchestration jobs use
the checksum-pinned Linux amd64 archive; hosted-Mac feasibility and artifact
verification jobs use the checksum-pinned Darwin archive for the runner's exact
architecture. The GHCR adapter packages layers from a private temporary working
directory and passes only relative paths to ORAS. Pulls require a new or empty
real destination and validate every tar member, PAX/GNU path override, symlink,
and hard-link target before invoking the platform extractor. Extraction drops
archived ownership and permission restoration, remains transactional, requires
the archive manifest to match the separate OCI manifest layer, rejects
hard-linked control/evidence files, rejects every symlink outside `artifacts/`,
and requires artifact symlinks to resolve inside the extracted tree. Generated
publisher/finalizer state is written in a separate trusted temporary directory.
Do not disable these path controls or replace ORAS with an unpinned
package-manager install.

`.github/workflows/release.yml` deliberately stops after the exact merge, tag,
prerelease, and `cloud_running` manifest have been pushed to private GHCR. It
does not keep a macOS runner alive while Xcode Cloud builds or Apple notarizes.
`.github/workflows/release_publish.yml` runs immediately after a successful
handoff and at minutes 11 and 41 each hour. Its Linux job performs one exact
Cloud-status read and exits; it starts the protected macOS verification job only
after every required Production and Alpha run is complete and related to the
expected app build. Authorized manual recovery requires
`PUBLISH ARTIFACTS <tag>`. Pending checks are successful no-ops, not timeouts.
Production is always resolved first; a pending Production run prevents an Alpha
result from deciding the beta's fate. A completed unsuccessful Cloud run is
recorded by a separate Ubuntu job, so failure handling never allocates a Mac.

Every asynchronous continuation requires the exact release App author
`sequel-ace-release-automation[bot]`, proves that the tagged commit remains on
current `main` with no intervening release-file changes, and binds the private
App Store notes to the fixed App Store section of the approved GitHub body.
Archived continuations also compare every live GitHub asset digest with the
verifier-produced SHA-256 in the private manifest. The release starter ignores
legacy user-authored prereleases, but an unreadable App-authored handoff fails
closed instead of allowing a second release to overlap it.

## One-time Apple setup

Create a dedicated **Team API key** with the App Manager role from App Store
Connect's Users and Access > Integrations page. A Team key is intentionally
team-wide and cannot be limited to only these two apps, so its scope is broader
than the previously planned individual-user key. The guarded workflows are
hard-coded to operate on only:

- Production app `1518036000`
- Alpha app `1594104035`

Store the key ID, issuer ID, and one-time private-key download only in the
protected release environment. Configure Xcode Cloud in the UI because the
public API does not expose the built-in
Notarize post-action or the configured **Next Build Number** setting:

- **Production:** scheme `Sequel Ace Release`; start on `production/*` and
  `beta/*` tags; add the built-in Notarize post-action.
- **Alpha:** scheme `Sequel Ace Beta`; remove the every-push-to-`main` trigger;
  retain manual `main`, schedule `main` nightly at 03:00
  `America/Los_Angeles`, and start on `beta/*` tags; add the built-in Notarize
  post-action and internal TestFlight distribution.

Nightly and manual Alpha builds are tester-only App Store Connect deliveries.
They never create or update a GitHub release and their build numbers remain
informational. The `beta/*` trigger remains separate because a public beta
requires both its Production and Alpha artifacts.

After saving both workflows, manually start only Alpha from the current `main`
commit. Record that Alpha build-run ID for the feasibility workflow. Do not
manually start Production during setup.

`.github/workflows/release_finalize.yml` checks for Production prereleases at
minute 17 every six hours and also supports an authorized manual recovery run.
Its first job uses an Ubuntu runner with read-only Contents permission. It exits
successfully without loading Apple credentials when publishing is disabled or
no Production prerelease exists. Only a real candidate starts the protected
Ubuntu API job with App Store Connect and GHCR access; finalization does not
need a Mac runner.

An initial scheduled run is trusted only as immutable workflow code from
protected `main`; any rerun must be initiated by `Jason-Morcos` or `Kaspik`.
Manual dispatches validate both the original and current initiating actor. The
protected API job rechecks the enable flag and `main` ref, proves the Team key still
reads the Production app, then independently validates each candidate's exact
App Store version/build, latest-version status, phased release, tag commit,
archived manifest, and public checksums before changing GitHub. No public
webhook endpoint, relay secret store, durable event ledger, or second GitHub App
is required.

Apple’s documented API exposes every Xcode Cloud build run and its assigned
number, but not the configured next number. Therefore the planner reads the
Production **Next Build Number** from the signed-in App Store Connect UI. The
deployment receives that exact observation and reconciles it against source,
tags, App Store builds, and every API-visible intervening Production run. A
missing run or regressing value stops the release.

The API client follows Apple's documented
[Xcode Cloud build-run endpoint](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-ciworkflows-_id_-buildruns)
and binds a release run to its workflow, source tag, commit, and related App
Store build rather than selecting the newest result.

## Fastlane behavior and documentation

Use Bundler for every invocation. The supported configuration follows the
official documentation for:

- [Fastlane setup](https://docs.fastlane.tools/getting-started/ios/setup/)
- [`increment_version_number`](https://docs.fastlane.tools/actions/increment_version_number/)
- [`increment_build_number`](https://docs.fastlane.tools/actions/increment_build_number/)
- [`app_store_connect_api_key`](https://docs.fastlane.tools/actions/app_store_connect_api_key/)
- [`upload_to_app_store`](https://docs.fastlane.tools/actions/upload_to_app_store/)

The increment actions can accept explicit values, but the release tool updates
the known project/plist locations itself and verifies their exact shape. No
implicit increment is permitted. This matters because Xcode Cloud, not
Fastlane, owns the next Production build number.

`app_store_connect_api_key` receives the Team key with its required issuer ID.
`upload_to_app_store` uses platform `osx`, the exact semantic version and build,
`skip_binary_upload: true`, `skip_screenshots: true`, seven-day phased release,
and `reset_ratings: false`. Both mutating Fastlane lanes independently require
`SA_RELEASE_AUTOMATION_ENABLED=true`, so invoking Fastlane directly cannot
bypass the feasibility gate.

Submission is deliberately split:

1. `stage_app_store_release` creates/updates metadata without submitting.
2. The Ruby client attaches the exact processed build through the documented
   App Store version/build relationship.
3. The API reads back the exact localization, Promotional Text, ten complete
   screenshots, review information, selected build, schedule, rating behavior,
   and phased release.
4. Only then does `submit_app_store_release` submit for review.

If submission returns ambiguously, a separate Ubuntu recovery job polls the
exact version and selected build for up to 15 minutes; the macOS publisher does
not wait. An observed submitted state is accepted only when its selected build
still matches the canonical Production build. If Apple still does not confirm
submission, the durable `archived` handoff remains unchanged and retryable.

## Planning and approval

Fetch `main` and tags, then run a read-only plan. The notes file contains only
the exact customer-facing App Store text, without a Markdown heading.

```sh
export SA_GITHUB_TOKEN="$(gh auth token)"
Scripts/release-tool plan \
  --channel production \
  --target-version 5.3.2 \
  --base-tag production/5.3.1-20104 \
  --main-ref origin/main \
  --app-store-notes /absolute/path/to/app-store-notes.txt \
  --observed-cloud-next-build 20105 \
  --output /absolute/path/to/release-plan.json
```

Review the recommended SemVer, frozen SHA, complete change list, App Store
notes, GitHub body, observed Cloud number, and approval SHA-256. Patch is the
default for fixes and infrastructure. Any `#added` change recommends minor.
Major is never recommended automatically. A later beta for an already chosen
semantic version recommends keeping that version while comparing only with the
preceding beta. Its changelog is still regenerated cumulatively from the latest
finalized Production release tag that is an ancestor of that beta, so a later
beta cannot replace the version section with only its incremental changes.

The approval hash includes the exact UI-observed Production Cloud next build,
the resolved commits behind both the release-note comparison tag and cumulative
changelog base tag, the complete generated GitHub release-body digest, planned
RC/beta iteration, and the
authoritative-Cloud-next policy. Changing that observation, main SHA, App Store
notes, generated GitHub body, release iteration, either base tag or its resolved
commit, channel, or semantic version requires a new plan and approval. Runtime
reconciliation may advance beyond the approved observation only when every
consumed Production number has the required Cloud-run evidence.

After Jason confirms the intended PR set is merged and approves the plan, use
the private Codex skill to dispatch `.github/workflows/release.yml` with the
plan's immutable values and exact approval hash. Base64-encode the approved
App Store notes without line wrapping. That workflow ends once the immutable
private handoff is durable. Monitor `Release Artifact Publisher` for the exact
Cloud run; do not rerun `Release` merely because Cloud or notarization is still
pending.

## Build-number reconciliation

For source `S`, highest canonical build from a Production or Beta tag, highest
relevant Production ASC build, and UI-observed Cloud next number `N` (both tag
channels trigger the Production workflow; only Alpha artifact builds are
informational):

- Normal: `N` is one above the reconciled baseline.
- Self-healing: the observed `N` is a lower bound. If API-visible Production
  runs consumed `N` (or later contiguous numbers) after planning, execution
  advances to one past the highest consumed number. Every number between the
  baseline and the resulting target must have exact Production run evidence;
  the manifest records each run's ID, status, and source.
- Resume after merge: if source already equals `N`, has no tag, and Cloud has
  not consumed it, ASC has no conflicting build, and the release-preparation
  commit remains the newest first-parent commit that changed every protected
  version file and `CHANGELOG.md`, reuse it. Unrelated commits may have advanced
  `main`; the recovery approval must be planned against the exact release
  commit, and `mode=resume` is the only mode allowed to start from that ancestor.
  When that commit is the generated release-PR merge, the planner uses its
  first parent as the release-notes comparison head, reproducing the original
  change range instead of listing the release-preparation PR itself.
  Before any recovery mutation and again immediately before tagging, GitHub must
  prove that exact commit is still an ancestor of live `main` and that no
  protected release file changed after it.
- Stop: `N` regresses, an intervening Production run is absent, histories
  conflict, or the eventual Cloud build does not exactly match the tag/build.

After release-PR checks finish, the workflow performs the same reconciliation
again immediately before merge or recovered tag creation. It first force/prune
refreshes the remote tag namespace and proves the approved comparison tag still
resolves to its approved SHA, so a newly claimed build or moved tag is included
in the final reconciliation. If the target moved, it aborts before either
transition, closes the exact PR, and deletes only its verified release branch;
a fresh plan must use the newly reconciled number.

Alpha numbers never enter this calculation. A failed Alpha-only beta build may
be rerun against the same tag through
`.github/workflows/release_alpha_retry.yml`. That workflow reuses the successful
Production run, starts or reuses only an Alpha run, records the exact retry ID
in the private handoff, and exits without waiting. The artifact publisher later
requires both exact runs and both artifacts to verify without advancing source,
tag, or canonical build. If the retry workflow itself fails after validation,
it leaves the last exact failed-Alpha archive untouched so a later authorized
retry can reuse it; it may append only the constrained, idempotent explanatory
suffix accepted by the handoff validator. If that unarchived retry itself later
fails, the next authorized attempt can select its exact newer failed run while
preserving the older durable run as predecessor evidence. The successful
handoff records both IDs after independently validating the selected run's
workflow, tag, commit, and terminal failure. A failed Production build consumes
its number; an explicitly authorized `resume` creates a new RC/build and
preserves the old prerelease.

## Artifacts, App Store submission, and finalization

- Production artifacts must be universal `arm64`/`x86_64`, carry bundle ID
  `com.sequel-ace.sequel-ace`, be Developer ID signed by Moballo team
  `NKQ4HJ66PX`, pass `codesign`, `stapler`, and Gatekeeper checks, launch, remain
  alive briefly, and quit.
- Beta requires both the Production artifact and the Alpha artifact. Alpha uses
  bundle ID `com.sequel-ace.sequel-ace-beta`; its build is recorded only as
  evidence.
- Public names are generated by `ReleaseNaming`; do not rename them manually.
- The release and Alpha-retry workflows never poll Cloud to completion. They
  archive an immutable handoff and release their macOS runners. The artifact
  publisher checks once on Linux every 30 minutes (and immediately after a
  handoff), then downloads, verifies, launches, packages, and uploads on macOS
  only when the exact notarized run is ready.
- Completed unsuccessful Cloud runs are terminal and are recorded on Ubuntu.
  Architecture, signing, notarization, stapling, Gatekeeper, bundle metadata,
  or launch verification failures are also terminal. Network, runner, download,
  upload, registry, and API failures leave the remote manifest and release body
  unchanged so a later short publisher check can retry the same exact tag.
- The complete Cloud artifacts, dSYMs, zips, checksums, notes, and redacted
  manifest are pushed to the private GHCR OCI archive and pulled back for
  checksum verification using GitHub's
  [container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).
  Pulled archive contents are treated as untrusted even after authentication;
  all member paths and link targets are preflighted before extraction, control
  files must be independent regular files, hard-link aliases may exist only
  wholly inside `artifacts/`, symlinks must remain contained, and a refreshed
  `artifacts/` tree replaces the old tree rather than copying through
  archive-controlled destinations.
- Production submission preserves current nonempty Promotional Text, changes no
  screenshots, keeps ratings, enables seven-day phased release, and schedules
  the first 09:00 America/Los_Angeles instant at least 72 hours away.
- Immediately before every App Store metadata, build-selection, or review
  mutation, submission revalidates the live GitHub tag, App-authored non-draft
  prerelease, immutable body, exact public asset digests, and current-main
  ancestry against the private archived manifest.
- Beta never creates a customer App Store version.
- The six-hour finalizer changes the GitHub title, prerelease flag, and
  latest flag only after the exact ASC version is `READY_FOR_DISTRIBUTION`, the
  exact version remains Apple's latest released Production version, the exact
  build remains selected, phased release is `ACTIVE` or `COMPLETE`, and public
  asset checksums match the private manifest. It first records that validation
  under the active `finalizing` state in the private archive, and only then performs the public GitHub
  transition; an archive failure therefore leaves the prerelease discoverable
  for the next scheduled check or an authorized manual retry. Each run continues
  examining other production prereleases when one archive is missing or
  malformed. Finalization outputs and logs stay outside the pulled archive; only
  the validated evidence files and updated regular manifest are copied back.
  After the public transition succeeds, the finalizer records `live` and pushes
  that read-back evidence to the private archive. If that last archive refresh
  fails after GitHub has already transitioned, an authorized manual finalizer
  run can name the exact production tag and idempotently repair the `live`
  checkpoint; scheduled runs continue scanning prereleases only.
- The public transition always explicitly sends `draft: false`,
  `prerelease: false`, and `make_latest: true`, even when the title and
  prerelease flag already look final. It then re-reads both the exact release
  and GitHub's latest release and fails unless both identify the expected final
  release with its body and assets unchanged.
- Finalization also resolves the current production tag and requires it to
  equal the archived release commit; a moved or recreated tag cannot become
  latest.
- A failure after App Store submission preserves `submitted` or `live` state
  and never edits the checksum-protected GitHub release body. If submission had
  an ambiguous response, Ubuntu recovery reads back the exact ASC version and
  build before changing durable state. The finalizer also accepts the last
  durable `archived` manifest so a failed post-submission GHCR refresh can
  self-heal through the same exact Apple and artifact checks. If reconciliation
  itself fails or returns malformed evidence, the archive remains at its last
  authenticated checkpoint rather than being terminalized by an infrastructure
  error.
- A failure before prerelease creation persists the verified release commit
  before opening the PR. Cleanup closes any open PR and deletes the generated
  branch only when its head still matches that exact commit (or the frozen main
  SHA when commit creation did not finish). If GitHub accepted the commit but
  its mutation response was lost, read-only reconciliation requires exactly one
  child of frozen main and byte-exact allowlisted file blobs from GitHub's
  [compare-commits API](https://docs.github.com/en/rest/commits/commits#compare-two-commits)
  before cleanup, so a retry is not stranded by a stale deterministic branch.
- The same exact branch/PR and prerelease recovery steps run for a GitHub
  cancellation, preventing an operator cancel from stranding generated state.
- Once Alpha-only recovery has verified and archived both beta artifacts, a
  later release-body or handoff failure records its workflow evidence without
  downgrading the durable `archived` manifest to `failed`.

## Feasibility gate

Run `.github/workflows/release_feasibility.yml` after the GitHub environment,
App, API key, Cloud triggers, Notarize actions, and manual Alpha run are ready.
Dispatch it with both the exact Alpha build-run ID and the full source commit
SHA reported for that run. The pinned Alpha source may equal current `main` or
be an ancestor of it; setup and unrelated app PRs can land while a one-time
notarization probe is processing. The workflow proves that ancestry, then
still requires the run's exact workflow/source identity and verifies the
downloaded artifact against the version at current `main`. Do not burn another
Alpha build merely to refresh this one-time evidence to a newer commit.
It must prove:

1. The hosted Mac downloads, verifies, opens, and quits 5.3.1 (20104).
2. The Team Apple key reads both apps and both Cloud workflows.
3. The exact Alpha run exposes a downloadable Moballo-signed notarized artifact.
4. A disposable GitHub App PR uses the same GitHub-signed GraphQL commit path
   as a release, has a verified bot commit and green checks, then closes without
   merge.
5. A private GHCR push/pull has matching checksums and private visibility.

The workflow refuses to start unless `SA_RELEASE_AUTOMATION_ENABLED` is already
`false`, and it does not enable publishing itself. After every gate passes and
the GitHub/Xcode Cloud UI configuration is reviewed, manually change the
variable to `true`. This keeps a failed or partial feasibility run incapable of
enabling releases.

## Local fallback

Use Homebrew Ruby and an isolated Bundler path; do not use the system Ruby:

```sh
export BUNDLE_PATH="$(mktemp -d -t sequel-ace-release-bundle)"
export PATH="/opt/homebrew/bin:${PATH}"
/opt/homebrew/bin/bundle install
/opt/homebrew/bin/bundle exec /opt/homebrew/bin/rake -f fastlane/Rakefile test
```

The same planner, reconciler, version editor, metadata gates, and artifact
verifier work locally. Manual local notarization is not ready unless
`security find-identity -v -p codesigning` shows a usable Moballo Developer ID
Application identity. Stop rather than substituting an Apple Distribution or
development identity.
