# Disabling Sequel Ace Update Mechanism

This document outlines how to disable or reconfigure the auto-update feature that currently checks the Sequel Ace GitHub repository for new versions.

## Problem

When running Sequel PAce, the app checks for updates from the **Sequel Ace** GitHub repository and shows messages like:
> "Version 5.1.0 (20096) is available. You are currently running 5.0.9 (20095)"

This is incorrect because Sequel PAce is a separate fork and should not update from Sequel Ace.

---

## Root Cause

The update check is configured in:

### 1. `Source/Other/Extensions/BundleExtension.swift` (Lines 67-70)
```swift
GitHubReleaseManager.setup(GitHubReleaseManager.Config(user: "Sequel-Ace",
                                                       project: "Sequel-Ace",
                                                       includeDraft: false,
                                                       includePrerelease: isSnapshotBuild ? true : false))
```

This fetches releases from `https://github.com/Sequel-Ace/Sequel-Ace/releases`.

### 2. User Preference: `SPShowUpdateAvailable`
The update check only runs if this preference is `YES`. See `SPAppController.m:350`.

---

## Solutions

### Option A: Disable Update Checks Completely (Quick Fix)

Set the default for `SPShowUpdateAvailable` to `NO` in the preference defaults:

**File:** `Resources/Plists/PreferenceDefaults.plist`

Add or modify:
```xml
<key>SPShowUpdateAvailable</key>
<false/>
```

### Option B: Point to Sequel PAce Repository (Recommended for Future)

If you set up a GitHub repository for Sequel PAce releases:

**File:** `Source/Other/Extensions/BundleExtension.swift`

Change lines 67-68:
```swift
// FROM:
GitHubReleaseManager.setup(GitHubReleaseManager.Config(user: "Sequel-Ace",
                                                       project: "Sequel-Ace",
// TO:
GitHubReleaseManager.setup(GitHubReleaseManager.Config(user: "your-github-username",
                                                       project: "Sequel-PAce",
```

### Option C: Remove Update Menu Item

Comment out or remove the update menu addition in `SPAppController.m:290`:
```objc
// [self addCheckForUpdatesMenuItem];
```

And the automatic check at line 287:
```objc
// [self checkForNewVersionWithDelay:SPDelayBeforeCheckingForNewReleases andIsFromMenuCheck:NO];
```

---

## Additional URLs to Update

The following files contain hardcoded Sequel Ace URLs that should be updated for Sequel PAce branding:

### `Source/Other/Data/SPConstants.h`
| Line | Constant | Current Value |
|------|----------|---------------|
| 240 | `SPLOCALIZEDURL_HOMEPAGE` | `https://sequel-ace.com/` |
| 241 | `SPLOCALIZEDURL_FAQ` | `https://sequel-ace.com/get-started/` |
| 242 | `SPLOCALIZEDURL_DOCUMENTATION` | `https://sequel-ace.com/` |
| 243 | `SPLOCALIZEDURL_CONTACT` | `https://github.com/Sequel-Ace/Sequel-Ace/issues` |
| 244-247 | Various help URLs | `https://sequel-ace.com/...` |

### `Source/Other/Data/SPConstants.m`
| Line | Constant | Current Value |
|------|----------|---------------|
| 297 | `SPDevURL` | `https://github.com/Sequel-Ace/Sequel-Ace` |
| 298-299 | Help URLs | `https://sequel-ace.com/...` |

### `Resources/Plists/Info.plist`
| Line | Key | Note |
|------|-----|------|
| 264-274 | `sequel-ace.com` domain | ATS exception - can be removed or replaced |

---

## Immediate Action Required

To stop the update notification popup **now**, apply **Option A** or **Option C**.

## After Rebuild

Run:
```bash
./Scripts/build.sh clean
./Scripts/build.sh debug
```

The app will no longer check Sequel Ace for updates.
