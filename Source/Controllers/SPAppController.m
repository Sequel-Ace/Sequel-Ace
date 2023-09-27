//
//  SPAppController.m
//  sequel-pro
//
//  Created by Lorenz Textor (lorenz@textor.ch) on May 1, 2002.
//  Copyright (c) 2002-2003 Lorenz Textor. All rights reserved.
//  Copyright (c) 2012 Sequel Pro Team. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

#import "SPKeychain.h"
#import "SPAppController.h"
#import "SPDatabaseDocument.h"
#import "SPPreferenceController.h"
#import "SPAboutController.h"
#import "SPDataImport.h"
#import "SPEncodingPopupAccessory.h"
#import "SPPreferencesUpgrade.h"
#import "SPBundleEditorController.h"
#import "SPTooltip.h"
#import "SPBundleHTMLOutputController.h"
#import "SPChooseMenuItemDialog.h"
#import "SPCustomQuery.h"
#import "SPFavoritesController.h"
#import "SPEditorTokens.h"
#import "SPBundleCommandRunner.h"
#import "SPCopyTable.h"
#import "SPSyntaxParser.h"
#import "SPTextView.h"
#import "SPFunctions.h"
#import "SPBundleManager.h"
#import "MGTemplateEngine.h"
#import "ICUTemplateMatcher.h"
#import "SPTreeNode.h"
#import "SPConnectionController.h"
#import "SPFavoritesOutlineView.h"

#import "sequel-ace-Swift.h"

@import AppCenter;
@import AppCenterAnalytics;
@import AppCenterCrashes;

static const double SPDelayBeforeCheckingForNewReleases = 10;

@interface SPAppController ()
@property (strong) IBOutlet NSMenu *mainMenu;

- (void)_copyDefaultThemes;

- (void)openConnectionFileAtPath:(NSString *)filePath;
- (void)openSQLFileAtPath:(NSString *)filePath;
- (void)openSessionBundleAtPath:(NSString *)filePath;
- (void)openColorThemeFileAtPath:(NSString *)filePath;
- (void)checkForNewVersionWithDelay:(double)delay andIsFromMenuCheck:(BOOL)isFromMenuCheck;
- (void)removeCheckForUpdatesMenuItem;
- (void)addCheckForUpdatesMenuItem;
- (void)checkForNewVersionFromMenu;

@property (readwrite, strong) NSFileManager *fileManager;

@property (nonatomic, strong, readwrite) TabManager *tabManager;

@end

@implementation SPAppController

@synthesize lastBundleBlobFilesDirectory;
@synthesize fileManager;
@synthesize mainMenu;
@synthesize sshProcessIDs;
#pragma mark -
#pragma mark Initialisation

/**
 * Initialise the application's main controller, setting itself as the app delegate.
 */
- (instancetype)init
{
    if ((self = [super init])) {
        aboutController = nil;
        lastBundleBlobFilesDirectory = nil;
        _spfSessionDocData = [[NSMutableDictionary alloc] init];

        runningActivitiesArray = [[NSMutableArray alloc] init];
        sshProcessIDs = [[NSMutableArray alloc] init];
        fileManager = [NSFileManager defaultManager];
        _tabManager = [[TabManager alloc] initWithAppController:self];

        //Create runtime directiories
        [fileManager createDirectoryAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"tmp"] withIntermediateDirectories:true attributes:nil error:nil];
        [fileManager createDirectoryAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@".keys"] withIntermediateDirectories:true attributes:nil error:nil];

        //Handle Appearance on macOS 10.14+
        if (@available(macOS 10.14, *)) {
            //Switch Appearance on Application startup (prevent Appearance blink)
            [self switchAppearance];

            //Register an observer to switch Appearance at runtime
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(defaultsChanged:) name:NSUserDefaultsDidChangeNotification object:nil];
        }
        [NSApp setDelegate:self];
    }
    return self;
}

/**
 * Called even before init so we can register our preference defaults
 */
+ (void)initialize
{
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];

    NSMutableDictionary *preferenceDefaults = [NSMutableDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:SPPreferenceDefaultsFile ofType:@"plist"]];
    // Register application defaults
    [prefs registerDefaults:preferenceDefaults];

    // Upgrade prefs before any other parts of the app pick up on the values
    SPApplyRevisionChanges();
}

/**
 * Called when default properties had a change at runtime
 */
- (void)defaultsChanged:(NSNotification *)notification {
    [self switchAppearance];
}

/**
 * Called when need to switch application appearance - on startup and when userDefaults changed
 */
- (void)switchAppearance {
    SPMainQSync(^{
        if (@available(macOS 10.14, *)) {
            NSInteger appearance = [[NSUserDefaults standardUserDefaults] integerForKey:SPAppearance];

            if (appearance == 1) {
                NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            } else if (appearance == 2) {
                NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            } else {
                NSApp.appearance = nil;
            }
        }
    });
}

/**
 * Initialisation stuff upon nib awakening
 */
- (void)awakeFromNib
{
    [super awakeFromNib];
    
    // Register url scheme handle
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                       andSelector:@selector(handleEvent:withReplyEvent:)
                                                     forEventClass:kInternetEventClass
                                                        andEventID:kAEGetURL];

    // Set up the prefs controller
    prefsController = [[SPPreferenceController alloc] init];

    // Register SPAppController as services provider
    [NSApp setServicesProvider:self];

    // Register SPAppController for AppleScript events
    [[NSScriptExecutionContext sharedScriptExecutionContext] setTopLevelObject:self];
}

/**
 * Initialisation stuff after launch is complete
 */
- (void)applicationDidFinishLaunching:(NSNotification *)notification {

    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if ([prefs boolForKey:SPSaveApplicationUsageAnalytics]) {
        // Send time interval for non-critical logs
        // must set before calling AppCenter.start
        // 5 mins?
        [MSACAnalytics setTransmissionInterval:60*5];

        // Use 30 MB for storage for logs
        [MSACAppCenter setMaxStorageSize:(30 * 1024 * 1024) completionHandler:nil];
        [MSACAppCenter start:@"65535bfb-1763-40fd-896b-a3aaae06227f" withServices:@[[MSACAnalytics class], [MSACCrashes class]]];

#ifdef DEBUG
        // default is 5 = MSACLogLevelWarning
        [MSACAppCenter setLogLevel:MSACLogLevelDebug];
#endif

        if(MSACAppCenter.isEnabled == YES && MSACAppCenter.isConfigured == YES){
            SPLog(@"Started MSACAppCenter. sdkVersion: %@. defaultLogLevel: %lu", MSACAppCenter.sdkVersion, (unsigned long) MSACAppCenter.logLevel);
        }
        else{
            SPLog(@"MSACAppCenter FAILED to start.");
        }
    }


    // this reRequests access to all bookmarks
    SecureBookmarkManager *secureBookmarkManager = SecureBookmarkManager.sharedInstance;

    // prompt user to recreate secure bookmarks
    if(secureBookmarkManager.staleBookmarks.count > 0){

        SPLog(@"We have stale bookmarks");

        NSMutableString *staleBookmarksString = [[NSMutableString alloc] initWithCapacity:secureBookmarkManager.staleBookmarks.count];

        for(NSString* staleFile in secureBookmarkManager.staleBookmarks){
            [staleBookmarksString appendFormat:@"%@\n", staleFile.lastPathComponent];
            SPLog(@"fileNames adding stale file: %@", staleFile.lastPathComponent);
        }

        [staleBookmarksString setString:[staleBookmarksString dropSuffixWithSuffix:@"\n"]];

        [NSAlert createAccessoryAlertWithTitle:NSLocalizedString(@"App Sandbox Issue", @"App Sandbox Issue") message:[NSString stringWithFormat:NSLocalizedString(@"You have stale secure bookmarks:\n\n%@\n\nWould you like to re-request access now?", @"Would you like to re-request access now?"), staleBookmarksString] accessoryView:_staleBookmarkHelpView primaryButtonTitle:NSLocalizedString(@"Yes", @"Yes")
                          primaryButtonHandler:^{
            SPLog(@"re-request access now");
            [self->prefsController showWindow:self];
            [self->prefsController displayPreferencePane:self->prefsController->fileItem];
        } cancelButtonHandler:^{
            SPLog(@"No not now");
        }];
    }

    // init SQLite query history
    SQLiteHistoryManager __unused *sqliteHistoryManager = SQLiteHistoryManager.sharedInstance;
    SQLitePinnedTableManager __unused *sqLitePinnedTableManager = SQLitePinnedTableManager.sharedInstance;

    NSDictionary *spfDict = nil;
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    if (args.count == 5) {
        if (([[args objectAtIndex:1] isEqualToString:@"--spfData"] && [[args objectAtIndex:3] isEqualToString:@"--dataVersion"] && [[args objectAtIndex:4] isEqualToString:@"1"]) || ([[args objectAtIndex:3] isEqualToString:@"--spfData"] && [[args objectAtIndex:1] isEqualToString:@"--dataVersion"] && [[args objectAtIndex:2] isEqualToString:@"1"])) {
            NSData* data = [[args objectAtIndex:2] dataUsingEncoding:NSUTF8StringEncoding];
            NSError *error = nil;
            spfDict = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error];
            if (error) {
                spfDict = nil;
            }
        }
    }
    executeOnBackgroundThread(^{
        // fake the dbViewInfoPanelSplit being open
        NSMutableArray *dbViewInfoPanelSplit = [[NSMutableArray alloc] initWithCapacity:2];
        [dbViewInfoPanelSplit addObject:@"0.000000, 0.000000, 359.500000, 577.500000, NO, NO"];
        [dbViewInfoPanelSplit addObject:@"0.000000, 586.500000, 359.500000, 190.500000, NO, NO"];
        [prefs setObject:dbViewInfoPanelSplit forKey:@"NSSplitView Subview Frames DbViewInfoPanelSplit"];
    });

    [self checkForNewVersionWithDelay:SPDelayBeforeCheckingForNewReleases andIsFromMenuCheck:NO];

    // Add menu item to check for updates
    [self addCheckForUpdatesMenuItem];

    [prefs addObserver:self forKeyPath:SPShowUpdateAvailable options:NSKeyValueObservingOptionNew context:NULL];

    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(externalApplicationWantsToOpenADatabaseConnection:) name:@"ExternalApplicationWantsToOpenADatabaseConnection" object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(duplicateConnectionToTab:) name:SPDocumentDuplicateTabNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(switchToPreviousTab:) name:SPWindowSelectPreviousTabNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(switchToNextTab:) name:SPWindowSelectNextTabNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveConnectionsToSPF:) name:SPDocumentSaveToSPFNotification object:nil];

    [SPBundleManager.shared reloadBundles:self];
    [self _copyDefaultThemes];

    // If no documents are open, open one
    if (![self frontDocument]) {

        SPWindowController *newWindowController = [self.tabManager replaceTabServiceWithInitialWindow];

        if (spfDict) {
            [newWindowController.databaseDocument setState:spfDict];
        }

        // Set autoconnection if appropriate
        if ([prefs boolForKey:SPAutoConnectToDefault] && secureBookmarkManager.staleBookmarks.count == 0) {
            [newWindowController.databaseDocument connect];
        }
    }
}

- (void)addCheckForUpdatesMenuItem {
    if (NSBundle.mainBundle.isMASVersion == NO && [[NSUserDefaults standardUserDefaults] boolForKey:SPShowUpdateAvailable] == YES) {
        SPLog(@"Adding menu item to check for updates");
        NSMenuItem *updates = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Check for Updates...", @"Menu item Check for Updates...") action:@selector(checkForNewVersionFromMenu) keyEquivalent:@""];
        [mainMenu insertItem:updates atIndex:1];
    }
}

- (void)removeCheckForUpdatesMenuItem {

    [mainMenu.itemArray enumerateObjectsUsingBlock:^(NSMenuItem *item2, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([item2.title isEqualToString:NSLocalizedString(@"Check for Updates...", @"Menu item Check for Updates...")]) {
            SPLog(@"Removing menu item to check for updates");
            [mainMenu removeItemAtIndex:idx];
            *stop = YES;
        }
    }];
}

- (void)checkForNewVersionFromMenu{
    [self checkForNewVersionWithDelay:0 andIsFromMenuCheck:YES];
}

- (void)checkForNewVersionWithDelay:(double)delay andIsFromMenuCheck:(BOOL)isFromMenuCheck {

    SPLog(@"isFromMenuCheck %d", isFromMenuCheck);
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SPShowUpdateAvailable] == YES) {
        SPLog(@"checking for updates");
        executeOnLowPrioQueueAfterADelay(^{
            [NSBundle.mainBundle checkForNewVersionWithIsFromMenuCheck:isFromMenuCheck];
        }, delay);
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
    if ([keyPath isEqualToString:SPShowUpdateAvailable]) {
        if([[change objectForKey:NSKeyValueChangeNewKey] boolValue] == YES){
            [self addCheckForUpdatesMenuItem];
        }
        else if([[change objectForKey:NSKeyValueChangeNewKey] boolValue] == NO){
            [self removeCheckForUpdatesMenuItem];
        }
    }
}

- (void)externalApplicationWantsToOpenADatabaseConnection:(NSNotification *)notification {
    NSDictionary *userInfo = [notification userInfo];
    NSString *MAMP_SPFVersion = [userInfo objectForKey:@"dataVersion"];
    if ([MAMP_SPFVersion isEqualToString:@"1"]) {
        NSDictionary *spfStructure = [userInfo objectForKey:@"spfData"];
        if (spfStructure) {
            SPWindowController *windowController = [self.tabManager newWindowForWindow];
            [windowController.databaseDocument setState:spfStructure];
        }
    }
}

- (void)switchToPreviousTab:(NSNotification *)notification {
    [self.tabManager switchToPreviousTab];
}

- (void)switchToNextTab:(NSNotification *)notification {
    [self.tabManager switchToNextTab];
}

- (void)duplicateConnectionToTab:(NSNotification *)notification {

    NSDictionary *userInfo = [notification userInfo];
    if (userInfo) {
        SPWindowController *newWindowController = [self.tabManager newWindowForTab];
        [newWindowController.databaseDocument setState:userInfo];
    }
}

- (void)saveConnectionsToSPF:(NSNotification *)notification {

    NSString *fileName = [notification object];
    NSError *error = nil;
//    NSString *contextInfo = [[notification userInfo] objectForKey:@"contextInfo"];
    NSNumber *encrypted = [[notification userInfo] objectForKey:@"encrypted"];
    NSString *saveConnectionEncryptString = [[notification userInfo] objectForKey:@"saveConnectionEncryptString"];
    NSNumber *auto_connect = [[notification userInfo] objectForKey:@"auto_connect"];
    NSNumber *save_password = [[notification userInfo] objectForKey:@"save_password"];
    NSNumber *include_session = [[notification userInfo] objectForKey:@"include_session"];
    NSNumber *save_editor_content = [[notification userInfo] objectForKey:@"save_editor_content"];

    // Sub-folder 'Contents' will contain all untitled connection as single window or tab.
    // info.plist will contain the opened structure (windows and tabs for each window). Each connection
    // is linked to a saved spf file either in 'Contents' for unTitled ones or already saved spf files.

    if(!fileName || ![fileName length]) {
        return;
    }

    // If bundle exists remove it
    if([fileManager fileExistsAtPath:fileName]) {
        [fileManager removeItemAtPath:fileName error:&error];
        if(error != nil) {
            NSAlert *errorAlert = [NSAlert alertWithError:error];
            [errorAlert runModal];
            return;
        }
    }

    [fileManager createDirectoryAtPath:fileName withIntermediateDirectories:YES attributes:nil error:&error];

    if (error != nil) {
        [[NSAlert alertWithError:error] runModal];
        return;
    }

    [fileManager createDirectoryAtPath:[NSString stringWithFormat:@"%@/Contents", fileName] withIntermediateDirectories:YES attributes:nil error:&error];

    if (error != nil) {
        [[NSAlert alertWithError:error] runModal];
        return;
    }

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSMutableArray *windows = [NSMutableArray array];

    // retrieve save panel data for passing them to each doc
    NSMutableDictionary *spfDocData_temp = [NSMutableDictionary dictionary];
    [spfDocData_temp setObject:encrypted forKey:@"encrypted"];
    if ([[spfDocData_temp objectForKey:@"encrypted"] boolValue]) {
        [spfDocData_temp setObject:saveConnectionEncryptString forKey:@"e_string"];
    }
    [spfDocData_temp setObject:auto_connect forKey:@"auto_connect"];
    [spfDocData_temp setObject:save_password forKey:@"save_password"];
    [spfDocData_temp setObject:include_session forKey:@"include_session"];
    [spfDocData_temp setObject:save_editor_content forKey:@"save_editor_content"];

    // Save the session's accessory view settings
    [self setSpfSessionDocData:spfDocData_temp];

    [info setObject:[NSNumber numberWithBool:[[spfDocData_temp objectForKey:@"encrypted"] boolValue]] forKey:@"encrypted"];
    [info setObject:[NSNumber numberWithBool:[[spfDocData_temp objectForKey:@"auto_connect"] boolValue]] forKey:@"auto_connect"];
    [info setObject:[NSNumber numberWithBool:[[spfDocData_temp objectForKey:@"save_password"] boolValue]] forKey:@"save_password"];
    [info setObject:[NSNumber numberWithBool:[[spfDocData_temp objectForKey:@"include_session"] boolValue]] forKey:@"include_session"];
    [info setObject:[NSNumber numberWithBool:[[spfDocData_temp objectForKey:@"save_editor_content"] boolValue]] forKey:@"save_editor_content"];
    [info setObject:@1 forKey:SPFVersionKey];
    [info setObject:@"connection bundle" forKey:SPFFormatKey];

    NSMutableArray *processedWindows = [NSMutableArray new];

    NSSet *allWindows = [self.tabManager windows];
    for (NSWindow *window in allWindows) {
        NSMutableArray *tabs = [NSMutableArray array];
        NSMutableDictionary *win = [NSMutableDictionary dictionary];

        NSArray *windowsToProcess = [[window tabbedWindows] count] > 0 ? [window tabbedWindows] : @[window];
        for (NSWindow *processedWindow in windowsToProcess) {
            SPWindowController *windowController = processedWindow.windowController;
            if ([processedWindows containsObject:windowController.uniqueID]) {
                continue;
            }

            // Skip not connected docs eg if connection controller is displayed (TODO maybe to be improved)
            if (![windowController.databaseDocument mySQLVersion]) {
                continue;
            }

            NSMutableDictionary *tabData = [NSMutableDictionary dictionary];
            if([windowController.databaseDocument isUntitled]) {
                // new bundle file name for untitled docs
                NSString *newName = [NSString stringWithFormat:@"%@.%@", [NSString stringWithNewUUID], SPFileExtensionDefault];
                // internal bundle path to store the doc
                NSString *filePath = [NSString stringWithFormat:@"%@/Contents/%@", fileName, newName];
                // save it as temporary spf file inside the bundle with save panel options spfDocData_temp
                [windowController.databaseDocument saveDocumentWithFilePath:filePath inBackground:NO onlyPreferences:NO contextInfo:[NSDictionary dictionaryWithDictionary:spfDocData_temp]];
                [windowController.databaseDocument setIsSavedInBundle:YES];
                [tabData setObject:@NO forKey:@"isAbsolutePath"];
                [tabData setObject:newName forKey:@"path"];
            } else {
                // save it to the original location and take the file's spfDocData
                [windowController.databaseDocument saveDocumentWithFilePath:[[windowController.databaseDocument fileURL] path] inBackground:YES onlyPreferences:NO contextInfo:nil];
                [tabData setObject:@YES forKey:@"isAbsolutePath"];
                [tabData setObject:[[windowController.databaseDocument fileURL] path] forKey:@"path"];
            }
            [tabs addObject:tabData];
            [win setObject:NSStringFromRect([[windowController window] frame]) forKey:@"frame"];

            [processedWindows addObject:windowController.uniqueID];
        }
        if ([tabs count] > 0) {
            [win setObject:tabs forKey:@"tabs"];
        }
        if ([[win allValues] count] > 0) {
            [windows addObject:win];
        }
    }
    [info setObject:windows forKey:@"windows"];

    error = nil;

    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];

    if (error) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error while converting session data", @"error while converting session data") message:[error localizedDescription] callback:nil];
        return;
    }

    [plist writeToFile:[NSString stringWithFormat:@"%@/info.plist", fileName] options:NSAtomicWrite error:&error];

    if (error != nil){
        NSAlert *errorAlert = [NSAlert alertWithError:error];
        [errorAlert runModal];

        return;
    }

    // Register spfs bundle in Recent Files
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:fileName]];
}

/**
 * Menu item validation.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = [menuItem action];
    if (action == @selector(newWindow:) || action == @selector(openConnectionSheet:)) {
        return YES;
    }
    if (action == @selector(newTab:)) {
        return ([[[self.tabManager activeWindowController] window] attachedSheet] == nil);
    }
    if (action == @selector(duplicateTab:)) {
        return ([[self frontDocument] getConnection] != nil);
    }
    if (action == @selector(openAboutPanel:) || action == @selector(openPreferences:) || action == @selector(visitWebsite:) || action == @selector(checkForNewVersionFromMenu)) {
        return YES;
    }

    if (action == @selector(visitHelpWebsite:) || action == @selector(visitFAQWebsite:) || action == @selector(viewKeyboardShortcuts:)) {
        return YES;
    }

    if (self.tabManager.activeWindowController.databaseDocument) {
        return [self.tabManager.activeWindowController.databaseDocument validateMenuItem:menuItem];
    }
    return YES;
}

#pragma mark -
#pragma mark Open methods

/**
 * NSOpenPanel delegate to control encoding popup and allowMultipleSelection
 */
- (void)panelSelectionDidChange:(id)sender
{
    if ([sender isKindOfClass:[NSOpenPanel class]]) {
        if([[[[[sender URL] path] pathExtension] lowercaseString] isEqualToString:SPFileExtensionSQL]) {
            [encodingPopUp setEnabled:YES];
        } else {
            [encodingPopUp setEnabled:NO];
        }
    }
}

/**
 * NSOpenPanel for selecting sql or spf file
 */
- (IBAction)openConnectionSheet:(id)sender
{
    // Avoid opening more than NSOpenPanel
    if (encodingPopUp) {
        NSBeep();
        return;
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];

    [panel setDelegate:self];
    [panel setCanSelectHiddenExtension:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setResolvesAliases:YES];

    // If no lastSqlFileEncoding in prefs set it to UTF-8
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];

    if (![prefs integerForKey:SPLastSQLFileEncoding]) {
        [prefs setInteger:4 forKey:SPLastSQLFileEncoding];
    }

    [panel setAccessoryView:[SPEncodingPopupAccessory encodingAccessory:[prefs integerForKey:SPLastSQLFileEncoding]
                                                    includeDefaultEntry:NO encodingPopUp:&encodingPopUp]];

    // it will enabled if user selects a *.sql file
    [encodingPopUp setEnabled:NO];

    [panel setAllowedFileTypes:@[SPFileExtensionDefault, SPFileExtensionSQL, SPBundleFileExtension]];

    // Check if at least one document exists, if so show a sheet
    if ([self.tabManager activeWindowController]) {

        [panel beginSheetModalForWindow:[[self.tabManager activeWindowController] window] completionHandler:^(NSInteger returnCode) {
            if (returnCode) {
                [panel orderOut:self];

                NSMutableArray *filePaths = [NSMutableArray arrayWithCapacity:[[panel URLs] count]];

                [[panel URLs] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop)
                 {
                    [filePaths addObject:[obj path]];
                }];

                [self application:NSApp openFiles:filePaths];
            }
        }];
    }
    else {
        NSInteger returnCode = [panel runModal];

        if (returnCode) {
            NSMutableArray *filePaths = [NSMutableArray arrayWithCapacity:[[panel URLs] count]];

            [[panel URLs] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop)
             {
                [filePaths addObject:[obj path]];
            }];

            [self application:NSApp openFiles:filePaths];
        }
    }

    encodingPopUp = nil;
}

/**
 * Called if user drag and drops files on Sequel Ace's dock item or double-clicked
 * at files *.spf or *.sql
 */
- (void)application:(NSApplication *)app openFiles:(NSArray *)filenames
{
    for (NSString *filePath in filenames)
    {
        NSString *fileExt = [[filePath pathExtension] lowercaseString];
        // Opens a sql file and insert its content into the Custom Query editor
        if ([fileExt isEqualToString:[SPFileExtensionSQL lowercaseString]]) {
            [self openSQLFileAtPath:filePath];
            break; // open only the first SQL file
        }
        else if ([fileExt isEqualToString:[SPFileExtensionDefault lowercaseString]]) {
            [self openConnectionFileAtPath:filePath];
        }
        else if ([fileExt isEqualToString:[SPBundleFileExtension lowercaseString]]) {
            [self openSessionBundleAtPath:filePath];
        }
        else if ([fileExt isEqualToString:[SPColorThemeFileExtension lowercaseString]]) {
            [self openColorThemeFileAtPath:filePath];
        }
        else if ([fileExt isEqualToString:[SPUserBundleFileExtension lowercaseString]] || [fileExt isEqualToString:[SPUserBundleFileExtensionV2 lowercaseString]]) {
            [SPBundleManager.shared openUserBundleAtPath:filePath];
        }
        else {
            NSBeep();
            SPLog(@"Only files with the extensions ‘%@’, ‘%@’, ‘%@’, ‘%@’, ‘%@’ or ‘%@’ are allowed.", SPFileExtensionDefault, SPBundleFileExtension, SPUserBundleFileExtensionV2, SPUserBundleFileExtension, SPColorThemeFileExtension, SPFileExtensionSQL);
        }
    }
}

- (void)openConnectionFileAtPath:(NSString *)filePath {
    SPWindowController *windowController = [self.tabManager newWindowForWindow];
    [windowController.databaseDocument setStateFromConnectionFile:filePath];
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filePath]];
}

- (void)openSQLFileAtPath:(NSString *)filePath
{
    // Check size and NSFileType
    NSDictionary *attr = [fileManager attributesOfItemAtPath:filePath error:nil];

    SPDatabaseDocument *frontDocument = [self frontDocument];

    if (attr)
    {
        NSNumber *filesize = [attr objectForKey:NSFileSize];
        NSString *filetype = [attr objectForKey:NSFileType];
        if(filetype == NSFileTypeRegular && filesize)
        {
            // Ask for confirmation if file content is larger than 1MB
            if ([filesize unsignedLongValue] > 1000000)
            {
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setAlertStyle:NSAlertStyleWarning];
                [alert setMessageText:NSLocalizedString(@"Warning",@"warning")];
                [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Do you really want to load a SQL file with %@ of data into the Query Editor?", @"message of panel asking for confirmation for loading large text into the query editor"), [NSByteCountFormatter stringWithByteSize:[filesize longLongValue]]]];
                [alert setHelpAnchor:filePath];


                // Order of buttons matters! first button has "firstButtonReturn" return value from runModal
                [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
                [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"cancel button")];

                // Show 'Import' button only if there's a connection available
                if ([self frontDocument]) {
                    [alert addButtonWithTitle:NSLocalizedString(@"Import", @"import button")];
                }

                NSUInteger returnCode = [alert runModal];
                switch (returnCode) {
                    case NSAlertSecondButtonReturn: // Cancel
                        return;
                    case NSAlertThirdButtonReturn: { // Import
                        [[frontDocument tableDumpInstance] startSQLImportProcessWithFile:filePath];
                        return;
                    }
                    default: // Ok - just proceed
                        break;
                }
            }
        }
    }

    // Attempt to open the file into a string.
    NSStringEncoding sqlEncoding;
    NSString *sqlString = nil;

    // If the user came from an openPanel use the chosen encoding
    if (encodingPopUp) {
        sqlEncoding = [[encodingPopUp selectedItem] tag];

        // Otherwise, attempt to autodetect the encoding
    }
    else {
        sqlEncoding = [fileManager detectEncodingforFileAtPath:filePath];
    }

    NSError *error = nil;

    sqlString = [NSString stringWithContentsOfFile:filePath encoding:sqlEncoding error:&error];

    if (error != nil) {
        NSAlert *errorAlert = [NSAlert alertWithError:error];
        [errorAlert runModal];

        return;
    }

    // if encodingPopUp is defined the filename comes from an openPanel and
    // the encodingPopUp contains the chosen encoding; otherwise autodetect encoding
    if (encodingPopUp) {
        [[NSUserDefaults standardUserDefaults] setInteger:[[encodingPopUp selectedItem] tag] forKey:SPLastSQLFileEncoding];
    }

    // Check if at least one document exists.  If not, open one.
    if (![self.tabManager activeWindowController]) {
        frontDocument = [self.tabManager newWindowForWindow].databaseDocument;
        [frontDocument initQueryEditorWithString:sqlString];
    }
    else {
        // Pass query to the Query editor of the current document
        [frontDocument doPerformLoadQueryService:sqlString];
    }

    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filePath]];

    [frontDocument setSqlFileURL:[NSURL fileURLWithPath:filePath]];
    [frontDocument setSqlFileEncoding:sqlEncoding];
}

- (void)openSessionBundleAtPath:(NSString *)filePath {
    NSError *error = nil;
    NSData *pData = [NSData dataWithContentsOfFile:[filePath stringByAppendingPathComponent:@"info.plist"]
                                           options:NSUncachedRead
                                             error:&error];

    NSDictionary *spfs = nil;
    if (pData && !error) {
        spfs = [NSPropertyListSerialization propertyListWithData:pData
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:&error];
    }

    if (!spfs || error) {
        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Connection data file couldn't be read. (%@)", @"error while reading connection data file"), [error localizedDescription]];
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error while reading connection data file", @"error while reading connection data file") message:message callback:nil];

        return;
    }

    if ([spfs objectForKey:@"windows"] && [[spfs objectForKey:@"windows"] isKindOfClass:[NSArray class]]) {

        // Retrieve Save Panel accessory view data for remembering them globally
        NSMutableDictionary *spfsDocData = [NSMutableDictionary dictionary];
        [spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"encrypted"] boolValue]] forKey:@"encrypted"];
        [spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"auto_connect"] boolValue]] forKey:@"auto_connect"];
        [spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"save_password"] boolValue]] forKey:@"save_password"];
        [spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"include_session"] boolValue]] forKey:@"include_session"];
        [spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"save_editor_content"] boolValue]] forKey:@"save_editor_content"];

        // Set global session properties
        [self setSpfSessionDocData:spfsDocData];

        // Loop through each defined window in reversed order to reconstruct the last active window
        for (NSDictionary *windowDictionary in [[[spfs objectForKey:@"windows"] reverseObjectEnumerator] allObjects]) {

            NSWindow *window;

            // Loop through all defined tabs / windows
            for (NSDictionary *tab in [windowDictionary objectForKey:@"tabs"]) {

                // Add new the tab or window
                SPWindowController *newWindowController = window == nil ? [self.tabManager newWindowForWindow] : [self.tabManager newWindowForTab];
                window = newWindowController.window;

                usleep(1000);

                [window setFrameFromString:[windowDictionary objectForKey:@"frame"]];

                NSString *fileName = nil;
                BOOL isBundleFile = NO;

                // If isAbsolutePath then take this path directly
                // otherwise construct the releative path for the passed spfs file
                if ([[tab objectForKey:@"isAbsolutePath"] boolValue]) {
                    fileName = [tab objectForKey:@"path"];
                } else {
                    fileName = [NSString stringWithFormat:@"%@/Contents/%@", filePath, [tab objectForKey:@"path"]];
                    isBundleFile = YES;
                }

                // Security check if file really exists
                if ([fileManager fileExistsAtPath:fileName]) {
                    [newWindowController.databaseDocument setIsSavedInBundle:isBundleFile];
                    if (![newWindowController.databaseDocument setStateFromConnectionFile:fileName]) {
                        break;
                    }
                } else {
                    SPLog(@"Bundle file “%@” does not exists", fileName);
                    NSBeep();
                }
                if ([window isMiniaturized]) {
                    [window deminiaturize:self];
                }
            }
        }
    }

    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filePath]];
}

- (void)openColorThemeFileAtPath:(NSString *)filePath {
    NSString *themePath = [fileManager applicationSupportDirectoryForSubDirectory:SPThemesSupportFolder error:nil];

    if (!themePath) return;

    if (![fileManager fileExistsAtPath:themePath isDirectory:nil]) {
        if (![fileManager createDirectoryAtPath:themePath withIntermediateDirectories:YES attributes:nil error:nil]) {
            NSBeep();
            return;
        }
    }

    NSString *newPath = [NSString stringWithFormat:@"%@/%@", themePath, [filePath lastPathComponent]];

    if (![fileManager fileExistsAtPath:newPath isDirectory:nil]) {
        if (![fileManager moveItemAtPath:filePath toPath:newPath error:nil]) {
            NSBeep();
            return;
        }
    }
    else {
        [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Error while installing color theme file", @"error while installing color theme file")] message:[NSString stringWithFormat:NSLocalizedString(@"The color theme ‘%@’ already exists.", @"the color theme ‘%@’ already exists."), [filePath lastPathComponent]] callback:nil];
        return;
    }
}


#pragma mark -
#pragma mark URL scheme handler

/**
 * sequelace://” url dispatcher
 *
 * sequelace://PROCESS_ID@command/parameter1/parameter2/...
 *    parameters has to be escaped according to RFC 1808  eg %3F for a '?'
 *
 */
- (void)handleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
    NSURL *url = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];

    if ([[url scheme] isEqualToString:@"sequelace"]) {
        [self handleEventWithURL:url];
    }
    else if([[url scheme] isEqualToString:@"mysql"]) {
        [self handleMySQLConnectWithURL:url];
    }
    else {
        NSBeep();
        SPLog(@"Error in sequelace URL scheme for URL <%@>",url);
    }
}

- (void)handleMySQLConnectWithURL:(NSURL *)url {
    if(![[url scheme] isEqualToString:@"mysql"]) {
        SPLog(@"unsupported url scheme: %@",url);
        return;
    }

    NSMutableDictionary *details = [NSMutableDictionary dictionary];

    NSValue *connect = @NO;

    if ([url query]) {
        NSArray *valid = @[@"ssh_host", @"ssh_port", @"ssh_user", @"ssh_password", @"ssh_keyLocation", @"ssh_keyLocationEnabled"];
        NSMutableArray *invalid = [NSMutableArray array];
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *queryItem in [components queryItems]) {
            if ([valid containsObject:queryItem.name]) {
                NSString *decodedQueryItem = [queryItem.value stringByRemovingPercentEncoding];
                [details setObject:decodedQueryItem forKey:queryItem.name];
            }
            else {
                [invalid addObject:queryItem.name];
            }
        }
        if ([invalid count] > 0) {
            NSBeep();
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"sequelace URL Scheme Error", @"sequelace url Scheme Error") message:[NSString stringWithFormat:@"%@:\n\n%@: %@\n\n%@: %@", NSLocalizedString(@"Error for", @"error for message"), NSLocalizedString(@"Invalid query parameters given", @"Invalid query parameters given"), [invalid componentsJoinedByString:@", "], NSLocalizedString(@"Allowed query parameters are", @"Allowed query parameters are"), [valid componentsJoinedByString:@", "]] callback:nil];
            return;
        }
    }

    if ([details objectForKey:@"ssh_host"]) {
        [details setObject:@"SPSSHTunnelConnection" forKey:@"type"];
    }
    else {
        [details setObject:@"SPTCPIPConnection" forKey:@"type"];
    }

    if ([url port]) {
        [details setObject:[url port] forKey:@"port"];
    }

    if ([url user]) {
        NSString *decodedUser = [[url user] stringByRemovingPercentEncoding];
        [details setObject:decodedUser forKey:@"user"];
    }

    if ([url password]) {
        NSString *decodedPassword = [[url password] stringByRemovingPercentEncoding];
        [details setObject:decodedPassword forKey:@"password"];
        connect = @YES;
    }

    if ([[url host] length]) {
        NSString *decodedHost = [[url host] stringByRemovingPercentEncoding];
        [details setObject:decodedHost forKey:@"host"];
    } else {
        [details setObject:@"127.0.0.1" forKey:@"host"];
    }

    NSArray *pc = [url pathComponents];
    if ([pc count] > 1) { // first object is "/"
        [details setObject:[pc objectAtIndex:1] forKey:@"database"];
    }

    SPWindowController *windowController = [self.tabManager newWindowForWindow];
    [windowController.databaseDocument setState:@{@"connection":details,@"auto_connect": connect} fromFile:NO];
}

- (void)handleEventWithURL:(NSURL*)url
{
    NSString *command = [url host];
    NSString *passedProcessID = [url user];
    NSArray *parameter;
    NSArray *pathComponents;
    if([[url absoluteString] hasSuffix:@"/"])
        pathComponents = [[[url absoluteString] substringToIndex:[[url absoluteString] length]-1] pathComponents];
    else
        pathComponents = [[url absoluteString] pathComponents];

    // remove percent encoding
    NSMutableArray *decodedPathComponents = [NSMutableArray arrayWithCapacity:pathComponents.count];
    for (NSString *component in pathComponents) {
        NSString *decoded;

        if(component.isPercentEncoded){
            decoded = component.stringByRemovingPercentEncoding;
        }
        else {
            decoded = component;
        }
        [decodedPathComponents addObject:decoded];
    }
    pathComponents = decodedPathComponents.copy;

    if([pathComponents count] > 2)
        parameter = [pathComponents subarrayWithRange:NSMakeRange(2, [pathComponents count]-2)];
    else
        parameter = @[];

    // Handle commands which don't need a connection window
    if([command isEqualToString:@"chooseItemFromList"]) {
        NSString *statusFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], (passedProcessID && [passedProcessID length]) ? passedProcessID : @""];
        NSString *resultFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], (passedProcessID && [passedProcessID length]) ? passedProcessID : @""];
        [fileManager removeItemAtPath:statusFileName error:nil];
        [fileManager removeItemAtPath:resultFileName error:nil];
        NSString *result = @"";
        NSString *status = @"0";
        if([parameter count]) {
            NSInteger idx = [SPChooseMenuItemDialog withItems:parameter atPosition:[NSEvent mouseLocation]];
            if(idx > -1) {
                result = [parameter objectAtIndex:idx];
            }
        }
        if(![status writeToFile:statusFileName atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
            NSBeep();
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"BASH Error", @"bash error") message:NSLocalizedString(@"Status file for sequelace url scheme command couldn't be written!", @"status file for sequelace url scheme command couldn't be written error message") callback:nil];
        }
        [result writeToFile:resultFileName atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    
    if ([command isEqualToString:@"LaunchFavorite"]) {
        NSString *targetBookmarkName = nil;
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *queryItem in components.queryItems) {
            if ([queryItem.name isEqualToString:@"name"]) {
                targetBookmarkName = queryItem.value;
                break;
            }
        }
        
        if (targetBookmarkName && [targetBookmarkName length]) {
            SPTreeNode *targetFavoriteNode = nil;
            SPTreeNode *favoritesTree = [SPFavoritesController sharedFavoritesController].favoritesTree;
            for (SPTreeNode *favoriteNode in [favoritesTree allChildLeafs]) {
                if ([favoriteNode.dictionaryRepresentation[SPFavoriteNameKey] isEqualToString:targetBookmarkName]) {
                    targetFavoriteNode = favoriteNode;
                    break;
                }
            }
            
            if (targetFavoriteNode) {
                SPWindowController *windowController = [self.tabManager newWindowForWindow];
                SPFavoritesOutlineView *favoritesOutlineView = windowController.databaseDocument.connectionController.favoritesOutlineView;
                [favoritesOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[favoritesOutlineView rowForItem:targetFavoriteNode]] byExtendingSelection:NO];
                [windowController.databaseDocument.connectionController initiateConnection:windowController.databaseDocument.connectionController];
                return;
            }
        }
        
        NSBeep();
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"LaunchFavorite URL Scheme Error", @"LaunchFavorite URL Scheme Error") message: [NSString stringWithFormat:@"%@ %@: “%@”", NSLocalizedString(@"The variable in the ?name= query parameter could not be matched with any of your favorites.", @"The variable in the ?name= query parameter could not be matched with any of your favorites."), NSLocalizedString(@"Variable", @"Variable"), targetBookmarkName] callback:nil];
        
        return;
    }

    if([command isEqualToString:@"SyntaxHighlighting"]) {

        BOOL isDir;

        NSString *anUUID = (passedProcessID && [passedProcessID length]) ? passedProcessID : @"";
        NSString *queryFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryInputPathHeader stringByExpandingTildeInPath], anUUID];
        NSString *resultFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], anUUID];
        NSString *metaFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultMetaPathHeader stringByExpandingTildeInPath], anUUID];
        NSString *statusFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], anUUID];

        NSError *inError = nil;
        NSString *query = [NSString stringWithContentsOfFile:queryFileName encoding:NSUTF8StringEncoding error:&inError];
        NSString *result = @"";
        NSString *status = @"0";

        if([fileManager fileExistsAtPath:queryFileName isDirectory:&isDir] && !isDir) {

            if(inError == nil && query && [query length]) {
                if([parameter count] > 0) {
                    if([[parameter lastObject] isEqualToString:@"html"])
                        result = [NSString stringWithString:[self doSQLSyntaxHighlightForString:query cssLike:NO]];
                    else if([[parameter lastObject] isEqualToString:@"htmlcss"])
                        result = [NSString stringWithString:[self doSQLSyntaxHighlightForString:query cssLike:YES]];
                }
            }
        }

        [fileManager removeItemAtPath:queryFileName error:nil];
        [fileManager removeItemAtPath:resultFileName error:nil];
        [fileManager removeItemAtPath:metaFileName error:nil];
        [fileManager removeItemAtPath:statusFileName error:nil];

        if(![result writeToFile:resultFileName atomically:YES encoding:NSUTF8StringEncoding error:nil])
            status = @"1";

        // write status file as notification that query was finished
        BOOL succeed = [status writeToFile:statusFileName atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if(!succeed) {
            NSBeep();
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"BASH Error", @"bash error") message:NSLocalizedString(@"Status file for sequelace url scheme command couldn't be written!", @"status file for sequelace url scheme command couldn't be written error message") callback:nil];
        }
        return;
    }

    NSString *activeProcessID = [[self frontDocument] processID];

    SPDatabaseDocument *processDocument = nil;

    // Try to find the SPDatabaseDocument which sent the the url scheme command
    // For speed check the front most first otherwise iterate through all
    if (passedProcessID && [passedProcessID length]) {
        if ([activeProcessID isEqualToString:passedProcessID]) {
            processDocument = [self frontDocument];
        } else {
            SPWindowController *windowController = [self.tabManager windowControllerWithDocumentWithProcessID:passedProcessID];
            if (windowController) {
                processDocument = windowController.databaseDocument;
            }
        }
    }

    // if no processDoc found and no passedProcessID was passed execute
    // command at front most doc
    if(!processDocument && !passedProcessID)
        processDocument = [self frontDocument];

    if(processDocument && command) {
        if([command isEqualToString:@"passToDoc"]) {
            NSMutableDictionary *cmdDict = [NSMutableDictionary dictionary];
            [cmdDict setObject:parameter forKey:@"parameter"];
            [cmdDict setObject:(passedProcessID)?:@"" forKey:@"id"];
            [processDocument handleSchemeCommand:cmdDict];
        } else {
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"sequelace URL Scheme Error", @"sequelace url Scheme Error") message:[NSString stringWithFormat:@"%@ “%@”:\n%@", NSLocalizedString(@"Error for", @"error for message"), [command description], NSLocalizedString(@"sequelace URL scheme command not supported.", @"sequelace URL scheme command not supported.")] callback:nil];

            // If command failed notify the file handle hand shake mechanism
            NSString *out = @"1";
            NSString *anUUID = @"";
            if(command && passedProcessID && [passedProcessID length])
                anUUID = passedProcessID;
            else
                anUUID = command;

            [out writeToFile:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], anUUID]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];

            out = @"Error";
            [out writeToFile:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], anUUID]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];

        }

        return;

    }

    if(passedProcessID && [passedProcessID length]) {
        // If command failed notify the file handle hand shake mechanism
        NSString *out = @"1";
        [out writeToFile:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], passedProcessID]
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];
        out = NSLocalizedString(@"An error for sequelace URL scheme command occurred. Probably no corresponding connection window found.", @"An error for sequelace URL scheme command occurred. Probably no corresponding connection window found.");
        [out writeToFile:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], passedProcessID]
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];

        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"sequelace URL Scheme Error", @"sequelace url Scheme Error") message:[NSString stringWithFormat:@"%@ “%@”:\n%@", NSLocalizedString(@"Error for", @"error for message"), [command description], NSLocalizedString(@"An error for sequelace URL scheme command occurred. Probably no corresponding connection window found.", @"An error for sequelace URL scheme command occurred. Probably no corresponding connection window found.")] callback:nil];

        usleep(5000);
        [fileManager removeItemAtPath:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], passedProcessID] error:nil];
        [fileManager removeItemAtPath:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], passedProcessID] error:nil];
        [fileManager removeItemAtPath:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultMetaPathHeader stringByExpandingTildeInPath], passedProcessID] error:nil];
        [fileManager removeItemAtPath:[NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryInputPathHeader stringByExpandingTildeInPath], passedProcessID] error:nil];
    } else {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"sequelace URL Scheme Error", @"sequelace url Scheme Error") message: [NSString stringWithFormat:@"%@ “%@”:\n%@", NSLocalizedString(@"Error for", @"error for message"), [command description], NSLocalizedString(@"An error occur while executing a scheme command. If the scheme command was invoked by a Bundle command, it could be that the command still runs. You can try to terminate it by pressing ⌘+. or via the Activities pane.", @"an error occur while executing a scheme command. if the scheme command was invoked by a bundle command, it could be that the command still runs. you can try to terminate it by pressing ⌘+. or via the activities pane.")] callback:nil];
    }

    if(processDocument)
        SPLog(@"process doc ID: %@\n%@", [processDocument processID], [processDocument tabTitleForTooltip]);
    else
        SPLog(@"No corresponding doc found");
    SPLog(@"param: %@", parameter);
    SPLog(@"command: %@", command);
    SPLog(@"command id: %@", passedProcessID);

}

/**
 * Return an HTML formatted string representing the passed SQL string syntax highlighted
 */
- (NSString*)doSQLSyntaxHighlightForString:(NSString*)sqlText cssLike:(BOOL)cssLike
{
    NSMutableString *sqlHTML = [[NSMutableString alloc] initWithCapacity:[sqlText length]];

    NSString *tokenColor;
    NSString *cssId;
    size_t token;
    NSRange tokenRange;

    // initialise flex
    yyuoffset = 0; yyuleng = 0;
    yy_switch_to_buffer(yy_scan_string([sqlText UTF8String]));
    BOOL skipFontTag;

    while ((token=yylex())) {
        skipFontTag = NO;
        switch (token) {
            case SPT_SINGLE_QUOTED_TEXT:
            case SPT_DOUBLE_QUOTED_TEXT:
                tokenColor = @"#A7221C";
                cssId = @"sp_sql_quoted";
                break;
            case SPT_BACKTICK_QUOTED_TEXT:
                tokenColor = @"#001892";
                cssId = @"sp_sql_backtick";
                break;
            case SPT_RESERVED_WORD:
                tokenColor = @"#0041F6";
                cssId = @"sp_sql_keyword";
                break;
            case SPT_NUMERIC:
                tokenColor = @"#67350F";
                cssId = @"sp_sql_numeric";
                break;
            case SPT_COMMENT:
                tokenColor = @"#265C10";
                cssId = @"sp_sql_comment";
                break;
            case SPT_VARIABLE:
                tokenColor = @"#6C6C6C";
                cssId = @"sp_sql_variable";
                break;
            case SPT_WHITESPACE:
                skipFontTag = YES;
                cssId = @"";
                break;
            default:
                skipFontTag = YES;
                cssId = @"";
        }

        tokenRange = NSMakeRange(yyuoffset, yyuleng);

        if(skipFontTag)
            [sqlHTML appendString:[[sqlText substringWithRange:tokenRange] HTMLEscapeString]];
        else {
            if(cssLike)
                [sqlHTML appendFormat:@"<span class=\"%@\">%@</span>", cssId, [[sqlText substringWithRange:tokenRange] HTMLEscapeString]];
            else
                [sqlHTML appendFormat:@"<font color=%@>%@</font>", tokenColor, [[sqlText substringWithRange:tokenRange] HTMLEscapeString]];
        }

    }

    // Wrap lines, and replace tabs with spaces
    [sqlHTML replaceOccurrencesOfString:@"\n" withString:@"<br>" options:NSLiteralSearch range:NSMakeRange(0, [sqlHTML length])];
    [sqlHTML replaceOccurrencesOfString:@"\t" withString:@"&nbsp;&nbsp;&nbsp;&nbsp;" options:NSLiteralSearch range:NSMakeRange(0, [sqlHTML length])];

    return (sqlHTML) ? sqlHTML : @"";
}



/**
 * Return of certain shell variables mainly for usage in JavaScript support inside the
 * HTML output window to allow to ask on run-time
 */
- (NSDictionary*)shellEnvironmentForDocument:(NSString*)docUUID {
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    if (docUUID == nil) {
        [self frontDocument];
    } else {
        SPWindowController *windowController = [self.tabManager windowControllerWithDocumentWithProcessID:docUUID];
        if (windowController) {
            [env addEntriesFromDictionary:[windowController.databaseDocument shellVariables]];
        }
    }

    id firstResponder = [[NSApp keyWindow] firstResponder];
    if([firstResponder respondsToSelector:@selector(executeBundleItemForInputField:)]) {
        BOOL selfIsQueryEditor = ([[[firstResponder class] description] isEqualToString:@"SPTextView"] && [[firstResponder delegate] respondsToSelector:@selector(currentQueryRange)]);
        NSRange currentWordRange, currentSelectionRange, currentLineRange, currentQueryRange;
        currentSelectionRange = [firstResponder selectedRange];
        currentWordRange = [firstResponder getRangeForCurrentWord];
        currentLineRange = [[firstResponder string] lineRangeForRange:NSMakeRange([firstResponder selectedRange].location, 0)];

        if(selfIsQueryEditor) {
            currentQueryRange = [(SPCustomQuery *)[firstResponder delegate] currentQueryRange];
        } else {
            currentQueryRange = currentLineRange;
        }
        if(!currentQueryRange.length)
            currentQueryRange = currentSelectionRange;

        [env setObject:SPBundleScopeInputField forKey:SPBundleShellVariableBundleScope];

        if(selfIsQueryEditor && [(SPCustomQuery *)[firstResponder delegate] currentQueryRange].length)
            [env setObject:[[firstResponder string] substringWithRange:[(SPCustomQuery *)[firstResponder delegate] currentQueryRange]] forKey:SPBundleShellVariableCurrentQuery];

        if(currentSelectionRange.length)
            [env setObject:[[firstResponder string] substringWithRange:currentSelectionRange] forKey:SPBundleShellVariableSelectedText];

        if(currentWordRange.length)
            [env setObject:[[firstResponder string] substringWithRange:currentWordRange] forKey:SPBundleShellVariableCurrentWord];

        if(currentLineRange.length)
            [env setObject:[[firstResponder string] substringWithRange:currentLineRange] forKey:SPBundleShellVariableCurrentLine];
    }
    else if([firstResponder respondsToSelector:@selector(executeBundleItemForDataTable:)]) {

        if([[firstResponder delegate] respondsToSelector:@selector(usedQuery)] && [[firstResponder delegate] usedQuery])
            [env setObject:[[firstResponder delegate] usedQuery] forKey:SPBundleShellVariableUsedQueryForTable];

        if([firstResponder numberOfSelectedRows]) {
            NSMutableArray *sel = [NSMutableArray array];
            NSIndexSet *selectedRows = [firstResponder selectedRowIndexes];
            [selectedRows enumerateIndexesUsingBlock:^(NSUInteger rowIndex, BOOL * _Nonnull stop) {
                [sel addObject:[NSString stringWithFormat:@"%ld", (long)rowIndex]];
            }];
            [env setObject:[sel componentsJoinedByString:@"\t"] forKey:SPBundleShellVariableSelectedRowIndices];
        }

        [env setObject:SPBundleScopeDataTable forKey:SPBundleShellVariableBundleScope];

    } else {
        [env setObject:SPBundleScopeGeneral forKey:SPBundleShellVariableBundleScope];
    }
    return env;
}

- (void)registerActivity:(NSDictionary*)commandDict
{
    [runningActivitiesArray addObject:commandDict];
    [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPActivitiesUpdateNotification object:nil];

    SPDatabaseDocument* frontMostDoc = [self frontDocument];
    if(frontMostDoc) {
        if([runningActivitiesArray count] || [[frontMostDoc runningActivities] count])
            [frontMostDoc performSelector:@selector(setActivityPaneHidden:) withObject:@0 afterDelay:1.0];
        else {
            [NSObject cancelPreviousPerformRequestsWithTarget:frontMostDoc
                                                     selector:@selector(setActivityPaneHidden:)
                                                       object:@0];
            [frontMostDoc setActivityPaneHidden:@1];
        }
    }

}

- (void)removeRegisteredActivity:(NSInteger)pid
{
    for(id cmd in runningActivitiesArray) {
        if([[cmd objectForKey:@"pid"] integerValue] == pid) {
            [runningActivitiesArray removeObject:cmd];
            break;
        }
    }

    [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPActivitiesUpdateNotification object:nil];

    SPDatabaseDocument* frontMostDoc = [self frontDocument];
    if(frontMostDoc) {
        if([runningActivitiesArray count] || [[frontMostDoc runningActivities] count])
            [frontMostDoc performSelector:@selector(setActivityPaneHidden:) withObject:@0 afterDelay:1.0];
        else {
            [NSObject cancelPreviousPerformRequestsWithTarget:frontMostDoc
                                                     selector:@selector(setActivityPaneHidden:)
                                                       object:@0];
            [frontMostDoc setActivityPaneHidden:@1];
        }
    }
}

- (NSArray*)runningActivities
{
    return (NSArray*)runningActivitiesArray;
}

#pragma mark -
#pragma mark IBAction methods

/**
 * Opens the about panel.
 */
- (IBAction)openAboutPanel:(id)sender
{
    if (!aboutController) {
        aboutController = [[SPAboutController alloc] init];
        aboutController.window.delegate = self;
    }

    [aboutController showWindow:self];
}

/**
 * Opens the preferences window.
 */
- (IBAction)openPreferences:(id)sender
{
    [prefsController showWindow:self];
}

#pragma mark -
#pragma mark Accessors

/**
 * Provide a method to retrieve the prefs controller
 */
- (SPPreferenceController *)preferenceController
{
    return prefsController;
}

/**
 * Retrieve the frontmost document; returns nil if not found.
 */
- (SPDatabaseDocument *)frontDocument {
    return [[self.tabManager activeWindowController] databaseDocument];
}

- (NSDictionary *)spfSessionDocData
{
    return _spfSessionDocData;
}

- (void)setSpfSessionDocData:(NSDictionary *)data {
    if (data) {
        _spfSessionDocData = [data mutableCopy];
    } else {
        _spfSessionDocData = [NSMutableDictionary new];
    }
}

#pragma mark -
#pragma mark Services menu methods

/**
 * Passes the query to the frontmost document
 */
- (void)doPerformQueryService:(NSPasteboard *)pboard userData:(NSString *)data error:(NSString **)error
{
    NSString *pboardString;

    NSArray *types = [pboard types];

    if ((![types containsObject:NSPasteboardTypeString]) || (!(pboardString = [pboard stringForType:NSPasteboardTypeString]))) {
        *error = @"Pasteboard couldn't give string.";

        return;
    }

    // Check if at least one document exists
    if (![self frontDocument]) {
        *error = @"No Documents open!";

        return;
    }

    // Pass query to front document
    [[self frontDocument] doPerformQueryService:pboardString];

    return;
}

#pragma mark -
#pragma mark Sequel Ace menu methods

/**
 * Opens website link in default browser
 */
- (IBAction)visitWebsite:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SPLOCALIZEDURL_HOMEPAGE]];
}

/**
 * Opens help link in default browser
 */
- (IBAction)visitHelpWebsite:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SPLOCALIZEDURL_DOCUMENTATION]];
}

/**
 * Opens FAQ help link in default browser
 */
- (IBAction)visitFAQWebsite:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SPLOCALIZEDURL_FAQ]];
}

/**
 * Opens the 'Keyboard Shortcuts' page in the default browser.
 */
- (IBAction)viewKeyboardShortcuts:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SPLOCALIZEDURL_KEYBOARDSHORTCUTS]];
}

#pragma mark -
#pragma mark Other methods

/**
 * Implement this method to prevent the above being called in the case of a reopen (for example, clicking
 * the dock icon) where we don't want the auto-connect to kick in.
 */
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    // Only create a new document (without auto-connect) when there are already no documents open.
    if ([self.tabManager windowControllers].count == 0) {
        [self.tabManager newWindowForWindow];
        return NO;
    }
    // Return YES to the automatic opening
    return YES;
}

/**
 * If Sequel Ace is terminating kill all running BASH scripts and release all HTML output controller.
 *
 * TODO: Remove a lot of this duplicate code.
 */
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    BOOL shouldSaveFavorites = NO;

    // removing vacuum here. See: https://www.sqlite.org/lang_vacuum.html
    // The VACUUM command may change the ROWIDs of entries in any tables that do not have an explicit INTEGER PRIMARY KEY.

    if (lastBundleBlobFilesDirectory != nil) {
        [fileManager removeItemAtPath:lastBundleBlobFilesDirectory error:nil];
    }

    // Iterate through each open window
    for (SPWindowController *windowController in [self.tabManager windowControllers]) {
        // Kill any BASH commands which are currently active
        for (NSDictionary *cmd in [windowController.databaseDocument runningActivities]) {
            NSInteger pid = [[cmd objectForKey:@"pid"] integerValue];
            NSTask *killTask = [[NSTask alloc] init];

            [killTask setLaunchPath:@"/bin/sh"];
            [killTask setArguments:[NSArray arrayWithObjects:@"-c", [NSString stringWithFormat:@"kill -9 -%ld", (long)pid], nil]];
            [killTask launch];
            [killTask waitUntilExit];
        }

        // If the connection view is active, mark the favourites for saving
        if (![windowController.databaseDocument getConnection]) {
            shouldSaveFavorites = YES;
        }
    }

    for (NSDictionary* cmd in [self runningActivities]) {
        NSInteger pid = [[cmd objectForKey:@"pid"] integerValue];
        NSTask *killTask = [[NSTask alloc] init];

        [killTask setLaunchPath:@"/bin/sh"];
        [killTask setArguments:[NSArray arrayWithObjects:@"-c", [NSString stringWithFormat:@"kill -9 -%ld", (long)pid], nil]];
        [killTask launch];
        [killTask waitUntilExit];
    }

    // this might catch some stray ssh pids, but probably not.
    NSTask *killTask = [[NSTask alloc] init];
    [killTask setLaunchPath:@"/bin/sh"];
    [killTask setArguments:@[@"-c",[NSString stringWithFormat:@"kill -9 %@", [NSString stringWithString:[sshProcessIDs componentsJoinedByString:@" "]]]]];
    [killTask launch];
    [killTask waitUntilExit];

    // If required, make sure we save any changes made to the connection outline view's state
    if (shouldSaveFavorites) {
        [[SPFavoritesController sharedFavoritesController] saveFavoritesSynchronously];
    }

    return YES;
}

#pragma mark -
#pragma mark Private API

/**
 * Copy default themes, when we start the app.
 */
- (void)_copyDefaultThemes
{
    NSError *appPathError = nil;

    NSString *defaultThemesPath = [NSString stringWithFormat:@"%@/Default Themes", NSBundle.mainBundle.sharedSupportPath];
    NSString *appSupportThemesPath = [fileManager applicationSupportDirectoryForSubDirectory:SPThemesSupportFolder createIfNotExists:YES error:&appPathError];

    // If ~/Library/Application Path/Sequel Ace/Themes couldn't be created bail
    if (appPathError != nil) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Themes Installation Error", @"themes installation error") message:[NSString stringWithFormat:NSLocalizedString(@"Couldn't create Application Support Theme folder!\nError: %@", @"Couldn't create Application Support Theme folder!\nError: %@"), [appPathError localizedDescription]] callback:nil];
        return;
    }

    NSError *error = nil;
    NSError *copyError = nil;
    NSArray *defaultThemes = [fileManager contentsOfDirectoryAtPath:defaultThemesPath error:&error];

    if (defaultThemes && [defaultThemes count] && error == nil) {
        for (NSString *defaultTheme in defaultThemes)
        {
            if (![[[defaultTheme pathExtension] lowercaseString] isEqualToString:[SPColorThemeFileExtension lowercaseString]]) continue;

            NSString *defaultThemeFullPath = [NSString stringWithFormat:@"%@/%@", defaultThemesPath, defaultTheme];
            NSString *appSupportThemeFullPath = [NSString stringWithFormat:@"%@/%@", appSupportThemesPath, defaultTheme];

            if ([fileManager fileExistsAtPath:appSupportThemeFullPath]) continue;

            [fileManager copyItemAtPath:defaultThemeFullPath toPath:appSupportThemeFullPath error:&copyError];
        }
    }

    // If Themes could not be copied, show error message
    if (copyError != nil) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Themes Installation Error", @"themes installation error") message:[NSString stringWithFormat:NSLocalizedString(@"Couldn't copy default themes to Application Support Theme folder!\nError: %@", @"Couldn't copy default themes to Application Support Theme folder!\nError: %@"), [copyError localizedDescription]] callback:nil];
        return;
    }
}

#pragma mark - SPAppleScriptSupport

/**
 * AppleScript call to get the available documents.
 */
- (NSArray *)orderedDocuments
{
    NSMutableArray *orderedDocuments = [NSMutableArray array];

    for (NSWindow *aWindow in [self orderedWindows]) {
        if ([[aWindow windowController] isMemberOfClass:[SPWindowController class]]) {
            [orderedDocuments addObject:[(SPWindowController *)[aWindow windowController] databaseDocument]];
        }
    }
    return orderedDocuments;
}

/**
 * AppleScript call to get the available windows.
 */
- (NSArray *)orderedWindows
{
    return [NSApp orderedWindows];
}

/**
 * AppleScript handler to quit Sequel Ace
 *
 * This handler is required to allow termination via the Dock or AppleScript event after activating it using AppleScript
 */
- (id)handleQuitScriptCommand:(NSScriptCommand *)command
{
    [NSApp terminate:self];

    return nil;
}

/**
 * AppleScript open handler
 *
 * This handler is required to catch the 'open' command if no argument was passed which would cause a crash.
 */
- (id)handleOpenScriptCommand:(NSScriptCommand *)command
{
    return nil;
}

/**
 * AppleScript print handler
 *
 * This handler prints the active view.
 */
- (id)handlePrintScriptCommand:(NSScriptCommand *)command
{
    SPDatabaseDocument *frontDoc = [self frontDocument];

    if (frontDoc && ![frontDoc isWorking] && ![[frontDoc connectionID] isEqualToString:@"_"]) {
        [frontDoc startPrintDocumentOperation];
    }

    return nil;
}

#pragma mark - SPWindowManagement

- (IBAction)newWindowForTab:(id)sender {
    [self.tabManager newWindowForTab];
}

/**
 * Duplicate the current connection tab
 */
- (IBAction)duplicateTab:(id)sender {

    // Get the state of the previously-frontmost document
    NSDictionary *allStateDetails = @{
        @"connection" : @YES,
        @"history"    : @YES,
        @"session"    : @YES,
        @"query"      : @YES,
        @"password"   : @YES
    };

    NSMutableDictionary *frontState = [NSMutableDictionary dictionaryWithDictionary:[self.tabManager.activeWindowController.databaseDocument stateIncludingDetails:allStateDetails]];

    // Ensure it's set to autoconnect
    [frontState setObject:@YES forKey:@"auto_connect"];

    [[NSNotificationCenter defaultCenter] postNotificationName:SPDocumentDuplicateTabNotification object:nil userInfo:frontState];
}

#pragma mark -

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self removeObserver:self forKeyPath:SPShowUpdateAvailable];
    if(SecureBookmarkManager.sharedInstance != nil) {
        [SecureBookmarkManager.sharedInstance stopAllSecurityScopedAccess];
    }

}

- (IBAction)reloadBundles:(id)sender{
    [SPBundleManager.shared reloadBundles:sender];
}

- (IBAction)openBundleEditor:(id)sender{
    [SPBundleManager.shared openBundleEditor:sender];
}

- (IBAction)bundleCommandDispatcher:(id)sender{
    [SPBundleManager.shared bundleCommandDispatcher:sender];
}

- (void)rebuildMenus{
    // === Rebuild Bundles main menu item ===

    // Get main menu "Bundles"'s submenu
    NSMenu *menu = [[[NSApp mainMenu] itemWithTag:SPMainMenuBundles] submenu];

    // Clean menu
    [menu removeAllItems];

    // Add default menu items
    NSMenuItem *anItem;
    anItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Bundle Editor", @"bundle editor menu item label") action:@selector(openBundleEditor:) keyEquivalent:@"b"];
    [anItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand|NSEventModifierFlagOption|NSEventModifierFlagControl)];
    [menu addItem:anItem];
    anItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Reload Bundles", @"reload bundles menu item label") action:@selector(reloadBundles:) keyEquivalent:@""];
    [menu addItem:anItem];

    // Bail out if no Bundle was installed
    if (!SPBundleManager.shared.foundInstalledBundles) return;

    // Add installed Bundles
    // For each scope add a submenu but not for the last one (should be General always)
    [menu addItem:[NSMenuItem separatorItem]];
    [menu setAutoenablesItems:YES];
    NSArray *scopes = @[SPBundleScopeInputField, SPBundleScopeDataTable, SPBundleScopeGeneral];
    NSArray *scopeTitles = @[
        NSLocalizedString(@"Input Field", @"input field menu item label"),
        NSLocalizedString(@"Data Table", @"data table menu item label"),
        NSLocalizedString(@"General", @"general menu item label")
    ];

    NSUInteger k = 0;
    BOOL bundleOtherThanGeneralFound = NO;
    for(NSString* scope in scopes) {

        NSArray *scopeBundleCategories = [SPBundleManager.shared bundleCategoriesForScope:scope];
        NSArray *scopeBundleItems = [SPBundleManager.shared bundleItemsForScope:scope];

        if(![scopeBundleItems count]) {
            k++;
            continue;
        }

        NSMenu *bundleMenu = nil;
        NSMenuItem *bundleSubMenuItem = nil;

        // Add last scope (General) not as submenu
        if(k < [scopes count]-1) {
            bundleMenu = [[NSMenu alloc] init];
            [bundleMenu setAutoenablesItems:YES];
            bundleSubMenuItem = [[NSMenuItem alloc] initWithTitle:[scopeTitles objectAtIndex:k] action:nil keyEquivalent:@""];
            [bundleSubMenuItem setTag:10000000];

            [menu addItem:bundleSubMenuItem];
            [menu setSubmenu:bundleMenu forItem:bundleSubMenuItem];

        } else {
            bundleMenu = menu;
            if(bundleOtherThanGeneralFound)
                [menu addItem:[NSMenuItem separatorItem]];
        }

        // Add found Category submenus
        NSMutableArray *categorySubMenus = [NSMutableArray array];
        NSMutableArray *categoryMenus = [NSMutableArray array];
        if([scopeBundleCategories count]) {
            for(NSString* title in scopeBundleCategories) {
                [categorySubMenus addObject:[[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""]];
                [categoryMenus addObject:[[NSMenu alloc] init]];
                [bundleMenu addItem:[categorySubMenus lastObject]];
                [bundleMenu setSubmenu:[categoryMenus lastObject] forItem:[categorySubMenus lastObject]];
            }
        }

        NSInteger i = 0;
        for(NSDictionary *item in scopeBundleItems) {

            NSString *keyEq;
            if([item objectForKey:SPBundleFileKeyEquivalentKey])
                keyEq = [[item objectForKey:SPBundleFileKeyEquivalentKey] objectAtIndex:0];
            else
                keyEq = @"";

            NSMenuItem *mItem = [[NSMenuItem alloc] initWithTitle:[item objectForKey:SPBundleInternLabelKey] action:@selector(bundleCommandDispatcher:) keyEquivalent:keyEq];
            bundleOtherThanGeneralFound = YES;
            if([keyEq length])
                [mItem setKeyEquivalentModifierMask:[[[item objectForKey:SPBundleFileKeyEquivalentKey] objectAtIndex:1] intValue]];

            if([item objectForKey:SPBundleFileTooltipKey])
                [mItem setToolTip:[item objectForKey:SPBundleFileTooltipKey]];

            [mItem setTag:1000000 + i++];
            [mItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                         scope, @"scope",
                                         ([item objectForKey:@"key"])?:@"", @"key", nil]];

            if([item objectForKey:SPBundleFileCategoryKey]) {
                [[categoryMenus objectAtIndex:[scopeBundleCategories indexOfObject:[item objectForKey:SPBundleFileCategoryKey]]] addItem:mItem];
            } else {
                [bundleMenu addItem:mItem];
            }
        }

        k++;
    }
}

@end
