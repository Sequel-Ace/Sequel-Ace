fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac prepare_release

```sh
[bundle exec] fastlane mac prepare_release
```

Creates new branch prepare_release, updates strings, increments build version, generates changelog, creates a PR.

### mac prepare_beta_release_bump_version

```sh
[bundle exec] fastlane mac prepare_beta_release_bump_version
```

Creates new branch prepare_release, updates strings, increments app version, increments build version, generates changelog, creates a PR.

### mac prepare_beta_release_bump_patch_version

```sh
[bundle exec] fastlane mac prepare_beta_release_bump_patch_version
```

Creates new branch prepare_release, updates strings, increments app patch version, increments build version, generates changelog, creates a PR.

### mac prepare_beta_release

```sh
[bundle exec] fastlane mac prepare_beta_release
```

Creates new branch prepare_release, updates strings, increments build version, generates changelog, creates a PR.

### mac generate_changelog

```sh
[bundle exec] fastlane mac generate_changelog
```

Creates new branch changelog, generates changelog, creates a PR.

### mac generate_changelog_locally

```sh
[bundle exec] fastlane mac generate_changelog_locally
```

Generates changelog only.

### mac increment_build_version

```sh
[bundle exec] fastlane mac increment_build_version
```

Increase build number

### mac increment_app_version

```sh
[bundle exec] fastlane mac increment_app_version
```

Increase app version

### mac increment_app_patch_version

```sh
[bundle exec] fastlane mac increment_app_patch_version
```

Increase app patch version

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
