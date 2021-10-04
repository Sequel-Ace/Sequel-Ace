Sequel Ace <img alt="Logo" src="https://sequel-ace.com/images/appIcon-1024.png" align="right" height="80">
=======
[![Crowdin](https://badges.crowdin.net/sequel-ace/localized.svg)](https://crowdin.com/project/sequel-ace)

Sequel Ace is the "sequel" to the longtime macOS tool Sequel Pro.
Sequel Ace is a fast, easy-to-use Mac database management application for working with MySQL & MariaDB databases.

If you would like to sponsor Sequel Ace, please check out our [Open Collective](https://opencollective.com/sequel-ace)!

## Installation

### Mac AppStore <a href="https://apps.apple.com/us/app/sequel-ace/id1518036000?ls=1"><img alt="Download on the Mac AppStore" src="https://sequel-ace.com/images/download_on_mas.png" align="right" height="60"></a>

Download Sequel Ace today from the [macOS App Store](https://apps.apple.com/us/app/sequel-ace/id1518036000?ls=1)!

### MAS CLI

To install via `mas` [MAS CLI](https://github.com/mas-cli/mas) use Sequel Ace id `1518036000`

```sh
mas install 1518036000 # Sequel Ace
```

### Homebrew

To install an unofficial community maintained [Homebrew](https://brew.sh) [Cask](https://github.com/Homebrew/homebrew-cask) of the [GitHub Release](https://github.com/sequel-ace/sequel-ace/releases)

```sh
brew install --cask sequel-ace
```

## Building Locally

To run Sequel Ace locally from XCode, please:
- download `.zip` archive of this repo/clone locally
- open `sequel-ace.xcworkspace` and run `Sequel Ace Local Testing` schema

If you encounter any issues, let us know by [creating a new issue](https://github.com/Sequel-Ace/Sequel-Ace/issues/new/choose).

## Moving Saved Connections from Sequel Pro

To move your favorites, please check the [migration guide](https://sequel-ace.com/get-started/migrating-from-sequel-pro.html).

## Contributing

We have a lot of work to do, but we're here to provide, with your help, an always-free, macOS first SQL database tool for everyone.

We use Slack for communication - feel free to join our [Slack workspace](https://join.slack.com/t/sequel-ace/shared_invite/zt-g9bg1q6o-gDWyGCzauwPdg8BjmBCqKg).

### Translations

If you would like to help with translations, please sign up for Crowdin and join our [Crowdin project](https://crowdin.com/project/sequel-ace) to translate Sequel Ace into supported languages. Also, if you want to add a new language, please [create a new issue](https://github.com/Sequel-Ace/Sequel-Ace/issues/new/choose), and we will be happy to enable that language for you to translate!

### Development

If you would like to help with code and development, please see either our [projects page](https://github.com/sequel-ace/sequel-ace/projects) or [issues](https://github.com/Sequel-Ace/Sequel-Ace/issues/new/choose) with relevant labels such as [Help Wanted](https://github.com/Sequel-Ace/Sequel-Ace/issues?q=is%3Aopen+is%3Aissue+label%3A%22Help+wanted%22), [Bug](https://github.com/Sequel-Ace/Sequel-Ace/issues?q=is%3Aopen+is%3Aissue+label%3ABug), [Feature Request](https://github.com/Sequel-Ace/Sequel-Ace/labels/Feature%20Request), and [PR Welcome](https://github.com/Sequel-Ace/Sequel-Ace/labels/PR%20Welcome). These lists contain the issues where we would most like your help. There are both challenging and straightforward tasks there, so new contributors should be able to get started.

## Branches

- main: Main is our active development branch. All contribution PRs should be pointed at main!

## Tags & Releases

- production/tags represent submissions to the macOS App Store. These are marked as "Pre-Release" until approved by Apple and officially released by the team. Both release candidates and final releases use production/ tags. Release candidates will have RC or Release Candidate in their title.
- beta/tags represent pre-release versions of Sequel Ace intended to test new features and bug fixes. The downloadable app in a beta/ tag has a different name and identifier (Sequel Ace Beta), meaning you can install it side-by-side with the latest App Store release. Beta releases also have increased logging turned on to help us identify critical issues.

## Compatibility

- **macOS:** >= 10.12
- **Processor:** Intel & Apple Silicon
- **MySQL:** >= 5.6
- **MariaDB:** >= 10.0

_Note: An [older version of Sequel Ace (version 2.3.2)](https://github.com/Sequel-Ace/Sequel-Ace/releases/tag/production%2F2.3.2-2121) is available to download for macOS versions 10.10 and 10.11. However support is limited, and we encourage upgrading to the latest macOS and Sequel Ace._

## License

Copyright (c) 2020-2021 Moballo, LLC.  All rights reserved.
Forked from Sequel Pro: Copyright (c) 2002-2019 Sequel Pro & CocoaMySQL Teams. All rights reserved.

Sequel Ace is free and open-source software licensed under [MIT](https://opensource.org/licenses/MIT). See [LICENSE](https://github.com/sequel-ace/sequel-ace/blob/master/LICENSE) for complete details.
