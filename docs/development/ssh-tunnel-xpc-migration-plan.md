# SSH Tunnel IPC — NSConnection → NSXPCConnection Migration Plan

> **Status 2026-09-01: spike run, Step 1 landed, transport decided.** The
> Step 0 spike answered **no** for `NSXPCListener(machServiceName:)` under the
> sandbox and **yes** for the fallback this plan named — a UNIX domain socket
> in the container, with peer code-signing validation from the socket's audit
> token in both directions. The project therefore continues on the fallback:
> the title stays for link stability, but from Step 2 on "XPC" reads "the
> socket transport". Details and the log evidence are under Step 0 below;
> the revised Steps 2–5 follow it. Step 1 (narrow the vended surface) is
> done and is the first PR.
>
> **Written 2026-08-24.** Picks up the "NSConnection → NSXPCConnection" item
> deferred in `docs/development/warnings-elimination-plan.md` (§ Deferred).
> Pairs with the deferred SPKeychain `SecItem` migration — both touch how the
> tunnel assistant obtains passwords. Sibling: `modernization-followup-plan.md`.

## Why do this

Not for the warning. `NSConnection` is deprecated, not removed, and after
PR #2586 moved the ivar out of the public header it accounts for **12 raw
occurrences**, not 148. If this were only about the warning count it would not
be worth the risk.

The reasons that do justify it:

1. **The app vends its entire `SPSSHTunnel` object to the helper.**
   `SPSSHTunnel.m:107` does `[tunnelConnection setRootObject:self]`. Distributed
   Objects exposes *every* method on that object to whatever holds the proxy —
   `disconnect`, `setPassword:`, `launchTask:`, the lot. Only three methods are
   meant to be reachable. An `NSXPCInterface` exposes exactly the protocol you
   declare and nothing else. **This is the actual prize.**
2. **The only peer check is a shared secret in the process environment.**
   `SP_CONNECTION_VERIFY_HASH` is set on the ssh task's environment
   (`SPSSHTunnel.m:530`) and compared in `getPasswordWithVerificationHash:`.
   The code comment concedes it "is easily bypassed". Any process running as the
   same user can read another process's environment. XPC gives us peer code-signing
   validation as a real replacement.
3. **DO is one of the oldest surfaces in the app** and is a plausible candidate
   for removal in a future macOS. The channel carries SSH passwords and key
   passphrases, so being ahead of that is worth something.

Risk framing: a regression here means **users cannot connect over SSH at all**.
That is the highest-blast-radius change in this area of the codebase. The plan
below is therefore spike-first and ships behind a flag.

## How it works today

```text
Sequel Ace (sandboxed, app group NKQ4HJ66PX.sequel-ace)
  │
  ├─ SPSSHTunnel init                                    SPSSHTunnel.m:100-112
  │    NSConnection, runInNewThread, setRootObject:self
  │    registerName:"NKQ4HJ66PX.sequel-ace.SequelAce-<hash>"
  │
  └─ NSTask: /usr/bin/ssh                                SPSSHTunnel.m:521-540
       env: SSH_ASKPASS=<bundle>/SequelAceTunnelAssistant
            DISPLAY=:0
            SP_CONNECTION_NAME, SP_CONNECTION_VERIFY_HASH
            SP_PASSWORD_METHOD, SP_KEYCHAIN_ITEM_{NAME,ACCOUNT}
       │
       └─ ssh execs SequelAceTunnelAssistant "<prompt text>"   (once per prompt)
            NSConnection rootProxyForConnectionWithRegisteredName:
            → blocks on one of three calls
            → printf(answer), exit
```

The three vended methods (`SPSSHTunnel.m:783`, `:795`, `:849`):

| Method | Returns | Used for |
|---|---|---|
| `getResponseForQuestion:` | `BOOL` | host-key mismatch and other yes/no prompts |
| `getPasswordWithVerificationHash:` | `NSString *` | the SSH password held in the app |
| `getPasswordForQuery:verificationHash:` | `NSString *` | key passphrases, SecurID, anything else |

Facts that matter for the design:

- **The app is sandboxed**, app group `NKQ4HJ66PX.sequel-ace`
  (`Entitlements/Sequel Ace.entitlements`). The assistant is sandboxed with
  `com.apple.security.inherit`. The DO service name is already app-group
  prefixed — that is *why* it is allowed to register at all.
- **Deployment target is macOS 13.5.**
- **The assistant is a 5-file `com.apple.product-type.tool` target** and
  **already compiles Swift** (`StringRegexExtension.swift`). Swift in the helper
  costs nothing new.
- **The assistant imports `SPSSHTunnel.h` purely to type the DO proxy.** It does
  not compile `SPSSHTunnel.m`. Under XPC it imports a shared protocol instead,
  which severs that dependency completely.
- **The assistant blocks**: its whole job is ask → wait → `printf` → exit. Any
  replacement must preserve synchronous semantics.

## Step 0 — The spike that decides everything

**Question: can a sandboxed app vend `NSXPCListener(machServiceName:)` under an
app-group-prefixed name, with the helper connecting via
`NSXPCConnection(machServiceName:)`, without a launchd plist?**

The SDK header is explicit that `initWithMachServiceName:` is for "a named Mach
service advertised in a `launchd.plist`". App-group mach services are a
documented sandbox affordance, and it is exactly what `NSMachBootstrapServer`
(under DO) is doing today — but *that NSXPCListener accepts such a name without
launchd registration is not documented and must be proven before anything else
is built.*

Spike: throwaway branch, hardcode a name, listener in the app, connect from the
assistant, log success/failure. **Test signed-and-sandboxed, not just from
Xcode's debug build** — bootstrap registration behaves differently outside the
sandbox, and a false positive here invalidates the whole design.

Timebox: 1 day. Everything downstream branches on the answer.

### Result (2026-09-01): XPC fails, the socket fallback passes

Run on a signed, sandboxed Debug build (`com.apple.security.app-sandbox`,
app group `NKQ4HJ66PX.sequel-ace`, team `NKQ4HJ66PX`), triggered from
`applicationDidFinishLaunching` with `-SASSHTunnelXPCSpike YES`, with the
assistant launched **both** as a direct `Process` child and as ssh's real
`SSH_ASKPASS` grandchild (github.com's host-key question, answered "no").
Spike code is on the local throwaway branch `spike/ssh-xpc-step0`.

**Phase 1 — `NSXPCListener(machServiceName:)`, app-group-prefixed name, no
launchd plist: fails.** `resume()` reports nothing, but the name is never
registered — `launchctl print pid/<app>` lists no such endpoint — and both
assistant launches fail the lookup identically:

```text
The connection to service named NKQ4HJ66PX.sequel-ace.SequelAce-spike-1346
was invalidated: Connection init failed at lookup with error 3 - No such process.
```

That is `bootstrap_look_up` → `BOOTSTRAP_UNKNOWN_SERVICE`. libxpc's listener
path is `bootstrap_check_in`, which only succeeds for launchd-declared
services; there is no public API that turns a `bootstrap_register`ed port
(what DO uses) into an XPC listener, and the endpoint-in-environment route is
ruled out above. So the SDK comment is the whole truth: **a sandboxed app
cannot vend NSXPC without launchd**, app group or not.

**Phase 2 — UNIX domain socket in the sandbox container: passes, both
launch paths, both directions of peer validation.** The socket lived at
`<container>/Data/tmp/SASpike.sock` (80 bytes, under the 104-byte `sun_path`
limit); the `com.apple.security.inherit` assistant reaches it as a direct
child and as ssh's grandchild. Peer identity comes from
`getsockopt(LOCAL_PEERTOKEN)` → `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)`
→ `SecCodeCheckValidity`, and the negative case fails as it must:

```text
[app]       validate assistant identity:            validity=0      identifier=SequelAceTunnelAssistant team=NKQ4HJ66PX
[app]       validate WRONG identity (expect failure): validity=-67050 identifier=SequelAceTunnelAssistant team=NKQ4HJ66PX
[assistant] validate app identity:                  validity=0      identifier=com.sequel-ace.sequel-ace team=NKQ4HJ66PX
[assistant] validate WRONG identity (expect failure): validity=-67050 identifier=com.sequel-ace.sequel-ace team=NKQ4HJ66PX
```

(`-67050` is `errSecCSReqFailed`.) Two facts recorded for the implementation:
the assistant's code-signing **identifier is `SequelAceTunnelAssistant`**, the
product name, not its bundle identifier — it is a bare executable; and the
Beta configuration's app identifier is `com.sequel-ace.sequel-ace-beta`, so
neither side may hardcode the other's identifier. Validation is therefore
**asymmetric**: the app requires *same team as me* **and** the fixed
identifier `SequelAceTunnelAssistant`, so no other same-team process can ask
it for a password; the assistant requires *same team as me* only, because the
app's identifier varies by configuration — a same-team process that planted a
socket could at most receive a request, never a secret. The team comes from
each process's own signing information, never from a constant.

### Decision

The plan's own rule was "if the spike fails, seriously consider not
migrating at all". Measured against the three reasons at the top: reason 1
(the exposed surface) is closed by Step 1 regardless; reason 2 (peer
identity) the socket delivers **fully** — the audit-token check is the same
primitive XPC uses internally, and unlike XPC it validates the *listener*
just as easily; reason 3 (getting off DO) it delivers too. What it costs is a
wire format to own and version, which for one request and one reply per
askpass launch is small. The remaining Steps run on the socket. Everything
else in this plan — flag-first rollout, both-direction validation, the
manual matrix, the rollback default — is unchanged.

### Do not try: archiving the endpoint into an environment variable

`NSXPCListenerEndpoint` conforms to `NSSecureCoding`, which makes it tempting to
`NSKeyedArchiver` an anonymous listener's endpoint, base64 it into the ssh task
environment, and rebuild it in the assistant. **This does not work.** An endpoint
wraps a Mach send right; that coding support exists for passing an endpoint
*over an existing XPC connection*, which transfers the right. Serialising it
through a byte channel to an unrelated process does not. Recorded here so nobody
spends a day rediscovering it.

### Fallback if the spike fails

A UNIX domain socket in the **app group container**, which both processes can
reach (the assistant inherits the sandbox). Hand-rolled length-prefixed JSON, or
`NWListener`/`NWConnection` over a local endpoint.

This is strictly worse than XPC — no free peer identity, a wire format to design
and version, more code — and it forfeits reason 3 above. If the spike fails,
seriously consider **not migrating at all** and instead hardening what exists:
narrow the DO root object to a small façade so `setRootObject:` stops exposing
all of `SPSSHTunnel`. That is Step 1 below, which is worth landing on its own
merits either way.

## Step 1 — Narrow the vended surface (ships regardless of the spike) — ✅ Done

Pure refactor of *what* is vended: no IPC or transport change. The one
intentional behaviour change is teardown, which now dismisses a prompt the
assistant is blocked on and answers "no"/nil instead of leaving it blocked
(details below).

Execution notes (2026-09-01):

- `SASSHTunnelAuthService` (Swift, app **and** Unit Tests targets) is the
  root object now; `SPSSHTunnel` hands it — not itself — to
  `setRootObject:`. It exposes exactly `getResponseForQuestion:`,
  `getPasswordWithVerificationHash:` and `getPasswordForQuery:verificationHash:`
  under the legacy selectors, so the assistant is untouched and still types
  its proxy through `SPSSHTunnel.h`; the tunnel keeps those three as
  one-line forwarders so that header stays honest.
- The decisions moved with it: the hash comparison, keychain-versus-held
  password branch, stored-passphrase lookup (folded in from
  `SASSHTunnelSecretResolver`, now deleted) and the cancelled-prompt refusal.
  The tunnel supplies state and the two blocking sheets through a new
  `SASSHTunnelAuthSource` protocol (pure Foundation, so the service compiles
  into the test target without seeing `SPSSHTunnel`). Parity note kept on
  purpose: `getResponseForQuestion:` never checked the hash and still does
  not — the answer is not a secret; Step 4 covers it with peer validation.
- Lifetime, as this step demanded: the service holds the tunnel weakly and
  every call fails closed (`NO`/nil) once it is gone. `SPSSHTunnel` tracks the
  sheet it is running modally (`activePromptDialog`) and
  `cancelPendingPrompt` — called from `disconnect`, `abortTask`, and the
  ssh-exited path of `launchTask:` — dismisses it on the main thread,
  answering "no"/nil **without** setting `passwordPromptCancelled`, so the
  real failure reason still reaches `SAConnectionService` instead of being
  mistaken for a user cancel. Before this a tunnel torn down mid-prompt left
  the sheet up and the assistant blocked until ssh gave up.
  Review (Codex, CodeRabbit) caught a race in the first cut: a prompt whose
  worker had not yet reached the main thread had no dialog to dismiss, so the
  cancellation was dropped and the sheet appeared after teardown. Teardown
  now latches `promptTeardownRequested` when the answer lock is held with no
  sheet up, and both workers consume the latch — or notice ssh is no longer
  running — and answer without presenting.
- 21 unit tests in `UnitTests/SASSHTunnelAuthServiceTests.swift` against a
  fake tunnel and an in-memory keychain: question forwarding, hash
  refusal (wrong/empty/nil) on both password calls, held vs keychain-mode
  resolution and keychain miss, cancelled-prompt refusal, stored-passphrase
  served without prompting, exists-but-nil falls through to the prompt,
  non-passphrase queries never touch the keychain, key-name extraction
  edge cases, and both lifetime rules (calls fail closed after release; the
  service does not retain the tunnel).
- Pre-existing quirk noticed, deliberately not changed here:
  `requestedPassphrase` is never reset between prompts, so cancelling a
  *second* passphrase prompt in one tunnel returns the first answer again
  instead of registering the cancel. Worth its own fix once the transport
  work is done.

Introduce `SASSHTunnelAuthService` holding a weak `SPSSHTunnel` and implementing
only the three methods. Change `setRootObject:self` to `setRootObject:` that
façade. The assistant keeps importing `SPSSHTunnel.h` for now.

This is the de-risking step: it collapses the exposed API from ~30 methods to 3
*before* any transport change, and it is independently reviewable and revertable.
If the XPC work later stalls, this alone closes the worst of the exposure.

**Lifetime is part of this step, not an afterthought.** The assistant blocks
inside a prompt while the user types; `disconnect()` can clear
`SAConnectionService.activeTunnel` in that window, and a weak `SPSSHTunnel`
would go `nil` under a call already in flight. Define it explicitly: the façade
outlives every in-flight prompt, and teardown resolves blocked waiters
deterministically — `disconnect()` fails outstanding prompts closed (reply
`nil`/`false`) rather than leaving the assistant blocked until ssh times out.
Cover cancellation and app termination during *both* prompt methods; a hang
here means the user cannot connect and cannot cancel.

## Step 2 — Shared wire format

The XPC version of this step was an `@objc` protocol; on a socket the
contract is a message format instead. New file compiled into **all three**
targets (app, assistant, Unit Tests), pure Foundation:

- `SASSHTunnelAuthRequest` — one of `question(text)`,
  `password(verificationHash)`, `query(text, verificationHash)` — and
  `SASSHTunnelAuthResponse` — `answer(Bool)`, `secret(String?)`, `refused`.
- One request and one response per connection, each a single JSON object
  terminated by `\n`, carrying a `v` field (1). That is the askpass
  lifecycle exactly: ssh execs the assistant once per prompt, it asks one
  thing and exits. No framing state machine, no multiplexing.
- `SASSHTunnelAuthService` gains `handle(_ request:) -> SASSHTunnelAuthResponse`,
  a pure dispatch onto the three Step 1 methods, so the socket server is
  transport only.

Unit tests pin the JSON both ways (a recorded fixture per message so the
format cannot drift without a test changing), unknown-version rejection,
and the dispatch.

Both ends must fail **closed**: on any transport or decoding error the
assistant exits non-zero rather than print an empty line, which ssh would
read as an empty password.

## Step 3 — Socket alongside DO, behind a default

Both transports built; a hidden `NSUserDefaults` key selects. Default to DO
in the first release that contains the code, so it can be exercised by early
adopters and support can flip it without a rebuild.

App side: `SASSHTunnelSocketServer` (Swift) owns a listening UNIX socket at
`NSTemporaryDirectory()/SequelAce-ssh-<random>.sock` — the container's tmp,
which the inherit-sandboxed assistant shares — mode 0600, per-tunnel, unlinked
on teardown. Its accept loop runs on a private queue; each connection is
read, validated (Step 4), dispatched to `SASSHTunnelAuthService.handle`,
answered and closed. `SPSSHTunnel` creates it next to the `NSConnection`
when the socket transport is selected.

Assistant side: `SASSHTunnelSocketClient` (Swift) connects, validates the
peer (Step 4), writes the request, reads the reply. The argument-sniffing
decision logic — which prompt is this, which request to send, what to print,
which fallback message on a keychain miss — moves to a pure, tested
`SASSHTunnelAskpass` in Swift, compiled into the assistant **and** the Unit
Tests target. `SequelAceTunnelAssistant.m` shrinks to `main` plus the DO
shim, because `NSConnection` is unavailable from Swift; it goes with the DO
path in Step 5, when `main.swift` replaces it (this plan's earlier "convert
the assistant in Step 3" is therefore split: logic now, entry point then).

**The assistant cannot read the default.** It is a separate short-lived
process launched by ssh, so a `NSUserDefaults` key in the app decides nothing
on its own. The app resolves the selection once, when it builds the ssh
task, and passes it in that task's environment next to
`SP_CONNECTION_VERIFY_HASH` (`SP_CONNECTION_TRANSPORT`, plus
`SP_CONNECTION_SOCKET_PATH` for the socket) — the channel that already exists
and is already per-launch. A tunnel therefore uses one transport for its
whole life, and flipping the default cannot strand a running tunnel halfway.
If the socket cannot be created (a `sun_path` over 104 bytes, say) the tunnel
falls back to DO for that launch and logs it.

## Step 4 — Peer validation (the security win)

Replace the environment shared-secret as the primary check, using exactly
what the spike proved: `getsockopt(SOL_LOCAL, LOCAL_PEERTOKEN)` for the
peer's audit token, `SecCodeCopyGuestWithAttributes` with
`kSecGuestAttributeAudit`, then `SecCodeCheckValidity` against a requirement.
The audit token is the same primitive XPC's own peer validation is built on,
pid-race-free by construction, and it needs no availability gate on 13.5.

Requirements are built from each process's **own** signing information
(`SecCodeCopySelf` → `kSecCodeInfoTeamIdentifier`), never hardcoded:

| Side | Requires of the peer |
|---|---|
| app (listener) | `anchor apple generic and certificate leaf[subject.OU] = "<own team>" and identifier "SequelAceTunnelAssistant"` |
| assistant | `anchor apple generic and certificate leaf[subject.OU] = "<own team>"` |

**Validate both directions.** The listener authenticates the assistant; the
assistant authenticates whatever answered at the socket path, so a process
that planted a socket first cannot impersonate the app. A build with no
team identifier (ad-hoc or unsigned local builds) cannot express the
requirement; it logs and skips validation, keeping the environment hash —
which stays in place on every build anyway; it is free and narrows the window
further. Verification must include the **negative** test in both directions,
as the spike already did once: a wrong identity is rejected with
`errSecCSReqFailed`.

## Step 5 — Flip the default, then delete DO

Separate releases. Flip to the socket, let it soak, then remove the DO path,
the `NSConnection` ivar, the assistant's DO shim and its `SPSSHTunnel.h`
import, and replace `SequelAceTunnelAssistant.m` with `main.swift`. The
remaining `NSConnection` warnings go to zero at this point — a side effect,
not the goal.

## Swift or not

**Swift for everything new; leave `SPSSHTunnel.m` in Objective-C.**

For: the assistant already links Swift, so there is no new cost; the protocol,
listener delegate and connection plumbing are markedly cleaner in Swift; and it
matches the `SA*` direction of the codebase and the AGENTS.md Swift-only rule for
new code.

Against rewriting `SPSSHTunnel.m` itself: it is ~990 lines of NSTask
management, hand-rolled locking, run-loop threading and XIB-backed dialogs. It
is a legitimate target for a Swift rewrite, but bundling it with an IPC change
would produce a diff nobody can review and would make a connection regression
impossible to bisect. Separate project.

`SequelAceTunnelAssistant.m` → `main.swift` is in scope and worth doing: it is
~215 lines of straight-line argument sniffing, and top-level code in `main.swift`
works fine for a tool target. The logic moves to Swift in Step 3 (where it
gains tests); the entry point itself only in Step 5, because `NSConnection`
is unavailable from Swift and the DO shim has to live somewhere until DO is
deleted. One practical note for the assistant target: it has no bridging
header, so a Swift declaration reaches its generated `sequel-ace-Swift.h`
only when it is `public`.

## Verification

The real path — `ssh` deciding to exec `SSH_ASKPASS` — cannot be unit-tested
end to end; the channel underneath it can. What each layer buys:

- **Unit-testable (new)**: `SASSHTunnelAuthService` against a fake tunnel — the
  hash comparison, the keychain-vs-UI branch, nil/cancel paths. None of this is
  testable today because the logic sits on `SPSSHTunnel` behind DO. Worth
  writing in Step 1 while the transport is still the old one.
- **Integration-testable (new)**: the socket server and client are plain
  Swift, so the Unit Tests target can run both ends in-process over a socket
  in its temporary directory and cover the wire contract end-to-end,
  including the refusal paths. (Launching the real assistant binary from the
  test runner is not possible: its `com.apple.security.inherit` sandbox
  needs a sandboxed parent.)
- **Manual only**: everything involving real ssh.

Manual matrix — every row on **both** transports while Step 3 is in flight, and
on a **signed, sandboxed** build, not a debug build:

| # | Scenario |
|---|---|
| 1 | Password held in app (`SP_PASSWORD_METHOD` = AsksUI) |
| 2 | Password in keychain (app resolves the item at ask time and serves it over the channel) |
| 3 | Key passphrase in keychain (app-side pre-prompt check in `getPasswordForQuery:`) |
| 4 | Key passphrase prompted in UI |
| 5 | Host-key mismatch yes/no |
| 6 | Unrecognised prompt / SecurID fallback |
| 7 | Cancel at each of 1, 4, 5, 6 |
| 8 | Keychain lookup fails → falls back to UI prompt |
| 9 | `ProxyJump` (checks the `SHELL`-removal path at `SPSSHTunnel.m:525`) |
| 10 | Connection muxing on and off (`SPSSHEnableMuxingPreference`) |
| 11 | Two tunnels at once — distinct service names, no cross-talk |
| 12 | App quits mid-prompt; assistant must exit non-zero, not hang |

Rows 11 and 12 are the ones DO gets right by accident and a new transport can
easily get wrong.

## Rollback

The default from Step 3 is the rollback: support tells affected users to write
one key and relaunch. Without it, a regression means a point release. This is the
main reason for the flag — do not skip it to save time.

## Effort

Rough, assuming the spike succeeds:

| Step | Estimate |
|---|---|
| 0 — spike | 1 day |
| 1 — narrow vended surface (+ unit tests) | 1 day |
| 2 — shared protocol | 0.5 day |
| 3 — XPC alongside DO, assistant → Swift | 2 days |
| 4 — peer validation | 0.5–1 day |
| 5 — flip and delete | 0.5 day + a release of soak |
| manual matrix, twice over | 1–2 days |

**~7–9 days**, spread over two releases. If the spike fails, Step 1 alone is a
day and captures most of the security benefit.

## Open questions

1. ~~**Does the spike pass?**~~ Answered 2026-09-01: no for XPC, yes for the
   socket fallback — see Step 0's result and the decision under it.
2. ~~**Can we require macOS 13?**~~ Answered: yes. The deployment target moved
   to 13.5 (`macos-13-minimum-plan.md`), so Step 4 is a real win, not a partial
   one.
3. ~~**Sequencing against the SPKeychain `SecItem` migration.**~~ Answered by
   that migration's Step 3 (see
   `docs/development/keychain-secitem-migration-plan.md`): the assistant no
   longer reads the keychain at all — `SPSSHTunnel` resolves keychain-backed
   passwords app-side inside `getPasswordWithVerificationHash:`, and the
   key-passphrase pre-prompt check moved into `getPasswordForQuery:`. The two
   projects no longer depend on each other's order. For this plan that means:
   the vended surface to narrow is one mode smaller, the manual matrix rows 2
   and 3 now exercise the same DO/XPC ask-the-app path as row 1 (still worth
   running — they cover the app-side keychain resolution), and
   `SP_KEYCHAIN_ITEM_{NAME,ACCOUNT}` no longer exist in the environment.
