# Vault Role Dropdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the free-text "Vault path:" field in the connection form with a "Vault mount:" text field plus an editable role combo box populated on demand from Vault, with a refresh button.

**Architecture:** A new pure helper splits/joins the persisted `vaultCredentialsPath` (`<mount>/creds/<role>`) into mount + role. `VaultClient` gains a `LIST .../roles` call; `VaultAuthManager` gains a token-ensuring `listRoles` wrapper that reuses the existing OIDC flow. `SPConnectionController` exposes `vaultMount`/`vaultCredentialsRole`/`vaultAvailableRoles` and a refresh action; `vaultCredentialsPath` becomes a computed value so persistence and the connect path stay untouched. The combo box (not a strict popup) preserves manual entry as a fallback when Vault policy forbids `LIST` on `<mount>/roles`.

**Tech Stack:** Swift + Objective-C, AppKit (NSComboBox / NSButton, Cocoa Bindings), XCTest. Mirrors the existing AWS region picker.

## Global Constraints

- `VaultAuthManager` / `VaultClient` network methods MUST run off the main thread (existing `assert(!Thread.isMainThread, ...)`).
- Vault token acquisition MUST reuse `VaultOIDCHandler` — never re-implement auth.
- `vaultCredentialsPath` MUST keep returning the full `<mount>/creds/<role>` so `generateCredentials` and favorite persistence are unchanged.
- Editable combo box only — never block the user from typing a role manually.
- Tests run with: `./Scripts/build.sh tests` (full) or targeted:
  `xcodebuild test -project sequel-ace.xcodeproj -scheme "Unit Tests" -destination "platform=macOS,arch=$(uname -m)" -only-testing:"Unit Tests/<TestClass>" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO | xcpretty -c`

---

### Task 1: `VaultCredentialsPath` split/join helper

**Files:**
- Create: `Source/Other/Vault/VaultCredentialsPath.swift`
- Test: `UnitTests/VaultCredentialsPathTests.swift`

**Interfaces:**
- Produces:
  - `VaultCredentialsPath.mount(fromCredPath: String) -> String`
  - `VaultCredentialsPath.role(fromCredPath: String) -> String`
  - `VaultCredentialsPath.credPath(mount: String, role: String) -> String`

- [ ] **Step 1: Write the failing tests**

```swift
//  VaultCredentialsPathTests.swift
//  Sequel Ace

import XCTest

final class VaultCredentialsPathTests: XCTestCase {

    func testMountIsPrefixBeforeCreds() {
        XCTAssertEqual(VaultCredentialsPath.mount(fromCredPath: "databases_credentials/creds/role-name"),
                       "databases_credentials")
    }

    func testRoleIsSuffixAfterCreds() {
        XCTAssertEqual(VaultCredentialsPath.role(fromCredPath: "databases_credentials/creds/role-name"),
                       "role-name")
    }

    func testNestedMountIsPreserved() {
        XCTAssertEqual(VaultCredentialsPath.mount(fromCredPath: "team/db/creds/ro"), "team/db")
        XCTAssertEqual(VaultCredentialsPath.role(fromCredPath: "team/db/creds/ro"), "ro")
    }

    func testPathWithoutCredsFallsBackToRole() {
        // Unparseable path: keep the whole string as the role so nothing is lost.
        XCTAssertEqual(VaultCredentialsPath.mount(fromCredPath: "weird-value"), "")
        XCTAssertEqual(VaultCredentialsPath.role(fromCredPath: "weird-value"), "weird-value")
    }

    func testCredPathJoinsMountAndRole() {
        XCTAssertEqual(VaultCredentialsPath.credPath(mount: "databases_credentials", role: "role-name"),
                       "databases_credentials/creds/role-name")
    }

    func testCredPathTrimsWhitespaceAndSlashes() {
        XCTAssertEqual(VaultCredentialsPath.credPath(mount: " databases_credentials/ ", role: " /role-name "),
                       "databases_credentials/creds/role-name")
    }

    func testCredPathWithEmptyMountReturnsRoleVerbatim() {
        // Lets a user paste a full path into the role field with no mount.
        XCTAssertEqual(VaultCredentialsPath.credPath(mount: "", role: "databases_credentials/creds/x"),
                       "databases_credentials/creds/x")
    }

    func testCredPathWithEmptyRoleIsEmpty() {
        XCTAssertEqual(VaultCredentialsPath.credPath(mount: "databases_credentials", role: "  "), "")
    }

    func testRoundTrip() {
        let original = "databases_credentials/creds/role-name"
        let rebuilt = VaultCredentialsPath.credPath(
            mount: VaultCredentialsPath.mount(fromCredPath: original),
            role: VaultCredentialsPath.role(fromCredPath: original))
        XCTAssertEqual(rebuilt, original)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project sequel-ace.xcodeproj -scheme "Unit Tests" -destination "platform=macOS,arch=$(uname -m)" -only-testing:"Unit Tests/VaultCredentialsPathTests" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO | xcpretty -c`
Expected: FAIL — "cannot find 'VaultCredentialsPath' in scope".

- [ ] **Step 3: Write the implementation**

```swift
//
//  VaultCredentialsPath.swift
//  Sequel Ace
//
//  Pure helpers to split/join the Vault database credentials path
//  (`<mount>/creds/<role>`) into its mount and role parts.
//

import Foundation

@objcMembers final class VaultCredentialsPath: NSObject {

    private static let separator = "/creds/"
    private static let slashes = CharacterSet(charactersIn: "/")

    /// Mount prefix (everything before `/creds/`). Empty when the path is unparseable.
    static func mount(fromCredPath credPath: String) -> String {
        let p = credPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = p.range(of: separator) else { return "" }
        return String(p[..<range.lowerBound])
    }

    /// Role suffix (everything after `/creds/`). Falls back to the whole string
    /// when `/creds/` is absent, so a hand-typed value is never dropped.
    static func role(fromCredPath credPath: String) -> String {
        let p = credPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = p.range(of: separator) else { return p }
        return String(p[range.upperBound...])
    }

    /// Rebuild `<mount>/creds/<role>`. Returns "" when role is empty; returns the
    /// role verbatim when mount is empty (lets a user paste a full path).
    static func credPath(mount: String, role: String) -> String {
        let m = mount.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: slashes)
        let r = role.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: slashes)
        if r.isEmpty { return "" }
        if m.isEmpty { return r }
        return "\(m)\(separator)\(r)"
    }
}
```

Then add the file to the project: in Xcode add `VaultCredentialsPath.swift` to **both** the app target and the **Unit Tests** target (match how `VaultClient.swift` is configured).

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: PASS (all VaultCredentialsPathTests).

- [ ] **Step 5: Commit**

```bash
git add Source/Other/Vault/VaultCredentialsPath.swift "UnitTests/VaultCredentialsPathTests.swift" sequel-ace.xcodeproj/project.pbxproj
git commit -m "feat(vault): add VaultCredentialsPath mount/role split-join helper"
```

---

### Task 2: `VaultClient` — parse + LIST database roles

**Files:**
- Modify: `Source/Other/Vault/VaultClient.swift` (add after `generateCredentials`, ~line 238)
- Test: `UnitTests/VaultClientTests.swift` (append role-list tests)

**Interfaces:**
- Consumes: `VaultClient.synchronousDataTask`, `parseVaultErrors`, `VaultClientError` (existing).
- Produces:
  - `VaultClient.parseRoleList(from: Data) throws -> [String]` (sorted, case-insensitive)
  - `VaultClient.listDatabaseRoles(baseURL: URL, mount: String, token: String) throws -> [String]`

- [ ] **Step 1: Write the failing tests** (append to `VaultClientTests.swift`)

```swift
    // MARK: - parseRoleList

    func testParseRoleListExtractsAndSortsKeys() throws {
        let json = """
        { "data": { "keys": ["prod", "dev", "Analytics"] } }
        """.data(using: .utf8)!
        let roles = try VaultClient.parseRoleList(from: json)
        XCTAssertEqual(roles, ["Analytics", "dev", "prod"]) // case-insensitive ascending
    }

    func testParseRoleListEmptyKeysReturnsEmptyArray() throws {
        let json = """
        { "data": { "keys": [] } }
        """.data(using: .utf8)!
        XCTAssertEqual(try VaultClient.parseRoleList(from: json), [])
    }

    func testParseRoleListThrowsWhenDataMissing() {
        let json = "{ \"foo\": 1 }".data(using: .utf8)!
        XCTAssertThrowsError(try VaultClient.parseRoleList(from: json))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project sequel-ace.xcodeproj -scheme "Unit Tests" -destination "platform=macOS,arch=$(uname -m)" -only-testing:"Unit Tests/VaultClientTests" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO | xcpretty -c`
Expected: FAIL — "type 'VaultClient' has no member 'parseRoleList'".

- [ ] **Step 3: Add the parser** (in `VaultClient.swift`, after `parseToken`, in the "Response parsers" section ~line 96)

```swift
    static func parseRoleList(from data: Data) throws -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let keys = dataDict["keys"] as? [String] else {
            throw VaultClientError.parseError("missing data.keys in roles response")
        }
        return keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
```

- [ ] **Step 4: Add the network call** (after `generateCredentials`, ~line 238)

```swift
    /// List the database roles available under `mount` (Vault `LIST <mount>/roles`).
    static func listDatabaseRoles(baseURL: URL, mount: String, token: String) throws -> [String] {
        let cleaned = mount.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleaned.isEmpty else { throw VaultClientError.parseError("empty Vault mount") }
        let url = baseURL.appendingPathComponent("v1/\(cleaned)/roles")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "LIST"
        request.setValue(token, forHTTPHeaderField: "X-Vault-Token")

        let (data, response, error) = synchronousDataTask(with: request)
        if let error = error {
            os_log("listDatabaseRoles network error: %{public}@", log: log, type: .error, error.localizedDescription)
            throw VaultClientError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VaultClientError.parseError("no HTTP response")
        }
        // Vault returns 404 for a mount with no roles; treat that as an empty list.
        if httpResponse.statusCode == 404 { return [] }
        guard httpResponse.statusCode == 200, let data = data else {
            let vaultDetail = parseVaultErrors(from: data)
            os_log("listDatabaseRoles HTTP error: %d%{public}@", log: log, type: .error,
                   httpResponse.statusCode, vaultDetail.map { " – \($0)" } ?? "")
            throw VaultClientError.httpError(httpResponse.statusCode, vaultDetail)
        }
        return try parseRoleList(from: data)
    }
```

- [ ] **Step 5: Run tests to verify they pass** (Step 2 command). Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Source/Other/Vault/VaultClient.swift "UnitTests/VaultClientTests.swift"
git commit -m "feat(vault): add VaultClient.listDatabaseRoles (LIST <mount>/roles)"
```

---

### Task 3: `VaultAuthManager.listRoles` wrapper

**Files:**
- Modify: `Source/Other/Vault/VaultAuthManager.swift` (add a new static method near `isAuthorized`, ~line 366)

**Interfaces:**
- Consumes: `VaultClient.buildBaseURL`, `VaultClient.tokenLookupSelf`, `VaultClient.listDatabaseRoles`, `VaultOIDCHandler.cachedToken(for:mount:)`, `VaultOIDCHandler.login(baseURL:mount:identifier:)`, `errorDomain`, `VaultAuthError` (all existing).
- Produces:
  - `@objc(listRolesWithHost:port:oidcMount:mount:error:) static func listRoles(host:port:oidcMount:mount:error:) -> [String]?`
  - Returns `nil` on failure (with `errorPointer` populated); `[]` is a valid empty result.

> **Note on testing:** this method performs synchronous network I/O and may trigger an interactive OIDC browser login, exactly like `generateCredentials`, which has no unit test for the same reason. Verify manually in Task 5. The token logic below is a trimmed copy of `generateCredentials` (lines 249–311) — no caching/coalescing needed for a one-shot user action.

- [ ] **Step 1: Add the method** (in `VaultAuthManager.swift`, after the `generateCredentials` method, before `isAuthorized` ~line 366)

```swift
    /// List database roles under `mount`, ensuring a valid Vault token first
    /// (reusing the cached token, else running the OIDC login flow).
    /// MUST be called from a background thread.
    @objc(listRolesWithHost:port:oidcMount:mount:error:)
    static func listRoles(
        host: String,
        port: String,
        oidcMount: String,
        mount: String,
        error errorPointer: NSErrorPointer
    ) -> [String]? {
        assert(!Thread.isMainThread, "listRoles must not be called on the main thread")

        let trimmedMountValue = mount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = VaultClient.buildBaseURL(host: host, port: port), !trimmedMountValue.isEmpty else {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.invalidConfiguration.rawValue,
                userInfo: [NSLocalizedDescriptionKey: VaultAuthError.invalidConfiguration.localizedDescription ?? ""])
            return nil
        }

        let trimmedOIDCMount = oidcMount.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveOIDCMount = trimmedOIDCMount.isEmpty ? "oidc" : trimmedOIDCMount

        // Resolve a valid token: cached-and-valid, else OIDC login.
        let token: String
        do {
            if let cached = VaultOIDCHandler.cachedToken(for: baseURL, mount: effectiveOIDCMount),
               try VaultClient.tokenLookupSelf(baseURL: baseURL, token: cached) {
                token = cached
            } else {
                token = try VaultOIDCHandler.login(baseURL: baseURL, mount: effectiveOIDCMount, identifier: nil)
            }
        } catch let oidcError as VaultOIDCError {
            let authError: VaultAuthError = (oidcError == .cancelled) ? .loginCancelled : .loginFailed
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: authError.rawValue,
                userInfo: [NSLocalizedDescriptionKey: oidcError.localizedDescription ?? ""])
            return nil
        } catch {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.loginFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
            return nil
        }

        do {
            return try VaultClient.listDatabaseRoles(baseURL: baseURL, mount: trimmedMountValue, token: token)
        } catch {
            errorPointer?.pointee = NSError(
                domain: errorDomain,
                code: VaultAuthError.credentialsFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
            return nil
        }
    }
```

> Before writing, open `VaultAuthManager.swift` and confirm the exact case names of `VaultAuthError` (e.g. `.invalidConfiguration`, `.loginFailed`, `.loginCancelled`, `.credentialsFailed`) and that `errorDomain` is in scope. Adjust names to match if they differ.

- [ ] **Step 2: Build to verify it compiles**

Run: `./Scripts/build.sh tests` (compiles app + test targets and runs the suite).
Expected: BUILD SUCCEEDS, existing tests still PASS.

- [ ] **Step 3: Commit**

```bash
git add Source/Other/Vault/VaultAuthManager.swift
git commit -m "feat(vault): add VaultAuthManager.listRoles token-ensuring wrapper"
```

---

### Task 4: `SPConnectionController` — mount/role properties, computed path, refresh action

**Files:**
- Modify: `Source/Controllers/MainViewControllers/ConnectionView/SPConnectionController.h`
- Modify: `Source/Controllers/MainViewControllers/ConnectionView/SPConnectionController.m`

**Interfaces:**
- Consumes: `VaultCredentialsPath` (Task 1), `VaultAuthManager.listRoles` (Task 3).
- Produces (for the XIB in Task 5):
  - properties `vaultMount`, `vaultCredentialsRole`, `vaultAvailableRoles`
  - outlets `vaultCredentialsRoleComboBox`, `vaultRefreshRolesButton`, `vaultRolesProgressIndicator`
  - action `- (IBAction)refreshVaultRoles:(id)sender`
  - `vaultCredentialsPath` remains the persisted/connect value (now computed).

- [ ] **Step 1: Declare properties and outlets** (in `SPConnectionController.h`)

After the existing Vault ivars (~line 118) add:

```objc
	NSString *vaultMount;
	NSString *vaultCredentialsRole;
	NSArray<NSString *> *vaultAvailableRoles;
```

Near the other Vault `IBOutlet`s (~line 193) add:

```objc
	IBOutlet NSComboBox *vaultCredentialsRoleComboBox;
	IBOutlet NSButton *vaultRefreshRolesButton;
	IBOutlet NSProgressIndicator *vaultRolesProgressIndicator;
```

Next to the other Vault `@property` lines (~line 287) add:

```objc
@property (readwrite, copy) NSString *vaultMount;
@property (readwrite, copy) NSString *vaultCredentialsRole;
@property (readwrite, copy) NSArray<NSString *> *vaultAvailableRoles;
```

> Keep the existing `@property (readwrite, copy) NSString *vaultCredentialsPath;` declaration — only its implementation changes (Step 2).

- [ ] **Step 2: Make `vaultCredentialsPath` computed + KVO-affecting** (in `SPConnectionController.m`)

Add `@dynamic vaultCredentialsPath;` is **not** needed (it was a stored ivar). Instead add these methods (place them near the other Vault accessors; the class likely uses `@synthesize` or ivar-backed properties — replace the auto-behavior by providing both accessors):

```objc
// vaultCredentialsPath is derived from mount + role so existing persistence
// (SPFavoriteVaultCredentialsPathKey) and the connect path stay unchanged.
+ (NSSet *)keyPathsForValuesAffectingVaultCredentialsPath
{
	return [NSSet setWithObjects:@"vaultMount", @"vaultCredentialsRole", nil];
}

- (NSString *)vaultCredentialsPath
{
	return [VaultCredentialsPath credPathWithMount:(vaultMount ?: @"") role:(vaultCredentialsRole ?: @"")];
}

- (void)setVaultCredentialsPath:(NSString *)path
{
	// Called when loading a favorite: split the stored path back into the fields.
	NSString *value = path ?: @"";
	[self setVaultMount:[VaultCredentialsPath mountFromCredPath:value]];
	[self setVaultCredentialsRole:[VaultCredentialsPath roleFromCredPath:value]];
}
```

> If the header declares `NSString *vaultCredentialsPath;` as an ivar, remove that ivar line (the property is now computed and has no backing storage). The `vaultMount` / `vaultCredentialsRole` / `vaultAvailableRoles` properties can stay `@synthesize`d (default) — only `vaultCredentialsPath` needs custom accessors.

> Add `#import "Sequel_Ace-Swift.h"` at the top of `SPConnectionController.m` if not already present (it is — Vault Swift classes are already used here), so `VaultCredentialsPath` is visible to Objective-C.

- [ ] **Step 3: Implement the refresh action** (in `SPConnectionController.m`)

```objc
- (IBAction)refreshVaultRoles:(id)sender
{
	NSString *mount = [self vaultMount] ?: @"";
	if (![[mount stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]) {
		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = NSLocalizedString(@"Enter a Vault mount first", @"Vault roles refresh – missing mount");
		alert.informativeText = NSLocalizedString(@"The list of roles is read from <mount>/roles. Fill in the Vault mount field, then refresh.", @"Vault roles refresh – missing mount detail");
		[alert beginSheetModalForWindow:[dbDocument parentWindowControllerWindow] completionHandler:nil];
		return;
	}

	NSString *host = [self vaultHost] ?: @"";
	NSString *port = [self vaultPort] ?: @"";
	NSString *oidcMount = [self vaultOIDCMount] ?: @"";

	[vaultRefreshRolesButton setEnabled:NO];
	[vaultRolesProgressIndicator setHidden:NO];
	[vaultRolesProgressIndicator startAnimation:self];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *error = nil;
		NSArray<NSString *> *roles = [VaultAuthManager listRolesWithHost:host
		                                                            port:port
		                                                       oidcMount:oidcMount
		                                                           mount:mount
		                                                           error:&error];
		dispatch_async(dispatch_get_main_queue(), ^{
			[self->vaultRolesProgressIndicator stopAnimation:self];
			[self->vaultRolesProgressIndicator setHidden:YES];
			[self->vaultRefreshRolesButton setEnabled:YES];

			if (roles) {
				[self willChangeValueForKey:@"vaultAvailableRoles"];
				self->vaultAvailableRoles = [roles copy];
				[self didChangeValueForKey:@"vaultAvailableRoles"];
			} else {
				NSAlert *alert = [[NSAlert alloc] init];
				alert.messageText = NSLocalizedString(@"Could not load Vault roles", @"Vault roles refresh – failure");
				alert.informativeText = error.localizedDescription ?: NSLocalizedString(@"Unknown error. You can still type the role manually.", @"Vault roles refresh – failure detail");
				[alert beginSheetModalForWindow:[self->dbDocument parentWindowControllerWindow] completionHandler:nil];
			}
		});
	});
}
```

> Match the surrounding code's accessor for the sheet's parent window — search the file for how existing Vault/AWS alerts present (e.g. `parentWindowControllerWindow`, `[tableDocument parentWindow]`, or `[self.view window]`) and use the same one. Adjust `dbDocument`/`vaultRefreshRolesButton`/`vaultRolesProgressIndicator` names to the actual ivars.

- [ ] **Step 4: Build to verify it compiles**

Run: `./Scripts/build.sh tests`
Expected: BUILD SUCCEEDS, existing tests PASS. (No new unit test here — behavior is verified manually in Task 5; the split/join logic it relies on is already covered by Task 1.)

- [ ] **Step 5: Commit**

```bash
git add Source/Controllers/MainViewControllers/ConnectionView/SPConnectionController.h Source/Controllers/MainViewControllers/ConnectionView/SPConnectionController.m
git commit -m "feat(vault): mount/role properties, computed credPath, role refresh action"
```

---

### Task 5: `ConnectionView.xib` — mount field + role combo + refresh button

**Files:**
- Modify: `Source/Interfaces/ConnectionView.xib`

> **Do this in Xcode's Interface Builder, not by hand-editing XML.** Open `ConnectionView.xib`, find the Vault form container (the `vaultCredentialsPathField` text field, id `0lr-8d-HwN`, label "Vault path:").

- [ ] **Step 1: Replace the path field with mount + role + button**

1. Delete the "Vault path:" `NSTextField` (`vaultCredentialsPathField`) and its label. Remove the now-dangling `vaultCredentialsPathField` outlet from `SPConnectionController` if Xcode flags it (the property/ivar was already retired in Task 4 Step 2 — also delete the `IBOutlet NSTextField *vaultCredentialsPathField;` line in the `.h`).
2. Add a label **"Vault mount:"** and an `NSTextField` next to it. In the Bindings inspector bind its **Value** to File's Owner `vaultMount` with **Continuously Updates Value** on. Set placeholder `databases_credentials`.
3. Add a label **"Role:"** and an editable `NSComboBox`. Bindings: **Content Values** → File's Owner `vaultAvailableRoles`; **Value** → File's Owner `vaultCredentialsRole` with **Continuously Updates Value** on. Connect its outlet to `vaultCredentialsRoleComboBox`. Keep it editable (combo cell default).
4. Add a small `NSButton` to the right of the combo (a refresh-style button — e.g. a square button with the `arrow.clockwise` SF Symbol or a "Refresh" title to match the AWS authorize button styling). Connect its outlet to `vaultRefreshRolesButton` and its action to `refreshVaultRoles:` on File's Owner.
5. Add a small `NSProgressIndicator` (spinning, `displayedWhenStopped = NO`, hidden) near the button. Connect its outlet to `vaultRolesProgressIndicator`.
6. Reposition the fields below (Port, Time Zone, Color) so the layout stays aligned — follow the AWS auth form (NSPopUpButton + NSComboBox rows, ~lines 2086–2134) for spacing/sizing reference.

- [ ] **Step 2: Build and run the app**

Run: `./Scripts/build.sh` (debug build) and launch, or build/run the "Sequel Ace Debug" scheme in Xcode.

- [ ] **Step 3: Manual verification**

- [ ] Open a new connection, choose the **Vault** connection type. The form shows "Vault mount:" + "Role:" combo + refresh button (no "Vault path:" field).
- [ ] Expand the empty combo before any refresh → it shows nothing and triggers **no** network call (watch Console for `VaultClient` os_log — none should appear).
- [ ] Fill host/port/OIDC mount + a valid mount, click refresh → (OIDC browser login if needed) → combo populates with **sorted** role names.
- [ ] Select a role, connect → connection succeeds (confirms `vaultCredentialsPath` resolves to `<mount>/creds/<role>`).
- [ ] Save as a favorite, reopen it → mount + role fields are pre-filled by splitting the stored path.
- [ ] Type a role manually without refreshing → connect still works (fallback path).
- [ ] Refresh against a mount your policy can't `LIST` → error sheet appears, combo stays usable for manual entry.

- [ ] **Step 4: Commit**

```bash
git add Source/Interfaces/ConnectionView.xib Source/Controllers/MainViewControllers/ConnectionView/SPConnectionController.h
git commit -m "feat(vault): replace path field with mount + role combo and refresh button"
```

---

## Self-Review Notes

- **Backward compatibility:** `vaultCredentialsPath` is unchanged externally (computed getter returns the full path); `SPFavoriteVaultCredentialsPathKey` persistence and `generateCredentials` need no edits. Loading a favorite splits the stored path back into the fields. ✓
- **No new favorite key** is needed — mount/role are not persisted separately. ✓
- **Type consistency:** Swift `[String]?` ↔ Obj-C `NSArray<NSString *> *`; helper names `credPathWithMount:role:`, `mountFromCredPath:`, `roleFromCredPath:` are the Obj-C selectors auto-generated from the Swift `@objcMembers` signatures in Task 1 — verify in `Sequel_Ace-Swift.h` after building Task 1 and adjust the Obj-C call sites if the generated selectors differ.
- **Policy fallback** (LIST forbidden / 404) is handled: 404 → empty list, other errors → sheet + editable combo. ✓
- **Open risk:** confirm `VaultAuthError` case names and the alert's parent-window accessor in the real source (flagged inline in Tasks 3 & 4).
