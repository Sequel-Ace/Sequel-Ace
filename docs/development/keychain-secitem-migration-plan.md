# SPKeychain → SecItem Migration Plan

> **Drafted 2026-08-30.** This is the design the warnings plan deferred to
> ("SPKeychain SecKeychain* API — highest risk item in the codebase; needs its
> own design"). Siblings: `warnings-elimination-plan.md` (this project owns 10
> of its remaining 20 warning lines), `ssh-tunnel-xpc-migration-plan.md` (open
> question 3 there asks for the sequencing decision made here),
> `modernization-followup-plan.md`, ground rules in `AGENTS.md`.

## Why this is the highest-risk file in the codebase

`Source/Other/Keychain/SPKeychain.m` (387 lines, unchanged in shape since the
Sequel Pro era, one method already on `SecItem*`) is the sole owner of every
saved MySQL and SSH password. It had **zero tests** before this plan's Step 1. Its wire format — the
service/account strings under which items are stored — is persisted in users'
login keychains, so any behavioural drift silently orphans passwords
(issue #1253 shows how sensitive users are to exactly that failure mode), and
the #2491 keychain-handoff regression shows the integration surface is easy to
break. It compiles into **two targets**: the app and `SequelAceTunnelAssistant`
(the SSH askpass helper), which is why the deprecated ACL machinery exists at
all.

Deprecated API in use (all deprecated as of macOS 12 / 10.15):

| API | Sites |
|---|---|
| `SecKeychainItemCreateFromContent` | :116 (add) |
| `SecKeychainFindGenericPassword` | :158 (get), :205 (delete), :278 (update) |
| `SecKeychainItemFreeContent` | :180 |
| `SecKeychainItemDelete` | :217 |
| `SecKeychainItemModifyAttributesAndData` | :314 |
| `SecTrustedApplicationCreateFromPath` ×2, `SecAccessCreate` | :86-91 (add-path ACL) |

→ the "SecKeychain (10 unique lines)" block in the warnings plan's floor.

## Current behaviour that must not change (the wire format)

These four format strings are the keychain wire format. They are persisted in
every user's login keychain and are also constructed *outside* SPKeychain
(`SAConnectionInfo+ConnectionString.swift` builds lookups through the same
methods; `.spf` files store the resulting name/account strings verbatim):

| Helper | Format |
|---|---|
| `nameForFavoriteName:id:` | `Sequel Ace : %@ (%lld)` |
| `accountForUser:host:database:` | `%@@%@/%@` (nil database → empty) |
| `nameForSSHForFavoriteName:id:` | `Sequel Ace SSHTunnel : %@ (%lld)` |
| `accountForSSHUser:sshHost:` | `%@@%@` |

Plus storage attributes: generic-password class, service = name, account =
account, label = name (or explicit label), and the legacy
`kSecGenericItemAttr` = `"application password"` (20 bytes). New items get an
ACL trusting the app + the tunnel assistant.

Behavioural quirks callers currently rely on:

- `addPassword:` **silently no-ops if the item already exists** — callers
  branch on `passwordExistsForName:` and use the update path instead.
- `updateItemWithName:...password:` recovers from `errSecItemNotFound`
  (-25300) by delete+add, and from `errSecDuplicateItem` (-25299) by deleting
  the *destination* and retrying.
- `getPasswordForName:` returns nil (not empty) for a missing item.
- `init` returns **nil** when `LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN` is set
  (issue #2437) — keychain access disabled wholesale.
- All name/account inputs are validated as non-nil + non-empty
  (`isValidName:acount:` [sic]); helpers return nil on invalid input.

## Known and suspected defects (to be pinned or fixed in Step 1/2)

Found by reading; Step 1's characterization tests confirm each before Step 2
fixes it. Every fix is its own commit with a test that fails first.

1. **`updateItemWithName:account:toPassword:` scrambles its arguments**
   (:260): it forwards `toName:password account:name password:account` — i.e.
   renames the item to the *password*, sets the account to the *name*, and
   stores the *account* as the secret. Currently dead (all four call sites in
   `SPConnectionController.m` use the five-arg form), but it is a public
   method one refactor away from destroying a user's keychain item. Delete it
   (preferred — it has no callers) or fix + test it.
2. **nil password → `strlen(NULL)` crash** in the five-arg update (:314). The
   attribute lengths guard `newName`/`newAccount` against nil but the password
   is dereferenced unguarded. Callers happen to guard today.
3. **`SPKeychain()` from Swift crashes when keychain access is disabled.**
   The unannotated ObjC `init` imports as `init!`; with
   `LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN` set it returns nil and the unguarded
   Swift call sites (`SAConnectionInfo+ConnectionString.swift:146/206`,
   `SAConnectionWindowController`) trap on first use. The nil-returning-init
   pattern is also invisible at every ObjC call site (messages to nil just do
   nothing — quietly skipping password saves). Needs an explicit design: a
   disabled-mode null object, not a nil init.
4. **`NSAlert runModal` from non-main threads**: add/update failure paths run
   modal alerts directly (:130, :294, :328), and connection setup calls these
   from background threads. AppKit off-main — undefined behaviour that has
   presumably survived by rarity of the error paths.
5. **Password read truncates at an embedded NUL** and returns nil for
   non-UTF-8 data (:172-177 `strncpy` + `stringWithCString:`). Edge case;
   decide (probably: pin as-is for parity, since a password that survived a
   round-trip can't contain NUL anyway — the write path's `strlen` truncates
   it first. Document *that* instead).
6. **`favoriteId` coerced via `longLongValue`** — a non-numeric id becomes
   `(0)` in the item name. Pin as characterization (changing it would orphan
   existing items).

## The design decision

### Rewrite in Swift — yes

Per AGENTS.md this isn't optional: new code is Swift. New type
`SAKeychain` (`@objc final class SAKeychain: NSObject`), plus a protocol
(`SAKeychainProviding`) so call sites and tests can inject. The four
name/account helpers move to a **pure** `SAKeychainNaming` struct (no
Security framework, compiles into the Unit Tests target unconditionally, same
pattern as `SAConnectionFormHelpers`) — SPKeychain/SAKeychain delegate to it,
and the Swift call sites that today instantiate `SPKeychain` just to compute
names can use it directly.

### Which keychain — stay on the file-based login keychain (for now)

Two candidate stores for the `SecItem*` rewrite:

**A. File-based login keychain** (`SecItem*` calls with no
`kSecUseDataProtectionKeychain`): the same physical store the legacy API
writes. Existing items are found, read, updated and deleted **in place — zero
data migration**. Item ACLs are preserved by `SecItemUpdate`. Unit-testable
without code signing. This is the chosen target.

**B. Data-protection keychain** (`kSecUseDataProtectionKeychain: true` + the
`$(AppIdentifierPrefix)com.sequel-ace.sequel-ace` access group already in the
app's entitlements): the fully modern store, no ACLs, no prompts ever. Ruled
out for this project because:

- The tunnel assistant reads passwords **directly** from the keychain
  (`SequelAceTunnelAssistant.m:97`) and its sandbox entitlement is
  `com.apple.security.inherit`, which (per App Store sandbox rules) must not
  be combined with additional entitlements — so it can never carry the
  keychain access group and could never read a DP-keychain item.
- The unit-test runner builds with `CODE_SIGNING_ALLOWED=NO`; DP-keychain
  calls fail with `errSecMissingEntitlement` from an unsigned process, so the
  entire storage layer would be untestable by exactly the tests this plan
  exists to add.
- It requires a real one-shot data migration of every user's saved passwords —
  the single most dangerous operation available to this codebase — for zero
  user-visible benefit.

Moving to B stays possible later (Step 6 records what it would take); nothing
in this plan burns that bridge.

### The ACL problem, and the tunnel assistant

The one thing `SecItem*` on the file keychain **cannot** do is reproduce the
trusted-application ACL: `SecAccessCreate`/`SecTrustedApplication*` have no
modern equivalent. Items created by `SecItemAdd` are readable only by the
creating app; the assistant reading such an item triggers a user-facing
keychain prompt (or a denial). So the migration forks on one question: *does
the assistant keep reading the keychain itself?*

Answer: **no — retire the assistant's direct keychain read (Step 3).** The
plumbing for the alternative already exists: in "ask UI" mode the assistant
already fetches the password from the app over the DO channel
(`getPasswordWithVerificationHash:`), and the keychain mode is merely an
optimization that bypasses the app. Change `SPSSHTunnel` so keychain-backed
connections resolve the password app-side at connect time and serve it over
the same in-memory path. Consequences:

- No ACL is ever needed again → `SecAccessCreate`/`SecTrustedApplication*`
  deleted, not migrated.
- `SPKeychain.m` leaves the SequelAceTunnelAssistant target → the dual-target
  warning duplication disappears, and the assistant loses its Security
  dependency entirely.
- This is the same step whether the channel is today's DO or the future XPC —
  which **answers the XPC plan's open question 3**: the two projects no longer
  care about ordering. If XPC lands first, its Step 1 (narrow the vended
  surface) simply has one fewer password mode to carry; if this lands first,
  the XPC migration inherits a smaller matrix (its manual test row 2/3,
  "assistant never contacts the app", collapses into row 1).
- Security note for the PR: the SSH password now transits the DO channel in
  keychain mode too. That channel already carries it in every other mode with
  the same verification-hash check, and hardening the channel itself is the
  XPC project's job. Net exposure change ≈ 0; the XPC plan's threat analysis
  already treats the channel as the thing to fix.

## Steps

Ground rules apply throughout: one focused PR per step, behaviour-preserving
except where a step names the change, full suite green, `#infra` tag.

### Step 0 — Test harness for keychain-touching tests

Decide and build the isolation strategy once, before any test exists:

- Tests run against the **real login keychain** of the machine, under a
  unique per-run namespace: service names prefixed
  `Sequel Ace Test <UUID> :` via the same naming helpers, so nothing can
  collide with real user items. `tearDown` deletes every item it created
  *and* a defensive sweep deletes any leftover `Sequel Ace Test` items from
  aborted runs.
- Items the test process itself created read back without ACL prompts, so
  this is prompt-free locally and on CI (GitHub Actions runners have an
  unlocked login keychain; a `SecKeychainGetStatus`-free probe — write one
  item, read it back — gates the suite with `XCTSkip` on any machine where
  the keychain is locked or unavailable, e.g. some SSH sessions).
- The suite must also pass with `LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN` **unset**
  — the init guard means these tests construct the store *after* asserting
  the env var is absent, and one dedicated test covers the guard itself.
- These tests live in a new `UnitTests/SAKeychainStoreCharacterizationTests.swift` (naming
  says what it is; "integration-ish" unit tests). Pure-logic tests (naming,
  validation) go in ordinary suites and never touch the keychain.

### Step 1 — Characterization tests for the current implementation

Pin `SPKeychain` exactly as it behaves, bugs and all (a characterization test
asserts current behaviour; where the behaviour is a defect the test carries a
comment naming the Step 2 fix that will flip it). Every *testable* defect is
confirmed this way — the one crasher (nil password, defect 2) cannot be
pinned as a passing test, so it is asserted post-fix in Step 2 instead:

- **Naming helpers, byte-exact** (pure, no keychain): all four format
  strings, nil/empty rejection matrix, `longLongValue` coercion including the
  non-numeric → `(0)` case, nil-database → trailing `/`.
- **CRUD round-trips** against the harness namespace: add → exists → get →
  delete → gone; get for missing item returns nil; add with existing item is
  a silent no-op (password unchanged); add stores service/account/label/
  generic-attr as documented (verified via `SecItemCopyMatching` with
  `kSecReturnAttributes`).
- **Update paths**: five-arg rename+repassword moves the item (old
  name/account gone, new present, password readable); the -25300 fallback
  (update of a missing item creates it); the -25299 fallback (update onto an
  existing destination replaces it).
- **Unicode/edge payloads**: multibyte UTF-8 passwords and service names
  round-trip; empty password; very long password.
- **The defects**: a disabled test (or one asserting the *buggy* output, per
  taste — but it must exist) for the three-arg update scramble; nil-password
  update crash documented via an `XCTExpectFailure`-style pin is not possible
  for a crasher, so that one is asserted post-fix only; the Swift
  `init!`-nil behaviour under the env var.
- **Cross-implementation seam**: these tests are written against the
  `SAKeychainProviding` protocol surface from day one, parameterized over the
  implementation, so Step 4 reruns the identical suite against `SAKeychain`
  for free.

### Step 2 — Fix the confirmed defects in the ObjC implementation

Smallest possible diffs, each with the Step 1 test flipped from
pinned-buggy to correct:

- Delete `updateItemWithName:account:toPassword:` (no callers) — or fix the
  forwarding if review prefers keeping the API.
- Guard nil password in the five-arg update (early return + log, matching the
  class's existing style).
- Replace the nil-returning init with an explicit disabled mode: annotate the
  header nullable as an interim fix, guard the Swift call sites, and route
  "keychain disabled" through a null-object (`SAKeychainDisabled` conforming
  to the protocol, returning nil/NO everywhere) so no caller ever holds nil.
- Marshal the three failure alerts onto the main thread (or better: convert
  them to a delegate/callback the caller presents — decide by blast radius,
  smallest change wins in this step).
- Header gains `NS_ASSUME_NONNULL` + explicit `nullable` while it's open
  (same pattern as the Step 3 nullability audit in the warnings plan).

Ship this as its own PR and let it soak a release if the schedule allows —
these fixes de-risk the rewrite regardless of when the rewrite lands.

### Step 3 — Retire the tunnel assistant's direct keychain read

- `SPSSHTunnel`: in keychain mode, resolve the password via `SPKeychain` at
  connect time (app side, where the item's ACL already trusts the app) and
  hold/serve it exactly as the ask-UI path does. `SP_PASSWORD_METHOD`'s
  keychain value and `SP_KEYCHAIN_ITEM_{NAME,ACCOUNT}` env vars die.
- `SequelAceTunnelAssistant.m` loses its `SPKeychain` import and lookup
  branch; `SPKeychain.m` leaves the assistant target.
- `addPassword:`'s ACL block (`SecTrustedApplication*`, `SecAccessCreate`)
  is deleted — from this point new items need no trusted-apps list. (Reads of
  *existing* user items are unaffected; their ACLs already include the app.)
- Manual verification is the SSH matrix from the XPC plan rows 2/3/8:
  password-in-keychain connect, passphrase-in-keychain connect, keychain-miss
  → UI prompt fallback. Plus one no-regression run of ask-UI mode.
- Coordinate with the XPC branch if it is in flight; the diff is small either
  way, and whichever lands second rebases trivially.

### Step 4 — `SAKeychain`: the Swift `SecItem*` implementation

New `Source/Other/Keychain/SAKeychain.swift` (+ `SAKeychainNaming.swift`,
pure, both targets — the store itself is app-target only):

- API surface = the existing protocol, ObjC-visible, drop-in for every call
  site. Mapping: `SecItemAdd` (service/account/label + `kSecAttrGeneric` =
  `"application password"` for Keychain Access display parity),
  `SecItemCopyMatching` with `kSecReturnData`, `SecItemUpdate` (which
  preserves existing items' ACLs — this is what makes in-place operation on
  legacy items safe), `SecItemDelete`. No `kSecUseDataProtectionKeychain`
  anywhere.
- Reproduce the pinned semantics exactly: add-is-no-op-when-present, update's
  -25300/-25299 recovery branches (now spelled `errSecItemNotFound` /
  `errSecDuplicateItem`), nil-for-missing get, validation rules, disabled
  mode.
- Password encode/decode via `Data(utf8)` both ways — kills the
  `strlen`/`strncpy`/VLA edge cases outright.
- Errors surface as values (OSStatus in the log + a callback for the two
  user-facing alert cases), presented on main.
- **The proof obligation is the cross-implementation matrix**, which is the
  whole reason Step 1 parameterized the suite:
  1. identical characterization suite green against `SAKeychain`;
  2. **legacy-writes → Swift-reads**: item created via `SPKeychain` is found,
     read, updated and deleted by `SAKeychain` — this simulates *every
     existing user item on upgrade* and is the test that makes "zero data
     migration" a verified claim instead of a hope;
  3. **Swift-writes → legacy-reads**: proves downgrade safety (user runs an
     older build after this ships);
  4. attribute-level diff: dump both implementations' items via
     `SecItemCopyMatching` attributes and assert the persisted shape matches
     field-for-field (same mechanical-diff spirit as the C3
     `apply(to:)`/`_buildConnectionInfo` check — the risk is omission).

### Step 5 — Flip the call sites, delete SPKeychain

- Swap the ~8 constructing call sites (`SPConnectionController`,
  `SPDatabaseDocument`, `SPSSHTunnel`, `SAConnectionService`,
  `SAConnectionInfo+ConnectionString`, `SAConnectionWindowController`,
  export/favorites paths) to the protocol; naming-only Swift call sites move
  to `SAKeychainNaming` directly.
- Delete `SPKeychain.h/.m`. The warnings plan's SecKeychain block (10 unique
  lines) goes to zero; remaining floor is NSConnection (6) + the 4
  intentional markers.
- Manual verification matrix (once before merge, once on the release build):

  | # | Scenario |
  |---|---|
  | 1 | New favorite + save password → connect → item visible in Keychain Access with correct name/account/kind |
  | 2 | Existing (pre-migration) favorite's password auto-fills and connects |
  | 3 | Rename favorite → keychain item follows (update path), old name gone |
  | 4 | Change password on existing favorite → connects with new password |
  | 5 | Delete favorite (with "remove password") → item gone |
  | 6 | SSH favorite with saved SSH password → tunnel connects, no prompt |
  | 7 | Favorites import/export round-trip preserves password linkage |
  | 8 | `LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN=1` → keychain disabled, no crash, no saves |
  | 9 | Downgrade check: item created by the new build readable by the previous release |

- Soak one release before any follow-on keychain work, mirroring the XPC
  plan's flip-and-soak.

### Step 6 — (Deferred, recorded only) Data-protection keychain

Not part of this project. What it would take, so the option stays priced:
assistant must no longer touch the keychain (done in Step 3), a signed test
host or a manual-only test story for the storage layer, an explicit one-shot
+ lazy-fallback migration of existing login-keychain items with telemetry-free
failure accounting, and a decision on `kSecAttrSynchronizable` (today's items
never sync; silently enabling iCloud sync for database passwords is a product
decision, not a refactor).

## Risks

- **Losing user passwords** is the headline risk; the mitigations are the
  in-place store choice (no migration to get wrong), the
  legacy↔Swift cross-compat matrix in Step 4, and the downgrade row in the
  manual matrix.
- **ACL prompts**: `SecItemUpdate` preserving ACLs is what protects existing
  items. Should a code-path pair `SecItemDelete`+`SecItemAdd` where the
  legacy code updated in place, existing items would silently lose their ACL
  and, in a partial-rollout world, break the assistant. Step 3's ordering
  (assistant read retired *before* the rewrite) removes the consumer that
  cares, but the update-in-place semantics are pinned by test anyway.
- **Test flakiness against a real keychain**: mitigated by the Step 0
  namespace + skip-gate; if CI proves hostile, the keychain-touching suite
  gets an env-var opt-in like the planned B1 MySQL tests, and local runs
  remain the gate.
- **The assistant change (Step 3) touches SSH connections** — the same blast
  radius the XPC plan flags. It is deliberately its own small PR with its own
  manual matrix, and it reuses a code path (app-held password over the
  channel) that every non-keychain SSH connection exercises daily.

## Estimate

| Step | Size |
|---|---|
| 0 — harness | 0.5 day |
| 1 — characterization suite | 1–1.5 days |
| 2 — defect fixes | 0.5–1 day |
| 3 — assistant read retirement | 1 day + manual SSH matrix |
| 4 — SAKeychain + cross-compat matrix | 1.5–2 days |
| 5 — flip, delete, manual matrix | 1 day |

**~6–7 days** across 5 PRs, spread over at least two releases (Step 2 and
Step 5 each deserve soak).

## Open questions

1. **Alert UX on keychain errors** (Step 2/4): keep modal alerts (main-thread
   marshalled) or degrade to log-only with a non-modal notice? Current modal
   behaviour dates from an era when keychain corruption was common; a modal
   from a background connect flow is hostile. Default: keep behaviour in
   Step 2 (marshalled), decide properly in Step 4's review.
2. **Does CI's login keychain cooperate?** Step 0's probe answers this
   empirically on the first PR; the fallback (opt-in env var) is already
   scoped.
3. **Step 3 vs the XPC branch order** — no longer a dependency either way
   (see design section), but whichever is second rebases, so agree who goes
   first when both are in flight.
