# SSH Tunnel IPC — NSConnection → NSXPCConnection Migration Plan

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

```
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
- **Deployment target is macOS 13.0.**
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

## Step 1 — Narrow the vended surface (ships regardless of the spike)

Pure refactor, no IPC change, no behaviour change.

Introduce `SASSHTunnelAuthService` holding a weak `SPSSHTunnel` and implementing
only the three methods. Change `setRootObject:self` to `setRootObject:` that
façade. The assistant keeps importing `SPSSHTunnel.h` for now.

This is the de-risking step: it collapses the exposed API from ~30 methods to 3
*before* any transport change, and it is independently reviewable and revertable.
If the XPC work later stalls, this alone closes the worst of the exposure.

## Step 2 — Shared protocol

New file compiled into **both** targets:

```swift
@objc public protocol SASSHTunnelAuthProtocol {
    func response(forQuestion question: String,
                  reply: @escaping (Bool) -> Void)
    func password(verificationHash: String,
                  reply: @escaping (String?) -> Void)
    func password(forQuery query: String, verificationHash: String,
                  reply: @escaping (String?) -> Void)
}
```

XPC requires `@objc`, `void` returns and reply blocks. The assistant uses
`synchronousRemoteObjectProxyWithErrorHandler:`, whose reply block runs before
the call returns — preserving today's blocking semantics exactly.

Both proxies need an error handler that fails **closed**: on any XPC error the
assistant must exit non-zero rather than print an empty line, which ssh would
read as an empty password.

## Step 3 — XPC alongside DO, behind a default

Both transports built; a hidden `NSUserDefaults` key selects. Default to DO in
the first release that contains the code, so it can be exercised by
early adopters and support can flip it without a rebuild.

App side: `SASSHTunnelAuthService` gains an `NSXPCListener` and an
`NSXPCListenerDelegate`. Service name stays app-group prefixed and per-tunnel
unique, as today.

Assistant side: replace the three `rootProxyForConnectionWithRegisteredName:`
call sites with an `NSXPCConnection`, and **drop the `SPSSHTunnel.h` import**.

## Step 4 — Peer validation (the security win)

Replace the environment shared-secret as the primary check.

`NSXPCListener.setConnectionCodeSigningRequirement:` (verified present in the
26.0 SDK, `API_AVAILABLE(macos(13.0))`, and it works on `machServiceName` and
anonymous listeners). Requirement along the lines of `anchor apple generic and
certificate leaf[subject.OU] = "NKQ4HJ66PX" and identifier
"<assistant identifier>"`.

This needs no availability gate: the deployment target moved to 13.0 in
`macos-13-minimum-plan.md`, which was done specifically to unblock this step.
On 12.0 there was no supported equivalent — `NSXPCConnection` exposes only
`processIdentifier` and `effectiveUserIdentifier`, `auditToken` is not public
API, and pid-based lookup is racy by construction — so the step would have
degraded to keeping the environment hash as the only check.

Keep the hash anyway; it is free and it narrows the window further.

## Step 5 — Flip the default, then delete DO

Separate releases. Flip to XPC, let it soak, then remove the DO path, the
`NSConnection` ivar, and the assistant's `SPSSHTunnel.h` import. The remaining
12 `NSConnection` warnings go to zero at this point — a side effect, not the goal.

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
works fine for a tool target. Do it in Step 3, not before — a transport change
and a language change in one commit is not bisectable either.

## Verification

There is no way to unit-test this end to end; the trigger is `ssh` deciding to
exec `SSH_ASKPASS`. What each layer buys:

- **Unit-testable (new)**: `SASSHTunnelAuthService` against a fake tunnel — the
  hash comparison, the keychain-vs-UI branch, nil/cancel paths. None of this is
  testable today because the logic sits on `SPSSHTunnel` behind DO. Worth
  writing in Step 1 while the transport is still the old one.
- **Integration-testable (new)**: launch the real assistant binary against a
  test listener with a canned service name and assert on its stdout/exit code.
  Feasible once the protocol exists, and it covers the wire contract.
- **Manual only**: everything involving real ssh.

Manual matrix — every row on **both** transports while Step 3 is in flight, and
on a **signed, sandboxed** build, not a debug build:

| # | Scenario |
|---|---|
| 1 | Password held in app (`SP_PASSWORD_METHOD` = AsksUI) |
| 2 | Password in keychain (assistant never contacts the app) |
| 3 | Key passphrase in keychain |
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

1. **Does the spike pass?** Everything depends on it.
2. ~~**Can we require macOS 13?**~~ Answered: yes. The deployment target moved
   to 13.0 (`macos-13-minimum-plan.md`), so Step 4 is a real win, not a partial
   one.
3. **Sequencing against the SPKeychain `SecItem` migration.** Both change how
   the assistant gets passwords. Suggest this project goes first: it is smaller,
   and it leaves the keychain work with a narrow, testable auth surface instead
   of a DO proxy. Worth confirming rather than assuming.
