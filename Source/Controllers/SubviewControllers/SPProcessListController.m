//
//  SPProcessListController.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on November 12, 2009.
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

#import "SPProcessListController.h"
#import "SPDatabaseDocument.h"
#import "SPAppController.h"
#import "SPDataCellFormatter.h"
#import "SPThreadAdditions.h"

#import <SPMySQL/SPMySQL.h>

#import "sequel-ace-Swift.h"

// Constants
static NSString *SPKillProcessQueryMode        = @"SPKillProcessQueryMode";
static NSString *SPKillProcessConnectionMode   = @"SPKillProcessConnectionMode";
static NSString *SPTableViewIDColumnIdentifier = @"Id";

static NSString * const SPKillModeKey = @"SPKillMode";
static NSString * const SPKillIdKey   = @"SPKillId";

@interface SPProcessListController ()

- (void)_processListRefreshed;
- (void)_startAutoRefreshTimer;
- (void)_killAutoRefreshTimer;
- (void)_fireAutoRefresh:(NSTimer *)timer;
- (void)_updateSelectedAutoRefreshIntervalInterface;
- (void)_startAutoRefreshTimerWithInterval:(NSTimeInterval)interval;
- (void)_getDatabaseProcessListInBackground:(id)object;
- (void)_killProcessQueryWithId:(long long)processId;
- (void)_killProcessConnectionWithId:(long long)processId;
- (void)_updateServerProcessesFilterForFilterString:(NSString *)filterString;
- (void)_addPreferenceObservers;
- (void)_removePreferenceObservers;

@end

@implementation SPProcessListController

@synthesize connection;

#pragma mark -
#pragma mark Initialisation

- (instancetype)init
{
	if ((self = [super initWithWindowNibName:@"DatabaseProcessList"])) {
		
		autoRefreshTimer = nil;
		processListThreadRunning = NO;
		
		showFullProcessList = [prefs boolForKey:SPProcessListShowFullProcessList];
		
		processes = [[NSMutableArray alloc] init];
		
		prefs = [NSUserDefaults standardUserDefaults];
		
		showFullProcessList = [prefs boolForKey:SPProcessListShowFullProcessList];
	}
	
	return self;
}

- (void)awakeFromNib
{	
	[[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Server Processes on %@", @"server processes window title (var = hostname)"),[[SPAppDelegate frontDocument] name]]];
	
	[self setWindowFrameAutosaveName:@"ProcessList"];
	
	// Show/hide table columns
	[[processListTableView tableColumnWithIdentifier:SPTableViewIDColumnIdentifier] setHidden:![prefs boolForKey:SPProcessListShowProcessID]];
	
	// Set the process table view's vertical gridlines if required
	[processListTableView setGridStyleMask:([prefs boolForKey:SPDisplayTableViewVerticalGridlines]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];

	NSFont *tableFont = [NSUserDefaults getFont];
	[processListTableView setRowHeight:2.0f+NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];

	for (NSTableColumn *column in [processListTableView tableColumns])
	{
		[[column dataCell] setFont:tableFont];

		// Add a formatter for linebreak display
		[[column dataCell] setFormatter:[SPDataCellFormatter new]];
	
		// Also, if available restore the table's column widths
		NSNumber *columnWidth = [[prefs objectForKey:SPProcessListTableColumnWidths] objectForKey:[[column headerCell] stringValue]];
				
		if (columnWidth) [column setWidth:[columnWidth floatValue]];
	}

	[self _addPreferenceObservers];
}

/**
 * Interface loading
 */
- (void)windowDidLoad
{
	// Update the selected auto refresh interval
	[self _updateSelectedAutoRefreshIntervalInterface];
}

#pragma mark -
#pragma mark IB action methods

/**
 * Copies the currently selected process(es) to the pasteboard.
 */
- (IBAction)copy:(id)sender
{	
	NSResponder *firstResponder = [[self window] firstResponder];
	
	if ((firstResponder == processListTableView) && ([processListTableView numberOfSelectedRows] > 0)) {
		
		NSMutableString *string = [NSMutableString string];
		NSIndexSet *rows = [processListTableView selectedRowIndexes];
		
		[rows enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * _Nonnull stop) {
			if (i < [processesFiltered count]) {
				NSDictionary *process = [processesFiltered safeObjectAtIndex:i];
				
				NSString *stringTmp = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@ %@",
									   [process objectForKey:@"Id"],
									   [process objectForKey:@"User"],
									   [process objectForKey:@"Host"],
									   [process objectForKey:@"db"],
									   [process objectForKey:@"Command"],
									   [process objectForKey:@"Time"],
									   [process objectForKey:@"State"],
									   [process objectForKey:@"Info"]];
				
				[string appendString:stringTmp];
				[string appendString:@"\n"];
			}
		}];
		
		NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
		
		// Copy the string to the pasteboard
		[pasteBoard declareTypes:@[NSStringPboardType] owner:nil];
		[pasteBoard setString:string forType:NSStringPboardType];
	}
}

/**
 * Close the current sheet
 */
- (IBAction)closeSheet:(id)sender
{
	[NSApp endSheet:[sender window] returnCode:[sender tag]];
	[[sender window] orderOut:self];
}

/**
 * If required start the auto refresh timer.
 */
- (void)showWindow:(id)sender
{
	// If the auto refresh option is enable start the timer
	if ([prefs boolForKey:SPProcessListEnableAutoRefresh]) {
		
		// Start the auto refresh time but by pass the interface updates
		[self _startAutoRefreshTimer];
	}
	
	[super showWindow:sender];
}

/**
 * Refreshes the process list.
 */
- (IBAction)refreshProcessList:(id)sender
{
	// If the document is currently performing a task (most likely threaded) on the current connection, don't
	// allow a refresh to prevent connection lock errors.
	if ([(SPDatabaseDocument *)[connection delegate] isWorking]) return;
	
	// Also, only proceed if there is not already a background thread running.
	if (processListThreadRunning) return;
	
	// Start progress Indicator
	[refreshProgressIndicator startAnimation:self];
	[refreshProgressIndicator setHidden:NO];
	
	// Disable controls
	[refreshProcessesButton setEnabled:NO];
	[saveProcessesButton setEnabled:NO];
	[filterProcessesSearchField setEnabled:NO];
	
	processListThreadRunning = YES;
		
	// Get the processes list on a background thread
	[NSThread detachNewThreadWithName:@"SPProcessListController retrieving process list" target:self selector:@selector(_getDatabaseProcessListInBackground:) object:nil];
}

/**
 * Saves the process list to the selected file.
 */
- (IBAction)saveServerProcesses:(id)sender
{
	NSSavePanel *panel = [NSSavePanel savePanel];
		
	[panel setExtensionHidden:NO];
	[panel setAllowsOtherFileTypes:YES];
	[panel setCanSelectHiddenExtension:YES];
	
    [panel setNameFieldStringValue:@"ServerProcesses"];
    [panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger returnCode) {
        if (returnCode == NSModalResponseOK) {
            if ([self->processesFiltered count] > 0) {
                NSMutableString *processesString = [NSMutableString stringWithFormat:@"# MySQL server processes for %@\n\n", [[SPAppDelegate frontDocument] host]];
                
                for (NSDictionary *process in self->processesFiltered)
                {
                    NSString *stringTmp = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@ %@",
                                           [process objectForKey:@"Id"],
                                           [process objectForKey:@"User"],
                                           [process objectForKey:@"Host"],
                                           [process objectForKey:@"db"],
                                           [process objectForKey:@"Command"],
                                           [process objectForKey:@"Time"],
                                           [process objectForKey:@"State"],
                                           [process objectForKey:@"Info"]];
                    
                    [processesString appendString:stringTmp];
                    [processesString appendString:@"\n"];
                }
                
                [processesString writeToURL:[panel URL] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            }
        }
    }];
}

/**
 * Kills the currently selected process' query.
 */
- (IBAction)killProcessQuery:(id)sender {
	// No process selected. Interface validation should prevent this.
	if ([processListTableView numberOfSelectedRows] != 1) return;
	
	long long processId = [[[processesFiltered objectAtIndex:[processListTableView selectedRow]] valueForKey:@"Id"] longLongValue];

	[NSAlert createDefaultAlertWithTitle:NSLocalizedString(@"Kill query?", @"kill query message") message:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to kill the current query executing on connection ID %lld?\n\nPlease be aware that continuing to kill this query may result in data corruption. Please proceed with caution.", @"kill query informative message"), processId] primaryButtonTitle:NSLocalizedString(@"Kill", @"kill button") primaryButtonHandler:^{
		[self _killProcessQueryWithId:processId];
	} cancelButtonHandler:nil];
}

/**
 * Kills the currently selected proceess' connection.
 */
- (IBAction)killProcessConnection:(id)sender {
	// No process selected. Interface validation should prevent this.
	if ([processListTableView numberOfSelectedRows] != 1) return;
	
	long long processId = [[[processesFiltered objectAtIndex:[processListTableView selectedRow]] valueForKey:@"Id"] longLongValue];

	[NSAlert createDefaultAlertWithTitle:NSLocalizedString(@"Kill connection?", @"kill connection message") message:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to kill connection ID %lld?\n\nPlease be aware that continuing to kill this connection may result in data corruption. Please proceed with caution.", @"kill connection informative message"), processId] primaryButtonTitle:NSLocalizedString(@"Kill", @"kill button") primaryButtonHandler:^{
		[self _killProcessConnectionWithId:processId];
	} cancelButtonHandler:nil];
}

/**
 * Toggles the display of the process ID table column.
 */
- (IBAction)toggleShowProcessID:(NSMenuItem *)sender
{
	[[processListTableView tableColumnWithIdentifier:SPTableViewIDColumnIdentifier] setHidden:([sender state])];
}

/**
 * Toggles the display of the FULL process list.
 */
- (IBAction)toggeleShowFullProcessList:(NSMenuItem *)sender
{
	showFullProcessList = (!showFullProcessList);

	[self refreshProcessList:self];
}

/**
 * Toggles whether or not auto refresh is enabled.
 */
- (IBAction)toggleProcessListAutoRefresh:(NSButton *)sender
{
	BOOL enable = [sender state];
	
	// Enable/Disable the refresh button
	[refreshProcessesButton setEnabled:(!enable)];
	
	(enable) ? [self _startAutoRefreshTimer] : [self _killAutoRefreshTimer];
}

/**
 * Changes the auto refresh time interval based on the selected item
 */
- (IBAction)setAutoRefreshInterval:(id)sender
{
	[self _startAutoRefreshTimerWithInterval:[sender tag]];
}

/**
 * Displays the set custom auto-refresh interval sheet.
 */
- (IBAction)setCustomAutoRefreshInterval:(id)sender
{
	[customIntervalTextField setStringValue:[prefs stringForKey:SPProcessListAutoRrefreshInterval]];

	[[self window] beginSheet:customIntervalWindow completionHandler:^(NSModalResponse returnCode) {
		if (returnCode == NSModalResponseOK) {
			[self _startAutoRefreshTimerWithInterval:[self->customIntervalTextField integerValue]];
		}
	}];
}

#pragma mark -
#pragma mark Other methods

/**
 * Displays the process list sheet attached to the supplied window.
 */
- (void)displayProcessListWindow
{
	// Weak reference
	processesFiltered = processes;
	
	[self refreshProcessList:self];
	 
	[self showWindow:self];
}

/**
 * Menu item validation.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	SEL action = [menuItem action];
	
	if (action == @selector(copy:)) {
		return ([processListTableView numberOfSelectedRows] > 0);
	}
	
	if ((action == @selector(killProcessQuery:)) || (action == @selector(killProcessConnection:))) {
		return ([processListTableView numberOfSelectedRows] == 1);
	}
	
	if ((action == @selector(setAutoRefreshInterval:)) || (action == @selector(setCustomAutoRefreshInterval:))) {
		return [prefs boolForKey:SPProcessListEnableAutoRefresh];
	}
	
	return YES;
}

/**
 * NSWindow autosave name
 */
- (NSString *)windowFrameAutosaveName
{
	return @"ProcessList";
}

/**
 * This method is called as part of Key Value Observing which is used to watch for prefernce changes which effect the interface.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{	
	// Display table veiew vertical gridlines preference changed
	if ([keyPath isEqualToString:SPDisplayTableViewVerticalGridlines]) {
        [processListTableView setGridStyleMask:([[change objectForKey:NSKeyValueChangeNewKey] boolValue]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	}
	// Table font preference changed
	else if ([keyPath isEqualToString:SPGlobalFontSettings]) {
		NSFont *tableFont = [NSUserDefaults getFont];

		[processListTableView setRowHeight:2.0f + NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];
		[processListTableView setFont:tableFont];
		[processListTableView reloadData];
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

#pragma mark -
#pragma mark Text field delegate methods

/**
 * Apply the filter string to the current process list.
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
	id object = [notification object];
	
	if (object == filterProcessesSearchField) {
		[self _updateServerProcessesFilterForFilterString:[object stringValue]];
	}
	else if (object == customIntervalTextField) {
		[customIntervalButton setEnabled:(([[customIntervalTextField stringValue] length] > 0) && ([customIntervalTextField integerValue] > 0))];
	}
}

#pragma mark -
#pragma mark Window delegate methods

/**
 * Kill the auto refresh timer if it's running.
 */
- (void)windowWillClose:(NSNotification *)notification
{	
	// If the filtered array is allocated and it's not a reference to the processes array get rid of it
	if (processesFiltered && processesFiltered != processes) {
		processesFiltered = nil;
	}
	
	// Kill the auto refresh timer if running
	[self _killAutoRefreshTimer];	
}

#pragma mark -
#pragma mark Private API

/**
 * Called by the background thread on the main thread once it has completed getting the list of processes.
 */
- (void)_processListRefreshed
{
	processListThreadRunning = NO;
	
	// Reapply any filters is required
	if ([[filterProcessesSearchField stringValue] length] > 0) {
		[self _updateServerProcessesFilterForFilterString:[filterProcessesSearchField stringValue]];
	}
	
	// Reset sort descriptors
	[processesFiltered sortUsingDescriptors:[processListTableView sortDescriptors]];
	
	// Reload data
	[processListTableView reloadData];
	
	// Enable controls
	[filterProcessesSearchField setEnabled:YES];
	[saveProcessesButton setEnabled:YES];
	[refreshProcessesButton setEnabled:(![autoRefreshButton state])];
	
	// Stop progress Indicator
	[refreshProgressIndicator stopAnimation:self];
	[refreshProgressIndicator setHidden:YES];
}

/**
 * Starts the auto refresh timer.
 */
- (void)_startAutoRefreshTimer
{		
	autoRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:[prefs doubleForKey:SPProcessListAutoRrefreshInterval] target:self selector:@selector(_fireAutoRefresh:) userInfo:nil repeats:YES];
}

/**
 * Kills the auto refresh timer.
 */
- (void)_killAutoRefreshTimer
{
	// If the auto refresh timer is running, kill it
	if (autoRefreshTimer && [autoRefreshTimer isValid]) {		
		[autoRefreshTimer invalidate];
		
	}
}

/**
 * Refreshes the process list when called by the auto refesh timer.
 */
- (void)_fireAutoRefresh:(NSTimer *)timer
{	
	[self refreshProcessList:self];
}

/**
 *
 */
- (void)_updateSelectedAutoRefreshIntervalInterface
{	
	BOOL found = NO;
	NSInteger interval = [prefs integerForKey:SPProcessListAutoRrefreshInterval];
	
	NSArray *items = [[autoRefreshIntervalMenuItem submenu] itemArray];
	
	// Uncheck all items
	for (NSMenuItem *item in items)
	{
		[item setState:NSOffState];
	}
	
	// Check the selected item
	for (NSMenuItem *item in items)
	{ 		
		if (interval == [item tag]) {
			found = YES;
			[item setState:NSOnState];
			break;
		}
	}
	
	// If a match wasn't found then a custom value is set
	if (!found) [(NSMenuItem*)[items objectAtIndex:([items count] - 1)] setState:NSOnState];
}

/**
 * Starts the auto refresh time with the supplied time interval.
 */
- (void)_startAutoRefreshTimerWithInterval:(NSTimeInterval)interval
{
	[prefs setDouble:interval forKey:SPProcessListAutoRrefreshInterval];
	
	// Update the interface
	[self _updateSelectedAutoRefreshIntervalInterface];
	
	// Kill the timer and restart it with the new interval
	[self _killAutoRefreshTimer];
	[self _startAutoRefreshTimer];
}

/**
 * Gets a list of current database processed on a background thread.
 */
- (void)_getDatabaseProcessListInBackground:(id)object;
{	
	@autoreleasepool {
		NSUInteger i = 0;

		// Get processes
		if ([connection isConnected]) {

			SPMySQLResult *processList = (showFullProcessList) ? [connection queryString:@"SHOW FULL PROCESSLIST"] : [connection listProcesses];

			[processList setReturnDataAsStrings:YES];

			[[processes onMainThread] removeAllObjects];

			for (i = 0; i < [processList numberOfRows]; i++)
			{
				//SPMySQL.framewokr currently returns numbers as NSString, which will break sorting of numbers in this case.
				NSMutableDictionary *rowsFixed = [[processList getRowAsDictionary] mutableCopy];

				// The ID can be a 64-bit value on 64-bit servers
				id idColumn = [rowsFixed objectForKey:@"Id"];
				if (idColumn != nil && [idColumn isKindOfClass:[NSString class]]) {
					long long numRaw = [(NSString *)idColumn longLongValue];
					NSNumber *num = [NSNumber numberWithLongLong:numRaw];
					[rowsFixed setObject:num forKey:@"Id"];
				}

				// Time is a signed int(7) - this is a 32 bit int value
				id timeColumn = [rowsFixed objectForKey:@"Time"];
				if(timeColumn != nil && [timeColumn isKindOfClass:[NSString class]]) {
					int numRaw = [(NSString *)timeColumn intValue];
					NSNumber *num = [NSNumber numberWithInt:numRaw];
					[rowsFixed setObject:num forKey:@"Time"];
				}

				// This is pretty bad from a performance standpoint, but we must not
				// interfere with the NSTableView's reload cycle and there is no way
				// to know when it starts/ends. We only know it will happen on the
				// main thread, so we have to interlock with that.
				[[processes onMainThread] addObject:[rowsFixed copy]];
			}
		}

		// Update the UI on the main thread
		[self performSelectorOnMainThread:@selector(_processListRefreshed) withObject:nil waitUntilDone:NO];
	}
}

/**
 * Attempts to kill the query executing on the connection associate with the supplied ID.
 */
- (void)_killProcessQueryWithId:(long long)processId
{
	// Kill the query
	if ([[connection serverVersionString] rangeOfString:@"TiDB"].location != NSNotFound) {
		[connection queryString:[NSString stringWithFormat:@"KILL TIDB QUERY %lld", processId]];
	}
	else {
		[connection queryString:[NSString stringWithFormat:@"KILL QUERY %lld", processId]];
	}
	
	// Check for errors
	if ([connection queryErrored]) {
		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Unable to kill query", @"error killing query message") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while attempting to kill the query associated with connection %lld.\n\nMySQL said: %@", @"error killing query informative message"), processId, [connection lastErrorMessage]] callback:nil];
	}
	
	// Refresh the process list
	[self refreshProcessList:self];
}

/**
 * Attempts the kill the connection associated with the supplied ID.
 */
- (void)_killProcessConnectionWithId:(long long)processId
{
	// Kill the connection
	if ([[connection serverVersionString] rangeOfString:@"TiDB"].location != NSNotFound) {
		[connection queryString:[NSString stringWithFormat:@"KILL TIDB CONNECTION %lld", processId]];
	}
	else {
		[connection queryString:[NSString stringWithFormat:@"KILL CONNECTION %lld", processId]];
	}
	
	// Check for errors
	if ([connection queryErrored]) {
		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Unable to kill connection", @"error killing connection message") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while attempting to kill connection %lld.\n\nMySQL said: %@", @"error killing query informative message"), processId, [connection lastErrorMessage]] callback:nil];
	}
	
	// Refresh the process list
	[self refreshProcessList:self];
}

/**
 * Filter the displayed server processes against the supplied filter string.
 */
- (void)_updateServerProcessesFilterForFilterString:(NSString *)filterString
{
	[saveProcessesButton setEnabled:NO];
		
	filterString = [[filterString lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	// If the filtered array is allocated and its not a reference to the processes array,
	// relase it to prevent memory leaks upon the next allocation.
	if (processesFiltered && processesFiltered != processes) {
		processesFiltered = nil;
	}
	
	processesFiltered = [[NSMutableArray alloc] init];
	
	if ([filterString length] == 0) {
		processesFiltered = processes;
		
		[saveProcessesButton setEnabled:YES];
		[saveProcessesButton setTitle:NSLocalizedString(@"Save As...", @"save as button title")];
		[processesCountTextField setStringValue:@""];
		
		[processListTableView reloadData];
		
		return;
	}
	
	// Perform filtering
	for (NSDictionary *process in processes) 
	{
		if (([[[process objectForKey:@"Id"] stringValue] rangeOfString:filterString options:NSCaseInsensitiveSearch].location != NSNotFound) ||
			([[process objectForKey:@"User"] rangeOfString:filterString options:NSCaseInsensitiveSearch].location != NSNotFound) ||
			([[process objectForKey:@"Host"] rangeOfString:filterString options:NSCaseInsensitiveSearch].location != NSNotFound) ||
			((![[process objectForKey:@"db"] isNSNull]) && ([[process objectForKey:@"db"] rangeOfString:filterString options:NSCaseInsensitiveSearch].location != NSNotFound)) ||
			([[process objectForKey:@"Command"] rangeOfString:filterString options:NSCaseInsensitiveSearch].location != NSNotFound) ||
			((![[process objectForKey:@"Time"] isNSNull]) && ([[[process objectForKey:@"Time"] stringValue] rangeOfString:filterString options:NSCaseInsensitiveSearch].location != NSNotFound)) ||
			((![[process objectForKey:@"State"] isNSNull]) && ([[process objectForKey:@"State"] rangeOfString:filterString options:NSCaseInsensitiveSearch].location != NSNotFound)) ||
			((![[process objectForKey:@"Info"] isNSNull]) && ([[process objectForKey:@"Info"] rangeOfString:filterString options:NSCaseInsensitiveSearch].location != NSNotFound)))
		{
			[processesFiltered addObject:process];
		}
	}
	
	[processListTableView reloadData];
	
	[processesCountTextField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Showing %lu of %lu processes", "filtered item count"), (unsigned long)[processesFiltered count], (unsigned long)[processes count]]];
	[processesCountTextField setHidden:NO];
	
	if ([processesFiltered count] == 0) return;
	
	[saveProcessesButton setEnabled:YES];
	[saveProcessesButton setTitle:NSLocalizedString(@"Save View As...", @"save view as button title")];
}

/**
 * Add any necessary preference observers to allow live updating on changes.
 */
- (void)_addPreferenceObservers
{
	// Register as an observer for font changes
	[prefs addObserver:self forKeyPath:SPGlobalFontSettings options:NSKeyValueObservingOptionNew context:nil];

	// Register to obeserve table view vertical grid line pref changes
	[prefs addObserver:self forKeyPath:SPDisplayTableViewVerticalGridlines options:NSKeyValueObservingOptionNew context:NULL];
}

/**
 * Remove any previously added preference observers.
 */
- (void)_removePreferenceObservers
{
	[prefs removeObserver:self forKeyPath:SPGlobalFontSettings];
	[prefs removeObserver:self forKeyPath:SPDisplayTableViewVerticalGridlines];
}

#pragma mark - SPProcessListControllerDataSource

#pragma mark Tableview delegate methods

/**
 * Table view delegate method. Returns the number of rows in the table veiw.
 */
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [processesFiltered count];
}

/**
 * Table view delegate method. Returns the specific object for the request column and row.
 */
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	id object = ((NSUInteger)row < [processesFiltered count]) ? [[processesFiltered objectAtIndex:row] valueForKey:[tableColumn identifier]] : @"";

	if ([object isNSNull]) {
		return [prefs stringForKey:SPNullValue];
	}

	// If the string is exactly 100 characters long, and FULL process lists are not enabled, it's a safe
	// bet that the string is truncated
	if (!showFullProcessList && [object isKindOfClass:[NSString class]] && [(NSString *)object length] == 100) {
		return [object stringByAppendingString:@"…"];
	}

	return object;
}

/**
 * Table view delegate method. Called when the user changes the sort by column.
 */
- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
	[processesFiltered sortUsingDescriptors:[tableView sortDescriptors]];

	[tableView reloadData];
}

/**
 * Table view delegate method. Called whenever the user changes a column width.
 */
- (void)tableViewColumnDidResize:(NSNotification *)notification
{
	NSTableColumn *column = [[notification userInfo] objectForKey:@"NSTableColumn"];

	// Get the existing table column widths dictionary if it exists
	NSMutableDictionary *tableColumnWidths = ([prefs objectForKey:SPProcessListTableColumnWidths]) ?
	[NSMutableDictionary dictionaryWithDictionary:[prefs objectForKey:SPProcessListTableColumnWidths]] :
	[NSMutableDictionary dictionary];

	// Save column size
	NSString *columnName = [[column headerCell] stringValue];

	if (columnName) {
		[tableColumnWidths setObject:[NSNumber numberWithDouble:[column width]] forKey:columnName];

		[prefs setObject:tableColumnWidths forKey:SPProcessListTableColumnWidths];
	}
}

#pragma mark -

- (void)dealloc
{
	processListThreadRunning = NO;

	[self _removePreferenceObservers];

}

@end
