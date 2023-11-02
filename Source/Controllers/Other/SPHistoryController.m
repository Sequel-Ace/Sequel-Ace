//
//  SPHistoryController.m
//  sequel-pro
//
//  Created by Rowan Beentje on July 23, 2009.
//  Copyright (c) 2008 Rowan Beentje. All rights reserved.
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

#import "SPDatabaseDocument.h"
#import "SPTableContent.h"
#import "SPTablesList.h"
#import "SPHistoryController.h"
#import "SPThreadAdditions.h"
#import "sequel-ace-Swift.h"


@interface SPHistoryController ()

- (void)loadEntryStart:(SPTableHistoryEntry *)entry;
- (void)loadEntryTaskWithEntry:(SPTableHistoryEntry *)entry;
- (void)loadEntryFromMenuItem:(NSMenuItem *)item;
- (SPTableHistoryEntry *)buildEntry;
- (void)doRetoreViewState:(SPTableHistoryEntry *)entry;
- (void)updateToolbarItem;
- (void)updateHistoryEntriesWithUpdateToolbarItem:(BOOL)updateMenuItems;

// handling notifications
- (void)startDocumentTask:(NSNotification *)aNotification;
- (void)endDocumentTask:(NSNotification *)aNotification;
- (void)toolbarDidRemoveItem:(NSNotification *)aNotification;
- (void)toolbarWillAddItem:(NSNotification *)aNotification;

@end

@implementation SPHistoryController

@synthesize modifyingState;
@synthesize navigatingFK;

#pragma mark - Setup and teardown

/**
 * Initialise by creating a blank history array.
 */
- (id)init {
	if ((self = [super init])) {
		tableContentStates = [[NSMutableDictionary alloc] init];
		historyManager = [[SPTableHistoryManager alloc] init];
		modifyingState = NO;
		navigatingFK = NO;
	}
	return self;
}

- (void)awakeFromNib {
	[super awakeFromNib];
	tableContentInstance = [theDocument tableContentInstance];
	tablesListInstance = [theDocument tablesListInstance];
	toolbarItemVisible = NO;

	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver: self selector: @selector(toolbarWillAddItem:) name: NSToolbarWillAddItemNotification object: theDocument.mainToolbar];
	[nc addObserver: self selector: @selector(toolbarDidRemoveItem:) name: NSToolbarDidRemoveItemNotification object: theDocument.mainToolbar];
	[nc addObserver: self selector: @selector(startDocumentTask:) name: SPDocumentTaskStartNotification object: theDocument];
	[nc addObserver: self selector: @selector(endDocumentTask:) name: SPDocumentTaskEndNotification object: theDocument];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver: self];
}

#pragma mark - Interface interaction

- (NSUInteger)countPrevious {
	return historyManager.countPrevious;
}

- (NSUInteger)countForward {
	return historyManager.countForward;
}

/**
 * Updates the toolbar item to reflect the current history state and position
 */
- (void)updateToolbarItem {
	// If the toolbar item isn't visible, don't perform any actions - as manipulating
	// items not on the toolbar can cause crashes.
	if (!toolbarItemVisible || !historyControl) { return; }

	// Set the active state of the segments if appropriate
	[historyControl setEnabled: historyManager.countPrevious > 0 forSegment: 0];
	[historyControl setEnabled: historyManager.countForward > 0 forSegment: 1];

	// Generate back and forward menus as appropriate to reflect the new state
	[historyControl setMenu: menuForEntries(historyManager.backEntries, self) forSegment: 0];
	[historyControl setMenu: menuForEntries(historyManager.forwardEntries, self) forSegment: 1];
}

/**
 * Go backward in the history.
 */
- (void)goBackInHistory {
	[self loadEntryStart: historyManager.peakPrevious];
}

/**
 * Go forward in the history.
 */
- (void)goForwardInHistory {
	[self loadEntryStart: historyManager.peakForward];
}

/**
 * Trigger a navigation action in response to a click
 */
- (IBAction)historyControlClicked:(NSSegmentedControl *)theControl {
	// Ensure history navigation is permitted - trigger end editing and any required saves
	if (![theDocument couldCommitCurrentViewActions]) { return; }

	if ([theControl respondsToSelector:@selector(selectedSegment)]) {
		switch ([theControl selectedSegment]) {
			case 0: // Back button clicked:
				[self goBackInHistory];
				break;
			case 1: // Forward button clicked:
				[self goForwardInHistory];
				break;
		}
	}
	else {
		SPLog(@"theControl does not respondToSelector: selectedSegment. theControl class: %@", [theControl class]);
	}
}

/**
 * Set up the toolbar items as appropriate.
 * State tracking is necessary as manipulating items not on the toolbar can cause crashes.
 */
- (void)setupInterface {
	NSArray *toolbarItems = [theDocument.mainToolbar items];
	for (NSToolbarItem *toolbarItem in toolbarItems) {
		if ([[toolbarItem itemIdentifier] isEqualToString:SPMainToolbarHistoryNavigation]) {
			toolbarItemVisible = YES;
			break;
		}
	}
}

/**
 * Disable the controls during a task.
 */
- (void)startDocumentTask:(NSNotification *)aNotification {
	if (toolbarItemVisible) [historyControl setEnabled:NO];
}

/**
 * Enable the controls once a task has completed.
 */
- (void)endDocumentTask:(NSNotification *)aNotification {
	if (toolbarItemVisible) [historyControl setEnabled:YES];
}

/**
 * Update the state when the item is added from the toolbar.
 * State tracking is necessary as manipulating items not on the toolbar can cause crashes.
 */
- (void)toolbarWillAddItem:(NSNotification *)aNotification {
	if ([[[[aNotification userInfo] objectForKey:@"item"] itemIdentifier] isEqualToString: SPMainToolbarHistoryNavigation]) {
		toolbarItemVisible = YES;
		[self performSelectorOnMainThread:@selector(updateToolbarItem) withObject: nil waitUntilDone: YES];
	}
}

/**
 * Update the state when the item is removed from the toolbar
 * State tracking is necessary as manipulating items not on the toolbar can cause crashes.
 */
- (void)toolbarDidRemoveItem:(NSNotification *)aNotification {
	if ([[[[aNotification userInfo] objectForKey:@"item"] itemIdentifier] isEqualToString: SPMainToolbarHistoryNavigation]) {
		toolbarItemVisible = NO;
	}
}

#pragma mark - Adding or updating history entries

- (void)updateHistoryEntries {
	[self updateHistoryEntriesWithUpdateToolbarItem: YES];
}

/**
 * Call to store or update a history item for the document state. Checks against
 * the latest stored details; if they match, a new history item is not created.
 * This should therefore be called without worry of duplicates.
 * Table histories are created per table/filter setting, and while view changes
 * update the current history entry, they don't replace it.
 */
- (void)updateHistoryEntriesWithUpdateToolbarItem:(BOOL)updateMenuItems {
	SPLog(@"updateHistoryEntries");
	// Don't modify anything if we're in the process of restoring an old history state
	if (modifyingState) { return; }

	// Work out the current document details
	SPTableHistoryEntry *newEntry = [[self onMainThread] buildEntry];
	if (!newEntry.database) { return; }

	// If a table is selected, update the table content states with this information - used when switching tables to restore last used view.
	if (newEntry.table) {
		NSString * const key = [NSString stringWithFormat:@"%@.%@", newEntry.database.backtickQuotedString, newEntry.table.backtickQuotedString];
		[tableContentStates setObject: newEntry forKey: key];
	}

	if (canCurrentReplaceEntry(historyManager.peakCurrent, newEntry)) {
		[historyManager replaceTopWithEntry: newEntry];
	}
	else {
		[historyManager push: newEntry];
	}

	if (updateMenuItems) {
		[[self onMainThread] updateToolbarItem];
	}
}

- (SPTableHistoryEntry *)buildEntry {
	return [[SPTableHistoryEntry alloc] initWithDatabase: theDocument.database
												   table: theDocument.table
													view: theDocument.currentlySelectedView
												viewPort: tableContentInstance.viewport
									  contentSortColName: tableContentInstance.sortColumnName
									 contentSortColIsAsc: tableContentInstance.sortColumnIsAscending
									   contentPageNumber: tableContentInstance.pageNumber
											selectedRows: [tableContentInstance selectionDetailsAllowingIndexSelection: YES]
											activeFilter: tableContentInstance.activeFilter
												  filter: tableContentInstance.filterSettings
											  filterData: tableContentInstance.filterTableData];
}

#pragma mark - Loading history entries

/**
 * Load a history entry and attempt to return the interface to that state.
 * Performs the load in a task which is threaded as necessary.
 */
- (void)loadEntryStart:(SPTableHistoryEntry *)entry {
	// Sanity check the input
	if (entry == nil) {
		NSBeep();
		return;
	}

	// Ensure a save of the current state - scroll position, selection
	// Don't update menu items since we'll be shuffling history around anyways; updated in loadEntryTaskWithEntry
	[self updateHistoryEntriesWithUpdateToolbarItem: NO];

	// Start the task and perform the load
	[theDocument startTaskWithDescription:NSLocalizedString(@"Loading history entry...", @"Loading history entry task desc")];
	if ([NSThread isMainThread]) {
		[NSThread detachNewThreadWithName: SPCtxt(@"SPHistoryController load of history entry", theDocument)
								   target: self
								 selector: @selector(loadEntryTaskWithEntry:)
								   object: entry];
	} else {
		[self loadEntryTaskWithEntry: entry];
	}
}

- (void)loadEntryTaskWithEntry:(SPTableHistoryEntry *)entry {
	@autoreleasepool {
		modifyingState = YES;
		[self doRetoreViewState: entry];

		// If the database, table, and view are the same and content - just trigger a table reload (filters)
		if (
			[theDocument.database isEqualToString: entry.database]
			&& entry.table
			&& [theDocument.table isEqualToString: entry.table]
			&& theDocument.currentlySelectedView == SPTableViewContent
			&& theDocument.currentlySelectedView == entry.view
		) {
			[tableContentInstance loadTable: entry.table];
			return completeLoadEntry(self, entry);
		}

		// If the same table was selected, mark the content as requiring a reload
		if (entry.table && [theDocument.table isEqualToString: entry.table]) {
			[theDocument setContentRequiresReload: YES];
		}

		// Update the database and table name if necessary
		[theDocument selectDatabase: entry.database item: entry.table];

		// If the database or table couldn't be selected, error.
		if (
			( ![theDocument.database isEqualToString: entry.database] && (theDocument.database || entry.database) )
			|| ( ![theDocument.table isEqualToString: entry.table] && (theDocument.table || entry.table) )
		) {
			return abortEntryLoad(self);
		}

		// Check and set the view
		if (theDocument.currentlySelectedView != entry.view) {
			switch (entry.view) {
				case SPTableViewStructure:
					[theDocument viewStructure];
					break;
				case SPTableViewContent:
					[theDocument viewContent];
					break;
				case SPTableViewCustomQuery:
					[theDocument viewQuery];
					break;
				case SPTableViewStatus:
					[theDocument viewStatus];
					break;
				case SPTableViewRelations:
					[theDocument viewRelations];
					break;
				case SPTableViewTriggers:
					[theDocument viewTriggers];
					break;
			}

			if (theDocument.currentlySelectedView != entry.view) {
				return abortEntryLoad(self);
			}
		}

		completeLoadEntry(self, entry);
	}
}

/**
 * Load a history entry from an associated menu item
 */
- (void)loadEntryFromMenuItem:(NSMenuItem *)item {
	[self loadEntryStart: item.representedObject];
}

#pragma mark - Restoring view states

/**
 * Check saved view states for the currently selected database and table (if any), and restore them if present.
 */
- (void)restoreViewStates {
	// Return if the history state is currently being modified
	if (modifyingState) { return; }

	// Return (and disable navigatingFK), if we are navigating using a Foreign-Key button
	if (navigatingFK) {
		navigatingFK = NO;
		return;
	}

	NSString *theDatabase = theDocument.database;
	NSString *theTable = theDocument.table;

	// Return if no database or table are selected
	if (!theDatabase || !theTable) { return; }

	// Retrieve the saved content state, returning if none was found
	NSString * const key = [NSString stringWithFormat:@"%@.%@", theDatabase.backtickQuotedString, theTable.backtickQuotedString];
	SPTableHistoryEntry *entry = (SPTableHistoryEntry *)[tableContentStates objectForKey: key];
	if (!entry) { return; }

	[self doRetoreViewState: entry];
}

- (void)doRetoreViewState:(SPTableHistoryEntry *)entry {
	// Restore the content view state
	[tableContentInstance setSortColumnNameToRestore: entry.contentSortColName isAscending: entry.contentSortColIsAsc];
	[tableContentInstance setPageToRestore: entry.contentPageNumber];
	[tableContentInstance setSelectionToRestore: entry.selectedRows];
	[tableContentInstance setViewportToRestore: entry.viewPort];
	[tableContentInstance setFiltersToRestore: entry.filter];
	[tableContentInstance setActiveFilterToRestore: (SPTableContentFilterSource)entry.activeFilter];
}

#pragma mark - Private Helper c-Functions

static BOOL canCurrentReplaceEntry(SPTableHistoryEntry *curr, SPTableHistoryEntry *new) {
	// no entry to replace
	if (!curr) { return NO; }

	// databases don't match, can't replace entry.
	if (![curr.database isEqualToString: new.database]) { return NO; }

	// Special case: if current entry has no table, replace it. This improves history flow.
	if (!curr.table) { return YES; }

	// tables don't match, can't replace entry.
	if (![curr.table isEqualToString: new.table]) { return NO; }

	BOOL viewIsTheSame  = curr.view == new.view;
	// If filter settings haven't changed, entry can be replaced.
	// This updates navigation within a table, rather than creating a new entry every time detail is changed.
	if (!viewIsTheSame || (!curr.filter && !new.filter) || [curr.filter isEqualToDictionary: new.filter]) {
		return YES;
	}
	// views are the same, but the filter settings have changed, also store the position details on the *previous* history item
	else if (viewIsTheSame || (!curr.filter && new.filter) || ![curr.filter isEqualToDictionary: new.filter]) {
		curr.viewPort = new.viewPort;
		if (new.selectedRows) {
			curr.selectedRows = new.selectedRows;
		}
	}

	return NO;
}

static void abortEntryLoad(SPHistoryController *c) {
	NSBeep();
	c->modifyingState = NO;
	[[c onMainThread] updateToolbarItem];
	[c->theDocument endTask];
}

static void completeLoadEntry(SPHistoryController *c, SPTableHistoryEntry *entry) {
	[c->historyManager navigateTo: entry];
	c->modifyingState = NO;
	[[c onMainThread] updateToolbarItem];
	[c->theDocument endTask];
}

static NSMenu* menuForEntries(NSArray *entries, SPHistoryController *target) {
	if (entries == nil || entries.count == 0) { return nil; }

	NSMenu *menu = [[NSMenu alloc] init];
	for (NSInteger i = entries.count - 1; i >= 0; i--) {
		NSMenuItem *item = menuEntryFor(entries[i], i, target);
		if (item.menu) {
			[item.menu removeItem: item];
		}
		[menu addItem: item];
	}

	return menu;
}

static NSMenuItem* menuEntryFor(SPTableHistoryEntry *entry, NSInteger index, SPHistoryController *target) {
	if (entry.cachedMenuItem) {
		return entry.cachedMenuItem;
	}

	NSMenuItem *item = [[NSMenuItem alloc] init];
	[item setTitle: menuItemDescriptionFor(entry)];
	[item setTarget: target];
	[item setAction: @selector(loadEntryFromMenuItem:)];
	[item setTag: index];
	[item setRepresentedObject: entry];
	entry.cachedMenuItem = item;

	return item;
}

static NSString* menuItemDescriptionFor(SPTableHistoryEntry *entry) {
	if (!entry.database) {
		return NSLocalizedString(@"(no selection)", @"History item title with nothing selected");
	}

	NSMutableString *name = [NSMutableString stringWithString: entry.database];
	if (!entry.table || !entry.table.length) { return name; }

	[name appendFormat: @"/%@", entry.table];

	if (entry.filter) {
		name = [NSMutableString stringWithFormat: NSLocalizedString(@"%@ (Filtered)", @"History item filtered by values label"), name];
	}

	if (entry.contentPageNumber > 0) {
		unsigned long num = entry.contentPageNumber;
		name = [NSMutableString stringWithFormat: NSLocalizedString(@"%@ (Page %lu)", @"History item with page number label"), name, num];
	}

	return name;
}

@end
