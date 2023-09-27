//
//  SPExtendedTableInfo.m
//  sequel-pro
//
//  Created by Jason Hallford (jason.hallford@byu.edu) on July 8, 2004.
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

#import "SPExtendedTableInfo.h"
#import "SPTableData.h"
#import "RegexKitLite.h"
#import "SPDatabaseData.h"
#import "SPDatabaseDocument.h"
#import "SPTablesList.h"
#import "SPTableStructure.h"
#import "SPServerSupport.h"
#import "sequel-ace-Swift.h"

#import <SPMySQL/SPMySQL.h>

static NSString *SPUpdateTableTypeNewType = @"SPUpdateTableTypeNewType";
static NSString *SPUpdateTableTypeCurrentType = @"SPUpdateTableTypeCurrentType";

// MySQL status field names
static NSString *SPMySQLEngineField           = @"Engine";
static NSString *SPMySQLRowFormatField        = @"Row_format";
static NSString *SPMySQLRowsField             = @"Rows";
static NSString *SPMySQLAverageRowLengthField = @"Avg_row_length";
static NSString *SPMySQLDataLengthField       = @"Data_length";
static NSString *SPMySQLMaxDataLengthField    = @"Max_data_length";
static NSString *SPMySQLIndexLengthField      = @"Index_length";
static NSString *SPMySQLDataFreeField         = @"Data_free";
static NSString *SPMySQLAutoIncrementField    = @"Auto_increment";
static NSString *SPMySQLCreateTimeField       = @"Create_time";
static NSString *SPMySQLUpdateTimeField       = @"Update_time";
static NSString *SPMySQLCollationField        = @"Collation";
static NSString *SPMySQLCommentField          = @"Comment";

@interface SPExtendedTableInfo ()

- (void)_updateDisplayedInfo:(NSNotification *)aNotification;
- (void)_changeCurrentTableTypeFrom:(NSString *)currentType to:(NSString *)newType;
- (NSString *)_formatValueWithKey:(NSString *)key inDictionary:(NSDictionary *)statusDict;

@end

@implementation SPExtendedTableInfo

@synthesize connection;

/**
 * Upon awakening bind the create syntax text view's background colour.
 */
- (void)awakeFromNib
{
    [super awakeFromNib];
    
	// Add observers for document task activity
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDocumentTaskForTab:)
												 name:SPDocumentTaskStartNotification
											   object:tableDocumentInstance];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(endDocumentTaskForTab:)
												 name:SPDocumentTaskEndNotification
											   object:tableDocumentInstance];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(_updateDisplayedInfo:)
												 name:SPTableInfoChangedNotification
											   object:tableDocumentInstance];
}

#pragma mark -
#pragma mark IBAction methods

/**
 * Reloads the info for the currently selected table.
 */
- (IBAction)reloadTable:(id)sender
{
	// Reset the table data's cache
	[tableDataInstance resetAllData];

	// Load the new table info
	[self loadTable:selectedTable];
}

/**
 * Update the table type (storage engine) of the currently selected table.
 */
- (IBAction)updateTableType:(id)sender
{
	NSString *newType = [sender titleOfSelectedItem];
	NSString *currentType = [tableDataInstance statusValueForKey:SPMySQLEngineField];

	// Check if the user selected the same type
	if ([currentType isEqualToString:newType]) return;

	// If the table is empty, perform the change directly
	if ([[tableDataInstance statusValueForKey:SPMySQLRowsField] isEqualToString:@"0"]) {
		[self _changeCurrentTableTypeFrom:currentType to:newType];
		return;
	}
	
	NSMutableDictionary *dataDict = [[NSMutableDictionary alloc] initWithCapacity:2];
	[dataDict setObject:currentType forKey:SPUpdateTableTypeCurrentType];
	[dataDict setObject:newType forKey:SPUpdateTableTypeNewType];

	[NSAlert createDefaultAlertWithTitle:NSLocalizedString(@"Change table type", @"change table type message") message:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to change this table's type to %@?\n\nPlease be aware that changing a table's type has the potential to cause the loss of some or all of its data. This action cannot be undone.", @"change table type informative message"), newType] primaryButtonTitle:NSLocalizedString(@"Change", @"change button") primaryButtonHandler:^{
		[self _changeCurrentTableTypeFrom:[dataDict objectForKey:SPUpdateTableTypeCurrentType]
									   to:[dataDict objectForKey:SPUpdateTableTypeNewType]];
	} cancelButtonHandler:^{
		[self->tableTypePopUpButton selectItemWithTitle:[dataDict objectForKey:SPUpdateTableTypeCurrentType]];
	}];
}

/**
 * Update the character set encoding of the currently selected table.
 */
- (IBAction)updateTableEncoding:(id)sender
{
	NSString *currentEncoding = [tableDataInstance tableEncoding];
	NSString *newEncoding = [[sender titleOfSelectedItem] stringByMatching:@"^.+\\((.+)\\)$" capture:1L];

	// Check if the user selected the same encoding
	if ([currentEncoding isEqualToString:newEncoding]) return;

	// Alter table's character set encoding
	[connection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ CHARACTER SET = %@", [selectedTable backtickQuotedString], newEncoding]];

	if (![connection queryErrored]) {
		// Reload the table's data
		[self reloadTable:self];
	}
	else {
		[sender selectItemWithTitle:currentEncoding];

		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error changing table encoding", @"error changing table encoding message") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred when trying to change the table encoding to '%@'.\n\nMySQL said: %@", @"error changing table encoding informative message"), newEncoding, [connection lastErrorMessage]] callback:nil];
	}
}

/**
 * Update the character set collation of the currently selected table.
 */
- (IBAction)updateTableCollation:(id)sender
{
	NSString *newCollation = [sender titleOfSelectedItem];
	NSString *currentCollation = [tableDataInstance statusValueForKey:SPMySQLCollationField];

	// Check if the user selected the same collation
	if ([currentCollation isEqualToString:newCollation]) return;

	// Alter table's character set collation
	[connection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ COLLATE = %@", [selectedTable backtickQuotedString], newCollation]];

	if (![connection queryErrored]) {
		// Reload the table's data
		[self reloadTable:self];
	}
	else {
		[sender selectItemWithTitle:currentCollation];

		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error changing table collation", @"error changing table collation message") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred when trying to change the table collation to '%@'.\n\nMySQL said: %@", @"error changing table collation informative message"), newCollation, [connection lastErrorMessage]] callback:nil];
	}
}

- (IBAction)resetAutoIncrement:(id)sender
{
	if ([sender tag] == 1) {
		[tableRowAutoIncrement setEditable:YES];
		[tableRowAutoIncrement selectText:nil];
	}
	else {
		[tableRowAutoIncrement setEditable:NO];
		[tableSourceInstance resetAutoIncrement:sender];
	}
}

- (IBAction)tableRowAutoIncrementWasEdited:(id)sender
{
	[tableRowAutoIncrement setEditable:NO];

	NSNumber *value = [NSNumberFormatter.decimalStyleFormatter numberFromString:[tableRowAutoIncrement stringValue]];
	
	[tableSourceInstance setAutoIncrementTo:value];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	// Listen to ESC to abort editing of auto increment input field
	if (command == @selector(cancelOperation:) && control == tableRowAutoIncrement) {
		[tableRowAutoIncrement abortEditing];
		[tableRowAutoIncrement setEditable:NO];
		return YES;
	}

	return NO;
}

#pragma mark -
#pragma mark Other

/**
 * Load all the info for the supplied table by querying the table data instance and updaing the interface
 * elements accordingly.
 * Note that interface elements are also toggled in start/endDocumentTaskForTab:, with similar logic.
 * Due to the large quantity of interface interaction in this function it is not thread-safe.
 */
- (void)loadTable:(NSString *)table
{
	BOOL enableInteraction = ![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableInfo] || ![tableDocumentInstance isWorking];

	[resetAutoIncrementResetButton setHidden:YES];

	// Store the table name away for future use
	selectedTable = table;

	// Retrieve the table status information via the table data cache
	NSDictionary *statusFields = [tableDataInstance statusValues];
  NSFont *font = [tableCreateSyntaxTextView font];

    SPLog(@"tableTypePopUpButton numberOfItems: %li", (long)tableTypePopUpButton.numberOfItems);
    SPLog(@"tableEncodingPopUpButton numberOfItems: %li", (long)tableEncodingPopUpButton.numberOfItems);
    SPLog(@"tableCollationPopUpButton numberOfItems: %li", (long)tableCollationPopUpButton.numberOfItems);

	[tableTypePopUpButton removeAllItems];
	[tableEncodingPopUpButton removeAllItems];
	[tableCollationPopUpButton removeAllItems];

	// No table selected or view selected
	if ((!table) || [table isEqualToString:@""] || [[statusFields safeObjectForKey:@"Engine"] isEqualToString:@"View"]) {

		[tableTypePopUpButton setEnabled:NO];
		[tableEncodingPopUpButton setEnabled:NO];
		[tableCollationPopUpButton setEnabled:NO];

		if ([[statusFields safeObjectForKey:SPMySQLEngineField] isEqualToString:@"View"]) {
			[tableTypePopUpButton addItemWithTitle:@"View"];
			
			// Set create syntax
			[tableCreateSyntaxTextView setEditable:YES];
			[tableCreateSyntaxTextView shouldChangeTextInRange:NSMakeRange(0, [[tableCreateSyntaxTextView string] length]) replacementString:@""];
			[tableCreateSyntaxTextView setString:@""];

			NSString *createViewSyntax = [[[tableDataInstance tableCreateSyntax] createViewSyntaxPrettifier] stringByAppendingString:@";"];

			if (createViewSyntax) {
				[tableCreateSyntaxTextView shouldChangeTextInRange:NSMakeRange(0, 0) replacementString:createViewSyntax];
				[tableCreateSyntaxTextView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:createViewSyntax]];
				[tableCreateSyntaxTextView didChangeText];
				[tableCreateSyntaxTextView setEditable:NO];
        [tableCreateSyntaxTextView setFont: font];
			}
		} 
		else {
			[tableCreateSyntaxTextView setEditable:YES];
			[tableCreateSyntaxTextView shouldChangeTextInRange:NSMakeRange(0, [[tableCreateSyntaxTextView string] length]) replacementString:@""];
			[tableCreateSyntaxTextView setString:@""];
			[tableCreateSyntaxTextView didChangeText];
			[tableCreateSyntaxTextView setEditable:NO];
		}

		[tableCreatedAt setStringValue:@""];
		[tableUpdatedAt setStringValue:@""];

		// Set row values
		[tableRowNumber setStringValue:@""];
		[tableRowFormat setStringValue:@""];
		[tableRowAvgLength setStringValue:@""];
		[tableRowAutoIncrement setStringValue:@""];

		// Set size values
		[tableDataSize setStringValue:@""];
		[tableMaxDataSize setStringValue:@""];
		[tableIndexSize setStringValue:@""];
		[tableSizeFree setStringValue:@""];

		// Set comments
		[tableCommentsTextView setEditable:NO];
		[tableCommentsTextView shouldChangeTextInRange:NSMakeRange(0, [[tableCommentsTextView string] length]) replacementString:@""];
		[tableCommentsTextView setString:@""];
		[tableCommentsTextView didChangeText];

		if ([[statusFields safeObjectForKey:SPMySQLEngineField] isEqualToString:@"View"] &&
			[statusFields safeObjectForKey:@"CharacterSetClient"] &&
			[statusFields safeObjectForKey:SPMySQLCollationField])
		{
			[tableEncodingPopUpButton safeAddItemWithTitle:[statusFields objectForKey:@"CharacterSetClient"]];
			[tableCollationPopUpButton safeAddItemWithTitle:[statusFields objectForKey:SPMySQLCollationField]];
		}
		
		return;
	}

	NSArray *engines    = [databaseDataInstance getDatabaseStorageEngines];
	NSArray *encodings  = [databaseDataInstance getDatabaseCharacterSetEncodings];
	NSArray *collations = [databaseDataInstance getDatabaseCollationsForEncoding:[tableDataInstance tableEncoding]];

	NSString *storageEngine = [statusFields safeObjectForKey:SPMySQLEngineField];

	if ([engines count] > 0 && storageEngine) {

		// Populate type popup button
		for (NSDictionary *engine in engines)
		{
            NSString *tmpEngine = [engine safeObjectForKey:SPMySQLEngineField];

            if(tmpEngine == nil){
                SPLog(@"engine string is nil: %@",engine);
                // raise Crashyltics error?
                continue;
            }

            [tableTypePopUpButton safeAddItemWithTitle:tmpEngine];
		}

		[tableTypePopUpButton selectItemWithTitle:storageEngine];
		[tableTypePopUpButton setEnabled:enableInteraction];

		// Object has a non-user storage engine (i.e. performance_schema) so just add it
		if ([tableTypePopUpButton indexOfSelectedItem] == -1) {
			[tableTypePopUpButton safeAddItemWithTitle:storageEngine];
			[tableTypePopUpButton selectItemWithTitle:storageEngine];
		}
	}
	else {
		[tableTypePopUpButton addItemWithTitle:NSLocalizedString(@"Not available", @"not available label")];
	}

	if (([encodings count] > 0) && ([tableDataInstance tableEncoding])) {
		NSString *selectedTitle = @"";

		// Populate encoding popup button
		for (NSDictionary *encoding in encodings)
		{
            NSString *encDesc    = [encoding safeObjectForKey:@"DESCRIPTION"];
            NSString *encCharset = [encoding safeObjectForKey:@"CHARACTER_SET_NAME"];

			NSString *menuItemTitle = (!encDesc) ? encCharset : [NSString stringWithFormat:@"%@ (%@)", encDesc, encCharset];

			if(menuItemTitle != nil) [tableEncodingPopUpButton safeAddItemWithTitle:menuItemTitle];

			if ([[tableDataInstance tableEncoding] isEqualToString:encCharset]) {
				selectedTitle = menuItemTitle;
			}
		}

        if(selectedTitle != nil) [tableEncodingPopUpButton selectItemWithTitle:selectedTitle];
		[tableEncodingPopUpButton setEnabled:enableInteraction];
	}
	else {
		[tableEncodingPopUpButton addItemWithTitle:NSLocalizedString(@"Not available", @"not available label")];
	}

	if (([collations count] > 0) && ([statusFields safeObjectForKey:SPMySQLCollationField])) {

		// Populate collation popup button
		for (NSDictionary *collation in collations)
		{
			[tableCollationPopUpButton safeAddItemWithTitle:[collation safeObjectForKey:@"COLLATION_NAME"]];
		}

		[tableCollationPopUpButton selectItemWithTitle:[statusFields safeObjectForKey:SPMySQLCollationField]];
		[tableCollationPopUpButton setEnabled:enableInteraction];
	}
	else {
		[tableCollationPopUpButton addItemWithTitle:NSLocalizedString(@"Not available", @"not available label")];
	}

	[tableCreatedAt setStringValue:[self _formatValueWithKey:SPMySQLCreateTimeField inDictionary:statusFields]];
	[tableUpdatedAt setStringValue:[self _formatValueWithKey:SPMySQLUpdateTimeField inDictionary:statusFields]];

	// Set row values
	[tableRowNumber setStringValue:[self _formatValueWithKey:SPMySQLRowsField inDictionary:statusFields]];
	[tableRowFormat setStringValue:[self _formatValueWithKey:SPMySQLRowFormatField inDictionary:statusFields]];
	[tableRowAvgLength setStringValue:[self _formatValueWithKey:SPMySQLAverageRowLengthField inDictionary:statusFields]];
	[tableRowAutoIncrement setStringValue:[self _formatValueWithKey:SPMySQLAutoIncrementField inDictionary:statusFields]];

	// Set size values
	[tableDataSize setStringValue:[self _formatValueWithKey:SPMySQLDataLengthField inDictionary:statusFields]];
	[tableMaxDataSize setStringValue:[self _formatValueWithKey:SPMySQLMaxDataLengthField inDictionary:statusFields]];
	[tableIndexSize setStringValue:[self _formatValueWithKey:SPMySQLIndexLengthField inDictionary:statusFields]];
	[tableSizeFree setStringValue:[self _formatValueWithKey:SPMySQLDataFreeField inDictionary:statusFields]];

	// Set comments
	// Note: On MySQL the comment column is marked as NOT NULL, but we still received crash reports because it was NULL!? (#2791)
	NSString *commentText = [[statusFields objectForKey:SPMySQLCommentField] unboxNull];
	
	if (!commentText) commentText = @"";
	
	[tableCommentsTextView setEditable:YES];
	[tableCommentsTextView shouldChangeTextInRange:NSMakeRange(0, [[tableCommentsTextView string] length]) replacementString:commentText];
	[tableCommentsTextView setString:commentText];
	[tableCommentsTextView didChangeText];
	[tableCommentsTextView setEditable:enableInteraction];

	// Set create syntax
	[tableCreateSyntaxTextView setEditable:YES];
	[tableCreateSyntaxTextView shouldChangeTextInRange:NSMakeRange(0, [[tableCommentsTextView string] length]) replacementString:@""];
	[tableCreateSyntaxTextView setString:@""];
	[tableCreateSyntaxTextView didChangeText];
	[tableCreateSyntaxTextView shouldChangeTextInRange:NSMakeRange(0, 0) replacementString:[tableDataInstance tableCreateSyntax]];
	
	if ([tableDataInstance tableCreateSyntax]) {
		[tableCreateSyntaxTextView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:[[tableDataInstance tableCreateSyntax] stringByAppendingString:@";"]]];
    [tableCreateSyntaxTextView setFont: font];
	}
	
	[tableCreateSyntaxTextView didChangeText];
	[tableCreateSyntaxTextView setEditable:NO];

	// Validate Reset AUTO_INCREMENT button
	if ([statusFields objectForKey:SPMySQLAutoIncrementField] && ![[statusFields objectForKey:SPMySQLAutoIncrementField] isNSNull]) {
		[resetAutoIncrementResetButton setHidden:NO];
	}
}

/**
 * Returns a dictionary describing the information of the table to be used for printing purposes.
 *
 * MUST BE CALLED ON THE UI THREAD!
 */
- (NSDictionary *)tableInformationForPrinting
{
	// Update possible pending comment changes by set the focus to create table syntax view
	[[NSApp keyWindow] makeFirstResponder:tableCreateSyntaxTextView];

	NSMutableDictionary *tableInfo = [NSMutableDictionary dictionary];
	NSDictionary *statusFields = [tableDataInstance statusValues];

	if ([tableTypePopUpButton titleOfSelectedItem]) {
		[tableInfo setObject:[tableTypePopUpButton titleOfSelectedItem] forKey:@"type"];
	}
		
	if ([tableEncodingPopUpButton titleOfSelectedItem]) {
		[tableInfo setObject:[tableEncodingPopUpButton titleOfSelectedItem] forKey:@"encoding"];
	}
	
	if ([tableCollationPopUpButton titleOfSelectedItem]) {
		[tableInfo setObject:[tableCollationPopUpButton titleOfSelectedItem] forKey:@"collation"];
	}

	if ([self _formatValueWithKey:SPMySQLCreateTimeField inDictionary:statusFields]) {
		[tableInfo setObject:[self _formatValueWithKey:SPMySQLCreateTimeField inDictionary:statusFields] forKey:@"createdAt"];
	}
	
	if ([self _formatValueWithKey:SPMySQLUpdateTimeField inDictionary:statusFields]) {
		[tableInfo setObject:[self _formatValueWithKey:SPMySQLUpdateTimeField inDictionary:statusFields] forKey:@"updatedAt"];
	}
	
	if ([self _formatValueWithKey:SPMySQLRowsField inDictionary:statusFields]) {
		[tableInfo setObject:[self _formatValueWithKey:SPMySQLRowsField inDictionary:statusFields] forKey:@"rowNumber"];
	}
	
	if ([self _formatValueWithKey:SPMySQLRowFormatField inDictionary:statusFields]) {
		[tableInfo setObject:[self _formatValueWithKey:SPMySQLRowFormatField inDictionary:statusFields] forKey:@"rowFormat"];
	}
	
	if ([self _formatValueWithKey:SPMySQLAverageRowLengthField inDictionary:statusFields]) {
		[tableInfo setObject:[self _formatValueWithKey:SPMySQLAverageRowLengthField inDictionary:statusFields] forKey:@"rowAvgLength"];
	}
	
	if ([self _formatValueWithKey:SPMySQLAutoIncrementField inDictionary:statusFields]) {
		[tableInfo setObject:[self _formatValueWithKey:SPMySQLAutoIncrementField inDictionary:statusFields] forKey:@"rowAutoIncrement"];
	}
	
	if ([self _formatValueWithKey:SPMySQLDataLengthField inDictionary:statusFields]) {
		[tableInfo setObject:[self _formatValueWithKey:SPMySQLDataLengthField inDictionary:statusFields] forKey:@"dataSize"];
	}
	
	if ([self _formatValueWithKey:SPMySQLMaxDataLengthField inDictionary:statusFields]) {
		[tableInfo setObject:[self _formatValueWithKey:SPMySQLMaxDataLengthField inDictionary:statusFields] forKey:@"maxDataSize"];
	}
	
	if ([self _formatValueWithKey:SPMySQLIndexLengthField inDictionary:statusFields]) {
		[tableInfo setObject:[self _formatValueWithKey:SPMySQLIndexLengthField inDictionary:statusFields] forKey:@"indexSize"];
	}
	
	[tableInfo setObject:[self _formatValueWithKey:SPMySQLDataFreeField inDictionary:statusFields] forKey:@"sizeFree"];

	if ([tableCommentsTextView string]) {
		[tableInfo setObject:[tableCommentsTextView string] forKey:@"comments"];
	}

	NSError *error = nil;
	NSArray *HTMLExcludes = @[@"doctype", @"html", @"head", @"body", @"xml"];

	NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:NSHTMLTextDocumentType,
		NSDocumentTypeDocumentAttribute, HTMLExcludes, NSExcludedElementsDocumentAttribute, nil];

	// Set tableCreateSyntaxTextView's font size temporarily to 10pt for printing
	NSFont *oldFont = [tableCreateSyntaxTextView font];
	BOOL editableStatus = [tableCreateSyntaxTextView isEditable];
	                   
	[tableCreateSyntaxTextView setEditable:YES];
	[tableCreateSyntaxTextView setFont:[NSFont fontWithName:[oldFont fontName] size:10.0f]];

	// Convert tableCreateSyntaxTextView to HTML
	NSData *HTMLData = [[tableCreateSyntaxTextView textStorage] dataFromRange:NSMakeRange(0, [[tableCreateSyntaxTextView string] length]) documentAttributes:attributes error:&error];

	// Restore original font settings
	[tableCreateSyntaxTextView setFont:oldFont];
	[tableCreateSyntaxTextView setEditable:editableStatus];

	if (error != nil) {
		NSLog(@"Error generating table's create syntax HTML for printing. Excluding from print out. Error was: %@", [error localizedDescription]);

		return tableInfo;
	}

	NSString *HTMLString = [[NSString alloc] initWithData:HTMLData encoding:NSUTF8StringEncoding];

	[tableInfo setObject:HTMLString forKey:@"createSyntax"];

	return tableInfo;
}

/**
 * NSTextView delegate. Used to change the selected table's comment.
 * THIS GETS CALLED A LOT - jcs
 */
- (void)textDidEndEditing:(NSNotification *)notification
{
	id object = [notification object];

	if ((object == tableCommentsTextView) && ([object isEditable]) && ([selectedTable length] > 0)) {

		NSString *currentComment = [[[tableDataInstance statusValueForKey:SPMySQLCommentField] unboxNull] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSString *newComment = [[tableCommentsTextView string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

		// Check that the user actually changed the tables comment
		// what if the new comment is "" and the current is nil?
		// or current is not nil and new new is "" or nil?
		if (([currentComment isEqualToString:newComment] == NO && newComment.length > 0) ||(newComment.length == 0 && currentComment.length > 0) ) {
																							
			// Alter table's comment
			[connection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ COMMENT = %@", [selectedTable backtickQuotedString], [connection escapeAndQuoteString:newComment]]];

			if (![connection queryErrored]) {
				// Reload the table's data
				[self reloadTable:self];
			}
			else {
				[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error changing table comment", @"error changing table comment message") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred when trying to change the table's comment to '%@'.\n\nMySQL said: %@", @"error changing table comment informative message"), newComment, [connection lastErrorMessage]] callback:nil];
			}
		}
	}
}

#pragma mark -
#pragma mark Task interaction

/**
 * Disable all content interactive elements during an ongoing task.
 */
- (void)startDocumentTaskForTab:(NSNotification *)aNotification
{
	// Only proceed if this view is selected.
	if (![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableInfo]) return;

	[tableTypePopUpButton setEnabled:NO];
	[tableEncodingPopUpButton setEnabled:NO];
	[tableCollationPopUpButton setEnabled:NO];
	[tableCommentsTextView setEditable:NO];
}

/**
 * Enable all content interactive elements after an ongoing task.
 */
- (void)endDocumentTaskForTab:(NSNotification *)aNotification
{
	// Only proceed if this view is selected.
	if (![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableInfo]) return;

	NSDictionary *statusFields = [tableDataInstance statusValues];

	if (!selectedTable || ![selectedTable length] || [[statusFields safeObjectForKey:SPMySQLEngineField] isEqualToString:@"View"]) return;

	// If we are viewing tables in the information_schema database, then disable all controls that cause table
	// changes as these tables are not modifiable by anyone.
	// also affects mysql and performance_schema
	BOOL isSystemSchemaDb = ([[tableDocumentInstance database] isEqualToString:SPMySQLInformationSchemaDatabase] || 
							 [[tableDocumentInstance database] isEqualToString:SPMySQLPerformanceSchemaDatabase] || 
							 [[tableDocumentInstance database] isEqualToString:SPMySQLDatabase]);

	if ([[databaseDataInstance getDatabaseStorageEngines] count] && [statusFields safeObjectForKey:SPMySQLEngineField]) {
		[tableTypePopUpButton setEnabled:(!isSystemSchemaDb)];
	}

	if ([[databaseDataInstance getDatabaseCharacterSetEncodings] count] && [tableDataInstance tableEncoding])
	{
		[tableEncodingPopUpButton setEnabled:(!isSystemSchemaDb)];
	}

	if ([[databaseDataInstance getDatabaseCollationsForEncoding:[tableDataInstance tableEncoding]] count] && 
		[statusFields objectForKey:SPMySQLCollationField])
	{
		[tableCollationPopUpButton setEnabled:(!isSystemSchemaDb)];
	}

	[tableCommentsTextView setEditable:(!isSystemSchemaDb)];
}

#pragma mark -
#pragma mark Private API

/**
 * Trigger an update to a display in reaction to changes in external data
 */
- (void)_updateDisplayedInfo:(NSNotification *)aNotification
{
	[self loadTable:selectedTable];
}

/**
 * Changes the current table's storage engine to the supplied type.
 */
- (void)_changeCurrentTableTypeFrom:(NSString *)currentType to:(NSString *)newType
{
	// Alter table's storage type
	[connection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ ENGINE = %@", [selectedTable backtickQuotedString], newType]];
	
	if ([connection queryErrored]) {

		[tableTypePopUpButton selectItemWithTitle:currentType];
		
		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error changing table type", @"error changing table type message") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred when trying to change the table type to '%@'.\n\nMySQL said: %@", @"error changing table type informative message"), newType, [connection lastErrorMessage]] callback:nil];
		return;
	}
	
	// Reload the table's data
	[tableDocumentInstance loadTable:selectedTable ofType:[tableDocumentInstance tableType]];
}

/**
 * Format and returns the value within the info dictionary with the associated key.
 */
- (NSString *)_formatValueWithKey:(NSString *)key inDictionary:(NSDictionary *)infoDict
{
	NSString *value = [infoDict objectForKey:key];

	if (![value unboxNull]) { // (value == nil || value == [NSNull null])
		value = @"";
	}
	else {
		// Format size strings
		if ([key isEqualToString:SPMySQLDataLengthField] ||
			[key isEqualToString:SPMySQLMaxDataLengthField] ||
			[key isEqualToString:SPMySQLIndexLengthField] ||
			[key isEqualToString:SPMySQLDataFreeField]) {

            value = [NSByteCountFormatter stringWithByteSize:[value longLongValue]];
		}
		// Format date strings to the user's long date format
		else if ([key isEqualToString:SPMySQLCreateTimeField] ||
				 [key isEqualToString:SPMySQLUpdateTimeField]) {

			// 2020-06-30 14:14:11 is one example
			value = [NSDateFormatter.mediumStyleFormatter stringFromDate:[NSDateFormatter.naturalLanguageFormatter dateFromString:value]];
		}
		// Format numbers
		else if ([key isEqualToString:SPMySQLRowsField] ||
				 [key isEqualToString:SPMySQLAverageRowLengthField] ||
				 [key isEqualToString:SPMySQLAutoIncrementField]) {

			value = [NSNumberFormatter.decimalStyleFormatter stringFromNumber:[NSNumber numberWithLongLong:[value longLongValue]]];

			// Prefix number of rows with '~' if it is not an accurate count
			if ([key isEqualToString:SPMySQLRowsField] && ![[infoDict objectForKey:@"RowsCountAccurate"] boolValue]) {
				value = [@"~" stringByAppendingString:value];
			}
		}
	}

    if (value.length){
        return value;
    } else{
        SPLog(@"Unable to format key: [%@], for value: [%@]", key, value);
        return NSLocalizedString(@"Not available", @"not available label");;
    }
}

#pragma mark -

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
}

@end
