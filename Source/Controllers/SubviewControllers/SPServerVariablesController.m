//
//  SPServerVariablesController.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on November 13, 2009.
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

#import "SPServerVariablesController.h"
#import "SPDatabaseDocument.h"
#import "SPAppController.h"

#import <SPMySQL/SPMySQL.h>

#import "sequel-ace-Swift.h"

@interface SPServerVariablesController ()

- (void)_getDatabaseServerVariables;
- (void)_updateServerVariablesFilterForFilterString:(NSString *)filterString;
- (void)_copyServerVariablesToPasteboardIncludingName:(BOOL)name andValue:(BOOL)value;

@end

@implementation SPServerVariablesController

@synthesize connection;

#pragma mark -
#pragma mark Initialisation

- (instancetype)init
{
	if ((self = [super initWithWindowNibName:@"DatabaseServerVariables"])) {
		variables = [[NSMutableArray alloc] init];

		prefs = [NSUserDefaults standardUserDefaults];
	}
	
	return self;
}

- (void)awakeFromNib
{
	// Set the process table view's vertical gridlines if required
	[variablesTableView setGridStyleMask:([prefs boolForKey:SPDisplayTableViewVerticalGridlines]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];

	NSFont *tableFont = [NSUserDefaults getFont];
	[variablesTableView setRowHeight:2.0f+NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];

	for (NSTableColumn *column in [variablesTableView tableColumns])
	{
		[[column dataCell] setFont:tableFont];
	}
	
	[self _addPreferenceObservers];
}

#pragma mark -
#pragma mark IBAction methods

/**
 * Copy implementation for server variables table view.
 */
- (IBAction)copy:(id)sender
{
	[self _copyServerVariablesToPasteboardIncludingName:YES andValue:YES];
}

/**
 * Copies the name(s) of the selected server variables.
 */
- (IBAction)copyServerVariableName:(id)sender
{
	[self _copyServerVariablesToPasteboardIncludingName:YES andValue:NO];
}

/**
 * Copies the value(s) of the selected server variables.
 */
- (IBAction)copyServerVariableValue:(id)sender
{
	[self _copyServerVariablesToPasteboardIncludingName:NO andValue:YES];
}

/**
 * Close the server variables sheet.
 */
- (IBAction)closeSheet:(id)sender
{
	[NSApp endSheet:[self window] returnCode:[sender tag]];
	[[self window] orderOut:self];
	
	// If the filtered array is allocated and it's not a reference to the processes array get rid of it
	if (variablesFiltered && variablesFiltered != variables) {
		variablesFiltered = nil;
	}		
}

/**
 * Saves the server variables to the selected file.
 */
- (IBAction)saveServerVariables:(id)sender
{
	NSSavePanel *panel = [NSSavePanel savePanel];
	
	[panel setAllowedFileTypes:@[@"cnf"]];

	[panel setExtensionHidden:NO];
	[panel setAllowsOtherFileTypes:YES];
	[panel setCanSelectHiddenExtension:YES];
	
    [panel setNameFieldStringValue:@"ServerVariables"];
    [panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger returnCode) {
        if (returnCode == NSModalResponseOK) {
            if ([self->variablesFiltered count] > 0) {
                NSMutableString *variablesString = [NSMutableString stringWithFormat:@"# MySQL server variables for %@\n\n", [[SPAppDelegate frontDocument] host]];
                
                for (NSDictionary *variable in self->variablesFiltered)
                {
                    [variablesString appendFormat:@"%@ = %@\n", [variable objectForKey:@"Variable_name"], [variable objectForKey:@"Value"]];
                }
                
                [variablesString writeToURL:[panel URL] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            }
        }
    }];
}

#pragma mark -
#pragma mark Other methods

/**
 * Displays the server variables sheet attached to the supplied window.
 */
- (void)displayServerVariablesSheetAttachedToWindow:(NSWindow *)window
{
	// Weak reference
	variablesFiltered = variables;
	
	// Get the variables
	[self _getDatabaseServerVariables];
	
	// Reload the tableview
	[variablesTableView reloadData];
	
	// If the search field already has value from when the panel was previously open, apply the filter.
	if ([[filterVariablesSearchField stringValue] length] > 0) {
		[self _updateServerVariablesFilterForFilterString:[filterVariablesSearchField stringValue]];
	}
	
	// Open the sheet
	[window beginSheet:self.window completionHandler:nil];
}

/**
 * Menu item validation.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	SEL action = [menuItem action];
	
	if (action == @selector(copy:)) {
		return ([variablesTableView numberOfSelectedRows] > 0);
	}
	
	// Copy selected server variable name(s)
	if ([menuItem action] == @selector(copyServerVariableName:)) {
		[menuItem setTitle:([variablesTableView numberOfSelectedRows] > 1) ? NSLocalizedString(@"Copy Variable Names", @"copy server variable names menu item") : NSLocalizedString(@"Copy Variable Name", @"copy server variable name menu item")];
		
		return ([variablesTableView numberOfSelectedRows] > 0);
	}
	
	// Copy selected server variable value(s)
	if ([menuItem action] == @selector(copyServerVariableValue:)) {
		[menuItem setTitle:([variablesTableView numberOfSelectedRows] > 1) ? NSLocalizedString(@"Copy Variable Values", @"copy server variable values menu item") : NSLocalizedString(@"Copy Variable Value", @"copy server variable value menu item")];
		
		return ([variablesTableView numberOfSelectedRows] > 0);
	}
	
	return YES;
}

/**
 * This method is called as part of Key Value Observing which is used to watch for prefernce changes which effect the interface.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{	
	// Display table veiew vertical gridlines preference changed
	if ([keyPath isEqualToString:SPDisplayTableViewVerticalGridlines]) {
        [variablesTableView setGridStyleMask:([[change objectForKey:NSKeyValueChangeNewKey] boolValue]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	}
	// Table font preference changed
	else if ([keyPath isEqualToString:SPGlobalFontSettings]) {
		NSFont *tableFont = [NSUserDefaults getFont];

		[variablesTableView setRowHeight:2.0f + NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];
		[variablesTableView setFont:tableFont];
		[variablesTableView reloadData];
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

#pragma mark -
#pragma mark Tableview delegate methods

/**
 * Table view delegate method. Returns the number of rows in the table veiw.
 */
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [variablesFiltered count];
}

/**
 * Table view delegate method. Returns the specific object for the request column and row.
 */
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{	
	return [[variablesFiltered objectAtIndex:row] valueForKey:[tableColumn identifier]];
}

#pragma mark -
#pragma mark Text field delegate methods

/**
 * Apply the filter string to the current variables list.
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
	id object = [notification object];
	
	if (object == filterVariablesSearchField) {
		[self _updateServerVariablesFilterForFilterString:[object stringValue]];
	}
}

#pragma mark -
#pragma mark Private API

/**
 * Gets the database's current server variables.
 */
- (void)_getDatabaseServerVariables
{
	// Get variables
	SPMySQLResult *serverVariables = [connection queryString:@"SHOW VARIABLES"];
	
	[serverVariables setReturnDataAsStrings:YES];
	
	[variables removeAllObjects];
	[variables addObjectsFromArray:[serverVariables getAllRows]];
}

/**
 * Filter the displayed server variables by matching the variable name and value against the
 * filter string.
 */
- (void)_updateServerVariablesFilterForFilterString:(NSString *)filterString
{
	[saveVariablesButton setEnabled:NO];
	
	filterString = [[filterString lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	// If the filtered array is allocated and its not a reference to the variables array
	// relase it to prevent memory leaks upon the next allocation.
	if (variablesFiltered && variablesFiltered != variables) {
		variablesFiltered = nil;
	}
	
	variablesFiltered = [[NSMutableArray alloc] init];
	
	if ([filterString length] == 0) {
		variablesFiltered = variables;
		
		[saveVariablesButton setEnabled:YES];
		[saveVariablesButton setTitle:@"Save As..."];
		[variablesCountTextField setStringValue:@""];
		
		[variablesTableView reloadData];
		
		return;
	}
	
	for (NSDictionary *variable in variables) 
	{
		if (([[variable objectForKey:@"Variable_name"] rangeOfString:filterString options:NSCaseInsensitiveSearch].location != NSNotFound) ||
			([[variable objectForKey:@"Value"] rangeOfString:filterString options:NSCaseInsensitiveSearch].location != NSNotFound))
		{
			[variablesFiltered addObject:variable];
		}
	}
	
	[variablesTableView reloadData];
	
	[variablesCountTextField setHidden:NO];
	[variablesCountTextField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%lu of %lu", "filtered item count"), (unsigned long)[variablesFiltered count], (unsigned long)[variables count]]];
	
	if ([variablesFiltered count] == 0) return;
	
	[saveVariablesButton setEnabled:YES];
	[saveVariablesButton setTitle:@"Save View As..."];
}

/**
 * Copies either the name or value or both (as name = value pairs) of the currently selected server variables.
 */
- (void)_copyServerVariablesToPasteboardIncludingName:(BOOL)name andValue:(BOOL)value
{
	// At least one of either name or value must be true
	if ((!name) && (!value)) return;
	
	NSResponder *firstResponder = [[self window] firstResponder];
	
	if ((firstResponder == variablesTableView) && ([variablesTableView numberOfSelectedRows] > 0)) {
		
		NSMutableString *string = [[NSMutableString alloc] init];
		NSIndexSet *rows = [variablesTableView selectedRowIndexes];
		
		[rows enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * _Nonnull stop) {
			if (i < [variablesFiltered count]) {
				NSDictionary *variable = [variablesFiltered safeObjectAtIndex:i];
				
				NSString *variableName  = [variable objectForKey:@"Variable_name"];
				NSString *variableValue = [variable objectForKey:@"Value"];
				
				// Decide what to include in the string
				if (name && value) {
					[string appendFormat:@"%@ = %@\n", variableName, variableValue];
				}
				else {
					[string appendFormat:@"%@\n", (name) ? variableName : variableValue];
				}
			}
		}];
		
		NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
		
		// Copy the string to the pasteboard
		[pasteBoard declareTypes:@[NSStringPboardType] owner:nil];
		[pasteBoard setString:string forType:NSStringPboardType];
	}
}

/**
 * Add any necessary preference observers to allow live updating on changes.
 */
- (void)_addPreferenceObservers
{
	[prefs addObserver:self forKeyPath:SPGlobalFontSettings options:NSKeyValueObservingOptionNew context:NULL];

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

#pragma mark -

- (void)dealloc
{
	[self _removePreferenceObservers];

}

@end
