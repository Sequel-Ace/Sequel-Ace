//
//  SPSequenceEditorController.m
//  Sequel PAce
//
//  Created for PostgreSQL sequence management.
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

#import "SPSequenceEditorController.h"
#import "SPDatabaseDocument.h"
#import "SPPostgresConnection.h"
#import "SPTablesList.h"
#import "SPFunctions.h"
#import "SPLogger.h"

@interface SPSequenceEditorController ()

- (void)setupUI;
- (void)resetFields;
- (NSString *)validatedSequenceName;
- (BOOL)validateInput;

@end

@implementation SPSequenceEditorController

@synthesize tableDocumentInstance;
@synthesize currentSchema;

#pragma mark - Initialization

- (instancetype)initWithDocument:(SPDatabaseDocument *)document
{
	if ((self = [super initWithWindowNibName:@"SequenceEditor"])) {
		tableDocumentInstance = document;
		connection = [document getConnection];
		currentSchema = @"public";
		editingSequenceName = nil;
		isEditMode = NO;
	}
	return self;
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	[self setupUI];
}

- (void)setupUI
{
	// Setup data type popup
	[dataTypePopup removeAllItems];
	[dataTypePopup addItemsWithTitles:@[@"bigint", @"integer", @"smallint"]];
	[dataTypePopup selectItemAtIndex:0];

	// Setup owner popup (will be populated when sheet is shown)
	[ownerPopup removeAllItems];

	// Set default values
	[self resetFields];
}

- (void)resetFields
{
	[sequenceNameField setStringValue:@""];
	[startValueField setStringValue:@"1"];
	[incrementByField setStringValue:@"1"];
	[minValueField setStringValue:@""];
	[maxValueField setStringValue:@""];
	[cacheValueField setStringValue:@"1"];
	[cycleCheckbox setState:NSControlStateValueOff];
	[dataTypePopup selectItemAtIndex:0];
	[statusLabel setStringValue:@""];
}

#pragma mark - Sheet Management

- (void)showCreateSequenceSheetAttachedToWindow:(NSWindow *)window
{
	isEditMode = NO;
	editingSequenceName = nil;

	[self resetFields];
	[self loadOwners];

	[createButton setTitle:NSLocalizedString(@"Create", @"Create button")];

	[window beginSheet:sequenceSheet completionHandler:^(NSModalResponse returnCode) {
		// Sheet closed
	}];
}

- (void)showEditSequenceSheet:(NSString *)sequenceName attachedToWindow:(NSWindow *)window
{
	isEditMode = YES;
	editingSequenceName = [sequenceName copy];

	[self resetFields];
	[self loadOwners];
	[self loadSequenceProperties:sequenceName];

	[createButton setTitle:NSLocalizedString(@"Save", @"Save button")];

	[window beginSheet:sequenceSheet completionHandler:^(NSModalResponse returnCode) {
		// Sheet closed
	}];
}

- (void)loadOwners
{
	[ownerPopup removeAllItems];

	// Query for database roles
	NSString *query = @"SELECT rolname FROM pg_roles WHERE rolcanlogin = true ORDER BY rolname";
	SPPostgresResult *result = [connection queryString:query];

	if (![connection queryErrored] && result) {
		for (NSDictionary *row in result) {
			NSString *roleName = [row objectForKey:@"rolname"];
			if (roleName && ![roleName isKindOfClass:[NSNull class]]) {
				[ownerPopup addItemWithTitle:roleName];
			}
		}
	}

	// Add current user if not in list
	NSString *currentUser = [connection currentUser];
	if (currentUser && ![ownerPopup itemWithTitle:currentUser]) {
		[ownerPopup insertItemWithTitle:currentUser atIndex:0];
	}

	// Select current user as default
	if (currentUser) {
		[ownerPopup selectItemWithTitle:currentUser];
	}
}

#pragma mark - Actions

- (IBAction)confirmSequence:(id)sender
{
	if (![self validateInput]) {
		return;
	}

	[progressIndicator startAnimation:nil];
	[statusLabel setStringValue:NSLocalizedString(@"Processing...", @"Processing status")];

	BOOL success = isEditMode ? [self alterSequence] : [self createSequence];

	[progressIndicator stopAnimation:nil];

	if (success) {
		[statusLabel setStringValue:@""];
		[[sequenceSheet sheetParent] endSheet:sequenceSheet returnCode:NSModalResponseOK];

		// Refresh the tables list
		if (tableDocumentInstance) {
			[[tableDocumentInstance tablesListInstance] updateTables:self];
		}
	}
}

- (IBAction)cancelSequence:(id)sender
{
	[[sequenceSheet sheetParent] endSheet:sequenceSheet returnCode:NSModalResponseCancel];
}

- (IBAction)resetToDefaults:(id)sender
{
	[self resetFields];
	if (editingSequenceName) {
		[sequenceNameField setStringValue:editingSequenceName];
	}
}

#pragma mark - Validation

- (BOOL)validateInput
{
	NSString *sequenceName = [self validatedSequenceName];

	if (!sequenceName || [sequenceName length] == 0) {
		[statusLabel setStringValue:NSLocalizedString(@"Sequence name is required", @"Error message")];
		[sequenceNameField becomeFirstResponder];
		return NO;
	}

	// Validate numeric fields
	NSString *startValue = [startValueField stringValue];
	if ([startValue length] > 0) {
		NSScanner *scanner = [NSScanner scannerWithString:startValue];
		long long value;
		if (![scanner scanLongLong:&value] || ![scanner isAtEnd]) {
			[statusLabel setStringValue:NSLocalizedString(@"Start value must be a valid integer", @"Error message")];
			[startValueField becomeFirstResponder];
			return NO;
		}
	}

	NSString *incrementBy = [incrementByField stringValue];
	if ([incrementBy length] > 0) {
		NSScanner *scanner = [NSScanner scannerWithString:incrementBy];
		long long value;
		if (![scanner scanLongLong:&value] || ![scanner isAtEnd] || value == 0) {
			[statusLabel setStringValue:NSLocalizedString(@"Increment must be a non-zero integer", @"Error message")];
			[incrementByField becomeFirstResponder];
			return NO;
		}
	}

	[statusLabel setStringValue:@""];
	return YES;
}

- (NSString *)validatedSequenceName
{
	NSString *name = [[sequenceNameField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return name;
}

#pragma mark - Sequence Operations

- (BOOL)createSequence
{
	NSString *sql = [self createSequenceSQL];
	SPLog(@"Creating sequence with SQL: %@", sql);

	[connection queryString:sql];

	if ([connection queryErrored]) {
		NSString *error = [connection lastErrorMessage] ?: @"Unknown error";
		[statusLabel setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Error: %@", @"Error message format"), error]];
		SPLog(@"Error creating sequence: %@", error);
		return NO;
	}

	return YES;
}

- (BOOL)alterSequence
{
	NSString *sql = [self alterSequenceSQL];
	SPLog(@"Altering sequence with SQL: %@", sql);

	[connection queryString:sql];

	if ([connection queryErrored]) {
		NSString *error = [connection lastErrorMessage] ?: @"Unknown error";
		[statusLabel setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Error: %@", @"Error message format"), error]];
		SPLog(@"Error altering sequence: %@", error);
		return NO;
	}

	return YES;
}

- (void)loadSequenceProperties:(NSString *)sequenceName
{
	[sequenceNameField setStringValue:sequenceName ?: @""];

	// Query sequence properties
	NSString *query = [NSString stringWithFormat:
		@"SELECT s.seqstart, s.seqincrement, s.seqmin, s.seqmax, s.seqcache, s.seqcycle, "
		 "pg_get_userbyid(c.relowner) as owner, "
		 "CASE WHEN s.seqtypid = 20 THEN 'bigint' "
		 "     WHEN s.seqtypid = 23 THEN 'integer' "
		 "     WHEN s.seqtypid = 21 THEN 'smallint' "
		 "     ELSE 'bigint' END as data_type "
		 "FROM pg_sequence s "
		 "JOIN pg_class c ON s.seqrelid = c.oid "
		 "JOIN pg_namespace n ON c.relnamespace = n.oid "
		 "WHERE c.relname = '%@' AND n.nspname = '%@'",
		sequenceName, currentSchema ?: @"public"];

	SPPostgresResult *result = [connection queryString:query];

	if (![connection queryErrored] && result && [result numberOfRows] > 0) {
		NSDictionary *row = [result getRowAsDictionary];

		id startValue = [row objectForKey:@"seqstart"];
		if (startValue && ![startValue isKindOfClass:[NSNull class]]) {
			[startValueField setStringValue:[startValue description]];
		}

		id increment = [row objectForKey:@"seqincrement"];
		if (increment && ![increment isKindOfClass:[NSNull class]]) {
			[incrementByField setStringValue:[increment description]];
		}

		id minValue = [row objectForKey:@"seqmin"];
		if (minValue && ![minValue isKindOfClass:[NSNull class]]) {
			[minValueField setStringValue:[minValue description]];
		}

		id maxValue = [row objectForKey:@"seqmax"];
		if (maxValue && ![maxValue isKindOfClass:[NSNull class]]) {
			[maxValueField setStringValue:[maxValue description]];
		}

		id cacheValue = [row objectForKey:@"seqcache"];
		if (cacheValue && ![cacheValue isKindOfClass:[NSNull class]]) {
			[cacheValueField setStringValue:[cacheValue description]];
		}

		id cycle = [row objectForKey:@"seqcycle"];
		if (cycle && ![cycle isKindOfClass:[NSNull class]]) {
			[cycleCheckbox setState:[cycle boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
		}

		id dataType = [row objectForKey:@"data_type"];
		if (dataType && ![dataType isKindOfClass:[NSNull class]]) {
			[dataTypePopup selectItemWithTitle:dataType];
		}

		id owner = [row objectForKey:@"owner"];
		if (owner && ![owner isKindOfClass:[NSNull class]]) {
			if ([ownerPopup itemWithTitle:owner]) {
				[ownerPopup selectItemWithTitle:owner];
			}
		}
	}
}

- (NSString *)createSequenceSQL
{
	NSMutableString *sql = [NSMutableString string];
	NSString *sequenceName = [self validatedSequenceName];
	NSString *schema = currentSchema ?: @"public";

	[sql appendFormat:@"CREATE SEQUENCE %@.%@",
		[schema postgresQuotedIdentifier],
		[sequenceName postgresQuotedIdentifier]];

	// Data type
	NSString *dataType = [[dataTypePopup selectedItem] title];
	if (dataType && ![dataType isEqualToString:@"bigint"]) {
		[sql appendFormat:@" AS %@", dataType];
	}

	// Increment
	NSString *increment = [incrementByField stringValue];
	if ([increment length] > 0 && ![increment isEqualToString:@"1"]) {
		[sql appendFormat:@" INCREMENT BY %@", increment];
	}

	// Min value
	NSString *minValue = [minValueField stringValue];
	if ([minValue length] > 0) {
		[sql appendFormat:@" MINVALUE %@", minValue];
	} else {
		[sql appendString:@" NO MINVALUE"];
	}

	// Max value
	NSString *maxValue = [maxValueField stringValue];
	if ([maxValue length] > 0) {
		[sql appendFormat:@" MAXVALUE %@", maxValue];
	} else {
		[sql appendString:@" NO MAXVALUE"];
	}

	// Start value
	NSString *startValue = [startValueField stringValue];
	if ([startValue length] > 0) {
		[sql appendFormat:@" START WITH %@", startValue];
	}

	// Cache
	NSString *cacheValue = [cacheValueField stringValue];
	if ([cacheValue length] > 0 && ![cacheValue isEqualToString:@"1"]) {
		[sql appendFormat:@" CACHE %@", cacheValue];
	}

	// Cycle
	if ([cycleCheckbox state] == NSControlStateValueOn) {
		[sql appendString:@" CYCLE"];
	} else {
		[sql appendString:@" NO CYCLE"];
	}

	return sql;
}

- (NSString *)alterSequenceSQL
{
	NSMutableString *sql = [NSMutableString string];
	NSString *sequenceName = editingSequenceName ?: [self validatedSequenceName];
	NSString *schema = currentSchema ?: @"public";

	[sql appendFormat:@"ALTER SEQUENCE %@.%@",
		[schema postgresQuotedIdentifier],
		[sequenceName postgresQuotedIdentifier]];

	// Increment
	NSString *increment = [incrementByField stringValue];
	if ([increment length] > 0) {
		[sql appendFormat:@" INCREMENT BY %@", increment];
	}

	// Min value
	NSString *minValue = [minValueField stringValue];
	if ([minValue length] > 0) {
		[sql appendFormat:@" MINVALUE %@", minValue];
	} else {
		[sql appendString:@" NO MINVALUE"];
	}

	// Max value
	NSString *maxValue = [maxValueField stringValue];
	if ([maxValue length] > 0) {
		[sql appendFormat:@" MAXVALUE %@", maxValue];
	} else {
		[sql appendString:@" NO MAXVALUE"];
	}

	// Restart value
	NSString *startValue = [startValueField stringValue];
	if ([startValue length] > 0) {
		[sql appendFormat:@" RESTART WITH %@", startValue];
	}

	// Cache
	NSString *cacheValue = [cacheValueField stringValue];
	if ([cacheValue length] > 0) {
		[sql appendFormat:@" CACHE %@", cacheValue];
	}

	// Cycle
	if ([cycleCheckbox state] == NSControlStateValueOn) {
		[sql appendString:@" CYCLE"];
	} else {
		[sql appendString:@" NO CYCLE"];
	}

	return sql;
}

@end
