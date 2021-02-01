fastlane documentation
================
# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```
xcode-select --install
```

Install _fastlane_ using
```
[sudo] gem install fastlane -NV
```
or alternatively using `brew install fastlane`

# Available Actions
## Mac
### mac prepare_release
```
fastlane mac prepare_release
```
Creates new branch prepare_release, updates strings, increments build version, generates changelog, creates a PR.
### mac prepare_beta_release_bump_version
```
fastlane mac prepare_beta_release_bump_version
```
Creates new branch prepare_release, updates strings, increments app version, increments build version, generates changelog, creates a PR.
### mac prepare_beta_release_bump_patch_version
```
fastlane mac prepare_beta_release_bump_patch_version
```
Creates new branch prepare_release, updates strings, increments app patch version, increments build version, generates changelog, creates a PR.
### mac prepare_beta_release
```
fastlane mac prepare_beta_release
```
Creates new branch prepare_release, updates strings, increments build version, generates changelog, creates a PR.
### mac generate_changelog
```
fastlane mac generate_changelog
```
Creates new branch changelog, generates changelog, creates a PR.
### mac generate_changelog_locally
```
fastlane mac generate_changelog_locally
```
Generates changelog only.
### mac update_strings
```
fastlane mac update_strings
```
Builds Sequel Ace strings target, uploads strings to Crowdin, builds them, downloads them and commits to git
### mac increment_build_version
```
fastlane mac increment_build_version
```
Increase build number
### mac increment_app_version
```
fastlane mac increment_app_version
```
Increase app version
### mac increment_app_patch_version
```
fastlane mac increment_app_patch_version
```
Increase app patch version
### mac appcenter_fetch_version
```
fastlane mac appcenter_fetch_version
```
appcenter_fetch_version
### mac appcenter_upload_dsyms
```
fastlane mac appcenter_upload_dsyms
```
appcenter_upload_dsyms

----

This README.md is auto-generated and will be re-generated every time [fastlane](https://fastlane.tools) is run.
More information about fastlane can be found on [fastlane.tools](https://fastlane.tools).
The documentation of fastlane can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
