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
static NSString *SPTableViewProgressColumnIdentifier = @"Progress";

static NSString * const SPKillModeKey = @"SPKillMode";
static NSString * const SPKillIdKey   = @"SPKillId";

// Formal conformance for methods AppKit moved off the informal NSObject
// categories; implementing them without it is deprecated. No behavior change.
@interface SPProcessListController () <NSMenuItemValidation, NSControlTextEditingDelegate>
@property (nonatomic, readwrite, strong) SAClaudeProcessListSession *processListSession;
/// The triage view over the XIB's (hidden) views: chips, list, detail panel.
@property (nonatomic, strong) SAClaudeProcessListContent *processListContent;
- (SAClaudeProcessListSession *)_openSessionIfNeeded;
- (void)_processListRefreshed;
- (BOOL)_isContextMenuItem:(id)sender;
- (void)_startAutoRefreshTimer;
- (void)_killAutoRefreshTimer;
- (void)_fireAutoRefresh:(NSTimer *)timer;
- (void)_updateSelectedAutoRefreshIntervalInterface;
- (void)_startAutoRefreshTimerWithInterval:(NSTimeInterval)interval;
- (void)_addPreferenceObservers;
- (void)_removePreferenceObservers;
+ (NSString *)_serializedProcessRow:(NSDictionary *)process includeProgress:(BOOL)includeProgress;

@end

@implementation SPProcessListController

@synthesize connection;
@synthesize processListSession;
@synthesize processListContent;

#pragma mark -
#pragma mark Serialization

+ (NSString *)_serializedProcessRow:(NSDictionary *)process includeProgress:(BOOL)includeProgress
{
	if (![process isKindOfClass:[NSDictionary class]]) return @"";

	return [SPProcessListRowSerializer serializedProcessRow:process includeProgress:includeProgress];
}

#pragma mark -
#pragma mark Initialisation

- (instancetype)init
{
	if ((self = [super initWithWindowNibName:@"DatabaseProcessList"])) {
		
		autoRefreshTimer = nil;
		processListThreadRunning = NO;
		
		processes = [[NSMutableArray alloc] init];
		
		prefs = [NSUserDefaults standardUserDefaults];
		
		// The list always fetches SHOW FULL PROCESSLIST (the "Show FULL list" option is retired).
		showFullProcessList = YES;
	}
	
	return self;
}

- (void)awakeFromNib
{	
    [super awakeFromNib];
    
	[[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Server Processes on %@", @"server processes window title (var = hostname)"),[[SPAppDelegate frontDocument] name]]];
	
	[self setWindowFrameAutosaveName:@"ProcessList"];
	
	// Show/hide table columns (the old table stays loaded, hidden, under the triage view)
  [[processListTableView tableColumnWithIdentifier:SPTableViewProgressColumnIdentifier] setHidden:![connection isMariaDB]];
	
	// Set the process table view's vertical gridlines if required
	[processListTableView setGridStyleMask:([prefs boolForKey:SPDisplayTableViewVerticalGridlines]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];

	NSFont *tableFont = [NSUserDefaults getFont];
	[processListTableView setRowHeight:4.0f + NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];

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

	// The triage view (chips, list, detail panel) over the XIB's views; the gear keeps Auto Refresh Interval and
	// gains Save As…; the right-click menu moves to the new list.
	processListContent = [SAClaudeProcessListContent installInWindow:[self window] controller:self autoRefreshIntervalItem:autoRefreshIntervalMenuItem contextMenu:[processListTableView menu]];
}

/**
 * Interface loading
 */
- (void)windowDidLoad
{
	// Update the selected auto refresh interval
	[self _updateSelectedAutoRefreshIntervalInterface];
    [super windowDidLoad];
}

#pragma mark -
#pragma mark IB action methods

/**
 * Copies the currently selected process(es) to the pasteboard.
 */
- (IBAction)copy:(id)sender
{	
	// The right-click menu acts on the clicked row (or the selection it is part of); the Edit menu on the selection
	// while the list has the focus.
	BOOL fromContextMenu = [self _isContextMenuItem:sender];
	if (!fromContextMenu && ![processListContent listIsFirstResponder]) return;

	NSArray<NSDictionary *> *rows = [processListContent rowsToCopyFromContextMenu:fromContextMenu];

	if ([rows count] > 0) {
		
		NSMutableString *string = [NSMutableString string];
		
		for (NSDictionary *process in rows)
		{
			NSString *stringTmp = [SPProcessListController _serializedProcessRow:process includeProgress:[connection isMariaDB]];
			
			[string appendString:stringTmp];
			[string appendString:@"\n"];
		}
		
		NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
		
		// Copy the string to the pasteboard
		[pasteBoard declareTypes:@[NSPasteboardTypeString] owner:nil];
		[pasteBoard setString:string forType:NSPasteboardTypeString];
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
	// Only proceed if there is not already a refresh running. The session runs it on the Process List's own
	// connection, so the document being busy no longer blocks it (on the shared fallback the session skips it).
	if (processListThreadRunning) return;

	// No session while the window is closed (e.g. a kill finishing after close): nothing to refresh
	SAClaudeProcessListSession *session = processListSession;
	if (!session) return;
	
	// The triage view shows a spinner if it takes a moment (it gets the rows from the session itself)
	[processListContent refreshStarted];
	
	processListThreadRunning = YES;

	[session refreshWithCompletion:^(NSArray<NSDictionary<NSString *, id> *> *rows) {
		// A completion from a session whose window has since closed (and perhaps reopened on a new session) writes
		// nothing: windowWillClose: already cleared the running flag.
		if (session != self->processListSession) return;

		// nil: skipped or failed — keep the current list
		if (rows) [self->processes setArray:rows];

		[self _processListRefreshed];
	}];
}

/**
 * Saves the process list to the selected file.
 */
- (IBAction)saveServerProcesses:(id)sender
{
	// What the list shows now (chip and search applied), in its order
	NSArray<NSDictionary *> *shownProcesses = [processListContent shownRows];

	NSSavePanel *panel = [NSSavePanel savePanel];
		
	[panel setExtensionHidden:NO];
	[panel setAllowsOtherFileTypes:YES];
	[panel setCanSelectHiddenExtension:YES];
	
    [panel setNameFieldStringValue:@"ServerProcesses"];
    [panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger returnCode) {
        if (returnCode == NSModalResponseOK) {
            if ([shownProcesses count] > 0) {
                NSMutableString *processesString = [NSMutableString stringWithFormat:@"# MySQL server processes for %@\n\n", [[SPAppDelegate frontDocument] host]];
                
                for (NSDictionary *process in shownProcesses)
                {
                    NSString *stringTmp = [SPProcessListController _serializedProcessRow:process includeProgress:[self->connection isMariaDB]];
                    
                    [processesString appendString:stringTmp];
                    [processesString appendString:@"\n"];
                }
                
                [processesString writeToURL:[panel URL] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            }
        }
    }];
}

/**
 * Kills the query of the clicked (or selected) connection, by the id that row shows.
 */
- (IBAction)killProcessQuery:(id)sender {
	[processListContent killQueryFromContextMenu:[self _isContextMenuItem:sender]];
}

/**
 * Kills the clicked (or selected) connection, by the id that row shows.
 */
- (IBAction)killProcessConnection:(id)sender {
	[processListContent killConnectionFromContextMenu:[self _isContextMenuItem:sender]];
}

- (void)killQueryOnConnectionId:(long long)processId shownQuery:(NSString *)shownQuery
{
	[processListSession confirmAndKillQueryOnConnectionId:processId shownQuery:shownQuery didFinish:^{
		[self refreshProcessList:self];
	}];
}

- (void)killConnectionWithConnectionId:(long long)processId
{
	[processListSession confirmAndKillConnectionWithId:processId didFinish:^{
		[self refreshProcessList:self];
	}];
}

/**
 * Toggles whether or not auto refresh is enabled (the XIB's hidden checkbox).
 */
- (IBAction)toggleProcessListAutoRefresh:(NSButton *)sender
{
	[self setAutoRefreshEnabled:([sender state] == NSControlStateValueOn)];
}

- (void)setAutoRefreshEnabled:(BOOL)enable
{
	[prefs setBool:enable forKey:SPProcessListEnableAutoRefresh];
	[processListContent autoRefreshChanged:enable];

	// One timer at most
	[self _killAutoRefreshTimer];
	if (enable) [self _startAutoRefreshTimer];
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

	// Load the window (and the triage view) first
	[self window];

	// Open the Process List's own connection (closed again in windowWillClose:)
	[self _openSessionIfNeeded];
	[processListContent attachSession:processListSession user:[connection username]];

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
		BOOL fromContextMenu = [self _isContextMenuItem:menuItem];
		if (!fromContextMenu && ![processListContent listIsFirstResponder]) return NO;
		return ([[processListContent rowsToCopyFromContextMenu:fromContextMenu] count] > 0);
	}
	
	// Exactly one connection, still listed (an ended one can't be killed)
	if ((action == @selector(killProcessQuery:)) || (action == @selector(killProcessConnection:))) {
		return [processListContent canKillFromContextMenu:[self _isContextMenuItem:menuItem]];
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

		[processListTableView setRowHeight:4.0f + NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];
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
	
	// (The XIB's search field is hidden: the triage view searches.)
	if (object == customIntervalTextField) {
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

	// Close the Process List's own connection; the next display opens a new one. A refresh still in flight belongs
	// to the closing session: its completion is ignored, so the flag mustn't hold up the next opening's first refresh.
	[processListSession close];
	processListSession = nil;
	processListThreadRunning = NO;
	[processListContent detachSession];
}

#pragma mark -
#pragma mark Private API

/**
 * Called by the background thread on the main thread once it has completed getting the list of processes.
 */
- (void)_processListRefreshed
{
	processListThreadRunning = NO;
	
	// The triage view already has the rows (from the session); the old table stays hidden
	[processListContent refreshFinished];
}

/**
 * Whether sender is an item of the list's right-click menu (it acts on the clicked row).
 */
- (BOOL)_isContextMenuItem:(id)sender
{
	return [sender isKindOfClass:[NSMenuItem class]] && [(NSMenuItem *)sender menu] == [processListTableView menu];
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
		[item setState:NSControlStateValueOff];
	}
	
	// Check the selected item
	for (NSMenuItem *item in items)
	{ 		
		if (interval == [item tag]) {
			found = YES;
			[item setState:NSControlStateValueOn];
			break;
		}
	}
	
	// If a match wasn't found then a custom value is set
	if (!found) [(NSMenuItem*)[items objectAtIndex:([items count] - 1)] setState:NSControlStateValueOn];
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
 * The Process List's own connection, opened when the window is displayed and closed with the window.
 */
- (SAClaudeProcessListSession *)_openSessionIfNeeded
{
	if (!processListSession && connection) {
		SPMySQLConnection *documentConnection = connection;

		processListSession = [[SAClaudeProcessListSession alloc] initWithDocumentConnection:documentConnection documentIsBusy:^BOOL{
			return [(SPDatabaseDocument *)[documentConnection delegate] isWorking];
		}];
		[processListSession open];
	}

	return processListSession;
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

	[processListSession close];

	[self _removePreferenceObservers];

}

@end
