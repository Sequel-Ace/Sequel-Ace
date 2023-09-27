//
//  SPQueryController.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on Jan 30, 2009
//  Copyright (c) 2009 Stuart Connolly. All rights reserved.
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

#import "SPQueryController.h"
#import "SPConsoleMessage.h"
#import "SPAppController.h"
#import "SPFunctions.h"
#import "pthread.h"
#import "SPCopyTable.h"
#import "SPDatabaseDocument.h"

@import FMDB;

#import "sequel-ace-Swift.h"

NSString *SPQueryConsoleWindowAutoSaveName = @"QueryConsole";
NSString *SPTableViewDateColumnID          = @"messageDate";
NSString *SPTableViewConnectionColumnID    = @"messageConnection";
NSString *SPTableViewDatabaseColumnID      = @"messageDatabase";

static NSString *SPCompletionTokensFilename     = @"CompletionTokens.plist";

static NSString *SPCompletionTokensKeywordsKey  = @"core_keywords";
static NSString *SPCompletionTokensFunctionsKey = @"core_builtin_functions";
static NSString *SPCompletionTokensSnippetsKey  = @"function_argument_snippets";

static NSUInteger SPMessageTruncateCharacterLength = 256;

@interface SPQueryController ()

- (void)_updateFilterState;
- (void)_allowFilterClearOrSave:(NSNumber *)enabled;
- (BOOL)_messageMatchesCurrentFilters:(NSString *)message;
- (NSString *)_getConsoleStringWithTimeStamps:(BOOL)timeStamps connections:(BOOL)connections databases:(BOOL)databases;
- (void)_addMessageToConsole:(NSString *)message connection:(NSString *)connection isError:(BOOL)error database:(NSString *)database;

@property (readwrite, strong) SQLiteHistoryManager *_SQLiteHistoryManager ;


@end

static SPQueryController *sharedQueryController = nil;

@implementation SPQueryController

@synthesize consoleFont, _SQLiteHistoryManager;

/**
 * Returns the shared query console.
 */
+ (SPQueryController *)sharedQueryController
{
	static dispatch_once_t onceToken;
	
	if (sharedQueryController == nil) {
		dispatch_once_on_main_thread(&onceToken, ^{
			sharedQueryController = [[SPQueryController alloc] init];
		});
	}

	return sharedQueryController;
}

- (instancetype)init
{
		
	if ((self = [super initWithWindowNibName:@"Console"])) {
		messagesFullSet		= [[NSMutableArray alloc] init];
		messagesFilteredSet	= [[NSMutableArray alloc] init];

		showSelectStatementsAreDisabled = NO;
		showHelpStatementsAreDisabled = NO;
		filterIsActive = NO;
		activeFilterString = [[NSMutableString alloc] init];

		// Weak reference to active messages set - starts off as full set
		messagesVisibleSet = messagesFullSet;

		untitledDocumentCounter = 1;
		numberOfMaxAllowedHistory = 100;
		allowConsoleUpdate = YES;

		favoritesContainer = [[NSMutableDictionary alloc] init];
		historyContainer = [[NSMutableDictionary alloc] init];
		contentFilterContainer = [[NSMutableDictionary alloc] init];
		completionKeywordList = nil;
		completionFunctionList = nil;
		functionArgumentSnippets = nil;
		
		_SQLiteHistoryManager = SQLiteHistoryManager.sharedInstance;
		
		pthread_mutex_init(&consoleLock, NULL);

		NSError *error = [self loadCompletionLists];

		// Trigger a load of the nib to prevent problems if it's lazy-loaded on first console message
		// on a bckground thread
		[[[self onMainThread] window] displayIfNeeded];

		if (error) {
			NSLog(@"Error loading completion tokens data: %@", [error localizedDescription]); 
		}
	
		return self;
	}
	else{
		return nil;;
	}
}

/**
 * The following base protocol methods are implemented to ensure the singleton status of this class.
 */

- (id)copyWithZone:(NSZone *)zone { return self; }

#pragma mark -
#pragma mark QueryConsoleController

/**
 * Copy implementation for console table view.
 */
- (void)copy:(id)sender
{
    if (([consoleTableView numberOfSelectedRows] > 0 || [consoleTableView clickedRow] > -1)) {
        NSIndexSet *rows = [consoleTableView selectedRowIndexes];
        if([consoleTableView clickedRow] > -1 && ![rows containsIndex:[consoleTableView clickedRow]]) {
            rows = [NSIndexSet indexSetWithIndex:[consoleTableView clickedRow]];
        }


        BOOL includeTimestamps  = ![[consoleTableView tableColumnWithIdentifier:SPTableViewDateColumnID] isHidden];
        BOOL includeConnections = ![[consoleTableView tableColumnWithIdentifier:SPTableViewConnectionColumnID] isHidden];
        BOOL includeDatabases   = ![[consoleTableView tableColumnWithIdentifier:SPTableViewDatabaseColumnID] isHidden];
        NSString *string = [self infoStringForRowIndexes:rows includeTimestamps:includeTimestamps includeConnections:includeConnections includeDatabases:includeDatabases];

        NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];

        // Copy the string to the pasteboard
        [pasteBoard declareTypes:@[NSPasteboardTypeString] owner:self];
        [pasteBoard setString:string forType:NSPasteboardTypeString];
    }
}

/**
 * Copy implementation for console table view.
 */
- (void)copyQueryOnly:(id)sender
{
    if (([consoleTableView numberOfSelectedRows] > 0 || [consoleTableView clickedRow] > -1)) {
        NSIndexSet *rows = [consoleTableView selectedRowIndexes];
        if([consoleTableView clickedRow] > -1 && ![rows containsIndex:[consoleTableView clickedRow]]) {
            rows = [NSIndexSet indexSetWithIndex:[consoleTableView clickedRow]];
        }

        NSString *string = [self infoStringForRowIndexes:rows includeTimestamps:NO includeConnections:NO includeDatabases:NO];

        NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];

        // Copy the string to the pasteboard
        [pasteBoard declareTypes:@[NSPasteboardTypeString] owner:self];
        [pasteBoard setString:string forType:NSPasteboardTypeString];
    }
}

- (NSString *)infoStringForRowIndexes:(NSIndexSet *)rows includeTimestamps:(BOOL)includeTimestamps includeConnections:(BOOL)includeConnections includeDatabases:(BOOL)includeDatabases
{
    if(![rows count]) return @"";

    NSMutableString *string = [[NSMutableString alloc] init];

    [rows enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * _Nonnull stop) {
        if (i < [messagesVisibleSet count]) {
            SPConsoleMessage *message = [messagesVisibleSet safeObjectAtIndex:i];

            if (includeTimestamps || includeConnections || includeDatabases) [string appendString:@"/* "];

            NSDate *date = [message messageDate];
            if (includeTimestamps && date) {
                [string appendString:[dateFormatter stringFromDate:date]];
                [string appendString:@" "];
            }

            NSString *connection = [message messageConnection];
            if (includeConnections && connection) {
                [string appendString:connection];
                [string appendString:@" "];
            }

            NSString *database = [message messageDatabase];
            if (includeDatabases && database) {
                [string appendString:database];
                [string appendString:@" "];
            }

            if (includeTimestamps || includeConnections || includeDatabases) [string appendString:@"*/ "];

            [string appendString:[message message]];
            [string appendString:@"\n"];
        }
    }];

    return string;
}

/**
 * Clears the console by removing all of its messages.
 */
- (IBAction)clearConsole:(id)sender {
	[messagesFullSet removeAllObjects];
	[messagesFilteredSet removeAllObjects];

	[consoleTableView reloadData];
}

/**
 * Presents the user with a save panel to the save the current console to a log file.
 */
- (IBAction)saveConsoleAs:(id)sender
{
	NSSavePanel *panel = [NSSavePanel savePanel];

	[panel setAllowedFileTypes:@[SPFileExtensionSQL]];

	[panel setExtensionHidden:NO];
	[panel setAllowsOtherFileTypes:YES];
	[panel setCanSelectHiddenExtension:YES];

	[panel setAccessoryView:saveLogView];

    [panel setNameFieldStringValue:NSLocalizedString(@"ConsoleLog", @"Console : Save as : Initial filename")];

    [panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger returnCode) {
        if (returnCode == NSModalResponseOK) {
            [[self _getConsoleStringWithTimeStamps:[self->includeTimeStampsButton state]
                                       connections:[self->includeConnectionButton state]
										 databases:[self->includeDatabaseButton state]] writeToFile:[[panel URL] path] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
    }];
}

/**
 * Toggles the display of the message time stamp column in the table view.
 */
- (IBAction)toggleShowTimeStamps:(id)sender
{
	[[consoleTableView tableColumnWithIdentifier:SPTableViewDateColumnID] setHidden:[(NSMenuItem*)sender state]];
}

/**
 * Toggles the display of the message connections column in the table view.
 */
- (IBAction)toggleShowConnections:(id)sender
{
	[[consoleTableView tableColumnWithIdentifier:SPTableViewConnectionColumnID] setHidden:[(NSMenuItem*)sender state]];
}

/**
 * Toggles the display of the message databases column in the table view.
 */
- (IBAction)toggleShowDatabases:(id)sender
{
	[[consoleTableView tableColumnWithIdentifier:SPTableViewDatabaseColumnID] setHidden:[(NSMenuItem*)sender state]];
}

/**
 * Toggles the hiding of messages containing SELECT and SHOW statements
 */
- (IBAction)toggleShowSelectShowStatements:(id)sender
{
	// Store the state of the toggle for later quick reference
	showSelectStatementsAreDisabled = [(NSMenuItem*)sender state];

	[self _updateFilterState];
}

/**
 * Toggles the hiding of messages containing HELP statements
 */
- (IBAction)toggleShowHelpStatements:(id)sender
{
	// Store the state of the toggle for later quick reference
	showHelpStatementsAreDisabled = [(NSMenuItem*)sender state];

	[self _updateFilterState];
}

/**
 * Shows the supplied message from the supplied connection in the console.
 */
- (void)showMessageInConsole:(NSString *)message connection:(NSString *)connection database:(NSString *)database
{
	[self _addMessageToConsole:message connection:connection isError:NO database:database];
}

/**
 * Shows the supplied error from the supplied connection in the console.
 */
- (void)showErrorInConsole:(NSString *)error connection:(NSString *)connection database:(NSString *)database
{
	[self _addMessageToConsole:error connection:connection isError:YES database:database];
}

/**
 * Returns the number of messages currently in the console.
 */
- (NSUInteger)consoleMessageCount
{
	return [messagesFullSet count];
}

#pragma mark -
#pragma mark Other

/**
 * Called whenever the text within the search field changes.
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([[notification object] isEqualTo:consoleSearchField]) {

		// Store the state of the text filter and the current filter string for later quick reference
		[activeFilterString setString:[[[notification object] stringValue] lowercaseString]];
		
		filterIsActive = [activeFilterString length] > 0;

		[self _updateFilterState];
	}
}

/**
 * This method is called as part of Key Value Observing which is used to watch for prefernce changes which effect the interface.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	// Show/hide logging disabled label
	if ([keyPath isEqualToString:SPConsoleEnableLogging]) {
		[loggingDisabledTextField setStringValue:([[change objectForKey:NSKeyValueChangeNewKey] boolValue]) ? @"" : NSLocalizedString(@"Query logging is currently disabled", @"query logging currently disabled label")];
	}
	// Display table veiew vertical gridlines preference changed
	else if ([keyPath isEqualToString:SPDisplayTableViewVerticalGridlines]) {
        [consoleTableView setGridStyleMask:([[change objectForKey:NSKeyValueChangeNewKey] boolValue]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	}
	// Table font preference changed
	else if ([keyPath isEqualToString:SPGlobalFontSettings]) {
		NSFont *tableFont = [NSUserDefaults getFont];

		[consoleTableView setRowHeight:2.0f + NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];
		[consoleTableView setFont:tableFont];
		[consoleTableView reloadData];
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

/**
 * Menu item validation for console table view contextual menu.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    // Disable "Copy with Column Names" and "Copy as SQL INSERT"
    // in the main menu
    if ([menuItem tag] == SPEditMenuCopyWithColumns || [menuItem tag] == SPEditMenuCopyAsSQL || [menuItem tag] == SPEditMenuCopyAsSQLNoAutoInc) {
        return NO;
    }
    
	if ([menuItem action] == @selector(copy:)) {
		return ([consoleTableView numberOfSelectedRows] > 0 || [consoleTableView clickedRow] > -1);
	}

    if ([menuItem action] == @selector(copyQueryOnly:)) {
        return ([consoleTableView numberOfSelectedRows] > 0 || [consoleTableView clickedRow] > -1);
    }

	// Clear console
	if ([menuItem action] == @selector(clearConsole:)) {
		return ([self consoleMessageCount] > 0);
	}

	return [[self window] validateMenuItem:menuItem];
}

- (BOOL)allowConsoleUpdate
{
	return allowConsoleUpdate;
}

- (void)setAllowConsoleUpdate:(BOOL)allowUpdate
{
	allowConsoleUpdate = allowUpdate;
	
	if (allowUpdate && [[self window] isVisible]) [self updateEntries];
}

/**
 * Update the Query Console and scroll to its last line.
 */
- (void)updateEntries
{
	[consoleTableView reloadData];
	[consoleTableView scrollRowToVisible:([messagesVisibleSet count] - 1)];
}

/**
 * Return the AutoSaveName of the Query Console.
 */
- (NSString *)windowFrameAutosaveName
{
	return SPQueryConsoleWindowAutoSaveName;
}

#pragma mark -
#pragma mark Privat API

/**
 * Updates the filtered result set based on any filter string and whether or not
 * all SELECT nd SHOW statements should be shown within the console.
 */
- (void)_updateFilterState
{
	// Display start progress spinner
	[progressIndicator setHidden:NO];
	[progressIndicator startAnimation:self];

	// Don't allow clearing the console while filtering its content
	[self _allowFilterClearOrSave:@NO];

	[messagesFilteredSet removeAllObjects];

	// If filtering is disabled and all show/selects are shown, empty the filtered
	// result set and set the full set to visible.
	if (!filterIsActive && !showSelectStatementsAreDisabled && !showHelpStatementsAreDisabled) {
		messagesVisibleSet = messagesFullSet;

		[consoleTableView reloadData];
		[consoleTableView scrollRowToVisible:([messagesVisibleSet count] - 1)];

		[self _allowFilterClearOrSave:@YES];

		[saveConsoleButton setTitle:NSLocalizedString(@"Save As...", @"save as button title")];

		// Hide progress spinner
		[progressIndicator setHidden:YES];
		[progressIndicator stopAnimation:self];
		
		return;
	}

	// Loop through all the messages in the full set to determine which should be
	// added to the filtered set.
	for (SPConsoleMessage *message in messagesFullSet) {

		// Add a reference to the message to the filtered set if filters are active and the
		// current message matches them
		if ([self _messageMatchesCurrentFilters:[message message]]) {
			[messagesFilteredSet addObject:message];
		}
	}

	// Ensure that the filtered set is marked as the currently visible set.
	messagesVisibleSet = messagesFilteredSet;

	[consoleTableView reloadData];
	[consoleTableView scrollRowToVisible:([messagesVisibleSet count] - 1)];

	if ([messagesVisibleSet count] > 0) {
		[self _allowFilterClearOrSave:@YES];
	}

	[saveConsoleButton setTitle:NSLocalizedString(@"Save View As...", @"save view as button title")];

	// Hide progress spinner
	[progressIndicator setHidden:YES];
	[progressIndicator stopAnimation:self];
}

/**
 * Enable or disable console save and clear buttons
 */
- (void)_allowFilterClearOrSave:(NSNumber *)enabled
{
	[saveConsoleButton setEnabled:[enabled boolValue]];
	[clearConsoleButton setEnabled:[enabled boolValue]];
}

/**
 * Checks whether the supplied message text matches the current filter text, if any,
 * and whether it should be hidden if the SELECT/SHOW toggle is off.
 */
- (BOOL)_messageMatchesCurrentFilters:(NSString *)message
{
	BOOL messageMatchesCurrentFilters = YES;

	// Check whether to hide the message based on the current filter text, if any
	if (filterIsActive && [message rangeOfString:activeFilterString options:NSCaseInsensitiveSearch].location == NSNotFound) {
		messageMatchesCurrentFilters = NO;
	}

	// If hiding SELECTs and SHOWs is toggled to on, check whether the message is a SELECT or SHOW
	if (messageMatchesCurrentFilters && 
		showSelectStatementsAreDisabled && 
		([[message uppercaseString] hasPrefix:@"SELECT"] || [[message uppercaseString] hasPrefix:@"SHOW"]))
	{
		messageMatchesCurrentFilters = NO;
	}

	// If hiding HELP is toggled to on, check whether the message is a HELP
	if (messageMatchesCurrentFilters && showHelpStatementsAreDisabled && ([[message uppercaseString] hasPrefix:@"HELP"])) {
		messageMatchesCurrentFilters = NO;
	}

	return messageMatchesCurrentFilters;
}

/**
 * Creates and returns a string made entirely of all of the console's messages and includes the message
 * time stamp and connection if specified.
 */
- (NSString *)_getConsoleStringWithTimeStamps:(BOOL)timeStamps connections:(BOOL)connections databases:(BOOL)databases
{
	NSMutableString *consoleString = [NSMutableString string];
	
	for (SPConsoleMessage *message in messagesVisibleSet)
	{
		// As we are going to save the messages as an SQL file we need to comment
		// the timestamps and connections if included.
		if (timeStamps || connections) [consoleString appendString:@"/* "];

		// If the timestamp column is not hidden we need to include them in the copy
		if (timeStamps) {
			[consoleString appendString:[dateFormatter stringFromDate:[message messageDate]]];
			[consoleString appendString:@" "];
		}

		// If the connection column is not hidden we need to include them in the copy
		if (connections) {
			[consoleString appendString:[message messageConnection]];
			[consoleString appendString:@" "];
		}

		if (databases && [message messageDatabase]) {
			[consoleString appendString:[message messageDatabase]];
			[consoleString appendString:@" "];
		}

		// Close the comment
		if (timeStamps || connections) [consoleString appendString:@"*/ "];

		[consoleString appendFormat:@"%@\n", [message message]];
	}

	return consoleString;
}

/**
 * Adds the supplied message to the query console.
 */
- (void)_addMessageToConsole:(NSString *)message connection:(NSString *)connection isError:(BOOL)error database:(NSString *)database
{

    // return if no actual message
    if(IsEmpty(message)){
        SPLog(@"message is empty, returning");
        return;
    }

	NSString *messageTemp = [[message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];

	// Only append a semi-colon (;) if the supplied message is not an error
	if (!error) messageTemp = [messageTemp stringByAppendingString:@";"];

	SPConsoleMessage *consoleMessage = [SPConsoleMessage consoleMessageWithMessage:messageTemp date:[NSDate date] connection:connection database:database];

	[consoleMessage setIsError:error];

	pthread_mutex_lock(&consoleLock);
	
	[messagesFullSet addObject:consoleMessage];

	// If filtering is active, determine whether to add a reference to the filtered set
	if ((showSelectStatementsAreDisabled || showHelpStatementsAreDisabled || filterIsActive)
		&& [self _messageMatchesCurrentFilters:[consoleMessage message]])
	{
		[messagesFilteredSet addObject:[messagesFullSet lastObject]];
		[self performSelectorOnMainThread:@selector(_allowFilterClearOrSave:) withObject:@YES waitUntilDone:NO];
	}

	// Reload the table and scroll to the new message if it's visible (for speed)
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self->allowConsoleUpdate && [[self window] isVisible]) {
			[self performSelectorOnMainThread:@selector(updateEntries) withObject:nil waitUntilDone:NO];
		}
	});

	pthread_mutex_unlock(&consoleLock);
}

#pragma mark - SPQueryControllerInitializer

/**
 * Set the window's auto save name and initialise display.
 */
- (void)awakeFromNib
{
    [super awakeFromNib];
    
	prefs = [NSUserDefaults standardUserDefaults];

	[self setWindowFrameAutosaveName:SPQueryConsoleWindowAutoSaveName];

	// Show/hide table columns
	[[consoleTableView tableColumnWithIdentifier:SPTableViewDateColumnID] setHidden:![prefs boolForKey:SPConsoleShowTimestamps]];
	[[consoleTableView tableColumnWithIdentifier:SPTableViewConnectionColumnID] setHidden:![prefs boolForKey:SPConsoleShowConnections]];
	[[consoleTableView tableColumnWithIdentifier:SPTableViewDatabaseColumnID] setHidden:![prefs boolForKey:SPConsoleShowDatabases]];

	showSelectStatementsAreDisabled = ![prefs boolForKey:SPConsoleShowSelectsAndShows];
	showHelpStatementsAreDisabled = ![prefs boolForKey:SPConsoleShowHelps];

	[self _updateFilterState];

	[loggingDisabledTextField setStringValue:([prefs boolForKey:SPConsoleEnableLogging]) ? @"" : NSLocalizedString(@"Query logging is currently disabled", @"query logging disabled label")];

	// Setup data formatter
	dateFormatter = NSDateFormatter.mediumStyleNoDateFormatter;

	// Set the process table view's vertical gridlines if required
	[consoleTableView setGridStyleMask:([prefs boolForKey:SPDisplayTableViewVerticalGridlines]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];

	[prefs addObserver:self forKeyPath:SPGlobalFontSettings options:NSKeyValueObservingOptionNew context:nil];

	// Set the strutcture and index view's font
	NSFont *tableFont = [NSUserDefaults getFont];
	[consoleTableView setRowHeight:2.0f+NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];

	for (NSTableColumn *column in [consoleTableView tableColumns])
	{
		[[column dataCell] setFont:tableFont];
	}

	//allow drag-out copying of selected rows
	[consoleTableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
}

/**
 * Loads the query controller's completion tokens data.
 */
- (NSError *)loadCompletionLists
{
	NSError *readError = nil;
	NSString *errorDescription = nil;
	
	NSString *filePath = [NSBundle pathForResource:SPCompletionTokensFilename
	                                        ofType:nil
	                                   inDirectory:[[NSBundle mainBundle] bundlePath]];
						  
	NSData *completionTokensData = [NSData dataWithContentsOfFile:filePath
	                                                      options:NSMappedRead
	                                                        error:&readError];

	NSDictionary *completionPlist = nil;
	if(completionTokensData && !readError) {
		NSDictionary *plistDict = [NSPropertyListSerialization propertyListWithData:completionTokensData
		                                                                    options:NSPropertyListMutableContainersAndLeaves
		                                                                     format:NULL
		                                                                      error:&readError];
	
		if(plistDict && !readError) {
			completionPlist = [NSDictionary dictionaryWithDictionary:plistDict];
		}
	}
	
	if (completionPlist == nil || readError) {
		errorDescription = [NSString stringWithFormat:@"Error reading '%@': %@", SPCompletionTokensFilename, readError];
	}
	else {
		if ([completionPlist objectForKey:SPCompletionTokensKeywordsKey]) {
			completionKeywordList = [NSArray arrayWithArray:[completionPlist objectForKey:SPCompletionTokensKeywordsKey]];
		}
		else {
			errorDescription = [NSString stringWithFormat:@"No '%@' array found.", SPCompletionTokensKeywordsKey];
		}

		if ([completionPlist objectForKey:SPCompletionTokensFunctionsKey]) {
			completionFunctionList = [NSArray arrayWithArray:[completionPlist objectForKey:SPCompletionTokensFunctionsKey]];
		}
		else {
			errorDescription = [NSString stringWithFormat:@"No '%@' array found.", SPCompletionTokensFunctionsKey];
		}

		if ([completionPlist objectForKey:SPCompletionTokensSnippetsKey]) {
			functionArgumentSnippets = [NSDictionary dictionaryWithDictionary:[completionPlist objectForKey:SPCompletionTokensSnippetsKey]];
		}
		else {
			errorDescription = [NSString stringWithFormat:@"No '%@' dictionary found.", SPCompletionTokensSnippetsKey];
		}
	}

	return errorDescription ? [NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey : errorDescription}] : nil;
}

#pragma mark - SPQueryConsoleDataSource

/**
 * Table view delegate method. Returns the number of rows in the table veiw.
 */
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [messagesVisibleSet count];
}

/**
 * Table view delegate method. Returns the specific object for the requested column and row.
 */
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *returnValue = nil;

	NSString *identifier = [tableColumn identifier];

	if (!identifier) return returnValue;

    id object = [[messagesVisibleSet safeObjectAtIndex:row] valueForKey:identifier];

	if ([[tableColumn identifier] isEqualToString:SPTableViewDateColumnID]) {

		returnValue = [dateFormatter stringFromDate:(NSDate *)object];
	}
	else {
		if ([(NSString *)object length] > SPMessageTruncateCharacterLength) {
			object = [NSString stringWithFormat:@"%@...", [object substringToIndex:SPMessageTruncateCharacterLength]];
		}

		returnValue = object;
	}

	if (!returnValue) return returnValue;

	NSMutableDictionary *stringAtributes = nil;

	if (consoleFont) {
		stringAtributes = [NSMutableDictionary dictionaryWithObject:consoleFont forKey:NSFontAttributeName];
	}

	// If this is an error message give it a red colour
	if ([(SPConsoleMessage *)[messagesVisibleSet safeObjectAtIndex:row] isError]) {
		if (stringAtributes) {
			[stringAtributes setObject:[NSColor redColor] forKey:NSForegroundColorAttributeName];
		}
		else {
			stringAtributes = [NSMutableDictionary dictionaryWithObject:[NSColor redColor] forKey:NSForegroundColorAttributeName];
		}
	}

	return [[NSAttributedString alloc] initWithString:returnValue attributes:stringAtributes];
}

- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
    BOOL includeTimestamps  = ![[consoleTableView tableColumnWithIdentifier:SPTableViewDateColumnID] isHidden];
    BOOL includeConnections = ![[consoleTableView tableColumnWithIdentifier:SPTableViewConnectionColumnID] isHidden];
    BOOL includeDatabases   = ![[consoleTableView tableColumnWithIdentifier:SPTableViewDatabaseColumnID] isHidden];

    NSString *string = [self infoStringForRowIndexes:rowIndexes includeTimestamps:includeTimestamps includeConnections:includeConnections includeDatabases:includeDatabases];
	if([string length]) {
		[pboard declareTypes:@[NSPasteboardTypeString] owner:self];
		return [pboard setString:string forType:NSPasteboardTypeString];
	}

	return NO;
}

#pragma mark - SPQueryDocumentsController

- (NSURL *)registerDocumentWithFileURL:(NSURL *)fileURL andContextInfo:(NSMutableDictionary *)contextInfo
{
	// Register a new untiled document and return its URL
	if (fileURL == nil) {
		NSURL *newURL = [NSURL URLWithString:[[NSString stringWithFormat:NSLocalizedString(@"Untitled %ld",@"Title of a new Sequel Ace Document"), (unsigned long)untitledDocumentCounter] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];
		untitledDocumentCounter++;

		if (![favoritesContainer safeObjectForKey:[newURL absoluteString]]) {
			NSMutableArray *arr = [[NSMutableArray alloc] init];
			[favoritesContainer safeSetObject:arr forKey:[newURL absoluteString]];
		}

		// Set the global history coming from the Prefs as default if available
		if (![historyContainer safeObjectForKey:[newURL absoluteString]]) {
			if(_SQLiteHistoryManager.migratedPrefsToDB == YES){

				// we want the values, sorted by the reverse of the key order
				// remember allKey specifies no order, so we need to sort.
				NSArray *sortedKeys = [[_SQLiteHistoryManager.queryHist allKeys] sortedArrayUsingFunction:intSortDesc context:NULL];

				NSMutableArray *sortedValues = [NSMutableArray array];
				for (NSNumber *key in sortedKeys){
					[sortedValues addObject: [_SQLiteHistoryManager.queryHist objectForKey:key]];
				}

				[historyContainer safeSetObject:sortedValues forKey:[newURL absoluteString]];
			}
			else{
				if ([prefs objectForKey:SPQueryHistory]) {
					NSMutableArray *arr = [[NSMutableArray alloc] init];
					[arr addObjectsFromArray:[prefs objectForKey:SPQueryHistory]];
					[historyContainer safeSetObject:arr forKey:[newURL absoluteString]];
				}
				else {
					[historyContainer safeSetObject:[NSMutableArray array] forKey:[newURL absoluteString]];
				}
			}
		}

		// Set the doc-based content filters
		if (![contentFilterContainer safeObjectForKey:[newURL absoluteString]]) {
			[contentFilterContainer safeSetObject:[NSMutableDictionary dictionary] forKey:[newURL absoluteString]];
		}

		return newURL;
	}

	// Register a spf file to manage all query favorites and query history items
	// file path based (incl. Untitled docs) in a dictionary whereby the key represents the file URL as string.
	if (![favoritesContainer safeObjectForKey:[fileURL absoluteString]]) {
		if (contextInfo != nil && [contextInfo safeObjectForKey:SPQueryFavorites] && [[contextInfo safeObjectForKey:SPQueryFavorites] count]) {
			NSMutableArray *arr = [[NSMutableArray alloc] init];
			[arr addObjectsFromArray:[contextInfo safeObjectForKey:SPQueryFavorites]];
			[favoritesContainer safeSetObject:arr forKey:[fileURL absoluteString]];
		}
		else {
			NSMutableArray *arr = [[NSMutableArray alloc] init];
			[favoritesContainer safeSetObject:arr forKey:[fileURL absoluteString]];
		}
	}

	if (![historyContainer safeObjectForKey:[fileURL absoluteString]]) {
		if (contextInfo != nil && [contextInfo safeObjectForKey:SPQueryHistory] && [[contextInfo safeObjectForKey:SPQueryHistory] count]) {
			NSMutableArray *arr = [[NSMutableArray alloc] init];
			[arr addObjectsFromArray:[contextInfo objectForKey:SPQueryHistory]];
			[historyContainer safeSetObject:arr forKey:[fileURL absoluteString]];
		}
		else {
			NSMutableArray *arr = [[NSMutableArray alloc] init];
			[historyContainer safeSetObject:arr forKey:[fileURL absoluteString]];
		}
	}

	if (![contentFilterContainer safeObjectForKey:[fileURL absoluteString]]) {
		if (contextInfo != nil && [contextInfo safeObjectForKey:SPContentFilters]) {
			[contentFilterContainer safeSetObject:[contextInfo safeObjectForKey:SPContentFilters] forKey:[fileURL absoluteString]];
		}
		else {
			NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
			[contentFilterContainer safeSetObject:dict forKey:[fileURL absoluteString]];
		}
	}

	return fileURL;
}

- (void)removeRegisteredDocumentWithFileURL:(NSURL *)fileURL
{
	// Check for multiple instance of the same document.
	// Remove it if only one instance was registerd.
	NSArray *allDocs = [SPAppDelegate orderedDocuments];
	NSMutableArray *allURLs = [NSMutableArray array];

	for (SPDatabaseDocument *databaseDocument in allDocs)
	{
        if (![databaseDocument fileURL]) {
            continue;
        }

		if ([allURLs containsObject:[databaseDocument fileURL]]) {
			return;
		} else {
			[allURLs addObject:[databaseDocument fileURL]];
		}
	}

	if ([favoritesContainer objectForKey:[fileURL absoluteString]]) {
		[favoritesContainer removeObjectForKey:[fileURL absoluteString]];
	}

	if ([historyContainer objectForKey:[fileURL absoluteString]]) {
		[historyContainer removeObjectForKey:[fileURL absoluteString]];
	}

	if ([contentFilterContainer objectForKey:[fileURL absoluteString]]) {
		[contentFilterContainer removeObjectForKey:[fileURL absoluteString]];
	}
}

- (void)replaceContentFilterByArray:(NSArray *)contentFilterArray ofType:(NSString *)filterType forFileURL:(NSURL *)fileURL
{
	if ([contentFilterContainer objectForKey:[fileURL absoluteString]]) {
		NSMutableDictionary *c = [[NSMutableDictionary alloc] init];
		[c setDictionary:[contentFilterContainer objectForKey:[fileURL absoluteString]]];
		[c setObject:contentFilterArray forKey:filterType];
		[contentFilterContainer setObject:c forKey:[fileURL absoluteString]];
	}
}

- (void)replaceFavoritesByArray:(NSArray *)favoritesArray forFileURL:(NSURL *)fileURL
{
	if ([favoritesContainer objectForKey:[fileURL absoluteString]]) {
		[favoritesContainer setObject:favoritesArray forKey:[fileURL absoluteString]];
	}
}

/**
 * Remove a Query Favorite the passed file URL
 *
 * @param index The index of the to be removed favorite
 *
 * @param fileURL The NSURL of the current active SPDatabaseDocument
 */
- (void)removeFavoriteAtIndex:(NSUInteger)index forFileURL:(NSURL *)fileURL
{
	[[favoritesContainer objectForKey:[fileURL absoluteString]] removeObjectAtIndex:index];
}

- (void)insertFavorite:(NSDictionary *)favorite atIndex:(NSUInteger)index forFileURL:(NSURL *)fileURL
{
	[[favoritesContainer objectForKey:[fileURL absoluteString]] insertObject:favorite atIndex:index];
}

- (void)replaceHistoryByArray:(NSArray *)historyArray forFileURL:(NSURL *)fileURL
{
	if ([historyContainer objectForKey:[fileURL absoluteString]]) {
		[historyContainer setObject:historyArray forKey:[fileURL absoluteString]];
	}

	// Inform all opened documents to update the history list
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPHistoryItemsHaveBeenUpdatedNotification object:self];

	// User did choose to clear the global history list
	if (![fileURL isFileURL] && ![historyArray count]) {
		
		if(_SQLiteHistoryManager.migratedPrefsToDB == YES){
			[_SQLiteHistoryManager deleteQueryHistory];
			[historyContainer setObject:@[] forKey:[fileURL absoluteString]]; // just set array to empty
		}
		else{
			[prefs setObject:historyArray forKey:SPQueryHistory];
		}
	}
}

- (void)addFavorite:(NSDictionary *)favorite forFileURL:(NSURL *)fileURL
{
	if ([favoritesContainer objectForKey:[fileURL absoluteString]]) {
		[[favoritesContainer objectForKey:[fileURL absoluteString]] addObject:favorite];
	}
}

- (void)addHistory:(NSString *)history forFileURL:(NSURL *)fileURL
{
	NSUInteger maxHistoryItems = [[prefs objectForKey:SPCustomQueryMaxHistoryItems] integerValue];

    NSString *fileURLStr = [fileURL absoluteString];

    SPLog(@"fileURLStr = %@", fileURLStr);

	// Save each history item due to its document source
	if (fileURLStr != nil && [historyContainer safeObjectForKey:fileURLStr]) {

		// Remove all duplicates by using a NSPopUpButton
		NSPopUpButton *uniquifier = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,0,0) pullsDown:YES];

        SPLog(@"uniquifier = %@\nAdding: %@", uniquifier.debugDescription, [historyContainer safeObjectForKey:fileURLStr]);

        // add current history
		[uniquifier addItemsWithTitles:[historyContainer safeObjectForKey:fileURLStr]];

        // add new history
        NSArray *histArr = [_SQLiteHistoryManager normalizeQueryHistoryWithArrayToNormalise:@[history]];
        for(NSString *str in histArr){
            [uniquifier insertItemWithTitle:str atIndex:0];
        }

		while ((NSUInteger)[uniquifier numberOfItems] > maxHistoryItems)
		{
			[uniquifier removeItemAtIndex:[uniquifier numberOfItems]-1];
		}

		[self replaceHistoryByArray:[uniquifier itemTitles] forFileURL:fileURL];
	}

	// Save history items coming from each Untitled document in the global Preferences successively
	// regardingless of the source document.
	if (![fileURL isFileURL]) {

		// Remove all duplicates by using a NSPopUpButton
		NSPopUpButton *uniquifier = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,0,0) pullsDown:YES];
		if(_SQLiteHistoryManager.migratedPrefsToDB == YES){
			[uniquifier addItemsWithTitles:_SQLiteHistoryManager.queryHist.allValues];
		}
		else{
			[uniquifier addItemsWithTitles:[prefs objectForKey:SPQueryHistory]];
		}
		[uniquifier insertItemWithTitle:history atIndex:0];

		while ((NSUInteger)[uniquifier numberOfItems] > maxHistoryItems)
		{
			[uniquifier removeItemAtIndex:[uniquifier numberOfItems] - 1];
		}

		if(_SQLiteHistoryManager.migratedPrefsToDB == YES){
			[_SQLiteHistoryManager updateQueryHistoryWithNewHist:[uniquifier itemTitles]];
		}
		else{
			[prefs setObject:[uniquifier itemTitles] forKey:SPQueryHistory];
		}
	}
}

- (NSMutableArray *)favoritesForFileURL:(NSURL *)fileURL
{
	if ([favoritesContainer objectForKey:[fileURL absoluteString]]) {
		return [favoritesContainer objectForKey:[fileURL absoluteString]];
	}

	return [NSMutableArray array];
}

- (NSMutableArray *)historyForFileURL:(NSURL *)fileURL
{
	if ([historyContainer safeObjectForKey:[fileURL absoluteString]]) {
		return [historyContainer safeObjectForKey:[fileURL absoluteString]];
	}

	return [NSMutableArray array];
}

- (NSArray *)historyMenuItemsForFileURL:(NSURL *)fileURL
{
	if ([historyContainer safeObjectForKey:[fileURL absoluteString]]) {
		NSMutableArray *returnArray = [NSMutableArray arrayWithCapacity:[[historyContainer safeObjectForKey:[fileURL absoluteString]] count]];
		NSMenuItem *historyMenuItem;

		for (NSString* history in [historyContainer safeObjectForKey:[fileURL absoluteString]])
		{
			historyMenuItem = [[NSMenuItem alloc] initWithTitle:([history length] > 64) ? [NSString stringWithFormat:@"%@…", [history substringToIndex:63]] : history
														  action:NULL
												   keyEquivalent:@""];

			[historyMenuItem setToolTip:([history length] > 256) ? [NSString stringWithFormat:@"%@…", [history substringToIndex:255]] : history];
			[returnArray addObject:historyMenuItem];
		}

		return returnArray;
	}

	return @[];
}

/**
 * Return the number of history items for the passed file URL
 *
 * @param fileURL The NSURL of the current active SPDatabaseDocument
 *
 */
- (NSUInteger)numberOfHistoryItemsForFileURL:(NSURL *)fileURL
{
	if ([historyContainer safeObjectForKey:[fileURL absoluteString]]) {
		return [[historyContainer safeObjectForKey:[fileURL absoluteString]] count];
	}
	else {
		return 0;
	}

	return 0;
}

/**
 * Return a mutable dictionary of all content filters for the passed file URL.
 * If no content filters were found it returns an empty mutable dictionary.
 *
 * @param fileURL The NSURL of the current active SPDatabaseDocument
 *
 */
- (NSMutableDictionary *)contentFilterForFileURL:(NSURL *)fileURL
{
	if ([contentFilterContainer safeObjectForKey:[fileURL absoluteString]]) {
		return [contentFilterContainer safeObjectForKey:[fileURL absoluteString]];
	}

	return [NSMutableDictionary dictionary];
}

- (NSArray *)queryFavoritesForFileURL:(NSURL *)fileURL andTabTrigger:(NSString *)tabTrigger includeGlobals:(BOOL)includeGlobals
{
	if (![tabTrigger length]) return @[];

	NSMutableArray *result = [[NSMutableArray alloc] init];

	for (id fav in [self favoritesForFileURL:fileURL])
	{
		if ([fav objectForKey:@"tabtrigger"] && [[fav objectForKey:@"tabtrigger"] isEqualToString:tabTrigger]) {
			[result addObject:fav];
		}
	}

	if (includeGlobals && [prefs objectForKey:SPQueryFavorites]) {

		for (id fav in [prefs objectForKey:SPQueryFavorites])
		{
			if ([fav objectForKey:@"tabtrigger"] && [[fav objectForKey:@"tabtrigger"] isEqualToString:tabTrigger]) {
				[result addObject:fav];
				break;
			}
		}
	}

	return result;
}

#pragma mark -
#pragma mark Completion list controller

/**
 * Return an array of all pre-defined SQL functions for completion.
 */
- (NSArray*)functionList
{
	return (completionFunctionList != nil && [completionFunctionList count]) ? completionFunctionList : @[];
}

/**
 * Return an array of all pre-defined SQL keywords for completion.
 */
- (NSArray*)keywordList
{
	return (completionKeywordList != nil && [completionKeywordList count]) ? completionKeywordList : @[];
}

/**
 * Return the parameter list as snippet of the passed SQL functions for completion.
 *
 * @param func The name of the function whose parameter list is asked for
 */
- (NSString*)argumentSnippetForFunction:(NSString*)func
{
	return (functionArgumentSnippets && [functionArgumentSnippets objectForKey:[func uppercaseString]]) ? [functionArgumentSnippets objectForKey:[func uppercaseString]] : @"";
}

#pragma mark -

- (void)dealloc
{
	[prefs removeObserver:self forKeyPath:SPGlobalFontSettings];
	messagesVisibleSet = nil;
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	
	[_SQLiteHistoryManager.queue close];

	pthread_mutex_destroy(&consoleLock);
}

@end
