//
//  SPTableStructure.m
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

#import "SPTableStructure.h"
#import "SPDatabaseStructure.h"
#import "SPDatabaseDocument.h"
#import "SPTableInfo.h"
#import "SPTablesList.h"
#import "SPTableData.h"
#import "SPTableView.h"
#import "SPDatabaseData.h"
#import "SPSQLParser.h"
#import "SPIndexesController.h"
#import "RegexKitLite.h"
#import "SPTableFieldValidation.h"
#import "SPThreadAdditions.h"
#import "SPServerSupport.h"
#import "SPExtendedTableInfo.h"
#import "SPFunctions.h"
#import "SPPillAttachmentCell.h"
#import "SPIdMenu.h"
#import "SPComboBoxCell.h"

#import "sequel-pace-Swift.h"

#import "SPPostgresConnection.h"
#import "SPPostgresDataTypes.h"

@interface SPFieldTypeHelp ()

@property(copy,readwrite) NSString *typeName;
@property(copy,readwrite) NSString *typeDefinition;
@property(copy,readwrite) NSString *typeRange;
@property(copy,readwrite) NSString *typeDescription;

@end

@implementation SPFieldTypeHelp

@synthesize typeName;
@synthesize typeDefinition;
@synthesize typeRange;
@synthesize typeDescription;

- (void)dealloc
{
	[self setTypeName:nil];
	[self setTypeDefinition:nil];
	[self setTypeRange:nil];
	[self setTypeDescription:nil];

    NSLog(@"Dealloc called %s", __FILE_NAME__);
}

@end

static inline SPFieldTypeHelp *MakeFieldTypeHelp(NSString *typeName,NSString *typeDefinition,NSString *typeRange,NSString *typeDescription) {
	SPFieldTypeHelp *obj = [[SPFieldTypeHelp alloc] init];
	
	[obj setTypeName:       typeName];
	[obj setTypeDefinition: typeDefinition];
	[obj setTypeRange:      typeRange];
	[obj setTypeDescription:typeDescription];
	
	return obj;
}

struct _cmpMap {
	NSString *title; // the title of the "pill"
	NSString *tooltipPart; // the tooltip of the menuitem
	NSString *cmpWith; // the string to match against
};

/**
 * This function will compare the representedObject of every item in menu against
 * every map->cmpWith. If they match it will append a pill-like (similar to a TokenFieldCell's token)
 * element labelled map->title to the menu item's title. If map->tooltipPart is set,
 * it will also be added to the menu item's tooltip.
 *
 * This is used with the encoding/collation popup menus to add visual indicators for the
 * table-level and default encoding/collation.
 */
static void _BuildMenuWithPills(NSMenu *menu,struct _cmpMap *map,size_t mapEntries);

@interface SPTableStructure () {
	TableSortHelper *fieldsSortHelper;
}

- (void)_removeFieldAndForeignKey:(NSNumber *)removeForeignKey;
- (NSString *)_buildPartialColumnDefinitionString:(NSDictionary *)theRow;
- (BOOL)filterFieldsWithString:(NSString *)filterString;
- (BOOL)sort:(NSMutableArray *)data withDescriptor:(NSSortDescriptor *)descriptor;

#pragma mark - SPTableStructureDelegate

- (void)_displayFieldTypeHelpIfPossible:(SPComboBoxCell *)cell;

@end

@implementation SPTableStructure

#pragma mark -
#pragma mark Initialisation

- (instancetype)init
{
	if ((self = [super init])) {
		
		tableFields = [[NSMutableArray alloc] init];
		oldRow      = [[NSMutableDictionary alloc] init];
		enumFields  = [[NSMutableDictionary alloc] init];
		
		defaultValues = nil;
		selectedTable = nil;
		typeSuggestions = nil;
		extraFieldSuggestions = nil;
		currentlyEditingRow = -1;
		isCurrentExtraAutoIncrement = NO;
		autoIncrementIndex = nil;
		filteredTableFields = nil;
		fieldsSortHelper = nil;

		fieldValidation = [[SPTableFieldValidation alloc] init];
		
		prefs = [NSUserDefaults standardUserDefaults];
	}

	return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    
	NSComparisonResult (^numCompare)(NSString *, NSString *) = ^NSComparisonResult(NSString *lhs, NSString *rhs) {
		return [@([lhs integerValue]) compare: @([rhs integerValue])];
	};
    
	fieldsSortHelper = [[TableSortHelper alloc] initWithTableView:tableSourceView descriptors:@[
		[NSSortDescriptor sortDescriptorWithKey: @"datacolumnindex" ascending: YES comparator: numCompare], // default order
		[NSSortDescriptor sortDescriptorWithKey: @"name" ascending: YES selector: @selector(compare:)],
		[NSSortDescriptor sortDescriptorWithKey: @"type" ascending: YES selector: @selector(compare:)],
		[NSSortDescriptor sortDescriptorWithKey: @"length" ascending: YES comparator: numCompare],
        [NSSortDescriptor sortDescriptorWithKey: @"unsigned" ascending: YES comparator: numCompare],
        [NSSortDescriptor sortDescriptorWithKey: @"zerofill" ascending: YES comparator: numCompare],
        [NSSortDescriptor sortDescriptorWithKey: @"binary" ascending: YES comparator: numCompare],
        [NSSortDescriptor sortDescriptorWithKey: @"null" ascending: YES comparator: numCompare],
		[NSSortDescriptor sortDescriptorWithKey: @"Key" ascending: YES selector: @selector(compare:)],
		[NSSortDescriptor sortDescriptorWithKey: @"default" ascending: YES selector: @selector(compare:)],
		[NSSortDescriptor sortDescriptorWithKey: @"Extra" ascending: YES selector: @selector(compare:)],
		[NSSortDescriptor sortDescriptorWithKey: @"comment" ascending: YES selector: @selector(compare:)],
        [NSSortDescriptor sortDescriptorWithKey: @"encodingName" ascending: YES selector: @selector(compare:)],
        [NSSortDescriptor sortDescriptorWithKey: @"collationName" ascending: YES selector: @selector(compare:)]
    ] aliases:@{ @"collation": @"collationName", @"encoding": @"encodingName" }];

	// Set the structure and index view's vertical gridlines if required
	[tableSourceView setGridStyleMask:[prefs boolForKey:SPDisplayTableViewVerticalGridlines] ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	[indexesTableView setGridStyleMask:[prefs boolForKey:SPDisplayTableViewVerticalGridlines] ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];

	// Set the double-click action in blank areas of the table to create new rows
	[tableSourceView setEmptyDoubleClickAction:@selector(addField:)];

	[prefs addObserver:self forKeyPath:SPGlobalFontSettings options:NSKeyValueObservingOptionNew context:nil];

	NSFont *tableFont = [NSUserDefaults getFont];
	[tableSourceView setRowHeight:4.0f + NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];
	[indexesTableView setRowHeight:4.0f + NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];

	extraFieldSuggestions = @[
			@"None",
			@"auto_increment",
			@"on update CURRENT_TIMESTAMP",
			@"SERIAL DEFAULT VALUE"
	];

	// PostgreSQL-native data types organized by category
	// Note: SPTableFieldValidation uses set-based type checking, not index positions
	typeSuggestions = @[
		// Numeric Types
		SPPostgresSmallIntType,
		SPPostgresIntegerType,
		SPPostgresBigIntType,
		SPPostgresDecimalType,
		SPPostgresNumericType,
		SPPostgresRealType,
		SPPostgresDoublePrecisionType,
		SPPostgresSmallSerialType,
		SPPostgresSerialType,
		SPPostgresBigSerialType,
		SPPostgresMoneyType,
		@"--------",
		// Character Types
		SPPostgresCharType,
		SPPostgresVarCharType,
		SPPostgresTextType,
		@"--------",
		// Binary Types
		SPPostgresByteaType,
		@"--------",
		// Date/Time Types
		SPPostgresDateType,
		SPPostgresTimeType,
		SPPostgresTimeTZType,
		SPPostgresTimestampType,
		SPPostgresTimestampTZType,
		SPPostgresIntervalType,
		@"--------",
		// Boolean
		SPPostgresBooleanType,
		@"--------",
		// UUID
		SPPostgresUUIDType,
		@"--------",
		// JSON Types
		SPPostgresJSONType,
		SPPostgresJSONBType,
		@"--------",
		// Network Types
		SPPostgresCidrType,
		SPPostgresInetType,
		SPPostgresMacAddrType,
		SPPostgresMacAddr8Type,
		@"--------",
		// Bit String Types
		SPPostgresBitType,
		SPPostgresBitVaryingType,
		@"--------",
		// Geometric Types
		SPPostgresPointType,
		SPPostgresLineType,
		SPPostgresLsegType,
		SPPostgresBoxType,
		SPPostgresPathType,
		SPPostgresPolygonType,
		SPPostgresCircleType,
		@"--------",
		// Range Types
		SPPostgresInt4RangeType,
		SPPostgresInt8RangeType,
		SPPostgresNumRangeType,
		SPPostgresTsRangeType,
		SPPostgresTsTZRangeType,
		SPPostgresDateRangeType,
		@"--------",
		// Other Types
		SPPostgresXMLType,
		SPPostgresTsVectorType,
		SPPostgresTsQueryType];

	[fieldValidation setFieldTypes:typeSuggestions];
	
	// Add observers for document task activity
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDocumentTaskForTab:)
												 name:SPDocumentTaskStartNotification
											   object:tableDocumentInstance];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(endDocumentTaskForTab:)
												 name:SPDocumentTaskEndNotification
											   object:tableDocumentInstance];

	// Init the view column submenu according to saved hidden status;
	// menu items are identified by their tag number which represents the initial column index
	for (NSMenuItem *item in [viewColumnsMenu itemArray]) [item setState:NSControlStateValueOn]; // Set all items to NSControlStateValueOn

	for (NSTableColumn *col in [tableSourceView tableColumns]) {
		if ([col isHidden]) {
			if ([[col identifier] isEqualToString:@"Key"])
				[[viewColumnsMenu itemWithTag:7] setState:NSControlStateValueOff];
			else if ([[col identifier] isEqualToString:@"encoding"])
				[[viewColumnsMenu itemWithTag:10] setState:NSControlStateValueOff];
			else if ([[col identifier] isEqualToString:@"collation"])
				[[viewColumnsMenu itemWithTag:11] setState:NSControlStateValueOff];
			else if ([[col identifier] isEqualToString:@"comment"])
				[[viewColumnsMenu itemWithTag:12] setState:NSControlStateValueOff];
		}
		[[col dataCell] setFont:tableFont];
	}

	[tableSourceView reloadData];

	for (NSTableColumn *col in [indexesTableView tableColumns]) {
		[[col dataCell] setFont:tableFont];
	}
}

#pragma mark -
#pragma mark Edit methods

/**
 * Adds an empty row to the tableSource-array and goes into edit mode
 */
- (IBAction)addField:(id)sender
{
	// Check whether table editing is permitted (necessary as some actions - eg table double-click - bypass validation)
	if ([tableDocumentInstance isWorking] || [tablesListInstance tableType] != SPTableTypeTable) return;

	// Check whether a save of the current row is required.
	if (![self saveRowOnDeselect]) return;

	NSInteger insertIndex = ([tableSourceView numberOfSelectedRows] == 0 ? [tableSourceView numberOfRows] : [tableSourceView selectedRow] + 1);

	BOOL allowNull = [[[tableDataInstance statusValueForKey:@"Engine"] uppercaseString] isEqualToString:@"CSV"] ? NO : [prefs boolForKey:SPNewFieldsAllowNulls];
	
	[[self activeFieldsSource] insertObject:[NSMutableDictionary
							   dictionaryWithObjects:[NSArray arrayWithObjects:@"", @"integer", @"", @"0", @"0", @"0", allowNull ? @"1" : @"0", @"", [prefs stringForKey:SPNullValue], @"None", @"", nil]
							   forKeys:@[@"name", @"type", @"length", @"unsigned", @"zerofill", @"binary", @"null", @"Key", @"default", @"Extra", @"comment"]]
					  atIndex:insertIndex];

	[tableSourceView reloadData];
	[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:insertIndex] byExtendingSelection:NO];
	
	isEditingRow = YES;
	isEditingNewRow = YES;
	currentlyEditingRow = [tableSourceView selectedRow];
	
	[tableSourceView editColumn:0 row:insertIndex withEvent:nil select:YES];
}

/**
 * Show optimized field type for selected field
 */
- (IBAction)showOptimizedFieldType:(id)sender
{
	SPPostgresResult *theResult = [postgresConnection queryString:[NSString stringWithFormat:@"SELECT %@ FROM %@ LIMIT 1", 
		[[[[self activeFieldsSource] objectAtIndex:[tableSourceView selectedRow]] objectForKey:@"name"] postgresQuotedIdentifier],
		[selectedTable postgresQuotedIdentifier]]];

	// Check for errors
	if ([postgresConnection queryErrored]) {
		NSString *message = NSLocalizedString(@"Error while fetching the optimized field type", @"error while fetching the optimized field type message");
		
		if ([postgresConnection isConnected]) {
			 [NSAlert createWarningAlertWithTitle:message message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while fetching the optimized field type.\n\nPostgreSQL said:%@", @"an error occurred while fetching the optimized field type.\n\nPostgreSQL said:%@"), [postgresConnection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")] callback:nil];
		}
		return;
	}

	[theResult setReturnDataAsStrings:YES];
	
	NSDictionary *analysisResult = [theResult getRowAsDictionary];

	NSString *type = [analysisResult objectForKey:@"Optimal_fieldtype"];
	
	if (!type || [type isNSNull] || ![type length]) {
		type = NSLocalizedString(@"No optimized field type found.", @"no optimized field type found. message");
	}
	[NSAlert createWarningAlertWithTitle:
		[NSString stringWithFormat:NSLocalizedString(@"Optimized type for field '%@'", @"Optimized type for field %@"),
			[[[self activeFieldsSource] objectAtIndex:[tableSourceView selectedRow]] objectForKey:@"name"]] message:type callback:nil];

}

/**
 * Control the visibility of the columns
 */
- (IBAction)toggleColumnView:(NSMenuItem *)sender
{
	NSString *columnIdentifierName = nil;

	switch([sender tag]) {
		case 7:
		columnIdentifierName = @"Key";
		break;
		case 10:
		columnIdentifierName = @"encoding";
		break;
		case 11:
		columnIdentifierName = @"collation";
		break;
		case 12:
		columnIdentifierName = @"comment";
		break;
		default:
		return;
	}

	for(NSTableColumn *col in [tableSourceView tableColumns]) {

		if([[col identifier] isEqualToString:columnIdentifierName]) {
			[col setHidden:([sender state] == NSControlStateValueOff) ? NO : YES];
			[(NSMenuItem *)sender setState:![sender state]];
			break;
		}

	}

	[tableSourceView reloadData];

}

/**
 * Copies a field and goes in edit mode for the new field
 */
- (IBAction)duplicateField:(id)sender
{
	NSMutableDictionary *tempRow;
	NSUInteger rowToCopy;

	// Store the row to duplicate, as saveRowOnDeselect and subsequent reloads may trigger a deselection
	if ([tableSourceView numberOfSelectedRows]) {
		rowToCopy = [tableSourceView selectedRow];
	} else {
		rowToCopy = [tableSourceView numberOfRows]-1;
	}

	// Check whether a save of the current row is required.
	if ( ![self saveRowOnDeselect] ) return;

	//add copy of selected row and go in edit mode
	tempRow = [NSMutableDictionary dictionaryWithDictionary:[[self activeFieldsSource] objectAtIndex:rowToCopy]];
	[tempRow setObject:[[tempRow objectForKey:@"name"] stringByAppendingString:@"Copy"] forKey:@"name"];
	[tempRow setObject:@"" forKey:@"Key"];
	[tempRow setObject:@"None" forKey:@"Extra"];
	[[self activeFieldsSource] addObject:tempRow];
	[tableSourceView reloadData];
	[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:[tableSourceView numberOfRows]-1] byExtendingSelection:NO];
	isEditingRow = YES;
	isEditingNewRow = YES;
	currentlyEditingRow = [tableSourceView selectedRow];
	[tableSourceView editColumn:0 row:[tableSourceView numberOfRows]-1 withEvent:nil select:YES];
}

/**
 * Ask the user to confirm that they really want to remove the selected field.
 */
- (IBAction)removeField:(id)sender
{
	if (![tableSourceView numberOfSelectedRows]) return;

	// Check whether a save of the current row is required.
	if (![self saveRowOnDeselect]) return;

	NSInteger anIndex = [tableSourceView selectedRow];

	if ((anIndex == -1) || (anIndex > (NSInteger)([[self activeFieldsSource] count] - 1))) return;

	// Check if the user tries to delete the last defined field in table
	// Note that because of better menu item validation, this check will now never evaluate to true.
	if ([tableSourceView numberOfRows] < 2) {
		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error while deleting field", @"Error while deleting field") message:NSLocalizedString(@"You cannot delete the last field in a table. Delete the table instead.", @"You cannot delete the last field in a table. Delete the table instead.") callback:nil];
	}

	NSString *field = [[[self activeFieldsSource] objectAtIndex:anIndex] objectForKey:@"name"];

	BOOL hasForeignKey = NO;
	NSString *referencedTable = @"";

	// Check to see whether the user is attempting to remove a field that has foreign key constraints and thus
	// would result in an error if not dropped before removing the field.
	for (NSDictionary *constraint in [tableDataInstance getConstraints])
	{
		for (NSString *column in [constraint objectForKey:@"columns"])
		{
			if ([column isEqualToString:field]) {
				hasForeignKey = YES;
				referencedTable = [constraint objectForKey:@"ref_table"];
				break;
			}
		}
	}

	NSString *alertMessage;
	if (hasForeignKey) {
		alertMessage = [NSString stringWithFormat:NSLocalizedString(@"This field is part of a foreign key relationship with the table '%@'. This relationship must be removed before the field can be deleted.\n\nAre you sure you want to continue to delete the relationship and the field? This action cannot be undone.", @"delete field and foreign key informative message"), referencedTable];
	} else {
		alertMessage = [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the field '%@'? This action cannot be undone.", @"delete field informative message"), field];
	}
	[NSAlert createDefaultAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Delete field '%@'?", @"delete field message"), field] message:alertMessage primaryButtonTitle:NSLocalizedString(@"Delete", @"delete button") primaryButtonHandler:^{

		[self->tableDocumentInstance startTaskWithDescription:NSLocalizedString(@"Removing field...", @"removing field task status message")];

		NSNumber *removeKey = [NSNumber numberWithBool:hasForeignKey];

		if ([NSThread isMainThread]) {
			[NSThread detachNewThreadWithName:SPCtxt(@"SPTableStructure field and key removal task", self->tableDocumentInstance)
									   target:self
									 selector:@selector(_removeFieldAndForeignKey:)
									   object:removeKey];

			[self->tableDocumentInstance enableTaskCancellationWithTitle:NSLocalizedString(@"Cancel", @"cancel button")
													callbackObject:self
												  callbackFunction:NULL];
		} else {
			[self _removeFieldAndForeignKey:removeKey];
		}
	} cancelButtonHandler:nil];
}

/**
 * Resets the auto increment value of a table.
 */
- (IBAction)resetAutoIncrement:(id)sender {
	if ([sender tag] == 1) {

		[resetAutoIncrementLine setHidden:YES];

		if ([tableDocumentInstance currentlySelectedView] == SPTableViewStructure){
			[resetAutoIncrementLine setHidden:NO];
		}

		[[tableDocumentInstance parentWindowControllerWindow] beginSheet:resetAutoIncrementSheet completionHandler:^(NSModalResponse returnCode) {
			if (returnCode == NSAlertFirstButtonReturn) {
				[self takeAutoIncrementFrom:self->resetAutoIncrementValue];
			}
		}];

		[resetAutoIncrementValue setStringValue:@"1"];
	} else if ([sender tag] == 2) {
		[self setAutoIncrementTo:@1];
	}
}

- (void)takeAutoIncrementFrom:(NSTextField *)field {
	id obj = [field objectValue];

	//nil is handled by -setAutoIncrementTo:
	if (obj && ![obj isKindOfClass:[NSNumber class]]) {
		[NSException raise:NSInternalInconsistencyException format:@"[$field objectValue] should return NSNumber *, but was %@",[obj class]];
	}

	[self setAutoIncrementTo:(NSNumber *)obj];
}

/**
 * Cancel active row editing, replacing the previous row if there was one
 * and resetting state.
 * Returns whether row editing was cancelled.
 */
- (BOOL)cancelRowEditing
{
	if (!isEditingRow) return NO;
	
	if (isEditingNewRow) {
		isEditingNewRow = NO;
		[[self activeFieldsSource] safeRemoveObjectAtIndex:currentlyEditingRow];
	} 
	else {
		[[self activeFieldsSource] safeReplaceObjectAtIndex:currentlyEditingRow withObject:[NSMutableDictionary dictionaryWithDictionary:oldRow]];
	}
	
	isEditingRow = NO;
	isCurrentExtraAutoIncrement = [tableDataInstance tableHasAutoIncrementField];
	autoIncrementIndex = nil;
	
	[tableSourceView reloadData];
	
	currentlyEditingRow = -1;
	
	[[tableDocumentInstance parentWindowControllerWindow] makeFirstResponder:tableSourceView];
	
	return YES;
}

#pragma mark -
#pragma mark Other IB action methods

- (IBAction)unhideIndexesView:(id)sender
{
	[tablesIndexesSplitView setPosition:[tablesIndexesSplitView frame].size.height-130 ofDividerAtIndex:0];
}

#pragma mark -
#pragma mark Index sheet methods

/**
 * Closes the current sheet and stops the modal session.
 */
- (IBAction)closeSheet:(id)sender
{
	[NSApp endSheet:[sender window] returnCode:[sender tag]];
	[[sender window] orderOut:self];
}

#pragma mark -
#pragma mark Additional methods

/**
 * Reset table's sequence to a specific value
 * PostgreSQL uses sequences instead of MySQL's AUTO_INCREMENT
 *
 * @param value The new sequence value as NSNumber
 */
- (void)setAutoIncrementTo:(NSNumber *)value
{
	NSString *selTable = [tablesListInstance tableName];

	if (selTable == nil || ![selTable length]) return;

	if (value == nil) {
		// reload data and bail
		[tableDataInstance resetAllData];
		[extendedTableInfoInstance loadTable:selTable];
		[tableInfoInstance tableChanged:nil];
		return;
	}

	// PostgreSQL: Find the sequence name for SERIAL/IDENTITY columns and reset it
	// First, find any columns with nextval() in their default value
	SPPostgresResult *seqResult = [postgresConnection queryString:[NSString stringWithFormat:
		@"SELECT pg_get_serial_sequence(%@, column_name) AS seq_name "
		@"FROM information_schema.columns "
		@"WHERE table_schema = 'public' AND table_name = %@ "
		@"AND column_default LIKE 'nextval%%'",
		[selTable tickQuotedString], [selTable tickQuotedString]]];

	[seqResult setReturnDataAsStrings:YES];

	if ([seqResult numberOfRows] > 0) {
		NSDictionary *row = [seqResult getRowAsDictionary];
		NSString *sequenceName = [row objectForKey:@"seq_name"];

		if (sequenceName && ![sequenceName isKindOfClass:[NSNull class]] && [sequenceName length]) {
			// Reset the sequence using ALTER SEQUENCE ... RESTART WITH
			[postgresConnection queryString:[NSString stringWithFormat:
				@"ALTER SEQUENCE %@ RESTART WITH %llu",
				sequenceName, [value unsignedLongLongValue]]];
		}
	}

	if ([postgresConnection queryErrored]) {
		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to reset the sequence of table '%@'.\n\nPostgreSQL said: %@", @"error resetting sequence informative message"), selTable, [postgresConnection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")] callback:nil];
	}

	// reload data
	[tableDataInstance resetStatusData];
	if([tableDocumentInstance currentlySelectedView] == SPTableViewStatus) {
		[tableDataInstance resetAllData];
		[extendedTableInfoInstance loadTable:selTable];
	}

	[tableInfoInstance tableChanged:nil];
}

/**
 * Converts the supplied result to an array containing a (mutable) dictionary for each row
 */
- (NSArray *)convertIndexResultToArray:(SPPostgresResult *)theResult
{
	NSUInteger numOfRows = (NSUInteger)[theResult numberOfRows];
	NSMutableArray *tempResult = [NSMutableArray arrayWithCapacity:numOfRows];
	NSMutableDictionary *tempRow;
	NSArray *keys;
	NSInteger i;
	id prefsNullValue = [prefs objectForKey:SPNullValue];

	// Ensure table information is returned as strings to avoid problems with some server versions
	[theResult setReturnDataAsStrings:YES];

	for ( i = 0 ; i < (NSInteger)numOfRows ; i++ ) {
		tempRow = [NSMutableDictionary dictionaryWithDictionary:[theResult getRowAsDictionary]];

		// Replace NSNull instances with the NULL string from preferences
		keys = [tempRow allKeys];
		for (id theKey in keys) {
			if ([[tempRow objectForKey:theKey] isNSNull])
				[tempRow setObject:prefsNullValue forKey:theKey];
		}

		// Update some fields to be more human-readable or GUI compatible
		id extraValue = [tempRow objectForKey:@"Extra"];
		if (extraValue == nil || [extraValue isKindOfClass:[NSNull class]] ||
		    ([extraValue isKindOfClass:[NSString class]] && [extraValue isEqualToString:@""])) {
			[tempRow setObject:@"None" forKey:@"Extra"];
		}
		id nullValue = [tempRow objectForKey:@"Null"];
		BOOL isNullable = NO;
		if ([nullValue isKindOfClass:[NSString class]]) {
			isNullable = [nullValue isEqualToString:@"YES"];
		} else if ([nullValue isKindOfClass:[NSNumber class]]) {
			isNullable = [nullValue boolValue];
		}
		[tempRow setObject:isNullable ? @"1" : @"0" forKey:@"Null"];
		[tempResult addObject:tempRow];
	}

	return tempResult;
}

/**
 * A method to be called whenever the selection changes or the table would be reloaded
 * or altered; checks whether the current row is being edited, and if so attempts to save
 * it.  Returns YES if no save was necessary or the save was successful, and NO if a save
 * was necessary but failed - also reselecting the row for re-editing.
 */
- (BOOL)saveRowOnDeselect
{

	// Save any edits which have been made but not saved to the table yet;
	// but not for any NSSearchFields which could cause a crash for undo, redo.
	id currentFirstResponder = [[tableDocumentInstance parentWindowControllerWindow] firstResponder];
	if (currentFirstResponder && [currentFirstResponder isKindOfClass:[NSView class]] && [(NSView *)currentFirstResponder isDescendantOf:tableSourceView]) {
		[[tableDocumentInstance parentWindowControllerWindow] endEditingFor:nil];
	}

	// If no rows are currently being edited, or a save is already in progress, return success at once.
	if (!isEditingRow || isSavingRow) return YES;
	isSavingRow = YES;

	// Attempt to save the row, and return YES if the save succeeded.
	if ([self addRowToDB]) {
		isSavingRow = NO;
		return YES;
	}

	// Saving failed - return failure.
	isSavingRow = NO;
	return NO;
}

/**
 * Tries to write row to PostgreSQL database
 * returns YES if row written to db, otherwise NO
 * returns YES if no row is being edited and nothing has to be written to db
 */
- (BOOL)addRowToDB
{
	if ((!isEditingRow) || (currentlyEditingRow == -1)) return YES;

	// Save any edits which have been started but not saved to the underlying table/data structures
	// yet - but not if currently undoing/redoing, as this can cause a processing loop
	if (![[[[tableSourceView window] firstResponder] undoManager] isUndoing] && ![[[[tableSourceView window] firstResponder] undoManager] isRedoing]) {
		[[tableSourceView window] endEditingFor:nil];
	}

	NSDictionary *theRow = [[self activeFieldsSource] safeObjectAtIndex:currentlyEditingRow];

	NSMutableString *queryString = [NSMutableString string];

	if (isEditingNewRow) {
		// PostgreSQL: ADD COLUMN syntax
		[queryString appendFormat:@"ALTER TABLE %@ ADD COLUMN ", [selectedTable postgresQuotedIdentifier]];
		[queryString appendString:[self _buildPartialColumnDefinitionString:theRow]];

		// Process index if given for fields set to AUTO_INCREMENT (SERIAL in PostgreSQL)
		if (autoIncrementIndex) {
			if ([autoIncrementIndex isEqualToString:@"PRIMARY KEY"]) {
				[queryString appendString:@" PRIMARY KEY"];
			}
			else {
				// Add index separately
				[queryString appendFormat:@"; CREATE INDEX ON %@ (%@)",
					[selectedTable postgresQuotedIdentifier],
					[[theRow objectForKey:@"name"] postgresQuotedIdentifier]];
			}
		}
	}
	else {
		// PostgreSQL: Modifying existing column requires multiple ALTER statements
		NSString *oldName = [oldRow objectForKey:@"name"];
		NSString *newName = [theRow objectForKey:@"name"];
		NSString *newType = [[theRow objectForKey:@"type"] uppercaseString];

		// Check if column name changed
		if (![oldName isEqualToString:newName]) {
			[queryString appendFormat:@"ALTER TABLE %@ RENAME COLUMN %@ TO %@; ",
				[selectedTable postgresQuotedIdentifier],
				[oldName postgresQuotedIdentifier],
				[newName postgresQuotedIdentifier]];
		}

		// Change column type
		[queryString appendFormat:@"ALTER TABLE %@ ALTER COLUMN %@ TYPE %@",
			[selectedTable postgresQuotedIdentifier],
			[newName postgresQuotedIdentifier],
			newType];

		// Add length if specified
		if ([theRow objectForKey:@"length"] && [[[theRow objectForKey:@"length"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]) {
			[queryString appendFormat:@"(%@)", [theRow objectForKey:@"length"]];
		}

		// Handle NULL constraint
		if ([[theRow objectForKey:@"null"] integerValue] == 0) {
			[queryString appendFormat:@"; ALTER TABLE %@ ALTER COLUMN %@ SET NOT NULL",
				[selectedTable postgresQuotedIdentifier],
				[newName postgresQuotedIdentifier]];
		} else {
			[queryString appendFormat:@"; ALTER TABLE %@ ALTER COLUMN %@ DROP NOT NULL",
				[selectedTable postgresQuotedIdentifier],
				[newName postgresQuotedIdentifier]];
		}

		// Handle DEFAULT value
		NSString *defaultValue = [theRow objectForKey:@"default"];
		if (defaultValue && [defaultValue length] > 0) {
			if ([defaultValue isEqualToString:[prefs objectForKey:SPNullValue]]) {
				[queryString appendFormat:@"; ALTER TABLE %@ ALTER COLUMN %@ SET DEFAULT NULL",
					[selectedTable postgresQuotedIdentifier],
					[newName postgresQuotedIdentifier]];
			} else {
				[queryString appendFormat:@"; ALTER TABLE %@ ALTER COLUMN %@ SET DEFAULT %@",
					[selectedTable postgresQuotedIdentifier],
					[newName postgresQuotedIdentifier],
					[postgresConnection escapeAndQuoteString:defaultValue]];
			}
		} else {
			[queryString appendFormat:@"; ALTER TABLE %@ ALTER COLUMN %@ DROP DEFAULT",
				[selectedTable postgresQuotedIdentifier],
				[newName postgresQuotedIdentifier]];
		}
	}

	isCurrentExtraAutoIncrement = NO;
	autoIncrementIndex = nil;

	// Execute query
	[postgresConnection queryString:queryString];

	if (![postgresConnection queryErrored]) {
		isEditingRow = NO;
		isEditingNewRow = NO;
		currentlyEditingRow = -1;

		[tableDataInstance resetAllData];
		[tableDocumentInstance setStatusRequiresReload:YES];
		[self loadTable:selectedTable];

		// Mark the content table for refresh
		[tableDocumentInstance setContentRequiresReload:YES];

		// Query the structure of all databases in the background
		[[tableDocumentInstance databaseStructureRetrieval] queryDbStructureInBackgroundWithUserInfo:[NSDictionary dictionaryWithObjectsAndKeys:@YES, @"forceUpdate", selectedTable, @"affectedItem", [NSNumber numberWithInteger:[tablesListInstance tableType]], @"affectedItemType", nil]];

		return YES;
	}
	else {
		// Check for PostgreSQL "table does not exist" error pattern
		// Guard against nil error message - if nil, assume table exists but query failed for other reason
		NSString *errorMsg = [postgresConnection lastErrorMessage];
		BOOL tableDoesNotExist = NO;

		if (errorMsg != nil) {
			NSString *lowerErrorMsg = [errorMsg lowercaseString];
			tableDoesNotExist = [lowerErrorMsg containsString:@"does not exist"];
		}

		// Also check if connection was lost
		if (![postgresConnection isConnected]) {
			tableDoesNotExist = YES;
		}

		if (tableDoesNotExist) { // If the current table doesn't exist anymore
			[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to alter table '%@'.\n\nPostgreSQL said: %@", @"error while trying to alter table message"), selectedTable, [postgresConnection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")] callback:nil];

			isEditingRow = NO;
			isEditingNewRow = NO;
			currentlyEditingRow = -1;
			[tableFields removeAllObjects];
			filteredTableFields = nil;
			[tableSourceView reloadData];
			[indexesTableView reloadData];
			[addFieldButton setEnabled:NO];
			[duplicateFieldButton setEnabled:NO];
			[removeFieldButton setEnabled:NO];
			[addIndexButton setEnabled:NO];
			[removeIndexButton setEnabled:NO];
			[editTableButton setEnabled:NO];
			[tablesListInstance updateTables:self];
			return NO;
		}

		if (isEditingNewRow) {
			NSString *alertMessage = [NSString stringWithFormat:NSLocalizedString(@"An error occurred when trying to add the field '%@' via\n\n%@\n\nPostgreSQL said: %@", @"error adding field informative message"), [theRow objectForKey:@"name"], queryString, [postgresConnection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")];
			[NSAlert createDefaultAlertWithTitle:NSLocalizedString(@"Error adding field", @"error adding field message") message:alertMessage primaryButtonTitle:NSLocalizedString(@"Edit row", @"Edit row button") primaryButtonHandler:^{
				[self addRowSheetPrimaryAction];
			} cancelButtonHandler:^{
				[self cancelRowEditing];
				[self->tableSourceView reloadData];
			}];

		} else {
			NSString *alertMessage = [NSString stringWithFormat:NSLocalizedString(@"An error occurred when trying to change the field '%@' via\n\n%@\n\nPostgreSQL said: %@", @"error changing field informative message"), [theRow objectForKey:@"name"], queryString, [postgresConnection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")];
			[NSAlert createDefaultAlertWithTitle:NSLocalizedString(@"Error changing field", @"error changing field message") message:alertMessage primaryButtonTitle:NSLocalizedString(@"Edit row", @"Edit row button") primaryButtonHandler:^{
				[self addRowSheetPrimaryAction];
			} cancelButtonHandler:^{
				[self cancelRowEditing];
				[self->tableSourceView reloadData];
			}];
		}

		return NO;
	}
}

/**
 * Takes the column definition from a dictionary and returns the it to be used
 * with an ALTER statement, e.g.:
 *  `col1` INT(10) UNSIGNED NOT NULL AUTO_INCREMENT
 */
- (NSString *)_buildPartialColumnDefinitionString:(NSDictionary *)theRow
{
	NSMutableString *queryString;
	BOOL fieldDefIncludesLen = NO;
	
	NSString *theRowType = @"";
	NSString *theRowExtra = @"";
    NSString *theRowGeneratedAlways = @"";

	BOOL specialFieldTypes = NO;

	if ([theRow objectForKey:@"type"])
		theRowType = [[[theRow objectForKey:@"type"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];

	if ([theRow objectForKey:@"Extra"])
		theRowExtra = [[[theRow objectForKey:@"Extra"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];

    if ([theRow objectForKey:@"generatedalways"])
        theRowGeneratedAlways = [[[theRow objectForKey:@"generatedalways"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];

	queryString = [NSMutableString stringWithString:[[theRow objectForKey:@"name"] postgresQuotedIdentifier]];

	[queryString appendString:@" "];
	[queryString appendString:theRowType];

	// Check for pre-defined field type SERIAL
	if([theRowType isEqualToString:@"SERIAL"]) {
		specialFieldTypes = YES;
    }
    
	// Check for pre-defined field type BOOL(EAN)
	else if([theRowType rangeOfRegex:@"(?i)bool(ean)?"].length) {
		specialFieldTypes = YES;

		if ([[theRow objectForKey:@"null"] integerValue] == 0) {
			[queryString appendString:@"\n NOT NULL"];
		} else {
			[queryString appendString:@"\n NULL"];
		}
		// If a NULL value has been specified, and NULL is allowed, specify DEFAULT NULL
		if ([[theRow objectForKey:@"default"] isEqualToString:[prefs objectForKey:SPNullValue]]) 
		{
			if ([[theRow objectForKey:@"null"] integerValue] == 1) {
				[queryString appendString:@"\n DEFAULT NULL "];
			}
		}
		else if (![(NSString *)[theRow objectForKey:@"default"] length]) {
			;
		}
		// Otherwise, use the provided default
		else {
			[queryString appendFormat:@"\n DEFAULT %@ ", [postgresConnection escapeAndQuoteString:[theRow objectForKey:@"default"]]];
		}
	}

	// Check for Length specification
	else if ([theRow objectForKey:@"length"] && [[[theRow objectForKey:@"length"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]) {
		fieldDefIncludesLen = YES;
		[queryString appendFormat:@"(%@)", [theRow objectForKey:@"length"]];
	}

	if(!specialFieldTypes) {

		// PostgreSQL handles encoding/collation at database level, not per-column
		// CHARACTER SET, BINARY, and COLLATE are MySQL-specific keywords
		// and are not supported for column definitions in PostgreSQL
		if ([fieldValidation isFieldTypeString:theRowType]) {
			// PostgreSQL uses COLLATE at column level but with different syntax
			NSString *fieldCollation = [theRow objectForKey:@"collationName"];
			if([fieldCollation length]) {
				[queryString appendFormat:@" COLLATE \"%@\"", fieldCollation];
			}
		}
		// PostgreSQL doesnt support UNSIGNED or ZEROFILL - these are MySQL-only keywords
		else if ([fieldValidation isFieldTypeNumeric:theRowType] && (![theRowType isEqualToString:@"BIT"])) {
			// UNSIGNED and ZEROFILL generation removed for PostgreSQL compatibility
		}

        // Don't provide NULL / NOT NULL for generated field
        if (![theRowGeneratedAlways length]) {
            if ([[theRow objectForKey:@"null"] integerValue] == 0 || [theRowExtra isEqualToString:@"SERIAL DEFAULT VALUE"]) {
                [queryString appendString:@"\n NOT NULL"];
            }
            else {
                [queryString appendString:@"\n NULL"];
            }
        }

		// Don't provide any defaults for auto-increment & generated field
		if (![theRowExtra isEqualToString:@"AUTO_INCREMENT"] && ![theRowGeneratedAlways length]) {
			NSArray *matches;
			NSString *defaultValue = [theRow objectForKey:@"default"];
            // Check if defaultValue is an expression - Must be surrunded by ( and )
            BOOL defaultValueIsExpression = NO;
            BOOL defaultValueIsString = NO;
            if ([defaultValue length]) {
                NSString *trimmedWhiteSpace = [defaultValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                // if trimmed string is empty, revert to original to avoid crash
                if ([trimmedWhiteSpace isEqualToString: @""]) {
                  trimmedWhiteSpace = defaultValue;
                }
                unichar firstChar = [trimmedWhiteSpace characterAtIndex:0];
                unichar lastChar = [trimmedWhiteSpace characterAtIndex:[trimmedWhiteSpace length] - 1];
                // Check if defaultValue is an expression
                if (lastChar == ')') {
                    // To check if brackets appear in pairs, then we assume the string is possibly an expression
                    // if it's expression by this check so query will be executed and an error will be shown
                    // TODO: Best possible solution would be checking the input value against the list of known functions/keywords
                    NSUInteger checkBracketPairs = 0;
                    for (NSUInteger i = 0; i < [trimmedWhiteSpace length]; i++) {
                        if ([trimmedWhiteSpace characterAtIndex:i] == '(') {
                          checkBracketPairs++;
                        } else if ([trimmedWhiteSpace characterAtIndex:i] == ')') {
                          checkBracketPairs--;
                        }
                    }
                  
                  // it means brackets are in pairs
                  if (checkBracketPairs == 0) {
                    defaultValueIsExpression = YES;
                  }
                }
                // Check if defaultValue is a string in quotes (single or double)
                else if ( ((firstChar == '"') && (lastChar = '"')) || ((firstChar == '\'') && (lastChar = '\'')) ) {
                    defaultValueIsString = YES;
                }
            }

            if([defaultValue length] == 0) {
                //DON'T APPEND AN EMPTY DEFAULT VALUE CLAUSE
            }

			// If a NULL value has been specified, and NULL is allowed, specify DEFAULT NULL
			else if ([defaultValue isEqualToString:[prefs objectForKey:SPNullValue]])
			{
				if ([[theRow objectForKey:@"null"] integerValue] == 1) {
					[queryString appendString:@"\n DEFAULT NULL"];
				}
			}
			// Otherwise, if CURRENT_TIMESTAMP was specified for timestamps/datetimes, use that
			else if ([theRowType isInArray:@[@"TIMESTAMP",@"DATETIME"]] &&
					[(matches = [[defaultValue uppercaseString] captureComponentsMatchedByRegex:SPCurrentTimestampPattern]) count])
			{
				[queryString appendString:@"\n DEFAULT CURRENT_TIMESTAMP"];
				NSString *userLen = [matches objectAtIndex:1];
				// mysql 5.6.4+ allows DATETIME(n) for fractional seconds, which in turn requires CURRENT_TIMESTAMP(n) with the same n!
				// Also, if the user explicitly added one we should never ignore that.
				if([userLen length] || fieldDefIncludesLen) {
					[queryString appendFormat:@"(%@)",([userLen length]? userLen : [theRow objectForKey:@"length"])];
				}
			}
			// If the field is of type BIT, permit the use of single qoutes and also don't quote the default value.
			// For example, use DEFAULT b'1' as opposed to DEFAULT 'b\'1\'' which results in an error.
			else if ([theRowType isEqualToString:@"BIT"]) {
				[queryString appendFormat:@"\n DEFAULT %@", defaultValue];
			}
            // *CHAR, *TEXT and *ENUM must be wrapped with single or double quotes for empty string and other default value. Expression are provided as is. TIMESTAMP, DATETIME and DATE must always be wrapped in quotes.
            else if ([theRowType hasSuffix:@"CHAR"] || [theRowType hasSuffix:@"TEXT"] || [theRowType hasSuffix:@"ENUM"] || [theRowType isInArray:@[@"TIMESTAMP",@"DATETIME",@"DATE"]]) {
                // If default value is not an expresion or a string, add quotes.
                if (!defaultValueIsExpression && !defaultValueIsString)
                    [queryString appendFormat:@"\n DEFAULT %@", [postgresConnection escapeAndQuoteString:defaultValue]];
                else
                    [queryString appendFormat:@"\n DEFAULT %@", defaultValue];
            }
			//for ENUM field type
			else if (([defaultValue length]==0) && [theRowType isEqualToString:@"ENUM"]) {
				[queryString appendFormat:@" "];
			}
            // Otherwise, use the provided default (Can be an expression, int value....)
            else  {
                [queryString appendFormat:@"\n DEFAULT %@", defaultValue];
//                [queryString appendFormat:@"\n DEFAULT %@", [postgresConnection escapeAndQuoteString:defaultValue]];
            }
		}

        // Generated field - set keywords GENERATED ALWAYS AS
        if ([theRowExtra isEqualToString:@"VIRTUAL GENERATED"] || [theRowExtra isEqualToString:@"STORED GENERATED"]) {
            [queryString appendFormat:@"\n %@", @"GENERATED ALWAYS AS"];
        // Other extra
        } else if ([theRowExtra length] && ![theRowExtra isEqualToString:@"NONE"]) {
			[queryString appendFormat:@"\n %@", theRowExtra];
			//fix our own default item if needed
			if([theRowExtra isEqualToString:@"ON UPDATE CURRENT_TIMESTAMP"] && fieldDefIncludesLen) {
				[queryString appendFormat:@"(%@)",[theRow objectForKey:@"length"]];
			}
		}
	}

	// Unparsed details - column formats, storage, reference definitions
	if ([(NSString *)[theRow objectForKey:@"unparsed"] length]) {
		[queryString appendFormat:@"\n %@", [theRow objectForKey:@"unparsed"]];
	}

    // Generated field can be VIRTUAL or STORED
    if ([theRowGeneratedAlways length]) {
        [queryString appendFormat:@"\n %@", [theRow objectForKey:@"generatedalways"]];
    }

    // Any column comments
    if ([(NSString *)[theRow objectForKey:@"comment"] length]) {
        [queryString appendFormat:@"\n COMMENT %@", [postgresConnection escapeAndQuoteString:[theRow objectForKey:@"comment"]]];
    }

	return queryString;
}

/**
 * A method to show an error sheet after a short delay, so that it can
 * be called from within an endSheet selector. This should be called on
 * the main thread.
 */
- (void)showErrorSheetWith:(NSDictionary *)errorDictionary
{
	// If this method has been called directly, invoke a delay.  Invoking the delay
	// on the main thread ensures the timer fires on the main thread.
	if (![errorDictionary objectForKey:@"delayed"]) {
		NSMutableDictionary *delayedErrorDictionary = [NSMutableDictionary dictionaryWithDictionary:errorDictionary];
		[delayedErrorDictionary setObject:@YES forKey:@"delayed"];
		[self performSelector:@selector(showErrorSheetWith:) withObject:delayedErrorDictionary afterDelay:0.3];
		return;
	}

	// Display the error sheet
	[NSAlert createWarningAlertWithTitle:[errorDictionary objectForKey:@"title"] message:[errorDictionary objectForKey:@"message"] callback:nil];
}

/**
 * Menu validation.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	// Remove field
	if ([menuItem action] == @selector(removeField:)) {
		return (([tableSourceView numberOfSelectedRows] == 1) && ([tableSourceView numberOfRows] > 1));
	}

	// Duplicate field
	if ([menuItem action] == @selector(duplicateField:)) {
		return ([tableSourceView numberOfSelectedRows] == 1);
	}
	
	//show optimized field type
	if([menuItem action] == @selector(showOptimizedFieldType:)) {
		return ([tableSourceView numberOfSelectedRows] == 1);
	}

	// Reset AUTO_INCREMENT
	if ([menuItem action] == @selector(resetAutoIncrement:)) {
		return [indexesController validateMenuItem:menuItem];
	}

	return YES;
}

#pragma mark -
#pragma mark Alert sheet methods

- (void)addRowSheetPrimaryAction {

	// Problem: reentering edit mode for first cell doesn't function
	[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:currentlyEditingRow] byExtendingSelection:NO];
	[tableSourceView performSelector:@selector(keyDown:) withObject:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSMakePoint(0,0) modifierFlags:0 timestamp:0 windowNumber:[[tableDocumentInstance parentWindowControllerWindow] windowNumber] context:[NSGraphicsContext currentContext] characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:0x24] afterDelay:0.0];

	[tableSourceView reloadData];
}

#pragma mark -
#pragma mark KVO methods

/**
 * This method is called as part of Key Value Observing which is used to watch for preference changes which effect the interface.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	// Display table veiew vertical gridlines preference changed
	if ([keyPath isEqualToString:SPDisplayTableViewVerticalGridlines]) {
        [tableSourceView setGridStyleMask:([[change objectForKey:NSKeyValueChangeNewKey] boolValue]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	}
	// Table font preference changed
	else if ([keyPath isEqualToString:SPGlobalFontSettings]) {
		NSFont *tableFont = [NSUserDefaults getFont];
		[tableSourceView setRowHeight:4.0f + NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];
		[indexesTableView setRowHeight:4.0f + NSSizeToCGSize([@"{ǞṶḹÜ∑zgyf" sizeWithAttributes:@{NSFontAttributeName : tableFont}]).height];
		[tableSourceView setFont:tableFont];
		[indexesTableView setFont:tableFont];
		[tableSourceView reloadData];
		[indexesTableView reloadData];
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

#pragma mark -
#pragma mark Accessors

/**
 * Sets the connection (received from SPDatabaseDocument) and makes things that have to be done only once
 */
- (void)setConnection:(SPPostgresConnection *)theConnection
{
    postgresConnection = nil;
    postgresConnection = theConnection;
	
	// Set the indexes controller connection
	[indexesController setConnection:postgresConnection];
	
	// Set up tableView
	[tableSourceView registerForDraggedTypes:@[SPDefaultPasteboardDragType]];
}

/**
 * Get the default value for a specified field
 */
- (NSString *)defaultValueForField:(NSString *)field
{
	if ( ![defaultValues objectForKey:field] ) {
		return [prefs objectForKey:SPNullValue];
	} else if ( [[defaultValues objectForKey:field] isNSNull] ) {
		return [prefs objectForKey:SPNullValue];
	} else {
		return [defaultValues objectForKey:field];
	}
}

/**
 * Returns an array containing the field names of the selected table
 */
- (NSArray *)fieldNames
{
	NSMutableArray *tempArray = [NSMutableArray array];
	NSEnumerator *enumerator;
	id field;

	//load table if not already done
	if ( ![tableDocumentInstance structureLoaded] ) {
		[self loadTable:[tableDocumentInstance table]];
	}

	//get field names
	enumerator = [tableFields objectEnumerator];
	while ( (field = [enumerator nextObject]) ) {
		[tempArray addObject:[field objectForKey:@"name"]];
	}

	return [NSArray arrayWithArray:tempArray];
}

/**
 * Returns a dictionary containing enum/set field names as key and possible values as array
 */
- (NSDictionary *)enumFields
{
	return [NSDictionary dictionaryWithDictionary:enumFields];
}

/**
 * Returns a dictionary describing the source of the table to be used for printing purposes. The object accessible
 * via the key 'structure' is an array of the tables fields, where the first element is always the field names
 * and each subsequent element is the field data. This is also true for the table's indexes, which are accessible
 * via the key 'indexes'.
 */
- (NSDictionary *)tableSourceForPrinting
{
	NSUInteger i, j;
	NSMutableArray *tempResult  = [NSMutableArray array];
	NSMutableArray *tempResult2 = [NSMutableArray array];

	NSString *nullValue = [prefs stringForKey:SPNullValue];
	CFStringRef escapedNullValue = CFXMLCreateStringByEscapingEntities(NULL, ((CFStringRef)nullValue), NULL);

	SPPostgresResult *structureQueryResult = [postgresConnection queryString:[NSString stringWithFormat:@"SELECT column_name AS Field, data_type AS Type, is_nullable AS \"Null\", column_default AS \"Default\" FROM information_schema.columns WHERE table_name = %@", [selectedTable postgresQuotedIdentifier]]];
	SPPostgresResult *indexesQueryResult   = [postgresConnection queryString:[NSString stringWithFormat:@"SELECT indexname AS Key_name, indexdef AS Index_type FROM pg_indexes WHERE tablename = %@", [selectedTable postgresQuotedIdentifier]]];

	[structureQueryResult setReturnDataAsStrings:YES];
	[indexesQueryResult setReturnDataAsStrings:YES];

	[tempResult safeAddObject:[structureQueryResult fieldNames]];

	NSMutableArray *temp = [[indexesQueryResult fieldNames] mutableCopy];

	// Remove the 'table' column
	[temp removeObjectAtIndex:0];

	[tempResult2 safeAddObject:temp];

	for (i = 0; i < [structureQueryResult numberOfRows]; i++) {
		NSMutableArray *row = [[structureQueryResult getRowAsArray] mutableCopy];

		// For every NULL value replace it with the user's NULL value placeholder so we can actually print it
		for (j = 0; j < [row count]; j++)
		{
			if ([[row objectAtIndex:j] isNSNull]) {
				[row safeReplaceObjectAtIndex:j withObject:(__bridge NSString *)escapedNullValue];
			}
		}

		[tempResult safeAddObject:row];
	}

	for (i = 0; i < [indexesQueryResult numberOfRows]; i++) {
		NSMutableArray *eachIndex = [[indexesQueryResult getRowAsArray] mutableCopy];

		// Remove the 'table' column values
		[eachIndex removeObjectAtIndex:0];

		// For every NULL value replace it with the user's NULL value placeholder so we can actually print it
		for (j = 0; j < [eachIndex count]; j++)
		{
			if ([[eachIndex objectAtIndex:j] isNSNull]) {
				[eachIndex safeReplaceObjectAtIndex:j withObject:(__bridge NSString *)escapedNullValue];
			}
		}

		[tempResult2 safeAddObject:eachIndex];
	}

	CFRelease(escapedNullValue);
	return [NSDictionary dictionaryWithObjectsAndKeys:tempResult, @"structure", tempResult2, @"indexes", nil];
}

- (NSMutableArray *)activeFieldsSource {
	return filteredTableFields == nil ? tableFields : filteredTableFields;
}

#pragma mark -
#pragma mark Task interaction

/**
 * Disable all content interactive elements during an ongoing task.
 */
- (void)startDocumentTaskForTab:(NSNotification *)aNotification
{
	// Only proceed if this view is selected.
	if (![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableStructure]) return;

	[tableSourceView setEnabled:NO];
	[addFieldButton setEnabled:NO];
	[removeFieldButton setEnabled:NO];
	[duplicateFieldButton setEnabled:NO];
	[reloadFieldsButton setEnabled:NO];
	[editTableButton setEnabled:NO];

	[indexesTableView setEnabled:NO];
	[addIndexButton setEnabled:NO];
	[removeIndexButton setEnabled:NO];
	[refreshIndexesButton setEnabled:NO];
}

/**
 * Enable all content interactive elements after an ongoing task.
 */
- (void)endDocumentTaskForTab:(NSNotification *)aNotification
{
	// Only re-enable elements if the current tab is the structure view
	if (![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableStructure]) return;

	BOOL editingEnabled = ([tablesListInstance tableType] == SPTableTypeTable);

	[tableSourceView setEnabled:YES];
	[tableSourceView displayIfNeeded];
	[addFieldButton setEnabled:editingEnabled];

	if (editingEnabled && [tableSourceView numberOfSelectedRows] > 0) {
		[removeFieldButton setEnabled:YES];
		[duplicateFieldButton setEnabled:YES];
	}

	[reloadFieldsButton setEnabled:YES];
	[editTableButton setEnabled:YES];

	[indexesTableView setEnabled:YES];
	[indexesTableView displayIfNeeded];

	[addIndexButton setEnabled:editingEnabled && ![[[tableDataInstance statusValueForKey:@"Engine"] uppercaseString] isEqualToString:@"CSV"]];
	[removeIndexButton setEnabled:(editingEnabled && ([indexesTableView numberOfSelectedRows] > 0))];
	[refreshIndexesButton setEnabled:YES];
}

#pragma mark -
#pragma mark Private API

/**
 * Removes a field from the current table and the dependent foreign key if specified.
 */
- (void)_removeFieldAndForeignKey:(NSNumber *)removeForeignKey
{
	SPMainQSync(^{
		@autoreleasepool {
			// Remove the foreign key before the field if required
			if ([removeForeignKey boolValue]) {
				NSString *relationName = @"";
				NSString *field = [[[self activeFieldsSource] safeObjectAtIndex:[self->tableSourceView selectedRow]] safeObjectForKey:@"name"];

				// Get the foreign key name
				for (NSDictionary *constraint in [self->tableDataInstance getConstraints])
				{
					for (NSString *column in [constraint safeObjectForKey:@"columns"])
					{
						if ([column isEqualToString:field]) {
							relationName = [constraint safeObjectForKey:@"name"];
							break;
						}
					}
				}

				[self->postgresConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ DROP CONSTRAINT %@", [self->selectedTable postgresQuotedIdentifier], [relationName postgresQuotedIdentifier]]];

				// Check for errors, but only if the query wasn't cancelled
				if ([self->postgresConnection queryErrored] && ![self->postgresConnection lastQueryWasCancelled]) {
					NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
					[errorDictionary setObject:NSLocalizedString(@"Unable to delete relation", @"error deleting relation message") forKey:@"title"];
					[errorDictionary setObject:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to delete the relation '%@'.\n\nPostgreSQL said: %@", @"error deleting relation informative message"), relationName, [self->postgresConnection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")] forKey:@"message"];
					[[self onMainThread] showErrorSheetWith:errorDictionary];
				}
			}

			// Remove field
			[self->postgresConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ DROP COLUMN %@",
																	[self->selectedTable postgresQuotedIdentifier], [[[[self activeFieldsSource] safeObjectAtIndex:[self->tableSourceView selectedRow]] safeObjectForKey:@"name"] postgresQuotedIdentifier]]];

			// Check for errors, but only if the query wasn't cancelled
			if ([self->postgresConnection queryErrored] && ![self->postgresConnection lastQueryWasCancelled]) {
				NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
				[errorDictionary setObject:NSLocalizedString(@"Error", @"error") forKey:@"title"];
				[errorDictionary setObject:[NSString stringWithFormat:NSLocalizedString(@"Couldn't delete field %@.\nPostgreSQL said: %@", @"message of panel when field cannot be deleted"),
																	  [[[self activeFieldsSource] objectAtIndex:[self->tableSourceView selectedRow]] objectForKey:@"name"],
																	  [self->postgresConnection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error")] forKey:@"message"];

				[[self onMainThread] showErrorSheetWith:errorDictionary];
			}
			else {
				[self->tableDataInstance resetAllData];

				// Refresh relevant views
				[self->tableDocumentInstance setStatusRequiresReload:YES];
				[self->tableDocumentInstance setContentRequiresReload:YES];
				[self->tableDocumentInstance setRelationsRequiresReload:YES];

				[self loadTable:self->selectedTable];
			}

			[self->tableDocumentInstance endTask];

			// Preserve focus on table for keyboard navigation
			[[self->tableDocumentInstance parentWindowControllerWindow] makeFirstResponder:self->tableSourceView];
		}
	});
}

#pragma mark -
#pragma mark Table loading

/**
 * Loads aTable, puts it in an array, updates the tableViewColumns and reloads the tableView.
 */
- (void)loadTable:(NSString *)aTable
{
	NSMutableDictionary *theTableEnumLists = [NSMutableDictionary dictionary];

	// Check whether a save of the current row is required.
	if (![[self onMainThread] saveRowOnDeselect]) return;

	// If no table is selected, reset the interface and return
	if (!aTable || ![aTable length]) {
		[[self onMainThread] setTableDetails:nil];
		return;
	}

	NSMutableArray *theTableFields = [[NSMutableArray alloc] init];

	// Make a mutable copy out of the cached [tableDataInstance columns] since we're adding infos
	for (id col in [tableDataInstance columns])
	{
		[theTableFields addObject:[col mutableCopy]];
	}

	// Retrieve the indexes for the table
	SPPostgresResult *indexesQueryResult   = [postgresConnection queryString:[NSString stringWithFormat:@"SELECT indexname AS Key_name, indexdef AS Index_type FROM pg_indexes WHERE tablename = %@", [selectedTable postgresQuotedIdentifier]]];

	// If an error occurred, reset the interface and abort
	if ([postgresConnection queryErrored]) {
		[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SPostgresQueryHasBeenPerformed" object:tableDocumentInstance];
		[[self onMainThread] setTableDetails:nil];

		if ([postgresConnection isConnected]) {
			NSString *lastError = [postgresConnection lastErrorMessage] ?: NSLocalizedString(@"Unknown error", @"unknown error");
			[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while retrieving information.\nPostgreSQL said: %@", @"message of panel when retrieving information failed"), lastError] callback:nil];
		}

		return;
	}

	// Process the indexes into a local array of dictionaries
	NSArray *tableIndexes = [self convertIndexResultToArray:indexesQueryResult];

	// Set the Key column
	for (NSDictionary *index in tableIndexes)
	{
		for (id field in theTableFields)
		{
			if ([[field objectForKey:@"name"] isEqualToString:[index objectForKey:@"Column_name"]]) {
				if ([[index objectForKey:@"Key_name"] isEqualToString:@"PRIMARY"]) {
					[field setObject:@"PRI" forKey:@"Key"];
				}
				else {
					if ([[field objectForKey:@"typegrouping"] isEqualToString:@"geometry"] &&
						[[index objectForKey:@"Index_type"] isEqualToString:@"SPATIAL"] &&
						![field objectForKey:@"Key"]) {
						[field setObject:@"SPA" forKey:@"Key"];
					}
					else {
						[field setObject:[[index objectForKey:@"Non_unique"] isEqualToString:@"1"] ? @"MUL" : @"UNI" forKey:@"Key"];
					}
				}

				break;
			}
		}
	}

	// Set up the encoding PopUpButtonCell
	NSArray *encodings  = [databaseDataInstance getDatabaseCharacterSetEncodings];

	SPMainQSync(^{
		@try {
			[self->encodingPopupCell removeAllItems];

			if (encodings && [encodings count]) {

				[self->encodingPopupCell addItemWithTitle:@"dummy"];
				//copy the default attributes and add gray color - with safety check
				NSMutableDictionary *defaultAttrs = nil;
				NSAttributedString *attributedTitle = [self->encodingPopupCell attributedTitle];
				if (attributedTitle && [attributedTitle length] > 0) {
					defaultAttrs = [NSMutableDictionary dictionaryWithDictionary:[attributedTitle attributesAtIndex:0 effectiveRange:NULL]];
				} else {
					defaultAttrs = [NSMutableDictionary dictionary];
				}
				[defaultAttrs setObject:[NSColor lightGrayColor] forKey:NSForegroundColorAttributeName];
				[[self->encodingPopupCell lastItem] setTitle:@""];

				for (NSDictionary *encoding in encodings)
				{
					if (!encoding || ![encoding isKindOfClass:[NSDictionary class]]) continue;
					
					NSString *encodingName = [encoding safeObjectForKey:@"CHARACTER_SET_NAME"];
					if (!encodingName || [encodingName isNSNull]) {
						encodingName = @"";
					}
					
					NSString *title = encodingName;
					id descObj = [encoding safeObjectForKey:@"DESCRIPTION"];
					if (descObj && ![descObj isNSNull]) {
						title = [NSString stringWithFormat:@"%@ (%@)", descObj, encodingName];
					}

					if(title == nil || [title isNSNull]) {
						title = @"";
					}

					[self->encodingPopupCell safeAddItemWithTitle:title];
					NSMenuItem *item = [self->encodingPopupCell lastItem];

					if (item) {
						[item setRepresentedObject:encodingName];

						NSString *tableEncoding = [self->tableDataInstance tableEncoding];
						if (encodingName && tableEncoding && [encodingName isEqualToString:tableEncoding]) {
							NSString *itemTitle = [item title];
							if (itemTitle && [itemTitle length] > 0) {
								NSAttributedString *itemString = [[NSAttributedString alloc] initWithString:itemTitle attributes:defaultAttrs];
								[item setAttributedTitle:itemString];
							}
						}
					}
				}
			}
			else {
				[self->encodingPopupCell addItemWithTitle:NSLocalizedString(@"Not available", @"not available label")];
			}
		}
		@catch (NSException *exception) {
			NSLog(@"SPTableStructure loadTable encoding block exception: %@ - %@", [exception name], [exception reason]);
			// Fallback - just add a default item
			[self->encodingPopupCell removeAllItems];
			[self->encodingPopupCell addItemWithTitle:NSLocalizedString(@"Not available", @"not available label")];
		}
	});

	// Process all the fields to normalise keys and add additional information
	for (id theField in theTableFields)
	{
		NSString *type = [[[theField objectForKey:@"type"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];

		if([type isEqualToString:@"JSON"]) {
			// MySQL 5.7 manual:
			// "MySQL handles strings used in JSON context using the utf8mb4 character set and utf8mb4_bin collation.
			//  Strings in other character set are converted to utf8mb4 as necessary."
			[theField safeSetObject:@"utf8mb4" forKey:@"encodingName"];
			[theField safeSetObject:@"utf8mb4_bin" forKey:@"collationName"];
			[theField safeSetObject:@1 forKey:@"binary"];
		}
		else if ([fieldValidation isFieldTypeString:type]) {
			// The MySQL 4.1 manual says:
			//
			// MySQL chooses the column character set and collation in the following manner:
			//   1. If both CHARACTER SET X and COLLATE Y were specified, then character set X and collation Y are used.
			//   2. If CHARACTER SET X was specified without COLLATE, then character set X and its default collation are used.
			//   3. If COLLATE Y was specified without CHARACTER SET, then the character set associated with Y and collation Y.
			//   4. Otherwise, the table character set and collation are used.
			NSString *encoding  = [theField objectForKey:@"encoding"];
			NSString *collation = [theField objectForKey:@"collation"];
			if(encoding) {
				if(collation) {
					// 1
				}
				else {
					collation = [databaseDataInstance getDefaultCollationForEncoding:encoding]; // 2
				}
			}
			else {
				if(collation) {
					encoding = [databaseDataInstance getEncodingFromCollation:collation]; // 3
				}
				else {
					encoding = [tableDataInstance tableEncoding]; //4
					collation = [tableDataInstance statusValueForKey:@"Collation"];
					if(!collation) {
						// should not happen, as the TABLE STATUS output always(?) includes the collation
						collation = [databaseDataInstance getDefaultCollationForEncoding:encoding];
					}
				}
			}

			// MySQL < 4.1 does not support collations (they are part of the charset), it will be nil there
            if(collation != nil){
                [theField safeSetObject:collation forKey:@"collationName"];
            }
            else{
                SPLog(@"collation was nil");
            }
            if(encoding != nil){
                [theField safeSetObject:encoding forKey:@"encodingName"];
            }
            else{
                SPLog(@"encoding was nil");
            }

			// Set BINARY if collation ends with _bin for convenience
			if (![collation isNSNull] && [collation hasSuffix:@"_bin"]) {
				[theField setObject:@1 forKey:@"binary"];
			}
		}

		// Get possible values if the field is an enum or a set
		if (([type isEqualToString:@"ENUM"] || [type isEqualToString:@"SET"]) && [theField objectForKey:@"values"]) {
			[theTableEnumLists setObject:[NSArray arrayWithArray:[theField objectForKey:@"values"]] forKey:[theField objectForKey:@"name"]];
			[theField setObject:[NSString stringWithFormat:@"'%@'", [[theField objectForKey:@"values"] componentsJoinedByString:@"','"]] forKey:@"length"];
		}

		// Join length and decimals if any
		if ([theField objectForKey:@"decimals"])
			[theField setObject:[NSString stringWithFormat:@"%@,%@", [theField objectForKey:@"length"], [theField objectForKey:@"decimals"]] forKey:@"length"];

		// Normalize default
		if (![theField objectForKey:@"default"]) {
			[theField setObject:@"" forKey:@"default"];
		}
		else if ([[theField objectForKey:@"default"] isNSNull]) {
			[theField setObject:[prefs stringForKey:SPNullValue] forKey:@"default"];
		}
        else if ([type hasSuffix:@"CHAR"] || [type hasSuffix:@"TEXT"] || [type hasSuffix:@"ENUM"]) {
            [theField setObject:[postgresConnection escapeAndQuoteString:[theField objectForKey:@"default"]] forKey:@"default"];
        }

		// Init Extra field
		[theField setObject:@"None" forKey:@"Extra"];

		// Check for auto_increment and set Extra accordingly
		if ([[theField objectForKey:@"autoincrement"] integerValue]) {
			[theField setObject:@"auto_increment" forKey:@"Extra"];
		}

        // Check for "generated always virtual | stored" and set Extra accordingly
        if ([theField objectForKey:@"generatedalways"]) {
            if ([[theField objectForKey:@"generatedalways"] isEqual:@"VIRTUAL"]) {
                [theField setObject:@"VIRTUAL GENERATED" forKey:@"Extra"];
            } else if ([[theField objectForKey:@"generatedalways"] isEqual:@"STORED"]) {
                [theField setObject:@"STORED GENERATED" forKey:@"Extra"];
            }
        }

		// For timestamps/datetime check to see whether "on update CURRENT_TIMESTAMP"  and set Extra accordingly
		else if ([type isInArray:@[@"TIMESTAMP",@"DATETIME"]] && [[theField objectForKey:@"onupdatetimestamp"] boolValue]) {
			NSString *ouct = @"on update CURRENT_TIMESTAMP";
			// restore a length parameter if the field has fractional seconds.
			// the parameter of current_timestamp MUST match the field's length in that case, so we can just 'guess' it.
			NSString *fieldLen = [theField objectForKey:@"length"];
			if([fieldLen length] && ![fieldLen isEqualToString:@"0"]) {
				ouct = [ouct stringByAppendingFormat:@"(%@)",fieldLen];
			}
			[theField setObject:ouct forKey:@"Extra"];
		}
	}

	// Set up the table details for the new table, and request an data/interface update
	NSDictionary *tableDetails = [NSDictionary dictionaryWithObjectsAndKeys:
								  aTable, @"name",
								  theTableFields, @"tableFields",
								  tableIndexes, @"tableIndexes",
								  theTableEnumLists, @"enumLists",
								  nil];

	[[self onMainThread] setTableDetails:tableDetails];

	isCurrentExtraAutoIncrement = [tableDataInstance tableHasAutoIncrementField];
	autoIncrementIndex = nil;

	// Send the query finished/work complete notification
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SPostgresQueryHasBeenPerformed" object:tableDocumentInstance];
}

/**
 * Reloads the table (performing a new query).
 */
- (IBAction)reloadTable:(id)sender
{
	// Check whether a save of the current row is required
	if (![[self onMainThread] saveRowOnDeselect]) return;

	[tableDataInstance resetAllData];
	[tableDocumentInstance setStatusRequiresReload:YES];

	// Query the structure of all databases in the background (mainly for completion)
	[[tableDocumentInstance databaseStructureRetrieval] queryDbStructureInBackgroundWithUserInfo:@{@"forceUpdate" : @YES}];

	[self loadTable:selectedTable];
}

/**
 * Updates the stored table details and updates the interface to match.
 *
 * Should be called on the main thread.
 */
- (void)setTableDetails:(NSDictionary *)tableDetails
{
	NSString *newTableName = [tableDetails safeObjectForKey:@"name"];
	NSMutableDictionary *newDefaultValues;

	BOOL enableInteraction =
	![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableStructure] ||
	![tableDocumentInstance isWorking];

	// Update the selected table name
	
	if (newTableName) selectedTable = [[NSString alloc] initWithString:newTableName];

	[indexesController setTable:selectedTable];

	// Reset the table store and display
	[tableSourceView deselectAll:self];
	[tableFields removeAllObjects];
	filteredTableFields = nil;
	[enumFields removeAllObjects];
	[indexesTableView deselectAll:self];
	[addFieldButton setEnabled:NO];
	[duplicateFieldButton setEnabled:NO];
	[removeFieldButton setEnabled:NO];
	[addIndexButton setEnabled:NO];
	[removeIndexButton setEnabled:NO];
	[editTableButton setEnabled:NO];

	// If no table is selected, refresh the table/index display to blank and return
	if (!selectedTable) {
		[tableSourceView reloadData];
		// Empty indexesController's fields and indices explicitly before reloading
		[indexesController setFields:@[]];
		[indexesController setIndexes:@[]];
		[indexesTableView reloadData];

		return;
	}

	// Update the fields and indexes stores
	[tableFields safeSetArray:[tableDetails safeObjectForKey:@"tableFields"]];

	[indexesController setFields:tableFields];
	[indexesController setIndexes:[tableDetails safeObjectForKey:@"tableIndexes"]];

	

	newDefaultValues = [NSMutableDictionary dictionaryWithCapacity:[tableFields count]];

	for (id theField in tableFields)
	{
		[newDefaultValues safeSetObject:[theField safeObjectForKey:@"default"] forKey:[theField safeObjectForKey:@"name"]];
	}

	defaultValues = [NSDictionary dictionaryWithDictionary:newDefaultValues];

	// Enable the edit table button
	[editTableButton setEnabled:enableInteraction];

	// If a view is selected, disable the buttons; otherwise enable.
	BOOL editingEnabled = ([tablesListInstance tableType] == SPTableTypeTable) && enableInteraction;

	[addFieldButton setEnabled:editingEnabled];
	[addIndexButton setEnabled:editingEnabled && ![[[tableDataInstance statusValueForKey:@"Engine"] uppercaseString] isEqualToString:@"CSV"]];

	// sort then filter fields before reloading table view
	[tableFields sortUsingDescriptors: [tableSourceView sortDescriptors]];
	[self sort: tableFields withDescriptor: [fieldsSortHelper currentSortDescriptor]];
	[self filterFieldsWithString:filterSearchField.stringValue];

	// Reload the views
	[indexesTableView reloadData];
	[tableSourceView reloadData];
}

#pragma mark - SPTableStructureDelegate

#pragma mark Table view datasource methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [[self activeFieldsSource] count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	// Return a placeholder if the table is reloading
	if ((NSUInteger)rowIndex >= [[self activeFieldsSource] count]) return @"...";

	NSDictionary *rowData = [[self activeFieldsSource] safeObjectAtIndex:rowIndex];

	if ([[tableColumn identifier] isEqualToString:@"collation"]) {
		NSString *tableEncoding = [tableDataInstance tableEncoding];
		NSString *columnEncoding = [rowData safeObjectForKey:@"encodingName"];
		NSString *columnCollation = [rowData safeObjectForKey:@"collationName"]; // loadTable: has already inferred it, if not set explicit

#warning Building the collation menu here is a big performance hog. This should be done in menuNeedsUpdate: below!
		NSPopUpButtonCell *collationCell = [tableColumn dataCell];
		[collationCell removeAllItems];
		[collationCell addItemWithTitle:@"dummy"];
		//copy the default style of menu items and add gray color for default item
		NSMutableDictionary *menuAttrs = [NSMutableDictionary dictionaryWithDictionary:[[collationCell attributedTitle] attributesAtIndex:0 effectiveRange:NULL]];
		[menuAttrs setObject:[NSColor lightGrayColor] forKey:NSForegroundColorAttributeName];
		[[collationCell lastItem] setTitle:@""];

		//if this is not set the column either has no encoding (numeric etc.) or retrieval failed. Either way we can't provide collations
		if([columnEncoding length]) {
			collations = [databaseDataInstance getDatabaseCollationsForEncoding:columnEncoding];

			if ([collations count] > 0) {
				NSString *tableCollation = [[tableDataInstance statusValues] safeObjectForKey:@"Collation"];

				if (![tableCollation isNSNull] && ![tableCollation length]) {
					tableCollation = [databaseDataInstance getDefaultCollationForEncoding:tableEncoding];
				}

				BOOL columnUsesTableDefaultEncoding = ([columnEncoding isEqualToString:tableEncoding]);
				// Populate collation popup button
				for (NSDictionary *collation in collations)
				{
					NSString *collationName = [collation safeObjectForKey:@"COLLATION_NAME"];

					[collationCell safeAddItemWithTitle:collationName];
					NSMenuItem *item = [collationCell lastItem];
					[item setRepresentedObject:collationName];

					// If this matches the table's collation, draw in gray
					if (columnUsesTableDefaultEncoding && [collationName isEqualToString:tableCollation]) {
						NSAttributedString *itemString = [[NSAttributedString alloc] initWithString:[item title] attributes:menuAttrs];
						[item setAttributedTitle:itemString];
					}
				}

				// the popup cell is subclassed to take the representedObject instead of the item index
				return columnCollation;
			}
		}

		return nil;
	}
	else if ([[tableColumn identifier] isEqualToString:@"encoding"]) {
		// the encoding menu was already configured during setTableDetails:
		NSString *columnEncoding = [rowData objectForKey:@"encodingName"];

		if([columnEncoding length]) {
			NSInteger idx = [encodingPopupCell indexOfItemWithRepresentedObject:columnEncoding];
			if(idx > 0) return @(idx);
		}

		return @0;
	}
	else if ([[tableColumn identifier] isEqualToString:@"Extra"]) {
		id dataCell = [tableColumn dataCell];

		[dataCell removeAllItems];

		// Populate Extra suggestion popup button
		for (id item in extraFieldSuggestions)
		{
			if (!(isCurrentExtraAutoIncrement && [item isEqualToString:@"auto_increment"])) {
				[dataCell addItemWithObjectValue:item];
			}
		}
	}

	return [rowData objectForKey:[tableColumn identifier]];
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	// Make sure that the operation is for the right table view
	if (aTableView != tableSourceView) return;

    NSMutableDictionary *currentRow = [[self activeFieldsSource] safeObjectAtIndex:rowIndex];

	if (!isEditingRow) {
		[oldRow setDictionary:currentRow];
		isEditingRow = YES;
		currentlyEditingRow = rowIndex;
	}

	// Reset collation if encoding was changed
	if ([[aTableColumn identifier] isEqualToString:@"encoding"]) {
		NSString *oldEncoding = [currentRow objectForKey:@"encodingName"];
		NSString *newEncoding = [[encodingPopupCell itemAtIndex:[anObject integerValue]] representedObject];
		if (![oldEncoding isEqualToString:newEncoding]) {
			[currentRow removeObjectForKey:@"collationName"];
			[tableSourceView reloadData];
		}
		if(!newEncoding)
			[currentRow removeObjectForKey:@"encodingName"];
		else
			[currentRow setObject:newEncoding forKey:@"encodingName"];
		return;
	}
	else if ([[aTableColumn identifier] isEqualToString:@"collation"]) {
		//the popup button is subclassed to return the representedObject instead of the item index
		NSString *newCollation = anObject;

		if(!newCollation)
			[currentRow removeObjectForKey:@"collationName"];
		else
			[currentRow setObject:newCollation forKey:@"collationName"];
		return;
	}
	// Reset collation if BINARY was changed, as enabling BINARY sets collation to *_bin
	else if ([[aTableColumn identifier] isEqualToString:@"binary"]) {
		if ([[currentRow objectForKey:@"binary"] integerValue] != [anObject integerValue]) {
			[currentRow removeObjectForKey:@"collationName"];

			[tableSourceView reloadData];
		}
	}
	// Set null field to "do not allow NULL" for auto_increment Extra and reset Extra suggestion list
	else if ([[aTableColumn identifier] isEqualToString:@"Extra"]) {
		if (![[currentRow objectForKey:@"Extra"] isEqualToString:anObject]) {

			isCurrentExtraAutoIncrement = [[[anObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString] isEqualToString:@"AUTO_INCREMENT"];

			if (isCurrentExtraAutoIncrement) {
				[currentRow setObject:@0 forKey:@"null"];

				// Asks the user to add an index to query if AUTO_INCREMENT is set and field isn't indexed
				if ((![currentRow objectForKey:@"Key"] || [[currentRow objectForKey:@"Key"] isEqualToString:@""])) {
					[chooseKeyButton selectItemWithTag:SPPrimaryKeyMenuTag];
					[[tableDocumentInstance parentWindowControllerWindow] beginSheet:keySheet completionHandler:^(NSModalResponse returnCode) {
						if (returnCode) {
							switch ([[self->chooseKeyButton selectedItem] tag]) {
								case SPPrimaryKeyMenuTag:
									self->autoIncrementIndex = @"PRIMARY KEY";
									break;
								case SPIndexMenuTag:
									self->autoIncrementIndex = @"INDEX";
									break;
								case SPUniqueMenuTag:
									self->autoIncrementIndex = @"UNIQUE";
									break;
							}
						} else {
							self->autoIncrementIndex = nil;
							if([self->tableSourceView selectedRow] > -1 && [self->extraFieldSuggestions count])
								[[[self activeFieldsSource] objectAtIndex:[self->tableSourceView selectedRow]] setObject:[self->extraFieldSuggestions objectAtIndex:0] forKey:@"Extra"];
							[self->tableSourceView reloadData];
							self->isCurrentExtraAutoIncrement = NO;
						}
					}];
				}
			} else {
				autoIncrementIndex = nil;
			}

			id dataCell = [aTableColumn dataCell];

			[dataCell removeAllItems];
			[dataCell addItemsWithObjectValues:extraFieldSuggestions];
			[dataCell noteNumberOfItemsChanged];
			[dataCell reloadData];

			[tableSourceView reloadData];

		}
	}
	// Reset default to "" if field doesn't allow NULL and current default is set to NULL
	else if ([[aTableColumn identifier] isEqualToString:@"null"]) {
		if ([[currentRow objectForKey:@"null"] integerValue] != [anObject integerValue]) {
			if ([anObject integerValue] == 0) {
				if ([[currentRow objectForKey:@"default"] isEqualToString:[prefs objectForKey:SPNullValue]]) {
					[currentRow setObject:@"" forKey:@"default"];
				}
			}

			[tableSourceView reloadData];
		}
	}
	// Store new value but not if user choose "---" for type and reset values if required
	else if ([[aTableColumn identifier] isEqualToString:@"type"]) {
		if (anObject && [(NSString*)anObject length] && ![(NSString*)anObject hasPrefix:@"--"]) {
			[currentRow setObject:[(NSString*)anObject uppercaseString] forKey:@"type"];

			// If type is BLOB or TEXT reset DEFAULT since these field types don't allow a default
			if ([[currentRow objectForKey:@"type"] hasSuffix:@"TEXT"] ||
				[[currentRow objectForKey:@"type"] hasSuffix:@"BLOB"] ||
				[[currentRow objectForKey:@"type"] isEqualToString:@"JSON"] ||
				[fieldValidation isFieldTypeGeometry:[currentRow objectForKey:@"type"]] ||
				([fieldValidation isFieldTypeDate:[currentRow objectForKey:@"type"]] && ![[currentRow objectForKey:@"type"] isEqualToString:@"YEAR"]))
			{
				[currentRow setObject:@"" forKey:@"default"];
				[currentRow setObject:@"" forKey:@"length"];
			}

			[tableSourceView reloadData];
		}
		return;
	}

	[currentRow setObject:(anObject) ? anObject : @"" forKey:[aTableColumn identifier]];
}

/**
 * Confirm whether to allow editing of a row. Returns YES by default, but NO for views.
 */
- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if ([tableDocumentInstance isWorking]) return NO;

	// Return NO for views
	if ([tablesListInstance tableType] == SPTableTypeView) return NO;

	return YES;
}

/**
 * Begin a drag and drop operation from the table - copy a single dragged row to the drag pasteboard.
 */
- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard*)pboard
{
	// Make sure that the drag operation is started from the right table view
	if (aTableView != tableSourceView) return NO;

	// Check whether a save of the current field row is required.
	if (![self saveRowOnDeselect]) return NO;

	if ([rows count] == 1) {
		[pboard declareTypes:@[SPDefaultPasteboardDragType] owner:nil];
		[pboard setString:[NSString stringWithFormat:@"%lu",[rows firstIndex]] forType:SPDefaultPasteboardDragType];

		return YES;
	}

	return NO;
}

/**
 * Determine whether to allow a drag and drop operation on this table - for the purposes of drag reordering,
 * validate that the original source is of the correct type and within the same table, and that the drag
 * would result in a position change.
 */
- (NSDragOperation)tableView:(NSTableView*)tableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	// Make sure that the drag operation is for the right table view
	if (tableView!=tableSourceView) return NSDragOperationNone;

	NSArray *pboardTypes = [[info draggingPasteboard] types];
	NSInteger originalRow;

	// Ensure the drop is of the correct type
	if (operation == NSTableViewDropAbove && row != -1 && [pboardTypes containsObject:SPDefaultPasteboardDragType]) {

		// Ensure the drag originated within this table
		if ([info draggingSource] == tableView) {
			originalRow = [[[info draggingPasteboard] stringForType:SPDefaultPasteboardDragType] integerValue];

			if (row != originalRow && row != (originalRow+1)) {
				return NSDragOperationMove;
			}
		}
	}

	return NSDragOperationNone;
}

/**
 * Having validated a drop, perform the field/column reordering to match.
 * NOTE: PostgreSQL does not support column reordering directly.
 * This operation would require recreating the table which is not safe.
 */
- (BOOL)tableView:(NSTableView*)tableView acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)destinationRowIndex dropOperation:(NSTableViewDropOperation)operation
{
	// Make sure that the drag operation is for the right table view
	if (tableView != tableSourceView) return NO;

	// PostgreSQL does not support column reordering (FIRST/AFTER clauses)
	// Show an informative message to the user
	[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Column Reordering Not Supported", @"column reordering not supported title")
								 message:NSLocalizedString(@"PostgreSQL does not support changing column order directly. To reorder columns, you would need to recreate the table with the desired column order.\n\nThe column order in the display can be changed, but this will not affect the actual table structure.", @"column reordering not supported message")
								callback:nil];

	// Return NO to indicate the drop was not accepted
	// But we can still reorder the visual display locally if needed
	return NO;

	// Original MySQL code for reference - PostgreSQL cannot use MODIFY COLUMN with FIRST/AFTER
	/*
	NSInteger originalRowIndex = [[[info draggingPasteboard] stringForType:SPDefaultPasteboardDragType] integerValue];
	NSDictionary *originalRow = [[NSDictionary alloc] initWithDictionary:[[self activeFieldsSource] objectAtIndex:originalRowIndex]];

	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryWillBePerformed" object:tableDocumentInstance];

	NSMutableString *queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ MODIFY COLUMN %@",
									[selectedTable postgresQuotedIdentifier],
									[self _buildPartialColumnDefinitionString:originalRow]];
	*/

	/*
	// This code is unreachable but kept for reference
	if ([postgresConnection queryErrored]) {
		[NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error moving field", @"error moving field message") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to move the field.\n\nPostgreSQL said: %@", @"error moving field informative message"), [postgresConnection lastErrorMessage]] callback:nil];
	}
	else {
		[tableDataInstance resetAllData];
		[tableDocumentInstance setStatusRequiresReload:YES];

		[self loadTable:selectedTable];

		// Mark the content table cache for refresh
		[tableDocumentInstance setContentRequiresReload:YES];

		[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:destinationRowIndex - ((originalRowIndex < destinationRowIndex) ? 1 : 0)] byExtendingSelection:NO];
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:@"SPostgresQueryHasBeenPerformed" object:tableDocumentInstance];

	return YES;
	*/
}

#pragma mark -
#pragma mark Table view delegate methods

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{
	// If we are editing a row, attempt to save that row - if saving failed, do not select the new row.
	if (isEditingRow && ![self addRowToDB]) return NO;

	return YES;
}

/**
 * Performs various interface validation
 */
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	// Check for which table view the selection changed
	if ([aNotification object] == tableSourceView) {

		// If we are editing a row, attempt to save that row - if saving failed, reselect the edit row.
		if (isEditingRow && [tableSourceView selectedRow] != currentlyEditingRow && ![self saveRowOnDeselect]) return;

		[duplicateFieldButton setEnabled:YES];

		// Check if there is currently a field selected and change button state accordingly
		if ([tableSourceView numberOfSelectedRows] > 0 && [tablesListInstance tableType] == SPTableTypeTable) {
			[removeFieldButton setEnabled:YES];
		}
		else {
			[removeFieldButton setEnabled:NO];
			[duplicateFieldButton setEnabled:NO];
		}

		// If the table only has one field, disable the remove button. This removes the need to check that the user
		// is attempting to remove the last field in a table in removeField: above, but leave it in just in case.
		if ([tableSourceView numberOfRows] == 1) {
			[removeFieldButton setEnabled:NO];
		}
	}
}

/**
 * Traps enter and esc and make/cancel editing without entering next row
 */
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	NSInteger row, column;

	row = [tableSourceView editedRow];
	column = [tableSourceView editedColumn];

	// Trap the tab key, selecting the next item in the line
	if ([textView methodForSelector:command] == [textView methodForSelector:@selector(insertTab:)] && [tableSourceView numberOfColumns] - 1 == column)
	{
		//save current line
		[[control window] makeFirstResponder:control];

		if ([self addRowToDB] && [textView methodForSelector:command] == [textView methodForSelector:@selector(insertTab:)]) {
			if (row < ([tableSourceView numberOfRows] - 1)) {
				[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:row + 1] byExtendingSelection:NO];
				[tableSourceView editColumn:0 row:row + 1 withEvent:nil select:YES];
			}
			else {
				[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
				[tableSourceView editColumn:0 row:0 withEvent:nil select:YES];
			}
		}

		return YES;
	}
	// Trap shift-tab key
	else if ([textView methodForSelector:command] == [textView methodForSelector:@selector(insertBacktab:)] && column < 1)
	{
		if ([self addRowToDB] && [textView methodForSelector:command] == [textView methodForSelector:@selector(insertBacktab:)]) {
			[[control window] makeFirstResponder:control];

			if (row > 0) {
				[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:row - 1] byExtendingSelection:NO];
				[tableSourceView editColumn:([tableSourceView numberOfColumns] - 1) row:row - 1 withEvent:nil select:YES];
			}
			else {
				[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:([[self activeFieldsSource] count] - 1)] byExtendingSelection:NO];
				[tableSourceView editColumn:([tableSourceView numberOfColumns] - 1) row:([tableSourceView numberOfRows] - 1) withEvent:nil select:YES];
			}
		}

		return YES;
	}
	// Trap the enter key, triggering a save
	else if ([textView methodForSelector:command] == [textView methodForSelector:@selector(insertNewline:)])
	{
		// Suppress enter for non-text fields to allow selecting of chosen items from comboboxes or popups
		if (![[[[[[tableSourceView tableColumns] objectAtIndex:column] dataCell] class] description] isEqualToString:@"NSTextFieldCell"]) {
			return YES;
		}

		[[control window] makeFirstResponder:control];

		[self addRowToDB];

		[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];

		[[tableDocumentInstance parentWindowControllerWindow] makeFirstResponder:tableSourceView];

		return YES;
	}
	// Trap escape, aborting the edit and reverting the row
	else if ([[control window] methodForSelector:command] == [[control window] methodForSelector:@selector(cancelOperation:)])
	{
		[control abortEditing];

		[self cancelRowEditing];

		return YES;
	}

	return NO;
}

/**
 * Modify cell display by disabling table cells when a view is selected, meaning structure/index
 * is uneditable and do cell validation due to row's field type.
 */
- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	// Make sure that the message is from the right table view
	if (tableView != tableSourceView) return;

	if ([tablesListInstance tableType] == SPTableTypeView) {
		[aCell setEnabled:NO];
	}
	else {
		// Validate cell against current field type
		NSString *rowType;
		NSDictionary *row = [[self activeFieldsSource] safeObjectAtIndex:rowIndex];

		if ((rowType = [row objectForKey:@"type"])) {
			rowType = [[rowType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
		}

		// Only string fields allow encoding settings, but JSON only uses utf8mb4
		if (([[tableColumn identifier] isEqualToString:@"encoding"])) {
			[aCell setEnabled:(![rowType isEqualToString:@"JSON"] && [fieldValidation isFieldTypeString:rowType])];
		}

		// Only string fields allow collation settings and string field is not set to BINARY since BINARY sets the collation to *_bin
		else if ([[tableColumn identifier] isEqualToString:@"collation"]) {
			// JSON always uses utf8mb4_bin which is already covered by this logic
			[aCell setEnabled:([fieldValidation isFieldTypeString:rowType] && [[row objectForKey:@"binary"] integerValue] == 0)];
		}

		// Check if UNSIGNED and ZEROFILL is allowed
		else if ([[tableColumn identifier] isEqualToString:@"zerofill"] || [[tableColumn identifier] isEqualToString:@"unsigned"]) {
			[aCell setEnabled:([fieldValidation isFieldTypeNumeric:rowType] && ![rowType isEqualToString:@"BIT"])];
		}

		// Check if BINARY is allowed
		else if ([[tableColumn identifier] isEqualToString:@"binary"]) {
			// JSON always uses utf8mb4_bin
			[aCell setEnabled:(![rowType isEqualToString:@"JSON"] && [fieldValidation isFieldTypeAllowBinary:rowType])];
		}

		// TEXT, BLOB, GEOMETRY and JSON fields don't allow a DEFAULT
		else if ([[tableColumn identifier] isEqualToString:@"default"]) {
			[aCell setEnabled:([rowType hasSuffix:@"TEXT"] || [rowType hasSuffix:@"BLOB"] || [rowType isEqualToString:@"JSON"] || [fieldValidation isFieldTypeGeometry:rowType]) ? NO : YES];
		}

		// Check allow NULL
		else if ([[tableColumn identifier] isEqualToString:@"null"]) {
			id keyValue = [row objectForKey:@"Key"];
			id extraValue = [row objectForKey:@"Extra"];
			id engineValue = [tableDataInstance statusValueForKey:@"Engine"];

			BOOL isPrimaryKey = [keyValue isKindOfClass:[NSString class]] && [keyValue isEqualToString:@"PRI"];
			BOOL isAutoIncrement = [extraValue isKindOfClass:[NSString class]] && [[extraValue uppercaseString] isEqualToString:@"AUTO_INCREMENT"];
			BOOL isCsvEngine = [engineValue isKindOfClass:[NSString class]] && [[engineValue uppercaseString] isEqualToString:@"CSV"];

			[aCell setEnabled:(isPrimaryKey || isAutoIncrement || isCsvEngine) ? NO : YES];
		}

		// TEXT, BLOB, date, GEOMETRY and JSON fields don't allow a length
		else if ([[tableColumn identifier] isEqualToString:@"length"]) {
			[aCell setEnabled:([rowType hasSuffix:@"TEXT"] ||
							   [rowType hasSuffix:@"BLOB"] ||
							   [rowType isEqualToString:@"JSON"] ||
							   ([fieldValidation isFieldTypeDate:rowType] && ![[tableDocumentInstance serverSupport] supportsFractionalSeconds] && ![rowType isEqualToString:@"YEAR"]) ||
							   [fieldValidation isFieldTypeGeometry:rowType]) ? NO : YES];
		}
		else {
			[aCell setEnabled:YES];
		}
	}
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn {
	if ([self sort:[self activeFieldsSource] withDescriptor:[fieldsSortHelper sortDescriptorForClickOn:tableView column:tableColumn]]) {
		[tableView reloadData];
	}
}

- (BOOL)sort:(NSMutableArray *)arr withDescriptor:(NSSortDescriptor *)descriptor {
	if (descriptor) {
		[arr sortUsingDescriptors:@[descriptor]];
		return YES;
	}
	return NO;
}

#pragma mark -
#pragma mark Split view delegate methods

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
	return YES;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset
{
	return proposedMax - 130;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset
{
	return proposedMin + 130;
}

- (NSRect)splitView:(NSSplitView *)splitView additionalEffectiveRectOfDividerAtIndex:(NSInteger)dividerIndex
{
	return [structureGrabber convertRect:[structureGrabber bounds] toView:splitView];
}

- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification
{
	if ([aNotification object] == tablesIndexesSplitView) {

		NSView *indexesView = [[tablesIndexesSplitView subviews] objectAtIndex:1];

		if ([tablesIndexesSplitView isSubviewCollapsed:indexesView]) {
			[indexesShowButton setHidden:NO];
		}
		else {
			[indexesShowButton setHidden:YES];
		}
	}
}

#pragma mark -
#pragma mark Combo box delegate methods

- (id)comboBoxCell:(NSComboBoxCell *)aComboBoxCell objectValueForItemAtIndex:(NSInteger)index
{
	return [typeSuggestions safeObjectAtIndex:index];
}

- (NSInteger)numberOfItemsInComboBoxCell:(NSComboBoxCell *)aComboBoxCell
{
	return [typeSuggestions count];
}

/**
 * Allow completion of field data types of lowercased input.
 */
- (NSString *)comboBoxCell:(NSComboBoxCell *)aComboBoxCell completedString:(NSString *)uncompletedString
{
	if ([uncompletedString hasPrefix:@"-"]) return @"";

	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF BEGINSWITH[c] %@", [uncompletedString uppercaseString]];
	NSArray *result = [typeSuggestions filteredArrayUsingPredicate:predicate];

	if ([result count]) return [result objectAtIndex:0];

	return @"";
}

- (void)comboBoxCell:(SPComboBoxCell *)cell willPopUpWindow:(NSWindow *)win
{
	// the selected item in the popup list is independent of the displayed text, we have to explicitly set it, too
	NSInteger pos = [typeSuggestions indexOfObject:[cell stringValue]];
	if(pos != NSNotFound) {
		[cell selectItemAtIndex:pos];
		[cell scrollItemAtIndexToTop:pos];
	}

	//set up the help window to the right position
	NSRect listFrame = [win frame];
	NSRect helpFrame = [structureHelpPanel frame];
	helpFrame.origin.y = listFrame.origin.y;
	helpFrame.size.height = listFrame.size.height;
	[structureHelpPanel setFrame:helpFrame display:YES];

	[self _displayFieldTypeHelpIfPossible:cell];
}

- (void)comboBoxCell:(SPComboBoxCell *)cell willDismissWindow:(NSWindow *)win
{
	//hide the window if it is still visible
	[structureHelpPanel orderOut:nil];
}

- (void)comboBoxCellSelectionDidChange:(SPComboBoxCell *)cell
{
	NSInteger selectedIndex = [cell indexOfSelectedItem];
	NSString *selectedValue = [typeSuggestions safeObjectAtIndex:selectedIndex];

	// Skip separator lines - find next valid item
	if ([selectedValue hasPrefix:@"----"]) {
		// Move to next non-separator item
		NSInteger newIndex = selectedIndex + 1;
		while (newIndex < (NSInteger)[typeSuggestions count]) {
			NSString *nextValue = [typeSuggestions safeObjectAtIndex:newIndex];
			if (![nextValue hasPrefix:@"----"]) {
				[cell selectItemAtIndex:newIndex];
				break;
			}
			newIndex++;
		}
		// If we went past the end, move backwards
		if (newIndex >= (NSInteger)[typeSuggestions count]) {
			newIndex = selectedIndex - 1;
			while (newIndex >= 0) {
				NSString *prevValue = [typeSuggestions safeObjectAtIndex:newIndex];
				if (![prevValue hasPrefix:@"----"]) {
					[cell selectItemAtIndex:newIndex];
					break;
				}
				newIndex--;
			}
		}
	}

	[self _displayFieldTypeHelpIfPossible:cell];
}

- (void)_displayFieldTypeHelpIfPossible:(SPComboBoxCell *)cell
{
	NSString *selected = [typeSuggestions safeObjectAtIndex:[cell indexOfSelectedItem]];

	const SPFieldTypeHelp *help = [[self class] helpForFieldType:selected];

	if (help) {
		NSMutableAttributedString *as = [[NSMutableAttributedString alloc] init];

		//title
		{
			NSDictionary *titleAttr = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont systemFontSize]], NSForegroundColorAttributeName: [NSColor controlTextColor]};
			NSAttributedString *title = [[NSAttributedString alloc] initWithString:[help typeDefinition] attributes:titleAttr];
			[as appendAttributedString:title];
			[[as mutableString] appendString:@"\n"];
		}

		//range
		if ([[help typeRange] length]) {
			NSDictionary *rangeAttr = @{NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSForegroundColorAttributeName: [NSColor controlTextColor]};
			NSAttributedString *range = [[NSAttributedString alloc] initWithString:[help typeRange] attributes:rangeAttr];
			[as appendAttributedString:range];
			[[as mutableString] appendString:@"\n"];
		}

		[[as mutableString] appendString:@"\n"];

		//description
		{
			NSDictionary *descAttr = @{NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]], NSForegroundColorAttributeName: [NSColor controlTextColor]};
			NSAttributedString *desc = [[NSAttributedString alloc] initWithString:[help typeDescription] attributes:descAttr];
			[as appendAttributedString:desc];
		}

		[as addAttribute:NSParagraphStyleAttributeName value:[NSParagraphStyle defaultParagraphStyle] range:NSMakeRange(0, [as length])];

		[[structureHelpText textStorage] setAttributedString:as];

		NSRect rect = [as boundingRectWithSize:NSMakeSize([structureHelpText frame].size.width-2, CGFLOAT_MAX) options:NSStringDrawingUsesFontLeading|NSStringDrawingUsesLineFragmentOrigin];

		NSRect winRect = [structureHelpPanel frame];

		CGFloat winAddonSize = (winRect.size.height - [[structureHelpPanel contentView] frame].size.height) + (6*2);

		NSRect popUpFrame = [[cell spPopUpWindow] frame];

		//determine the side on which to add our window based on the space left on screen
		NSPoint topRightCorner = NSMakePoint(popUpFrame.origin.x, NSMaxY(popUpFrame));
		NSRect screenRect = [NSScreen rectOfScreenAtPoint:topRightCorner];

		if (NSMaxX(popUpFrame)+10+winRect.size.width > NSMaxX(screenRect)-10) {
			// exceeds right border, display on the left
			winRect.origin.x = popUpFrame.origin.x - 10 - winRect.size.width;
		}
		else {
			// display on the right
			winRect.origin.x = NSMaxX(popUpFrame)+10;
		}

		winRect.size.height = rect.size.height + winAddonSize;
		winRect.origin.y = NSMaxY(popUpFrame) - winRect.size.height;

		[structureHelpPanel setFrame:winRect display:YES];

		[structureHelpPanel orderFront:nil];
	}
	else {
		[structureHelpPanel orderOut:nil];
	}
}

#pragma mark -
#pragma mark Menu delegate methods (encoding/collation dropdown menu)

- (void)menuNeedsUpdate:(SPIdMenu *)menu
{
	if(![menu isKindOfClass:[SPIdMenu class]]) return;
	//NOTE: NSTableView will usually copy the menu and call this method on the copy. Matching with == won't work!

	//walk through the menu and clear the attributedTitle if set. This will remove the gray color from the default items
	for(NSMenuItem *item in [menu itemArray]) {
		if([item attributedTitle]) {
			[item setAttributedTitle:nil];
		}
	}

	NSDictionary *rowData = [[self activeFieldsSource] safeObjectAtIndex:[tableSourceView selectedRow]];

	if([[menu menuId] isEqualToString:@"encodingPopupMenu"]) {
		NSString *tableEncoding = [tableDataInstance tableEncoding];
		//NSString *databaseEncoding = [databaseDataInstance getDatabaseDefaultCharacterSet];
		//NSString *serverEncoding = [databaseDataInstance getServerDefaultCharacterSet];

		struct _cmpMap defaultCmp[] = {
			{
				NSLocalizedString(@"Table",@"Table Structure : Encoding dropdown : 'item is table default' marker"),
				[NSString stringWithFormat:NSLocalizedString(@"This is the default encoding of table “%@”.", @"Table Structure : Encoding dropdown : table marker tooltip"),selectedTable],
				tableEncoding
			},
			/* //we could, but that might confuse users even more plus there is no inheritance between a columns charset and the db/server default
			 {
			 NSLocalizedString(@"Database",@"Table Structure : Encoding dropdown : 'item is database default' marker"),
			 [NSString stringWithFormat:NSLocalizedString(@"This is the default encoding of database “%@”.", @"Table Structure : Encoding dropdown : database marker tooltip"),[tableDocumentInstance database]],
			 databaseEncoding
			 },
			 {
			 NSLocalizedString(@"Server",@"Table Structure : Encoding dropdown : 'item is server default' marker"),
			 NSLocalizedString(@"This is the default encoding of this server.", @"Table Structure : Encoding dropdown : server marker tooltip"),
			 serverEncoding
			 } */
		};

		_BuildMenuWithPills(menu, defaultCmp, COUNT_OF(defaultCmp));
	}
	else if([[menu menuId] isEqualToString:@"collationPopupMenu"]) {
		NSString *encoding = [rowData objectForKey:@"encodingName"];
		NSString *encodingDefaultCollation = [databaseDataInstance getDefaultCollationForEncoding:encoding];
		NSString *tableCollation = [tableDataInstance statusValueForKey:@"Collation"];
		//NSString *databaseCollation = [databaseDataInstance getDatabaseDefaultCollation];
		//NSString *serverCollation = [databaseDataInstance getServerDefaultCollation];

		struct _cmpMap defaultCmp[] = {
			{
				NSLocalizedString(@"Default",@"Table Structure : Collation dropdown : 'item is the same as the default collation of the row's charset' marker"),
				[NSString stringWithFormat:NSLocalizedString(@"This is the default collation of encoding “%@”.", @"Table Structure : Collation dropdown : default marker tooltip"),encoding],
				encodingDefaultCollation
			},
			{
				NSLocalizedString(@"Table",@"Table Structure : Collation dropdown : 'item is the same as the collation of table' marker"),
				[NSString stringWithFormat:NSLocalizedString(@"This is the default collation of table “%@”.", @"Table Structure : Collation dropdown : table marker tooltip"),selectedTable],
				tableCollation
			},
			/* // see the comment for charset above
			 {
			 NSLocalizedString(@"Database",@"Table Structure : Collation dropdown : 'item is the same as the collation of database' marker"),
			 [NSString stringWithFormat:NSLocalizedString(@"This is the default collation of database “%@”.", @"Table Structure : Collation dropdown : database marker tooltip"),[tableDocumentInstance database]],
			 databaseCollation
			 },
			 {
			 NSLocalizedString(@"Server",@"Table Structure : Collation dropdown : 'item is the same as the collation of server' marker"),
			 NSLocalizedString(@"This is the default collation of this server.", @"Table Structure : Collation dropdown : server marker tooltip"),
			 serverCollation
			 } */
		};

		_BuildMenuWithPills(menu, defaultCmp, COUNT_OF(defaultCmp));
	}
}

#pragma mark -

- (void)dealloc
{
	[prefs removeObserver:self forKeyPath:SPGlobalFontSettings];
	[[NSNotificationCenter defaultCenter] removeObserver:self];

    NSLog(@"Dealloc called %s", __FILE_NAME__);
}

+ (SPFieldTypeHelp *)helpForFieldType:(NSString *)typeName
{
	static dispatch_once_t token;
	static NSArray *list;
	dispatch_once(&token, ^{
		// NSString *FN(NSNumber *): format a number using the user locale (to make large numbers more legible)
#define FN(x) [NSNumberFormatter localizedStringFromNumber:x numberStyle:NSNumberFormatterDecimalStyle]
		list = @[
			// ==================== NUMERIC TYPES ====================
			MakeFieldTypeHelp(
				SPPostgresSmallIntType,
				@"smallint",
				[NSString stringWithFormat:NSLocalizedString(@"Range: %@ to %@", @"range for smallint type"),FN(@(-32768)),FN(@32767)],
				NSLocalizedString(@"Small-range integer. Storage: 2 bytes. Aliases: int2",@"description of smallint")
			),
			MakeFieldTypeHelp(
				SPPostgresIntegerType,
				@"integer",
				[NSString stringWithFormat:NSLocalizedString(@"Range: %@ to %@", @"range for integer type"),FN(@(-2147483648)),FN(@2147483647)],
				NSLocalizedString(@"Typical choice for integer. Storage: 4 bytes. Aliases: int, int4",@"description of integer")
			),
			MakeFieldTypeHelp(
				SPPostgresBigIntType,
				@"bigint",
				[NSString stringWithFormat:NSLocalizedString(@"Range: %@ to %@", @"range for bigint type"),FN([NSDecimalNumber decimalNumberWithString:@"-9223372036854775808"]),FN([NSDecimalNumber decimalNumberWithString:@"9223372036854775807"])],
				NSLocalizedString(@"Large-range integer. Storage: 8 bytes. Aliases: int8",@"description of bigint")
			),
			MakeFieldTypeHelp(
				SPPostgresDecimalType,
				@"decimal[(precision[,scale])]",
				NSLocalizedString(@"Precision: up to 131072 digits before decimal point\nScale: up to 16383 digits after decimal point", @"range for decimal type"),
				NSLocalizedString(@"User-specified precision, exact. Recommended for storing monetary amounts and other quantities where exactness is required. Storage: variable.",@"description of decimal")
			),
			MakeFieldTypeHelp(
				SPPostgresNumericType,
				@"numeric[(precision[,scale])]",
				NSLocalizedString(@"Precision: up to 131072 digits before decimal point\nScale: up to 16383 digits after decimal point", @"range for numeric type"),
				NSLocalizedString(@"Alias for decimal. User-specified precision, exact. Recommended for storing monetary amounts and other quantities where exactness is required.",@"description of numeric")
			),
			MakeFieldTypeHelp(
				SPPostgresRealType,
				@"real",
				NSLocalizedString(@"6 decimal digits precision\nRange: approximately 1E-37 to 1E+37", @"range for real type"),
				NSLocalizedString(@"Single precision floating-point number. Storage: 4 bytes. Alias: float4. Inexact, variable-precision numeric type.",@"description of real")
			),
			MakeFieldTypeHelp(
				SPPostgresDoublePrecisionType,
				@"double precision",
				NSLocalizedString(@"15 decimal digits precision\nRange: approximately 1E-307 to 1E+308", @"range for double precision type"),
				NSLocalizedString(@"Double precision floating-point number. Storage: 8 bytes. Alias: float8. Inexact, variable-precision numeric type.",@"description of double precision")
			),
			MakeFieldTypeHelp(
				SPPostgresSmallSerialType,
				@"smallserial",
				[NSString stringWithFormat:NSLocalizedString(@"Range: 1 to %@", @"range for smallserial type"),FN(@32767)],
				NSLocalizedString(@"Autoincrementing two-byte integer. Creates a sequence automatically. Equivalent to: smallint NOT NULL DEFAULT nextval('sequence'). Storage: 2 bytes.",@"description of smallserial")
			),
			MakeFieldTypeHelp(
				SPPostgresSerialType,
				@"serial",
				[NSString stringWithFormat:NSLocalizedString(@"Range: 1 to %@", @"range for serial type"),FN(@2147483647)],
				NSLocalizedString(@"Autoincrementing four-byte integer. Creates a sequence automatically. Equivalent to: integer NOT NULL DEFAULT nextval('sequence'). Storage: 4 bytes.",@"description of serial")
			),
			MakeFieldTypeHelp(
				SPPostgresBigSerialType,
				@"bigserial",
				[NSString stringWithFormat:NSLocalizedString(@"Range: 1 to %@", @"range for bigserial type"),FN([NSDecimalNumber decimalNumberWithString:@"9223372036854775807"])],
				NSLocalizedString(@"Autoincrementing eight-byte integer. Creates a sequence automatically. Equivalent to: bigint NOT NULL DEFAULT nextval('sequence'). Storage: 8 bytes.",@"description of bigserial")
			),
			MakeFieldTypeHelp(
				SPPostgresMoneyType,
				@"money",
				NSLocalizedString(@"Range: -92233720368547758.08 to +92233720368547758.07", @"range for money type"),
				NSLocalizedString(@"Currency amount with fixed fractional precision. Storage: 8 bytes. Output format is locale-sensitive (lc_monetary setting).",@"description of money")
			),
			// ==================== CHARACTER TYPES ====================
			MakeFieldTypeHelp(
				SPPostgresCharType,
				@"character(n)",
				NSLocalizedString(@"n: 1 to 10485760 characters", @"range for character type"),
				NSLocalizedString(@"Fixed-length, blank-padded character string. If the string to be stored is shorter than n, it will be blank-padded. Alias: char(n).",@"description of character")
			),
			MakeFieldTypeHelp(
				SPPostgresVarCharType,
				@"character varying(n)",
				NSLocalizedString(@"n: 1 to 10485760 characters (unlimited if n omitted)", @"range for character varying type"),
				NSLocalizedString(@"Variable-length character string with limit. Stores up to n characters without blank-padding. Alias: varchar(n).",@"description of character varying")
			),
			MakeFieldTypeHelp(
				SPPostgresTextType,
				@"text",
				NSLocalizedString(@"Variable unlimited length", @"range for text type"),
				NSLocalizedString(@"Variable-length character string with unlimited length. There is no performance difference between text and varchar in PostgreSQL.",@"description of text")
			),
			// ==================== BINARY TYPES ====================
			MakeFieldTypeHelp(
				SPPostgresByteaType,
				@"bytea",
				NSLocalizedString(@"Up to 1 GB", @"range for bytea type"),
				NSLocalizedString(@"Variable-length binary string (byte array). Stores raw binary data. Use hex or escape format for input/output.",@"description of bytea")
			),
			// ==================== DATE/TIME TYPES ====================
			MakeFieldTypeHelp(
				SPPostgresDateType,
				@"date",
				NSLocalizedString(@"Range: 4713 BC to 5874897 AD\nResolution: 1 day", @"range for date type"),
				NSLocalizedString(@"Calendar date (year, month, day). Storage: 4 bytes.",@"description of date")
			),
			MakeFieldTypeHelp(
				SPPostgresTimeType,
				@"time[(p)] [without time zone]",
				NSLocalizedString(@"Range: 00:00:00 to 24:00:00\nResolution: 1 microsecond", @"range for time type"),
				NSLocalizedString(@"Time of day without time zone. Storage: 8 bytes. p is optional precision (0-6, default 6) for fractional seconds.",@"description of time")
			),
			MakeFieldTypeHelp(
				SPPostgresTimeTZType,
				@"time[(p)] with time zone",
				NSLocalizedString(@"Range: 00:00:00+1559 to 24:00:00-1559\nResolution: 1 microsecond", @"range for time with time zone type"),
				NSLocalizedString(@"Time of day with time zone. Storage: 12 bytes. Includes time zone offset. Alias: timetz.",@"description of time with time zone")
			),
			MakeFieldTypeHelp(
				SPPostgresTimestampType,
				@"timestamp[(p)] [without time zone]",
				NSLocalizedString(@"Range: 4713 BC to 294276 AD\nResolution: 1 microsecond", @"range for timestamp type"),
				NSLocalizedString(@"Date and time without time zone. Storage: 8 bytes. p is optional precision (0-6, default 6) for fractional seconds.",@"description of timestamp")
			),
			MakeFieldTypeHelp(
				SPPostgresTimestampTZType,
				@"timestamp[(p)] with time zone",
				NSLocalizedString(@"Range: 4713 BC to 294276 AD\nResolution: 1 microsecond", @"range for timestamp with time zone type"),
				NSLocalizedString(@"Date and time with time zone. Storage: 8 bytes. Internally stored as UTC, displayed in session timezone. Alias: timestamptz.",@"description of timestamp with time zone")
			),
			MakeFieldTypeHelp(
				SPPostgresIntervalType,
				@"interval [fields][(p)]",
				NSLocalizedString(@"Range: -178000000 years to +178000000 years\nResolution: 1 microsecond", @"range for interval type"),
				NSLocalizedString(@"Time span. Storage: 16 bytes. Can restrict to YEAR, MONTH, DAY, HOUR, MINUTE, SECOND or combinations. p is fractional seconds precision (0-6).",@"description of interval")
			),
			// ==================== BOOLEAN TYPE ====================
			MakeFieldTypeHelp(
				SPPostgresBooleanType,
				@"boolean",
				NSLocalizedString(@"Values: true, false, null", @"range for boolean type"),
				NSLocalizedString(@"Logical Boolean (true/false). Storage: 1 byte. Accepts: TRUE, 't', 'true', 'y', 'yes', 'on', '1' for true; FALSE, 'f', 'false', 'n', 'no', 'off', '0' for false.",@"description of boolean")
			),
			// ==================== UUID TYPE ====================
			MakeFieldTypeHelp(
				SPPostgresUUIDType,
				@"uuid",
				NSLocalizedString(@"Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", @"format for uuid type"),
				NSLocalizedString(@"Universally unique identifier. Storage: 16 bytes. Stores 128-bit UUID values. Use gen_random_uuid() or uuid-ossp extension to generate.",@"description of uuid")
			),
			// ==================== JSON TYPES ====================
			MakeFieldTypeHelp(
				SPPostgresJSONType,
				@"json",
				NSLocalizedString(@"Variable length, stores exact copy of input", @"range for json type"),
				NSLocalizedString(@"Textual JSON data. Validates JSON syntax on input but stores exact copy. Processing requires reparsing on each execution.",@"description of json")
			),
			MakeFieldTypeHelp(
				SPPostgresJSONBType,
				@"jsonb",
				NSLocalizedString(@"Variable length, decomposed binary format", @"range for jsonb type"),
				NSLocalizedString(@"Binary JSON data. Slower to input due to conversion overhead, but significantly faster to process. Supports indexing. Recommended over json for most cases.",@"description of jsonb")
			),
			// ==================== NETWORK TYPES ====================
			MakeFieldTypeHelp(
				SPPostgresCidrType,
				@"cidr",
				NSLocalizedString(@"IPv4: 7 bytes, IPv6: 19 bytes", @"storage for cidr type"),
				NSLocalizedString(@"IPv4 or IPv6 network address. Stores network address with netmask. Rejects values with non-zero bits to the right of the netmask.",@"description of cidr")
			),
			MakeFieldTypeHelp(
				SPPostgresInetType,
				@"inet",
				NSLocalizedString(@"IPv4: 7 bytes, IPv6: 19 bytes", @"storage for inet type"),
				NSLocalizedString(@"IPv4 or IPv6 host address with optional netmask. Can store both host addresses and network addresses. More permissive than cidr.",@"description of inet")
			),
			MakeFieldTypeHelp(
				SPPostgresMacAddrType,
				@"macaddr",
				NSLocalizedString(@"Storage: 6 bytes", @"storage for macaddr type"),
				NSLocalizedString(@"MAC address (Media Access Control address). Accepts various formats: '08:00:2b:01:02:03', '08-00-2b-01-02-03', '08002b010203', etc.",@"description of macaddr")
			),
			MakeFieldTypeHelp(
				SPPostgresMacAddr8Type,
				@"macaddr8",
				NSLocalizedString(@"Storage: 8 bytes", @"storage for macaddr8 type"),
				NSLocalizedString(@"MAC address (EUI-64 format). Stores MAC addresses in 8-byte format. Can accept 6-byte input and convert to 8-byte EUI-64 format.",@"description of macaddr8")
			),
			// ==================== BIT STRING TYPES ====================
			MakeFieldTypeHelp(
				SPPostgresBitType,
				@"bit(n)",
				NSLocalizedString(@"n: number of bits (must match exactly)", @"range for bit type"),
				NSLocalizedString(@"Fixed-length bit string. Data must be exactly n bits. Storage varies with n.",@"description of bit")
			),
			MakeFieldTypeHelp(
				SPPostgresBitVaryingType,
				@"bit varying(n)",
				NSLocalizedString(@"n: maximum number of bits", @"range for bit varying type"),
				NSLocalizedString(@"Variable-length bit string with maximum length n. Alias: varbit(n). If n is omitted, allows any length.",@"description of bit varying")
			),
			// ==================== GEOMETRIC TYPES ====================
			MakeFieldTypeHelp(
				SPPostgresPointType,
				@"point",
				NSLocalizedString(@"Format: (x,y)", @"format for point type"),
				NSLocalizedString(@"Point on a plane. Storage: 16 bytes (two float8). Foundation for other geometric types.",@"description of point")
			),
			MakeFieldTypeHelp(
				SPPostgresLineType,
				@"line",
				NSLocalizedString(@"Format: {A,B,C} where Ax+By+C=0", @"format for line type"),
				NSLocalizedString(@"Infinite line represented by linear equation Ax + By + C = 0. Storage: 32 bytes.",@"description of line")
			),
			MakeFieldTypeHelp(
				SPPostgresLsegType,
				@"lseg",
				NSLocalizedString(@"Format: [(x1,y1),(x2,y2)]", @"format for lseg type"),
				NSLocalizedString(@"Line segment represented by two endpoints. Storage: 32 bytes.",@"description of lseg")
			),
			MakeFieldTypeHelp(
				SPPostgresBoxType,
				@"box",
				NSLocalizedString(@"Format: ((x1,y1),(x2,y2))", @"format for box type"),
				NSLocalizedString(@"Rectangular box represented by opposite corners. Storage: 32 bytes. Corners are reordered to store upper right and lower left.",@"description of box")
			),
			MakeFieldTypeHelp(
				SPPostgresPathType,
				@"path",
				NSLocalizedString(@"Format: [(x1,y1),...] or ((x1,y1),...)", @"format for path type"),
				NSLocalizedString(@"Geometric path. Can be open (square brackets) or closed (parentheses). Storage: 16+16n bytes.",@"description of path")
			),
			MakeFieldTypeHelp(
				SPPostgresPolygonType,
				@"polygon",
				NSLocalizedString(@"Format: ((x1,y1),...)", @"format for polygon type"),
				NSLocalizedString(@"Closed geometric path (polygon). Similar to closed path. Storage: 40+16n bytes.",@"description of polygon")
			),
			MakeFieldTypeHelp(
				SPPostgresCircleType,
				@"circle",
				NSLocalizedString(@"Format: <(x,y),r>", @"format for circle type"),
				NSLocalizedString(@"Circle represented by center point and radius. Storage: 24 bytes.",@"description of circle")
			),
			// ==================== RANGE TYPES ====================
			MakeFieldTypeHelp(
				SPPostgresInt4RangeType,
				@"int4range",
				NSLocalizedString(@"Range of integer values", @"description for int4range type"),
				NSLocalizedString(@"Range of integer. Example: '[1,10)' includes 1-9. Supports empty, infinite, and inclusive/exclusive bounds.",@"description of int4range")
			),
			MakeFieldTypeHelp(
				SPPostgresInt8RangeType,
				@"int8range",
				NSLocalizedString(@"Range of bigint values", @"description for int8range type"),
				NSLocalizedString(@"Range of bigint. Supports same operations as int4range but for larger integers.",@"description of int8range")
			),
			MakeFieldTypeHelp(
				SPPostgresNumRangeType,
				@"numrange",
				NSLocalizedString(@"Range of numeric values", @"description for numrange type"),
				NSLocalizedString(@"Range of numeric. Useful for continuous numeric ranges where exact precision is required.",@"description of numrange")
			),
			MakeFieldTypeHelp(
				SPPostgresTsRangeType,
				@"tsrange",
				NSLocalizedString(@"Range of timestamp without time zone", @"description for tsrange type"),
				NSLocalizedString(@"Range of timestamp without time zone. Useful for scheduling and time period operations.",@"description of tsrange")
			),
			MakeFieldTypeHelp(
				SPPostgresTsTZRangeType,
				@"tstzrange",
				NSLocalizedString(@"Range of timestamp with time zone", @"description for tstzrange type"),
				NSLocalizedString(@"Range of timestamp with time zone. Time zone aware scheduling and time period operations.",@"description of tstzrange")
			),
			MakeFieldTypeHelp(
				SPPostgresDateRangeType,
				@"daterange",
				NSLocalizedString(@"Range of date values", @"description for daterange type"),
				NSLocalizedString(@"Range of date. Useful for date-based intervals and period calculations.",@"description of daterange")
			),
			// ==================== OTHER TYPES ====================
			MakeFieldTypeHelp(
				SPPostgresXMLType,
				@"xml",
				NSLocalizedString(@"Variable length", @"range for xml type"),
				NSLocalizedString(@"XML data type. Validates well-formedness on input. Supports XPath queries and XML functions.",@"description of xml")
			),
			MakeFieldTypeHelp(
				SPPostgresTsVectorType,
				@"tsvector",
				NSLocalizedString(@"Variable length, sorted list of lexemes", @"range for tsvector type"),
				NSLocalizedString(@"Text search document. Sorted list of distinct lexemes (normalized words) with optional position and weight information. Use to_tsvector() to create.",@"description of tsvector")
			),
			MakeFieldTypeHelp(
				SPPostgresTsQueryType,
				@"tsquery",
				NSLocalizedString(@"Variable length", @"range for tsquery type"),
				NSLocalizedString(@"Text search query. Normalized lexemes combined with Boolean operators (& | !) and phrase search. Use to_tsquery() or plainto_tsquery() to create.",@"description of tsquery")
			),
		];
#undef FN
	});

	for (SPFieldTypeHelp *item in list) {
		if ([[item typeName] isEqualToString:typeName]) {
			return item;
		}
	}
	
	return nil;
}

- (IBAction)filterChanged:(NSSearchField *)sender {
	if (sender == filterSearchField && [self filterFieldsWithString:sender.stringValue]) {
		[tableSourceView reloadData];
	}
}

- (BOOL)filterFieldsWithString:(NSString *)filterString {
	if (selectedTable) {
		NSString *search = [filterString.lowercaseString stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
		if (search.length == 0 && filteredTableFields != nil) {
			// clear the filter and reload
			filteredTableFields = nil;
			return YES;
		}

		// start new filter
		NSUInteger fieldCount = tableFields.count;
		if (search.length > 0 && fieldCount > 0) {
			NSMutableArray *filteredFields = [[NSMutableArray alloc] initWithCapacity: fieldCount];
			for (NSDictionary *entry in tableFields) {
				NSString *value = entry[@"name"];
				if ([value.lowercaseString contains: search]) {
					[filteredFields addObject: entry];
					NSLog(@"%@", entry);
				}
			}

			if (filteredFields.count < fieldCount) {
				filteredTableFields = filteredFields;
				return YES;
			}
		}
	}

	return NO;
}

@end

#pragma mark -

void _BuildMenuWithPills(NSMenu *menu, struct _cmpMap *map, size_t mapEntries)
{
	NSDictionary *baseAttrs = @{NSFontAttributeName: [menu font], NSParagraphStyleAttributeName: [NSParagraphStyle defaultParagraphStyle]};

	for (NSMenuItem *item in [menu itemArray])
	{
		NSMutableAttributedString *itemStr = [[NSMutableAttributedString alloc] initWithString:[item title] attributes:baseAttrs];
		NSString *value = [item representedObject];

		NSMutableArray *tooltipParts = [NSMutableArray array];

		for (unsigned int i = 0; i < mapEntries; ++i)
		{
			struct _cmpMap *cmp = &map[i];

			if ([cmp->cmpWith isEqualToString:value]) {

				SPPillAttachmentCell *cell = [[SPPillAttachmentCell alloc] init];

				[cell setStringValue:cmp->title];

				NSTextAttachment *attachment = [[NSTextAttachment alloc] init];

				[attachment setAttachmentCell:cell];

				NSAttributedString *attachmentString = [NSAttributedString attributedStringWithAttachment:attachment];

				[[itemStr mutableString] appendString:@" "];
				[itemStr appendAttributedString:attachmentString];

				if (cmp->tooltipPart) {
					[tooltipParts addObject:cmp->tooltipPart];
				}
			}
		}

		if ([tooltipParts count]) {
			[item setToolTip:[tooltipParts componentsJoinedByString:@" "]];
		}

		[item setAttributedTitle:itemStr];
	}
}
