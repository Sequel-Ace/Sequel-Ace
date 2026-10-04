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

### mac prepare_release_files

```sh
[bundle exec] fastlane mac prepare_release_files
```

Set an explicit release version/build and regenerate the changelog; never commits or pushes

### mac stage_app_store_release

```sh
[bundle exec] fastlane mac stage_app_store_release
```

Create/update production metadata without submitting it for review

### mac submit_app_store_release

```sh
[bundle exec] fastlane mac submit_app_store_release
```

Submit the exact already-staged production version/build for review

### mac generate_changelog_locally

```sh
[bundle exec] fastlane mac generate_changelog_locally
```

Generate the changelog locally without any git side effects

### mac prepare_release

```sh
[bundle exec] fastlane mac prepare_release
```

Retired unsafe release lane

### mac prepare_release_bump_patch_version

```sh
[bundle exec] fastlane mac prepare_release_bump_patch_version
```

Retired unsafe release lane

### mac prepare_beta_release_bump_version

```sh
[bundle exec] fastlane mac prepare_beta_release_bump_version
```

Retired unsafe release lane

### mac prepare_beta_release_bump_patch_version

```sh
[bundle exec] fastlane mac prepare_beta_release_bump_patch_version
```

Retired unsafe release lane

### mac prepare_beta_release

```sh
[bundle exec] fastlane mac prepare_beta_release
```

Retired unsafe release lane

### mac generate_changelog

```sh
[bundle exec] fastlane mac generate_changelog
```

Retired unsafe release lane

### mac increment_build_version

```sh
[bundle exec] fastlane mac increment_build_version
```

Retired unsafe release lane

### mac increment_app_version

```sh
[bundle exec] fastlane mac increment_app_version
```

Retired unsafe release lane

### mac increment_app_patch_version

```sh
[bundle exec] fastlane mac increment_app_patch_version
```

Retired unsafe release lane

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
