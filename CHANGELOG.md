## [4.0.13]

### Added


### Fixed


### Changed


### Removed


### Infra


## [4.0.12]

### Added


### Fixed


### Changed


### Removed


### Infra


## [4.0.11]

### Added


### Fixed


### Changed


### Removed


### Infra


## [4.0.10]

### Added


### Fixed


### Changed


### Removed


### Infra


## [4.0.9]

### Added


### Fixed


### Changed


### Removed


### Infra


## [4.0.8]

### Added


### Fixed


### Changed


### Removed


### Infra


## [4.0.7]

### Added


### Fixed


### Changed


### Removed


### Infra


## [4.0.6]

### Added


### Fixed


### Changed


### Removed


### Infra


## [4.0.5]

### Added
- 9c3dd59f, Add preference for column types visibility 
- fe2b4506,  preference for column type visibility

### Fixed
- 1a47d524,  Error when altering Timestamp/Datetime columns in structure view

### Changed


### Removed


### Infra


## [4.0.4]

### Added


### Fixed
- b09e83df, Temporary Hotfix: Kill the task after termination 
- 9f6d5ec0, Fix column types when copying content with column types and when exporting 
- 49ec01cb,  Autocomplete weirdness
- 4e1dfbec,  Pasting content in unloaded text/blob field causes crash

### Changed
- 55f6cc02, Update OpenSSL to 1.1.1s 

### Removed


### Infra
- e2d231a1, Move OCMock to SPM from included framework 

## [4.0.3]

### Added


### Fixed
- 81e08793, Fix copy as SQL insert, Fix users modal resizing 

### Changed


### Removed


### Infra


## [4.0.2]

### Added
- 51fad246, Show column type in query editor and content view 

### Fixed
- 0756e835,  Remove data type names from CSV exports
- e8fa9487,   Text is not invalidated if just a cut or paste action is executed
- 9ccf9d19, Enable Help menu for connection screen 

### Changed


### Removed


### Infra


## [4.0.1]

### Added


### Fixed
- 1b531f4c, Fix closing all connections that are being opened

### Changed


### Removed


### Infra


## [4.0.0]

### Added
- 968d5361, Make analytics opt-out 

### Fixed
- c9d037a3,  Fix small typo on Export dialog
- e37e799e,  Portuguese localization
- f8f016ca, Fix major memory leak with database document not being released 
- 24676d51, Fix memory leaks when closing connection 
- c9e367d5, Fix saving session not saving / restoring tabs 
- 6381ff81, Fix crash on right click when field editor is active 
- dd6d02c5, Fix deprecations and warnings 
- 2dd099f6, Fix saving session more than once 

### Changed


### Removed
- 26092354, Breaking change: Officially drop MySQL 5.6 support 
- 6183c515, Drop macOS 10.12 

### Infra


## [3.5.3]

### Added


### Fixed


### Changed
- ebeb253c, Update MAMP Documentation regarding settings to connect 

### Removed


### Infra
- ed74fc85, Fix preferences path, keychain path, formatting  
- b10de447, [CLEANUP] Migration HowTo 
- c5ecac7e, chore: Included githubactions in the dependabot config 

## [3.5.2]

### Added


### Fixed
- c25b64a7, Possible fix for crash on tables with invisible columns 
- 03c9e6f1, Only append a default value if its specified 

### Changed


### Removed


### Infra


## [3.5.1]

### Added
- 3acc82a8,  support to copy table's name with database name in the list of tables

### Fixed


### Changed
- e9ac3d3c,  Attempt non-SSL connections if we fail connecting via SSL and SSL is not required

### Removed


### Infra
- 4dac484c, Infra cleanup, xcworkspace removal, hierarchy simplification 

## [3.5.0]

### Added
- 49ed5429, Support for pinning tables at top of tables list 
- 18af48c0,  Clicking S[tructure] C[ontent] or D[rop] in export window will toggle the value for all tables
- 7293fc50,   Filter and Sorting to Structure "fields" Table View.

### Fixed
- 7e16cee2, Disable dark mode variants of colors for tab bar 
- d46f0712, Disable TouchBar font panel API 

### Changed
- 8afb7e51,  Improved tab coloring appearance in Dark and Light modes
- 81ec264f,  Stop exporting a placeholder table for views in database exports
- da43e08c,  Accurately show SSL connection status always
- a37b653c,  Allow sorting every column on the Structure "fields" table view
- b002cae1,  Change default query editor font to Menlo to improve query editor performance

### Removed


### Infra


## [3.4.5]

### Added


### Fixed
- 8b89abd0,  Fix ssh connections broken by latest beta
- 3ea8b8c4,  Undo/Redo in Query Editor
- dbfc1369,  Add Find Next/Previous Menu Items with Shortcuts

### Changed
- 285a4f69,  Handle special characters in bookmark file names and paths
- 06794a4c,  - Remove GeneratedColumn from 'Copy as SQL Insert' #1282

### Removed


### Infra


## [3.4.4]

### Added


### Fixed
- f8ae57d1,  Fixed spreadsheet edit mode not honoring the cutoff length setting and add an option to edit multiline content in popup editor
- 5a65d157,  Fixed JSON viewer UI bugs and occasional failures to parse
- 4bd96b9f,  Fix user editing crash
- 00fa40e9,  Show time in addition to date for table created and updated at dates

### Changed


### Removed


### Infra


## [3.4.3]

### Added


### Fixed
- 3c313175,  #979 Properly reset the sorting column
- 864b9cb1, Show tab color on the first tab after it's expanded  #1216

### Changed


### Removed


### Infra
- 58e233e7, Attempt app center fixes for Xcode Cloud 
- c6695f62,  More bundle execution refactoring
- 671eb8d6,  Extract duplicate bundle dispatch logic
- 5c49df6a,  Clean up bundle loading

## [3.4.2]

### Added
- 4b298830, #fixed Shortcut to show/hide toolbar.  Shortcut to duplicate connection in new tab.

### Fixed
- c7594584, Add new line only when adding to existing queries 
- 5ba8e135, Make Preferences elements consistent #2 
- 904f9240, Reload query history after new entries are added 
- 72f4d43d, Favorite and placeholder display bug in query editor fixed 
- 88fb0a7d, Make Preferences elements consistent 
- f9fa6430, Fix crash when adding a row locally 
- 0f03c3a6, Allow Updating in Joined Instances 
- c44118ff, Remove redundant rawErrorText parameter 
- 4b298830,  Shortcut to show/hide toolbar. #added Shortcut to duplicate connection in new tab.

### Changed


### Removed


### Infra


## [3.4.1]

### Added


### Fixed
- a0ce9cc2, Fix stats counts not updating immediately for MySQL 8 
- 865043fa, Fix issue with Check for Update Failing 
- dd4d3093, Possible fix for issues with reconnecting 
- c0470af9,  Resolved 'alter table' bug for generated column

### Changed


### Removed


### Infra


## [3.4.0]

### Added


### Fixed
- 3dbc261f, Fix tabbing, titles and window order 
- 304f4d62, Fixed buggy behavior when trying to edit a generated column 
- a30214a9, Fix character counts for multi-byte strings 

### Changed


### Removed


### Infra


## [3.3.3]

### Added
- 22493671, Options when Deleting All Rows from Table 

### Fixed
- 3ecace04, Fix query timer after reconnect 
- 36c79bb8, Fix text jump and crash in query editor 

### Changed
- 879307e5, Take 2 at UTF8mb3 Support 
- bbf6f99c, Update encodings mappings 

### Removed


### Infra


## [3.3.2]

### Added
- f26d498b, New Nord theme 

### Fixed
- 878a9553, Fix grammar of "Check for Updates..." menu item 
- 09845e14, Fix getting windows for bundles 

### Changed


### Removed


### Infra


## [3.3.1]

### Added


### Fixed
- 8eee143e, Stop query button works as expected 
- a86bee7a, Fix tab title to show different string than window title 
- b7019ec0, Shortcuts for switching between tabs work as expected 
- 40e1cb9b, Open table in new tab works as expected 
- 6c8b05d0, Users icon is clickable and doesn't crash 
- 95fa0270, Improve tabs coloring 
- 5749f2bd, Display binary data as hex color in dark mode 

### Changed


### Removed
- a8f67d0a, Remove favorites divider 

### Infra


## [3.3.0]

### Added
- 57f0bbfb,  Ability to choose custom known_hosts file

### Fixed
- 8d56fa4f, re-added Edit inline or popup 
- 21e80ddb, Improve memory handling on SQL export 
- 672b44a4, #changed/ - Feature requests 955
- 588d1c42,  custom query result sorting
- 1dd4b0f0,  various small legibility issues across the documentation
- a792bd67,  Auto pair characters changing font
- e7b089b2,  exporting database with no selected table

### Changed
- c5f1a35c, Windows & Tabs refactoring: Remove Custom tabbing, implement native tabbed windows, rewrite app structure & hierarchy 
- 672b44a4, /#fixed - Feature requests 955
- 6018892c,  - foreign key creation when skip-show-database is on

### Removed
- 25942e3a, Remove unused SPFlippedView 
- 479f8a8a, Remove titleAccessoryView 

### Infra
- 4879793e, re-added SPTaskAdditions.m 
- 574bad74, Move NSWindowDelegate to Swift 

## [3.2.3]

### Added
- eb3378d5, No Newer Release Available info alert 
- caa4103b, kill ssh child processes on crash 
- baa65392, Edit cells inline or popup 'intelligent' switch 
- 3b188a8f, GitHub release checker 

### Fixed
- e6899d3b, Fix windows being created instead of populated 
- 07e01804, GitHub version checker fixes  
- b074152d,  saving individual query history
- 1a8377bf,  some analyzer warnings
- 53f87c86,  hide the filter for the current session
- f07244a8,  a couple of crashes
- 0b0ae9cf, allow insertion of NULL into varchar fields of length < 4  
- bff9f326,   latest crashes
- 62491cb9, edit in popup  
- 22de4acc, Export directory bookmarks 
- 8163a425,  some crashes

### Changed
- e4a68c3e, Don't show no new release available alert on startup 

### Removed


### Infra
- cf73d714, faster-stringForByteSize 
- b967b556, Sqlite error logging 

## [3.2.2]

### Added


### Fixed
- 3cb1d8aa,  maintain table filter state
- 104cc39f,  Tooltip crash attempt two
- 57890626, show error if setting the time zone fails  

### Changed
- 550a566e, Remove hard-coded minimum for resetting auto-increment 
- 839bdfc8, Build Version is now selectable 

### Removed


### Infra


## [3.2.1]

### Added


### Fixed
- cb22f005,   some crashes
- 2db66191,  Tooltip crash
- 73d2bfa9,  Export directory bookmarks

### Changed


### Removed


### Infra


## [3.2.0]

### Added
- cccc8755, UTC time tooltips 
- 85d0d6b5, Allow creating foreign keys referencing other databases 

### Fixed
- 9f32eeff,  import/export when table has a trigger
- 2e642c83,  information schema crash 883
- dab36f4f,  indenting issue on query editor
- fc7ced75,  text wrapping on query screen 
- e8b516b1,  a few crashes
- 4a711678,  Duplicate Table... name not editable 
- 2e468c1b,  some crashes
- e30d9f53,  rename table so that it drops the original table
- 0aa257c0,  Users screen schemas not updating
- 8a2dbe4d,  remove space char used to trigger syntax highlighting on paste
- a67ef9ed,  more fb crashes
- 351b9daa, Fix CSV Import Index out of bound in array crash 
- 30836826,  Bookmarks not being generated correctly

### Changed


### Removed


### Infra
- 69e2d39d,  Set some App Center configs and events
- c827cfd4, Rename SPWindowController's properties, start AutoLayout programatically without xibs 
- 05fa4958, Appcenter upload_symbols script 
- 351643ce, Get rid of Firebase Crashlytics, move to MSAppCenter Crashlytics & Analytics 
- e6ffd106, Windows hierarchy cleanup and typesafety, part 1 
- fac631db, Added more logging and removed a few non-fatal error reports 

## [3.1.1]

### Added
- ebe453a7, Add Chinese localizations 
- edd5e4eb, Add support for generic Spanish language next to Spanish (Spain) language 

### Fixed
- b7578c22, Fix Broken run current query button 
- 74fd2acb,  syntax highlighting not being properly applied after pasting
- f220ccb3,  Some crashes
- a53198a7,  Query history duplicates and order
- 100cd2db,  Table history buttons not working
- cb7f9022, Fix reconnect timeout - accept SSH password after network connection reset  
- 056bb81a,  some more crashes

### Changed
- 3350b13d, apply custom font to all inserted snippets  
- 5df7a388, highlight errors in red in the query status field 
- 8f91391c, Get rid of CocoaPods, switch FMDB to SPM, enable Swift standard libraries 
- 656cc948, Consistently use encoding utf8mb4 

### Removed


### Infra
- 056e7e9e, os_log wrapper for swift 

## [3.1.0]

### Added
- 01fa877d, Copy tables between databases 

### Fixed
- 9bd486ab,  table information eye symbol crash
- 5ae47f9d,  exporting multiple tables 
- 1bcfe5f4,  changing custom query font and respect font when inserting favourite
- d21af610,  some crashes
- c08f883b,  some crashes
- 0738da94,  Two custom queries with syntax errors = crash  
- d6e987d9, Fix cutoff file names in Preferences 
- 02b68274,   display json string properly in edit popup
- e424db42,  - SSHTunnel crash
- 8cca7500,  more crashes
- 9430b976, Improve query editor performance - Revert double click functionality by overriding NSTextStorage 
- dddf027d,  a few new crashes
- 4030d3fb, Fix quick connect not clearing fields 

### Changed
- da1c1c8c,  better handle stale bookmarks 
- 5474b93f,  Better export error handling
- 2664a177, Bookmarks improvements 
- 460e706b, Always show tab bar as native macOS apps, cleanup tab bar code 

### Removed


### Infra
- ae7d0dd7, Improved clarity of bug report issue template 
- e254ba0e, More doc tweaks  
- 4e8931d3, Doc tweaks 
- 4044855c,  Connection logging
- dea19267, App Sandbox and Secure Bookmarks docs 
- 051134ab,  fave colour support optimisation

## [3.0.2]

### Added


### Fixed
- c199dd0d,  spfieldmappercontroller match header names crash
- f03f6146, Fix Query Window Forgets Active Query 
- b0b0da30,  SPExtendedTableInfo loadTable crash
- b7b93ad3,   SPTableCopy _createTableStatementFor:inDatabase crash
- f2899dd6, Homebrew installation command 
- 4540f8e8,  SPTableInfo crash
- b33ac44f, Fixed commenting out one or multiple lines in query editor 
- 7eba8716,  double error alerts on connection failure
- c7cc1506,  sp table structure load table crash
- 07b2d485,  - tableChanged NSNull Collation crash
- 013c0f94,  tableViewColumnDidResize crash
- 38a712e7, Update UI for light and dark mode on Tabs 
- 5d70e94d,  deriveQueryString crash
- 03fefe99,  databasestructure crash
- 4c3f1a82, Keychain improvements and safety checks 
- ab1e3ea7, Query editor improvements 
- 2bf774db, Use entered password for favorite if it changed 
- b10320f8, Various fixes/changes 

### Changed
- cd85311a, Improvements to Console 

### Removed


### Infra
- 42e36f3b, Remove a few extraneous log messages 
- 22926dce, Change all NSArrayObjectAtIndex to safeObjectAtIndex 
- 21fbea78,  logging in RegexKit's Exception and Error generation code
- 20d48662, Update pull_request_template.md 
- 7710ca24, Update bug_report.md 

## [3.0.1]

### Added


### Fixed
- 4d7ae04c, Fix 3.0.0 bugs 
- 7cf9986a, CSV import crash
- 69011da7, Query alias completions 
- 863909cc, Alerts being created on background threads
- 26f8b0bc, SPQueryController addHistory:forFileURL crash
- c5644649, Crash when taking substring of query
- 8f079d3e, Fix couple of Crashlytics crashes 
- 4f5a1900, Secure bookmark generation and logging 

### Changed


### Removed


### Infra
- d02aa6cc, Added logging for missing key 


## [3.0.0]

### Added
- 4facbb7c,  Shift + Cmd ←/→ shortcuts to next/previous arrows on content view
- b4f2a858, Re-implement double click functionality for Query editor 
- 5dec70de, Implement localizations mechanism, add Spanish localization as first 
- cb74045b, kill tidb query and kill tidb connection support 
- 58fde57b, Compile libmysqlclient for Apple Silicon, enable ARM architecture, make Sequel Ace Apple Silicon compatible 

### Fixed
- ce01e021, Fix reopening window when last window is closed 
- 17c7c0cd,   very large combo box warning
- ce03040d, fixed deleting rows 
- a6bbf298, Fix connection controller and keychain getters 
- 7c390fca, Fix spelling of "occurred" 
- 76e7b423, Fix color changes to favorites 
- 29ea14a2, Crash and bug fixes 
- 8b73fb16, Beta 1 & 2 fixes, crash fixes, fix table content positioning 
- 068622cc, Get rid of SPAlertSheets and fix over 150 warnings 
- 4db1f957, Main thread crashes  
- 3ef4e6ec, Fix couple of warnings and deprecations 
- fd57651a, A couple of fixes  
- 395006b9, Fix broken add connection button 
- 12d1d8a8, Show alert on bad bundle, also actually delete it 
- 4ba2bc9f, Fix table list allow resizing table information 
- 6944d8d8, Fix close button style on tabs 
- d58d3a93, Fix Query ruler view and rows count 
- 2e0af572, Speedup loading list of the tables 

### Changed
- 0f66fda8, More bundle handling 
- 3437f246, Switch Firebase to SPM instead of CocoaPods 
- 084c8ce0, Migrate query history to sqlite 
- 7614d567, Cleanup query abort support 
- 9b1cfae4, Handle .saBundle and .spBundle files 
- db395c51, SPTextView: Rewrite behavior of syntax highlight and scroll 
- 52af9e8f, SPTextView improvements and warnings 
- c3733542,  ShortcutRecorder converted to ARC and ARM
- 007e82a7, Rewrite appearance for split view actions - part 2 
- a66c083f, Rewrite appearance for settings toolbar, database toolbar and split view actions 

### Removed


### Infra
- 93a8ebf2, Update to OpenSSL 1.1.1i 
- a1995e67, crashlytics-logging 
- 5de34545, fix path to Crashlytics upload-symbols script for SPM build 
- cc27ecb1, Tweak issue and pr templates 
- 6f87e6cb, Fix Beta Scheme 
- fa2e2e83, Add fastlane automation for increment_build and for Changelog generation 
- 363bb954, Add Swiftlint to the project 


## [2.3.1]

### Added
- Added connection option to enable Cleartext plugin (fixes #368: Thanks, @SumBeam!)

### Fixed
- Made query history search much faster (fixes #366)
- Fixed re-ordering the query favorites by drag and drop (fixes #475)
- Fixed favorite query variables always displaying black in the query editor (fixes #382)
- Fixed invalid bundles and Beeping of the app (fixes #489)
- Fixed bracket highlighter crash on macOS 10.10 and 10.11 (fixes #511)

### Changed

### Removed
