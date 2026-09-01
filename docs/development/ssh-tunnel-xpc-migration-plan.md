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

## Step 2 — Shared wire format — ✅ Done

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

Execution notes (2026-09-01): landed as `SASSHTunnelAuthMessage.swift` —
`SASSHTunnelAuthRequest` / `SASSHTunnelAuthResponse` enums and a
`SASSHTunnelAuthWire` codec over `JSONSerialization` with sorted keys and
unescaped slashes, so the bytes are stable and key paths read naturally in
the fixtures. `SASSHTunnelAuthService.handle(_:)` is the dispatch. 15 tests in
`SASSHTunnelAuthMessageTests`: a byte-exact fixture for each of the six
message shapes, round trips, multi-line and non-ASCII text staying on one
line, CR/LF tolerance, and the refusals (garbage, other versions, unknown
kinds, missing or mistyped fields — including `"secret": null`, which is
refused rather than read as empty). Review (Codex) added the scalar-type
rule: `JSONSerialization` returns `NSNumber` for every scalar and Swift's
bridge reads `1` as `true` and `true` as `1`, so the decoder checks the
underlying JSON type — a Bool must be a JSON boolean, `v` a JSON integer —
and a numeric `answer` is refused rather than read as "yes". Nothing in the
file is `public`: the assistant's Objective-C `main` never touches these
types.

## Step 3 — Socket alongside DO, behind a default — ✅ Done (default still DO)

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

Execution notes (2026-09-01):

- Landed as described, with these specifics. The preference is a Bool,
  `SPSSHTunnelUseSocketTransport` (absent → `SASSHTunnelTransportSelection.defaultTransport`,
  which is DO for now); the app passes `SP_CONNECTION_TRANSPORT` and
  `SP_CONNECTION_SOCKET_PATH`. The DO connection is still registered for
  every tunnel, so a socket failure at init falls back with no gap. The
  socket file is `ssh-<10 hex>.sock`, mode 0600, in the container tmp: the
  name is short because that directory already costs ~60 bytes plus the user
  name against the 103-byte limit — with this naming a user name of up to 19
  characters fits, and anything longer falls back to DO for now (see
  Step 5's to-do). `SASSHTunnelSocketServer` also **sweeps stale sockets**
  when it starts: a killed app skips `close()`, and the first live run left
  its socket file behind until this was added. Stale means "refuses a
  connection", so live sockets are untouched.
- The listen backlog is 32, not the obvious 5: macOS *refuses* rather than
  queues a UNIX-socket connect beyond the backlog, which the concurrency test
  hit at 12 parallel askpass launches. Accepted sockets are served on a
  concurrent queue so one parked prompt never blocks another connection.
- Assistant side, three Swift files: `SASSHTunnelAskpass` (the decisions,
  pure, 20 tests mirroring every branch of the Objective-C `main` — including
  the keychain-miss and direct-miss fallback messages, `integerValue`'s
  non-numeric-is-0 reading of `SP_PASSWORD_METHOD`, that a question wins
  over a prompt that merely contains "password:", and — after Codex review —
  that only an explicit `refused` reaches the GUI fallback: a channel error
  on the password request is exit 1, never a second connection that might
  print a secret), `SASSHTunnelSocketClient`
  (connect, send one line, read one line), and the `public`
  `SASSHTunnelAssistantSocketMain` entry the `.m` calls first thing. The DO
  path in the `.m` is byte-for-byte what it was; it is deleted in Step 5.
- Tests: 14 in `SASSHTunnelSocketTransportTests` run both ends in-process —
  every request kind, multi-line prompts, 12 concurrent connections, the
  slow-prompt-does-not-block-others case, 0600 + unlink-on-close, distinct
  paths, the stale sweep, and every refusal (server policy → EOF, client
  policy → nothing sent, garbage/unsupported version → dropped and the server
  keeps serving, malformed reply, missing socket, over-long path). 3 in
  `SASSHTunnelTransportTests` for the preference. Full suite 1279 / 0
  failures.
- **Live verification, both transports**, against a Docker `openssh-server`
  (password auth, `AllowTcpForwarding yes`) forwarding to a `mysql:8.4`
  container, driven by an auto-connect `.spf` and the flag passed via
  `open --args`: on the socket transport ssh authenticated (`Accepted
  password` in sshd's log), held the `-L` forward, and the app's MySQL
  sessions arrived through it; the socket file was present and 0600 during
  the tunnel's life. Same result on DO with the flag off (no socket file).
  Manual-matrix row 12 also fell out: with the assistant parked on a
  passphrase prompt over the socket, killing the app made it exit at once
  instead of hanging — EOF on the socket fails closed.
- **Not verified live** (needs a hand on the UI or a real keychain
  interaction): the passphrase prompt sheet, host-key yes/no, cancel at each
  prompt, the keychain-miss fallback message, and a stored passphrase served
  from the keychain — that last one was attempted (item added with
  `security add-generic-password -T <app>`) and the app blocked on either the
  keychain ACL prompt or its own sheet, which cannot be told apart or
  dismissed from a script. The decisions behind all of these are unit-tested;
  the transport underneath them is the same one the password path proved.

## Step 4 — Peer validation (the security win) — ✅ Done

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

Execution notes (2026-09-01):

- Landed as `SASSHTunnelPeerValidator` (all three targets). One change to
  the table above: **team equality is read from the peer's signing
  information** (`kSecCodeInfoTeamIdentifier`) rather than written as a
  `certificate leaf[subject.OU]` clause, so the same check holds for
  Developer ID, App Store and development certificates without knowing
  which certificate the leaf is. The requirement passed to
  `SecCodeCheckValidity` is `anchor apple generic`, plus
  `identifier "SequelAceTunnelAssistant"` on the app side; the team then has
  to equal the process's own. Both policies are built from
  `SecCodeCopySelf`, never from constants. The app-side policy is the
  default of `SASSHTunnelSocketServer`'s Objective-C initializer; the
  assistant sets the client policy in `SASSHTunnelAssistantSocketMain`.
- Order matters for what the log says: the signature requirement is
  checked before the team, so a foreign Apple-signed binary is logged as
  `requirementFailed(-67050)` and a same-identifier impostor from another
  team as `teamMismatch`. A build with no team logs once ("relying on the
  verification hash") and accepts — that line was seen for real when an
  ad-hoc-signed build ran (see the hazard below).
- 13 tests in `SASSHTunnelPeerValidatorTests`, against the one peer a test
  can always reach — itself, over `socketpair(2)`: the audit token's pid
  field is the peer, not-a-socket and bad-fd failures, signature pass/fail
  by identifier, an unparseable requirement, team mismatch after a passing
  signature, the accept-and-warn-once path, both shipping policies agreeing
  with the explicit one for this process, and both rejection directions
  seen through the real server and client. The test host (Xcode's `xctest`
  agent) does not satisfy `anchor apple` on a beta Xcode and has no team, so
  the tests drive the requirement base and the team explicitly; the shipping
  base was proven on the signed binaries in Step 0 and again below.
- **Live, signed and sandboxed build**, same Docker sshd + MySQL as Step 3:
  with validation on, the assistant was admitted (`Accepted password`,
  sessions through the tunnel), and an unrelated process (`python3`,
  unsandboxed, same user) connecting to the live socket with a well-formed
  request got **EOF and no reply**, the app logging `socket peer rejected:
  noGuest(100001)` — `kPOSIXErrorBase + EPERM`: from inside the sandbox the
  foreign process cannot even be resolved to guest code, which is a
  rejection all the same. The assistant-validates-app direction is covered
  by the same primitive in-process (client policy → nothing sent) and by the
  Step 0 spike's negative case on the real binaries.
- ⚠️ **Hazard for anyone re-running the live checks**: `xcodebuild test`
  with `CODE_SIGNING_ALLOWED=NO` in the shared DerivedData rebuilds the app
  product ad-hoc, and the next Debug build does not re-sign it. The app then
  runs unsandboxed — real `$HOME`, `/var/folders` temp dir, no team — which
  looks like a tunnel regression (a surprise host-key prompt, validation
  disabled) and is not. Check `codesign -dv` for the team before a live
  run; give test runs their own `-derivedDataPath`.

## Step 5 — Flip the default, then delete DO — 🟡 5a (flip) done; 5b (delete) prepared

Separate releases. Flip to the socket, let it soak, then remove the DO path,
the `NSConnection` ivar, the assistant's DO shim and its `SPSSHTunnel.h`
import, and replace `SequelAceTunnelAssistant.m` with `main.swift`. The
remaining `NSConnection` warnings go to zero at this point — a side effect,
not the goal.

Execution notes, 5a (2026-09-01): `SASSHTunnelTransportSelection.defaultTransport`
is `.socket`; the rollback is the same key written `NO` — in the running
build's own defaults domain, which Codex review pointed out differs for the
Beta configuration (`com.sequel-ace.sequel-ace-beta`, not
`com.sequel-ace.sequel-ace`), so support has two commands to hand out, one
per build. The socket name
shrank to `s-<8 hex>.sock` (15 bytes) so user names up to 26 characters fit
the container-tmp path; the stale sweep recognises both shapes. This is the
release that soaks.

Before DO can go, the socket must have somewhere to live for *every* user:
today a container-tmp path over 103 bytes (user names past ~19 characters)
falls back to DO. Give the server a second candidate directory that is short
and sandbox-reachable — the per-user `DARWIN_USER_TEMP_DIR` (`/var/folders/…/T/`,
~50 bytes) is the obvious one if the sandbox permits it for both processes;
prove it the same way Step 0 did — and turn the fallback into a hard error
with a clear log line.

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
one key and relaunch — `SPSSHTunnelUseSocketTransport -bool NO` in the
build's defaults domain, `com.sequel-ace.sequel-ace` for release and
`com.sequel-ace.sequel-ace-beta` for Beta. Without it, a regression means a
point release. This is the main reason for the flag — do not skip it to save
time.

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
