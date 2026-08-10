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
  deployment, and finalization.
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
   `triggering_actor`; event-finalizer reruns validate the latter as well.
6. Add environment secrets:

   | Name | Value |
   | --- | --- |
   | `SA_RELEASE_GITHUB_APP_ID` | Dedicated App ID |
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
   environment. Never copy it to the public App Store webhook relay; that relay
   uses the separate, non-bypass App described below.

7. Add repository variables:

   | Name | Initial value |
   | --- | --- |
   | `SA_RELEASE_AUTOMATION_ENABLED` | `false` |
   | `SA_WEBHOOK_GITHUB_APP_BOT` | Exact separate webhook-relay App bot login, including `[bot]` |
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
event-driven finalizer checks out the immutable event SHA rather than resolving
the mutable `main` branch after authorization.

All release workflows that use the private archive install ORAS 1.3.3 through
`oras-project/setup-oras` v2.0.1 pinned to commit
`1d808f7d7f6995cc68b7bf507bfe5c5446e1dc9d`. The Darwin arm64 and amd64
download URLs and their upstream SHA-256 checksums are explicit in the workflow;
do not replace this with an unpinned package-manager install.

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
- **Alpha:** scheme `Sequel Ace Beta`; remove the every-`main` trigger; start on
  `beta/*` tags; add the built-in Notarize post-action.

After saving both workflows, manually start only Alpha from the current `main`
commit. Record that Alpha build-run ID for the feasibility workflow. Do not
manually start Production during setup.

Configure one Production-app App Store Connect webhook only after a public
HTTPS relay has been deployed and its secret is stored outside this repository.
Subscribe it to App Store version state updates. Configure the HTTPS ingress to
reject request bodies larger than 1 MiB before buffering or writing them. The
relay also needs a durable local event ledger on persistent storage, owned by
the relay user with mode `0600`. It must pass the raw request body, Apple's
`x-apple-signature` header, and that ledger path to:

```sh
export SA_ASC_WEBHOOK_SIGNATURE='<exact x-apple-signature header>'
bundle exec ruby fastlane/bin/sa-release relay-webhook \
  --payload /absolute/path/to/raw-request-body.json \
  --app-id 1518036000 \
  --event-ledger /persistent/private/app-store-events.jsonl
```

Create a **second** GitHub App for this relay and install it only on
`Sequel-Ace/Sequel-Ace`. Grant it Actions read/write and Metadata read only. Do
not grant Contents, Pull requests, Checks, Workflows, or any organization
permission; do not subscribe it to events; and never add it to a branch or
ruleset bypass list. Put its exact bot login in the repository variable
`SA_WEBHOOK_GITHUB_APP_BOT`.

The relay runtime needs `SA_ASC_WEBHOOK_SECRET`,
`SA_WEBHOOK_GITHUB_APP_ID`, and `SA_WEBHOOK_GITHUB_APP_PRIVATE_KEY`; set
`SA_WEBHOOK_GITHUB_APP_PRIVATE_KEY_BASE64=1` only if that PEM is stored as
strict base64. The powerful release App key must not be present on this host.
These values belong in the relay host's secret store, never in a file, image,
log, repository variable, or webhook response. The Ruby verifier reads at most
1 MiB plus one byte, authenticates the exact raw bytes with HMAC-SHA256,
ignores valid pings and non-live transitions, and rejects state events older
than 24 hours or more than five minutes in the future. Before making a network
request it atomically consumes each event ID and signed-body fingerprint in the
durable ledger, so duplicate deliveries cannot enqueue another run. An
ambiguous dispatch failure stays consumed and requires the authorized manual
recovery path.

The relay mints a repository-selected installation token requesting only
Actions write. It also fails closed unless GitHub reports that both the App
installation and minted token have exactly Actions write plus implicit Metadata
read, select only this repository, and subscribe to no events. It then
dispatches `release_finalize.yml` on `main`. GitHub documents that this exact
endpoint accepts GitHub App installation tokens with Actions write. See Apple's
[webhook configuration](https://developer.apple.com/documentation/appstoreconnectapi/configuring-webhook-notifications)
and [webhook management](https://developer.apple.com/help/app-store-connect/manage-your-team/manage-webhooks)
documentation and GitHub's
[workflow-dispatch endpoint](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event).

The webhook is only a wake-up signal. The workflow independently resolves the
event's exact Production App Store version and selected build, requires the
corresponding `production/<version>-<build>` tag, matches both ASC IDs to the
private manifest, and repeats all live-state, tag, build, phased-release, and
checksum validation before changing GitHub. It also requires the event version
to remain Apple's latest released Production version before GitHub can mark it
latest. Duplicate valid events inside the delivery window are therefore
suppressed by the relay ledger, while stale replays fail. A direct attempt to
invoke the finalizer must still authenticate as either the separate relay App
bot with every exact event field or an authorized human performing manual
recovery. There is no scheduled polling.

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

If submission returns ambiguously, failure recovery polls the exact version and
selected build for up to 15 minutes before recording a pre-submission failure.
An observed submitted state is accepted only when its selected build still
matches the canonical Production build.

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
App Store notes without line wrapping.

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
Production run, starts or reuses only an Alpha run, requires both artifacts to
verify, and refreshes the same private archive without advancing source, tag,
or canonical build. Its failure handler cannot edit the release or archive
unless dispatcher authorization and exact archived tag/commit validation both
completed successfully. A failed Production build consumes its number; an
explicitly authorized `resume` creates a new RC/build and preserves the old
prerelease.

## Artifacts, App Store submission, and finalization

- Production artifacts must be universal `arm64`/`x86_64`, carry bundle ID
  `com.sequel-ace.sequel-ace`, be Developer ID signed by Moballo team
  `NKQ4HJ66PX`, pass `codesign`, `stapler`, and Gatekeeper checks, launch, remain
  alive briefly, and quit.
- Beta requires both the Production artifact and the Alpha artifact. Alpha uses
  bundle ID `com.sequel-ace.sequel-ace-beta`; its build is recorded only as
  evidence.
- Public names are generated by `ReleaseNaming`; do not rename them manually.
- The complete Cloud artifacts, dSYMs, zips, checksums, notes, and redacted
  manifest are pushed to the private GHCR OCI archive and pulled back for
  checksum verification using GitHub's
  [container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).
- Production submission preserves current nonempty Promotional Text, changes no
  screenshots, keeps ratings, enables seven-day phased release, and schedules
  the first 09:00 America/Los_Angeles instant at least 72 hours away.
- Beta never creates a customer App Store version.
- The event-driven finalizer changes the GitHub title, prerelease flag, and
  latest flag only after the exact ASC version is `READY_FOR_DISTRIBUTION`, the
  exact version remains Apple's latest released Production version, the exact
  build remains selected, phased release is `ACTIVE` or `COMPLETE`, and public
  asset checksums match the private manifest. It first records that live
  validation in the private archive, and only then performs the public GitHub
  transition; an archive failure therefore leaves the prerelease discoverable
  for an authorized manual retry. Webhook events target one exact Production
  tag; manual recovery continues examining other production prereleases when
  one archive is missing or malformed.
- Finalization also resolves the current production tag and requires it to
  equal the archived release commit; a moved or recreated tag cannot become
  latest.
- A failure after App Store submission preserves `submitted` or `live` state
  and never edits the checksum-protected GitHub release body. If submission had
  an ambiguous response, cleanup reads back the exact ASC version and build
  before deciding whether the release failed. The finalizer also accepts the
  last durable `archived` manifest so a failed post-submission GHCR refresh can
  self-heal through the same exact Apple and artifact checks. If reconciliation
  itself fails or returns malformed evidence, cleanup continues recording and
  archiving the remaining failure evidence.
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
It must prove:

1. The hosted Mac downloads, verifies, opens, and quits 5.3.1 (20104).
2. The Team Apple key reads both apps and both Cloud workflows.
3. The exact Alpha run exposes a downloadable Moballo-signed notarized artifact.
4. A disposable GitHub App PR uses the same GitHub-signed GraphQL commit path
   as a release, has a verified bot commit and green checks, then closes without
   merge.
5. A private GHCR push/pull has matching checksums and private visibility.
6. The separately installed webhook App reports only Actions write plus
   Metadata read, selected-repository installation, and no event subscriptions;
   the deployed relay accepts Apple's signed ping without dispatch, persists
   its mode-0600 ledger across restart, and suppresses a duplicate signed test
   event. A controlled relay workflow dispatch while publishing is disabled
   must identify the relay bot correctly and stop at the disabled-release gate.

The workflow refuses to start unless `SA_RELEASE_AUTOMATION_ENABLED` is already
`false`, and it does not enable publishing itself. After every gate passes and
the GitHub/Xcode Cloud UI configuration and the manual relay checks above are
reviewed, manually change the variable to `true`. This keeps a failed or
partial feasibility run incapable of enabling releases.

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
