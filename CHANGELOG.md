## [3.0.1]

### Added


### Fixed
4d7ae04c, Fix 3.0.0 bugs 
7cf9986a, CSV import crash
69011da7, Query alias completions 
863909cc, Alerts being created on background threads
26f8b0bc, SPQueryController addHistory:forFileURL crash
c5644649, Crash when taking substring of query
8f079d3e, Fix couple of Crashlytics crashes 
4f5a1900, Secure bookmark generation and logging 

### Changed


### Removed


### Infra
d02aa6cc, Added logging for missing key 


## [3.0.0]

### Added
4facbb7c,  Shift + Cmd ←/→ shortcuts to next/previous arrows on content view
b4f2a858, Re-implement double click functionality for Query editor 
5dec70de, Implement localizations mechanism, add Spanish localization as first 
cb74045b, kill tidb query and kill tidb connection support 
58fde57b, Compile libmysqlclient for Apple Silicon, enable ARM architecture, make Sequel Ace Apple Silicon compatible 

### Fixed
ce01e021, Fix reopening window when last window is closed 
17c7c0cd,   very large combo box warning
ce03040d, fixed deleting rows 
a6bbf298, Fix connection controller and keychain getters 
7c390fca, Fix spelling of "occurred" 
76e7b423, Fix color changes to favorites 
29ea14a2, Crash and bug fixes 
8b73fb16, Beta 1 & 2 fixes, crash fixes, fix table content positioning 
068622cc, Get rid of SPAlertSheets and fix over 150 warnings 
4db1f957, Main thread crashes  
3ef4e6ec, Fix couple of warnings and deprecations 
fd57651a, A couple of fixes  
395006b9, Fix broken add connection button 
12d1d8a8, Show alert on bad bundle, also actually delete it 
4ba2bc9f, Fix table list allow resizing table information 
6944d8d8, Fix close button style on tabs 
d58d3a93, Fix Query ruler view and rows count 
2e0af572, Speedup loading list of the tables 

### Changed
0f66fda8, More bundle handling 
3437f246, Switch Firebase to SPM instead of CocoaPods 
084c8ce0, Migrate query history to sqlite 
7614d567, Cleanup query abort support 
9b1cfae4, Handle .saBundle and .spBundle files 
db395c51, SPTextView: Rewrite behavior of syntax highlight and scroll 
52af9e8f, SPTextView improvements and warnings 
c3733542,  ShortcutRecorder converted to ARC and ARM
007e82a7, Rewrite appearance for split view actions - part 2 
a66c083f, Rewrite appearance for settings toolbar, database toolbar and split view actions 

### Removed


### Infra
93a8ebf2, Update to OpenSSL 1.1.1i 
a1995e67, crashlytics-logging 
5de34545, fix path to Crashlytics upload-symbols script for SPM build 
cc27ecb1, Tweak issue and pr templates 
6f87e6cb, Fix Beta Scheme 
fa2e2e83, Add fastlane automation for increment_build and for Changelog generation 
363bb954, Add Swiftlint to the project 


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
