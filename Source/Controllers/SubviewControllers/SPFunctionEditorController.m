//
//  SPFunctionEditorController.m
//  Sequel PAce
//
//  Created for PostgreSQL function and procedure management.
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

#import "SPFunctionEditorController.h"
#import "SPDatabaseDocument.h"
#import "SPPostgresConnection.h"
#import "SPTablesList.h"
#import "SPFunctions.h"
#import "SPLogger.h"

@interface SPFunctionEditorController ()

- (void)setupUI;
- (void)resetFields;
- (NSString *)validatedFunctionName;
- (BOOL)validateInput;
- (void)loadDataTypes;
- (void)loadLanguages;
- (NSString *)buildParameterString;

@end

@implementation SPFunctionEditorController

@synthesize tableDocumentInstance;
@synthesize currentSchema;
@synthesize parameters;

#pragma mark - Initialization

- (instancetype)initWithDocument:(SPDatabaseDocument *)document
{
	if ((self = [super initWithWindowNibName:@"FunctionEditor"])) {
		tableDocumentInstance = document;
		connection = [document getConnection];
		currentSchema = @"public";
		editingFunctionName = nil;
		parameters = [[NSMutableArray alloc] init];
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
	// Setup routine type popup
	[routineTypePopup removeAllItems];
	[routineTypePopup addItemsWithTitles:@[@"Function", @"Procedure"]];
	[routineTypePopup selectItemAtIndex:0];

	// Setup volatility popup
	[volatilityPopup removeAllItems];
	[volatilityPopup addItemsWithTitles:@[@"VOLATILE", @"STABLE", @"IMMUTABLE"]];
	[volatilityPopup selectItemAtIndex:0];

	// Setup security popup
	[securityPopup removeAllItems];
	[securityPopup addItemsWithTitles:@[@"INVOKER", @"DEFINER"]];
	[securityPopup selectItemAtIndex:0];

	// Load data types and languages
	[self loadDataTypes];
	[self loadLanguages];

	// Set default values
	[self resetFields];
}

- (void)resetFields
{
	[functionNameField setStringValue:@""];
	[routineTypePopup selectItemAtIndex:0];
	[returnTypePopup selectItemWithTitle:@"void"];
	[languagePopup selectItemWithTitle:@"plpgsql"];
	[volatilityPopup selectItemAtIndex:0];
	[securityPopup selectItemAtIndex:0];
	[strictCheckbox setState:NSControlStateValueOff];
	[leakproofCheckbox setState:NSControlStateValueOff];
	[functionBodyTextView setString:@"BEGIN\n    -- Function body here\nEND;"];
	[parameters removeAllObjects];
	[parametersTableView reloadData];
	[statusLabel setStringValue:@""];
}

- (void)loadDataTypes
{
	[returnTypePopup removeAllItems];

	// Common PostgreSQL data types
	NSArray *commonTypes = @[
		@"void", @"boolean", @"smallint", @"integer", @"bigint",
		@"real", @"double precision", @"numeric", @"money",
		@"char", @"varchar", @"text", @"bytea",
		@"date", @"time", @"timestamp", @"timestamptz", @"interval",
		@"uuid", @"json", @"jsonb", @"xml",
		@"point", @"line", @"lseg", @"box", @"path", @"polygon", @"circle",
		@"inet", @"cidr", @"macaddr",
		@"int4range", @"int8range", @"numrange", @"tsrange", @"tstzrange", @"daterange",
		@"SETOF record", @"TABLE", @"trigger"
	];

	[returnTypePopup addItemsWithTitles:commonTypes];
}

- (void)loadLanguages
{
	[languagePopup removeAllItems];

	// Query for available languages
	NSString *query = @"SELECT lanname FROM pg_language WHERE lanpltrusted = true OR lanname IN ('plpgsql', 'sql', 'c') ORDER BY lanname";
	SPPostgresResult *result = [connection queryString:query];

	NSMutableArray *languages = [NSMutableArray array];
	[languages addObject:@"sql"]; // Always available

	if (![connection queryErrored] && result) {
		for (NSDictionary *row in result) {
			NSString *langName = [row objectForKey:@"lanname"];
			if (langName && ![langName isKindOfClass:[NSNull class]] && ![languages containsObject:langName]) {
				[languages addObject:langName];
			}
		}
	}

	// Ensure plpgsql is in the list
	if (![languages containsObject:@"plpgsql"]) {
		[languages addObject:@"plpgsql"];
	}

	[languagePopup addItemsWithTitles:languages];
	[languagePopup selectItemWithTitle:@"plpgsql"];
}

#pragma mark - Sheet Management

- (void)showCreateFunctionSheetAttachedToWindow:(NSWindow *)window
{
	isEditMode = NO;
	editingFunctionName = nil;

	[self resetFields];
	[routineTypePopup selectItemAtIndex:SPRoutineTypeFunction];
	[returnTypePopup setEnabled:YES];

	[createButton setTitle:NSLocalizedString(@"Create", @"Create button")];

	[window beginSheet:functionSheet completionHandler:^(NSModalResponse returnCode) {
		// Sheet closed
	}];
}

- (void)showCreateProcedureSheetAttachedToWindow:(NSWindow *)window
{
	isEditMode = NO;
	editingFunctionName = nil;

	[self resetFields];
	[routineTypePopup selectItemAtIndex:SPRoutineTypeProcedure];
	[returnTypePopup selectItemWithTitle:@"void"];
	[returnTypePopup setEnabled:NO];

	[createButton setTitle:NSLocalizedString(@"Create", @"Create button")];

	[window beginSheet:functionSheet completionHandler:^(NSModalResponse returnCode) {
		// Sheet closed
	}];
}

- (void)showEditFunctionSheet:(NSString *)functionName attachedToWindow:(NSWindow *)window
{
	isEditMode = YES;
	editingFunctionName = [functionName copy];

	[self resetFields];
	[routineTypePopup selectItemAtIndex:SPRoutineTypeFunction];
	[self loadFunctionProperties:functionName];

	[createButton setTitle:NSLocalizedString(@"Save", @"Save button")];

	[window beginSheet:functionSheet completionHandler:^(NSModalResponse returnCode) {
		// Sheet closed
	}];
}

- (void)showEditProcedureSheet:(NSString *)procedureName attachedToWindow:(NSWindow *)window
{
	isEditMode = YES;
	editingFunctionName = [procedureName copy];

	[self resetFields];
	[routineTypePopup selectItemAtIndex:SPRoutineTypeProcedure];
	[returnTypePopup selectItemWithTitle:@"void"];
	[returnTypePopup setEnabled:NO];
	[self loadFunctionProperties:procedureName];

	[createButton setTitle:NSLocalizedString(@"Save", @"Save button")];

	[window beginSheet:functionSheet completionHandler:^(NSModalResponse returnCode) {
		// Sheet closed
	}];
}

#pragma mark - Actions

- (IBAction)confirmFunction:(id)sender
{
	if (![self validateInput]) {
		return;
	}

	[progressIndicator startAnimation:nil];
	[statusLabel setStringValue:NSLocalizedString(@"Processing...", @"Processing status")];

	BOOL success = isEditMode ? [self replaceFunction] : [self createFunction];

	[progressIndicator stopAnimation:nil];

	if (success) {
		[statusLabel setStringValue:@""];
		[[functionSheet sheetParent] endSheet:functionSheet returnCode:NSModalResponseOK];

		// Refresh the tables list
		if (tableDocumentInstance) {
			[[tableDocumentInstance tablesListInstance] updateTables:self];
		}
	}
}

- (IBAction)cancelFunction:(id)sender
{
	[[functionSheet sheetParent] endSheet:functionSheet returnCode:NSModalResponseCancel];
}

- (IBAction)addParameter:(id)sender
{
	NSDictionary *param = @{
		@"name": @"param",
		@"type": @"integer",
		@"mode": @"IN",
		@"default": @""
	};
	[parameters addObject:[param mutableCopy]];
	[parametersTableView reloadData];
}

- (IBAction)removeParameter:(id)sender
{
	NSInteger selectedRow = [parametersTableView selectedRow];
	if (selectedRow >= 0 && selectedRow < (NSInteger)[parameters count]) {
		[parameters removeObjectAtIndex:selectedRow];
		[parametersTableView reloadData];
	}
}

- (IBAction)routineTypeChanged:(id)sender
{
	SPRoutineType type = (SPRoutineType)[routineTypePopup indexOfSelectedItem];
	if (type == SPRoutineTypeProcedure) {
		[returnTypePopup selectItemWithTitle:@"void"];
		[returnTypePopup setEnabled:NO];
	} else {
		[returnTypePopup setEnabled:YES];
	}
}

#pragma mark - Validation

- (BOOL)validateInput
{
	NSString *functionName = [self validatedFunctionName];

	if (!functionName || [functionName length] == 0) {
		[statusLabel setStringValue:NSLocalizedString(@"Function name is required", @"Error message")];
		[functionNameField becomeFirstResponder];
		return NO;
	}

	NSString *body = [[functionBodyTextView string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([body length] == 0) {
		[statusLabel setStringValue:NSLocalizedString(@"Function body is required", @"Error message")];
		return NO;
	}

	[statusLabel setStringValue:@""];
	return YES;
}

- (NSString *)validatedFunctionName
{
	NSString *name = [[functionNameField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return name;
}

#pragma mark - Function Operations

- (BOOL)createFunction
{
	SPRoutineType type = (SPRoutineType)[routineTypePopup indexOfSelectedItem];
	NSString *sql = (type == SPRoutineTypeProcedure) ? [self createProcedureSQL] : [self createFunctionSQL];

	SPLog(@"Creating function with SQL: %@", sql);

	[connection queryString:sql];

	if ([connection queryErrored]) {
		NSString *error = [connection lastErrorMessage] ?: @"Unknown error";
		[statusLabel setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Error: %@", @"Error message format"), error]];
		SPLog(@"Error creating function: %@", error);
		return NO;
	}

	return YES;
}

- (BOOL)replaceFunction
{
	SPRoutineType type = (SPRoutineType)[routineTypePopup indexOfSelectedItem];
	NSString *sql = (type == SPRoutineTypeProcedure) ? [self createProcedureSQL] : [self createFunctionSQL];

	// Add OR REPLACE for functions
	sql = [sql stringByReplacingOccurrencesOfString:@"CREATE FUNCTION" withString:@"CREATE OR REPLACE FUNCTION"];
	sql = [sql stringByReplacingOccurrencesOfString:@"CREATE PROCEDURE" withString:@"CREATE OR REPLACE PROCEDURE"];

	SPLog(@"Replacing function with SQL: %@", sql);

	[connection queryString:sql];

	if ([connection queryErrored]) {
		NSString *error = [connection lastErrorMessage] ?: @"Unknown error";
		[statusLabel setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Error: %@", @"Error message format"), error]];
		SPLog(@"Error replacing function: %@", error);
		return NO;
	}

	return YES;
}

- (void)loadFunctionProperties:(NSString *)functionName
{
	[functionNameField setStringValue:functionName ?: @""];

	// Query function properties
	NSString *query = [NSString stringWithFormat:
		@"SELECT p.proname, pg_get_function_result(p.oid) as return_type, "
		 "pg_get_function_arguments(p.oid) as arguments, "
		 "l.lanname as language, p.prosrc as source, "
		 "p.provolatile, p.prosecdef, p.proisstrict, p.proleakproof, p.prokind "
		 "FROM pg_proc p "
		 "JOIN pg_namespace n ON p.pronamespace = n.oid "
		 "JOIN pg_language l ON p.prolang = l.oid "
		 "WHERE p.proname = '%@' AND n.nspname = '%@'",
		functionName, currentSchema ?: @"public"];

	SPPostgresResult *result = [connection queryString:query];

	if (![connection queryErrored] && result && [result numberOfRows] > 0) {
		NSDictionary *row = [result getRowAsDictionary];

		id returnType = [row objectForKey:@"return_type"];
		if (returnType && ![returnType isKindOfClass:[NSNull class]]) {
			if ([returnTypePopup itemWithTitle:returnType]) {
				[returnTypePopup selectItemWithTitle:returnType];
			}
		}

		id language = [row objectForKey:@"language"];
		if (language && ![language isKindOfClass:[NSNull class]]) {
			if ([languagePopup itemWithTitle:language]) {
				[languagePopup selectItemWithTitle:language];
			}
		}

		id source = [row objectForKey:@"source"];
		if (source && ![source isKindOfClass:[NSNull class]]) {
			[functionBodyTextView setString:source];
		}

		id volatile_str = [row objectForKey:@"provolatile"];
		if (volatile_str && ![volatile_str isKindOfClass:[NSNull class]]) {
			NSString *v = [volatile_str description];
			if ([v isEqualToString:@"v"]) {
				[volatilityPopup selectItemWithTitle:@"VOLATILE"];
			} else if ([v isEqualToString:@"s"]) {
				[volatilityPopup selectItemWithTitle:@"STABLE"];
			} else if ([v isEqualToString:@"i"]) {
				[volatilityPopup selectItemWithTitle:@"IMMUTABLE"];
			}
		}

		id secdef = [row objectForKey:@"prosecdef"];
		if (secdef && ![secdef isKindOfClass:[NSNull class]]) {
			[securityPopup selectItemAtIndex:[secdef boolValue] ? 1 : 0];
		}

		id strict = [row objectForKey:@"proisstrict"];
		if (strict && ![strict isKindOfClass:[NSNull class]]) {
			[strictCheckbox setState:[strict boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
		}

		id leakproof = [row objectForKey:@"proleakproof"];
		if (leakproof && ![leakproof isKindOfClass:[NSNull class]]) {
			[leakproofCheckbox setState:[leakproof boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
		}

		id prokind = [row objectForKey:@"prokind"];
		if (prokind && ![prokind isKindOfClass:[NSNull class]]) {
			if ([[prokind description] isEqualToString:@"p"]) {
				[routineTypePopup selectItemAtIndex:SPRoutineTypeProcedure];
				[returnTypePopup setEnabled:NO];
			} else {
				[routineTypePopup selectItemAtIndex:SPRoutineTypeFunction];
				[returnTypePopup setEnabled:YES];
			}
		}
	}
}

- (NSString *)buildParameterString
{
	if ([parameters count] == 0) {
		return @"";
	}

	NSMutableArray *paramStrings = [NSMutableArray array];
	for (NSDictionary *param in parameters) {
		NSString *mode = param[@"mode"] ?: @"IN";
		NSString *name = param[@"name"] ?: @"param";
		NSString *type = param[@"type"] ?: @"integer";
		NSString *defaultVal = param[@"default"];

		NSMutableString *paramStr = [NSMutableString string];
		[paramStr appendFormat:@"%@ %@ %@", mode, name, type];

		if (defaultVal && [defaultVal length] > 0) {
			[paramStr appendFormat:@" DEFAULT %@", defaultVal];
		}

		[paramStrings addObject:paramStr];
	}

	return [paramStrings componentsJoinedByString:@", "];
}

- (NSString *)createFunctionSQL
{
	NSMutableString *sql = [NSMutableString string];
	NSString *functionName = [self validatedFunctionName];
	NSString *schema = currentSchema ?: @"public";

	[sql appendFormat:@"CREATE FUNCTION %@.%@(%@)\n",
		[schema postgresQuotedIdentifier],
		[functionName postgresQuotedIdentifier],
		[self buildParameterString]];

	// Return type
	NSString *returnType = [[returnTypePopup selectedItem] title];
	[sql appendFormat:@"RETURNS %@\n", returnType];

	// Language
	NSString *language = [[languagePopup selectedItem] title];
	[sql appendFormat:@"LANGUAGE %@\n", language];

	// Volatility
	NSString *volatility = [[volatilityPopup selectedItem] title];
	[sql appendFormat:@"%@\n", volatility];

	// Security
	if ([securityPopup indexOfSelectedItem] == 1) {
		[sql appendString:@"SECURITY DEFINER\n"];
	}

	// Strict
	if ([strictCheckbox state] == NSControlStateValueOn) {
		[sql appendString:@"STRICT\n"];
	}

	// Leakproof
	if ([leakproofCheckbox state] == NSControlStateValueOn) {
		[sql appendString:@"LEAKPROOF\n"];
	}

	// Body
	NSString *body = [functionBodyTextView string];
	[sql appendFormat:@"AS $$\n%@\n$$", body];

	return sql;
}

- (NSString *)createProcedureSQL
{
	NSMutableString *sql = [NSMutableString string];
	NSString *procName = [self validatedFunctionName];
	NSString *schema = currentSchema ?: @"public";

	[sql appendFormat:@"CREATE PROCEDURE %@.%@(%@)\n",
		[schema postgresQuotedIdentifier],
		[procName postgresQuotedIdentifier],
		[self buildParameterString]];

	// Language
	NSString *language = [[languagePopup selectedItem] title];
	[sql appendFormat:@"LANGUAGE %@\n", language];

	// Security
	if ([securityPopup indexOfSelectedItem] == 1) {
		[sql appendString:@"SECURITY DEFINER\n"];
	}

	// Body
	NSString *body = [functionBodyTextView string];
	[sql appendFormat:@"AS $$\n%@\n$$", body];

	return sql;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [parameters count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row >= (NSInteger)[parameters count]) return nil;

	NSDictionary *param = [parameters objectAtIndex:row];
	NSString *identifier = [tableColumn identifier];

	return [param objectForKey:identifier];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row >= (NSInteger)[parameters count]) return;

	NSMutableDictionary *param = [parameters objectAtIndex:row];
	NSString *identifier = [tableColumn identifier];

	[param setObject:(object ?: @"") forKey:identifier];
}

@end
