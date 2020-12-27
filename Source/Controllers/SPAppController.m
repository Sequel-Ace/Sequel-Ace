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
#import "SPWindowController.h"
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
#import "PSMTabBarControl.h"
#import "SPFunctions.h"
#import "SPBundleManager.h"

#import "sequel-ace-Swift.h"

@interface SPAppController ()

- (void)_copyDefaultThemes;

- (void)openConnectionFileAtPath:(NSString *)filePath;
- (void)openSQLFileAtPath:(NSString *)filePath;
- (void)openSessionBundleAtPath:(NSString *)filePath;
- (void)openColorThemeFileAtPath:(NSString *)filePath;

@property (readwrite, strong) NSFileManager *fileManager;
@property (readwrite, strong) SPBundleManager *sharedSPBundleManager;

@end

@implementation SPAppController

@synthesize lastBundleBlobFilesDirectory;
@synthesize fileManager;
@synthesize sharedSPBundleManager;

#pragma mark -
#pragma mark Initialisation

/**
 * Initialise the application's main controller, setting itself as the app delegate.
 */
- (instancetype)init
{
	if ((self = [super init])) {
		_sessionURL = nil;
		aboutController = nil;
		lastBundleBlobFilesDirectory = nil;
		_spfSessionDocData = [[NSMutableDictionary alloc] init];

		runningActivitiesArray = [[NSMutableArray alloc] init];
		fileManager = [NSFileManager defaultManager];

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

	if ([prefs objectForKey:@"GlobalResultTableFont"]) {
		NSFont *tableFont = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:@"GlobalResultTableFont"]];
		if (tableFont) {
			[NSUserDefaults saveFont:tableFont];
		}
		[prefs removeObjectForKey:@"GlobalResultTableFont"];
	}

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

	// Register for drag start notifications - used to bring all windows to front
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tabDragStarted:) name:PSMTabDragDidBeginNotification object:nil];

}

/**
 * Initialisation stuff after launch is complete
 */
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	
	[FIRApp configure]; // default options read from Google service plist
	
#ifdef DEBUG
	// default is FIRLoggerLevelNotice, and for App Store apps
	// cannot be set higher than FIRLoggerLevelNotice
	[[FIRConfiguration sharedInstance] setLoggerLevel:FIRLoggerLevelDebug];
#endif
	
	
	// init SQLite query history	
	SQLiteHistoryManager __unused *sqliteHistoryManager = SQLiteHistoryManager.sharedInstance;

	sharedSPBundleManager = SPBundleManager.sharedSPBundleManager;

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
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        FIRCrashlytics *crashlytics = FIRCrashlytics.crashlytics;

        // set some keys to help us diagnose issues
        [crashlytics setCustomValue:@(user_defaults_get_bool_ud(SPCustomQueryAutoComplete, prefs)) forKey:@"CustomQueryAutoComplete"];
        [crashlytics setCustomValue:@(user_defaults_get_bool_ud(SPCustomQueryEnableSyntaxHighlighting, prefs)) forKey:@"CustomQueryEnableSyntaxHighlighting"];
        [crashlytics setCustomValue:@(user_defaults_get_bool_ud(SPCustomQueryAutoIndent, prefs)) forKey:@"CustomQueryAutoIndent"];
        [crashlytics setCustomValue:@(user_defaults_get_bool_ud(SPCustomQueryAutoUppercaseKeywords, prefs)) forKey:@"CustomQueryAutoUppercaseKeywords"];
        [crashlytics setCustomValue:@(user_defaults_get_bool_ud(SPCustomQueryEnableBracketHighlighting, prefs)) forKey:@"CustomQueryEnableBracketHighlighting"];
        [crashlytics setCustomValue:@(user_defaults_get_bool_ud(SPCustomQueryEditorCompleteWithBackticks, prefs)) forKey:@"CustomQueryEditorCompleteWithBackticks"];
        [crashlytics setCustomValue:[[NSLocale currentLocale] localeIdentifier] forKey:@"localeIdentifier"];
        [crashlytics setCustomValue:[[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode] forKey:@"localeLanguageCode"];
    });


    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(externalApplicationWantsToOpenADatabaseConnection:) name:@"ExternalApplicationWantsToOpenADatabaseConnection" object:nil];

	[sharedSPBundleManager reloadBundles:self];
    [self _copyDefaultThemes];

	// If no documents are open, open one
	if (![self frontDocument]) {
		SPDatabaseDocument *newConnection = [self makeNewConnectionTabOrWindow];

		if (spfDict) {
			[newConnection setState:spfDict];
		}

		// Set autoconnection if appropriate
		if ([[NSUserDefaults standardUserDefaults] boolForKey:SPAutoConnectToDefault]) {
			[newConnection connect];
		}
	}
}

- (void)externalApplicationWantsToOpenADatabaseConnection:(NSNotification *)notification
{
	NSDictionary *userInfo = [notification userInfo];
	NSString *MAMP_SPFVersion = [userInfo objectForKey:@"dataVersion"];
	if ([MAMP_SPFVersion isEqualToString:@"1"]) {
		NSDictionary *spfStructure = [userInfo objectForKey:@"spfData"];
		if (spfStructure) {
			SPDatabaseDocument *frontDoc = [self makeNewConnectionTabOrWindow];
			[frontDoc setState:spfStructure];
		}
	}
}

/**
 * Menu item validation.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if ([menuItem action] == @selector(openCurrentConnectionInNewWindow:))
	{
		[menuItem setTitle:NSLocalizedString(@"Open in New Window", @"menu item open in new window")];

		return NO;
	}

	if ([menuItem action] == @selector(newTab:))
	{
		return ([[self frontDocumentWindow] attachedSheet] == nil);
	}

	if ([menuItem action] == @selector(duplicateTab:))
	{
		return ([[self frontDocument] getConnection] != nil);
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
	if ([self frontDocumentWindow]) {

		[panel beginSheetModalForWindow:[self frontDocumentWindow] completionHandler:^(NSInteger returnCode) {
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
			[sharedSPBundleManager openUserBundleAtPath:filePath];
		}
		else {
			NSBeep();
			SPLog(@"Only files with the extensions ‘%@’, ‘%@’, ‘%@’, ‘%@’, ‘%@’ or ‘%@’ are allowed.", SPFileExtensionDefault, SPBundleFileExtension, SPUserBundleFileExtensionV2, SPUserBundleFileExtension, SPColorThemeFileExtension, SPFileExtensionSQL);
		}
	}
}

- (void)openConnectionFileAtPath:(NSString *)filePath
{
	SPDatabaseDocument *frontDocument = [self makeNewConnectionTabOrWindow];

	[frontDocument setStateFromConnectionFile:filePath];

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
				[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Do you really want to load a SQL file with %@ of data into the Query Editor?", @"message of panel asking for confirmation for loading large text into the query editor"), [NSString stringForByteSize:[filesize longLongValue]]]];
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
	if (!frontDocument) {
		frontDocument = [self makeNewConnectionTabOrWindow];
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

- (void)openSessionBundleAtPath:(NSString *)filePath
{
	NSDictionary *spfs = nil;
	{
		NSError *error = nil;

		NSData *pData = [NSData dataWithContentsOfFile:[filePath stringByAppendingPathComponent:@"info.plist"]
											   options:NSUncachedRead
												 error:&error];

		if(pData && !error) {
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
	}

	if([spfs objectForKey:@"windows"] && [[spfs objectForKey:@"windows"] isKindOfClass:[NSArray class]]) {

		// Retrieve Save Panel accessory view data for remembering them globally
		NSMutableDictionary *spfsDocData = [NSMutableDictionary dictionary];
		[spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"encrypted"] boolValue]] forKey:@"encrypted"];
		[spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"auto_connect"] boolValue]] forKey:@"auto_connect"];
		[spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"save_password"] boolValue]] forKey:@"save_password"];
		[spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"include_session"] boolValue]] forKey:@"include_session"];
		[spfsDocData setObject:[NSNumber numberWithBool:[[spfs objectForKey:@"save_editor_content"] boolValue]] forKey:@"save_editor_content"];

		// Set global session properties
		[SPAppDelegate setSpfSessionDocData:spfsDocData];
		[SPAppDelegate setSessionURL:filePath];

		// Loop through each defined window in reversed order to reconstruct the last active window
		for (NSDictionary *window in [[[spfs objectForKey:@"windows"] reverseObjectEnumerator] allObjects])
		{
			// Create a new window controller, and set up a new connection view within it.
			SPWindowController *newWindowController = [[SPWindowController alloc] initWithWindowNibName:@"MainWindow"];
			NSWindow *newWindow = [newWindowController window];

			// If window has more than 1 tab then set setHideForSingleTab to NO
			// in order to avoid animation problems while opening tabs
			if([[window objectForKey:@"tabs"] count] > 1)
				[newWindowController setHideForSingleTab:NO];

			// The first window should use autosaving; subsequent windows should cascade.
			// So attempt to set the frame autosave name; this will succeed for the very
			// first window, and fail for others.
			BOOL usedAutosave = [newWindow setFrameAutosaveName:@"DBView"];

			if (!usedAutosave) {
				[newWindow setFrameUsingName:@"DBView"];
			}

			if ([window objectForKey:@"frame"])
			{
				[newWindow setFrame:NSRectFromString([window objectForKey:@"frame"]) display:NO];
			}

			// Set the window controller as the window's delegate
			[newWindow setDelegate:newWindowController];

			usleep(1000);

			// Show the window
			[newWindowController showWindow:self];

			// Loop through all defined tabs for each window
			for (NSDictionary *tab in [window objectForKey:@"tabs"])
			{
				NSString *fileName = nil;
				BOOL isBundleFile = NO;

				// If isAbsolutePath then take this path directly
				// otherwise construct the releative path for the passed spfs file
				if ([[tab objectForKey:@"isAbsolutePath"] boolValue]) {
					fileName = [tab objectForKey:@"path"];
				}
				else {
					fileName = [NSString stringWithFormat:@"%@/Contents/%@", filePath, [tab objectForKey:@"path"]];
					isBundleFile = YES;
				}

				// Security check if file really exists
				if ([fileManager fileExistsAtPath:fileName]) {

					// Add new the tab
					if(newWindowController) {

						if ([[newWindowController window] isMiniaturized]) [[newWindowController window] deminiaturize:self];
						SPDatabaseDocument *newConnection = [newWindowController addNewConnection];

						[newConnection setIsSavedInBundle:isBundleFile];
						if (![newConnection setStateFromConnectionFile:fileName]) {
							break;
						}
					}

				}
				else {
					SPLog(@"Bundle file “%@” does not exists", fileName);
					NSBeep();
				}
			}

			// Select active tab
			[newWindowController selectTabAtIndex:[[window objectForKey:@"selectedTabIndex"] intValue]];

			// Reset setHideForSingleTab
			if ([[NSUserDefaults standardUserDefaults] objectForKey:SPAlwaysShowWindowTabBar]) {
				[newWindowController setHideForSingleTab:[[NSUserDefaults standardUserDefaults] boolForKey:SPAlwaysShowWindowTabBar]];
			}
			else {
				[newWindowController setHideForSingleTab:YES];
			}
		}
	}

	[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filePath]];
}

- (void)openColorThemeFileAtPath:(NSString *)filePath
{
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

- (void)handleMySQLConnectWithURL:(NSURL *)url
{
	if(![[url scheme] isEqualToString:@"mysql"]) {
		SPLog(@"unsupported url scheme: %@",url);
		return;
	}

	// make connection window
	SPDatabaseDocument *doc = [self makeNewConnectionTabOrWindow];

	NSMutableDictionary *details = [NSMutableDictionary dictionary];

	NSValue *connect = @NO;

	[details setObject:@"SPTCPIPConnection" forKey:@"type"];
	if([url port])
		[details setObject:[url port] forKey:@"port"];

	if([url user])
		[details setObject:[url user] forKey:@"user"];

	if([url password]) {
		[details setObject:[url password] forKey:@"password"];
		connect = @YES;
	}

	if([[url host] length] && ![[url host] isEqualToString:@"localhost"])
		[details setObject:[url host] forKey:@"host"];
	else
		[details setObject:@"127.0.0.1" forKey:@"host"];

	NSArray *pc = [url pathComponents];
	if([pc count] > 1) // first object is "/"
		[details setObject:[pc objectAtIndex:1] forKey:@"database"];

	[doc setState:@{@"connection":details,@"auto_connect": connect} fromFile:NO];
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
	if(passedProcessID && [passedProcessID length]) {
		if([activeProcessID isEqualToString:passedProcessID]) {
			processDocument = [self frontDocument];
		} else {
			for (NSWindow *aWindow in [self orderedDatabaseConnectionWindows]) {
				for(SPDatabaseDocument *doc in [[aWindow windowController] documents]) {
					if([doc processID] && [[doc processID] isEqualToString:passedProcessID]) {
						processDocument = doc;
						goto break_loop;
					}
				}
			}
			break_loop: /* breaking two levels of foreach */;
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
- (NSDictionary*)shellEnvironmentForDocument:(NSString*)docUUID
{
	NSMutableDictionary *env = [NSMutableDictionary dictionary];
	SPDatabaseDocument *doc;
	if(docUUID == nil)
		doc = [self frontDocument];
	else {
		for (NSWindow *aWindow in [self orderedDatabaseConnectionWindows]) {
			for(SPDatabaseDocument *d in [[aWindow windowController] documents]) {
				if([d processID] && [[d processID] isEqualToString:docUUID]) {
					[env addEntriesFromDictionary:[d shellVariables]];
					goto break_loop;
				}
			}
		}
		break_loop: /* breaking two levels of foreach */;
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
 * Provide a method to retrieve an ordered list of the database
 * connection windows currently open in the application.
 */
- (NSArray *) orderedDatabaseConnectionWindows
{
	NSMutableArray *orderedDatabaseConnectionWindows = [NSMutableArray array];
	for (NSWindow *aWindow in [NSApp orderedWindows]) {
		if ([[aWindow windowController] isMemberOfClass:[SPWindowController class]]) [orderedDatabaseConnectionWindows addObject:aWindow];
	}
	return orderedDatabaseConnectionWindows;
}

/**
 * Retrieve the frontmost document; returns nil if not found.
 */
- (SPDatabaseDocument *) frontDocument
{
	return [[self frontController] selectedTableDocument];
}

/**
 * Retrieve the session URL. Return nil if no session is opened
 */
- (NSURL *)sessionURL
{
	return _sessionURL;
}

/**
 * Set the global session URL used for Save (As) Session.
 */
- (void)setSessionURL:(NSString *)urlString
{
	
	if(urlString)
		_sessionURL = [NSURL fileURLWithPath:urlString];
}

- (NSDictionary *)spfSessionDocData
{
	return _spfSessionDocData;
}

- (void)setSpfSessionDocData:(NSDictionary *)data
{
	[_spfSessionDocData removeAllObjects];
	if(data)
		[_spfSessionDocData addEntriesFromDictionary:data];
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

	if ((![types containsObject:NSStringPboardType]) || (!(pboardString = [pboard stringForType:NSStringPboardType]))) {
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
	if (![self frontDocument]) {
		[self newWindow:self];
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

	[SQLiteHistoryManager.sharedInstance execSQLiteVacuum];
	
	if (lastBundleBlobFilesDirectory != nil) {
		[fileManager removeItemAtPath:lastBundleBlobFilesDirectory error:nil];
	}

	// Iterate through each open window
	for (NSWindow *aWindow in [self orderedDatabaseConnectionWindows])
	{
		// Iterate through each document in the window
		for (SPDatabaseDocument *doc in [[aWindow windowController] documents])
		{
			// Kill any BASH commands which are currently active
			for (NSDictionary* cmd in [doc runningActivities])
			{
				NSInteger pid = [[cmd objectForKey:@"pid"] integerValue];
				NSTask *killTask = [[NSTask alloc] init];

				[killTask setLaunchPath:@"/bin/sh"];
				[killTask setArguments:[NSArray arrayWithObjects:@"-c", [NSString stringWithFormat:@"kill -9 -%ld", (long)pid], nil]];
				[killTask launch];
				[killTask waitUntilExit];
			}

			// If the connection view is active, mark the favourites for saving
			if (![doc getConnection]) {
				shouldSaveFavorites = YES;
			}
		}
	}

	for (NSDictionary* cmd in [self runningActivities])
	{
		NSInteger pid = [[cmd objectForKey:@"pid"] integerValue];
		NSTask *killTask = [[NSTask alloc] init];

		[killTask setLaunchPath:@"/bin/sh"];
		[killTask setArguments:[NSArray arrayWithObjects:@"-c", [NSString stringWithFormat:@"kill -9 -%ld", (long)pid], nil]];
		[killTask launch];
		[killTask waitUntilExit];
	}

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

	for (NSWindow *aWindow in [self orderedWindows])
	{
		if ([[aWindow windowController] isMemberOfClass:[SPWindowController class]]) {
			[orderedDocuments addObjectsFromArray:[[aWindow windowController] documents]];
		}
	}

	return orderedDocuments;
}

/**
 * AppleScript support for 'make new document'.
 *
 * TODO: following tab support this has been disabled - need to discuss reimplmenting vs syntax.
 */
- (void)insertInOrderedDocuments:(SPDatabaseDocument *)doc
{
	[self newWindow:self];

	// Set autoconnection if appropriate
	if ([[NSUserDefaults standardUserDefaults] boolForKey:SPAutoConnectToDefault]) {
		[[self frontDocument] connect];
	}
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

- (IBAction)newWindow:(id)sender
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self newWindow];
	});
}

/**
 * Create a new window, containing a single tab.
 */
- (SPWindowController *)newWindow
{
	static NSPoint cascadeLocation = {.x = 0, .y = 0};

	// Create a new window controller, and set up a new connection view within it.
	SPWindowController *newWindowController = [[SPWindowController alloc] initWithWindowNibName:@"MainWindow"];
	NSWindow *newWindow = [newWindowController window];

	// Cascading defaults to on - retrieve the window origin automatically assigned by cascading,
	// and convert to a top left point.
	NSPoint topLeftPoint = [newWindow frame].origin;
	topLeftPoint.y += [newWindow frame].size.height;

	// The first window should use autosaving; subsequent windows should cascade.
	// So attempt to set the frame autosave name; this will succeed for the very
	// first window, and fail for others.
	BOOL usedAutosave = [newWindow setFrameAutosaveName:@"DBView"];

	if (!usedAutosave) {
		[newWindow setFrameUsingName:@"DBView"];
	}

	// Add the connection view
	[newWindowController addNewConnection];

	// Cascade according to the statically stored cascade location.
	cascadeLocation = [newWindow cascadeTopLeftFromPoint:cascadeLocation];

	// Set the window controller as the window's delegate
	[newWindow setDelegate:newWindowController];

	// Show the window, and perform frontmost tasks again once the window has drawn
	[newWindowController showWindow:self];
	[[newWindowController selectedTableDocument] didBecomeActiveTabInWindow];

	return newWindowController;
}

/**
 * Create a new tab in the frontmost window.
 */
- (IBAction)newTab:(id)sender
{
	SPWindowController *frontController = [self frontController];

	// If no window was found, create a new one
	if (!frontController) {
		[self newWindow:self];
	}
	else {
		if ([[frontController window] isMiniaturized]) {
			[[frontController window] deminiaturize:self];
		}

		[frontController addNewConnection:self];
	}
}

- (SPDatabaseDocument *)makeNewConnectionTabOrWindow
{
	SPWindowController *frontController = [self frontController];

	SPDatabaseDocument *frontDocument;
	// If no window was found or the front most window has no tabs, create a new one
	if (!frontController || [[frontController valueForKeyPath:@"tabView"] numberOfTabViewItems] == 1) {
		frontController = [self newWindow];
		frontDocument = [frontController selectedTableDocument];
	}
	// Open the spf file in a new tab if the tab bar is visible
	else {
		if ([[frontController window] isMiniaturized]) [[frontController window] deminiaturize:self];
		frontDocument = [frontController addNewConnection];
	}

	return frontDocument;
}

/**
 * Duplicate the current connection tab
 */
- (IBAction)duplicateTab:(id)sender
{
	SPDatabaseDocument *theFrontDocument = [self frontDocument];

	if (!theFrontDocument) return [self newTab:sender];

	// Add a new tab to the window
	if ([[self frontDocumentWindow] isMiniaturized]) {
		[[self frontDocumentWindow] deminiaturize:self];
	}

	SPDatabaseDocument *newConnection = [[self frontController] addNewConnection];

	// Get the state of the previously-frontmost document
	NSDictionary *allStateDetails = @{
									  @"connection" : @YES,
									  @"history"    : @YES,
									  @"session"    : @YES,
									  @"query"      : @YES,
									  @"password"   : @YES
									  };

	NSMutableDictionary *frontState = [NSMutableDictionary dictionaryWithDictionary:[theFrontDocument stateIncludingDetails:allStateDetails]];

	// Ensure it's set to autoconnect
	[frontState setObject:@YES forKey:@"auto_connect"];

	// Set the connection on the new tab
	[newConnection setState:frontState];
}

/**
 * Retrieve the frontmost document window; returns nil if not found.
 */
- (NSWindow *)frontDocumentWindow
{
	return [[self frontController] window];
}

- (SPWindowController *)frontController
{
	for (NSWindow *aWindow in [NSApp orderedWindows]) {
		id ctr = [aWindow windowController];
		if ([ctr isMemberOfClass:[SPWindowController class]]) {
			return ctr;
		}
	}
	return nil;
}

/**
 * When tab drags start, bring all the windows in front of other applications.
 */
- (void)tabDragStarted:(id)sender
{
	[NSApp arrangeInFront:self];
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
	id window = notification.object;
	if (!window) { return; }

	if (window == aboutController.window) {
		aboutController.window.delegate = nil;
	}
}

#pragma mark -

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

}

- (IBAction)reloadBundles:(id)sender{
	[SPBundleManager.sharedSPBundleManager reloadBundles:sender];
}

- (IBAction)openBundleEditor:(id)sender{
	[SPBundleManager.sharedSPBundleManager openBundleEditor:sender];
}

- (IBAction)bundleCommandDispatcher:(id)sender{
	[SPBundleManager.sharedSPBundleManager bundleCommandDispatcher:sender];
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
	if (!SPBundleManager.sharedSPBundleManager.foundInstalledBundles) return;

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

		NSArray *scopeBundleCategories = [SPBundleManager.sharedSPBundleManager bundleCategoriesForScope:scope];
		NSArray *scopeBundleItems = [SPBundleManager.sharedSPBundleManager bundleItemsForScope:scope];

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
