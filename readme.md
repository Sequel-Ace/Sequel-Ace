Sequel Ace <img alt="Logo" src="https://sequel-ace.com/images/appIcon-1024.png" align="right" height="80">
=======
[![Crowdin](https://badges.crowdin.net/sequel-ace/localized.svg)](https://crowdin.com/project/sequel-ace)

Sequel Ace is the "sequel" to longtime macOS tool Sequel Pro.
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

## Building locally

To run Sequel Ace locally from XCode, please:
- download `.zip` archive of this repo / clone locally
- open `sequel-ace.xcworkspace` and run `Sequel Ace Local Testing` schema

If you encounter any issue, let us know by [creating a new issue](https://github.com/Sequel-Ace/Sequel-Ace/issues/new/choose).

## Moving saved connections from Sequel Pro

To move your favorites, please check [migration guide](https://sequel-ace.com/get-started/migrating-from-sequel-pro.html).

## Contributing

We have a lot of work to do, but we're here to provide, with your help, an always-free, macOS first SQL database tool for everyone.

### Translations

If you wanna help us with translation, please sign up for Crowdin and join our [Crowdin project](https://crowdin.com/project/sequel-ace) to translate Sequel Ace into supported languages. If you want to add a new language, please open new Issue and we will add that language for you!

### Development

If you wanna help us with code and development, please see either our [projects page](https://github.com/sequel-ace/sequel-ace/projects) or issues with relevant labels. These lists contain the issues where we would most like your help. There are simple and difficult tasks there so new contributors should be able to get started.

## Branches

- main: Main is our active development branch. All contribution PRs should be pointed at main!
- staging: Staging is used for pending app store submissions and release candidates
- release: Release represents what's currently on the app store. All non-release PRs to release will be rejected.

## Compatibility

- **macOS:** >= 10.12
- **Processor:** Intel & Apple Silicon
- **MySQL:** >= 5.6
- **MariaDB:** >= 10.0

_Note: An [older version of Sequel Ace (version 2.3.2)](https://github.com/sequel-ace/sequel-ace/releases) is available to download for macOS versions 10.10 and 10.11, however support is limited and we encourage upgrading to the latest macOS and Sequel Ace._

## License

Copyright (c) 2020-2021 Moballo, LLC.  All rights reserved.
Forked from Sequel Pro: Copyright (c) 2002-2019 Sequel Pro & CocoaMySQL Teams. All rights reserved.

Sequel Ace is free and open source software, licensed under [MIT](https://opensource.org/licenses/MIT). See [LICENSE](https://github.com/sequel-ace/sequel-ace/blob/master/LICENSE) for full details.
