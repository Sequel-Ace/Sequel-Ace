## [5.2.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.2.0+%28*%29%22&expanded=true)

### Added
- Add support for mysql urls for sockets and iam connections ([7cc618829](https://github.com/Sequel-Ace/Sequel-Ace/commit/7cc6188298aea86f2a80841a810488ac5b821ada), [#2355](https://github.com/Sequel-Ace/Sequel-Ace/pull/2355))
- Add MySQL 8 fallback for optimized field type ([a91c54cdc](https://github.com/Sequel-Ace/Sequel-Ace/commit/a91c54cdcf99299f77f55c0b669d2e6f2e78a8d0), [#2345](https://github.com/Sequel-Ace/Sequel-Ace/pull/2345))
- Add support for authenticating via AWS IAM to RDS - building on top of work by ostark ([c8f8989eb](https://github.com/Sequel-Ace/Sequel-Ace/commit/c8f8989eb5b2488c4bb5ad4d50523c8f1251ffca), [#2346](https://github.com/Sequel-Ace/Sequel-Ace/pull/2346))
- Add minimal agents.md ([9c1ec8e02](https://github.com/Sequel-Ace/Sequel-Ace/commit/9c1ec8e0245234d72fe3651df84a002165cf3407))

### Fixed
- Fix default bundle migration and bump built-in bundle versions ([38a093ad3](https://github.com/Sequel-Ace/Sequel-Ace/commit/38a093ad3c72aec00990513571aaa1243f858837), [#2351](https://github.com/Sequel-Ace/Sequel-Ace/pull/2351))
- Fix process-list copy/save regression from missing serializer bridge ([6ca28f8b6](https://github.com/Sequel-Ace/Sequel-Ace/commit/6ca28f8b6ab623fc619962f657059c764efac695), [#2349](https://github.com/Sequel-Ace/Sequel-Ace/pull/2349))
- Fix repeated modal loop for failing view metadata/status loads ([2728c07bb](https://github.com/Sequel-Ace/Sequel-Ace/commit/2728c07bb33821821a9fae2a240d88c31b7ba1a9), [#2342](https://github.com/Sequel-Ace/Sequel-Ace/pull/2342))
- Fix Copy as SQL INSERT quoting for numeric fields ([6cc9f24ea](https://github.com/Sequel-Ace/Sequel-Ace/commit/6cc9f24ea8a9753d9c357165e4d6ea8edc2ba116), [#2337](https://github.com/Sequel-Ace/Sequel-Ace/pull/2337))
- Fix process list copy/save appending `(null)` on MySQL ([293575709](https://github.com/Sequel-Ace/Sequel-Ace/commit/293575709ad720300ab6da39ae6c22c3c9269452), [#2333](https://github.com/Sequel-Ace/Sequel-Ace/pull/2333))
- Fix query result column-type preference handling and add regression tests ([96b83e0ad](https://github.com/Sequel-Ace/Sequel-Ace/commit/96b83e0ad5293df8c896e4f28ebfb7e7d1715d98), [#2344](https://github.com/Sequel-Ace/Sequel-Ace/pull/2344))
- Recover from stale database list during database reselection ([887fdcd92](https://github.com/Sequel-Ace/Sequel-Ace/commit/887fdcd92a6b5d7c5cea91865ced1d3fd90932f3), [#2343](https://github.com/Sequel-Ace/Sequel-Ace/pull/2343))
- Fix SSH host key prompt freeze on reconnect ([4e41e5841](https://github.com/Sequel-Ace/Sequel-Ace/commit/4e41e584192c73976af4eb454e5f5883dff9d9cf), [#2340](https://github.com/Sequel-Ace/Sequel-Ace/pull/2340))
- Fix export-system bugs across path, cancel, XML, BIT, and bookmark handling ([cdb2f522d](https://github.com/Sequel-Ace/Sequel-Ace/commit/cdb2f522dbe4677a00176ae564463a4f6958db6d), [#2336](https://github.com/Sequel-Ace/Sequel-Ace/pull/2336))
- Fix pinned table leakage across different connections ([59f7df047](https://github.com/Sequel-Ace/Sequel-Ace/commit/59f7df0477bb9be4d991b63c12abff342ce02e72), [#2334](https://github.com/Sequel-Ace/Sequel-Ace/pull/2334))

### Changed
- Changelog updates ([156238e3b](https://github.com/Sequel-Ace/Sequel-Ace/commit/156238e3bd7bc25a5b74f9654c79fafd07bdc27f))
- Increment build version ([b5cf17e46](https://github.com/Sequel-Ace/Sequel-Ace/commit/b5cf17e46cedf27f9d45a29ec057b575662fbd0a))
- Revamp AWS IAM Auth to a tier 1 auth type ([538f14034](https://github.com/Sequel-Ace/Sequel-Ace/commit/538f140349daae2bab8c0f0a35d1e88181e3476c), [#2353](https://github.com/Sequel-Ace/Sequel-Ace/pull/2353))
- Detect local network privacy denial via Network.framework ([58c6a5258](https://github.com/Sequel-Ace/Sequel-Ace/commit/58c6a5258829c43a85c6336a423600c343ff27c5), [#2352](https://github.com/Sequel-Ace/Sequel-Ace/pull/2352))
- Increment build version ([75affcdc9](https://github.com/Sequel-Ace/Sequel-Ace/commit/75affcdc9676b97e5a4386e310fdff36f21620a9))
- Prepare release ([290884067](https://github.com/Sequel-Ace/Sequel-Ace/commit/29088406730b0779451016932d8968c5583bc8cd), [#2350](https://github.com/Sequel-Ace/Sequel-Ace/pull/2350))
- Detect Local Network permission denial for SSH no-route failures ([4eff50bc7](https://github.com/Sequel-Ace/Sequel-Ace/commit/4eff50bc7608f1e5d9267e822d309868a32653f6), [#2347](https://github.com/Sequel-Ace/Sequel-Ace/pull/2347))
- Expand socket workaround documentation (Issue #113) ([9ce397dff](https://github.com/Sequel-Ace/Sequel-Ace/commit/9ce397dffcb17b23b6fce171b4480e6c93b3de93), [#2339](https://github.com/Sequel-Ace/Sequel-Ace/pull/2339))
- Rewrite default bundles to avoid removed macOS interpreters ([e4496f011](https://github.com/Sequel-Ace/Sequel-Ace/commit/e4496f011a5c681d63207ee0c3dd0c3acea13644), [#2338](https://github.com/Sequel-Ace/Sequel-Ace/pull/2338))
- Attempted fixes for 5.1.0 slowness ([077d208f1](https://github.com/Sequel-Ace/Sequel-Ace/commit/077d208f1287ca042b62d367aa563424d68534f0), [#2331](https://github.com/Sequel-Ace/Sequel-Ace/pull/2331))
- Respect query warning preferences for table comment edits ([9cb3a13ff](https://github.com/Sequel-Ace/Sequel-Ace/commit/9cb3a13ffc70b19564cd4626ac4426e220fc12cb), [#2335](https://github.com/Sequel-Ace/Sequel-Ace/pull/2335))
- Update readme.md ([d8ba62c53](https://github.com/Sequel-Ace/Sequel-Ace/commit/d8ba62c53d32a0a7f7d172079421137806032d71))
- feat: Improve auto-completion with table prioritization and horizontal scrolling ([7ec6d3c45](https://github.com/Sequel-Ace/Sequel-Ace/commit/7ec6d3c45decc40f5813b1391a00d3b4d0e21881), [#2320](https://github.com/Sequel-Ace/Sequel-Ace/pull/2320))

### Removed
- Delete temp file ([afa18ee06](https://github.com/Sequel-Ace/Sequel-Ace/commit/afa18ee06b5c2541b183400a471ae36f382e5c12))

### Infra
- Document mysql:// connection URLs and improve discoverability ([545ae538d](https://github.com/Sequel-Ace/Sequel-Ace/commit/545ae538d61e86a9c33f1ab1b2db3d1e14c429f6), [#2341](https://github.com/Sequel-Ace/Sequel-Ace/pull/2341))
- Bump nokogiri from 1.18.9 to 1.19.1 in /docs ([add5d407b](https://github.com/Sequel-Ace/Sequel-Ace/commit/add5d407bb11fd8770fe26dad1053a7668383cbf), [#2330](https://github.com/Sequel-Ace/Sequel-Ace/pull/2330))
- Bump faraday from 1.10.4 to 1.10.5 ([03794198a](https://github.com/Sequel-Ace/Sequel-Ace/commit/03794198aa694819b8c7968588dd10a4f42fd94a), [#2328](https://github.com/Sequel-Ace/Sequel-Ace/pull/2328))
- Bump faraday from 2.7.10 to 2.14.1 in /docs ([39129add1](https://github.com/Sequel-Ace/Sequel-Ace/commit/39129add1a71664fd94d96bd36b6391910f696c0), [#2327](https://github.com/Sequel-Ace/Sequel-Ace/pull/2327))
- Bump aws-sdk-s3 from 1.179.0 to 1.208.0 ([a0fbd5f33](https://github.com/Sequel-Ace/Sequel-Ace/commit/a0fbd5f33c8b98c666ef3e3958f4695c84af854c), [#2319](https://github.com/Sequel-Ace/Sequel-Ace/pull/2319))

## [5.1.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.1.0+%28*%29%22&expanded=true)

### Added


### Fixed
- fix: data types of copy as sql insert ([6bc7c4ae3](https://github.com/Sequel-Ace/Sequel-Ace/commit/6bc7c4ae315261f6e1251146a6b0b145672da60e), [#2307](https://github.com/Sequel-Ace/Sequel-Ace/pull/2307))

### Changed
- Prepare release ([b30fb280b](https://github.com/Sequel-Ace/Sequel-Ace/commit/b30fb280b0be8602c128fbf94d77bfa3c94c6c67), [#2317](https://github.com/Sequel-Ace/Sequel-Ace/pull/2317))
- Column filter for Content view ([7aad56cf0](https://github.com/Sequel-Ace/Sequel-Ace/commit/7aad56cf0df11aa2dec31becb045eb52207d3b77), [#2311](https://github.com/Sequel-Ace/Sequel-Ace/pull/2311))
- feat: support indent/undent by tab/shift+tab (when using tab characters for indentation) ([adbb52a1a](https://github.com/Sequel-Ace/Sequel-Ace/commit/adbb52a1a7d31314880ce57c620bc774e000043f), [#2305](https://github.com/Sequel-Ace/Sequel-Ace/pull/2305))
- feat: Support dash-style for block comment ([9d972d864](https://github.com/Sequel-Ace/Sequel-Ace/commit/9d972d86400021ae951e3a779c39be828b31ded8), [#2301](https://github.com/Sequel-Ace/Sequel-Ace/pull/2301))

### Removed


### Infra
- Bump actions/checkout from 5 to 6 ([13da8f3ce](https://github.com/Sequel-Ace/Sequel-Ace/commit/13da8f3ce0eb7c2e7f8d45cf9b49c342fdfd14cb), [#2309](https://github.com/Sequel-Ace/Sequel-Ace/pull/2309))
- Bump rexml from 3.4.0 to 3.4.2 ([2753c6671](https://github.com/Sequel-Ace/Sequel-Ace/commit/2753c6671995ee2154628d1e25f522f048cb57d4), [#2296](https://github.com/Sequel-Ace/Sequel-Ace/pull/2296))
- Bump rexml from 3.3.9 to 3.4.2 in /docs ([739f37879](https://github.com/Sequel-Ace/Sequel-Ace/commit/739f37879dbc2c2f7384fc0c77ee289d9657e708), [#2294](https://github.com/Sequel-Ace/Sequel-Ace/pull/2294))
- Bump actions/checkout from 4 to 5 ([7559621e8](https://github.com/Sequel-Ace/Sequel-Ace/commit/7559621e86703dfd036d30a20838bb3a41b3f5e4), [#2287](https://github.com/Sequel-Ace/Sequel-Ace/pull/2287))
- Bump nokogiri from 1.18.8 to 1.18.9 in /docs ([f541d30de](https://github.com/Sequel-Ace/Sequel-Ace/commit/f541d30def4b46e4ddd6a8ab19090752aa135a5e), [#2278](https://github.com/Sequel-Ace/Sequel-Ace/pull/2278))

## [5.0.9](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.0.9+%28*%29%22&expanded=true)

### Added
- support goto database.table with the "Go to Database" ([08085999c](https://github.com/Sequel-Ace/Sequel-Ace/commit/08085999c53d73ea5d5dac671350a371fd73f792), [#2244](https://github.com/Sequel-Ace/Sequel-Ace/pull/2244))

### Fixed
- Fix: Premature closure of auto-completion popup ([bab2ab022](https://github.com/Sequel-Ace/Sequel-Ace/commit/bab2ab02245dc1bc0797cd99deea0155e0ccbfb4), [#2268](https://github.com/Sequel-Ace/Sequel-Ace/pull/2268))
- Correct the date string value to default for DATE, and utilize any of the functions for the field default ([41bfd3e06](https://github.com/Sequel-Ace/Sequel-Ace/commit/41bfd3e066d86aa2fc1e89a7635fd0ac3dc2df6a), [#2254](https://github.com/Sequel-Ace/Sequel-Ace/pull/2254))

### Changed
- Prepare release ([f30103316](https://github.com/Sequel-Ace/Sequel-Ace/commit/f301033162239ecf1845a9cbb04e89c9df0e51f8), [#2269](https://github.com/Sequel-Ace/Sequel-Ace/pull/2269))
- This file has extension "xcodeproj" not "xcworkspace" ([0c81e48ec](https://github.com/Sequel-Ace/Sequel-Ace/commit/0c81e48ec082f8bb96273dbe0b21cca55fde429a), [#2261](https://github.com/Sequel-Ace/Sequel-Ace/pull/2261))
- Update index.md ([d831b1e82](https://github.com/Sequel-Ace/Sequel-Ace/commit/d831b1e820f76e0814e275be26c7483000924695), [#2257](https://github.com/Sequel-Ace/Sequel-Ace/pull/2257))
- #1746 clicking foreign key arrows on _bin column filters correctly ([5d43e5702](https://github.com/Sequel-Ace/Sequel-Ace/commit/5d43e5702b09c07d200d76c8901f01558bfe2148), [#2248](https://github.com/Sequel-Ace/Sequel-Ace/pull/2248))
- Reset the relevant variables to prepare for the next time ([2340e0ca2](https://github.com/Sequel-Ace/Sequel-Ace/commit/2340e0ca2f3776121b5d7a10b9a053a4bdfb8412), [#2243](https://github.com/Sequel-Ace/Sequel-Ace/pull/2243))

### Removed


### Infra


## [5.0.8](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.0.8+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Prepare release ([7c91dddfb](https://github.com/Sequel-Ace/Sequel-Ace/commit/7c91dddfbd11eef5d5c3155c8eac64cc99dee93c), [#2241](https://github.com/Sequel-Ace/Sequel-Ace/pull/2241))
- Attempt to fix high CPU usage ([f58af042d](https://github.com/Sequel-Ace/Sequel-Ace/commit/f58af042dbf315ac5c9695dee7f8712ffd589583), [#2238](https://github.com/Sequel-Ace/Sequel-Ace/pull/2238))
- Revert "Attempt to fix high cpu reconnect issues" ([f169c5621](https://github.com/Sequel-Ace/Sequel-Ace/commit/f169c56214286440b258b262316253948dc07406), [#2237](https://github.com/Sequel-Ace/Sequel-Ace/pull/2237))
- Update generate-changelog.sh ([305c5333c](https://github.com/Sequel-Ace/Sequel-Ace/commit/305c5333ca47aa33ef4edfcc26659c72fc2774a0))

### Removed


### Infra


## [5.0.7](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.0.7+%28*%29%22&expanded=true)

### Added
- Create .coderabbit.yaml ([bc65a9b0e](https://github.com/Sequel-Ace/Sequel-Ace/commit/bc65a9b0e1a5fb94b0ed0d6a6a241a50a45bd866))

### Fixed


### Changed
- Prepare release ([aded84341](https://github.com/Sequel-Ace/Sequel-Ace/commit/aded843419315e4258905de0186a430feba005ac), [#2229](https://github.com/Sequel-Ace/Sequel-Ace/pull/2229))
- Throw an error if ssh config file is inaccessible ([1fa22d2b4](https://github.com/Sequel-Ace/Sequel-Ace/commit/1fa22d2b4e8f2b49f302dfdf86a66317402707b0), [#2227](https://github.com/Sequel-Ace/Sequel-Ace/pull/2227))
- Cleanup crashes and inconsistencies with font handling ([503d0e140](https://github.com/Sequel-Ace/Sequel-Ace/commit/503d0e140e617e06db13b0a59c7959ac8f9d17f4), [#2228](https://github.com/Sequel-Ace/Sequel-Ace/pull/2228))
- Attempt to fix high cpu reconnect issues ([854c1f563](https://github.com/Sequel-Ace/Sequel-Ace/commit/854c1f563e316974875103142b7298eb12356d83), [#2226](https://github.com/Sequel-Ace/Sequel-Ace/pull/2226))
- Font handling improvements ([dd4ab98f7](https://github.com/Sequel-Ace/Sequel-Ace/commit/dd4ab98f7fc593070676659d8ba338e9cd21a82f), [#2223](https://github.com/Sequel-Ace/Sequel-Ace/pull/2223))

### Removed


### Infra
- Bump nokogiri from 1.18.4 to 1.18.8 in /docs ([8f67fb853](https://github.com/Sequel-Ace/Sequel-Ace/commit/8f67fb85389f1cf475c19897b890803598af9f30), [#2224](https://github.com/Sequel-Ace/Sequel-Ace/pull/2224))

## [5.0.6](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.0.6+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix Enum Alignment in Content View ([09c9eb6ee](https://github.com/Sequel-Ace/Sequel-Ace/commit/09c9eb6eee87dc5711689f393e530769f6a6eb81), [#2216](https://github.com/Sequel-Ace/Sequel-Ace/pull/2216))

### Changed
- Prepare release ([81778f5f6](https://github.com/Sequel-Ace/Sequel-Ace/commit/81778f5f6cbbb5994c97e2455b9809c30278fe5a), [#2221](https://github.com/Sequel-Ace/Sequel-Ace/pull/2221))
- Flow around GitHub-based Auto-updates ([680c04a56](https://github.com/Sequel-Ace/Sequel-Ace/commit/680c04a568d1a2c1b60debbe6aa0e80bdfa9ebd9), [#2220](https://github.com/Sequel-Ace/Sequel-Ace/pull/2220))
- Arbitrary sorting of favorites not being preserved between uses ([a9fb9babd](https://github.com/Sequel-Ace/Sequel-Ace/commit/a9fb9babd0f9cae0ccfd21d081298cd8ed5a67c0), [#2219](https://github.com/Sequel-Ace/Sequel-Ace/pull/2219))
- a bug that caused table content to be mangled after completing an automatic resize ([ea36d7fc8](https://github.com/Sequel-Ace/Sequel-Ace/commit/ea36d7fc80a748c15303a4fe84a688518877ef5a), [#2218](https://github.com/Sequel-Ace/Sequel-Ace/pull/2218))

### Removed


### Infra


## [5.0.5](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.0.5+%28*%29%22&expanded=true)

### Added


### Fixed
- fix: Unable to delete table if it's UUID type ([d69d7bcfc](https://github.com/Sequel-Ace/Sequel-Ace/commit/d69d7bcfc72028e185d0f686ba52993dd49ea137), [#2213](https://github.com/Sequel-Ace/Sequel-Ace/pull/2213))
- Fix alignment of ENUMs in content view ([690654205](https://github.com/Sequel-Ace/Sequel-Ace/commit/690654205459dfbcdec90cd9282a099f381100f7), [#2209](https://github.com/Sequel-Ace/Sequel-Ace/pull/2209))

### Changed
- Prepare release ([66b7ec037](https://github.com/Sequel-Ace/Sequel-Ace/commit/66b7ec0373fdb01c7bf20ecabc438bc59a0a6734), [#2214](https://github.com/Sequel-Ace/Sequel-Ace/pull/2214))
- Comment out problematic ln line ([dea3ad734](https://github.com/Sequel-Ace/Sequel-Ace/commit/dea3ad734bc9b9a2501aed5da2933561f97a3cb9))
- Beep-on-application-start - cleanup delete logic ([836fa2e8e](https://github.com/Sequel-Ace/Sequel-Ace/commit/836fa2e8e3c825512fea6c8fc9dc65d54ac74afe), [#2208](https://github.com/Sequel-Ace/Sequel-Ace/pull/2208))
- energy spikes on connection drops. ([90ee29010](https://github.com/Sequel-Ace/Sequel-Ace/commit/90ee290103342673db668306a524e5eaecd5f47b), [#2212](https://github.com/Sequel-Ace/Sequel-Ace/pull/2212))
- Revert "Fix issue with dylib build script" ([359537cc1](https://github.com/Sequel-Ace/Sequel-Ace/commit/359537cc107978526c59fd30db02ffbecb15fe01))
- issue with dylib build script ([3447c3c2c](https://github.com/Sequel-Ace/Sequel-Ace/commit/3447c3c2cce6c2b9840250a4ffb3ce6dacfbb7b8), [#2210](https://github.com/Sequel-Ace/Sequel-Ace/pull/2210))

### Removed


### Infra


## [5.0.4](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.0.4+%28*%29%22&expanded=true)

### Added


### Fixed
- fix: unexpected blue line on bottom of cell ([c1f48a28d](https://github.com/Sequel-Ace/Sequel-Ace/commit/c1f48a28db54f495fe441b84e8b20ae96a92c96e), [#2205](https://github.com/Sequel-Ace/Sequel-Ace/pull/2205))

### Changed
- Prepare release ([bd2b3d382](https://github.com/Sequel-Ace/Sequel-Ace/commit/bd2b3d38214253c73deeb047da28c62f2c24da54), [#2206](https://github.com/Sequel-Ace/Sequel-Ace/pull/2206))

### Removed


### Infra
- Bump nokogiri from 1.18.3 to 1.18.4 in /docs ([479c9196b](https://github.com/Sequel-Ace/Sequel-Ace/commit/479c9196b221a70b5fc0a7b26a46a77bfbf2876d), [#2202](https://github.com/Sequel-Ace/Sequel-Ace/pull/2202))

## [5.0.3](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.0.3+%28*%29%22&expanded=true)

### Added


### Fixed
- fix: Crash on MariaDB >= 11.3 caused by a new db privilege ([1f943ad87](https://github.com/Sequel-Ace/Sequel-Ace/commit/1f943ad8747abc97895147f220f220f23ed4e14e), [#2196](https://github.com/Sequel-Ace/Sequel-Ace/pull/2196))
- fix: Keep original order of table list ([46cd494a0](https://github.com/Sequel-Ace/Sequel-Ace/commit/46cd494a01f972c2670472875e7c77a019f2f30a), [#2197](https://github.com/Sequel-Ace/Sequel-Ace/pull/2197))

### Changed
- Prepare release ([de990f515](https://github.com/Sequel-Ace/Sequel-Ace/commit/de990f515b8186d774a9f6533702477e2cf7d9ed), [#2200](https://github.com/Sequel-Ace/Sequel-Ace/pull/2200))
- feat: Toggle pin for multiple selected items ([510321a5b](https://github.com/Sequel-Ace/Sequel-Ace/commit/510321a5bf6c424e38ed3bef1582c620491dea94), [#2199](https://github.com/Sequel-Ace/Sequel-Ace/pull/2199))

### Removed


### Infra


## [5.0.2](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.0.2+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Prepare release ([8d8f5a5f6](https://github.com/Sequel-Ace/Sequel-Ace/commit/8d8f5a5f6affb1877342b98e4c8d3b8e3ea9e218), [#2188](https://github.com/Sequel-Ace/Sequel-Ace/pull/2188))
- (Fix vertical centering of cells, fix padding for tables list ([76abd481f](https://github.com/Sequel-Ace/Sequel-Ace/commit/76abd481f6b6163d5349a39bbde528ed931e1fd7), [#2185](https://github.com/Sequel-Ace/Sequel-Ace/pull/2185))

### Removed


### Infra


## [5.0.1](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.0.1+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Prepare release ([e6a1b56d5](https://github.com/Sequel-Ace/Sequel-Ace/commit/e6a1b56d573e2ab9b897cda7259b9d65b7fe6b7f), [#2181](https://github.com/Sequel-Ace/Sequel-Ace/pull/2181))
- Hotfix table view row height ([eeebe4895](https://github.com/Sequel-Ace/Sequel-Ace/commit/eeebe4895060c383310d0ba2862b7d102a29aafe), [#2175](https://github.com/Sequel-Ace/Sequel-Ace/pull/2175))
- Clarify the readme around previous versions ([a0dcb183e](https://github.com/Sequel-Ace/Sequel-Ace/commit/a0dcb183ec5579d1d53252254e14bfab53611edf))

### Removed


### Infra
- Bump nokogiri from 1.16.5 to 1.18.3 in /docs ([d653c11a5](https://github.com/Sequel-Ace/Sequel-Ace/commit/d653c11a56972e49a796b66a13261ee2379a2e04), [#2176](https://github.com/Sequel-Ace/Sequel-Ace/pull/2176))

## [5.0.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%225.0.0+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Prepare release ([50fd72bcc](https://github.com/Sequel-Ace/Sequel-Ace/commit/50fd72bcc242dd61a65536450f733b0afc135f46), [#2171](https://github.com/Sequel-Ace/Sequel-Ace/pull/2171))

### Removed
- Drop Support for macOS < 12 ([397bcb40a](https://github.com/Sequel-Ace/Sequel-Ace/commit/397bcb40af9eeced1a3e5f570f64ea0485ab8b8a), [#2170](https://github.com/Sequel-Ace/Sequel-Ace/pull/2170))

### Infra


## [4.2.1](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.2.1+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Restore support for building Sequel Ace in macOS 15 ([5ca4f3bbc](https://github.com/Sequel-Ace/Sequel-Ace/commit/5ca4f3bbcf1ed6c3dc28dddae44782e11230b135), [#2168](https://github.com/Sequel-Ace/Sequel-Ace/pull/2168))
- Prepare release ([7c0f295f6](https://github.com/Sequel-Ace/Sequel-Ace/commit/7c0f295f6bcd0b667851e9eac2a05d29a4a3cfb5), [#2167](https://github.com/Sequel-Ace/Sequel-Ace/pull/2167))
- New Crowdin updates ([b2ad799d9](https://github.com/Sequel-Ace/Sequel-Ace/commit/b2ad799d9eabced1c428904014af096ddad30b06), [#2163](https://github.com/Sequel-Ace/Sequel-Ace/pull/2163))

### Removed


### Infra


## [4.2.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.2.0+%28*%29%22&expanded=true)

### Added


### Fixed
- fix: MySQL filter #2153 ([a93fc2b90](https://github.com/Sequel-Ace/Sequel-Ace/commit/a93fc2b9047fe58ec227dee0514806721d146f74), [#2155](https://github.com/Sequel-Ace/Sequel-Ace/pull/2155))

### Changed
- Increment build version ([d5d88ac4b](https://github.com/Sequel-Ace/Sequel-Ace/commit/d5d88ac4b104cb8108c4e423f8ee64f72cf71d08))
- Stop symlinking mysql plugins ([a7ab344d0](https://github.com/Sequel-Ace/Sequel-Ace/commit/a7ab344d03ae3f59c836a927fb1b7bcbbc899ad7))
- Increment build version ([c37c91e7d](https://github.com/Sequel-Ace/Sequel-Ace/commit/c37c91e7d81dcbebb13accc613b97137db355dc9))
- Prepare release ([67d716c74](https://github.com/Sequel-Ace/Sequel-Ace/commit/67d716c7490ebb98dc1b3fc29a93e764afea2472), [#2160](https://github.com/Sequel-Ace/Sequel-Ace/pull/2160))
- Update DYLIB Files moving to libMySQLClient 8.4.4 ([37990a412](https://github.com/Sequel-Ace/Sequel-Ace/commit/37990a412348a54d29d42e2838d70721ab8d43b5), [#2159](https://github.com/Sequel-Ace/Sequel-Ace/pull/2159))
- New Crowdin updates ([4311aa355](https://github.com/Sequel-Ace/Sequel-Ace/commit/4311aa355c07a7660b723561b45d5b7732805dce), [#2157](https://github.com/Sequel-Ace/Sequel-Ace/pull/2157))

### Removed


### Infra


## [4.1.7](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.1.7+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Increment build version ([259e5fa71](https://github.com/Sequel-Ace/Sequel-Ace/commit/259e5fa7132230bae6550cae2cf4740b6fb10d99))
- Default to not sharing analytics ([b2650277b](https://github.com/Sequel-Ace/Sequel-Ace/commit/b2650277b0a88592c4fa1e20859d85d89b381bf3), [#2147](https://github.com/Sequel-Ace/Sequel-Ace/pull/2147))
- Prepare release ([70150cb4e](https://github.com/Sequel-Ace/Sequel-Ace/commit/70150cb4ef558047e228c80ecf819c7a395c9f8a), [#2146](https://github.com/Sequel-Ace/Sequel-Ace/pull/2146))
- Application quits on closing last DB connection ([1995d263b](https://github.com/Sequel-Ace/Sequel-Ace/commit/1995d263b4e5db22673168f4167a95c20e5cc9ae), [#2036](https://github.com/Sequel-Ace/Sequel-Ace/pull/2036))
- CopyAsMarkdown rewrite in perl (fixes #1724) ([28dabe3b8](https://github.com/Sequel-Ace/Sequel-Ace/commit/28dabe3b89f5c5bde05607b24d935d21c4b34064), [#2142](https://github.com/Sequel-Ace/Sequel-Ace/pull/2142))

### Removed


### Infra


## [4.1.6](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.1.6+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Prepare release ([7f9587745](https://github.com/Sequel-Ace/Sequel-Ace/commit/7f95877451f2ab0b2cff31dd86a32140a63a0009), [#2140](https://github.com/Sequel-Ace/Sequel-Ace/pull/2140))
- Show warning when renaming table by interacting with table list ([a95bdf6f1](https://github.com/Sequel-Ace/Sequel-Ace/commit/a95bdf6f1e3dc2ab2f6ce176db8d8790566b3929), [#2064](https://github.com/Sequel-Ace/Sequel-Ace/pull/2064))
- #fixed: Close data structure retrieval connection when closing main connection ([6aa2df25d](https://github.com/Sequel-Ace/Sequel-Ace/commit/6aa2df25df4a094379373ef930430bd1900cb770), [#2139](https://github.com/Sequel-Ace/Sequel-Ace/pull/2139))
- Export view height ([7f78f3eef](https://github.com/Sequel-Ace/Sequel-Ace/commit/7f78f3eefebd6df96e964a40bbadbfa997e6a5c0), [#2124](https://github.com/Sequel-Ace/Sequel-Ace/pull/2124))
- New Crowdin updates ([ecfa0ec19](https://github.com/Sequel-Ace/Sequel-Ace/commit/ecfa0ec19c7f9abb1dc59f8fe086ddd787d99239), [#2122](https://github.com/Sequel-Ace/Sequel-Ace/pull/2122))

### Removed


### Infra
- Bump rexml from 3.3.6 to 3.3.9 ([7fb1e173d](https://github.com/Sequel-Ace/Sequel-Ace/commit/7fb1e173db39cbb0e8a4f5031bb379177c9e9d25), [#2126](https://github.com/Sequel-Ace/Sequel-Ace/pull/2126))
- Bump rexml from 3.3.6 to 3.3.9 in /docs ([d7c31868d](https://github.com/Sequel-Ace/Sequel-Ace/commit/d7c31868d03ee8cd74a09556a462a360e89db60a), [#2123](https://github.com/Sequel-Ace/Sequel-Ace/pull/2123))

## [4.1.5](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.1.5+%28*%29%22&expanded=true)

### Added
- Add new column for Server Processes UI ([fcdac82a2](https://github.com/Sequel-Ace/Sequel-Ace/commit/fcdac82a26e497b0b54102168777292b41fe2197), [#2085](https://github.com/Sequel-Ace/Sequel-Ace/pull/2085))

### Fixed
- Fix: Escaping textdata/string for binary data when exporting to SQL ([8aceaabac](https://github.com/Sequel-Ace/Sequel-Ace/commit/8aceaabac64258223b33a044e06ce26cf4a9d820), [#2118](https://github.com/Sequel-Ace/Sequel-Ace/pull/2118))
- Fixed: Improve detecting default value by considering quote characters ([f38e46495](https://github.com/Sequel-Ace/Sequel-Ace/commit/f38e46495f0144785a7f04e87465012c6170c0ee), [#2113](https://github.com/Sequel-Ace/Sequel-Ace/pull/2113))

### Changed
- Prepare release ([9ef44054f](https://github.com/Sequel-Ace/Sequel-Ace/commit/9ef44054f2c31bbb30a9aec5cb1e63fdcd818800), [#2119](https://github.com/Sequel-Ace/Sequel-Ace/pull/2119))
- Increment build version ([31bb5bef5](https://github.com/Sequel-Ace/Sequel-Ace/commit/31bb5bef5d668957eb9d6ab498fe35bbaaddf664))

### Removed


### Infra


## [4.1.4](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.1.4+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix Pull Request Template to include Sequoia ([a864cf24f](https://github.com/Sequel-Ace/Sequel-Ace/commit/a864cf24f90c3f6519c7ae2c6f71a8cd53caf6c3), [#2109](https://github.com/Sequel-Ace/Sequel-Ace/pull/2109))
- Fixed: Custom input value can't be applied if field has default value ([157bad9d8](https://github.com/Sequel-Ace/Sequel-Ace/commit/157bad9d8d0037dcc175b5f85597690e882a61dd), [#2102](https://github.com/Sequel-Ace/Sequel-Ace/pull/2102))

### Changed
- Prepare release ([389fefedb](https://github.com/Sequel-Ace/Sequel-Ace/commit/389fefedb8ee5f0b753577ba2c5dd39f5d61e5d5), [#2111](https://github.com/Sequel-Ace/Sequel-Ace/pull/2111))
- crash affecting older versions of macOS ([ae80b4dd6](https://github.com/Sequel-Ace/Sequel-Ace/commit/ae80b4dd660d517393e34fb180baa39397617c43), [#2108](https://github.com/Sequel-Ace/Sequel-Ace/pull/2108))
- Guard MS App Center Calls in Try catch ([ae50ffb51](https://github.com/Sequel-Ace/Sequel-Ace/commit/ae50ffb51656232fe31e4b8341e030a17b704f27), [#2110](https://github.com/Sequel-Ace/Sequel-Ace/pull/2110))
- New Crowdin updates ([822c71b07](https://github.com/Sequel-Ace/Sequel-Ace/commit/822c71b075d6ecb34e0730275d54eba3d46ab16b), [#2099](https://github.com/Sequel-Ace/Sequel-Ace/pull/2099))

### Removed


### Infra
- Bump webrick from 1.8.1 to 1.8.2 ([685884f00](https://github.com/Sequel-Ace/Sequel-Ace/commit/685884f0025740628120c8ac12a83b28a078c35c), [#2098](https://github.com/Sequel-Ace/Sequel-Ace/pull/2098))

## [4.1.3](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.1.3+%28*%29%22&expanded=true)

### Added


### Fixed
- Fixed: Unable to use CURRENT_TIMESTAMP as function's synonym ([61f1b97f0](https://github.com/Sequel-Ace/Sequel-Ace/commit/61f1b97f0a80478229900280ce4290f264558c31), [#2096](https://github.com/Sequel-Ace/Sequel-Ace/pull/2096))

### Changed
- Prepare release ([f3d778667](https://github.com/Sequel-Ace/Sequel-Ace/commit/f3d778667e5662ef34a91e29aba1d6fc4b9a47a8), [#2097](https://github.com/Sequel-Ace/Sequel-Ace/pull/2097))
- Increment build version ([205b3d232](https://github.com/Sequel-Ace/Sequel-Ace/commit/205b3d2324b4b6884959259fe9651f431136004d))

### Removed


### Infra


## [4.1.2](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.1.2+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Prepare release ([ea1609718](https://github.com/Sequel-Ace/Sequel-Ace/commit/ea160971893d2eeb1cba0ce8ccde543c7efb6f66), [#2089](https://github.com/Sequel-Ace/Sequel-Ace/pull/2089))
- Use regex to check if default value is a function ([ae7aa36ff](https://github.com/Sequel-Ace/Sequel-Ace/commit/ae7aa36ff3c59fdd56aaa4a397a1cd189b5bf1b9), [#2082](https://github.com/Sequel-Ace/Sequel-Ace/pull/2082))
- New Crowdin updates ([48e07bb09](https://github.com/Sequel-Ace/Sequel-Ace/commit/48e07bb09f8ef149b75064732e69967f25f18c3c), [#2083](https://github.com/Sequel-Ace/Sequel-Ace/pull/2083))
- New Crowdin updates ([c367c7629](https://github.com/Sequel-Ace/Sequel-Ace/commit/c367c76299d5ffefd815c56162656c028f878fa1), [#2073](https://github.com/Sequel-Ace/Sequel-Ace/pull/2073))
- Increment build version ([6fcbc2aed](https://github.com/Sequel-Ace/Sequel-Ace/commit/6fcbc2aed9d790dff6c14a0fdb6c353328cc2fae))

### Removed


### Infra
- Bump rexml from 3.3.3 to 3.3.6 ([1ffdd52f6](https://github.com/Sequel-Ace/Sequel-Ace/commit/1ffdd52f66fb5ebb447eb4ef5d8b36452f441e75), [#2081](https://github.com/Sequel-Ace/Sequel-Ace/pull/2081))
- Bump rexml from 3.3.3 to 3.3.6 in /docs ([46d0f6275](https://github.com/Sequel-Ace/Sequel-Ace/commit/46d0f62753c2bdf017bc798d8c1ee6704bcb4504), [#2075](https://github.com/Sequel-Ace/Sequel-Ace/pull/2075))

## [4.1.1](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.1.1+%28*%29%22&expanded=true)

### Added
- Added: JSON view is now displayed when the field has collate binary ([6780be2f9](https://github.com/Sequel-Ace/Sequel-Ace/commit/6780be2f9dbaf3bf9e2aefe848193a7d01d3554f), [#2060](https://github.com/Sequel-Ace/Sequel-Ace/pull/2060))

### Fixed
- Fixed: Fix insert data in content view with field type default value ([45554a60c](https://github.com/Sequel-Ace/Sequel-Ace/commit/45554a60cfe777c969e0294b84f5665849075167), [#2063](https://github.com/Sequel-Ace/Sequel-Ace/pull/2063))
- Fixed: Copy data on textdata/string field which has collate binary ([9fce88e7e](https://github.com/Sequel-Ace/Sequel-Ace/commit/9fce88e7e2199cbbbaae9bbf042d54a0618040dd), [#2062](https://github.com/Sequel-Ace/Sequel-Ace/pull/2062))

### Changed
- Prepare release ([2dca3e94c](https://github.com/Sequel-Ace/Sequel-Ace/commit/2dca3e94c518db3d6aca10369d4c6224447a2659), [#2071](https://github.com/Sequel-Ace/Sequel-Ace/pull/2071))
- Crash Closing Field Editor on Binary Column with UUID with a format override ([7f0d989cc](https://github.com/Sequel-Ace/Sequel-Ace/commit/7f0d989cc0105ae069f12c9869fec8768ff3450e), [#2069](https://github.com/Sequel-Ace/Sequel-Ace/pull/2069))

### Removed


### Infra


## [4.1.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.1.0+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix: Unable to update UUID field's value by text editor ([f8997c635](https://github.com/Sequel-Ace/Sequel-Ace/commit/f8997c63508ade582f1cbdf8561433972d17d875), [#2051](https://github.com/Sequel-Ace/Sequel-Ace/pull/2051))
- fix #2049: switch to use formatter for JSON beautifying instead of us… ([c2f43dada](https://github.com/Sequel-Ace/Sequel-Ace/commit/c2f43dada40bcffd6501a68767d0d4cf7f8d9f81), [#2044](https://github.com/Sequel-Ace/Sequel-Ace/pull/2044))

### Changed
- Prepare release ([112e43c42](https://github.com/Sequel-Ace/Sequel-Ace/commit/112e43c4261f4db46e2595c914e3eaf350ca8182), [#2059](https://github.com/Sequel-Ace/Sequel-Ace/pull/2059))
- Feature/bin16 as UUID ([774233fc2](https://github.com/Sequel-Ace/Sequel-Ace/commit/774233fc24c15315f2d0824e72b5bf38d80e3102), [#2054](https://github.com/Sequel-Ace/Sequel-Ace/pull/2054))
- Improved picking query from fav/history lists ([3d59855e2](https://github.com/Sequel-Ace/Sequel-Ace/commit/3d59855e2568521a0056e08b2af291bef16f0190), [#2050](https://github.com/Sequel-Ace/Sequel-Ace/pull/2050))
- Ability to re-format JSON (in field data editor) by soft-indent setting ([57d6fb429](https://github.com/Sequel-Ace/Sequel-Ace/commit/57d6fb429b438bee261b6f80637505c898dbe09c), [#2045](https://github.com/Sequel-Ace/Sequel-Ace/pull/2045))
- package.resolved must be committed for xcode cloud ([855541779](https://github.com/Sequel-Ace/Sequel-Ace/commit/8555417798cc90eb9b54c23224a7640488872cea))
- Prepare Beta release ([f89bd6713](https://github.com/Sequel-Ace/Sequel-Ace/commit/f89bd67138baad19daf750c2553a55c14eb4bda5), [#2043](https://github.com/Sequel-Ace/Sequel-Ace/pull/2043))
- feat #2029: able to use shift-tab to undent selected text ([5f4b3a567](https://github.com/Sequel-Ace/Sequel-Ace/commit/5f4b3a5673b55c11f1dccad1bcde5de7e6b22d33), [#2038](https://github.com/Sequel-Ace/Sequel-Ace/pull/2038))
- feat: ability to reset font to system font & fix Font preview input font size ([3711773a2](https://github.com/Sequel-Ace/Sequel-Ace/commit/3711773a2b3a7eef24d763d261743e40bed9d7f3), [#2039](https://github.com/Sequel-Ace/Sequel-Ace/pull/2039))
- New Crowdin updates ([14618adf5](https://github.com/Sequel-Ace/Sequel-Ace/commit/14618adf534ccef7757503ac35da911f73cc762a), [#2032](https://github.com/Sequel-Ace/Sequel-Ace/pull/2032))
- update homebrew cask link ([69d694088](https://github.com/Sequel-Ace/Sequel-Ace/commit/69d694088f2a63049f956ffccb0ab7588d72e1ba), [#2026](https://github.com/Sequel-Ace/Sequel-Ace/pull/2026))
- New Crowdin updates ([f14d3a5af](https://github.com/Sequel-Ace/Sequel-Ace/commit/f14d3a5af4ac37327935965895c60ad4e98f7ed8), [#2023](https://github.com/Sequel-Ace/Sequel-Ace/pull/2023))
- Adjust size of connection error alert ([42ee54406](https://github.com/Sequel-Ace/Sequel-Ace/commit/42ee54406b8d513137eaff19cd176a7b8a94c9dd), [#2014](https://github.com/Sequel-Ace/Sequel-Ace/pull/2014))

### Removed


### Infra
- Bump rexml from 3.3.2 to 3.3.3 ([196f8a967](https://github.com/Sequel-Ace/Sequel-Ace/commit/196f8a967a716cea765081e8ae31781b5e747fd7), [#2058](https://github.com/Sequel-Ace/Sequel-Ace/pull/2058))
- Bump rexml from 3.3.2 to 3.3.3 in /docs ([c70d13d99](https://github.com/Sequel-Ace/Sequel-Ace/commit/c70d13d99792517558263ea7364c3b2ded7d7161), [#2057](https://github.com/Sequel-Ace/Sequel-Ace/pull/2057))
- Bump rexml from 3.2.8 to 3.3.2 ([50801e234](https://github.com/Sequel-Ace/Sequel-Ace/commit/50801e23458647b7fabffc06a6a9bd399ed28fce), [#2056](https://github.com/Sequel-Ace/Sequel-Ace/pull/2056))
- Bump rexml from 3.2.8 to 3.3.2 in /docs ([02f6590a6](https://github.com/Sequel-Ace/Sequel-Ace/commit/02f6590a6d57feac061836b9680399b45ab7260f), [#2049](https://github.com/Sequel-Ace/Sequel-Ace/pull/2049))
- Bump rexml from 3.2.6 to 3.2.8 in /docs ([c052873f3](https://github.com/Sequel-Ace/Sequel-Ace/commit/c052873f3840a5699e4f841c8fd52fd1ac589d64), [#2018](https://github.com/Sequel-Ace/Sequel-Ace/pull/2018))
- Bump rexml from 3.2.5 to 3.2.8 ([de76d291c](https://github.com/Sequel-Ace/Sequel-Ace/commit/de76d291ca1a2dcdd8a4b2af36a405e0fc57fec9), [#2017](https://github.com/Sequel-Ace/Sequel-Ace/pull/2017))
- Bump nokogiri from 1.16.2 to 1.16.5 in /docs ([66d028aaa](https://github.com/Sequel-Ace/Sequel-Ace/commit/66d028aaaf33fc90b0ddf961f612d79c0eb043d4), [#2015](https://github.com/Sequel-Ace/Sequel-Ace/pull/2015))

## [4.0.17](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.17+%28*%29%22&expanded=true)

### Added
- Add prompt if app should close before termination ([19054dc3c](https://github.com/Sequel-Ace/Sequel-Ace/commit/19054dc3c3e9cc2407573d40ed8f103175c0c902), [#2002](https://github.com/Sequel-Ace/Sequel-Ace/pull/2002))

### Fixed
- Fix app not quitting and crashing when last window closes ([948540e17](https://github.com/Sequel-Ace/Sequel-Ace/commit/948540e17a7a8f94c7c8c6d7d79167c317a3f0bb), [#2001](https://github.com/Sequel-Ace/Sequel-Ace/pull/2001))
- Fix duplicated tables in exports ([fe33bfbbf](https://github.com/Sequel-Ace/Sequel-Ace/commit/fe33bfbbfac42da48b7fab9945f981f03b58b41a), [#2000](https://github.com/Sequel-Ace/Sequel-Ace/pull/2000))

### Changed
- Prepare release ([1351d3e41](https://github.com/Sequel-Ace/Sequel-Ace/commit/1351d3e4152a8081e4367eebe7a223864a7d06d7), [#2012](https://github.com/Sequel-Ace/Sequel-Ace/pull/2012))
- Make prompt on quit configurable ([3f4e6e333](https://github.com/Sequel-Ace/Sequel-Ace/commit/3f4e6e333546b5913034d95afe3996c2af4e5339), [#2011](https://github.com/Sequel-Ace/Sequel-Ace/pull/2011))
- New Crowdin updates ([635e34b46](https://github.com/Sequel-Ace/Sequel-Ace/commit/635e34b46d79f624dac0a3d2fa916e3e206b71c9), [#2009](https://github.com/Sequel-Ace/Sequel-Ace/pull/2009))
- New Crowdin updates ([60e5e4ac7](https://github.com/Sequel-Ace/Sequel-Ace/commit/60e5e4ac7ab6514ae0cb8c17b399ac385f6f747d), [#2003](https://github.com/Sequel-Ace/Sequel-Ace/pull/2003))

### Removed


### Infra


## [4.0.16](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.16+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix FMDB ([d1a0c3eb5](https://github.com/Sequel-Ace/Sequel-Ace/commit/d1a0c3eb542639b0440670bb7c8e51633db85054))

### Changed
- Prepare release ([5511ed752](https://github.com/Sequel-Ace/Sequel-Ace/commit/5511ed7521a3f334bb3c9d764623cc244a0887d7), [#1999](https://github.com/Sequel-Ace/Sequel-Ace/pull/1999))
- Disable Swift UI support ([d3ac29b9f](https://github.com/Sequel-Ace/Sequel-Ace/commit/d3ac29b9fa4a5675e46d4353faf066cf82410f2a), [#1996](https://github.com/Sequel-Ace/Sequel-Ace/pull/1996))

### Removed


### Infra


## [4.0.15](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.15+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix wrong tab order and disrupted titles for tabs ([e673ae6c2](https://github.com/Sequel-Ace/Sequel-Ace/commit/e673ae6c2f2772e69093b86be61b889822c81c5f), [#1988](https://github.com/Sequel-Ace/Sequel-Ace/pull/1988))

### Changed
- Prepare release ([3be4e16d1](https://github.com/Sequel-Ace/Sequel-Ace/commit/3be4e16d1cf982b52b9cf8357014695cb576f288), [#1993](https://github.com/Sequel-Ace/Sequel-Ace/pull/1993))
- New Crowdin updates ([b6e5efc20](https://github.com/Sequel-Ace/Sequel-Ace/commit/b6e5efc2083c636c612a15a16a31ba32de8f9ac4), [#1991](https://github.com/Sequel-Ace/Sequel-Ace/pull/1991))
- Turn off brew cleanup for CI ([dbeae0c4e](https://github.com/Sequel-Ace/Sequel-Ace/commit/dbeae0c4ec565ccf712ab06d5479db19b85e431e), [#1984](https://github.com/Sequel-Ace/Sequel-Ace/pull/1984))
- New Crowdin updates ([adde0e0cd](https://github.com/Sequel-Ace/Sequel-Ace/commit/adde0e0cd1e31e19fa34d114dc7ceac68ecac83d), [#1983](https://github.com/Sequel-Ace/Sequel-Ace/pull/1983))
- New Crowdin updates ([aee160eb3](https://github.com/Sequel-Ace/Sequel-Ace/commit/aee160eb31647ebfa4f1aa02c5eebbbbdf07fbe2), [#1982](https://github.com/Sequel-Ace/Sequel-Ace/pull/1982))

### Removed


### Infra


## [4.0.14](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.14+%28*%29%22&expanded=true)

### Added
- Enable two languages ([d1bada89b](https://github.com/Sequel-Ace/Sequel-Ace/commit/d1bada89bc41fc04eebe9f4e399a016b783923b3))
- Enable Arabic ([cb4d73edf](https://github.com/Sequel-Ace/Sequel-Ace/commit/cb4d73edf23bbc11c8bb696ea321d6927f3d34d7))

### Fixed
- Fix localization ([4f237abb9](https://github.com/Sequel-Ace/Sequel-Ace/commit/4f237abb9ab3e1002325b297383c1af5db7b72d9))

### Changed
- Prepare release ([91725d473](https://github.com/Sequel-Ace/Sequel-Ace/commit/91725d473e3bc3f9d922d56c7f4016722b3ceecd), [#1981](https://github.com/Sequel-Ace/Sequel-Ace/pull/1981))
- Prepare Beta release ([9e8b604a8](https://github.com/Sequel-Ace/Sequel-Ace/commit/9e8b604a8e38fa5dc54fbf69550ec71f41dbdfb2), [#1970](https://github.com/Sequel-Ace/Sequel-Ace/pull/1970))
- #1966 Debug: Changing column name on UUID type (MariaDB) fails ([272ddbd03](https://github.com/Sequel-Ace/Sequel-Ace/commit/272ddbd03fa834350816fe187636c127e022a39f), [#1969](https://github.com/Sequel-Ace/Sequel-Ace/pull/1969))
- New Crowdin updates ([a5be31baa](https://github.com/Sequel-Ace/Sequel-Ace/commit/a5be31baa3a8e96f880de15cb3db8e2b38eb4a76), [#1965](https://github.com/Sequel-Ace/Sequel-Ace/pull/1965))
- New Crowdin updates ([6de324be8](https://github.com/Sequel-Ace/Sequel-Ace/commit/6de324be8d23a2cbac0351650ef1e99febc498d4), [#1954](https://github.com/Sequel-Ace/Sequel-Ace/pull/1954))
- New Crowdin updates ([0f423054f](https://github.com/Sequel-Ace/Sequel-Ace/commit/0f423054ffa01503c3525d0947c81c936f4ff0d0), [#1942](https://github.com/Sequel-Ace/Sequel-Ace/pull/1942))
- New Crowdin updates ([3ba37b26f](https://github.com/Sequel-Ace/Sequel-Ace/commit/3ba37b26fa7dab9da70fd21c88069661b495cb9e), [#1941](https://github.com/Sequel-Ace/Sequel-Ace/pull/1941))
- New Crowdin updates ([39d987cb0](https://github.com/Sequel-Ace/Sequel-Ace/commit/39d987cb07acbe61a7e442ffd92c523e4c0de534), [#1940](https://github.com/Sequel-Ace/Sequel-Ace/pull/1940))
- New Crowdin updates ([81578f87f](https://github.com/Sequel-Ace/Sequel-Ace/commit/81578f87f5dc73110b169a3a99b80b3342ea2a22), [#1939](https://github.com/Sequel-Ace/Sequel-Ace/pull/1939))
- #1842: Re-enable 'Save ... to Favorites" option ([9a3d874e6](https://github.com/Sequel-Ace/Sequel-Ace/commit/9a3d874e676e8b45fcafca651bf32c2f01fe2973), [#1928](https://github.com/Sequel-Ace/Sequel-Ace/pull/1928))
- New Crowdin updates ([1b896f307](https://github.com/Sequel-Ace/Sequel-Ace/commit/1b896f3075e4725acc34581da1fb80130d62bd8b), [#1926](https://github.com/Sequel-Ace/Sequel-Ace/pull/1926))
- New Crowdin updates ([ebcbb032d](https://github.com/Sequel-Ace/Sequel-Ace/commit/ebcbb032deeaeeef1e599d8ef4e4cf04aceba2d4), [#1924](https://github.com/Sequel-Ace/Sequel-Ace/pull/1924))
- Merge branch 'main' of github.com:Sequel-Ace/Sequel-Ace ([9a856fb01](https://github.com/Sequel-Ace/Sequel-Ace/commit/9a856fb019968ddfc50f8ce5b699769488e27b46))

### Removed


### Infra
- Bump nokogiri from 1.15.4 to 1.16.2 in /docs ([862b901ff](https://github.com/Sequel-Ace/Sequel-Ace/commit/862b901ff7afe30e22463a5b5a4f067ccf61bb10), [#1964](https://github.com/Sequel-Ace/Sequel-Ace/pull/1964))

## [4.0.13](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.13+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix database duplication command for MySQL 8 ([9d005b61a](https://github.com/Sequel-Ace/Sequel-Ace/commit/9d005b61a5b3c6464d6a916c0566f1b8776a24f6), [#1919](https://github.com/Sequel-Ace/Sequel-Ace/pull/1919))
- Fix mysql_real_escape_string when NO_BACKSLASH_ESCAPES SQL mode is enabled ([8d66aa2b3](https://github.com/Sequel-Ace/Sequel-Ace/commit/8d66aa2b3b4dcffb6b6fb61463ce6ee97daee711), [#1917](https://github.com/Sequel-Ace/Sequel-Ace/pull/1917))

### Changed
- Prepare release ([f9d68ecfa](https://github.com/Sequel-Ace/Sequel-Ace/commit/f9d68ecfa6b126a4add70e4e5552f366fb816dea), [#1922](https://github.com/Sequel-Ace/Sequel-Ace/pull/1922))
- New Crowdin updates ([f1ae143e8](https://github.com/Sequel-Ace/Sequel-Ace/commit/f1ae143e8dee4e42c25748276f800fe127aaf47d), [#1921](https://github.com/Sequel-Ace/Sequel-Ace/pull/1921))
- Increment build version ([1f6fe8147](https://github.com/Sequel-Ace/Sequel-Ace/commit/1f6fe8147104e5673c8cb1b92bfa3bb3a79a3e99))
- Increment build version ([29384725f](https://github.com/Sequel-Ace/Sequel-Ace/commit/29384725f98cb8ffe3d4d23d5fac656b166a0404))

### Removed


### Infra


## [4.0.12](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.12+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Prepare release ([81566595a](https://github.com/Sequel-Ace/Sequel-Ace/commit/81566595a0174ba8d6c901dfbc2071ace5f6b244), [#1914](https://github.com/Sequel-Ace/Sequel-Ace/pull/1914))
- Table History Navigation ([0b51d97c3](https://github.com/Sequel-Ace/Sequel-Ace/commit/0b51d97c3c66e3e92e39c4e7962420fa0fff0f4e), [#1902](https://github.com/Sequel-Ace/Sequel-Ace/pull/1902))
- New Crowdin updates ([23b0a38a7](https://github.com/Sequel-Ace/Sequel-Ace/commit/23b0a38a7c7639aa3e444eb4f34b2cd12ef7b568), [#1905](https://github.com/Sequel-Ace/Sequel-Ace/pull/1905))
- New Crowdin updates ([38d44c391](https://github.com/Sequel-Ace/Sequel-Ace/commit/38d44c391dc73b9e7d005483225e596256953da2), [#1903](https://github.com/Sequel-Ace/Sequel-Ace/pull/1903))
- New Crowdin updates ([4f52e24d2](https://github.com/Sequel-Ace/Sequel-Ace/commit/4f52e24d2a0719680e733d666274fa741162426e), [#1901](https://github.com/Sequel-Ace/Sequel-Ace/pull/1901))
- New Crowdin updates ([a7c63e7b9](https://github.com/Sequel-Ace/Sequel-Ace/commit/a7c63e7b99487418da2d62221b94ac4b2c12ae3e), [#1897](https://github.com/Sequel-Ace/Sequel-Ace/pull/1897))
- Increment build version ([35761f380](https://github.com/Sequel-Ace/Sequel-Ace/commit/35761f38050a41ff0d7c8a6829e3939e1cb23afa))

### Removed


### Infra


## [4.0.11](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.11+%28*%29%22&expanded=true)

### Added
- Add fastlane prepare_release_bump_patch_version ([1a7c86131](https://github.com/Sequel-Ace/Sequel-Ace/commit/1a7c8613131114916c989cf8e411b06192f2f2ae))

### Fixed
- fixed: Crash when default value contains only whitespace ([9d2d85efe](https://github.com/Sequel-Ace/Sequel-Ace/commit/9d2d85efef57f6fbe10e2f96dabc18b5c1cc9439), [#1884](https://github.com/Sequel-Ace/Sequel-Ace/pull/1884))

### Changed
- Prepare release ([a204cc41b](https://github.com/Sequel-Ace/Sequel-Ace/commit/a204cc41ba3be0708191ff79382adffcaae6b0b5), [#1892](https://github.com/Sequel-Ace/Sequel-Ace/pull/1892))
- Progress window is modal ([014267dbb](https://github.com/Sequel-Ace/Sequel-Ace/commit/014267dbb72bb215407d220a81a834533fa2edab), [#1888](https://github.com/Sequel-Ace/Sequel-Ace/pull/1888))
- New Crowdin updates ([22bff344d](https://github.com/Sequel-Ace/Sequel-Ace/commit/22bff344d29c48599d96cdb273e1eb9c28dc117e), [#1886](https://github.com/Sequel-Ace/Sequel-Ace/pull/1886))
- New Crowdin updates ([c3350ae05](https://github.com/Sequel-Ace/Sequel-Ace/commit/c3350ae0506d3b30c90a63fb6c8fd3dabb10ea91), [#1883](https://github.com/Sequel-Ace/Sequel-Ace/pull/1883))
- New Crowdin updates ([c5995f182](https://github.com/Sequel-Ace/Sequel-Ace/commit/c5995f182001cae1b73b52a19505d7a6cb12eee3), [#1876](https://github.com/Sequel-Ace/Sequel-Ace/pull/1876))

### Removed


### Infra


## [4.0.10](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.10+%28*%29%22&expanded=true)

### Added
- Add LD64 flag ([84de23b63](https://github.com/Sequel-Ace/Sequel-Ace/commit/84de23b638d3a8ed3972b2d3feb32e0dba1679c7))

### Fixed
- Fix window losing focus when running query ([6fa1a351e](https://github.com/Sequel-Ace/Sequel-Ace/commit/6fa1a351e84a5dfc40c026601a0029d2ba38e04b), [#1849](https://github.com/Sequel-Ace/Sequel-Ace/pull/1849))

### Changed
- Prepare release ([9f8381f10](https://github.com/Sequel-Ace/Sequel-Ace/commit/9f8381f10a0d3b2f9ff7e2559b82988a8bc7f29f), [#1868](https://github.com/Sequel-Ace/Sequel-Ace/pull/1868))
- Revert "Add LD64 flag" ([41d2c8d09](https://github.com/Sequel-Ace/Sequel-Ace/commit/41d2c8d09836226286f58d3816bac3c188d05ff7))
- New Crowdin updates ([b89123100](https://github.com/Sequel-Ace/Sequel-Ace/commit/b89123100a55c9dc306a85545de2c66f2ff9bc43), [#1867](https://github.com/Sequel-Ace/Sequel-Ace/pull/1867))
- Prepare Beta release ([5c66f52bd](https://github.com/Sequel-Ace/Sequel-Ace/commit/5c66f52bdaea2da1f200878564e84154eb76ad39), [#1866](https://github.com/Sequel-Ace/Sequel-Ace/pull/1866))
- Update dependencies and AppCenter ([7863eaf54](https://github.com/Sequel-Ace/Sequel-Ace/commit/7863eaf546f38d6b905bfa9370928c48d9c5f10b))
- Prepare Beta release ([d20b58254](https://github.com/Sequel-Ace/Sequel-Ace/commit/d20b58254332f9de65f1461262407d7e0cd177c2), [#1864](https://github.com/Sequel-Ace/Sequel-Ace/pull/1864))
- Revert more past threading changes ([6782fadce](https://github.com/Sequel-Ace/Sequel-Ace/commit/6782fadceefaa049ba6963babbdb1acf9e04c922), [#1863](https://github.com/Sequel-Ace/Sequel-Ace/pull/1863))
- Allow for specifying connection timeout of zero - https://github.com/… ([009f3d6fa](https://github.com/Sequel-Ace/Sequel-Ace/commit/009f3d6fa3e8db344afd3aea110a61b629ceca95), [#1861](https://github.com/Sequel-Ace/Sequel-Ace/pull/1861))
- Prepare Beta release ([d9e417973](https://github.com/Sequel-Ace/Sequel-Ace/commit/d9e4179738ea0005e658c84c4528f7d013da9c46), [#1860](https://github.com/Sequel-Ace/Sequel-Ace/pull/1860))
- Revert some of the unneeded threading changes from 4.0.9 ([213779963](https://github.com/Sequel-Ace/Sequel-Ace/commit/21377996387deabb5527cea3d60888c0e55890ba), [#1859](https://github.com/Sequel-Ace/Sequel-Ace/pull/1859))
- New Crowdin updates ([22161a2c9](https://github.com/Sequel-Ace/Sequel-Ace/commit/22161a2c9f888b0c84c6067556f2539008f28bce), [#1855](https://github.com/Sequel-Ace/Sequel-Ace/pull/1855))
- Potentially fixed filter hanging and appearance ([6e0f2674b](https://github.com/Sequel-Ace/Sequel-Ace/commit/6e0f2674b57df3ae307b770bba66d6b6f2019b67), [#1854](https://github.com/Sequel-Ace/Sequel-Ace/pull/1854))
- Update pull_request_template.md ([36da9464e](https://github.com/Sequel-Ace/Sequel-Ace/commit/36da9464e251341e84fea34cfb74c66aa7f8a713))
- Open database using urlencoding ([3acb5852d](https://github.com/Sequel-Ace/Sequel-Ace/commit/3acb5852db9daf364aa8e3c81958bca3213da479), [#1850](https://github.com/Sequel-Ace/Sequel-Ace/pull/1850))

### Removed


### Infra


## [4.0.9](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.9+%28*%29%22&expanded=true)

### Added
- Create SECURITY.md ([1c3bf628d](https://github.com/Sequel-Ace/Sequel-Ace/commit/1c3bf628d5ed18705793b22cb783998ca4c4930e), [#1835](https://github.com/Sequel-Ace/Sequel-Ace/pull/1835))
- Create codeql.yml ([cbc2065f0](https://github.com/Sequel-Ace/Sequel-Ace/commit/cbc2065f06fdf34ac0646c256f5c0022d13d722c))

### Fixed
- Fixed app hanging on load on macOS Sonoma ([e693c98bd](https://github.com/Sequel-Ace/Sequel-Ace/commit/e693c98bd3513108dd9b046d23851a1903cc139e), [#1846](https://github.com/Sequel-Ace/Sequel-Ace/pull/1846))

### Changed
- Prepare release ([920229bf7](https://github.com/Sequel-Ace/Sequel-Ace/commit/920229bf7bc9a3cdbbbb55e6b725d79e80582413), [#1847](https://github.com/Sequel-Ace/Sequel-Ace/pull/1847))
- Increment app patch version ([fee11b407](https://github.com/Sequel-Ace/Sequel-Ace/commit/fee11b407760fbb1975fbaee1e799cced67b8ae1))
- Update SECURITY.md ([4ae16ab93](https://github.com/Sequel-Ace/Sequel-Ace/commit/4ae16ab9347eb2b05e8645b36235813ae2d7298c))
- Update docs versions ([8fbfed5f1](https://github.com/Sequel-Ace/Sequel-Ace/commit/8fbfed5f1fea15ca3d379222ee666d87f4038e4d))

### Removed
- Remove code QL yaml ([91fb42757](https://github.com/Sequel-Ace/Sequel-Ace/commit/91fb427579978eb77c7afb8358e05307633589d8))

### Infra
- Bump actions/checkout from 3 to 4 ([66d6495b5](https://github.com/Sequel-Ace/Sequel-Ace/commit/66d6495b5c3a91417c1920c10320f60834d75ded), [#1839](https://github.com/Sequel-Ace/Sequel-Ace/pull/1839))

## [4.0.8](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.8+%28*%29%22&expanded=true)

### Added
- Add mising collation types ([a2b9bb016](https://github.com/Sequel-Ace/Sequel-Ace/commit/a2b9bb01682ce3699fca5ff32a50dcfaa1a2f506), [#1833](https://github.com/Sequel-Ace/Sequel-Ace/pull/1833))

### Fixed
- Fix Minor issue in phrasing of error message for duplicate table error ([99fd5f5f1](https://github.com/Sequel-Ace/Sequel-Ace/commit/99fd5f5f1813143a51e8338ae1f3018e0fd08481), [#1831](https://github.com/Sequel-Ace/Sequel-Ace/pull/1831))

### Changed
- Prepare release ([cc7f101ab](https://github.com/Sequel-Ace/Sequel-Ace/commit/cc7f101abb25c0f95bdc05aa557c36c99b0492b2), [#1834](https://github.com/Sequel-Ace/Sequel-Ace/pull/1834))
- Increment app patch version ([3f31646fb](https://github.com/Sequel-Ace/Sequel-Ace/commit/3f31646fb54ee887014ae60efc349d595fc55b01))
- Merge branch 'l10n_main' ([d3464a799](https://github.com/Sequel-Ace/Sequel-Ace/commit/d3464a79986710a3ce7a86d40c2dd8d8ac7b6b00))
- New Crowdin updates ([98cf84154](https://github.com/Sequel-Ace/Sequel-Ace/commit/98cf841544f6541810f9bfe6c02616b4caacf044), [#1827](https://github.com/Sequel-Ace/Sequel-Ace/pull/1827))
- New Crowdin updates ([33e9cb8ce](https://github.com/Sequel-Ace/Sequel-Ace/commit/33e9cb8ce88fc23e02faa45cbd8480eeed659719), [#1823](https://github.com/Sequel-Ace/Sequel-Ace/pull/1823))
- 'failed connection'-alert not being able to close when the error message it too long ([aeb6a0b18](https://github.com/Sequel-Ace/Sequel-Ace/commit/aeb6a0b18a8d6c52c4b6ee459a22b4cd162c0b81), [#1813](https://github.com/Sequel-Ace/Sequel-Ace/pull/1813))
- Closing tab in Structure view causes freeze ([7085f4829](https://github.com/Sequel-Ace/Sequel-Ace/commit/7085f4829aac4895260178789c92046441c855e3), [#1817](https://github.com/Sequel-Ace/Sequel-Ace/pull/1817))

### Removed


### Infra
- Bump commonmarker from 0.23.9 to 0.23.10 in /docs ([4169a2621](https://github.com/Sequel-Ace/Sequel-Ace/commit/4169a26217263af07aa09fe38a40d97724bfc14c), [#1816](https://github.com/Sequel-Ace/Sequel-Ace/pull/1816))

## [4.0.7](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.7+%28*%29%22&expanded=true)

### Added


### Fixed
- Fixed data interpreting buttons hidden on editor popup ([8f287dd3f](https://github.com/Sequel-Ace/Sequel-Ace/commit/8f287dd3fe6b57e1f80b21e0f9a107c3684eeeb3), [#1801](https://github.com/Sequel-Ace/Sequel-Ace/pull/1801))
- Fixed issue with keychain items for SSH Passwords ([22c314b8e](https://github.com/Sequel-Ace/Sequel-Ace/commit/22c314b8e786df39578d03b9c213fe2e22b1991f), [#1796](https://github.com/Sequel-Ace/Sequel-Ace/pull/1796))

### Changed
- Prepare release ([78b3bb7da](https://github.com/Sequel-Ace/Sequel-Ace/commit/78b3bb7dae21f95258b555eea978a47e34e75028), [#1802](https://github.com/Sequel-Ace/Sequel-Ace/pull/1802))
- Further improved keychain handling around missing keys ([2ac6d0aeb](https://github.com/Sequel-Ace/Sequel-Ace/commit/2ac6d0aeb053d5c098129522e7c5e706d0dea62f), [#1799](https://github.com/Sequel-Ace/Sequel-Ace/pull/1799))
- Minor code cleanup ([1b8f45b6b](https://github.com/Sequel-Ace/Sequel-Ace/commit/1b8f45b6b3dca420f6aaa135459dde621ad5443d), [#1800](https://github.com/Sequel-Ace/Sequel-Ace/pull/1800))
- Prepare Beta release ([956eeb5b9](https://github.com/Sequel-Ace/Sequel-Ace/commit/956eeb5b97248d230482a738dd8b3505c52eac99), [#1798](https://github.com/Sequel-Ace/Sequel-Ace/pull/1798))

### Removed


### Infra


## [4.0.6](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.6+%28*%29%22&expanded=true)

### Added
- support query parameters in mysql url scheme for #108 ([e95305dba](https://github.com/Sequel-Ace/Sequel-Ace/commit/e95305dbafa192941f19aa828d074bba391e5aeb), [#1703](https://github.com/Sequel-Ace/Sequel-Ace/pull/1703))

### Fixed
- Fixed incorrect file type for saved connections ([10655918b](https://github.com/Sequel-Ace/Sequel-Ace/commit/10655918bfa797e20aa7be4c5f892d63c50d7e39), [#1782](https://github.com/Sequel-Ace/Sequel-Ace/pull/1782))
- fix the "Initializing 'NSRange' (aka 'struct _NSRange') with an expre… ([43f5e3846](https://github.com/Sequel-Ace/Sequel-Ace/commit/43f5e3846ca9895fab9761d3c9063336ec1dd133), [#1753](https://github.com/Sequel-Ace/Sequel-Ace/pull/1753))
- Correct the terms used in the Taiwanese translation ([963a2b047](https://github.com/Sequel-Ace/Sequel-Ace/commit/963a2b04738712f3b4d1854b31df42d04d8b8cff), [#1685](https://github.com/Sequel-Ace/Sequel-Ace/pull/1685))

### Changed
- Prepare release ([d00a24b04](https://github.com/Sequel-Ace/Sequel-Ace/commit/d00a24b0432ba5b63049ba29a652826b84c06676), [#1787](https://github.com/Sequel-Ace/Sequel-Ace/pull/1787))
- Prepare Beta release ([ba9fe5579](https://github.com/Sequel-Ace/Sequel-Ace/commit/ba9fe5579daed35120fd83b012869572756d0178), [#1784](https://github.com/Sequel-Ace/Sequel-Ace/pull/1784))
- Ability to clear out saved passwords ([0d0524788](https://github.com/Sequel-Ace/Sequel-Ace/commit/0d052478843ac67712085740ecc07a83e40e2648), [#1783](https://github.com/Sequel-Ace/Sequel-Ace/pull/1783))
- Make setting to hide column types apply for custom query results too ([8fc665c4e](https://github.com/Sequel-Ace/Sequel-Ace/commit/8fc665c4e27f49543f95764f4bc0a8c4e5a0cd72), [#1781](https://github.com/Sequel-Ace/Sequel-Ace/pull/1781))
- New Crowdin updates ([6e97f7ea3](https://github.com/Sequel-Ace/Sequel-Ace/commit/6e97f7ea37e127f4a6340dd044242bf7ca2cdf1b), [#1777](https://github.com/Sequel-Ace/Sequel-Ace/pull/1777))
- New Crowdin updates ([01d979f64](https://github.com/Sequel-Ace/Sequel-Ace/commit/01d979f64ca4bcee82d04ba243d6567f9cf7dd28), [#1768](https://github.com/Sequel-Ace/Sequel-Ace/pull/1768))
- New Crowdin updates ([d9b5e63ee](https://github.com/Sequel-Ace/Sequel-Ace/commit/d9b5e63eea1cbacee90790abe3d21996d847a4b6), [#1752](https://github.com/Sequel-Ace/Sequel-Ace/pull/1752))
- possible active window cycling fix for issue #1666 ([d89c0eea7](https://github.com/Sequel-Ace/Sequel-Ace/commit/d89c0eea79418d4b9fbe54f5d97b585f07e0f99f), [#1736](https://github.com/Sequel-Ace/Sequel-Ace/pull/1736))
- New Crowdin updates ([8c0acfcf0](https://github.com/Sequel-Ace/Sequel-Ace/commit/8c0acfcf04d3c955770d54c1153355c0407ffe76), [#1749](https://github.com/Sequel-Ace/Sequel-Ace/pull/1749))
- Attempt to fix issues with automated tests not running ([62992297d](https://github.com/Sequel-Ace/Sequel-Ace/commit/62992297da2ffc930e577a9d0b2899ef1a403953))
- New Crowdin updates ([92c04cca4](https://github.com/Sequel-Ace/Sequel-Ace/commit/92c04cca4463ef94de4fbbfc37bcf2b4f7365c86), [#1748](https://github.com/Sequel-Ace/Sequel-Ace/pull/1748))
- Warning fixes ([3e492fe48](https://github.com/Sequel-Ace/Sequel-Ace/commit/3e492fe48d17a10ae58ec5b90b9322c5d3ac27cc))
- Update AppCenter ([cd143d6ae](https://github.com/Sequel-Ace/Sequel-Ace/commit/cd143d6ae07212f16419806d0f9fdac55502e884))
- Update Alamofire ([aa69896ed](https://github.com/Sequel-Ace/Sequel-Ace/commit/aa69896ed48cc99a8ce411da46c150d9ea828f20))
- Update dependencies ([f80958e76](https://github.com/Sequel-Ace/Sequel-Ace/commit/f80958e766e7fb9cb96d45a8b280f19a77777d6d))
- New Crowdin updates ([98822e355](https://github.com/Sequel-Ace/Sequel-Ace/commit/98822e355c4c0d2447cf8aab32877113125003dc), [#1725](https://github.com/Sequel-Ace/Sequel-Ace/pull/1725))
- New Crowdin updates ([21a431fea](https://github.com/Sequel-Ace/Sequel-Ace/commit/21a431fea443fdb60a79d86cb3bfb93972c087a8), [#1718](https://github.com/Sequel-Ace/Sequel-Ace/pull/1718))
- New Crowdin updates ([b6684e508](https://github.com/Sequel-Ace/Sequel-Ace/commit/b6684e508bbecd5bf9dae62d29d53f136c8cc5ed), [#1717](https://github.com/Sequel-Ace/Sequel-Ace/pull/1717))
- New Crowdin updates ([c0772e1ec](https://github.com/Sequel-Ace/Sequel-Ace/commit/c0772e1ecc263f5fbd6eb9dbd38524ac041892c6), [#1715](https://github.com/Sequel-Ace/Sequel-Ace/pull/1715))
- New Crowdin updates ([0ade170a5](https://github.com/Sequel-Ace/Sequel-Ace/commit/0ade170a55f8531401e43d1409d576ca27143d8f), [#1708](https://github.com/Sequel-Ace/Sequel-Ace/pull/1708))
- Try to fix tests running ([eb02f0d02](https://github.com/Sequel-Ace/Sequel-Ace/commit/eb02f0d02f99d130d1b939073fdc29c25a096b40), [#1704](https://github.com/Sequel-Ace/Sequel-Ace/pull/1704))
- New Crowdin updates ([aa7b45cfe](https://github.com/Sequel-Ace/Sequel-Ace/commit/aa7b45cfe6ab54dbf15538cba9987263a2420ca6), [#1699](https://github.com/Sequel-Ace/Sequel-Ace/pull/1699))
- font size changing when enabling column types ([def80c390](https://github.com/Sequel-Ace/Sequel-Ace/commit/def80c390501407f26e06b6e6afc8d7ebe0a043e), [#1687](https://github.com/Sequel-Ace/Sequel-Ace/pull/1687))
- New Crowdin updates ([ab2c32010](https://github.com/Sequel-Ace/Sequel-Ace/commit/ab2c32010d77df141533b6de2ff8c89c33717885), [#1686](https://github.com/Sequel-Ace/Sequel-Ace/pull/1686))

### Removed


### Infra
- Bump commonmarker from 0.23.7 to 0.23.9 in /docs ([0566ebe18](https://github.com/Sequel-Ace/Sequel-Ace/commit/0566ebe18f720e1b01b94ba37c01221772933d20), [#1740](https://github.com/Sequel-Ace/Sequel-Ace/pull/1740))
- Bump nokogiri from 1.13.10 to 1.14.3 in /docs ([6ec9cc2da](https://github.com/Sequel-Ace/Sequel-Ace/commit/6ec9cc2daa05f5faab5c0c64561395cb9ac6e03b), [#1741](https://github.com/Sequel-Ace/Sequel-Ace/pull/1741))
- Bump activesupport from 6.0.5 to 6.0.6.1 in /docs ([4cbdc7c7d](https://github.com/Sequel-Ace/Sequel-Ace/commit/4cbdc7c7d1cbbfafcad2ccb0843c3299d5e4c385), [#1695](https://github.com/Sequel-Ace/Sequel-Ace/pull/1695))
- Bump commonmarker from 0.23.6 to 0.23.7 in /docs ([b83e4c055](https://github.com/Sequel-Ace/Sequel-Ace/commit/b83e4c0558797d7d43a08b03f5129519fcd3b651), [#1691](https://github.com/Sequel-Ace/Sequel-Ace/pull/1691))

## [4.0.5](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.5+%28*%29%22&expanded=true)

### Added
- Add preference for column types visibility ([9c3dd59fd](https://github.com/Sequel-Ace/Sequel-Ace/commit/9c3dd59fd12a5cc00cbad8445d3c9f2e537302f8), [#1657](https://github.com/Sequel-Ace/Sequel-Ace/pull/1657))

### Fixed


### Changed
- Prepare release ([983dc30a8](https://github.com/Sequel-Ace/Sequel-Ace/commit/983dc30a85cf23e6402a340869e546dc56a128e3), [#1672](https://github.com/Sequel-Ace/Sequel-Ace/pull/1672))
- Prepare Beta release ([91288f6ec](https://github.com/Sequel-Ace/Sequel-Ace/commit/91288f6ec037f0ac5ddff499f407b7923b71464e), [#1671](https://github.com/Sequel-Ace/Sequel-Ace/pull/1671))
- Merge pull request #1670 from Sequel-Ace/fix/Allow-passwords-with-special-characters-by-escaping-special-chars ([e23193b39](https://github.com/Sequel-Ace/Sequel-Ace/commit/e23193b39e865de493658624edc52dca2d4f3513), [#1670](https://github.com/Sequel-Ace/Sequel-Ace/pull/1670))
- Merge pull request #1668 from Sequel-Ace/fix/Enums-cut-off-in-UI ([b625e1e4c](https://github.com/Sequel-Ace/Sequel-Ace/commit/b625e1e4cf734445c1660aa38f55fdd451f4ad5c), [#1668](https://github.com/Sequel-Ace/Sequel-Ace/pull/1668))
- Merge pull request #1669 from Sequel-Ace/fix/Export-error-on-changing-databases ([c979bb6fd](https://github.com/Sequel-Ace/Sequel-Ace/commit/c979bb6fdb16e45f3deb216eb97c20ddbaa0a047), [#1669](https://github.com/Sequel-Ace/Sequel-Ace/pull/1669))
- Merge pull request #1664 from Sequel-Ace/fix/Bundle-runner-not-getting-document-ENV ([c42b6acba](https://github.com/Sequel-Ace/Sequel-Ace/commit/c42b6acba25c6ced04e36f76cb1e8a300593bc50), [#1664](https://github.com/Sequel-Ace/Sequel-Ace/pull/1664))
- Merge pull request #1665 from Sequel-Ace/fix/Selected-tables-list-excludes-views ([8b57ee167](https://github.com/Sequel-Ace/Sequel-Ace/commit/8b57ee1673cd2e520b0f001e6b8361663b7b92bf), [#1665](https://github.com/Sequel-Ace/Sequel-Ace/pull/1665))
- Merge pull request #1663 from Sequel-Ace/fix/Content-view-crashing-on-columns-containing-dollar-signs ([40615bf02](https://github.com/Sequel-Ace/Sequel-Ace/commit/40615bf02be90bff9d845ba584ce86e84018b40b), [#1663](https://github.com/Sequel-Ace/Sequel-Ace/pull/1663))
- Merge pull request #1662 from Sequel-Ace/fix/Default-value-empty-string-not-able-to-be-set ([5a78eeb7a](https://github.com/Sequel-Ace/Sequel-Ace/commit/5a78eeb7a54e2096540cdc3b597b85ad71e10356), [#1662](https://github.com/Sequel-Ace/Sequel-Ace/pull/1662))
- Error when altering Timestamp/Datetime columns in structure view ([1a47d5242](https://github.com/Sequel-Ace/Sequel-Ace/commit/1a47d5242671f08f33605fed75600f70ddc85fd8), [#1661](https://github.com/Sequel-Ace/Sequel-Ace/pull/1661))

### Removed


### Infra


## [4.0.4](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.4+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix column types when copying content with column types and when exporting ([9f6d5ec01](https://github.com/Sequel-Ace/Sequel-Ace/commit/9f6d5ec016ef8ba6cd89fc7d2b33b9e614fac0c8), [#1632](https://github.com/Sequel-Ace/Sequel-Ace/pull/1632))

### Changed
- Prepare release ([01e8d3e61](https://github.com/Sequel-Ace/Sequel-Ace/commit/01e8d3e61cb109cca309d32d851894baed17ac1a), [#1653](https://github.com/Sequel-Ace/Sequel-Ace/pull/1653))
- Temporary Hotfix: Kill the task after termination ([b09e83dfc](https://github.com/Sequel-Ace/Sequel-Ace/commit/b09e83dfc18f6d6ce2c40d7461274d2fe5838ef1), [#1650](https://github.com/Sequel-Ace/Sequel-Ace/pull/1650))
- Merge pull request #1646 from Sequel-Ace/dependabot/bundler/docs/nokogiri-1.13.10 ([83028062d](https://github.com/Sequel-Ace/Sequel-Ace/commit/83028062dad6bc5c60594b091db9365c21392c4e), [#1646](https://github.com/Sequel-Ace/Sequel-Ace/pull/1646))
- New Crowdin updates ([9600dc476](https://github.com/Sequel-Ace/Sequel-Ace/commit/9600dc4760bd600f367006e8375a3bae5384742b), [#1644](https://github.com/Sequel-Ace/Sequel-Ace/pull/1644))
- Merge pull request #1643 from Sequel-Ace/l10n_main ([67b929fea](https://github.com/Sequel-Ace/Sequel-Ace/commit/67b929feabe1406a13cee200323b7027d78caa60), [#1643](https://github.com/Sequel-Ace/Sequel-Ace/pull/1643))
- Prepare Beta release ([1dd015ef1](https://github.com/Sequel-Ace/Sequel-Ace/commit/1dd015ef14d750558a44fe94e2f4a7ea50065b53), [#1636](https://github.com/Sequel-Ace/Sequel-Ace/pull/1636))
- Move OCMock to SPM from included framework ([e2d231a1b](https://github.com/Sequel-Ace/Sequel-Ace/commit/e2d231a1b7a84987d5466aadbcbdea187c94b4db), [#1634](https://github.com/Sequel-Ace/Sequel-Ace/pull/1634))
- Update OpenSSL to 1.1.1s ([55f6cc021](https://github.com/Sequel-Ace/Sequel-Ace/commit/55f6cc02134fe31edada6c6a59c54dda19c7b5a7), [#1633](https://github.com/Sequel-Ace/Sequel-Ace/pull/1633))
- Autocomplete weirdness ([49ec01cbd](https://github.com/Sequel-Ace/Sequel-Ace/commit/49ec01cbdb855c6ede242dc69dd82eafcf4e037e), [#1619](https://github.com/Sequel-Ace/Sequel-Ace/pull/1619))
- Pasting content in unloaded text/blob field causes crash ([4e1dfbecb](https://github.com/Sequel-Ace/Sequel-Ace/commit/4e1dfbecb2e3617ebe7fe6001619a9e1cbf584d3), [#1627](https://github.com/Sequel-Ace/Sequel-Ace/pull/1627))
- Merge pull request #1616 from luis-/bugfix/1509 ([c28e73be9](https://github.com/Sequel-Ace/Sequel-Ace/commit/c28e73be9ff7fa379294bcb2145af5eb5f351853), [#1616](https://github.com/Sequel-Ace/Sequel-Ace/pull/1616))
- Merge pull request #1617 from DannyJJK/filter-content-kb-shortcut ([445b50f27](https://github.com/Sequel-Ace/Sequel-Ace/commit/445b50f27fa037e770cc9cddd96db8a70bf946cb), [#1617](https://github.com/Sequel-Ace/Sequel-Ace/pull/1617))

### Removed


### Infra


## [4.0.3](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.3+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix copy as SQL insert, Fix users modal resizing ([81e087935](https://github.com/Sequel-Ace/Sequel-Ace/commit/81e087935ff8367f701cb495ec3defbcdbf0498b), [#1612](https://github.com/Sequel-Ace/Sequel-Ace/pull/1612))

### Changed
- Prepare release ([775519e31](https://github.com/Sequel-Ace/Sequel-Ace/commit/775519e3152077d1bc496851679ad217adba8fbe), [#1613](https://github.com/Sequel-Ace/Sequel-Ace/pull/1613))

### Removed


### Infra


## [4.0.2](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.2+%28*%29%22&expanded=true)

### Added
- Enable Help menu for connection screen ([9ccf9d191](https://github.com/Sequel-Ace/Sequel-Ace/commit/9ccf9d1915c979547e0ddb5318870a8327b75314), [#1589](https://github.com/Sequel-Ace/Sequel-Ace/pull/1589))

### Fixed


### Changed
- Prepare release ([b1cd8f527](https://github.com/Sequel-Ace/Sequel-Ace/commit/b1cd8f5270065c2435e556ca296ee746e59d38d4), [#1608](https://github.com/Sequel-Ace/Sequel-Ace/pull/1608))
- Prepare Beta release ([a448babd5](https://github.com/Sequel-Ace/Sequel-Ace/commit/a448babd5966166542c64e3e51bc1c5180f7f52c), [#1607](https://github.com/Sequel-Ace/Sequel-Ace/pull/1607))
- Text is not invalidated if just a cut or paste action is executed ([e8fa94874](https://github.com/Sequel-Ace/Sequel-Ace/commit/e8fa94874ff5eb257129f46017a2a3f82a88728f), [#1605](https://github.com/Sequel-Ace/Sequel-Ace/pull/1605))
- Merge pull request #1604 from Sequel-Ace/filtering ([45e1ae3ff](https://github.com/Sequel-Ace/Sequel-Ace/commit/45e1ae3ff3be634a191cca85a75816d21becb1e8), [#1604](https://github.com/Sequel-Ace/Sequel-Ace/pull/1604))
- Update stale.yml ([2e6d73f97](https://github.com/Sequel-Ace/Sequel-Ace/commit/2e6d73f97fabe5f7caa4c8988798b9d1226852c2))
- Show column type in query editor and content view ([51fad2462](https://github.com/Sequel-Ace/Sequel-Ace/commit/51fad2462c091f3cea4a838fa528a176c2bda162), [#1588](https://github.com/Sequel-Ace/Sequel-Ace/pull/1588))

### Removed
- Remove data type names from CSV exports ([0756e8359](https://github.com/Sequel-Ace/Sequel-Ace/commit/0756e83590746351135de039f863c18b97d4c784), [#1606](https://github.com/Sequel-Ace/Sequel-Ace/pull/1606))

### Infra


## [4.0.1](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.1+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix closing all connections that are being opened ([1b531f4c4](https://github.com/Sequel-Ace/Sequel-Ace/commit/1b531f4c4767027f38edcfcbf67719937a6f8ec5), [#1585](https://github.com/Sequel-Ace/Sequel-Ace/pull/1585))

### Changed
- Prepare 4.0.1 release ([5777a071c](https://github.com/Sequel-Ace/Sequel-Ace/commit/5777a071c0c12da1dd23304bbc1e2f540fd4a4b0), [#1586](https://github.com/Sequel-Ace/Sequel-Ace/pull/1586))
- Update CHANGELOG.md ([a54b66437](https://github.com/Sequel-Ace/Sequel-Ace/commit/a54b664379099c9073f78a5abf1d21b24e1d6203))
- Update bundler ([95aa80269](https://github.com/Sequel-Ace/Sequel-Ace/commit/95aa80269aab512e767c952e35b9c0a59e3fa2f4))
- New Crowdin updates ([c28cf9458](https://github.com/Sequel-Ace/Sequel-Ace/commit/c28cf9458175ad4aa9e87d65185a608d573ebe83), [#1584](https://github.com/Sequel-Ace/Sequel-Ace/pull/1584))
- Push new release to resolve build version mismatch and incomplete 4.0.0 release ([812220fc9](https://github.com/Sequel-Ace/Sequel-Ace/commit/812220fc981a0504c8dfbaacf8392beaec74338c), [#1581](https://github.com/Sequel-Ace/Sequel-Ace/pull/1581))

### Removed


### Infra
- Bump nokogiri from 1.13.6 to 1.13.9 in /docs ([a6dab89a9](https://github.com/Sequel-Ace/Sequel-Ace/commit/a6dab89a93ebb92cab2f0ddcdb17b5b0314a5d19), [#1583](https://github.com/Sequel-Ace/Sequel-Ace/pull/1583))

## [4.0.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%224.0.0+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix small typo on Export dialog ([c9d037a35](https://github.com/Sequel-Ace/Sequel-Ace/commit/c9d037a35b6c0501ed0e336753f439ed3520a764), [#1568](https://github.com/Sequel-Ace/Sequel-Ace/pull/1568))
- Fix major memory leak with database document not being released ([f8f016ca0](https://github.com/Sequel-Ace/Sequel-Ace/commit/f8f016ca084b315230cb97ecf7c7dfee89c615a9), [#1529](https://github.com/Sequel-Ace/Sequel-Ace/pull/1529))
- Fix crash on right click when field editor is active ([6381ff811](https://github.com/Sequel-Ace/Sequel-Ace/commit/6381ff811a861376c4132e85b17df5ab47f59555), [#1525](https://github.com/Sequel-Ace/Sequel-Ace/pull/1525))
- Fix deprecations and warnings ([dd6d02c5e](https://github.com/Sequel-Ace/Sequel-Ace/commit/dd6d02c5ed3778050c7a1238739a244127b88867), [#1523](https://github.com/Sequel-Ace/Sequel-Ace/pull/1523))
- Fix saving session more than once ([2dd099f6e](https://github.com/Sequel-Ace/Sequel-Ace/commit/2dd099f6ed416a5c564766e6cc711693bfe65bc5), [#1522](https://github.com/Sequel-Ace/Sequel-Ace/pull/1522))

### Changed
- Prepare release ([177c19d4e](https://github.com/Sequel-Ace/Sequel-Ace/commit/177c19d4e6b32869054e5c021f0de6bb418fa6e0), [#1576](https://github.com/Sequel-Ace/Sequel-Ace/pull/1576))
- Make analytics opt-out ([968d5361c](https://github.com/Sequel-Ace/Sequel-Ace/commit/968d5361c399aafbdbb237ef421a2fdca2191ed6), [#1564](https://github.com/Sequel-Ace/Sequel-Ace/pull/1564))
- Merge pull request #1563 from Sequel-Ace/dependabot/bundler/docs/commonmarker-0.23.6 ([e0d7a1507](https://github.com/Sequel-Ace/Sequel-Ace/commit/e0d7a1507d04d1e0ce89b129ce1b4d46d4dced11), [#1563](https://github.com/Sequel-Ace/Sequel-Ace/pull/1563))
- Merge pull request #1542 from stefanfuerst/Saving-Bug ([8367cfc73](https://github.com/Sequel-Ace/Sequel-Ace/commit/8367cfc73078af5df16f1254d62229ed7d78cf95), [#1542](https://github.com/Sequel-Ace/Sequel-Ace/pull/1542))
- New Crowdin updates ([d21ed46da](https://github.com/Sequel-Ace/Sequel-Ace/commit/d21ed46da0f7b0d2d15230983918e1ba9c752825), [#1544](https://github.com/Sequel-Ace/Sequel-Ace/pull/1544))
- Portuguese localization ([e37e799e2](https://github.com/Sequel-Ace/Sequel-Ace/commit/e37e799e2e01b8fa5744603cd11397f41df98bce), [#1543](https://github.com/Sequel-Ace/Sequel-Ace/pull/1543))
- Update readme.md ([e4f8c0702](https://github.com/Sequel-Ace/Sequel-Ace/commit/e4f8c0702a4fbe7bd0cbc37298d2cbf5b457d03a))
- Prepare Beta release ([a50cb4840](https://github.com/Sequel-Ace/Sequel-Ace/commit/a50cb4840f1dbcb3028d68ba0e4672ad12597a63), [#1532](https://github.com/Sequel-Ace/Sequel-Ace/pull/1532))
- Breaking change: Officially drop MySQL 5.6 support ([260923540](https://github.com/Sequel-Ace/Sequel-Ace/commit/260923540ba4abe5f25bb15f656128b37fe37ada), [#1531](https://github.com/Sequel-Ace/Sequel-Ace/pull/1531))
- Move upload_symbols into an inline run script - non-inline run scripts are not supported by XCode Cloud ([45dbcb3ff](https://github.com/Sequel-Ace/Sequel-Ace/commit/45dbcb3ff93804beb0d4f2b7290f2072d8352611))
- Merge branch 'main' of https://github.com/Sequel-Ace/Sequel-Ace ([a6a780485](https://github.com/Sequel-Ace/Sequel-Ace/commit/a6a780485e598c0c98a958bc6ce1da7f6dba8761))
- New Crowdin updates ([0b3273317](https://github.com/Sequel-Ace/Sequel-Ace/commit/0b3273317f1ef8a60fe62d7ee3dfa220bfe28cb2), [#1526](https://github.com/Sequel-Ace/Sequel-Ace/pull/1526))

### Removed
- Remove extra quotes from upload symbols ([0dc3f105a](https://github.com/Sequel-Ace/Sequel-Ace/commit/0dc3f105ad120e4e98cf2fe16e64cd17b6d8bc8c))
- Drop macOS 10.12 ([6183c515b](https://github.com/Sequel-Ace/Sequel-Ace/commit/6183c515ba602970e469c9a80446788997f38b98), [#1521](https://github.com/Sequel-Ace/Sequel-Ace/pull/1521))

### Infra


## [3.5.3](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.5.3+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix preferences path, keychain path, formatting ([ed74fc85f](https://github.com/Sequel-Ace/Sequel-Ace/commit/ed74fc85ff1bdf77c511223515e603684dfd575b), [#1484](https://github.com/Sequel-Ace/Sequel-Ace/pull/1484))

### Changed
- Prepare release ([6f8578e99](https://github.com/Sequel-Ace/Sequel-Ace/commit/6f8578e995e8c708874547a989dcca679f2856eb), [#1524](https://github.com/Sequel-Ace/Sequel-Ace/pull/1524))
- rename schemes ([24d4d9475](https://github.com/Sequel-Ace/Sequel-Ace/commit/24d4d9475e41a29d63663fee12dd3374296e250c))
- Update mamp-xampp.md ([e8160a0a7](https://github.com/Sequel-Ace/Sequel-Ace/commit/e8160a0a74b6dbb4ba6aa56696372691b0c4c98a))
- Update MAMP Documentation regarding settings to connect ([ebeb253cf](https://github.com/Sequel-Ace/Sequel-Ace/commit/ebeb253cf299ae0c3f7eb248f23b8d2d2e2900c0), [#1488](https://github.com/Sequel-Ace/Sequel-Ace/pull/1488))
- Merge pull request #1502 from Sequel-Ace/l10n_main ([8435e74dc](https://github.com/Sequel-Ace/Sequel-Ace/commit/8435e74dc79e27c07e57880171bab19fc7c6fcd7), [#1502](https://github.com/Sequel-Ace/Sequel-Ace/pull/1502))
- New Crowdin updates ([5aafd0666](https://github.com/Sequel-Ace/Sequel-Ace/commit/5aafd0666790a22fd0d8eeb451ed8a007a4bb368), [#1500](https://github.com/Sequel-Ace/Sequel-Ace/pull/1500))
- Merge branch 'crowdin_updates' ([12944b16d](https://github.com/Sequel-Ace/Sequel-Ace/commit/12944b16d1537917e3b74c76a1fb1709341e38fd))
- Update Crowdin configuration file ([772ab94e7](https://github.com/Sequel-Ace/Sequel-Ace/commit/772ab94e7832f2219439690242ee425e521c1251))
- (Infra) Update translations process ([e13aa98aa](https://github.com/Sequel-Ace/Sequel-Ace/commit/e13aa98aaaa76caa365f6cd2e52374f3acd8614a), [#1499](https://github.com/Sequel-Ace/Sequel-Ace/pull/1499))
- Update docs ([ea2b5cfe5](https://github.com/Sequel-Ace/Sequel-Ace/commit/ea2b5cfe53fb8e70f84cc861b46560a1ee0d51f5))
- Prepare Beta release ([82d1b9fda](https://github.com/Sequel-Ace/Sequel-Ace/commit/82d1b9fda513f021acbe07ef79e3446083432429), [#1483](https://github.com/Sequel-Ace/Sequel-Ace/pull/1483))
- [CLEANUP] Migration HowTo ([b10de4478](https://github.com/Sequel-Ace/Sequel-Ace/commit/b10de4478efbe1f8f8b4870206382d57d1d4ad43), [#1476](https://github.com/Sequel-Ace/Sequel-Ace/pull/1476))
- Merge pull request #1465 from Sequel-Ace/dependabot/bundler/docs/nokogiri-1.13.6 ([c1d6f01c1](https://github.com/Sequel-Ace/Sequel-Ace/commit/c1d6f01c13dd774eaac8dcd5e7a6e634af022e8d), [#1465](https://github.com/Sequel-Ace/Sequel-Ace/pull/1465))
- Merge pull request #1447 from mmackh/main ([478f7bb97](https://github.com/Sequel-Ace/Sequel-Ace/commit/478f7bb97947c8e6e473205a295c91630b827cb1), [#1447](https://github.com/Sequel-Ace/Sequel-Ace/pull/1447))

### Removed
- Remove update strings ([c831ba593](https://github.com/Sequel-Ace/Sequel-Ace/commit/c831ba59348e20f7cadcc6eb08cecba49a641ad3))

### Infra
- Bump tzinfo from 1.2.9 to 1.2.10 in /docs ([4c7ec4bbd](https://github.com/Sequel-Ace/Sequel-Ace/commit/4c7ec4bbd9a548d0f6d70cfe7cc3b68f007dd784), [#1507](https://github.com/Sequel-Ace/Sequel-Ace/pull/1507))
- Bump actions/checkout from 2 to 3 ([385ddc8d9](https://github.com/Sequel-Ace/Sequel-Ace/commit/385ddc8d901d006aa3c1bedd6988cbfeea615714), [#1470](https://github.com/Sequel-Ace/Sequel-Ace/pull/1470))
- Bump jmespath from 1.6.0 to 1.6.1 ([fc93c23ba](https://github.com/Sequel-Ace/Sequel-Ace/commit/fc93c23babd7254f5d3cc8a08603889c8bfcf266), [#1477](https://github.com/Sequel-Ace/Sequel-Ace/pull/1477))
- chore: Included githubactions in the dependabot config ([c5ecac7ef](https://github.com/Sequel-Ace/Sequel-Ace/commit/c5ecac7eff7525e563628723f8cb6967f6e91251), [#1469](https://github.com/Sequel-Ace/Sequel-Ace/pull/1469))
- chore: Set permissions for GitHub actions ([02a269fdd](https://github.com/Sequel-Ace/Sequel-Ace/commit/02a269fddb44da3b625b9e8041baaf9244286faf), [#1463](https://github.com/Sequel-Ace/Sequel-Ace/pull/1463))
- Bump nokogiri from 1.13.3 to 1.13.4 in /docs ([c019f7f88](https://github.com/Sequel-Ace/Sequel-Ace/commit/c019f7f885983b96ab05d62842fd3a2d7070a5f6), [#1445](https://github.com/Sequel-Ace/Sequel-Ace/pull/1445))

## [3.5.2](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.5.2+%28*%29%22&expanded=true)

### Added
- Add Italian ([ed4ad251d](https://github.com/Sequel-Ace/Sequel-Ace/commit/ed4ad251de3feacac35f4daf6ad8d31840629847))

### Fixed


### Changed
- Prepare release ([9bb4216ae](https://github.com/Sequel-Ace/Sequel-Ace/commit/9bb4216aefbc7e536c3180bb090b433b3a5cf874), [#1432](https://github.com/Sequel-Ace/Sequel-Ace/pull/1432))
- Possible fix for crash on tables with invisible columns ([c25b64a7d](https://github.com/Sequel-Ace/Sequel-Ace/commit/c25b64a7d033527973bb48b18df4bc010b880075), [#1421](https://github.com/Sequel-Ace/Sequel-Ace/pull/1421))
- Update strings ([6a23b4e70](https://github.com/Sequel-Ace/Sequel-Ace/commit/6a23b4e7014e7a42554dace287d71b2632da276e))
- Force upload symbols to always run to possibly fix build error in Xcode Cloud ([3a5afa977](https://github.com/Sequel-Ace/Sequel-Ace/commit/3a5afa9770a2e024c0639c02ed1bfbb6b6438a46))
- Prepare Beta release ([de3d9b273](https://github.com/Sequel-Ace/Sequel-Ace/commit/de3d9b2737495f1402b5cb29e4f03aaa74073cd7), [#1422](https://github.com/Sequel-Ace/Sequel-Ace/pull/1422))
- Only append a default value if its specified ([03c9e6f1b](https://github.com/Sequel-Ace/Sequel-Ace/commit/03c9e6f1b453e623ce1c6690ff081cc63d22184a), [#1418](https://github.com/Sequel-Ace/Sequel-Ace/pull/1418))
- Updatestrings ([114e9430c](https://github.com/Sequel-Ace/Sequel-Ace/commit/114e9430cde659258751c858d7b8580b54373d7e))

### Removed


### Infra


## [3.5.1](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.5.1+%28*%29%22&expanded=true)

### Added
- Add Airam alternative icon to Artwork ([ea17aaa3e](https://github.com/Sequel-Ace/Sequel-Ace/commit/ea17aaa3e42682188a0d2520eb186f62fd4f744e))
- Add Frnch localization ([385b93e26](https://github.com/Sequel-Ace/Sequel-Ace/commit/385b93e2607f3e9d7f85f4e96c6c0beb650300ca))
- support to copy table's name with database name in the list of tables ([3acc82a84](https://github.com/Sequel-Ace/Sequel-Ace/commit/3acc82a840f727485e242a9373332cacb94f6dec), [#1385](https://github.com/Sequel-Ace/Sequel-Ace/pull/1385))

### Fixed
- Fix strings that had issues ([e494fb44a](https://github.com/Sequel-Ace/Sequel-Ace/commit/e494fb44a743969dfa2127fbed777fc14fc8f911))

### Changed
- Prepare release ([1938e2065](https://github.com/Sequel-Ace/Sequel-Ace/commit/1938e206544448a0ce9a598654d60eeba1cc7fc7), [#1410](https://github.com/Sequel-Ace/Sequel-Ace/pull/1410))
- Store a couple more pieces of artwork that Jason previously made just in case they're useful ([4883ececc](https://github.com/Sequel-Ace/Sequel-Ace/commit/4883ececc4753ef02cc50c87b9b91462c9827af6))
- Update bundler ([bf4690a34](https://github.com/Sequel-Ace/Sequel-Ace/commit/bf4690a34088d733ff953417f7a0fc0ba3f74967))
- Share scheme ([929826a40](https://github.com/Sequel-Ace/Sequel-Ace/commit/929826a408fef479cad26d91944b952d1e814ab7))
- Prepare Beta release ([e17cb0baa](https://github.com/Sequel-Ace/Sequel-Ace/commit/e17cb0baa4b2e87851734ed9c4b18af9e2251833), [#1392](https://github.com/Sequel-Ace/Sequel-Ace/pull/1392))
- Attempt non-SSL connections if we fail connecting via SSL and SSL is not required ([e9ac3d3c6](https://github.com/Sequel-Ace/Sequel-Ace/commit/e9ac3d3c6978d01305a7d9e4be79c8aa7b969597), [#1381](https://github.com/Sequel-Ace/Sequel-Ace/pull/1381))

### Removed


### Infra
- Bump nokogiri from 1.12.5 to 1.13.3 in /docs ([492290511](https://github.com/Sequel-Ace/Sequel-Ace/commit/49229051114bf7ebb14ec005d767f66a338afd9f), [#1398](https://github.com/Sequel-Ace/Sequel-Ace/pull/1398))
- Infra cleanup, xcworkspace removal, hierarchy simplification ([4dac484cd](https://github.com/Sequel-Ace/Sequel-Ace/commit/4dac484cdc68fc6da47cae2d8000d3878d56b3ec), [#1389](https://github.com/Sequel-Ace/Sequel-Ace/pull/1389))

## [3.5.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.5.0+%28*%29%22&expanded=true)

### Added
- Support for pinning tables at top of tables list ([49ed54290](https://github.com/Sequel-Ace/Sequel-Ace/commit/49ed54290dbed226fdfc9f3fb70b0adc97def2d8), [#1236](https://github.com/Sequel-Ace/Sequel-Ace/pull/1236))

### Fixed
- Fix issue with new release notes for the new default value PR showing every single app open ([fca67ee01](https://github.com/Sequel-Ace/Sequel-Ace/commit/fca67ee01c258ee3cde0632191ad5bf721072b5a))

### Changed
- Prepare release ([adf31e85b](https://github.com/Sequel-Ace/Sequel-Ace/commit/adf31e85b300d607b904f29455f759299ae5f228), [#1382](https://github.com/Sequel-Ace/Sequel-Ace/pull/1382))
- Merge pull request #1376 from Sequel-Ace/fix-global-priviledges-broken ([66bece992](https://github.com/Sequel-Ace/Sequel-Ace/commit/66bece992132da990688c800e7f0df646dda1899), [#1376](https://github.com/Sequel-Ace/Sequel-Ace/pull/1376))
- Improved tab coloring appearance in Dark and Light modes ([8afb7e518](https://github.com/Sequel-Ace/Sequel-Ace/commit/8afb7e518eb8b3aea3d119b5be2c40f648a6ea6e), [#1371](https://github.com/Sequel-Ace/Sequel-Ace/pull/1371))
- Merge branch 'main' of github.com:Sequel-Ace/Sequel-Ace ([29c81690a](https://github.com/Sequel-Ace/Sequel-Ace/commit/29c81690a2327b59580e843a7eaaeb28b60f9ce4))
- Update RU strings ([ba9feb9b5](https://github.com/Sequel-Ace/Sequel-Ace/commit/ba9feb9b53e841de5762a8361546a407f3f18137))
- Update strings ([2bdb20f43](https://github.com/Sequel-Ace/Sequel-Ace/commit/2bdb20f43feb1fbb97a04429d4103d7c0d139cc8))
- Prepare Beta release ([5949f1bcf](https://github.com/Sequel-Ace/Sequel-Ace/commit/5949f1bcf23c9446d3484148cd736e41654af965), [#1362](https://github.com/Sequel-Ace/Sequel-Ace/pull/1362))
- Increment app version ([a1c479b42](https://github.com/Sequel-Ace/Sequel-Ace/commit/a1c479b42669efa1c5484593862534d0088158c4))
- Change default column behavior (Structure tab) - fix #1163 ([c9cb5c8b7](https://github.com/Sequel-Ace/Sequel-Ace/commit/c9cb5c8b745fddde92ad6e9d02cb5750f8e74f7f), [#1250](https://github.com/Sequel-Ace/Sequel-Ace/pull/1250))
- Accurately show SSL connection status always ([da43e08c8](https://github.com/Sequel-Ace/Sequel-Ace/commit/da43e08c87f8e7c9a57deca11373cf2bd4db1a84), [#1358](https://github.com/Sequel-Ace/Sequel-Ace/pull/1358))
- Clicking S[tructure] C[ontent] or D[rop] in export window will toggle the value for all tables ([18af48c02](https://github.com/Sequel-Ace/Sequel-Ace/commit/18af48c02ef790d91e5299a784ef28e0238584a6), [#1357](https://github.com/Sequel-Ace/Sequel-Ace/pull/1357))
- Allow sorting every column on the Structure "fields" table view ([a37b653c5](https://github.com/Sequel-Ace/Sequel-Ace/commit/a37b653c584ce96607ca8bc1603e1539e7c6622e), [#1355](https://github.com/Sequel-Ace/Sequel-Ace/pull/1355))
- Filter and Sorting to Structure "fields" Table View. ([7293fc50b](https://github.com/Sequel-Ace/Sequel-Ace/commit/7293fc50b9cf3a20f8d98ade0980a48271138155), [#1345](https://github.com/Sequel-Ace/Sequel-Ace/pull/1345))
- Prepare Beta release ([4da1e8df6](https://github.com/Sequel-Ace/Sequel-Ace/commit/4da1e8df6b82aacbd577d2e001771003d8d8c702), [#1353](https://github.com/Sequel-Ace/Sequel-Ace/pull/1353))
- Merge pull request #1350 from Sequel-Ace/only-check-for-newlines-in-NSStrings ([2f330503a](https://github.com/Sequel-Ace/Sequel-Ace/commit/2f330503a521a3a4b6068fd41c9e3f5552e9d803), [#1350](https://github.com/Sequel-Ace/Sequel-Ace/pull/1350))
- Update stale.yml ([8e17308d8](https://github.com/Sequel-Ace/Sequel-Ace/commit/8e17308d8e92d024ad8f19c8ee1524ffdfd86e8e))
- Change default query editor font to Menlo to improve query editor performance ([b002cae12](https://github.com/Sequel-Ace/Sequel-Ace/commit/b002cae12a01bedfefed340db6e570200daeee26), [#1341](https://github.com/Sequel-Ace/Sequel-Ace/pull/1341))

### Removed


### Infra


## [3.4.5](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.4.5+%28*%29%22&expanded=true)

### Added
- Add Find Next/Previous Menu Items with Shortcuts ([dbfc13693](https://github.com/Sequel-Ace/Sequel-Ace/commit/dbfc136931e086be85c74b30117724a494f4fab3), [#1332](https://github.com/Sequel-Ace/Sequel-Ace/pull/1332))
- Add even more paths ([e77be5020](https://github.com/Sequel-Ace/Sequel-Ace/commit/e77be50209a74d02beeed730cd20293d8fa9ac07))
- Add more lib paths ([a48451988](https://github.com/Sequel-Ace/Sequel-Ace/commit/a48451988a8b1325e515b3c56aa092bcccf156e5))

### Fixed
- Fix english localizable strings error ([d0f94f970](https://github.com/Sequel-Ace/Sequel-Ace/commit/d0f94f9707653bbbc3f9716530b21b65e6a650a2))
- Fix ssh connections broken by latest beta ([8b89abd03](https://github.com/Sequel-Ace/Sequel-Ace/commit/8b89abd03d08578319a3ddd8aac756cfe9fdffe7), [#1336](https://github.com/Sequel-Ace/Sequel-Ace/pull/1336))

### Changed
- Prepare release ([858f5d0a2](https://github.com/Sequel-Ace/Sequel-Ace/commit/858f5d0a20e72536f551d4f8e94cd55618b372a4), [#1339](https://github.com/Sequel-Ace/Sequel-Ace/pull/1339))
- Merge pull request #1338 from Sequel-Ace/fix-MariaDB-10.5.12-cannot-grant-db-privileges ([fd9eea010](https://github.com/Sequel-Ace/Sequel-Ace/commit/fd9eea010b6ea3c3aa967af041866dbdc84733b5), [#1338](https://github.com/Sequel-Ace/Sequel-Ace/pull/1338))
- Prepare Beta release ([b2be9f8e8](https://github.com/Sequel-Ace/Sequel-Ace/commit/b2be9f8e83c747a60c5caef5f6f14e90cd9afe8c), [#1337](https://github.com/Sequel-Ace/Sequel-Ace/pull/1337))
- Handle special characters in bookmark file names and paths ([285a4f697](https://github.com/Sequel-Ace/Sequel-Ace/commit/285a4f697bd9701f08dda6cdeeec9f1e4f59cb66), [#1335](https://github.com/Sequel-Ace/Sequel-Ace/pull/1335))
- Undo/Redo in Query Editor ([3ea8b8c4c](https://github.com/Sequel-Ace/Sequel-Ace/commit/3ea8b8c4c60b0d09b46743482012c0bcd42f8a95), [#1334](https://github.com/Sequel-Ace/Sequel-Ace/pull/1334))
- Update strings ([c22fb1627](https://github.com/Sequel-Ace/Sequel-Ace/commit/c22fb162704b50fa4b7585ebdf8c58493e4142fb))
- Merge pull request #1333 from luis-/fix/incorrect-font-in-query-editor ([0820bd0e0](https://github.com/Sequel-Ace/Sequel-Ace/commit/0820bd0e01cd16294c71be317bc75451f1e7d951), [#1333](https://github.com/Sequel-Ace/Sequel-Ace/pull/1333))
- Merge pull request #1329 from luis-/main ([80a8cf880](https://github.com/Sequel-Ace/Sequel-Ace/commit/80a8cf8801acc31c61063dde9554cef4b4ffe825), [#1329](https://github.com/Sequel-Ace/Sequel-Ace/pull/1329))
- Prepare Beta release ([6eae22092](https://github.com/Sequel-Ace/Sequel-Ace/commit/6eae22092473a47cfef18d944f708eebee1a312d), [#1328](https://github.com/Sequel-Ace/Sequel-Ace/pull/1328))
- Remove GeneratedColumn from 'Copy as SQL Insert' #1282 ([06794a4c5](https://github.com/Sequel-Ace/Sequel-Ace/commit/06794a4c50cb030326259a8f5c33ea98dfcf7382), [#1295](https://github.com/Sequel-Ace/Sequel-Ace/pull/1295))
- Merge pull request #1327 from Sequel-Ace/fix-1326_Allow-localhost-for-ssh-connections ([20caa1917](https://github.com/Sequel-Ace/Sequel-Ace/commit/20caa1917bce6468a9c22f4b92226cfe7ae5a8ce), [#1327](https://github.com/Sequel-Ace/Sequel-Ace/pull/1327))
- More logging around the upload symbols process to try to figure out what's wrong with xcode cloud ([ddb1a97b2](https://github.com/Sequel-Ace/Sequel-Ace/commit/ddb1a97b23c3e43af89c0a85300ce99176580356))
- Increment build version ([839b033b0](https://github.com/Sequel-Ace/Sequel-Ace/commit/839b033b0f7b883260db350a0ee2e8f8b36cadb5))

### Removed


### Infra


## [3.4.4](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.4.4+%28*%29%22&expanded=true)

### Added


### Fixed
- Fixed spreadsheet edit mode not honoring the cutoff length setting and add an option to edit multiline content in popup editor ([f8ae57d15](https://github.com/Sequel-Ace/Sequel-Ace/commit/f8ae57d15aa6e507f4b49f05e6782c69c2bc0f86), [#1324](https://github.com/Sequel-Ace/Sequel-Ace/pull/1324))
- Fixed JSON viewer UI bugs and occasional failures to parse ([5a65d1578](https://github.com/Sequel-Ace/Sequel-Ace/commit/5a65d157864858d4f3a1a3a05e0869b585a768c7), [#1323](https://github.com/Sequel-Ace/Sequel-Ace/pull/1323))
- Fix user editing crash ([4bd96b9f5](https://github.com/Sequel-Ace/Sequel-Ace/commit/4bd96b9f5a02d86b8a28c9aafb2f5935331a1cd3), [#1322](https://github.com/Sequel-Ace/Sequel-Ace/pull/1322))

### Changed
- Increment build version ([8f9dc6713](https://github.com/Sequel-Ace/Sequel-Ace/commit/8f9dc6713db082bd22f65d7469ba788bf5dc72dd))
- Update search paths for upload symbols script ([42cd8e9f1](https://github.com/Sequel-Ace/Sequel-Ace/commit/42cd8e9f12b5c880a709b6d2b368452bc81ffd10))
- Prepare release ([8f9421c81](https://github.com/Sequel-Ace/Sequel-Ace/commit/8f9421c81b724858632d597cf86e64c010c7a5dd), [#1325](https://github.com/Sequel-Ace/Sequel-Ace/pull/1325))
- Increment app patch version ([f616e9955](https://github.com/Sequel-Ace/Sequel-Ace/commit/f616e99553de0d129407f23c9db52545730a0f10))
- Silence scheme update warings ([8cef3ea2e](https://github.com/Sequel-Ace/Sequel-Ace/commit/8cef3ea2e7c9b1e6d5dc06ff5a8d13b8378513cd))
- Update strings, add Turkish ([8c7fb54ed](https://github.com/Sequel-Ace/Sequel-Ace/commit/8c7fb54ed72b5b7cfcaa5438ac9bbb9c04c21e3c))
- Update CI and frameworks ([3450feeda](https://github.com/Sequel-Ace/Sequel-Ace/commit/3450feedabc1a0812683aea3e60310cd4ffdc4e6))
- Merge pull request #1319 from soh335/fail-somecommandw-multiple-version-perl ([8d3eb7346](https://github.com/Sequel-Ace/Sequel-Ace/commit/8d3eb7346ff6dfb74aa94c62c2cab2c7b9ca3b25), [#1319](https://github.com/Sequel-Ace/Sequel-Ace/pull/1319))
- Show time in addition to date for table created and updated at dates ([00fa40e9b](https://github.com/Sequel-Ace/Sequel-Ace/commit/00fa40e9b1dc9ef2ae6e9458f0f5ce66d8f61f91), [#1314](https://github.com/Sequel-Ace/Sequel-Ace/pull/1314))

### Removed


### Infra


## [3.4.3](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.4.3+%28*%29%22&expanded=true)

### Added


### Fixed
- Recover from AppStoreConnect build number snafoo ([b3229194a](https://github.com/Sequel-Ace/Sequel-Ace/commit/b3229194a8663baecb303b1da6677b56e42d8389))
- Fix building issues for beta builds ([3f91af40e](https://github.com/Sequel-Ace/Sequel-Ace/commit/3f91af40e53ed78c288573b1c6f93d7c916008a7))
- Fix issues with fastlane building ([9ac27d627](https://github.com/Sequel-Ace/Sequel-Ace/commit/9ac27d627ad03fb8684a3f43498d61815351a582))

### Changed
- Prepare release ([2e5caa95a](https://github.com/Sequel-Ace/Sequel-Ace/commit/2e5caa95a7a974537de744e0f753e1653f5276f6), [#1313](https://github.com/Sequel-Ace/Sequel-Ace/pull/1313))
- Attempt app center fixes for Xcode Cloud ([58e233e7e](https://github.com/Sequel-Ace/Sequel-Ace/commit/58e233e7e0af0fcf20241bd07080916dbd6b962b), [#1312](https://github.com/Sequel-Ace/Sequel-Ace/pull/1312))
- #979 Properly reset the sorting column ([3c3131751](https://github.com/Sequel-Ace/Sequel-Ace/commit/3c3131751e475ba618e3648f6e5d98d5aee62a27), [#1299](https://github.com/Sequel-Ace/Sequel-Ace/pull/1299))
- Merge pull request #1297 from Sequel-Ace/fix-1290-TooltipsNotVisibleCompletely ([8b04e14db](https://github.com/Sequel-Ace/Sequel-Ace/commit/8b04e14db589bc4a4ec8160a03171add198e9812), [#1297](https://github.com/Sequel-Ace/Sequel-Ace/pull/1297))
- Merge branch 'main' of https://github.com/Sequel-Ace/Sequel-Ace ([9eb3fe492](https://github.com/Sequel-Ace/Sequel-Ace/commit/9eb3fe492e35e99647d5a201df448bfbba28da8d))
- Gitignore package.resolved ([b09c26da4](https://github.com/Sequel-Ace/Sequel-Ace/commit/b09c26da4139e5db5c3af9820fd2ee0135fecea8))
- Re-build libcrypto ([8f0071b2b](https://github.com/Sequel-Ace/Sequel-Ace/commit/8f0071b2b943f6837777f3b53578c07b346b6e3b))
- Update SPM, fi warnings ([343f8c92a](https://github.com/Sequel-Ace/Sequel-Ace/commit/343f8c92ab7caf85fe804dc30b3fc6b5af2344fb))
- Prepare Beta release ([cd49e369e](https://github.com/Sequel-Ace/Sequel-Ace/commit/cd49e369e6d630994467c3e6401a85a6893a0127), [#1292](https://github.com/Sequel-Ace/Sequel-Ace/pull/1292))
- More bundle execution refactoring ([c6695f627](https://github.com/Sequel-Ace/Sequel-Ace/commit/c6695f62798ffae6aefce9d29419547962023d3f), [#1274](https://github.com/Sequel-Ace/Sequel-Ace/pull/1274))
- Update SPExportFavoritesFilename to SequelAceFavorites.plist ([8604d481e](https://github.com/Sequel-Ace/Sequel-Ace/commit/8604d481e216e90ab479b452b140c947d4b71021), [#1287](https://github.com/Sequel-Ace/Sequel-Ace/pull/1287))
- Update index.md ([7d408d573](https://github.com/Sequel-Ace/Sequel-Ace/commit/7d408d5738e8bb434d887d293af4895ffc8c80d9))
- Update index.md ([890d5ec46](https://github.com/Sequel-Ace/Sequel-Ace/commit/890d5ec4697e6bb10508f435d85d29b52800f9d9))
- Merge pull request #1280 from Undo1/patch-1 ([654325c55](https://github.com/Sequel-Ace/Sequel-Ace/commit/654325c558f34c7716361afa1c337dcc5102fa50), [#1280](https://github.com/Sequel-Ace/Sequel-Ace/pull/1280))
- Update readme.md ([639ad5c02](https://github.com/Sequel-Ace/Sequel-Ace/commit/639ad5c020bec6bf945a83874d3ba73738226d1a))
- Extract duplicate bundle dispatch logic ([671eb8d6d](https://github.com/Sequel-Ace/Sequel-Ace/commit/671eb8d6da4ab251c48874bf1112244b2187a2dd), [#1273](https://github.com/Sequel-Ace/Sequel-Ace/pull/1273))
- Clean up bundle loading ([5c49df6a2](https://github.com/Sequel-Ace/Sequel-Ace/commit/5c49df6a2a3c0d93a33cf4cbb60d94ed8321e9be), [#1272](https://github.com/Sequel-Ace/Sequel-Ace/pull/1272))
- Merge pull request #1271 from Sequel-Ace/improve-local-dev-instructions ([416091439](https://github.com/Sequel-Ace/Sequel-Ace/commit/416091439bb910c396841066195c71670f667665), [#1271](https://github.com/Sequel-Ace/Sequel-Ace/pull/1271))
- Show tab color on the first tab after it's expanded #1216 ([864b9cb14](https://github.com/Sequel-Ace/Sequel-Ace/commit/864b9cb145ac6d7d263b1eb66cbadf751b27eba6), [#1263](https://github.com/Sequel-Ace/Sequel-Ace/pull/1263))

### Removed


### Infra


## [3.4.2](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.4.2+%28*%29%22&expanded=true)

### Added
- Add new line only when adding to existing queries ([c75945843](https://github.com/Sequel-Ace/Sequel-Ace/commit/c759458436e5b1f772e065850bdfd6e89a67b1a7), [#1260](https://github.com/Sequel-Ace/Sequel-Ace/pull/1260))
- Add Russian language ([e49c88e92](https://github.com/Sequel-Ace/Sequel-Ace/commit/e49c88e92cba0e4277668d0bb67cadaeef6e7520))

### Fixed
- Fix crash when adding a row locally ([f9fa6430e](https://github.com/Sequel-Ace/Sequel-Ace/commit/f9fa6430ed78597d5bcaa912c602cc8806fe7d49), [#1252](https://github.com/Sequel-Ace/Sequel-Ace/pull/1252))

### Changed
- Prepare release ([0ec06630e](https://github.com/Sequel-Ace/Sequel-Ace/commit/0ec06630eba02bcc977ac39658976bfcdbddfe67), [#1262](https://github.com/Sequel-Ace/Sequel-Ace/pull/1262))
- Merge pull request #1261 from alexkuc/main ([2ef252aaa](https://github.com/Sequel-Ace/Sequel-Ace/commit/2ef252aaabc1264c1a820cf132910e8301aabe08), [#1261](https://github.com/Sequel-Ace/Sequel-Ace/pull/1261))
- Make Preferences elements consistent #2 ([5ba8e1351](https://github.com/Sequel-Ace/Sequel-Ace/commit/5ba8e13510582dbe8329f6be95201a62c969c121), [#1259](https://github.com/Sequel-Ace/Sequel-Ace/pull/1259))
- Prepare Beta release ([82a4328b7](https://github.com/Sequel-Ace/Sequel-Ace/commit/82a4328b77c86efcc5c668b6d9a76ed225c56b01), [#1258](https://github.com/Sequel-Ace/Sequel-Ace/pull/1258))
- Reload query history after new entries are added ([904f9240d](https://github.com/Sequel-Ace/Sequel-Ace/commit/904f9240de7ff4b769dfb4439b763fa8e9f31122), [#1257](https://github.com/Sequel-Ace/Sequel-Ace/pull/1257))
- Favorite and placeholder display bug in query editor fixed ([72f4d43d5](https://github.com/Sequel-Ace/Sequel-Ace/commit/72f4d43d50a72d270fc76fb516f74080ed7621d8), [#1256](https://github.com/Sequel-Ace/Sequel-Ace/pull/1256))
- Make Preferences elements consistent ([88fb0a7da](https://github.com/Sequel-Ace/Sequel-Ace/commit/88fb0a7da9c6e0925f377f18a75c40a7d04df051), [#1251](https://github.com/Sequel-Ace/Sequel-Ace/pull/1251))
- Merge pull request #1243 from dnicolson/fix-double-check ([47da1e8c0](https://github.com/Sequel-Ace/Sequel-Ace/commit/47da1e8c0729267ac8fe3cda464cd18ea90b9902), [#1243](https://github.com/Sequel-Ace/Sequel-Ace/pull/1243))
- Allow Updating in Joined Instances ([0f03c3a68](https://github.com/Sequel-Ace/Sequel-Ace/commit/0f03c3a68db0348dfd8ed4f853ee59cd61c33d7a), [#1247](https://github.com/Sequel-Ace/Sequel-Ace/pull/1247))
- Merge pull request #1245 from dnicolson/improve-stale-bookmark-ux ([74fa88ab9](https://github.com/Sequel-Ace/Sequel-Ace/commit/74fa88ab9e18b1256d51173e5b972bea208802e9), [#1245](https://github.com/Sequel-Ace/Sequel-Ace/pull/1245))
- Merge pull request #1246 from dnicolson/fix-multiple-bookmark-removal ([eae141461](https://github.com/Sequel-Ace/Sequel-Ace/commit/eae14146172b1c952973df6c9874808db35930fa), [#1246](https://github.com/Sequel-Ace/Sequel-Ace/pull/1246))
- Merge pull request #1242 from dnicolson/improve-version-check ([43d3f412b](https://github.com/Sequel-Ace/Sequel-Ace/commit/43d3f412bc75dd330f08a97a11cf706f229f909c), [#1242](https://github.com/Sequel-Ace/Sequel-Ace/pull/1242))
- Merge pull request #1237 from mazedlx/patch-1 ([1b60019f8](https://github.com/Sequel-Ace/Sequel-Ace/commit/1b60019f897778fe4d9aa3404dfa9f05727eafdc), [#1237](https://github.com/Sequel-Ace/Sequel-Ace/pull/1237))
- Merge pull request #1230 from Sequel-Ace/dependabot/bundler/docs/nokogiri-1.12.5 ([d908d8526](https://github.com/Sequel-Ace/Sequel-Ace/commit/d908d852692dc5fe361b8ab7a77eb7190b485f29), [#1230](https://github.com/Sequel-Ace/Sequel-Ace/pull/1230))
- Shortcut to show/hide toolbar. Shortcut to duplicate connection in new tab. ([4b298830d](https://github.com/Sequel-Ace/Sequel-Ace/commit/4b298830d171216c6ccd0e21ad10477e9e6af921), [#1229](https://github.com/Sequel-Ace/Sequel-Ace/pull/1229))
- Update strings ([46a560fb2](https://github.com/Sequel-Ace/Sequel-Ace/commit/46a560fb2a816e09c76076d3b08107dc98512cea))

### Removed
- Remove provisioning style line ([9a9fb579c](https://github.com/Sequel-Ace/Sequel-Ace/commit/9a9fb579c81a17b8a20a2bf95ce3fa5eb092d4f0))
- Remove redundant rawErrorText parameter ([c44118ffb](https://github.com/Sequel-Ace/Sequel-Ace/commit/c44118ffb945a73143e25d790e7fc71570b1ed6e), [#1233](https://github.com/Sequel-Ace/Sequel-Ace/pull/1233))
- Remove old Localized string ([aa1aac5df](https://github.com/Sequel-Ace/Sequel-Ace/commit/aa1aac5dfe9549a509cb0a2cfebbec05511b4e9b))

### Infra


## [3.4.1](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.4.1+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix stats counts not updating immediately for MySQL 8 ([a0ce9cc27](https://github.com/Sequel-Ace/Sequel-Ace/commit/a0ce9cc275d6585a93708ecacfab639b21a33fcc), [#1222](https://github.com/Sequel-Ace/Sequel-Ace/pull/1222))
- Fix issue with Check for Update Failing ([865043fae](https://github.com/Sequel-Ace/Sequel-Ace/commit/865043fae78c7c1ad47c8ea30a88d16d688d3862), [#1221](https://github.com/Sequel-Ace/Sequel-Ace/pull/1221))
- Resolved 'alter table' bug for generated column ([c0470af96](https://github.com/Sequel-Ace/Sequel-Ace/commit/c0470af968f5a54fc63ceff818de7d238c56517c), [#1212](https://github.com/Sequel-Ace/Sequel-Ace/pull/1212))
- Fix tab index when creating new tabs ([8f7c4ddd1](https://github.com/Sequel-Ace/Sequel-Ace/commit/8f7c4ddd1ac45797118823e133742e12217278d4), [#1202](https://github.com/Sequel-Ace/Sequel-Ace/pull/1202))

### Changed
- Prepare release ([3ef59e8fb](https://github.com/Sequel-Ace/Sequel-Ace/commit/3ef59e8fb53d67f75885772e29b890a0bde2d04c), [#1223](https://github.com/Sequel-Ace/Sequel-Ace/pull/1223))
- Prepare Beta release ([13a061e1d](https://github.com/Sequel-Ace/Sequel-Ace/commit/13a061e1d57071e398451b8d07d14d2fac0c54cd), [#1220](https://github.com/Sequel-Ace/Sequel-Ace/pull/1220))
- Possible fix for issues with reconnecting ([dd4d30939](https://github.com/Sequel-Ace/Sequel-Ace/commit/dd4d309396c610dbc31bc3c9f4c9af6e8200f7b0), [#1219](https://github.com/Sequel-Ace/Sequel-Ace/pull/1219))
- Prepare Beta release ([a4d1cfc12](https://github.com/Sequel-Ace/Sequel-Ace/commit/a4d1cfc1228a64d1f698029a6e7ab62c11eec895), [#1211](https://github.com/Sequel-Ace/Sequel-Ace/pull/1211))
- Second attempt to export to unwritable directory doesn't show failure message ([2ec88c1d4](https://github.com/Sequel-Ace/Sequel-Ace/commit/2ec88c1d42bf362969fcccf813aa949ba9d85292), [#1210](https://github.com/Sequel-Ace/Sequel-Ace/pull/1210))
- Merge pull request #1203 from dnicolson/fix-tab-switching ([279bdfaee](https://github.com/Sequel-Ace/Sequel-Ace/commit/279bdfaeebe7911537fc276c025fda1d55e9ce47), [#1203](https://github.com/Sequel-Ace/Sequel-Ace/pull/1203))
- Update strings ([2e5059d1f](https://github.com/Sequel-Ace/Sequel-Ace/commit/2e5059d1fd3fda9a6054bded05bf4ef4432e4624))
- Update SPM ([911e53256](https://github.com/Sequel-Ace/Sequel-Ace/commit/911e532562823959eec9b27541c33a06ddb0a35c))
- Update strings ([fb4b26a50](https://github.com/Sequel-Ace/Sequel-Ace/commit/fb4b26a50c2ebcd48e658b8abab90ed60a087663))

### Removed


### Infra


## [3.4.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.4.0+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix tabbing, titles and window order ([3dbc261f5](https://github.com/Sequel-Ace/Sequel-Ace/commit/3dbc261f5169797a4c06d9544dfda7608bbe9009), [#1181](https://github.com/Sequel-Ace/Sequel-Ace/pull/1181))
- Fixed buggy behavior when trying to edit a generated column ([304f4d62f](https://github.com/Sequel-Ace/Sequel-Ace/commit/304f4d62ffd2b47b212ec773adb703761547ceb6), [#1162](https://github.com/Sequel-Ace/Sequel-Ace/pull/1162))
- Fix character counts for multi-byte strings ([a30214a95](https://github.com/Sequel-Ace/Sequel-Ace/commit/a30214a953a227ea30c695ce6944a24a5e3ce11b), [#1165](https://github.com/Sequel-Ace/Sequel-Ace/pull/1165))

### Changed
- Prepare release ([608ecf997](https://github.com/Sequel-Ace/Sequel-Ace/commit/608ecf997c9d8d4d0dda28ac4e4699b756fc040c), [#1186](https://github.com/Sequel-Ace/Sequel-Ace/pull/1186))
- Merge pull request #1185 from Sequel-Ace/feature/better-error-message-for-generated-columns ([a76ca1982](https://github.com/Sequel-Ace/Sequel-Ace/commit/a76ca1982bd344521d56306595d79880bee14403), [#1185](https://github.com/Sequel-Ace/Sequel-Ace/pull/1185))
- Revert accidentally prematurely updating the changelog ([8b046706c](https://github.com/Sequel-Ace/Sequel-Ace/commit/8b046706ccc15420f07b99a150d0d21c85ca29f7))
- Prepare release ([43efe0809](https://github.com/Sequel-Ace/Sequel-Ace/commit/43efe080912d0e7669e3a4a828c2911d2201f135), [#1184](https://github.com/Sequel-Ace/Sequel-Ace/pull/1184))
- Merge pull request #1177 from mann/mann-patch-shortcuts ([9445ffd6d](https://github.com/Sequel-Ace/Sequel-Ace/commit/9445ffd6d8aa9fdd5821f2355fdc12e4a48028e0), [#1177](https://github.com/Sequel-Ace/Sequel-Ace/pull/1177))
- Update autoPullBack.yml ([8eee05738](https://github.com/Sequel-Ace/Sequel-Ace/commit/8eee057381a9f76aebe476359409c025f6143a16))
- Update readme.md ([e580fbc6a](https://github.com/Sequel-Ace/Sequel-Ace/commit/e580fbc6ab9484776fc5c895641a8653bae998d5))
- Update autoPullBack.yml ([cb3adfb82](https://github.com/Sequel-Ace/Sequel-Ace/commit/cb3adfb8250f0d9c9b0c68f9977d020246032ef4))
- Update autoPullBack.yml ([ad9c6fe3e](https://github.com/Sequel-Ace/Sequel-Ace/commit/ad9c6fe3ea9b34983f59326cf57a48b98ba38c13))
- Update readme.md ([e58e3baa8](https://github.com/Sequel-Ace/Sequel-Ace/commit/e58e3baa865f587c317425c30124dfdd4465590c))
- Keep PRs in sync with main branch always ([96cd00ab3](https://github.com/Sequel-Ace/Sequel-Ace/commit/96cd00ab3625e0933635ae235a23ea7294f297b6))
- Prepare Beta release ([c0d7fcb0a](https://github.com/Sequel-Ace/Sequel-Ace/commit/c0d7fcb0a338350e76ffca072abff08d2ecabdcd), [#1170](https://github.com/Sequel-Ace/Sequel-Ace/pull/1170))
- Prepare Beta release ([294f0a426](https://github.com/Sequel-Ace/Sequel-Ace/commit/294f0a426b1e920d373b570bf61f83b3f49d8099), [#1158](https://github.com/Sequel-Ace/Sequel-Ace/pull/1158))
- Changes about type GENERATED ALWAYS ([d827b10d6](https://github.com/Sequel-Ace/Sequel-Ace/commit/d827b10d61928e4e9690cfb0b2f552bc4ae54c00), [#1155](https://github.com/Sequel-Ace/Sequel-Ace/pull/1155))
- Switch to latest macOS and XCode ([ba830cbf1](https://github.com/Sequel-Ace/Sequel-Ace/commit/ba830cbf1d4ecbef6de8df9bbbb37bf35982461a))
- Update strings, add Vietnamese ([0de78a1b5](https://github.com/Sequel-Ace/Sequel-Ace/commit/0de78a1b5005f04653689062857e944ed3f78185))

### Removed
- Delete autoPullBack.yml ([195b245f8](https://github.com/Sequel-Ace/Sequel-Ace/commit/195b245f808cefe2e8bad91541c8c3b75881f303))

### Infra
- Bump addressable from 2.7.0 to 2.8.0 in /docs ([521bf3589](https://github.com/Sequel-Ace/Sequel-Ace/commit/521bf3589de12801ff22381d4966752e149359c1), [#1169](https://github.com/Sequel-Ace/Sequel-Ace/pull/1169))
- Bump addressable from 2.7.0 to 2.8.0 ([8684d3e61](https://github.com/Sequel-Ace/Sequel-Ace/commit/8684d3e61d05eaebf4ebafd442397cb0eeae7abc), [#1168](https://github.com/Sequel-Ace/Sequel-Ace/pull/1168))

## [3.3.3](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.3.3+%28*%29%22&expanded=true)

### Added
- Add support for Japanese language ([0bb5ed4ca](https://github.com/Sequel-Ace/Sequel-Ace/commit/0bb5ed4ca0c2edc5bd255893f613cad956d7a7e9))

### Fixed
- Fix query timer after reconnect ([3ecace043](https://github.com/Sequel-Ace/Sequel-Ace/commit/3ecace04377c75956db7e8a72c06644884a4de2b), [#1131](https://github.com/Sequel-Ace/Sequel-Ace/pull/1131))
- Fix text jump and crash in query editor ([36c79bb8d](https://github.com/Sequel-Ace/Sequel-Ace/commit/36c79bb8d244f7f662cf98eeb3303a548b7b267a), [#1106](https://github.com/Sequel-Ace/Sequel-Ace/pull/1106))

### Changed
- Prepare release ([9ef97525a](https://github.com/Sequel-Ace/Sequel-Ace/commit/9ef97525acf5a7e0f5fef76995a13e622c7f8d11), [#1139](https://github.com/Sequel-Ace/Sequel-Ace/pull/1139))
- Prepare Beta release ([ea22b01af](https://github.com/Sequel-Ace/Sequel-Ace/commit/ea22b01af3ec83ad8b9ef75a1bb7228239b78180), [#1137](https://github.com/Sequel-Ace/Sequel-Ace/pull/1137))
- Manually Granted Files should NOT be readonly ([88f33d957](https://github.com/Sequel-Ace/Sequel-Ace/commit/88f33d957a883b43b77cdaeca2d03446ae630332), [#1136](https://github.com/Sequel-Ace/Sequel-Ace/pull/1136))
- Prepare Beta release ([6e74be18e](https://github.com/Sequel-Ace/Sequel-Ace/commit/6e74be18e586df5c12c0786afd892378800ccf04), [#1130](https://github.com/Sequel-Ace/Sequel-Ace/pull/1130))
- Take 2 at UTF8mb3 Support ([879307e50](https://github.com/Sequel-Ace/Sequel-Ace/commit/879307e509d02c60c9b7b84dd2f429e126b7c0d7), [#1124](https://github.com/Sequel-Ace/Sequel-Ace/pull/1124))
- Options when Deleting All Rows from Table ([224936710](https://github.com/Sequel-Ace/Sequel-Ace/commit/2249367103f5dc0269ecffea261719628f019afa), [#1128](https://github.com/Sequel-Ace/Sequel-Ace/pull/1128))
- Merge pull request #1125 from Sequel-Ace/dont-stop-accessing-bookmarks-until-dealloc ([84b277648](https://github.com/Sequel-Ace/Sequel-Ace/commit/84b277648db4a578e70087951e902750c1e53a9e), [#1125](https://github.com/Sequel-Ace/Sequel-Ace/pull/1125))
- Merge pull request #1126 from Sequel-Ace/Fix-copy-create-table-syntax-always-disabled ([89f2f45b4](https://github.com/Sequel-Ace/Sequel-Ace/commit/89f2f45b49e21a031d9281d2500878b1f7ea485d), [#1126](https://github.com/Sequel-Ace/Sequel-Ace/pull/1126))
- Merge pull request #1127 from Sequel-Ace/Fix-edit-table-details-button-not-doing-anything ([45c3babe7](https://github.com/Sequel-Ace/Sequel-Ace/commit/45c3babe70a243cb20ab331b7348727376b11032), [#1127](https://github.com/Sequel-Ace/Sequel-Ace/pull/1127))
- Rebuild libcrypto ([f6311c094](https://github.com/Sequel-Ace/Sequel-Ace/commit/f6311c0947bd5e03e473b75b2f7c9d1d1b738052))
- Prepare Beta release ([f409df1e8](https://github.com/Sequel-Ace/Sequel-Ace/commit/f409df1e8bbf8eb4eabc5607160a001252504db2), [#1119](https://github.com/Sequel-Ace/Sequel-Ace/pull/1119))
- Update encodings mappings ([bbf6f99c5](https://github.com/Sequel-Ace/Sequel-Ace/commit/bbf6f99c5fbd53d786675ad35db32df0797e219d), [#1111](https://github.com/Sequel-Ace/Sequel-Ace/pull/1111))
- Update bundler and german localization, update japanese localization ([3a7aac3bb](https://github.com/Sequel-Ace/Sequel-Ace/commit/3a7aac3bb19659cbc4a08335687de1b4b5efd457))
- Merge pull request #1105 from dnicolson/fix-select-database-label ([22af83dcd](https://github.com/Sequel-Ace/Sequel-Ace/commit/22af83dcd86f669f1782f00925bd35416ffd2be4), [#1105](https://github.com/Sequel-Ace/Sequel-Ace/pull/1105))
- Merge pull request #1099 from dnicolson/allow-empty-favorite-password ([37ff34cf7](https://github.com/Sequel-Ace/Sequel-Ace/commit/37ff34cf763d733cb049c19a41b75842d8a92d35), [#1099](https://github.com/Sequel-Ace/Sequel-Ace/pull/1099))
- Merge pull request #1100 from dnicolson/fix-empty-tooltip ([dabb49e6b](https://github.com/Sequel-Ace/Sequel-Ace/commit/dabb49e6b3ecaa3d6e2909c3d560f41ef70d50b7), [#1100](https://github.com/Sequel-Ace/Sequel-Ace/pull/1100))
- Merge pull request #1098 from dnicolson/remove-newline-delimiters ([948e2fdb0](https://github.com/Sequel-Ace/Sequel-Ace/commit/948e2fdb02acca23d97b21bf899378039d9487f1), [#1098](https://github.com/Sequel-Ace/Sequel-Ace/pull/1098))

### Removed


### Infra
- Bump nokogiri from 1.11.2 to 1.11.5 in /docs ([8222f4df2](https://github.com/Sequel-Ace/Sequel-Ace/commit/8222f4df219e8762584f9d051068ec23e7a50217), [#1112](https://github.com/Sequel-Ace/Sequel-Ace/pull/1112))

## [3.3.2](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.3.2+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix missing connection name in tab title ([167ef7e77](https://github.com/Sequel-Ace/Sequel-Ace/commit/167ef7e7707d3a816018ccaf2eeac2ba2884095f))
- Fix grammar of "Check for Updates..." menu item ([878a9553d](https://github.com/Sequel-Ace/Sequel-Ace/commit/878a9553d9e603910a3582ded4681100385bf5d1), [#1063](https://github.com/Sequel-Ace/Sequel-Ace/pull/1063))
- Fix label color in tab ([b6e76bc1f](https://github.com/Sequel-Ace/Sequel-Ace/commit/b6e76bc1fe955dd0abe2e88e323a361938878bb2))
- Fix getting windows for bundles ([09845e14f](https://github.com/Sequel-Ace/Sequel-Ace/commit/09845e14fa3513ba6583d6f71311afdb0da6c4c6), [#1039](https://github.com/Sequel-Ace/Sequel-Ace/pull/1039))

### Changed
- Prepare release ([3d42bc9a5](https://github.com/Sequel-Ace/Sequel-Ace/commit/3d42bc9a5bd572c37255e95275f8a217a983ed37), [#1093](https://github.com/Sequel-Ace/Sequel-Ace/pull/1093))
- Prepare Beta release ([6f10c683a](https://github.com/Sequel-Ace/Sequel-Ace/commit/6f10c683ad7a36bec677f0e826235d13c0f7fc57), [#1089](https://github.com/Sequel-Ace/Sequel-Ace/pull/1089))
- New Nord theme ([f26d498b5](https://github.com/Sequel-Ace/Sequel-Ace/commit/f26d498b56065efe9c8f175382e04736d37e3ebf), [#1084](https://github.com/Sequel-Ace/Sequel-Ace/pull/1084))
- Merge pull request #1075 from mtgto/fix_1061 ([89484b495](https://github.com/Sequel-Ace/Sequel-Ace/commit/89484b495413fbb8e5c39aada48f9b07a30d326d), [#1075](https://github.com/Sequel-Ace/Sequel-Ace/pull/1075))
- Update strings ([fd8f07dae](https://github.com/Sequel-Ace/Sequel-Ace/commit/fd8f07dae2ae6e5083aaeb25e5d1a0019e9dde38))
- Update bundler ([4bd043467](https://github.com/Sequel-Ace/Sequel-Ace/commit/4bd043467e9e6ede4267b06268e9a6fb314d1250))
- Adds option to exclude GENERATED columns for SQL export #1041 ([60e4fd90b](https://github.com/Sequel-Ace/Sequel-Ace/commit/60e4fd90b32c38ffd91789d5ca21f94de45280f3), [#1060](https://github.com/Sequel-Ace/Sequel-Ace/pull/1060))
- Merge pull request #1073 from Sequel-Ace/dependabot/bundler/rexml-3.2.5 ([d75f85cb6](https://github.com/Sequel-Ace/Sequel-Ace/commit/d75f85cb6bf49fc451e4ffb8ef66953a69f1e2a5), [#1073](https://github.com/Sequel-Ace/Sequel-Ace/pull/1073))
- Merge pull request #1072 from Sequel-Ace/dependabot/bundler/docs/rexml-3.2.5 ([d8e9e0d00](https://github.com/Sequel-Ace/Sequel-Ace/commit/d8e9e0d00e4eeb8e70eb7b7b5a62aa65da3e05c3), [#1072](https://github.com/Sequel-Ace/Sequel-Ace/pull/1072))
- Merge pull request #1055 from gduh/fix-1000-disable-skip-show-database-warning ([207a05a48](https://github.com/Sequel-Ace/Sequel-Ace/commit/207a05a4871b178e993ef687342d0c33f57a9f4a), [#1055](https://github.com/Sequel-Ace/Sequel-Ace/pull/1055))

### Removed


### Infra


## [3.3.1](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.3.1+%28*%29%22&expanded=true)

### Added
- Enable main SequelAce menu actions ([bc90f72da](https://github.com/Sequel-Ace/Sequel-Ace/commit/bc90f72dad6b2097904fd719bd836010ee0100be))
- Enable Portugese (Portugal) and Portugese (Brazil) languages ([b1111ed80](https://github.com/Sequel-Ace/Sequel-Ace/commit/b1111ed80e94de7a1585d863ea2163afa7714043))
- Add CMD+F to Show Filter instead of Find ([b55a1a03f](https://github.com/Sequel-Ace/Sequel-Ace/commit/b55a1a03fd3da8bf1b75cfa3d873025d0106ebc3), [#1017](https://github.com/Sequel-Ace/Sequel-Ace/pull/1017))
- Add localized badge ([18173dc84](https://github.com/Sequel-Ace/Sequel-Ace/commit/18173dc84268296dd99106809413553bbf3d5a22))
- Enable German language ([759b1dd32](https://github.com/Sequel-Ace/Sequel-Ace/commit/759b1dd32a5c5306c042f0f7cb629238c25ee8f5))

### Fixed
- Fix tab title to show different string than window title ([a86bee7ac](https://github.com/Sequel-Ace/Sequel-Ace/commit/a86bee7ac619a667626800cfbd5c2bf1fc8f4844), [#1029](https://github.com/Sequel-Ace/Sequel-Ace/pull/1029))
- Fix possible crashes on tabAccessoryView ([e5520fced](https://github.com/Sequel-Ace/Sequel-Ace/commit/e5520fced1860e719f0d6ac23e825c870eb39e53))

### Changed
- Prepare release ([5448cd181](https://github.com/Sequel-Ace/Sequel-Ace/commit/5448cd1817fc887efc82f03c369ec7839bb00837), [#1034](https://github.com/Sequel-Ace/Sequel-Ace/pull/1034))
- Stop query button works as expected ([8eee143e6](https://github.com/Sequel-Ace/Sequel-Ace/commit/8eee143e69565b2992fd719b1dc114184ae4379f), [#1032](https://github.com/Sequel-Ace/Sequel-Ace/pull/1032))
- Prepare Beta release ([466039dbd](https://github.com/Sequel-Ace/Sequel-Ace/commit/466039dbdf198085ced60d80e26cebf45996d874), [#1023](https://github.com/Sequel-Ace/Sequel-Ace/pull/1023))
- Update Readme ([aabd63a54](https://github.com/Sequel-Ace/Sequel-Ace/commit/aabd63a548e145c8c66b67cbbdbc237a89347782))
- Open table in new tab works as expected ([40e1cb9b7](https://github.com/Sequel-Ace/Sequel-Ace/commit/40e1cb9b7ebb4e110500fc5334ba96726562e974), [#1022](https://github.com/Sequel-Ace/Sequel-Ace/pull/1022))
- Users icon is clickable and doesn't crash ([6c8b05d06](https://github.com/Sequel-Ace/Sequel-Ace/commit/6c8b05d06dbb4ca9a90c12f1cf5640ef60d3e807), [#1021](https://github.com/Sequel-Ace/Sequel-Ace/pull/1021))
- Update readme.md ([e4b5628e4](https://github.com/Sequel-Ace/Sequel-Ace/commit/e4b5628e4309a1629bde0b0e3ed385f4b87a135e))
- Improve tabs coloring ([95fa0270f](https://github.com/Sequel-Ace/Sequel-Ace/commit/95fa0270fabaa4e76456f6773816d9c94007ae9b), [#1015](https://github.com/Sequel-Ace/Sequel-Ace/pull/1015))
- Display binary data as hex color in dark mode ([5749f2bd8](https://github.com/Sequel-Ace/Sequel-Ace/commit/5749f2bd84bb8d88119c8b4c497076d0309ed20f), [#995](https://github.com/Sequel-Ace/Sequel-Ace/pull/995))
- Make badge smaller ([3d2a1437c](https://github.com/Sequel-Ace/Sequel-Ace/commit/3d2a1437c83bc7541321c52444a9937282f1dbb1))
- Update readme ([3bb5877b7](https://github.com/Sequel-Ace/Sequel-Ace/commit/3bb5877b7cb47a729e3bf2b1534da03521b08b08))
- Update readme ([9f254ab0d](https://github.com/Sequel-Ace/Sequel-Ace/commit/9f254ab0dd07dcd2f4c2eeb8df707b197a284492))

### Removed
- Remove favorites divider ([a8f67d0a2](https://github.com/Sequel-Ace/Sequel-Ace/commit/a8f67d0a240b825ab5226e5de00eb566fd40f294), [#996](https://github.com/Sequel-Ace/Sequel-Ace/pull/996))

### Infra


## [3.3.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.3.0+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Prepare release ([0a6e978d9](https://github.com/Sequel-Ace/Sequel-Ace/commit/0a6e978d990ba8062384fc1202a9d0b7f357a66c), [#994](https://github.com/Sequel-Ace/Sequel-Ace/pull/994))
- re-added Edit inline or popup ([8d56fa4f0](https://github.com/Sequel-Ace/Sequel-Ace/commit/8d56fa4f000763be48768fbaf921b78208ab8bff), [#993](https://github.com/Sequel-Ace/Sequel-Ace/pull/993))
- Improve memory handling on SQL export ([21e80ddb9](https://github.com/Sequel-Ace/Sequel-Ace/commit/21e80ddb94ce88b246164caf52371e5d02b42573), [#988](https://github.com/Sequel-Ace/Sequel-Ace/pull/988))
- Update readme ([68c118472](https://github.com/Sequel-Ace/Sequel-Ace/commit/68c1184725352c94286473e92646ee0509b15527))
- Update bundler ([a9fd90df9](https://github.com/Sequel-Ace/Sequel-Ace/commit/a9fd90df9d1b76514caba1d6db76ccff0e5ffa00))
- Force Kramdown to 2.3.1 [CVE-2021-28834] ([3c348839a](https://github.com/Sequel-Ace/Sequel-Ace/commit/3c348839a4596d1ff9c337308748ba0d07e3c29d))
- Format exporters ([98d3630c4](https://github.com/Sequel-Ace/Sequel-Ace/commit/98d3630c4182dd49250666bd1a7c2d892213a4f9))
- Update bundler ([bbfe48d0a](https://github.com/Sequel-Ace/Sequel-Ace/commit/bbfe48d0a76f0e82abad32226eea9ce7845cd7d2))
- Prepare Beta release ([aadf3f6b2](https://github.com/Sequel-Ace/Sequel-Ace/commit/aadf3f6b21f91142ffffa85b73283ea0868bd0ef), [#975](https://github.com/Sequel-Ace/Sequel-Ace/pull/975))
- Update AppCenter ([3de615974](https://github.com/Sequel-Ace/Sequel-Ace/commit/3de615974a1743e6a0b009a0f89952f090171117))
- Windows & Tabs refactoring: Remove Custom tabbing, implement native tabbed windows, rewrite app structure & hierarchy ([c5f1a35cb](https://github.com/Sequel-Ace/Sequel-Ace/commit/c5f1a35cb39bda92287fd6214bb6be366f3c95d9), [#970](https://github.com/Sequel-Ace/Sequel-Ace/pull/970))
- #changed/#fixed - Feature requests 955 ([672b44a48](https://github.com/Sequel-Ace/Sequel-Ace/commit/672b44a48b82631dd656b50dc945fdead074bf36), [#961](https://github.com/Sequel-Ace/Sequel-Ace/pull/961))
- foreign key creation when skip-show-database is on ([6018892c7](https://github.com/Sequel-Ace/Sequel-Ace/commit/6018892c7f0497d5d2dff6c8800eb00d3eb0105e), [#945](https://github.com/Sequel-Ace/Sequel-Ace/pull/945))
- Merge pull request #948 from Sequel-Ace/fix-some-crashes ([a704611ff](https://github.com/Sequel-Ace/Sequel-Ace/commit/a704611ff98b62fa5035e7e67b323191d41fdc32), [#948](https://github.com/Sequel-Ace/Sequel-Ace/pull/948))
- custom query result sorting ([588d1c424](https://github.com/Sequel-Ace/Sequel-Ace/commit/588d1c424a69dd265a17e663dc258d584f467902), [#947](https://github.com/Sequel-Ace/Sequel-Ace/pull/947))
- various small legibility issues across the documentation ([1dd4b0f07](https://github.com/Sequel-Ace/Sequel-Ace/commit/1dd4b0f076416a49f217360135e6e4b5a75ccad5), [#944](https://github.com/Sequel-Ace/Sequel-Ace/pull/944))
- re-added SPTaskAdditions.m ([4879793e2](https://github.com/Sequel-Ace/Sequel-Ace/commit/4879793e2415701a06c57754347e3f1f4e1b545d), [#942](https://github.com/Sequel-Ace/Sequel-Ace/pull/942))
- Auto pair characters changing font ([a792bd675](https://github.com/Sequel-Ace/Sequel-Ace/commit/a792bd67557707795cf856d06aabb08bced6fcdc), [#941](https://github.com/Sequel-Ace/Sequel-Ace/pull/941))
- exporting database with no selected table ([e7b089b20](https://github.com/Sequel-Ace/Sequel-Ace/commit/e7b089b2080ed062728062f0e8eed15abb3fb1ff), [#940](https://github.com/Sequel-Ace/Sequel-Ace/pull/940))
- Move NSWindowDelegate to Swift ([574bad740](https://github.com/Sequel-Ace/Sequel-Ace/commit/574bad740eeec79c8c6e3e186ebe0c45d4127e0d), [#936](https://github.com/Sequel-Ace/Sequel-Ace/pull/936))
- Ability to choose custom known_hosts file ([57f0bbfb6](https://github.com/Sequel-Ace/Sequel-Ace/commit/57f0bbfb6be37f5c23b201c729da896762af175a), [#906](https://github.com/Sequel-Ace/Sequel-Ace/pull/906))

### Removed
- Remove unused SPFlippedView ([25942e3a9](https://github.com/Sequel-Ace/Sequel-Ace/commit/25942e3a9354231422f0f34362e36dee79d23414), [#949](https://github.com/Sequel-Ace/Sequel-Ace/pull/949))
- Remove titleAccessoryView ([479f8a8ae](https://github.com/Sequel-Ace/Sequel-Ace/commit/479f8a8ae2f7bb203870604c29041e42048a5893), [#935](https://github.com/Sequel-Ace/Sequel-Ace/pull/935))

### Infra


## [3.2.3](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.2.3+%28*%29%22&expanded=true)

### Added
- Add Swift 5 command line tools ([56f138ccb](https://github.com/Sequel-Ace/Sequel-Ace/commit/56f138ccbb80e5af02bf523435d5245a9daf5b92))

### Fixed
- Fix windows being created instead of populated ([e6899d3b3](https://github.com/Sequel-Ace/Sequel-Ace/commit/e6899d3b3b25314c3f0c8d964a91c04cf1cb707b), [#933](https://github.com/Sequel-Ace/Sequel-Ace/pull/933))

### Changed
- Prepare release ([1ad55c928](https://github.com/Sequel-Ace/Sequel-Ace/commit/1ad55c9284772c9252d10c0d796267c1b99be52a), [#934](https://github.com/Sequel-Ace/Sequel-Ace/pull/934))
- Don't show no new release available alert on startup ([e4a68c3e2](https://github.com/Sequel-Ace/Sequel-Ace/commit/e4a68c3e2efc29d31efdf61585bd6029219c8ef8), [#930](https://github.com/Sequel-Ace/Sequel-Ace/pull/930))
- faster-stringForByteSize ([cf73d714b](https://github.com/Sequel-Ace/Sequel-Ace/commit/cf73d714b8901f76b350403a8322f1a06f46ff9c), [#927](https://github.com/Sequel-Ace/Sequel-Ace/pull/927))
- No Newer Release Available info alert ([eb3378d50](https://github.com/Sequel-Ace/Sequel-Ace/commit/eb3378d50d7285a7ebe91883694aec374eb9505a), [#928](https://github.com/Sequel-Ace/Sequel-Ace/pull/928))
- kill ssh child processes on crash ([caa4103be](https://github.com/Sequel-Ace/Sequel-Ace/commit/caa4103bee39b1ac0d11326d28945df9a5de31a0), [#920](https://github.com/Sequel-Ace/Sequel-Ace/pull/920))
- Edit cells inline or popup 'intelligent' switch ([baa653928](https://github.com/Sequel-Ace/Sequel-Ace/commit/baa6539285fcd195d8021dc3d16bd72b9cbed046), [#912](https://github.com/Sequel-Ace/Sequel-Ace/pull/912))
- Prepare Beta release ([1a432a035](https://github.com/Sequel-Ace/Sequel-Ace/commit/1a432a03566263190402cb6ec938aba98f5d9b55), [#925](https://github.com/Sequel-Ace/Sequel-Ace/pull/925))
- GitHub version checker fixes ([07e018044](https://github.com/Sequel-Ace/Sequel-Ace/commit/07e01804479d22e9f4445d4aede6fd875dfba17c), [#923](https://github.com/Sequel-Ace/Sequel-Ace/pull/923))
- Prepare Beta release ([85dbe4b31](https://github.com/Sequel-Ace/Sequel-Ace/commit/85dbe4b31d6eb6b58d9c0f9b5c10cac6356e4296), [#922](https://github.com/Sequel-Ace/Sequel-Ace/pull/922))
- saving individual query history ([b074152de](https://github.com/Sequel-Ace/Sequel-Ace/commit/b074152debf21861824017c944e938d411196ad7), [#916](https://github.com/Sequel-Ace/Sequel-Ace/pull/916))
- some analyzer warnings ([1a8377bfe](https://github.com/Sequel-Ace/Sequel-Ace/commit/1a8377bfebc4e0db474f6b98bdb4bf3d77fc36db), [#921](https://github.com/Sequel-Ace/Sequel-Ace/pull/921))
- hide the filter for the current session ([53f87c865](https://github.com/Sequel-Ace/Sequel-Ace/commit/53f87c865575c316cf823d3a731bdeb3ca6dcc86), [#909](https://github.com/Sequel-Ace/Sequel-Ace/pull/909))
- a couple of crashes ([f07244a85](https://github.com/Sequel-Ace/Sequel-Ace/commit/f07244a8510d8383d85a9ab20f206cb9784508e6), [#919](https://github.com/Sequel-Ace/Sequel-Ace/pull/919))
- allow insertion of NULL into varchar fields of length < 4 ([0b0ae9cf9](https://github.com/Sequel-Ace/Sequel-Ace/commit/0b0ae9cf915d7d3e0065752607d664d7eb4449b6), [#911](https://github.com/Sequel-Ace/Sequel-Ace/pull/911))
- latest crashes ([bff9f3262](https://github.com/Sequel-Ace/Sequel-Ace/commit/bff9f3262d96130a31d67502e1f3331f01810ee4), [#901](https://github.com/Sequel-Ace/Sequel-Ace/pull/901))
- Merge pull request #903 from Sequel-Ace/Delete-and-Truncate-ellipsis ([f9c987fe1](https://github.com/Sequel-Ace/Sequel-Ace/commit/f9c987fe119241cb5ea5aaa377e746cb6220f694), [#903](https://github.com/Sequel-Ace/Sequel-Ace/pull/903))
- Sqlite error logging ([b967b556f](https://github.com/Sequel-Ace/Sequel-Ace/commit/b967b556ff9c921946f1ba1c4f156fc9246855d9), [#898](https://github.com/Sequel-Ace/Sequel-Ace/pull/898))
- edit in popup ([62491cb9b](https://github.com/Sequel-Ace/Sequel-Ace/commit/62491cb9b93b4cb573d0d15df67b163185ca414f), [#899](https://github.com/Sequel-Ace/Sequel-Ace/pull/899))
- Export directory bookmarks ([22de4acc2](https://github.com/Sequel-Ace/Sequel-Ace/commit/22de4acc27ac86e0495d57a7d114c49043c68c14), [#897](https://github.com/Sequel-Ace/Sequel-Ace/pull/897))
- some crashes ([8163a4250](https://github.com/Sequel-Ace/Sequel-Ace/commit/8163a4250dcf389a320ff081ccab74628639a088), [#889](https://github.com/Sequel-Ace/Sequel-Ace/pull/889))
- GitHub release checker ([3b188a8fe](https://github.com/Sequel-Ace/Sequel-Ace/commit/3b188a8fe32d54ba3f982efec2019482f20b3ce6), [#879](https://github.com/Sequel-Ace/Sequel-Ace/pull/879))

### Removed


### Infra


## [3.2.2](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.2.2+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Prepare release ([2d3c93d91](https://github.com/Sequel-Ace/Sequel-Ace/commit/2d3c93d9103995925a027debaccaa1649fdb3083), [#895](https://github.com/Sequel-Ace/Sequel-Ace/pull/895))
- Increment app patch version ([c3bf8a9b3](https://github.com/Sequel-Ace/Sequel-Ace/commit/c3bf8a9b3eee544e671713f09679f2cd450ea382))
- maintain table filter state ([3cb1d8aa4](https://github.com/Sequel-Ace/Sequel-Ace/commit/3cb1d8aa4848aee8e09ccc65ba6aa071fd34db16), [#890](https://github.com/Sequel-Ace/Sequel-Ace/pull/890))
- Tooltip crash attempt two ([104cc39f4](https://github.com/Sequel-Ace/Sequel-Ace/commit/104cc39f471a1756b2f5c42dca56f415e2831fb5), [#886](https://github.com/Sequel-Ace/Sequel-Ace/pull/886))
- show error if setting the time zone fails ([578906262](https://github.com/Sequel-Ace/Sequel-Ace/commit/578906262522c8d7bf58ee7b2564b3daf645e372), [#884](https://github.com/Sequel-Ace/Sequel-Ace/pull/884))

### Removed
- Remove hard-coded minimum for resetting auto-increment ([550a566e4](https://github.com/Sequel-Ace/Sequel-Ace/commit/550a566e4d76411afd92a4afa61c74e28a2f5ffc), [#885](https://github.com/Sequel-Ace/Sequel-Ace/pull/885))

### Infra
- Build Version is now selectable ([839bdfc85](https://github.com/Sequel-Ace/Sequel-Ace/commit/839bdfc85896bd091caaba7fb191260bb73c24da), [#883](https://github.com/Sequel-Ace/Sequel-Ace/pull/883))

## [3.2.1](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.2.1+%28*%29%22&expanded=true)

### Added


### Fixed


### Changed
- Prepare release ([7b42f7532](https://github.com/Sequel-Ace/Sequel-Ace/commit/7b42f7532900448314af3f67f15e9b9c60e4e9b4), [#880](https://github.com/Sequel-Ace/Sequel-Ace/pull/880))
- Increment app patch version ([6a19809c9](https://github.com/Sequel-Ace/Sequel-Ace/commit/6a19809c9339be570618da376f7ce5f582659c96))
- some crashes ([cb22f0053](https://github.com/Sequel-Ace/Sequel-Ace/commit/cb22f00531f53dca13d8b823a597ff9e75636555), [#878](https://github.com/Sequel-Ace/Sequel-Ace/pull/878))
- Tooltip crash ([2db66191f](https://github.com/Sequel-Ace/Sequel-Ace/commit/2db66191f926496bf9247db9694af0d00a073922), [#877](https://github.com/Sequel-Ace/Sequel-Ace/pull/877))
- Export directory bookmarks ([73d2bfa9d](https://github.com/Sequel-Ace/Sequel-Ace/commit/73d2bfa9d6a137103d81c70904d7a9fdf78313f5), [#871](https://github.com/Sequel-Ace/Sequel-Ace/pull/871))

### Removed


### Infra


## [3.2.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.2.0+%28*%29%22&expanded=true)

### Added
- Added the \ so that when copying it directly it works. ([5a0230317](https://github.com/Sequel-Ace/Sequel-Ace/commit/5a02303176bb8385c486e637ab58ac37c0206317), [#860](https://github.com/Sequel-Ace/Sequel-Ace/pull/860))
- Added more logging and removed a few non-fatal error reports ([fac631db4](https://github.com/Sequel-Ace/Sequel-Ace/commit/fac631db43e45aed0ba134b019c809a0d2d996d8), [#815](https://github.com/Sequel-Ace/Sequel-Ace/pull/815))

### Fixed
- Fix CSV Import Index out of bound in array crash ([351b9daa6](https://github.com/Sequel-Ace/Sequel-Ace/commit/351b9daa62aad8b04e2e67ecda019369a22e11d2), [#824](https://github.com/Sequel-Ace/Sequel-Ace/pull/824))
- Fix CR ([93d2720b4](https://github.com/Sequel-Ace/Sequel-Ace/commit/93d2720b465e94a3805d77dc66379e654599d511))
- Fix 742 multiple update from grid ([e3f10075b](https://github.com/Sequel-Ace/Sequel-Ace/commit/e3f10075ba1132192b60a0eff103fd2dbc22d065), [#812](https://github.com/Sequel-Ace/Sequel-Ace/pull/812))

### Changed
- Prepare release ([4c44f9b35](https://github.com/Sequel-Ace/Sequel-Ace/commit/4c44f9b356b0b3bb2d828f8d7274c10fa8113c65), [#869](https://github.com/Sequel-Ace/Sequel-Ace/pull/869))
- import/export when table has a trigger ([9f32eeff8](https://github.com/Sequel-Ace/Sequel-Ace/commit/9f32eeff8bd75ec060f32beeb67a68cfdac2cf38), [#866](https://github.com/Sequel-Ace/Sequel-Ace/pull/866))
- information schema crash 883 ([2e642c83e](https://github.com/Sequel-Ace/Sequel-Ace/commit/2e642c83e6d333d35e009bdd8e4353344e049c03), [#848](https://github.com/Sequel-Ace/Sequel-Ace/pull/848))
- UTC time tooltips ([cccc87556](https://github.com/Sequel-Ace/Sequel-Ace/commit/cccc8755671b1d6ea177d4621094e833e36ef0c9), [#862](https://github.com/Sequel-Ace/Sequel-Ace/pull/862))
- Prepare Beta release ([70f700744](https://github.com/Sequel-Ace/Sequel-Ace/commit/70f7007445cd23ea9127e6247411072eeab8c63b), [#859](https://github.com/Sequel-Ace/Sequel-Ace/pull/859))
- indenting issue on query editor ([dab36f4f6](https://github.com/Sequel-Ace/Sequel-Ace/commit/dab36f4f61125bd0b987e970be287cb7670271b8), [#855](https://github.com/Sequel-Ace/Sequel-Ace/pull/855))
- text wrapping on query screen ([fc7ced754](https://github.com/Sequel-Ace/Sequel-Ace/commit/fc7ced7546f27bcfb75beef95aa3de6ead77bf87), [#854](https://github.com/Sequel-Ace/Sequel-Ace/pull/854))
- a few crashes ([e8b516b19](https://github.com/Sequel-Ace/Sequel-Ace/commit/e8b516b19feaa85ba37e41e27c37a1b1e595d274), [#852](https://github.com/Sequel-Ace/Sequel-Ace/pull/852))
- Duplicate Table... name not editable ([4a7116787](https://github.com/Sequel-Ace/Sequel-Ace/commit/4a7116787af58b8569e9f1aa895b8ca5714ca5a7), [#846](https://github.com/Sequel-Ace/Sequel-Ace/pull/846))
- some crashes ([2e468c1b1](https://github.com/Sequel-Ace/Sequel-Ace/commit/2e468c1b1129b63f0d6b55eeebeb3569b71a45ae), [#844](https://github.com/Sequel-Ace/Sequel-Ace/pull/844))
- rename table so that it drops the original table ([e30d9f53f](https://github.com/Sequel-Ace/Sequel-Ace/commit/e30d9f53f39eb936a72073840e7000361336c672), [#842](https://github.com/Sequel-Ace/Sequel-Ace/pull/842))
- Users screen schemas not updating ([0aa257c07](https://github.com/Sequel-Ace/Sequel-Ace/commit/0aa257c0793a8e3db6896c72b9f8d6873d24dbd4), [#840](https://github.com/Sequel-Ace/Sequel-Ace/pull/840))
- Merge pull request #838 from Sequel-Ace/auto-inc-issue-747 ([cacbbca43](https://github.com/Sequel-Ace/Sequel-Ace/commit/cacbbca43c6537e30d68fe1378a0eb3c7d7e32a0), [#838](https://github.com/Sequel-Ace/Sequel-Ace/pull/838))
- Set some App Center configs and events ([69e2d39d9](https://github.com/Sequel-Ace/Sequel-Ace/commit/69e2d39d907e695cd12575351fd9e673ce5ca43f), [#830](https://github.com/Sequel-Ace/Sequel-Ace/pull/830))
- more fb crashes ([a67ef9edf](https://github.com/Sequel-Ace/Sequel-Ace/commit/a67ef9edfa0b3d42eb0a79f665b155a7c62b1b30), [#828](https://github.com/Sequel-Ace/Sequel-Ace/pull/828))
- Rename SPWindowController's properties, start AutoLayout programatically without xibs ([c827cfd4e](https://github.com/Sequel-Ace/Sequel-Ace/commit/c827cfd4e80edfddce1836df488e4adbe7a8cce3), [#826](https://github.com/Sequel-Ace/Sequel-Ace/pull/826))
- Appcenter upload_symbols script ([05fa4958e](https://github.com/Sequel-Ace/Sequel-Ace/commit/05fa4958e9dbf9606dcf54d89d4fde5b04381816), [#827](https://github.com/Sequel-Ace/Sequel-Ace/pull/827))
- Merge pull request #825 from Sequel-Ace/query-history-prefs ([37b08f858](https://github.com/Sequel-Ace/Sequel-Ace/commit/37b08f8584bf7231fa94cf886d9c453471ee42ed), [#825](https://github.com/Sequel-Ace/Sequel-Ace/pull/825))
- Code style ([2b386d2ab](https://github.com/Sequel-Ace/Sequel-Ace/commit/2b386d2ab990212f554351bb04256dde82d4e7e1))
- Prepare Beta release ([4f6d1a112](https://github.com/Sequel-Ace/Sequel-Ace/commit/4f6d1a1122a3538ea11265ba8fd9926109abbf20), [#823](https://github.com/Sequel-Ace/Sequel-Ace/pull/823))
- Get rid of Firebase Crashlytics, move to MSAppCenter Crashlytics & Analytics ([351643ce3](https://github.com/Sequel-Ace/Sequel-Ace/commit/351643ce34cda8f1135f3653612daf9fcb84a4bb), [#822](https://github.com/Sequel-Ace/Sequel-Ace/pull/822))
- Windows hierarchy cleanup and typesafety, part 1 ([e6ffd1063](https://github.com/Sequel-Ace/Sequel-Ace/commit/e6ffd106394480d59b8d6453e285fed7633c5e8f), [#821](https://github.com/Sequel-Ace/Sequel-Ace/pull/821))
- Allow creating foreign keys referencing other databases ([85d0d6b55](https://github.com/Sequel-Ace/Sequel-Ace/commit/85d0d6b559f9ebf4c7b275a74829378e9b2ada10), [#808](https://github.com/Sequel-Ace/Sequel-Ace/pull/808))
- Bookmarks not being generated correctly ([308368261](https://github.com/Sequel-Ace/Sequel-Ace/commit/308368261d87b96b3a41449696b4dfed1b56b404), [#819](https://github.com/Sequel-Ace/Sequel-Ace/pull/819))
- indentation for database document and app controller ([8c959989f](https://github.com/Sequel-Ace/Sequel-Ace/commit/8c959989feca30716dde706f06e49aaa91b34db8))
- Update Firebase ([cd3a04b60](https://github.com/Sequel-Ace/Sequel-Ace/commit/cd3a04b60dd17d2a6031c91ff8deaa09a0749594))
- Merge pull request #816 from Sequel-Ace/fix-some-crashes ([1f7fed2eb](https://github.com/Sequel-Ace/Sequel-Ace/commit/1f7fed2eb18c6634935bd4de7f5e7da25e31a8be), [#816](https://github.com/Sequel-Ace/Sequel-Ace/pull/816))

### Removed
- remove space char used to trigger syntax highlighting on paste ([8a2dbe4d5](https://github.com/Sequel-Ace/Sequel-Ace/commit/8a2dbe4d5a9483398ef7c9338f370997c3dd8a1d), [#835](https://github.com/Sequel-Ace/Sequel-Ace/pull/835))

### Infra


## [3.1.1](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.1.1+%28*%29%22&expanded=true)

### Added
- Add Chinese localizations ([ebe453a7e](https://github.com/Sequel-Ace/Sequel-Ace/commit/ebe453a7e350343e775b7786b3471b6a34b28924), [#781](https://github.com/Sequel-Ace/Sequel-Ace/pull/781))
- Add support for generic Spanish language next to Spanish (Spain) language ([edd5e4eb2](https://github.com/Sequel-Ace/Sequel-Ace/commit/edd5e4eb2f357256211100db75ba5b8ca2e8000f), [#771](https://github.com/Sequel-Ace/Sequel-Ace/pull/771))

### Fixed
- Fix Broken run current query button ([b7578c22e](https://github.com/Sequel-Ace/Sequel-Ace/commit/b7578c22e3d5524500f6c54b8b44def706613631), [#809](https://github.com/Sequel-Ace/Sequel-Ace/pull/809))
- Fix reconnect timeout - accept SSH password after network connection reset ([cb7f90224](https://github.com/Sequel-Ace/Sequel-Ace/commit/cb7f90224fb5ec764e0f2e73207fef61b3659086), [#772](https://github.com/Sequel-Ace/Sequel-Ace/pull/772))

### Changed
- Prepare release ([2a9c86176](https://github.com/Sequel-Ace/Sequel-Ace/commit/2a9c86176f38fdf6670f1f52253bd5c6e00b5eb5), [#810](https://github.com/Sequel-Ace/Sequel-Ace/pull/810))
- os_log wrapper for swift ([056e7e9e4](https://github.com/Sequel-Ace/Sequel-Ace/commit/056e7e9e47e9d0932bea389230efefbe6982990d), [#807](https://github.com/Sequel-Ace/Sequel-Ace/pull/807))
- Merge pull request #806 from Sequel-Ace/Fix-stop-query-broken-in-beta ([458e00f72](https://github.com/Sequel-Ace/Sequel-Ace/commit/458e00f720ca905164d856f815fcff18965796b4), [#806](https://github.com/Sequel-Ace/Sequel-Ace/pull/806))
- Prepare Beta release ([376bad3ad](https://github.com/Sequel-Ace/Sequel-Ace/commit/376bad3adb3beb4486482f00aa104387754d8d78), [#800](https://github.com/Sequel-Ace/Sequel-Ace/pull/800))
- syntax highlighting not being properly applied after pasting ([74fd2acb7](https://github.com/Sequel-Ace/Sequel-Ace/commit/74fd2acb7b9d59aa1a931da70df5ae343cc88443), [#798](https://github.com/Sequel-Ace/Sequel-Ace/pull/798))
- Update Chinese translations ([15594240d](https://github.com/Sequel-Ace/Sequel-Ace/commit/15594240d6154259b3a1751e74cf9a807761e832))
- apply custom font to all inserted snippets ([3350b13dc](https://github.com/Sequel-Ace/Sequel-Ace/commit/3350b13dc1e799a13efd233a53fb4037d456a7a7), [#797](https://github.com/Sequel-Ace/Sequel-Ace/pull/797))
- highlight errors in red in the query status field ([5df7a388e](https://github.com/Sequel-Ace/Sequel-Ace/commit/5df7a388e322408e3eb3c368954073212b342424), [#796](https://github.com/Sequel-Ace/Sequel-Ace/pull/796))
- Prepare Beta release ([a4c46a539](https://github.com/Sequel-Ace/Sequel-Ace/commit/a4c46a5396fb5034856292274c1a588da7b38e5a), [#794](https://github.com/Sequel-Ace/Sequel-Ace/pull/794))
- Some crashes ([f220ccb3b](https://github.com/Sequel-Ace/Sequel-Ace/commit/f220ccb3b1fdd3d87bf7e077f657eb231d6fc591), [#789](https://github.com/Sequel-Ace/Sequel-Ace/pull/789))
- Query history duplicates and order ([a53198a7a](https://github.com/Sequel-Ace/Sequel-Ace/commit/a53198a7af6b0b604b9a06ee54091b5e6d5679b3), [#788](https://github.com/Sequel-Ace/Sequel-Ace/pull/788))
- Table history buttons not working ([100cd2dbf](https://github.com/Sequel-Ace/Sequel-Ace/commit/100cd2dbfe1c63611e72a6120ca08afda4f4a916), [#783](https://github.com/Sequel-Ace/Sequel-Ace/pull/783))
- Get rid of CocoaPods, switch FMDB to SPM, enable Swift standard libraries ([8f91391cb](https://github.com/Sequel-Ace/Sequel-Ace/commit/8f91391cb3f8440c6cdcd4c18ba8537186a85aeb), [#779](https://github.com/Sequel-Ace/Sequel-Ace/pull/779))
- Consistently use encoding utf8mb4 ([656cc9481](https://github.com/Sequel-Ace/Sequel-Ace/commit/656cc94818853129e1fc27504db85beb89542764), [#769](https://github.com/Sequel-Ace/Sequel-Ace/pull/769))
- some more crashes ([056bb81ac](https://github.com/Sequel-Ace/Sequel-Ace/commit/056bb81ac953064e098eaaa048378f3245f22b66), [#766](https://github.com/Sequel-Ace/Sequel-Ace/pull/766))
- Attempt to Allow Connections via Localhost ([16ac37c5e](https://github.com/Sequel-Ace/Sequel-Ace/commit/16ac37c5e727c46e21b8fb6195ba81aa20476253), [#765](https://github.com/Sequel-Ace/Sequel-Ace/pull/765))
- Update Changelog generator, update dependencies ([e1e0b9829](https://github.com/Sequel-Ace/Sequel-Ace/commit/e1e0b98292160fe267b92a3ff98ed36cdf61e088), [#763](https://github.com/Sequel-Ace/Sequel-Ace/pull/763))

### Removed


### Infra


## [3.1.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.1.0+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix cutoff file names in Preferences ([d6e987d9f](https://github.com/Sequel-Ace/Sequel-Ace/commit/d6e987d9f63aa9d64c1abce8cb8a046ac680de62), [#738](https://github.com/Sequel-Ace/Sequel-Ace/pull/738))
- Fix quick connect not clearing fields ([4030d3fb1](https://github.com/Sequel-Ace/Sequel-Ace/commit/4030d3fb14ccea000570adb6a94ee2c9ffe514f1), [#711](https://github.com/Sequel-Ace/Sequel-Ace/pull/711))
- Fix crashlytics script ([f13bbca11](https://github.com/Sequel-Ace/Sequel-Ace/commit/f13bbca1187b57de0415a76c35aa8497c9ece5a5))

### Changed
- Prepare release ([5f2e52cc2](https://github.com/Sequel-Ace/Sequel-Ace/commit/5f2e52cc2c11d62631eeee9238f9487e0e7e1502), [#762](https://github.com/Sequel-Ace/Sequel-Ace/pull/762))
- table information eye symbol crash ([9bd486ab7](https://github.com/Sequel-Ace/Sequel-Ace/commit/9bd486ab7013d4d147e5f6dd37855294d74a26de), [#760](https://github.com/Sequel-Ace/Sequel-Ace/pull/760))
- exporting multiple tables ([5ae47f9d5](https://github.com/Sequel-Ace/Sequel-Ace/commit/5ae47f9d5ec1d2eb658ee4eeba21fc56da72b1de), [#759](https://github.com/Sequel-Ace/Sequel-Ace/pull/759))
- changing custom query font and respect font when inserting favourite ([1bcfe5f43](https://github.com/Sequel-Ace/Sequel-Ace/commit/1bcfe5f43c8a336c799d38cc8725ffa8f5136f43), [#757](https://github.com/Sequel-Ace/Sequel-Ace/pull/757))
- some crashes ([d21af6100](https://github.com/Sequel-Ace/Sequel-Ace/commit/d21af6100baab56082f4996fdacb4c37d65a4c28), [#754](https://github.com/Sequel-Ace/Sequel-Ace/pull/754))
- better handle stale bookmarks ([da1c1c8c9](https://github.com/Sequel-Ace/Sequel-Ace/commit/da1c1c8c9761b9a2bf46fb9193bdeb9594dc0447), [#739](https://github.com/Sequel-Ace/Sequel-Ace/pull/739))
- Improved clarity of bug report issue template ([ae7d0dd76](https://github.com/Sequel-Ace/Sequel-Ace/commit/ae7d0dd7698da6e3f76bca6f4396793f3044d98d), [#748](https://github.com/Sequel-Ace/Sequel-Ace/pull/748))
- More doc tweaks ([e254ba0ef](https://github.com/Sequel-Ace/Sequel-Ace/commit/e254ba0ef0f7d16e407cb23ea58556db79e9b9b4), [#752](https://github.com/Sequel-Ace/Sequel-Ace/pull/752))
- Prepare Beta release ([5b8a86d63](https://github.com/Sequel-Ace/Sequel-Ace/commit/5b8a86d6321f58640bf009d871b3d9fea3cc6921), [#746](https://github.com/Sequel-Ace/Sequel-Ace/pull/746))
- Connection logging ([4044855cc](https://github.com/Sequel-Ace/Sequel-Ace/commit/4044855cc7932684d714e6aa9507dabb10bff5c4), [#737](https://github.com/Sequel-Ace/Sequel-Ace/pull/737))
- App Sandbox and Secure Bookmarks docs ([dea19267f](https://github.com/Sequel-Ace/Sequel-Ace/commit/dea19267f055f6df097b8aa04f7146d9dbc269eb), [#743](https://github.com/Sequel-Ace/Sequel-Ace/pull/743))
- some crashes ([c08f883b1](https://github.com/Sequel-Ace/Sequel-Ace/commit/c08f883b127e3c7b6213db40bfc86fc4d6f7f43e), [#733](https://github.com/Sequel-Ace/Sequel-Ace/pull/733))
- Two custom queries with syntax errors = crash ([0738da947](https://github.com/Sequel-Ace/Sequel-Ace/commit/0738da947335c256f1eb46c3b1bee6287af1d86a), [#736](https://github.com/Sequel-Ace/Sequel-Ace/pull/736))
- Better export error handling ([5474b93f2](https://github.com/Sequel-Ace/Sequel-Ace/commit/5474b93f297a5d66516e784a2d9da476138165d9), [#731](https://github.com/Sequel-Ace/Sequel-Ace/pull/731))
- display json string properly in edit popup ([02b682748](https://github.com/Sequel-Ace/Sequel-Ace/commit/02b682748e9fda954c4d799d52b9cd1fa312dead), [#730](https://github.com/Sequel-Ace/Sequel-Ace/pull/730))
- SSHTunnel crash ([e424db420](https://github.com/Sequel-Ace/Sequel-Ace/commit/e424db420b20ffda648e3f39c99cb70561c7568c), [#728](https://github.com/Sequel-Ace/Sequel-Ace/pull/728))
- more crashes ([8cca75003](https://github.com/Sequel-Ace/Sequel-Ace/commit/8cca750039f03c1f4a52e2d52056c5f4dcc3f5ca), [#724](https://github.com/Sequel-Ace/Sequel-Ace/pull/724))
- fave colour support optimisation ([051134abc](https://github.com/Sequel-Ace/Sequel-Ace/commit/051134abc47cd36a3001d89fb04195a95d22cbb4), [#725](https://github.com/Sequel-Ace/Sequel-Ace/pull/725))
- Prepare Beta release ([eaf07c6aa](https://github.com/Sequel-Ace/Sequel-Ace/commit/eaf07c6aa3159594e07e257f9b69c4e22729adb1), [#722](https://github.com/Sequel-Ace/Sequel-Ace/pull/722))
- Improve query editor performance - Revert double click functionality by overriding NSTextStorage ([9430b9767](https://github.com/Sequel-Ace/Sequel-Ace/commit/9430b9767239bcc39512986e5d4b6da24f4b2812), [#715](https://github.com/Sequel-Ace/Sequel-Ace/pull/715))
- a few new crashes ([dddf027d6](https://github.com/Sequel-Ace/Sequel-Ace/commit/dddf027d612a62483b86349449b1d76f080b3b34), [#714](https://github.com/Sequel-Ace/Sequel-Ace/pull/714))
- Bookmarks improvements ([2664a177f](https://github.com/Sequel-Ace/Sequel-Ace/commit/2664a177f64a6ed16cbaa15ad09989ad4eb3b7bb), [#659](https://github.com/Sequel-Ace/Sequel-Ace/pull/659))
- Copy tables between databases ([01fa877d0](https://github.com/Sequel-Ace/Sequel-Ace/commit/01fa877d01ba6b75dc5359567cf97c82bca4aad4), [#620](https://github.com/Sequel-Ace/Sequel-Ace/pull/620))
- Always show tab bar as native macOS apps, cleanup tab bar code ([460e706b1](https://github.com/Sequel-Ace/Sequel-Ace/commit/460e706b18d3f23bd8708cff90444dbd6fab4422), [#710](https://github.com/Sequel-Ace/Sequel-Ace/pull/710))

### Removed


### Infra
- Doc tweaks ([4e8931d34](https://github.com/Sequel-Ace/Sequel-Ace/commit/4e8931d342f7f5cdc9d91c052e893fc7a23a34f4), [#751](https://github.com/Sequel-Ace/Sequel-Ace/pull/751))

## [3.0.2](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.0.2+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix Query Window Forgets Active Query ([f03f61461](https://github.com/Sequel-Ace/Sequel-Ace/commit/f03f61461856e0ef7a1797c4b6aaa03bfcb9ba3e), [#696](https://github.com/Sequel-Ace/Sequel-Ace/pull/696))
- Fixed commenting out one or multiple lines in query editor ([b33ac44f9](https://github.com/Sequel-Ace/Sequel-Ace/commit/b33ac44f983deb35a291c40785c76fb8a0d43584), [#691](https://github.com/Sequel-Ace/Sequel-Ace/pull/691))

### Changed
- Prepare release ([d08a7f45e](https://github.com/Sequel-Ace/Sequel-Ace/commit/d08a7f45e8136301614a048d99db1c7a4686f892), [#706](https://github.com/Sequel-Ace/Sequel-Ace/pull/706))
- Improvements to Console ([cd85311aa](https://github.com/Sequel-Ace/Sequel-Ace/commit/cd85311aabc1a13917c23b8a969a1fb184113edb), [#703](https://github.com/Sequel-Ace/Sequel-Ace/pull/703))
- spfieldmappercontroller match header names crash ([c199dd0d2](https://github.com/Sequel-Ace/Sequel-Ace/commit/c199dd0d2384668c7b4512e65157819c473412e2), [#704](https://github.com/Sequel-Ace/Sequel-Ace/pull/704))
- Fastlane improvements ([87699fcfc](https://github.com/Sequel-Ace/Sequel-Ace/commit/87699fcfcfb44cd95f6b9c622eb9761dfc284a49), [#701](https://github.com/Sequel-Ace/Sequel-Ace/pull/701))
- Prepare Beta release ([081ca3410](https://github.com/Sequel-Ace/Sequel-Ace/commit/081ca3410d030a659c56750d8d58f20e7d948d0e), [#700](https://github.com/Sequel-Ace/Sequel-Ace/pull/700))
- Update Fastfile ([dacd4a8e4](https://github.com/Sequel-Ace/Sequel-Ace/commit/dacd4a8e492d2ce7747e150779d5d89eadc79322))
- SPExtendedTableInfo loadTable crash ([b0b0da30f](https://github.com/Sequel-Ace/Sequel-Ace/commit/b0b0da30f66f344ec296ce884bbf1aea6a7f6ad1), [#699](https://github.com/Sequel-Ace/Sequel-Ace/pull/699))
- SPTableCopy _createTableStatementFor:inDatabase crash ([b7b93ad35](https://github.com/Sequel-Ace/Sequel-Ace/commit/b7b93ad3545cef16286b8ce90cf340d9255031fc), [#698](https://github.com/Sequel-Ace/Sequel-Ace/pull/698))
- Homebrew installation command ([f2899dd6a](https://github.com/Sequel-Ace/Sequel-Ace/commit/f2899dd6a48e12e18a0c3e6fbdec3707d5cfa3d3), [#697](https://github.com/Sequel-Ace/Sequel-Ace/pull/697))
- SPTableInfo crash ([4540f8e82](https://github.com/Sequel-Ace/Sequel-Ace/commit/4540f8e82e25514c67a7c5cc861a5bb89234cf54), [#695](https://github.com/Sequel-Ace/Sequel-Ace/pull/695))
- double error alerts on connection failure ([7eba8716c](https://github.com/Sequel-Ace/Sequel-Ace/commit/7eba8716caab981079b16a2b1386b63a236d3ef1), [#693](https://github.com/Sequel-Ace/Sequel-Ace/pull/693))
- sp table structure load table crash ([c7cc1506e](https://github.com/Sequel-Ace/Sequel-Ace/commit/c7cc1506e93f211d50b031c0419082dc7bf3a2a7), [#692](https://github.com/Sequel-Ace/Sequel-Ace/pull/692))
- tableChanged NSNull Collation crash ([07b2d4854](https://github.com/Sequel-Ace/Sequel-Ace/commit/07b2d4854a92e19e91aef03642a3bb9374e3410a), [#688](https://github.com/Sequel-Ace/Sequel-Ace/pull/688))
- tableViewColumnDidResize crash ([013c0f944](https://github.com/Sequel-Ace/Sequel-Ace/commit/013c0f9449fd2e32b5ee650ff2bc9e8ecad068fc), [#690](https://github.com/Sequel-Ace/Sequel-Ace/pull/690))
- Update UI for light and dark mode on Tabs ([38a712e75](https://github.com/Sequel-Ace/Sequel-Ace/commit/38a712e75b0ad3939b7d06bca843a2d9502b66ff), [#682](https://github.com/Sequel-Ace/Sequel-Ace/pull/682))
- deriveQueryString crash ([5d70e94d5](https://github.com/Sequel-Ace/Sequel-Ace/commit/5d70e94d59f20d021bf220f841598156ffea1740), [#686](https://github.com/Sequel-Ace/Sequel-Ace/pull/686))
- Change all NSArrayObjectAtIndex to safeObjectAtIndex ([22926dce1](https://github.com/Sequel-Ace/Sequel-Ace/commit/22926dce118699ac57cb17730a02ae175ec74e2a), [#684](https://github.com/Sequel-Ace/Sequel-Ace/pull/684))
- databasestructure crash ([03fefe995](https://github.com/Sequel-Ace/Sequel-Ace/commit/03fefe9958597196eaa34ef54b2219351fdaa16e), [#680](https://github.com/Sequel-Ace/Sequel-Ace/pull/680))
- logging in RegexKit's Exception and Error generation code ([21fbea781](https://github.com/Sequel-Ace/Sequel-Ace/commit/21fbea781d650cb12f2ba5e8936bc41c8d8c785c), [#681](https://github.com/Sequel-Ace/Sequel-Ace/pull/681))
- Keychain improvements and safety checks ([4c3f1a82b](https://github.com/Sequel-Ace/Sequel-Ace/commit/4c3f1a82b2445dba59aa94a894884bc796d43eec), [#678](https://github.com/Sequel-Ace/Sequel-Ace/pull/678))
- Query editor improvements ([ab1e3ea7a](https://github.com/Sequel-Ace/Sequel-Ace/commit/ab1e3ea7a103ca337780ac4a97461ccdb044dc8f), [#676](https://github.com/Sequel-Ace/Sequel-Ace/pull/676))
- Use entered password for favorite if it changed ([2bf774dbe](https://github.com/Sequel-Ace/Sequel-Ace/commit/2bf774dbe9038b20d7e41cb0fe0f21c355c4d49a), [#677](https://github.com/Sequel-Ace/Sequel-Ace/pull/677))
- Update pull_request_template.md ([20d486621](https://github.com/Sequel-Ace/Sequel-Ace/commit/20d486621394d815f23f6efc591b067ed34c5875), [#656](https://github.com/Sequel-Ace/Sequel-Ace/pull/656))
- Various fixes/changes ([b10320f89](https://github.com/Sequel-Ace/Sequel-Ace/commit/b10320f89ac3714209dea18e829b64fe151a1f8e), [#660](https://github.com/Sequel-Ace/Sequel-Ace/pull/660))
- Update bug_report.md ([7710ca242](https://github.com/Sequel-Ace/Sequel-Ace/commit/7710ca2421258fc60bc739f9a3c9673654cafaf7), [#657](https://github.com/Sequel-Ace/Sequel-Ace/pull/657))

### Removed
- Remove a few extraneous log messages ([42e36f3b1](https://github.com/Sequel-Ace/Sequel-Ace/commit/42e36f3b15d9c037ca28a437b85535a18b5831ad), [#702](https://github.com/Sequel-Ace/Sequel-Ace/pull/702))

### Infra


## [3.0.1](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.0.1+%28*%29%22&expanded=true)

### Added


### Fixed
- Fix 3.0.0 bugs ([4d7ae04c3](https://github.com/Sequel-Ace/Sequel-Ace/commit/4d7ae04c369ea7941648b42cb19844b67f10e01a), [#654](https://github.com/Sequel-Ace/Sequel-Ace/pull/654))
- Fix couple of Crashlytics crashes ([8f079d3e2](https://github.com/Sequel-Ace/Sequel-Ace/commit/8f079d3e2d87e2521a50ff33eb0fc065c33c5682), [#637](https://github.com/Sequel-Ace/Sequel-Ace/pull/637))

### Changed
- Prepare Patch release ([53d6951d7](https://github.com/Sequel-Ace/Sequel-Ace/commit/53d6951d73263fb705919feb0a2eab131c62733a), [#655](https://github.com/Sequel-Ace/Sequel-Ace/pull/655))
- logging for missing key ([d02aa6cca](https://github.com/Sequel-Ace/Sequel-Ace/commit/d02aa6cca5ca99c6ffc7ea93ee889b0783f379de), [#653](https://github.com/Sequel-Ace/Sequel-Ace/pull/653))
- csv import crash ([7cf9986ae](https://github.com/Sequel-Ace/Sequel-Ace/commit/7cf9986aee780d34d36a1e999d859aa1c557eb1e), [#644](https://github.com/Sequel-Ace/Sequel-Ace/pull/644))
- extra crashlytics logging for file handles ([027af8ff3](https://github.com/Sequel-Ace/Sequel-Ace/commit/027af8ff3e859da75fdafeb50502579f1488fa4a), [#650](https://github.com/Sequel-Ace/Sequel-Ace/pull/650))
- fix-alias-completions ([69011da79](https://github.com/Sequel-Ace/Sequel-Ace/commit/69011da79af25aff65f9feb060f35bcbbf28bec8), [#635](https://github.com/Sequel-Ace/Sequel-Ace/pull/635))
- alerts being created on background threads ([863909cc8](https://github.com/Sequel-Ace/Sequel-Ace/commit/863909cc842c134051551f94cfeb789c8fac5d8e), [#648](https://github.com/Sequel-Ace/Sequel-Ace/pull/648))
- Extra logging and a guard on the connection error text ([eafbfe760](https://github.com/Sequel-Ace/Sequel-Ace/commit/eafbfe7608bd41aca6b606412bc8e18a1f90685d), [#647](https://github.com/Sequel-Ace/Sequel-Ace/pull/647))
- Maybe SPQueryController addHistory:forFileURL ([26f8b0bc3](https://github.com/Sequel-Ace/Sequel-Ace/commit/26f8b0bc321d73149771e09d045e99b750c19cd9), [#646](https://github.com/Sequel-Ace/Sequel-Ace/pull/646))
- guard when taking substring of query ([c56446491](https://github.com/Sequel-Ace/Sequel-Ace/commit/c564464919f5de0e214d8a107b74a4320ec20eb1), [#642](https://github.com/Sequel-Ace/Sequel-Ace/pull/642))
- some fixes re secure bookmark generation and logging ([4f5a19008](https://github.com/Sequel-Ace/Sequel-Ace/commit/4f5a19008488a8389a1958b13e2c022a8afd14ae), [#624](https://github.com/Sequel-Ace/Sequel-Ace/pull/624))

### Removed


### Infra


## [3.0.0](https://github.com/Sequel-Ace/Sequel-Ace/releases?q=%223.0.0+%28*%29%22&expanded=true)

### Added
- Implement localizations mechanism, add Spanish localization as first ([5dec70de2](https://github.com/Sequel-Ace/Sequel-Ace/commit/5dec70de2d255d330cfdec1b16e1bb62e0903b04), [#589](https://github.com/Sequel-Ace/Sequel-Ace/pull/589))
- Add fastlane automation for increment_build and for Changelog generation ([fa2e2e83a](https://github.com/Sequel-Ace/Sequel-Ace/commit/fa2e2e83a38e14222129a229994bd8662dce7b9c), [#530](https://github.com/Sequel-Ace/Sequel-Ace/pull/530))
- Add Swiftlint to the project ([363bb954d](https://github.com/Sequel-Ace/Sequel-Ace/commit/363bb954df3f664c4ca0ccc90896e5ce982347c9), [#525](https://github.com/Sequel-Ace/Sequel-Ace/pull/525))

### Fixed
- Fix password edit for favorites ([32f47dbdd](https://github.com/Sequel-Ace/Sequel-Ace/commit/32f47dbdd6d5e2231ffd1eb45d53f0c0fb2afe4c), [#632](https://github.com/Sequel-Ace/Sequel-Ace/pull/632))
- Fix query button mask ([f2eda67fc](https://github.com/Sequel-Ace/Sequel-Ace/commit/f2eda67fca3783104b081ddbaa1e431b1bff6f8c), [#628](https://github.com/Sequel-Ace/Sequel-Ace/pull/628))
- Fix localizable strings diffing ([4c871b660](https://github.com/Sequel-Ace/Sequel-Ace/commit/4c871b66017f6e03cf887837d03715e666f1ab7c))
- Fix reopening window when last window is closed ([ce01e021e](https://github.com/Sequel-Ace/Sequel-Ace/commit/ce01e021e4a30893b557c8b244886bda6586ee8e), [#616](https://github.com/Sequel-Ace/Sequel-Ace/pull/616))
- fixed deleting rows ([ce03040d4](https://github.com/Sequel-Ace/Sequel-Ace/commit/ce03040d487d0002ad877ceca0d5b8b04a3e82bc), [#609](https://github.com/Sequel-Ace/Sequel-Ace/pull/609))
- Fix connection controller and keychain getters ([a6bbf2986](https://github.com/Sequel-Ace/Sequel-Ace/commit/a6bbf298633606813fda5c1b54b03e9372cbd371), [#606](https://github.com/Sequel-Ace/Sequel-Ace/pull/606))
- Fix spelling of "occurred" ([7c390fca9](https://github.com/Sequel-Ace/Sequel-Ace/commit/7c390fca9930291e7ba614b3b399d1398f92fc27), [#601](https://github.com/Sequel-Ace/Sequel-Ace/pull/601))
- Fix color changes to favorites ([76e7b4233](https://github.com/Sequel-Ace/Sequel-Ace/commit/76e7b423304442b2a2625099ed3d046aeff56f8d), [#594](https://github.com/Sequel-Ace/Sequel-Ace/pull/594))
- fix path to Crashlytics upload-symbols script for SPM build ([5de34545d](https://github.com/Sequel-Ace/Sequel-Ace/commit/5de34545d09002e41ef802a78728611cac43d415), [#588](https://github.com/Sequel-Ace/Sequel-Ace/pull/588))
- Fix couple of warnings and deprecations ([3ef4e6ec0](https://github.com/Sequel-Ace/Sequel-Ace/commit/3ef4e6ec0c9dd3962641d929fa82c7fc516dce44), [#564](https://github.com/Sequel-Ace/Sequel-Ace/pull/564))
- Fix broken add connection button ([395006b91](https://github.com/Sequel-Ace/Sequel-Ace/commit/395006b9106f1d75e0495c019507ffb4b9138505), [#551](https://github.com/Sequel-Ace/Sequel-Ace/pull/551))
- Fix table list allow resizing table information ([4ba2bc9f3](https://github.com/Sequel-Ace/Sequel-Ace/commit/4ba2bc9f3b1fd063bc1b5aa6c46a99e69d644baf), [#538](https://github.com/Sequel-Ace/Sequel-Ace/pull/538))
- Fix Beta Scheme ([6f87e6cb5](https://github.com/Sequel-Ace/Sequel-Ace/commit/6f87e6cb5ca23978bf2d5db6ee8207677a6021bb), [#537](https://github.com/Sequel-Ace/Sequel-Ace/pull/537))
- Fix close button style on tabs ([6944d8d87](https://github.com/Sequel-Ace/Sequel-Ace/commit/6944d8d872737c33b1b89dbd4f6a004d60e93d86), [#536](https://github.com/Sequel-Ace/Sequel-Ace/pull/536))
- Fix Query ruler view and rows count ([d58d3a93a](https://github.com/Sequel-Ace/Sequel-Ace/commit/d58d3a93ab04359347fa997f229569cb82adb49f), [#535](https://github.com/Sequel-Ace/Sequel-Ace/pull/535))
- Fix changelog spacing ([d77e6bb7e](https://github.com/Sequel-Ace/Sequel-Ace/commit/d77e6bb7e5b08755b2da80d3338e16b235fd2237))
- Fix base branch ([f9b165d74](https://github.com/Sequel-Ace/Sequel-Ace/commit/f9b165d7420296aedfc06fdf6a2dff9f7cb1ed1b))
- fix tooltip font and size ([a3bb05633](https://github.com/Sequel-Ace/Sequel-Ace/commit/a3bb056333efd8eb6935dc40e586e25867955aba), [#527](https://github.com/Sequel-Ace/Sequel-Ace/pull/527))

### Changed
- Version Bump to 3007 ([3b88709cc](https://github.com/Sequel-Ace/Sequel-Ace/commit/3b88709cc6e1c95574680a2115776cdc781a6e66))
- Prepare 3.0.0 release ([bf38c32df](https://github.com/Sequel-Ace/Sequel-Ace/commit/bf38c32dfa99e90630092a7f11dc7963fc53387e), [#629](https://github.com/Sequel-Ace/Sequel-Ace/pull/629))
- re-added credits and license files ([7cf46ae81](https://github.com/Sequel-Ace/Sequel-Ace/commit/7cf46ae81f6dabd5694fd2b21cbd7f1446aa6b78), [#626](https://github.com/Sequel-Ace/Sequel-Ace/pull/626))
- Prepare 3.0.0 release ([d1d94b708](https://github.com/Sequel-Ace/Sequel-Ace/commit/d1d94b7083e5f4fe95ae70a8dbbcfff638fe53e2), [#621](https://github.com/Sequel-Ace/Sequel-Ace/pull/621))
- Update strings ([4b6dfa854](https://github.com/Sequel-Ace/Sequel-Ace/commit/4b6dfa8546e418a24551718814abd8b175ce4a02), [#619](https://github.com/Sequel-Ace/Sequel-Ace/pull/619))
- very large combo box warning ([17c7c0cd2](https://github.com/Sequel-Ace/Sequel-Ace/commit/17c7c0cd219d1f73c38746d0e8a532771db4917b), [#617](https://github.com/Sequel-Ace/Sequel-Ace/pull/617))
- #temp: swizzle initFileURLWithPath: isDirectory ([902a3ad06](https://github.com/Sequel-Ace/Sequel-Ace/commit/902a3ad069ddfb24322da47a58ec91d0e438e3ce), [#615](https://github.com/Sequel-Ace/Sequel-Ace/pull/615))
- Update to OpenSSL 1.1.1i ([93a8ebf2a](https://github.com/Sequel-Ace/Sequel-Ace/commit/93a8ebf2a64126776142b53f64658a9e76418fc7), [#614](https://github.com/Sequel-Ace/Sequel-Ace/pull/614))
- Shift + Cmd ←/→ shortcuts to next/previous arrows on content view ([4facbb7ca](https://github.com/Sequel-Ace/Sequel-Ace/commit/4facbb7cae16cc37b4eff71c0464a12dde47cb54), [#612](https://github.com/Sequel-Ace/Sequel-Ace/pull/612))
- Prepare 3.0.0 RC 1 ([b254d96f8](https://github.com/Sequel-Ace/Sequel-Ace/commit/b254d96f890f6b4eaadc025f2cc7d2d2c8a8efcc), [#610](https://github.com/Sequel-Ace/Sequel-Ace/pull/610))
- crashlytics-logging ([a1995e670](https://github.com/Sequel-Ace/Sequel-Ace/commit/a1995e670c6b78948c7cb06227c02f554323a1f6), [#605](https://github.com/Sequel-Ace/Sequel-Ace/pull/605))
- More bundle handling ([0f66fda86](https://github.com/Sequel-Ace/Sequel-Ace/commit/0f66fda86fac883dc66b2e6feb18aa11a3b98dc7), [#577](https://github.com/Sequel-Ace/Sequel-Ace/pull/577))
- Prepare 3.0.0 Beta 3 ([cca213eb0](https://github.com/Sequel-Ace/Sequel-Ace/commit/cca213eb0f5c1317ae9ac449a09ee1143789b8cf), [#592](https://github.com/Sequel-Ace/Sequel-Ace/pull/592))
- Re-implement double click functionality for Query editor ([b4f2a8589](https://github.com/Sequel-Ace/Sequel-Ace/commit/b4f2a85896f350750dd72f4a9cbdf91044e42d40), [#591](https://github.com/Sequel-Ace/Sequel-Ace/pull/591))
- Disable spanish xibs for now ([8be0a2c0c](https://github.com/Sequel-Ace/Sequel-Ace/commit/8be0a2c0c248b060cbb87356ac33f5def856cf2a))
- Update readme ([f769043d4](https://github.com/Sequel-Ace/Sequel-Ace/commit/f769043d47a38ea16468b27188de0b8ab7d15243))
- Crash and bug fixes ([29ea14a29](https://github.com/Sequel-Ace/Sequel-Ace/commit/29ea14a298649ff20e078700cd749951da32d300), [#587](https://github.com/Sequel-Ace/Sequel-Ace/pull/587))
- Switch Firebase to SPM instead of CocoaPods ([3437f246e](https://github.com/Sequel-Ace/Sequel-Ace/commit/3437f246ef90e8c754979316a9789c1da85c3e4c), [#586](https://github.com/Sequel-Ace/Sequel-Ace/pull/586))
- Migrate query history to sqlite ([084c8ce00](https://github.com/Sequel-Ace/Sequel-Ace/commit/084c8ce00c4988054af0a29d2a50ff3037989a81), [#507](https://github.com/Sequel-Ace/Sequel-Ace/pull/507))
- Beta 1 & 2 fixes, crash fixes, fix table content positioning ([8b73fb16a](https://github.com/Sequel-Ace/Sequel-Ace/commit/8b73fb16a04de6787a77e948c21280b0012c9df4), [#575](https://github.com/Sequel-Ace/Sequel-Ace/pull/575))
- Cleanup query abort support ([7614d5675](https://github.com/Sequel-Ace/Sequel-Ace/commit/7614d5675a6b77acf4c2556bf48bc53e9bb363dc), [#580](https://github.com/Sequel-Ace/Sequel-Ace/pull/580))
- Handle .saBundle and .spBundle files ([9b1cfae40](https://github.com/Sequel-Ace/Sequel-Ace/commit/9b1cfae401278fe6cb913816ea933a6001be1b28), [#576](https://github.com/Sequel-Ace/Sequel-Ace/pull/576))
- Prepare and ship 3.0.0 beta 1 ([6e1451200](https://github.com/Sequel-Ace/Sequel-Ace/commit/6e14512009c98e40a9d19254988f3c31d5a0e6e4), [#570](https://github.com/Sequel-Ace/Sequel-Ace/pull/570))
- Get rid of SPAlertSheets and fix over 150 warnings ([068622cc7](https://github.com/Sequel-Ace/Sequel-Ace/commit/068622cc72ae3e28497038dc27588c8bfc30909c), [#567](https://github.com/Sequel-Ace/Sequel-Ace/pull/567))
- Main thread crashes ([4db1f957b](https://github.com/Sequel-Ace/Sequel-Ace/commit/4db1f957b8dfe42de32bac905ac9cef5bb8ea2f8), [#566](https://github.com/Sequel-Ace/Sequel-Ace/pull/566))
- SPTextView: Rewrite behavior of syntax highlight and scroll ([db395c519](https://github.com/Sequel-Ace/Sequel-Ace/commit/db395c519d1cc224bebc7bfb84ba5faf8a6dd7e3), [#563](https://github.com/Sequel-Ace/Sequel-Ace/pull/563))
- kill tidb query and kill tidb connection support ([cb74045bd](https://github.com/Sequel-Ace/Sequel-Ace/commit/cb74045bd7cb20cc80b40ae9304b1391a873ed00), [#558](https://github.com/Sequel-Ace/Sequel-Ace/pull/558))
- SPTextView improvements and warnings ([52af9e8fe](https://github.com/Sequel-Ace/Sequel-Ace/commit/52af9e8fe9790678ce08786f1ff8d479677a98b9), [#561](https://github.com/Sequel-Ace/Sequel-Ace/pull/561))
- Compile libmysqlclient for Apple Silicon, enable ARM architecture, make Sequel Ace Apple Silicon compatible ([58fde57b0](https://github.com/Sequel-Ace/Sequel-Ace/commit/58fde57b0ccc136a120adc28fc6671e01245fc2e), [#560](https://github.com/Sequel-Ace/Sequel-Ace/pull/560))
- A couple of fixes ([fd57651a7](https://github.com/Sequel-Ace/Sequel-Ace/commit/fd57651a7f3c195546134dc1e12c33c9b12cdb43), [#559](https://github.com/Sequel-Ace/Sequel-Ace/pull/559))
- Tweak issue and pr templates ([cc27ecb13](https://github.com/Sequel-Ace/Sequel-Ace/commit/cc27ecb13c8c19caa9866e21ea3b2e78fc9a352f), [#552](https://github.com/Sequel-Ace/Sequel-Ace/pull/552))
- ShortcutRecorder converted to ARC and ARM ([c37335424](https://github.com/Sequel-Ace/Sequel-Ace/commit/c37335424fffa629aad3f7e00b5021a0775f3356), [#548](https://github.com/Sequel-Ace/Sequel-Ace/pull/548))
- Update pull_request_template.md ([c143b2038](https://github.com/Sequel-Ace/Sequel-Ace/commit/c143b20386a93343721a2b8b48de81839984d885), [#549](https://github.com/Sequel-Ace/Sequel-Ace/pull/549))
- Show alert on bad bundle, also actually delete it ([12d1d8a89](https://github.com/Sequel-Ace/Sequel-Ace/commit/12d1d8a890b92d261227e0d2664c0528447eb6dc), [#546](https://github.com/Sequel-Ace/Sequel-Ace/pull/546))
- Set theme jekyll-theme-tactile ([fe303c6f0](https://github.com/Sequel-Ace/Sequel-Ace/commit/fe303c6f0a8433ec5c62630f7dcc4bea795b431e))
- Set theme jekyll-theme-merlot ([0dae64631](https://github.com/Sequel-Ace/Sequel-Ace/commit/0dae646318c3edca117a463eac8a3b7aede436d7))
- Update build number to 3000 ([63ff8ff70](https://github.com/Sequel-Ace/Sequel-Ace/commit/63ff8ff70edea89148124611cde0c06b5674764b))
- Rewrite appearance for split view actions - part 2 ([007e82a73](https://github.com/Sequel-Ace/Sequel-Ace/commit/007e82a731c01e1d047a379022b537acca397219), [#532](https://github.com/Sequel-Ace/Sequel-Ace/pull/532))
- Merge branch 'staging' into main ([a4d2531a3](https://github.com/Sequel-Ace/Sequel-Ace/commit/a4d2531a333f9ab1650b10ede865c90c54fe3d6f))
- Gitignore prebuild file from release builds ([e08bfe067](https://github.com/Sequel-Ace/Sequel-Ace/commit/e08bfe0673181143607feba1ba76c27226c94809))
- Rewrite appearance for settings toolbar, database toolbar and split view actions ([a66c083f6](https://github.com/Sequel-Ace/Sequel-Ace/commit/a66c083f6de27da1b6b3c8b2a2a13aaa60cab16e), [#528](https://github.com/Sequel-Ace/Sequel-Ace/pull/528))
- Speedup loading list of the tables ([2e0af5728](https://github.com/Sequel-Ace/Sequel-Ace/commit/2e0af572832112045036a822557f9eeddfe5005a), [#526](https://github.com/Sequel-Ace/Sequel-Ace/pull/526))
- use fontname ([0d1205879](https://github.com/Sequel-Ace/Sequel-Ace/commit/0d1205879c672b91b0dd194966742bb1a0ebc86a), [#529](https://github.com/Sequel-Ace/Sequel-Ace/pull/529))
- Migrate document icon to xcassets for compatibility ([43327eaa5](https://github.com/Sequel-Ace/Sequel-Ace/commit/43327eaa5f5e77144e3e998209ec86704fbc5bd7), [#516](https://github.com/Sequel-Ace/Sequel-Ace/pull/516))
- Switch Development to Future Release 3.0.0 ([2b7b09d47](https://github.com/Sequel-Ace/Sequel-Ace/commit/2b7b09d4746390d1fbfb9d6e9d4beea42b1d3d1e), [#427](https://github.com/Sequel-Ace/Sequel-Ace/pull/427))

### Removed


### Infra


