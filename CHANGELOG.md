## [3.0.0]

### Added
cb74045b, kill tidb query and kill tidb connection support 
58fde57b, Compile libmysqlclient for Apple Silicon, enable ARM architecture, make Sequel Ace Apple Silicon compatible 

### Fixed
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
db395c51, SPTextView: Rewrite behavior of syntax highlight and scroll 
52af9e8f, SPTextView improvements and warnings 
c3733542,  ShortcutRecorder converted to ARC and ARM
007e82a7, Rewrite appearance for split view actions - part 2 
a66c083f, Rewrite appearance for settings toolbar, database toolbar and split view actions 

### Removed


### Infra
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
