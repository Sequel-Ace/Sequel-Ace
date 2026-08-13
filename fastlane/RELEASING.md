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

- `main` is frozen at the approved SHA. Any movement requires a new plan except
  the tool's own failed release-preparation merge during a validated automatic
  forward-build recovery.
- Only `Jason-Morcos` and `Kaspik` may initiate a release. The Actions bot may
  dispatch only a chained `mode=resume` recovery authenticated against the
  failed release's private archive and original approval.
- The typed confirmation is `RELEASE <channel> <version>`.
- `SA_RELEASE_AUTOMATION_ENABLED` remains `false` until every feasibility gate
  passes.
- One `sequel-ace-release` concurrency group prevents overlapping preparation,
  deployment, artifact publication, Alpha recovery, and finalization.
- The GitHub App may bypass the release PR's human-review requirement, but the
  workflow still waits for the exact release commit's `Run Tests`,
  `Release Tool Tests`, and every other observed check to finish acceptably.
- A failed tag or prerelease is preserved. Never delete, move, or reuse it.
- New GitHub releases are temporarily created by `Jason-Morcos` for
  compatibility with installed Sequel Ace versions affected by
  [#2555](https://github.com/Sequel-Ace/Sequel-Ace/issues/2555). The dedicated
  GitHub App still creates the tag and performs every later release mutation.
- Secrets, App Review credentials, private-key material, and full sensitive ASC
  responses must never be written to a manifest or workflow log.
- Hosted workflows put their transient JSON/evidence paths in the checkout's
  private git exclude file, so only the allowlisted version files and changelog
  can enter a generated release commit.

## One-time GitHub setup

1. Create a dedicated GitHub App owned by the Sequel Ace organization and
   install it only on `Sequel-Ace/Sequel-Ace`.
2. Grant repository permissions: Contents read/write, Pull requests read/write,
   Actions read, Checks read, Metadata read, Variables read/write, and Workflows
   read/write. Do not grant organization-wide access or subscribe it to events.
   Variables write is used only to arm or clear the exact non-secret artifact
   handoff tag. GitHub requires
   Workflows write when creating or updating a release whose target commit has
   workflow files that differ from current `main`; workflows request it only in
   fresh, repository-scoped tokens used for those exact release mutations.
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
   | `SA_RELEASE_GITHUB_PUBLISHER_TOKEN` | Fine-grained PAT owned by `Jason-Morcos`, selected-repository access to `Sequel-Ace/Sequel-Ace`, and Contents read/write only |
   | `SA_ASC_KEY_ID` | Dedicated Team ASC key ID with the App Manager role |
   | `SA_ASC_PRIVATE_KEY` | Base64-encoded `.p8` bytes |
   | `SA_ASC_ISSUER_ID` | Team API issuer ID shown on App Store Connect's Integrations page |

   The workflows set the non-secret environment flag
   `SA_ASC_PRIVATE_KEY_BASE64=1` so `SA_ASC_PRIVATE_KEY` is decoded before use,
   and `SA_ASC_REQUIRE_ISSUER=1` so a missing Team issuer fails closed instead
   of being interpreted as an individual key. Set both flags for any guarded
   local fallback that uses the encoded Team key.

   The release App private key and publisher token must remain exclusive to
   this protected environment. Do not copy the publisher token to either
   release Mac. Both Macs plan and dispatch the same protected workflow, so
   their local GitHub CLI OAuth sessions never become the release publisher.

7. Add protected release-environment variables:

   | Name | Initial value |
   | --- | --- |
   | `SA_RELEASE_GITHUB_APP_CLIENT_ID` | Dedicated release App client ID |
   | `SA_RELEASE_AUTOMATION_ENABLED` | `false` |
   | `SA_PRODUCTION_CLOUD_WORKFLOW_ID` | Production Xcode Cloud workflow ID |
   | `SA_ALPHA_CLOUD_WORKFLOW_ID` | Alpha Xcode Cloud workflow ID |
   | `SA_GHCR_ARCHIVE` | `ghcr.io/sequel-ace/sequel-ace-release-archive` |

8. Add repository variable `SA_RELEASE_PENDING_ARTIFACT_TAG` with initial value
   `none`. It must be repository-scoped, rather than environment-scoped, because
   GitHub evaluates the scheduled publisher's job condition before opening the
   protected environment.
9. Require both `Run Tests` and `Release Tool Tests` on `main`.
10. Confirm the GHCR package is private and linked to this repository. The
   feasibility workflow verifies this again before enabling publishing.

The GitHub App first creates the release branch at the frozen base SHA, then
uses GraphQL `createCommitOnBranch` to make the complete release commit without
custom author, committer, or signature fields. GitHub documents that commits
created by this mutation are automatically signed; the tool requires a valid
GitHub-generated signature before the PR is opened. See GitHub's documentation
for [`createCommitOnBranch`](https://docs.github.com/en/graphql/reference/mutations#createcommitonbranch),
[GitHub App workflow authentication](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow)
and [bot signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification#signature-verification-for-bots).

### Temporary release-publisher compatibility bridge

Issue [#2555](https://github.com/Sequel-Ace/Sequel-Ace/issues/2555) showed that
already-installed Sequel Ace versions can reject GitHub's releases response
when the newest release is authored by an unfamiliar publishing identity. New
releases therefore use a deliberately narrow compatibility bridge:

- The release App validates the frozen target and creates the exact tag.
- Only the initial `POST /releases` call receives
  `SA_RELEASE_GITHUB_PUBLISHER_TOKEN`. Before that mutation, the tool reads
  `/user` and the exact repository and requires `Jason-Morcos` plus write
  access to `Sequel-Ace/Sequel-Ace`.
- Before `2027-08-14T00:00:00Z`, the create response, and any idempotently
  reused release, must report `author.login == Jason-Morcos`. The publisher
  token is absent from every artifact, failure-recovery, App Store submission,
  and finalization step.
- The protected secret is a fine-grained personal access token owned by
  `Jason-Morcos`, limited to the single repository, with Contents read/write
  and no organization permissions. Metadata read access is implicit. The
  release tag already exists, so Workflows write remains only on the short-lived
  GitHub App token that creates the tag.

GitHub documents fine-grained-token support and the Contents write permission
for [creating a release](https://docs.github.com/en/rest/releases/releases#create-a-release).
Follow GitHub's
[fine-grained PAT permission model](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens)
when provisioning the protected secret. Never print, persist, or
archive the token value.

The PAT's organization-enforced 366-day expiration is August 14, 2027. That
timestamp is also a fixed, tested publisher cutover—not an error fallback. A
missing, revoked, or invalid PAT before the cutoff stops the release. At and
after the cutoff, the workflow no longer reads the PAT and creates new releases
with the same dedicated release GitHub App that already creates tags. It
preflights the App's immutable ID `4541115`, exact Sequel Ace installation, and
repository write access, then requires the release response author to match the
App's live slug. This avoids both annual credential rotation and an accidental
early bot transition.

Release-author provenance is an immutable epoch, not a mutable allowlist:

- `production/5.4.0-20105` is the one accepted legacy release authored by
  `sequel-ace-release-automation[bot]`.
- Canonical production build 20109 and later are currently required to be
  authored by `Jason-Morcos` when their GitHub `created_at` timestamp is before
  the cutoff; those historical releases remain verifiable afterward.
- New releases created at or after the cutoff are authored by the dedicated
  release App. Both its current `sequel-ace-release-automation[bot]` slug and a
  future rename to `sequel-ace-releases[bot]` are recognized, while the stable
  App ID is the authentication authority. Recovery and finalization validate
  the immutable release creation timestamp rather than the current wall clock,
  so an early bot-authored release cannot become eligible merely because the
  cutoff date later arrives.

This automatic August 2027 cutover supersedes the earlier approximate 2028
target for removing Jason from publication. Do not renew the PAT. Remove the
expired `SA_RELEASE_GITHUB_PUBLISHER_TOKEN` secret after readback proves a
post-cutover bot-authored release, and retain every earlier provenance epoch so
archived releases remain verifiable. Renaming the existing App to
`sequel-ace-releases` is optional and must not create a second GitHub App.

The shared HTTP transport automatically retries read-only `GET` requests only.
It never replays `POST`, `PATCH`, `PUT`, or `DELETE` mutations after a server or
network failure because their remote outcome may be ambiguous.

Long release-PR and feasibility-probe check polling uses the job-scoped
`GITHUB_TOKEN`. Each workflow mints a fresh release App installation token
immediately before an App-only mutation and independently refreshes it for
failure cleanup. Every token explicitly requests only the permissions needed by
that mutation. Because `actions/create-github-app-token` 3.2.0 does not expose
GitHub's Variables permission, the fixed wake-state adapter directly requests a
short-lived installation token limited to this repository ID and exactly
`actions_variables: write`, verifies the returned repository and permission
set, and revokes the token after use. In particular, Workflows write is absent
from branch, PR, check, cleanup, and wake-state tokens and is present only on
fresh tokens used for exact-target GitHub release mutations. This prevents both
unnecessary privilege reuse and the one-hour App-token lifetime from stranding
a PR or deterministic release branch during the two-hour check window. See GitHub's
[repository-variable API](https://docs.github.com/en/rest/actions/variables#update-a-repository-variable).

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
The release tool creates and verifies the lightweight Git tag through GitHub's
Git-reference API before it publishes the prerelease. Do not let the Releases
API synthesize a missing tag: that path can publish a release without emitting
the tag-change event Xcode Cloud needs. An existing tag is reusable only when
it is a lightweight ref that resolves directly to the exact release commit.
The subsequent Releases API request repeats the complete approved commit as
`target_commitish`, even when the tag already exists. This atomically binds the
mutation to the approved target if the tag disappears between validation and
the request. GitHub requires Contents write plus Workflows write when that
target's workflow files differ from current `main`; the workflow mints a fresh,
narrow token for this one mutation. The same narrowly scoped token pattern is
used for later release-body updates and finalization. See GitHub's
[Create a release](https://docs.github.com/en/rest/releases/releases#create-a-release)
and [Update a release](https://docs.github.com/en/rest/releases/releases#update-a-release)
permission and `target_commitish` rules.
Prerelease creation is idempotent: an existing release is reused only when its
tag, title, body, draft flag, and prerelease flag exactly match the approved
release. The direct-commit tag ref is revalidated immediately before and after
both prerelease creation and reuse so a moved tag cannot be accepted. If
explicit tag creation succeeds but GitHub has no release behind
that tag, a newly approved `mode=resume` plan against the exact release commit
reuses the same canonical build. The recovery validates the missing release
and, if Cloud already consumed the tag, binds the exact Production workflow,
tag, commit, and run before recreating the prerelease; it never bumps or retags.
`.github/workflows/release_publish.yml` runs immediately after a successful
handoff and when Xcode Cloud posts either its authenticated Archive check or
terminal workflow commit status. It treats both only as wake-ups and still
validates the exact private handoff against App Store Connect. GitHub's native
[`check_run: completed` and `status` events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
supply this connection; no webhook or relay is required. A schedule at minutes
11 and 41 is retained only as lost-event or
post-notarization recovery, and its Ubuntu job is created only while repository
variable `SA_RELEASE_PENDING_ARTIFACT_TAG` contains one exact production or beta
tag. Idle schedules and unrelated Xcode Cloud checks therefore allocate no
runner and never download ORAS. The release or Alpha-retry workflow arms the
variable only after its immutable handoff is in private GHCR; terminal or
successful processing clears only that same tag, while transient failures leave
it armed. A forward-RC child replaces its exact predecessor tag in one guarded
write only after the new `cloud_running` archive is durable; the predecessor is
not cleared if forward dispatch fails. The state adapter retries transient API
failures. If arming fails or is cancelled after the durable archive exists,
cleanup preserves that discoverable `cloud_running` handoff and prerelease for
an exact manual publisher dispatch instead of marking it terminal. The Linux job performs one exact Cloud-status read and exits; it
starts the protected GitHub-hosted `macos-15` verification job only after every
required Production and Alpha run is complete and related to the expected app
build. Authorized manual recovery requires
`PUBLISH ARTIFACTS <tag>`. Pending checks are successful no-ops, not timeouts.
The immediate continuation authenticates its source by the immutable workflow
path from the `workflow_run` payload; GitHub's `workflow_run.name` contains the
dynamic `run-name` and is not an authorization identity. Xcode Cloud check
wake-ups require GitHub App ID `117084`, slug `xcode-cloud`, a terminal check,
an exact known Archive-check name, and a valid head SHA. The later workflow
status wake-up requires a terminal state, exact workflow context, matching
Production or Alpha App Store Connect target URL, valid SHA, and at least one
matching completed Archive check from the authenticated Xcode Cloud App.
Scheduled and
event discovery inspect only the exact tag held in the repository variable. An
explicitly requested ineligible tag fails. Every eligible handoff still receives
strict live validation, and any API or transport failure stops discovery while
leaving recovery armed.
Production is always resolved first; a pending Production run prevents an Alpha
result from deciding the beta's fate. A completed unsuccessful Cloud run or an
assigned Production build-number mismatch is recorded by a separate Ubuntu job,
so failure handling never allocates a Mac. A higher assignment may dispatch the
bounded forward-only RC recovery described below; a lower assignment is
terminal.

Every asynchronous continuation requires an exact publisher provenance epoch,
proves that the tagged commit remains on current `main` with no intervening
release-file changes, and binds the private App Store notes to the fixed App
Store section of the approved GitHub body. Archived continuations also compare
every live GitHub asset digest with the verifier-produced SHA-256 in the
private manifest. The release starter ignores releases outside the explicit
epochs, but an unreadable authorized-publisher handoff fails closed instead of
allowing a second release to overlap it.

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
public API does not expose the built-in Notarize post-action. The release
process does not read or trust the UI's configured **Next Build Number**:

- **Production:** scheme `Sequel Ace Release`; start on `production/*` and
  `beta/*` tags; allow manual starts for only those same tag prefixes (not
  branches or pull requests); add the built-in Notarize post-action.
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

When changing Xcode Cloud start conditions through the App Store Connect API,
read the complete workflow first and send every start-condition field that must
remain enabled in the same update. Apple treats those attributes as a set; a
partial update that supplies only `manualTagStartCondition` can clear the
existing `tagStartCondition`. Always read back both conditions before creating
a release tag.

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
number, but not the configured next number. The deployment therefore derives
the expected Production build as one greater than the highest build observed
across canonical tags, the Production app in App Store Connect, and Production
workflow runs. It never accepts a caller-entered or UI-observed build number.
If the exact tagged run is assigned a higher number anyway, that authenticated
run proves the Cloud counter jumped and can never move backward. The failed RC
is preserved and a new RC advances to at least the assigned number plus one.

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
  --output /absolute/path/to/release-plan.json
```

Review the recommended SemVer, frozen SHA, complete change list, App Store
notes, GitHub body, forward-only build policy, and approval SHA-256. The exact
candidate build is derived later inside the protected workflow using the Team
App Store Connect key. Patch is the default for fixes and infrastructure. Any
`#added` change recommends minor.
Major is never recommended automatically. A later beta for an already chosen
semantic version recommends keeping that version while comparing only with the
preceding beta. Its changelog is still regenerated cumulatively from the latest
finalized Production release tag that is an ancestor of that beta, so a later
beta cannot replace the version section with only its incremental changes.

The approval hash includes the resolved commits behind both the release-note
comparison tag and cumulative changelog base tag, the complete generated GitHub
release-body digest, and the
`highest-observed-production-build-plus-one-forward-only-v1` policy. Changing
the frozen main SHA, App Store notes, generated GitHub body, either base tag or
its resolved commit, channel, semantic version, or build policy requires a new
plan and approval. The RC/beta iteration is runtime naming state rather than an
approved product input, so an authenticated forward recovery can create RC 2
without weakening or regenerating the original approval.

After Jason confirms the intended PR set is merged and approves the plan, use
the private Codex skill to dispatch `.github/workflows/release.yml` with the
plan's immutable values and exact approval hash. Base64-encode the approved
App Store notes without line wrapping. That workflow ends once the immutable
private handoff is durable. Monitor `Release Artifact Publisher` for the exact
Cloud run; do not rerun `Release` merely because Cloud or notarization is still
pending.

## Build-number reconciliation

For source `S`, let `H` be the highest build observed across canonical
Production/Beta tags, the Production app's App Store Connect builds, and the
Production workflow's API-visible runs. Both tag channels trigger the
Production workflow; Alpha artifact numbers are never included.

- Normal: the protected Ruby reconciler derives the explicit candidate as
  `H + 1`. Fastlane lanes never calculate or increment it, and workflow inputs
  cannot override it.
- Forward self-healing: if source or a prior failed RC is behind `H`, advance to
  `H + 1`. The manifest records all source values, the highest exact Cloud run,
  the expected target, actual consumed runs, and any unassigned gap made
  permanently unusable by a later Cloud assignment or Production ASC build.
- Result verification: the publisher finds the exact run by workflow, tag, and
  commit before comparing its assigned number with the canonical tag build. A
  match continues normally. A lower assigned number is a fatal regression and
  can never trigger recovery. A higher number immediately becomes durable
  forward-jump evidence; the current tag and prerelease remain failed and
  immutable.
- Automatic RC recovery: after durable failure evidence is archived, a
  short-lived Ubuntu job revalidates the failed tag, release-App author, empty
  asset set, unchanged release commit at current `main`, immutable body/notes,
  original approval hash, and `assigned > expected`. Only then may the job's
  narrowly scoped `GITHUB_TOKEN` (`actions: write`) dispatch `Release` in
  `mode=resume`. GitHub documents that
  [`workflow_dispatch` triggered by `GITHUB_TOKEN` creates a new run](https://docs.github.com/en/actions/concepts/security/github_token#when-github_token-triggers-workflow-runs).
  The chained run recalculates `H + 1`, creates
  a new release PR and RC iteration, and carries predecessor evidence forward.
  Recovery is capped at three chained attempts to prevent an uncontrolled
  loop. It never deletes, retags, or reuses the failed RC.
- Resume after merge: if source already equals `H + 1`, has no tag, and Cloud
  has not consumed it, ASC has no conflicting build, and the release-preparation
  commit remains the newest first-parent commit that changed every protected
  version file and `CHANGELOG.md`, reuse it. Unrelated commits may have advanced
  `main`; the recovery approval must be planned against the exact release
  commit, and `mode=resume` is the only mode allowed to start from that ancestor.
  The recovery job executes the immutable workflow/tooling revision at the
  authenticated dispatch SHA on protected `main`, so a recovery-only fix can be
  used without changing the frozen release approval. Planning, build
  reconciliation, protected-file validation, and the eventual tag target stay
  pinned to the exact approved release commit.
  When that commit is the generated release-PR merge, the planner uses its
  first parent as the release-notes comparison head, reproducing the original
  change range instead of listing the release-preparation PR itself.
  Before any recovery mutation and again immediately before tagging, GitHub must
  prove that exact commit is still an ancestor of live `main` and that no
  protected release file changed after it.
- Resume after tag: if the exact lightweight release tag resolves to the newest
  release-preparation commit but its GitHub release is absent, `mode=resume`
  reuses the source build. Cloud may either still report that build as next or
  have exactly one run for it; the latter must identify the Production
  workflow, exact tag, exact commit, and no later Production run. Any existing
  GitHub release, mismatched tag/run, App Store build ahead of source, or Cloud
  advancement beyond that one exact run aborts recovery.
- Stop: source is ahead of `H + 1`, histories conflict, an exact tagged run is
  assigned below its canonical build, the recovery chain is malformed, main
  changes after the failed release commit, assets already exist, or the bounded
  recovery limit is reached.

After release-PR checks finish, the workflow performs the same reconciliation
again immediately before merge or recovered tag creation. It first force/prune
refreshes the remote tag namespace and proves the approved comparison tag still
resolves to its approved SHA, so a newly claimed build or moved tag is included
in the final reconciliation. If the target moved, it aborts before either
transition, closes the exact PR, and deletes only its verified release branch.
The original approval remains valid for a later authenticated forward recovery;
unrelated changes to `main` still require a fresh plan.

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
its number. Ordinary build failures remain preserved for an explicitly
authorized resume; only a proven higher-number assignment receives the bounded
automatic RC recovery described above.

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
  archive an immutable handoff and release their Ubuntu runners. Xcode Cloud's
  authenticated GitHub check or terminal workflow status wakes the publisher; the
  repository-variable-gated 30-minute schedule is recovery only. The publisher
  checks once on Linux, then downloads, verifies, launches, packages, and
  uploads on GitHub-hosted macOS only when the exact notarized run is ready.
- Completed unsuccessful Cloud runs are terminal and are recorded on Ubuntu.
  An exact Production run with a different assigned number is also classified
  there before completion: higher invokes the authenticated forward-recovery
  path, while lower remains terminal. Architecture, signing, notarization,
  stapling, Gatekeeper, bundle metadata,
  or launch verification failures are also terminal. Network, runner, download,
  upload, registry, and API failures leave the remote manifest and release body
  unchanged and leave the exact wake tag armed so the next Xcode event or short
  recovery check can retry it.
- Optional GitHub failure/recovery annotations verify that the remote tag names
  the exact archived release commit both before and after the edit, require the
  tag to exist, and send that commit as their target. An absent or moved tag
  therefore fails closed instead of being recreated from current `main`.
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
  mutation, submission revalidates the live GitHub tag, authorized-publisher
  non-draft prerelease, immutable body, exact public asset digests, and
  current-main ancestry against the private archived manifest.
- Beta never creates a customer App Store version.
- The six-hour finalizer changes the GitHub title, prerelease flag, and
  latest flag only after the exact ASC version is `READY_FOR_DISTRIBUTION`, the
  exact version remains Apple's latest released Production version, the exact
  build remains selected, phased release is `ACTIVE` or `COMPLETE`, and public
  asset checksums match the private manifest. It first records that validation
  under the active `finalizing` state in the private archive, and only then
  performs the public GitHub transition; an archive failure therefore leaves the
  prerelease discoverable for the next scheduled check or an authorized manual
  retry. The GitHub update repeats both the exact tag and archived release
  commit, then revalidates the tag ref before accepting the release readback, so
  a deleted or moved tag cannot redirect the transition to current `main`.
  Each run continues examining other production prereleases when one archive is
  missing or malformed. Finalization outputs and logs stay outside the pulled
  archive; only the validated evidence files and updated regular manifest are
  copied back.
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

The GHCR probe is cleanup-sensitive: after the probe step is attempted, a
separate unconditional cleanup step finds exactly one package version carrying
only the run-specific tag and deletes it through GitHub's Packages REST API.
GitHub refuses to delete the last tagged version through the version endpoint,
so the workflow deletes the package endpoint only when two identical,
paginated inventories prove that probe is the package's sole version and sole
tag. Otherwise it deletes only the exact probe version. The workflow preserves
any earlier failure and fails unless read-back is an exact package `404` after
whole-package deletion or a live package with the probe tag absent after
version deletion. Every other read-back result remains fatal. Do not use the
OCI registry manifest-delete operation; GHCR reports that operation as
unsupported.

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
