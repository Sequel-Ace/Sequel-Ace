//
//  SPDataImport.m
//  sequel-pro
//
//  Created by Lorenz Textor (lorenz@textor.ch) on Wed May 1, 2002.
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

#import "SPDataImport.h"
#import "SPDatabaseDocument.h"
#import "SPTablesList.h"
#import "SPTableStructure.h"
#import "SPDatabaseStructure.h"
#import "SPCustomQuery.h"
#import "SPSQLParser.h"
#import "SPCSVParser.h"
#import "SPTableData.h"
#import "RegexKitLite.h"
#import "SPAlertSheets.h"
#import "SPFieldMapperController.h"
#import "SPFileHandle.h"
#import "SPEncodingPopupAccessory.h"
#import "SPThreadAdditions.h"
#import "SPFunctions.h"
#import "SPQueryController.h"
#import "SPConstants.h"

#import <SPMySQL/SPMySQL.h>

#import "sequel-ace-Swift.h"

#define SP_FILE_READ_ERROR_STRING NSLocalizedString(@"File read error", @"File read error title (Import Dialog)")

@interface SPDataImport ()

- (void)_startBackgroundImportTaskForFilename:(NSString *)filename;
- (void)_importBackgroundProcess:(NSDictionary *)userInfo;
- (void)_closeAndStopProgressSheet;
- (NSString *)_getLineEndingForFile:(NSString *)filePath;

@property (readwrite, strong) NSFileManager *fileManager;

@end

@implementation SPDataImport

@synthesize fileManager;

#pragma mark -
#pragma mark Initialisation

- (id)init
{
	if ((self = [super init])) {
		
		geometryFields = [[NSMutableArray alloc] init];
		geometryFieldsMapIndex = [[NSMutableIndexSet alloc] init];
		bitFields = [[NSMutableArray alloc] init];
		bitFieldsMapIndex = [[NSMutableIndexSet alloc] init];
		nullableNumericFields = [[NSMutableArray alloc] init];
		nullableNumericFieldsMapIndex = [[NSMutableIndexSet alloc] init];
		fieldMappingArray = nil;
		fieldMappingGlobalValueArray = nil;
		fieldMappingTableColumnNames = nil;
		fieldMappingTableDefaultValues = nil;
		fieldMappingImportArray = nil;
		csvImportTailString = nil;
		csvImportHeaderString = nil;
		csvImportMethodHasTail = NO;
		fieldMappingImportArrayIsPreview = NO;
		fieldMappingArrayHasGlobalVariables = NO;
		importMethodIsUpdate = NO;
		importIntoNewTable = NO;
		insertRemainingRowsAfterUpdate = NO;
		numberOfImportDataColumns = 0;
		selectedTableTarget = nil;
		
		prefs = nil;
		lastFilename = nil;
		mainNibLoaded = NO;
		fileManager = [NSFileManager defaultManager];
	}
	
	return self;
}

- (void)awakeFromNib
{
	if (mainNibLoaded) return;

	mainNibLoaded = YES;
	
	// Load the import accessory view, retaining a reference to the top-level objects that need releasing.
	NSArray *importAccessoryTopLevelObjects = nil;
	NSNib *nibLoader = [[NSNib alloc] initWithNibNamed:@"ImportAccessory" bundle:[NSBundle mainBundle]];
	[nibLoader instantiateWithOwner:self topLevelObjects:&importAccessoryTopLevelObjects];

	// Set the accessory view's tabview to tabless (left in for easier editing in IB)
	[importTabView setTabViewType:NSNoTabsNoBorder];

	// Set up the encodings menu
	NSMutableArray *encodings = [NSMutableArray arrayWithArray:[SPEncodingPopupAccessory enabledEncodings]];
	[importEncodingPopup removeAllItems];
	[importEncodingPopup addItemWithTitle:NSLocalizedString(@"Autodetect", @"Encoding autodetect menu item")];
	[[importEncodingPopup menu] addItem:[NSMenuItem separatorItem]];
	for (NSNumber *encodingNumber in encodings) {
		[importEncodingPopup addItemWithTitle:[NSString localizedNameOfStringEncoding:[encodingNumber unsignedIntegerValue]]];
		[[importEncodingPopup lastItem] setTag:[encodingNumber unsignedIntegerValue]];
	}
}

#pragma mark -
#pragma mark IBAction methods

/**
 * Shows/hides the CSV options accessory view based on the selected format.
 */
- (IBAction)changeFormat:(id)sender
{
	[importTabView selectTabViewItemAtIndex:[importFormatPopup indexOfSelectedItem]];
}

/**
 * Cancels the current operation.
 */
- (IBAction)cancelProgressBar:(id)sender
{
	progressCancelled = YES;
}

/**
 * Common method for ending modal sessions
 */
- (IBAction)closeSheet:(id)sender
{
	[NSApp endSheet:[sender window] returnCode:[sender tag]];
	[[sender window] orderOut:self];
}

#pragma mark -
#pragma mark Import construction methods

/**
 * Invoked when user clicks on an ImportFromClipboard menuitem.
 */
- (void)importFromClipboard
{
	// clipboard textview with no wrapping
	const CGFloat LargeNumberForText = 1.0e7f;

	[[importFromClipboardTextView textContainer] setContainerSize:NSMakeSize(LargeNumberForText, LargeNumberForText)];
	[[importFromClipboardTextView textContainer] setWidthTracksTextView:NO];
	[[importFromClipboardTextView textContainer] setHeightTracksTextView:NO];
	[importFromClipboardTextView setAutoresizingMask:NSViewNotSizable];
	[importFromClipboardTextView setMaxSize:NSMakeSize(LargeNumberForText, LargeNumberForText)];
	[importFromClipboardTextView setHorizontallyResizable:YES];
	[importFromClipboardTextView setVerticallyResizable:YES];
	[importFromClipboardTextView setFont:[NSFont fontWithName:@"Monaco" size:11.0f]];
	
	if([[[NSPasteboard generalPasteboard] stringForType:NSStringPboardType] length] > 4000)
		[importFromClipboardTextView setString:[[[[NSPasteboard generalPasteboard] stringForType:NSStringPboardType] substringToIndex:4000] stringByAppendingString:@"\n…"]];
	else
		[importFromClipboardTextView setString:[[NSPasteboard generalPasteboard] stringForType:NSStringPboardType]];

	// Preset the accessory view with prefs defaults
	[importFieldsTerminatedField setStringValue:[prefs objectForKey:SPCSVImportFieldTerminator]];
	[importLinesTerminatedField setStringValue:[prefs objectForKey:SPCSVImportLineTerminator]];
	[importFieldsEscapedField setStringValue:[prefs objectForKey:SPCSVImportFieldEscapeCharacter]];
	[importFieldsEnclosedField setStringValue:[prefs objectForKey:SPCSVImportFieldEnclosedBy]];
	[importFieldNamesSwitch setState:[[prefs objectForKey:SPCSVImportFirstLineIsHeader] boolValue]];

	// Reset and disable the encoding menu
	[importEncodingPopup selectItemWithTag:NSUTF8StringEncoding];
	[importEncodingPopup setEnabled:NO];

	// Add the view, and resize it to fit the accessory view size
	[importFromClipboardAccessoryView addSubview:importView];
	NSRect accessoryViewRect = [importFromClipboardAccessoryView frame];
	[importView setFrame:NSMakeRect(0, 0, accessoryViewRect.size.width, accessoryViewRect.size.height)];

	[NSApp beginSheet:importFromClipboardSheet
	   modalForWindow:[tableDocumentInstance parentWindow]
	    modalDelegate:self
	   didEndSelector:@selector(importFromClipboardSheetDidEnd:returnCode:contextInfo:)
	      contextInfo:nil];
}

/**
 * Callback when the import from clipback sheet is closed
 */
- (void)importFromClipboardSheetDidEnd:(id)sheet returnCode:(NSInteger)returnCode contextInfo:(NSString *)contextInfo
{
	// Reset the interface and store prefs
	[importFromClipboardTextView setString:@""];
	[prefs setObject:[[importFormatPopup selectedItem] title] forKey:@"importFormatPopupValue"];

	// Check if the user canceled
	if (returnCode != NSModalResponseOK)
		return;

	// Reset progress cancelled from any previous runs
	progressCancelled = NO;
	
	NSString *importFileName = [NSString stringWithFormat:@"%@%@",
								SPImportClipboardTempFileNamePrefix,
								[[NSDate date] stringWithFormat:@"HHmmss" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]]];
		
	// Write clipboard content to temp file using the connection encoding
	NSStringEncoding encoding;
	if ([[[importFormatPopup selectedItem] title] isEqualToString:@"SQL"])
		encoding = NSUTF8StringEncoding;
	else
		encoding = [mySQLConnection stringEncoding];

	if(![[[NSPasteboard generalPasteboard] stringForType:NSStringPboardType] writeToFile:importFileName atomically:NO encoding:encoding error:nil]) {
		NSBeep();
		NSLog(@"Couldn't write clipboard content to temporary file.");
		return;
	}

	if (importFileName == nil) return;

	// Begin import process
	[self _startBackgroundImportTaskForFilename:importFileName];
}

/**
 * Invoked when user clicks on an import menuitem.
 */
- (void)importFile
{
	// prepare open panel and accessory view
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];

	// Preset the accessory view with prefs defaults
	[importFieldsTerminatedField setStringValue:[prefs objectForKey:SPCSVImportFieldTerminator]];
	[importLinesTerminatedField setStringValue:[prefs objectForKey:SPCSVImportLineTerminator]];
	[importFieldsEscapedField setStringValue:[prefs objectForKey:SPCSVImportFieldEscapeCharacter]];
	[importFieldsEnclosedField setStringValue:[prefs objectForKey:SPCSVImportFieldEnclosedBy]];
	[importFieldNamesSwitch setState:[[prefs objectForKey:SPCSVImportFirstLineIsHeader] boolValue]];

	[openPanel setAccessoryView:importView];
	if ([openPanel respondsToSelector:@selector(isAccessoryViewDisclosed)]) {
		openPanel.accessoryViewDisclosed = YES;
	}
	[openPanel setDelegate:self];
	
	if ([prefs valueForKey:@"importFormatPopupValue"]) {
		[importFormatPopup selectItemWithTitle:[prefs valueForKey:@"importFormatPopupValue"]];
		[self changeFormat:self];
	}

	if (lastFilename && [lastFilename lastPathComponent]) {
		[openPanel setNameFieldStringValue:[lastFilename lastPathComponent]];
	}

	NSString *openPath;
	if((openPath = [prefs objectForKey:@"exportPath"])) {
		// Doc says calling +[NSURL URLWithString:] with nil is fine,
		// but at least on 10.6 this will cause an exception
		[openPanel setDirectoryURL:[NSURL URLWithString:openPath]];
	}

	[openPanel beginSheetModalForWindow:[tableDocumentInstance parentWindow] completionHandler:^(NSInteger returnCode) {
		// Ensure text inputs are completed, preventing dead character entry
		[openPanel makeFirstResponder:nil];

		// Save values to preferences
		[self->prefs setObject:[[openPanel directoryURL] path] forKey:@"exportPath"];
		[self->prefs setObject:[[self->importFormatPopup selectedItem] title] forKey:@"importFormatPopupValue"];

		// Close NSOpenPanel sheet
		[openPanel orderOut:self];

		// Check if the user canceled
		if (returnCode != NSModalResponseOK) return;

		// Reset progress cancelled from any previous runs
		self->progressCancelled = NO;

		

		self->lastFilename = [NSString stringWithString:[[openPanel URL] path]];

		NSString *importFileName = [NSString stringWithString:self->lastFilename];

		if (self->lastFilename == nil || ![self->lastFilename length]) {
			NSBeep();
			return;
		}

		if (importFileName == nil) return;
		
		// Check to see if current connection has existing tables, if so warn
		if([[self->tablesListInstance tables] count] > 1 && [[[self->importFormatPopup selectedItem] title] isEqualToString:@"SQL"]){
			SPBeginAlertSheet(NSLocalizedString(@"The current database already has existing tables, importing may overwrite data. Are you sure you want to continue?", @"title of warning when trying to import data when tables already exist"),
							  NSLocalizedString(@"Yes, continue anyway", @"Yes, continue anyway"),	// Main button
							  NSLocalizedString(@"Cancel import", @"Cancel import"),	// Alternate button
							  nil,	// Other button
							  [self->tableDocumentInstance parentWindow],	// Window to attach to
							  self,	// Modal delegate
							  @selector(importOverwriteWarningSheetDidEnd:returnCode:contextInfo:),	// Did end selector
							  (__bridge void *)(importFileName),	// Contextual info for selectors
							  NSLocalizedString(@"The chosen import file can potentially overwrite existing data. You should use caution when proceeding with the import.", @"message of warning when trying to import data when tables already exist."));

			return;
		}
		
		[self _startBackgroundImportTaskForFilename:importFileName];
	}];
}

/**
 * Alert sheet callback method - invoked when the error sheet is closed.
 */
- (void)importOverwriteWarningSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(NSString *)importFileName
{
	if (returnCode == NSAlertDefaultReturn && importFileName != nil) {
		// Begin the import process
		[self _startBackgroundImportTaskForFilename:importFileName];
	};
}

/**
 * Invoked when the user opens a large file, and when warned, chooses "Import".
 */
- (void)startSQLImportProcessWithFile:(NSString *)filename
{
	[importFormatPopup selectItemWithTitle:@"SQL"];
	[self _startBackgroundImportTaskForFilename:filename];
}

#pragma mark -
#pragma mark SQL import

/**
 * Streaming data processing method to import a supplied SQL file.
 *
 * The file is read in chunk by chunk; each chunk is then checked
 * for line endings, which are used to split the data into parts
 * which can be parsed to NSStrings in the appropriate encoding.
 *
 * The NSStrings are then fed to a SQL parser, which splits them
 * into statements ready to be executed.
 */
- (void)importSQLFile:(NSString *)filename
{
	SPLog(@"Starting import....");
	
//	TODO: this is slowwwwwwww
#ifdef DEBUG
	NSDate *startDate;
	NSDate *endDate;
	NSTimeInterval interval;
	startDate = [NSDate date];
#endif

	SPFileHandle *sqlFileHandle;
	NSMutableData *sqlDataBuffer;
	const unsigned char *sqlDataBufferBytes;
	NSData *fileChunk;
	NSString *sqlString;
	SPSQLParser *sqlParser;
	NSString *query;
	NSMutableString *errors = [NSMutableString string];
	NSInteger fileChunkMaxLength = 1024 * 1024;
	NSUInteger fileTotalLength = 0;
	NSUInteger fileProcessedLength = 0;
	NSInteger queriesPerformed = 0;
	NSInteger dataBufferLength = 0;
	NSInteger dataBufferPosition = 0;
	NSInteger dataBufferLastQueryEndPosition = 0;
	BOOL fileIsCompressed;
	BOOL allDataRead = NO;
	BOOL ignoreSQLErrors = ([[importSQLErrorHandlingPopup onMainThread] selectedTag] == SPSQLImportIgnoreErrors);
	BOOL ignoreCharsetError = NO;
	NSStringEncoding sqlEncoding = NSUTF8StringEncoding;
	NSString *connectionEncodingToRestore = nil;
	NSCharacterSet *whitespaceAndNewlineCharset = [NSCharacterSet whitespaceAndNewlineCharacterSet];

	// Open a filehandle for the SQL file
	sqlFileHandle = [SPFileHandle fileHandleForReadingAtPath:filename];
	if (!sqlFileHandle) {
		SPOnewayAlertSheet(
			NSLocalizedString(@"Import Error", @"Import Error title"),
			[tableDocumentInstance parentWindow],
			NSLocalizedString(@"The SQL file you selected could not be found or read.", @"SQL file open error")
		);
		if([filename hasPrefix:SPImportClipboardTempFileNamePrefix])
			[fileManager removeItemAtPath:filename error:nil];
		return;
	}
	fileIsCompressed = ([sqlFileHandle compressionFormat] != SPNoCompression);

	// Grab the file length
	fileTotalLength = (NSUInteger)[[[fileManager attributesOfItemAtPath:filename error:NULL] objectForKey:NSFileSize] longLongValue];
	if (!fileTotalLength) fileTotalLength = 1;

	SPMainQSync(^{
		// Reset progress interface
		[self->errorsView setString:@""];
		[self->singleProgressTitle setStringValue:NSLocalizedString(@"Importing SQL", @"text showing that the application is importing SQL")];
		[self->singleProgressText setStringValue:NSLocalizedString(@"Reading...", @"text showing that app is reading dump")];
		[self->singleProgressBar setIndeterminate:NO];
		[self->singleProgressBar setMaxValue:fileTotalLength];
		[self->singleProgressBar setUsesThreadedAnimation:YES];
		[self->singleProgressBar startAnimation:self];
		
		// Open the progress sheet
		[[self->tableDocumentInstance parentWindow] beginSheet:self->singleProgressSheet completionHandler:nil];
	});

	[tableDocumentInstance setQueryMode:SPImportExportQueryMode];

	// Determine the file encoding.  The first item in the encoding menu is "Autodetect"; if
	// this is selected, attempt to detect the encoding of the file
	if (![[importEncodingPopup onMainThread]indexOfSelectedItem]) {
	sqlEncoding = [fileManager detectEncodingforFileAtPath:filename];
		if ([SPMySQLConnection mySQLCharsetForStringEncoding:sqlEncoding]) {
			connectionEncodingToRestore = [mySQLConnection encoding];
			[mySQLConnection queryString:[NSString stringWithFormat:@"SET NAMES '%@'", [SPMySQLConnection mySQLCharsetForStringEncoding:sqlEncoding]]];
		}

	// Otherwise, get the encoding to use from the menu
	} else {
		sqlEncoding = [importEncodingPopup selectedTag];
	}

	//store the sqlMode to restore, if the import changes it
	NSString *sqlModeToRestore = nil;
	{
		// this query should work in ≥ 4.1.0 (which is also the first version that allows setting sql_mode at runtime)
		SPMySQLResult *res = [mySQLConnection queryString:@"SELECT @@sql_mode"];
		[res setReturnDataAsStrings:YES]; //TODO #2700: The framework misinterprets binary collation as binary data, so in order to be safe force it to use strings

		sqlModeToRestore = [[res getRowAsArray] objectAtIndex:0];
	}

	SPMySQLServerStatusBits serverStatus;
	// initialize
	serverStatus.noBackslashEscapes = 0; // for the moment we only care about that flag

	// Read in the file in a loop
	sqlParser = [[SPSQLParser alloc] init];
	[sqlParser setDelimiterSupport:YES];
	[mySQLConnection updateServerStatusBits:&serverStatus];
	[sqlParser setNoBackslashEscapes:serverStatus.noBackslashEscapes];
	sqlDataBuffer = [[NSMutableData alloc] init];
	while (1) {
		if (progressCancelled) break;

		@try {
			fileChunk = [sqlFileHandle readDataOfLength:fileChunkMaxLength];
		}
		// Report file read errors, and bail
		@catch (NSException *exception) {
			if (connectionEncodingToRestore) {
				[mySQLConnection queryString:[NSString stringWithFormat:@"SET NAMES '%@'", connectionEncodingToRestore]];
			}
			if (sqlModeToRestore) {
				[mySQLConnection queryString:[NSString stringWithFormat:@"SET SQL_MODE=%@", [sqlModeToRestore tickQuotedString]]];
			}

			[self _closeAndStopProgressSheet];

			SPOnewayAlertSheet(
				SP_FILE_READ_ERROR_STRING,
				[tableDocumentInstance parentWindow],
				[NSString stringWithFormat:NSLocalizedString(@"An error occurred when reading the file.\n\nOnly %ld queries were executed.\n\n(%@)", @"SQL read error, including detail from system"), (long)queriesPerformed, [exception reason]]
			);
			[tableDocumentInstance setQueryMode:SPInterfaceQueryMode];
			if([filename hasPrefix:SPImportClipboardTempFileNamePrefix]) [fileManager removeItemAtPath:filename error:nil];
			return;
		}

		// If no data returned, end of file - set a marker to ensure full processing
		if (!fileChunk || ![fileChunk length]) {
			allDataRead = YES;

		// Otherwise add the data to the read/parse buffer
		} else {
			[sqlDataBuffer appendData:fileChunk];
		}

		// Step through the data buffer, identifying line endings to parse the data with
		sqlDataBufferBytes = [sqlDataBuffer bytes];
		dataBufferLength = [sqlDataBuffer length];
		for ( ; dataBufferPosition < dataBufferLength || allDataRead; dataBufferPosition++) {
			if (sqlDataBufferBytes[dataBufferPosition] == 0x0A || sqlDataBufferBytes[dataBufferPosition] == 0x0D || allDataRead) {

				// Keep reading through any other line endings
				while (dataBufferPosition + 1 < dataBufferLength
						&& (sqlDataBufferBytes[dataBufferPosition+1] == 0x0A
							|| sqlDataBufferBytes[dataBufferPosition+1] == 0x0D))
				{
					dataBufferPosition++;
				}

				// Try to generate a NSString with the resulting data
				sqlString = [[NSString alloc] initWithData:[sqlDataBuffer subdataWithRange:NSMakeRange(dataBufferLastQueryEndPosition, dataBufferPosition - dataBufferLastQueryEndPosition)]
				                                  encoding:sqlEncoding];
				if (!sqlString) {
					if (connectionEncodingToRestore) {
						[mySQLConnection queryString:[NSString stringWithFormat:@"SET NAMES '%@'", connectionEncodingToRestore]];
					}
					if (sqlModeToRestore) {
						[mySQLConnection queryString:[NSString stringWithFormat:@"SET SQL_MODE=%@", [sqlModeToRestore tickQuotedString]]];
					}

					[self _closeAndStopProgressSheet];

					NSString *displayEncoding;

					if (![[importEncodingPopup onMainThread] indexOfSelectedItem]) {
						displayEncoding = [NSString stringWithFormat:@"%@ - %@", [[importEncodingPopup onMainThread] titleOfSelectedItem], [NSString localizedNameOfStringEncoding:sqlEncoding]];
					} else {
						displayEncoding = [NSString localizedNameOfStringEncoding:sqlEncoding];
					}
					SPOnewayAlertSheet(
						SP_FILE_READ_ERROR_STRING,
						[tableDocumentInstance parentWindow],
						[NSString stringWithFormat:NSLocalizedString(@"An error occurred when reading the file, as it could not be read in the encoding you selected (%@).\n\nOnly %ld queries were executed.", @"SQL encoding read error"), displayEncoding, (long)queriesPerformed]
					);
					[tableDocumentInstance setQueryMode:SPInterfaceQueryMode];
					if([filename hasPrefix:SPImportClipboardTempFileNamePrefix]) [fileManager removeItemAtPath:filename error:nil];
					return;
				}

				// Add the NSString segment to the SQL parser and release it
				[sqlParser appendString:sqlString];

				if (allDataRead) break;

				// Increment the query end position marker
				dataBufferLastQueryEndPosition = dataBufferPosition;
			}
		}

		// Trim the data buffer if part of it was used
		if (dataBufferLastQueryEndPosition) {
			[sqlDataBuffer setData:[sqlDataBuffer subdataWithRange:NSMakeRange(dataBufferLastQueryEndPosition, dataBufferLength - dataBufferLastQueryEndPosition)]];
			dataBufferPosition -= dataBufferLastQueryEndPosition;
			dataBufferLastQueryEndPosition = 0;
		}

		// Before entering the following loop, check that we actually have a connection.
		// If not, check the connection if appropriate and then clean up and exit if appropriate.
		if (![mySQLConnection isConnected] && ([mySQLConnection userTriggeredDisconnect] || ![mySQLConnection checkConnection])) {
			if ([filename hasPrefix:SPImportClipboardTempFileNamePrefix]) [fileManager removeItemAtPath:filename error:nil];

			[self _closeAndStopProgressSheet];
			[errors appendString:NSLocalizedString(@"The connection to the server was lost during the import.  The import is only partially complete.", @"Connection lost during import error message")];
			[self showErrorSheetWithMessage:errors];

			return;
		}

		// Extract and process any complete SQL queries that can be found in the strings parsed so far
		while ((query = [sqlParser trimAndReturnStringToCharacter:';' trimmingInclusively:YES returningInclusively:NO])) {
			if (progressCancelled) break;
			fileProcessedLength += [query lengthOfBytesUsingEncoding:sqlEncoding] + 1;

			// Ensure whitespace is removed from both ends, and normalise if necessary.
			if ([sqlParser containsCarriageReturns]) {
				query = [SPSQLParser normaliseQueryForExecution:query];
			} else {
				query = [query stringByTrimmingCharactersInSet:whitespaceAndNewlineCharset];
			}

			// Skip blank or whitespace-only queries to avoid errors
			if (![query length]) continue;

			// Run the query
			[mySQLConnection queryString:query usingEncoding:sqlEncoding withResultType:SPMySQLResultAsResult];

			// in case the query was a "SET @@sql_mode = ...", the server_status may have changed
			if([mySQLConnection updateServerStatusBits:&serverStatus]) [sqlParser setNoBackslashEscapes:serverStatus.noBackslashEscapes];

			// Check for any errors
			if ([mySQLConnection queryErrored] && ![[mySQLConnection lastErrorMessage] isEqualToString:@"Query was empty"]) {
				[errors appendFormat:NSLocalizedString(@"[ERROR in query %ld] %@\n", @"error text when multiple custom query failed"), (long)(queriesPerformed+1), [mySQLConnection lastErrorMessage]];

				// if the error is about utf8mb4 not being supported by the server display a more helpful message.
				// Note: the same error will occur when doing CREATE TABLE... with utf8mb4.
				if([mySQLConnection lastErrorID] == 1115 /* ER_UNKNOWN_CHARACTER_SET */ && [[mySQLConnection lastErrorMessage] rangeOfString:@"utf8mb4" options:NSCaseInsensitiveSearch].location != NSNotFound && [query rangeOfString:@"SET NAMES" options:NSCaseInsensitiveSearch].location != NSNotFound) {
					if(!ignoreCharsetError) {
						__block NSInteger charsetErrorSheetReturnCode;

						SPMainQSync(^{
							NSAlert *charsetErrorAlert = [NSAlert alertWithMessageText:NSLocalizedString(@"Incompatible encoding in SQL file", @"sql import error message")
							                                             defaultButton:NSLocalizedString(@"Import Anyway", @"sql import : charset error alert : continue button")
							                                           alternateButton:NSLocalizedString(@"Cancel Import", @"sql import : charset error alert : cancel button")
							                                               otherButton:nil
							                                 informativeTextWithFormat:NSLocalizedString(@"The SQL file uses utf8mb4 encoding, but your MySQL version only supports the limited utf8 subset.\n\nYou can continue the import, but any non-BMP characters in the SQL file (eg. some typographic and scientific special characters, archaic CJK logograms, emojis) will be unrecoverably lost!", @"sql import : charset error alert : detail message")];
							[charsetErrorAlert setAlertStyle:NSAlertStyleWarning];
							charsetErrorSheetReturnCode = [charsetErrorAlert runModal];
						});

						switch (charsetErrorSheetReturnCode) {
							// don't display the message a second time
							case NSAlertDefaultReturn:
								ignoreCharsetError = YES;
								break;
							// Otherwise, stop
							default:
								[errors appendString:NSLocalizedString(@"Import cancelled!\n", @"import cancelled message")];
								progressCancelled = YES;
						}
					}
				}
				// If not set to ignore errors, ask what to do.  Use NSAlert rather than
				// SPBeginWaitingAlertSheet as there is already a modal sheet in progress.
				else if (!ignoreSQLErrors) {
					__block NSInteger sqlImportErrorSheetReturnCode;

					SPMainQSync(^{
						NSAlert *sqlErrorAlert = [NSAlert alertWithMessageText:NSLocalizedString(@"An error occurred while importing SQL", @"sql import error message")
						                                         defaultButton:NSLocalizedString(@"Continue", @"continue button")
						                                       alternateButton:NSLocalizedString(@"Ignore All Errors", @"ignore errors button")
						                                           otherButton:NSLocalizedString(@"Stop", @"stop button")
						                             informativeTextWithFormat:NSLocalizedString(@"[ERROR in query %ld] %@\n", @"error text when multiple custom query failed"), (long)(queriesPerformed+1), [self->mySQLConnection lastErrorMessage]];
						[sqlErrorAlert setAlertStyle:NSAlertStyleWarning];
						sqlImportErrorSheetReturnCode = [sqlErrorAlert runModal];
					});

					switch (sqlImportErrorSheetReturnCode) {
						// On "continue", no additional action is required
						case NSAlertDefaultReturn:
							break;
						// Ignore all future errors if asked to
						case NSAlertAlternateReturn:
							ignoreSQLErrors = YES;
							break;
						// Otherwise, stop
						default:
							[errors appendString:NSLocalizedString(@"Import cancelled!\n", @"import cancelled message")];
							progressCancelled = YES;
					}
				}
			}

			// Increment the processed queries count
			queriesPerformed++;
#ifdef DEBUG
			endDate = [NSDate date];
			interval = [endDate timeIntervalSinceDate:startDate];
			SPLog(@"JIMMY time taken: %@, for %ld queries", [NSString stringWithFormat:@"%.3f", interval], (long)queriesPerformed);
#endif
			// Update the progress bar
			if (fileIsCompressed) {
				[[singleProgressBar onMainThread] setDoubleValue:[sqlFileHandle realDataReadLength]];
				[[singleProgressText onMainThread] setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Imported %@ of SQL", @"SQL import progress text where total size is unknown"),
					[NSString stringForByteSize:fileProcessedLength]]];
			} else {
				[[singleProgressBar onMainThread] setDoubleValue:fileProcessedLength];
				[[singleProgressText onMainThread] setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Imported %@ of %@", @"SQL import progress text"),
					[NSString stringForByteSize:fileProcessedLength], [NSString stringForByteSize:fileTotalLength]]];
			}
		}

		// If all the data has been read, break out of the processing loop
		if (allDataRead) break;
	}

	// If any text remains in the SQL parser, it's an unterminated query - execute it.
	query = [sqlParser stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([query length] && !progressCancelled) {

		// Run the query
		[mySQLConnection queryString:query usingEncoding:sqlEncoding withResultType:SPMySQLResultAsResult];
		// we don't care for the server_status that is set AFTER the last query has been executed

		// Check for any errors
		if ([mySQLConnection queryErrored] && ![[mySQLConnection lastErrorMessage] isEqualToString:@"Query was empty"]) {
			[errors appendFormat:NSLocalizedString(@"[ERROR in query %ld] %@\n", @"error text when multiple custom query failed"), (long)(queriesPerformed+1), [mySQLConnection lastErrorMessage]];
		}

		// Increment the processed queries count
		queriesPerformed++;
	}

	// Clean up
	if (connectionEncodingToRestore) {
		[mySQLConnection queryString:[NSString stringWithFormat:@"SET NAMES '%@'", connectionEncodingToRestore]];
	}
	if (sqlModeToRestore) {
		[mySQLConnection queryString:[NSString stringWithFormat:@"SET SQL_MODE=%@", [sqlModeToRestore tickQuotedString]]];
	}
	[tableDocumentInstance setQueryMode:SPInterfaceQueryMode];
	if([filename hasPrefix:SPImportClipboardTempFileNamePrefix]) [fileManager removeItemAtPath:filename error:nil];

	// Close progress sheet
	[self _closeAndStopProgressSheet];

	// Display any errors
	if ([errors length]) {
		[self showErrorSheetWithMessage:errors];
	}

	// Update available databases
	[[tableDocumentInstance onMainThread] setDatabases:self];

	// Update current selected database
	[tableDocumentInstance refreshCurrentDatabase];

	// Update current database tables 
	[tablesListInstance updateTables:self];
	
	// Re-query the structure of all databases in the background
	[[tableDocumentInstance databaseStructureRetrieval] queryDbStructureInBackgroundWithUserInfo:@{@"forceUpdate" : @YES}];

	// Import finished notification
	NSUserNotification *notification = [[NSUserNotification alloc] init];
	notification.title = @"Import Finished";
	notification.informativeText=[NSString stringWithFormat:NSLocalizedString(@"Finished importing %@", @"description for finished importing notification"), [filename lastPathComponent]];
	notification.soundName = NSUserNotificationDefaultSoundName;

	[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];

#ifdef DEBUG
	endDate = [NSDate date];
	interval = [endDate timeIntervalSinceDate:startDate];
	SPLog(@"JIMMY total time taken: %@, for %ld queries", [NSString stringWithFormat:@"%.3f", interval], (long)queriesPerformed);
#endif

}

#pragma mark -
#pragma mark CSV import

/**
 * Streaming data processing method to import a supplied CSV file.
 *
 * The file is read in chunk by chunk; each chunk is then checked
 * for line endings, which are used to split the data into parts
 * which can be parsed to NSStrings in the appropriate encoding.
 *
 * The NSStrings are then fed to a CSV parser, which splits them
 * into arrays of rows/cells.  Once 100 have been read in, a field
 * mapping sheet is displayed to allow columns to be mapped to
 * fields in a table; the queries are then constructed for each of
 * the rows, and the rest of the file is processed.
 */
- (void)importCSVFile:(NSString *)filename
{
	SPFileHandle *csvFileHandle;
	NSMutableData *csvDataBuffer;
	const unsigned char *csvDataBufferBytes;
	NSData *fileChunk;
	NSString *csvString;
	SPCSVParser *csvParser;
	NSMutableString *query;
	NSMutableString *errors = [NSMutableString string];
	NSMutableString *insertBaseString = [NSMutableString string];
	NSMutableString *insertRemainingBaseString = [NSMutableString string];
	NSMutableArray *parsedRows = [[NSMutableArray alloc] init];
	NSMutableArray *parsePositions = [[NSMutableArray alloc] init];
	NSArray *csvRowArray;
	NSInteger fileChunkMaxLength = 256 * 1024;
	NSUInteger csvRowsPerQuery = 1000;
	NSUInteger csvRowsThisQuery;
	NSUInteger fileTotalLength = 0;
	BOOL fileIsCompressed;
	NSInteger rowsImported = 0;
	NSInteger dataBufferLength = 0;
	NSInteger dataBufferPosition = 0;
	NSInteger dataBufferLastQueryEndPosition = 0;
	NSUInteger i;
	BOOL allDataRead = NO;
	BOOL insertBaseStringHasEntries;
	__block NSStringEncoding csvEncoding;

	fieldMappingArray = nil;
	fieldMappingGlobalValueArray = nil;

	[geometryFields removeAllObjects];
	[geometryFieldsMapIndex removeAllIndexes];
	[bitFields removeAllObjects];
	[bitFieldsMapIndex removeAllIndexes];
	[nullableNumericFields removeAllObjects];
	[nullableNumericFieldsMapIndex removeAllIndexes];

	// Open a filehandle for the CSV file
	csvFileHandle = [SPFileHandle fileHandleForReadingAtPath:filename];
	
	if (!csvFileHandle) {
		SPOnewayAlertSheet(
			NSLocalizedString(@"Import Error", @"Import Error title"),
			[tableDocumentInstance parentWindow],
			NSLocalizedString(@"The CSV file you selected could not be found or read.", @"CSV file open error")
		);
		if([filename hasPrefix:SPImportClipboardTempFileNamePrefix])
			[fileManager removeItemAtPath:filename error:nil];
		return;
	}

	// Grab the file length and status
	fileTotalLength = (NSUInteger)[[[fileManager attributesOfItemAtPath:filename error:NULL] objectForKey:NSFileSize] longLongValue];
	if (!fileTotalLength) fileTotalLength = 1;
	fileIsCompressed = ([csvFileHandle compressionFormat] != SPNoCompression);

	// Reset progress interface
	SPMainQSync(^{
		[self->errorsView setString:@""];
		[self->singleProgressTitle setStringValue:NSLocalizedString(@"Importing CSV", @"text showing that the application is importing CSV")];
		[self->singleProgressText setStringValue:NSLocalizedString(@"Reading...", @"text showing that app is reading dump")];
		[self->singleProgressBar setIndeterminate:NO];
		[self->singleProgressBar setUsesThreadedAnimation:YES];
		[self->singleProgressBar startAnimation:self];
		
		// Open the progress sheet
		[[self->tableDocumentInstance parentWindow] beginSheet:self->singleProgressSheet completionHandler:nil];
	});

	[tableDocumentInstance setQueryMode:SPImportExportQueryMode];

	SPMainQSync(^{
		// Determine the file encoding.  The first item in the encoding menu is "Autodetect";
		if (![self->importEncodingPopup indexOfSelectedItem]) {
			csvEncoding = 0;
		}
		// Otherwise, get the encoding to use from the menu
		else {
			csvEncoding = [self->importEncodingPopup selectedTag];
		}
	});
	// if "Autodetect" is selected, attempt to detect the encoding of the file.
	if (!csvEncoding) {
		csvEncoding = [fileManager detectEncodingforFileAtPath:filename];
	}

	// Read in the file in a loop.  The loop actually needs to perform three tasks: read in
	// CSV data and parse them into row arrays; present the field mapping interface once it
	// has some data to show within the interface; and use the field mapping data to construct
	// and send queries to the server.  The loop is mainly to perform the first of these; the
	// other two must therefore be performed where possible.
	csvParser = [[SPCSVParser alloc] init];

	SPMainQSync(^{
		// Store settings in prefs
		[self->prefs setObject:[self->importFieldsEnclosedField stringValue] forKey:SPCSVImportFieldEnclosedBy];
		[self->prefs setObject:[self->importFieldsEscapedField stringValue] forKey:SPCSVImportFieldEscapeCharacter];
		[self->prefs setObject:[self->importLinesTerminatedField stringValue] forKey:SPCSVImportLineTerminator];
		[self->prefs setObject:[self->importFieldsTerminatedField stringValue] forKey:SPCSVImportFieldTerminator];
		[self->prefs   setBool:[self->importFieldNamesSwitch state] forKey:SPCSVImportFirstLineIsHeader];
		
		// Take CSV import setting from accessory view
		[csvParser setFieldTerminatorString:[self->importFieldsTerminatedField stringValue] convertDisplayStrings:YES];
		[csvParser  setLineTerminatorString:[self->importLinesTerminatedField stringValue] convertDisplayStrings:YES];
		[csvParser      setFieldQuoteString:[self->importFieldsEnclosedField stringValue] convertDisplayStrings:YES];
		if ([[self->importFieldsEscapedField stringValue] isEqualToString:@"\\ or \""]) {
			[csvParser setEscapeString:@"\\" convertDisplayStrings:NO];
		} else {
			[csvParser setEscapeString:[self->importFieldsEscapedField stringValue] convertDisplayStrings:YES];
			[csvParser setEscapeStringsAreMatchedStrictly:YES];
		}
		[csvParser setNullReplacementString:[self->prefs objectForKey:SPNullValue]];
	});

	csvDataBuffer = [[NSMutableData alloc] init];
	while (1) {
		if (progressCancelled) break;

		@try {
			fileChunk = [csvFileHandle readDataOfLength:fileChunkMaxLength];
		}

		// Report file read errors, and bail
		@catch (NSException *exception) {
			[self _closeAndStopProgressSheet];
			SPOnewayAlertSheet(
				SP_FILE_READ_ERROR_STRING,
				[tableDocumentInstance parentWindow],
				[NSString stringWithFormat:NSLocalizedString(@"An error occurred when reading the file.\n\nOnly %ld rows were imported.\n\n(%@)", @"CSV read error, including detail string from system"), (long)rowsImported, [exception reason]]
			);
			[tableDocumentInstance setQueryMode:SPInterfaceQueryMode];
			if([filename hasPrefix:SPImportClipboardTempFileNamePrefix])
				[fileManager removeItemAtPath:filename error:nil];
			return;
		}

		// If no data returned, end of file - set a marker to ensure full processing
		if (!fileChunk || ![fileChunk length]) {
			allDataRead = YES;

		// Otherwise add the data to the read/parse buffer
		} else {
			[csvDataBuffer appendData:fileChunk];
		}

		// Step through the data buffer, identifying line endings to parse the data with
		csvDataBufferBytes = [csvDataBuffer bytes];
		dataBufferLength = [csvDataBuffer length];
		for ( ; dataBufferPosition < dataBufferLength || allDataRead; dataBufferPosition++) {
			if (csvDataBufferBytes[dataBufferPosition] == 0x0A || csvDataBufferBytes[dataBufferPosition] == 0x0D || allDataRead) {
#warning This EOL detection logic will break for multibyte encodings (like UTF16)!
				// Keep reading through any other line endings
				while (dataBufferPosition + 1 < dataBufferLength
						&& (csvDataBufferBytes[dataBufferPosition+1] == 0x0A
							|| csvDataBufferBytes[dataBufferPosition+1] == 0x0D))
				{
					dataBufferPosition++;
				}

				// Try to generate a NSString with the resulting data
				csvString = [[NSString alloc] initWithData:[csvDataBuffer subdataWithRange:NSMakeRange(dataBufferLastQueryEndPosition, dataBufferPosition - dataBufferLastQueryEndPosition)] encoding:csvEncoding];
				if (!csvString) {
					[self _closeAndStopProgressSheet];
					SPMainQSync(^{
						NSString *displayEncoding;
						if (![self->importEncodingPopup indexOfSelectedItem]) {
							displayEncoding = [NSString stringWithFormat:@"%@ - %@", [self->importEncodingPopup titleOfSelectedItem], [NSString localizedNameOfStringEncoding:csvEncoding]];
						} else {
							displayEncoding = [NSString localizedNameOfStringEncoding:csvEncoding];
						}
						SPOnewayAlertSheet(
							SP_FILE_READ_ERROR_STRING,
							[self->tableDocumentInstance parentWindow],
							[NSString stringWithFormat:NSLocalizedString(@"An error occurred when reading the file, as it could not be read using the encoding you selected (%@).\n\nOnly %ld rows were imported.", @"CSV encoding read error"), displayEncoding, (long)rowsImported]
						);
					});
					[tableDocumentInstance setQueryMode:SPInterfaceQueryMode];
					if([filename hasPrefix:SPImportClipboardTempFileNamePrefix])
						[fileManager removeItemAtPath:filename error:nil];
					return;
				}

				// Add the NSString segment to the CSV parser and release it
				[csvParser appendString:csvString];

				if (allDataRead) break;

				// Increment the buffer end position marker
				dataBufferLastQueryEndPosition = dataBufferPosition;
			}
		}

		// Trim the data buffer if part of it was used
		if (dataBufferLastQueryEndPosition) {
			[csvDataBuffer setData:[csvDataBuffer subdataWithRange:NSMakeRange(dataBufferLastQueryEndPosition, dataBufferLength - dataBufferLastQueryEndPosition)]];
			dataBufferPosition -= dataBufferLastQueryEndPosition;
			dataBufferLastQueryEndPosition = 0;
		}

		// Extract and process any full CSV rows found so far.  Also trigger processing if all
		// rows have been read, in order to ensure short files are still processed.
		while ((csvRowArray = [csvParser getRowAsArrayAndTrimString:YES stringIsComplete:allDataRead]) || (allDataRead && [parsedRows count])) {

			// If valid, add the row array and length to local storage
			if (csvRowArray) {
				[parsedRows addObject:csvRowArray];
				[parsePositions addObject:@([csvParser totalLengthParsed])];
			}

			// If we have no field mapping array, and either the first hundred rows or all
			// the rows, request the field mapping from the user.
			if (!fieldMappingArray
				&& ([parsedRows count] >= 100 || (!csvRowArray && allDataRead)))
			{
				[self _closeAndStopProgressSheet];
				if (![self buildFieldMappingArrayWithData:parsedRows isPreview:!allDataRead ofSoureFile:filename]) {
					[tableDocumentInstance setQueryMode:SPInterfaceQueryMode];
					if([filename hasPrefix:SPImportClipboardTempFileNamePrefix])
						[fileManager removeItemAtPath:filename error:nil];
					return;
				}

				// Reset progress interface and open the progress sheet
				SPMainQSync(^{
					[self->singleProgressBar setMaxValue:fileTotalLength];
					[self->singleProgressBar setIndeterminate:NO];
					[self->singleProgressBar startAnimation:self];
					[[self->tableDocumentInstance parentWindow] beginSheet:self->singleProgressSheet completionHandler:nil];
				});

				// Set up index sets for use during row enumeration
				for (i = 0; i < [fieldMappingArray count]; i++) {
					if ([NSArrayObjectAtIndex(fieldMapperOperator, i) integerValue] == 0) {
						NSString *fieldName = NSArrayObjectAtIndex(fieldMappingTableColumnNames, i);
						if ([nullableNumericFields containsObject:fieldName]) {
							[nullableNumericFieldsMapIndex addIndex:i];
						}
					}
				}
				
				// Set up the field names import string for INSERT or REPLACE INTO
				[insertBaseString appendString:csvImportHeaderString];
				if(!importMethodIsUpdate) {
					NSString *fieldName;
					[insertBaseString appendFormat:@"%@ (", [selectedTableTarget backtickQuotedString]];
					insertBaseStringHasEntries = NO;
					for (i = 0; i < [fieldMappingArray count]; i++) {
						if ([NSArrayObjectAtIndex(fieldMapperOperator, i) integerValue] == 0) {
							if (insertBaseStringHasEntries)
								[insertBaseString appendString:@","];
							else
								insertBaseStringHasEntries = YES;
							if([geometryFields count]) {
								// Store column index for each geometry field to be able to apply ST_GeomFromText() while importing
								if([geometryFields containsObject:fieldName = NSArrayObjectAtIndex(fieldMappingTableColumnNames, i) ])
									[geometryFieldsMapIndex addIndex:i];
								[insertBaseString appendString:[fieldName backtickQuotedString]];
							} else if([bitFields count]) {
								// Store column index for each bit field to be able to wrap it into b'…' while importing
								if([bitFields containsObject:fieldName = NSArrayObjectAtIndex(fieldMappingTableColumnNames, i) ])
									[bitFieldsMapIndex addIndex:i];
								[insertBaseString appendString:[fieldName backtickQuotedString]];
							} else {
								[insertBaseString appendString:[NSArrayObjectAtIndex(fieldMappingTableColumnNames, i) backtickQuotedString]];
							}
						}
					}
					[insertBaseString appendString:@") VALUES\n"];
				}

				// Remove the header row from the data set if appropriate
				if ([[importFieldNamesSwitch onMainThread] state] == NSOnState) {
					[parsedRows removeObjectAtIndex:0];
					[parsePositions removeObjectAtIndex:0];
				}
			}
			if (!fieldMappingArray) continue;
			
			// Before entering the following loop, check that we actually have a connection.
			// If not, check the connection if appropriate and then clean up and exit if appropriate.
			if (![mySQLConnection isConnected] && ([mySQLConnection userTriggeredDisconnect] || ![mySQLConnection checkConnection])) {
				[self _closeAndStopProgressSheet];
				[tableDocumentInstance setQueryMode:SPInterfaceQueryMode];
				if([filename hasPrefix:SPImportClipboardTempFileNamePrefix])
					[fileManager removeItemAtPath:filename error:nil];
				return;
			}

			// If we have more than the csvRowsPerQuery amount, or if we're at the end of the
			// available data, construct and run a query.
			while ([parsedRows count] >= csvRowsPerQuery
					|| (!csvRowArray && allDataRead && [parsedRows count]))
			{
				if (progressCancelled) break;
				csvRowsThisQuery = 0;
				if(!importMethodIsUpdate) {
					query = [[NSMutableString alloc] initWithString:insertBaseString];
					for (i = 0; i < csvRowsPerQuery && i < [parsedRows count]; i++) {
						if (i > 0) [query appendString:@",\n"];
						[query appendString:[[self mappedValueStringForRowArray:[parsedRows objectAtIndex:i]] description]];
						csvRowsThisQuery++;
						if ([query length] > 250000) break;
					}

					// Perform the query
					if(csvImportMethodHasTail)
						[mySQLConnection queryString:[NSString stringWithFormat:@"%@ %@", query, csvImportTailString]];
					else
						[mySQLConnection queryString:query];
				} else {
					if(insertRemainingRowsAfterUpdate) {
						[insertRemainingBaseString setString:@"INSERT INTO "];
						[insertRemainingBaseString appendFormat:@"%@ (", [selectedTableTarget backtickQuotedString]];
						insertBaseStringHasEntries = NO;
						for (i = 0; i < [fieldMappingArray count]; i++) {
							if ([NSArrayObjectAtIndex(fieldMapperOperator, i) integerValue] == 0) {
								if (insertBaseStringHasEntries) [insertRemainingBaseString appendString:@","];
								else insertBaseStringHasEntries = YES;
								[insertRemainingBaseString appendString:[NSArrayObjectAtIndex(fieldMappingTableColumnNames, i) backtickQuotedString]];
							}
						}
						[insertRemainingBaseString appendString:@") VALUES\n"];
					}
					for (i = 0; i < [parsedRows count]; i++) {
						if (progressCancelled) break;

						query = [[NSMutableString alloc] initWithString:insertBaseString];
						[query appendString:[self mappedUpdateSetStatementStringForRowArray:[parsedRows objectAtIndex:i]]];

						// Perform the query
						if(csvImportMethodHasTail)
							[mySQLConnection queryString:[NSString stringWithFormat:@"%@ %@", query, csvImportTailString]];
						else
							[mySQLConnection queryString:query];

						if ([mySQLConnection queryErrored]) {
							[[tableDocumentInstance onMainThread] showConsole:nil];
							[errors appendFormat:
								NSLocalizedString(@"[ERROR in row %ld] %@\n", @"error text when reading of csv file gave errors"),
								(long)(rowsImported+1),[mySQLConnection lastErrorMessage]];
							
							if(user_defaults_get_bool_ud(SPConsoleEnableImportExportLogging, prefs) == YES){
								[[SPQueryController sharedQueryController] showErrorInConsole:mySQLConnection.lastErrorMessage connection:mySQLConnection.host database:mySQLConnection.database];
							}
						}

						if ( insertRemainingRowsAfterUpdate && ![mySQLConnection rowsAffectedByLastQuery]) {
							query = [[NSMutableString alloc] initWithString:insertRemainingBaseString];
							[query appendString:[self mappedValueStringForRowArray:[parsedRows objectAtIndex:i]]];

							// Perform the query
							if(csvImportMethodHasTail)
								[mySQLConnection queryString:[NSString stringWithFormat:@"%@ %@", query, csvImportTailString]];
							else
								[mySQLConnection queryString:query];

							if ([mySQLConnection queryErrored]) {
								[errors appendFormat:
									NSLocalizedString(@"[ERROR in row %ld] %@\n", @"error text when reading of csv file gave errors"),
									(long)(rowsImported+1),[mySQLConnection lastErrorMessage]];
							}
						}

						rowsImported++;
						csvRowsThisQuery++;
#warning Updating the UI for every single row is likely a performance killer (even without synchronization).
						SPMainQSync(^{
							if (fileIsCompressed) {
								[self->singleProgressBar setDoubleValue:[csvFileHandle realDataReadLength]];
								[self->singleProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Imported %@ of CSV data", @"CSV import progress text where total size is unknown"), [NSString stringForByteSize:[[parsePositions objectAtIndex:i] longValue]]]];
							} else {
								[self->singleProgressBar setDoubleValue:[[parsePositions objectAtIndex:i] doubleValue]];
								[self->singleProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Imported %@ of %@", @"CSV import progress text"), [NSString stringForByteSize:[[parsePositions objectAtIndex:i] longValue]], [NSString stringForByteSize:fileTotalLength]]];
							}
						});
					}
				}

				// If an error occurred, run the queries individually to get exact line errors
				if (!importMethodIsUpdate && [mySQLConnection queryErrored]) {
					[[tableDocumentInstance onMainThread] showConsole:nil];
					if(user_defaults_get_bool_ud(SPConsoleEnableImportExportLogging, prefs) == YES){
						[[SPQueryController sharedQueryController] showErrorInConsole:mySQLConnection.lastErrorMessage connection:mySQLConnection.host database:mySQLConnection.database];
					}
					for (i = 0; i < csvRowsThisQuery; i++) {
						if (progressCancelled) break;
						query = [[NSMutableString alloc] initWithString:insertBaseString];
						[query appendString:[self mappedValueStringForRowArray:[parsedRows objectAtIndex:i]]];

						// Perform the query
						if(csvImportMethodHasTail)
							[mySQLConnection queryString:[NSString stringWithFormat:@"%@ %@", query, csvImportTailString]];
						else
							[mySQLConnection queryString:query];

						if ([mySQLConnection queryErrored]) {
							[errors appendFormat:
								NSLocalizedString(@"[ERROR in row %ld] %@\n", @"error text when reading of csv file gave errors"),
								(long)(rowsImported+1),[mySQLConnection lastErrorMessage]];
							if(user_defaults_get_bool_ud(SPConsoleEnableImportExportLogging, prefs) == YES){
								[[SPQueryController sharedQueryController] showErrorInConsole:mySQLConnection.lastErrorMessage connection:mySQLConnection.host database:mySQLConnection.database];
							}
						}
#warning duplicate code (see above)
						rowsImported++;
						SPMainQSync(^{
							if (fileIsCompressed) {
								[self->singleProgressBar setDoubleValue:[csvFileHandle realDataReadLength]];
								[self->singleProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Imported %@ of CSV data", @"CSV import progress text where total size is unknown"), [NSString stringForByteSize:[[parsePositions objectAtIndex:i] longValue]]]];
							} else {
								[self->singleProgressBar setDoubleValue:[[parsePositions objectAtIndex:i] doubleValue]];
								[self->singleProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Imported %@ of %@", @"SQL import progress text"), [NSString stringForByteSize:[[parsePositions objectAtIndex:i] longValue]], [NSString stringForByteSize:fileTotalLength]]];
							}
						});
					}
				} else {
					rowsImported += csvRowsThisQuery;
#warning duplicate code (see above)
					SPMainQSync(^{
						if (fileIsCompressed) {
							[self->singleProgressBar setDoubleValue:[csvFileHandle realDataReadLength]];
							[self->singleProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Imported %@ of CSV data", @"CSV import progress text where total size is unknown"), [NSString stringForByteSize:[[parsePositions objectAtIndex:csvRowsThisQuery-1] longValue]]]];
						} else {
							[self->singleProgressBar setDoubleValue:[[parsePositions objectAtIndex:csvRowsThisQuery-1] doubleValue]];
							[self->singleProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Imported %@ of %@", @"SQL import progress text"), [NSString stringForByteSize:[[parsePositions objectAtIndex:csvRowsThisQuery-1] longValue]], [NSString stringForByteSize:fileTotalLength]]];
						}
					});
				}

				// Update the arrays
				[parsedRows removeObjectsInRange:NSMakeRange(0, csvRowsThisQuery)];
				[parsePositions removeObjectsInRange:NSMakeRange(0, csvRowsThisQuery)];
			}
		}
		
		// If all the data has been read, break out of the processing loop
		if (allDataRead) break;
	}

	// Clean up
	[tableDocumentInstance setQueryMode:SPInterfaceQueryMode];
	if([filename hasPrefix:SPImportClipboardTempFileNamePrefix])
		[fileManager removeItemAtPath:filename error:nil];

	// Close progress sheet
	[self _closeAndStopProgressSheet];

	// Display any errors
	if ([errors length]) {
		[self showErrorSheetWithMessage:errors];
	}
	
	// Import finished notification
	NSUserNotification *notification = [[NSUserNotification alloc] init];
	notification.title = @"Import Finished";
	notification.informativeText=[NSString stringWithFormat:NSLocalizedString(@"Finished importing %@", @"description for finished importing notification"), [filename lastPathComponent]];
	notification.soundName = NSUserNotificationDefaultSoundName;

	[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];

	SPMainQSync(^{

		if(self->importIntoNewTable) {

			// Select the new table
			
			// Update current database tables
			[self->tablesListInstance updateTables:self];
			
			// Re-query the structure of all databases in the background
			[[self->tableDocumentInstance databaseStructureRetrieval] queryDbStructureInBackgroundWithUserInfo:@{@"forceUpdate" : @YES}];
			
			// Select the new table
			[self->tablesListInstance selectItemWithName:self->selectedTableTarget];
			
		} else {
			
			// If import was done into a new table or the table selected for import is also selected in the content view,
			// update the content view - on the main thread to avoid crashes.
			if ([self->tablesListInstance tableName] && [self->selectedTableTarget isEqualToString:[self->tablesListInstance tableName]]) {
				[self->tableDocumentInstance setContentRequiresReload:YES];
			}
			
		}
	});

}

/**
 * Sets up the field mapping array, and asks the user to provide a field mapping to an
 * appropriate table; on success, constructs the field mapping array into the global variable,
 * and returns true.  On failure, displays error messages itself, and returns false.
 * Takes an array of data to show when selecting the field mapping, and an indicator of whether
 * that dataset is complete or a preview of the full data set.
 */
- (BOOL) buildFieldMappingArrayWithData:(NSArray *)importData isPreview:(BOOL)dataIsPreviewData ofSoureFile:(NSString*)filename
{

	// Ensure data was provided, or alert than an import error occurred and return false.
	if (![importData count]) {
		[self _closeAndStopProgressSheet];
		SPOnewayAlertSheet(
			NSLocalizedString(@"Error", @"error"),
			[tableDocumentInstance parentWindow],
			NSLocalizedString(@"Could not parse file as CSV", @"Error when we can't parse/split file as CSV")
		);
		return YES;
	}

	// Sanity check the first row of the CSV to prevent hang loops caused by wrong line ending entry
	if ([[importData objectAtIndex:0] count] > 512) {
		[self _closeAndStopProgressSheet];
		SPOnewayAlertSheet(
			NSLocalizedString(@"Error", @"error"),
			[tableDocumentInstance parentWindow],
			NSLocalizedString(@"The CSV was read as containing more than 512 columns, more than the maximum columns permitted for speed reasons by Sequel Ace.\n\nThis usually happens due to errors reading the CSV; please double-check the CSV to be imported and the line endings and escape characters at the bottom of the CSV selection dialog.", @"Error when CSV appears to have too many columns to import, probably due to line ending mismatch")
		);
		return NO;
	}
	fieldMappingImportArrayIsPreview = dataIsPreviewData;

	// Set the import array
	fieldMappingImportArray = [[NSArray alloc] initWithArray:importData];
	numberOfImportDataColumns = [[importData objectAtIndex:0] count];

	fieldMapperSheetStatus = SPFieldMapperInProgress;
	fieldMappingArrayHasGlobalVariables = NO;

	//the field mapper is an UI object and must not be caught in the background thread's autoreleasepool
	__block SPFieldMapperController *fieldMapperController = nil;
	dispatch_async(dispatch_get_main_queue(), ^{
		// Init the field mapper controller
		fieldMapperController = [[SPFieldMapperController alloc] initWithDelegate:self];
		[fieldMapperController setConnection:self->mySQLConnection];
		[fieldMapperController setSourcePath:filename];
		[fieldMapperController setImportDataArray:self->fieldMappingImportArray hasHeader:[self->importFieldNamesSwitch state] isPreview:self->fieldMappingImportArrayIsPreview];
		
		// Show field mapper sheet and set the focus to it
		[[self->tableDocumentInstance parentWindow] beginSheet:[fieldMapperController window] completionHandler:^(NSModalResponse returnCode) {
			self->fieldMapperSheetStatus = (returnCode) ? SPFieldMapperCompleted : SPFieldMapperCancelled;
		}];
	});

	// Wait for field mapper sheet
	while (fieldMapperSheetStatus == SPFieldMapperInProgress)
		usleep(100000);
	
	BOOL success = NO;

	// If the mapping was cancelled, abort the import
	if (fieldMapperSheetStatus == SPFieldMapperCancelled) {
		return success;
	}

	// Get mapping settings and preset some global variables
	SPMainQSync(^{
		self->fieldMapperOperator                 = [NSArray arrayWithArray:[fieldMapperController fieldMapperOperator]];
		self->fieldMappingArray                   = [NSArray arrayWithArray:[fieldMapperController fieldMappingArray]];
		self->selectedTableTarget                 = [NSString stringWithString:[fieldMapperController selectedTableTarget]];
		self->selectedImportMethod                = [NSString stringWithString:[fieldMapperController selectedImportMethod]];
		self->fieldMappingTableColumnNames        = [NSArray arrayWithArray:[fieldMapperController fieldMappingTableColumnNames]];
		self->fieldMappingGlobalValueArray        = [NSArray arrayWithArray:[fieldMapperController fieldMappingGlobalValueArray]];
		self->fieldMappingTableDefaultValues      = [NSArray arrayWithArray:[fieldMapperController fieldMappingTableDefaultValues]];
		self->csvImportHeaderString               = [NSString stringWithString:[fieldMapperController importHeaderString]];
		self->csvImportTailString                 = [NSString stringWithString:[fieldMapperController onupdateString]];
		self->importIntoNewTable                  = [fieldMapperController importIntoNewTable];
		self->fieldMappingArrayHasGlobalVariables = [fieldMapperController globalValuesInUsage];
		self->insertRemainingRowsAfterUpdate      = [fieldMapperController insertRemainingRowsAfterUpdate];
	});
	csvImportMethodHasTail = ([csvImportTailString length] == 0) ? NO : YES;
	importMethodIsUpdate = ([selectedImportMethod isEqualToString:@"UPDATE"]) ? YES : NO;

	// Error checking
	if(    ![fieldMapperOperator count] 
		|| ![fieldMappingArray count] 
		|| ![selectedImportMethod length] 
		|| ![selectedTableTarget length]
		|| ![csvImportHeaderString length])
	{
		NSBeep();
		return success;
	}

	// Store target table definitions
	SPTableData *selectedTableData = [[SPTableData alloc] init];
	[selectedTableData setConnection:mySQLConnection];
	NSDictionary *targetTableDetails = [selectedTableData informationForTable:selectedTableTarget];

	// Store all field names which are of typegrouping 'geometry' and 'bit', and check if
	// numeric columns can hold NULL values to map empty strings to.
	for(NSDictionary *field in [targetTableDetails objectForKey:@"columns"]) {
		if([[field objectForKey:@"typegrouping"] isEqualToString:@"geometry"])
			[geometryFields addObject:[field objectForKey:@"name"]];
		if([[field objectForKey:@"typegrouping"] isEqualToString:@"bit"])
			[bitFields addObject:[field objectForKey:@"name"]];
		if(([[field objectForKey:@"typegrouping"] isEqualToString:@"float"] || [[field objectForKey:@"typegrouping"] isEqualToString:@"integer"]) && [[field objectForKey:@"null"] boolValue])
			[nullableNumericFields addObject:[field objectForKey:@"name"]];
	}

	SPMainQSync(^{
		[self->importFieldNamesSwitch setState:[fieldMapperController importFieldNamesHeader]];
		[self->prefs setBool:[self->importFieldNamesSwitch state] forKey:SPCSVImportFirstLineIsHeader];
	});
	success = YES;
	return success;
}

/**
 * Construct the SET and WHERE clause for a CSV row, based on the field mapping array 
 * for the import method "UPDATE".
 */
- (NSString *)mappedUpdateSetStatementStringForRowArray:(NSArray *)csvRowArray
{

	NSMutableString *setString = [NSMutableString stringWithString:@""];
	NSMutableString *whereString = [NSMutableString stringWithString:@"WHERE "];

	NSInteger i;
	NSInteger mapColumn;
	id cellData;
	NSInteger mappingArrayCount = [fieldMappingArray count];
	NSString *re = @"(?<!\\\\)\\$(\\d+)";

	for (i = 0; i < mappingArrayCount; i++) {

		// Skip unmapped columns
		if ([NSArrayObjectAtIndex(fieldMapperOperator, i) integerValue] == 1 ) continue;

		mapColumn = [NSArrayObjectAtIndex(fieldMappingArray, i) integerValue];

		// SET clause
		if ([NSArrayObjectAtIndex(fieldMapperOperator, i) integerValue] == 0 ) {
			if ([setString length] > 1) [setString appendString:@","];
			[setString appendString:[NSArrayObjectAtIndex(fieldMappingTableColumnNames, i) backtickQuotedString]];
			[setString appendString:@"="];
			// Append the data
			// - check for global values
			if(fieldMappingArrayHasGlobalVariables && mapColumn >= numberOfImportDataColumns) {
				NSMutableString *globalVar = [NSMutableString string];
				id insertItem = NSArrayObjectAtIndex(fieldMappingGlobalValueArray, mapColumn);
				if([insertItem isNSNull]) {
					[globalVar setString:@"NULL"];
				} else if([insertItem isSPNotLoaded]) {
					[globalVar setString:@"NULL"];
				} else {
					[globalVar setString:insertItem];
					// Global variables are coming wrapped in ' ' if there're not marked as SQL.
					// If global variable contains column placeholders $1 etc. replace them.
					if([globalVar rangeOfString:@"$"].length && [globalVar isMatchedByRegex:re]) {
						while([globalVar isMatchedByRegex:re]) {
							[globalVar flushCachedRegexData];
							NSRange aRange = [globalVar rangeOfRegex:re capture:0L];
							NSInteger colIndex = [[globalVar substringWithRange:[globalVar rangeOfRegex:re capture:1L]] integerValue];
							if (colIndex > 0 && colIndex <= (NSInteger)[csvRowArray count]) {
								id colStr = NSArrayObjectAtIndex(csvRowArray, colIndex-1);
								if([colStr isNSNull])
									[globalVar replaceCharactersInRange:aRange withString:@"NULL"];
								else if([colStr isSPNotLoaded])
									[globalVar replaceCharactersInRange:aRange withString:@""];
								else
									[globalVar replaceCharactersInRange:aRange withString:[NSString stringWithFormat:@"'%@'", [(NSString*)colStr stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]]];
							} else {
								[globalVar replaceCharactersInRange:aRange withString:@"GLOBAL_SQL_EXPRESSION_ERROR"];
							}
						}
					}
				}
				[setString appendString:globalVar];
			} else {
				cellData = NSArrayObjectAtIndex(csvRowArray, mapColumn);

				// If import column isn't specified import the table column default value
				if ([cellData isSPNotLoaded])
					cellData = NSArrayObjectAtIndex(fieldMappingTableDefaultValues, i);

				if ([cellData isNSNull]) {
					[setString appendString:@"NULL"];
				} else {
					[setString appendString:[mySQLConnection escapeAndQuoteString:cellData]];
				}
			}
		}
		// WHERE clause
		else if ([NSArrayObjectAtIndex(fieldMapperOperator, i) integerValue] == 2 )
		{
			if ([whereString length] > 7) [whereString appendString:@" AND "];
			[whereString appendString:[NSArrayObjectAtIndex(fieldMappingTableColumnNames, i) backtickQuotedString]];
			// Append the data
			// - check for global values
			if(fieldMappingArrayHasGlobalVariables && mapColumn >= numberOfImportDataColumns) {
				NSMutableString *globalVar = [NSMutableString string];
				id insertItem = NSArrayObjectAtIndex(fieldMappingGlobalValueArray, mapColumn);
				if([insertItem isNSNull]) {
					[globalVar setString:@"NULL"];
				} else if([insertItem isSPNotLoaded]) {
					[globalVar setString:@"NULL"];
				} else {
					[globalVar setString:insertItem];
					// Global variables are coming wrapped in ' ' if there're not marked as SQL.
					// If global variable contains column placeholders $1 etc. replace them.
					if([globalVar rangeOfString:@"$"].length && [globalVar isMatchedByRegex:re]) {
						while([globalVar isMatchedByRegex:re]) {
							[globalVar flushCachedRegexData];
							NSRange aRange = [globalVar rangeOfRegex:re capture:0L];
							NSInteger colIndex = [[globalVar substringWithRange:[globalVar rangeOfRegex:re capture:1L]] integerValue];
							if(colIndex > 0 && colIndex <= (NSInteger)[csvRowArray count]) {
								id colStr = NSArrayObjectAtIndex(csvRowArray, colIndex-1);
								if([colStr isNSNull])
									[globalVar replaceCharactersInRange:aRange withString:@"NULL"];
								else if([colStr isSPNotLoaded])
									[globalVar replaceCharactersInRange:aRange withString:@""];
								else
									[globalVar replaceCharactersInRange:aRange withString:[NSString stringWithFormat:@"'%@'", [(NSString*)colStr stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]]];
							} else {
								[globalVar replaceCharactersInRange:aRange withString:@"GLOBAL_SQL_EXPRESSION_ERROR"];
							}
						}
					}
				}
				[whereString appendFormat:@"=%@", globalVar];
			} else {
				cellData = NSArrayObjectAtIndex(csvRowArray, mapColumn);

				// If import column isn't specified import the table column default value
				if ([cellData isSPNotLoaded])
					cellData = NSArrayObjectAtIndex(fieldMappingTableDefaultValues, i);

				if ([cellData isNSNull]) {
					[whereString appendString:@" IS NULL"];
				} else {
					[whereString appendString:@"="];
					[whereString appendString:[mySQLConnection escapeAndQuoteString:cellData]];
				}
			}
		}
	}
	
	return [NSString stringWithFormat:@"%@ %@", setString, whereString];
}

/**
 * Construct the VALUES string for a CSV row, based on the field mapping array - including
 * surrounding brackets but not including the VALUES keyword.
 */
- (NSString *)mappedValueStringForRowArray:(NSArray *)csvRowArray
{
	NSMutableString *valueString = [NSMutableString stringWithString:@"("];
	NSInteger i;
	NSInteger mapColumn;
	id cellData;
	NSInteger mappingArrayCount = [fieldMappingArray count];
	NSString *re = @"(?<!\\\\)\\$(\\d+)";

	for (i = 0; i < mappingArrayCount; i++) {

		// Skip unmapped columns
		if ([NSArrayObjectAtIndex(fieldMapperOperator, i) integerValue] > 0) continue;

		mapColumn = [NSArrayObjectAtIndex(fieldMappingArray, i) integerValue];

		if ([valueString length] > 1) [valueString appendString:@","];

		// Append the data
		// - check for global values
		if(fieldMappingArrayHasGlobalVariables && mapColumn >= numberOfImportDataColumns) {
			NSMutableString *globalVar = [NSMutableString string];
			id insertItem = NSArrayObjectAtIndex(fieldMappingGlobalValueArray, mapColumn);
			if([insertItem isNSNull]) {
				[globalVar setString:@"NULL"];
			} else if([insertItem isSPNotLoaded]) {
				[globalVar setString:@"NULL"];
			} else {
				[globalVar setString:insertItem];
				// Global variables are coming wrapped in ' ' if there're not marked as SQL.
				// If global variable contains column placeholders $1 etc. replace them by escaped 'csv content' or NULL.
				if([globalVar rangeOfString:@"$"].length && [globalVar isMatchedByRegex:re]) {
					while([globalVar isMatchedByRegex:re]) {
						[globalVar flushCachedRegexData];
						NSRange aRange = [globalVar rangeOfRegex:re capture:0L];
						NSInteger colIndex = [[globalVar substringWithRange:[globalVar rangeOfRegex:re capture:1L]] integerValue];
						if(colIndex > 0 && colIndex <= (NSInteger)[csvRowArray count]) {
							id colStr = NSArrayObjectAtIndex(csvRowArray, colIndex-1);
							if([colStr isNSNull])
								[globalVar replaceCharactersInRange:aRange withString:@"NULL"];
							else if([colStr isSPNotLoaded])
								[globalVar replaceCharactersInRange:aRange withString:@""];
							else
								[globalVar replaceCharactersInRange:aRange withString:[NSString stringWithFormat:@"'%@'", [(NSString*)colStr stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]]];
						} else {
							[globalVar replaceCharactersInRange:aRange withString:@"GLOBAL_SQL_EXPRESSION_ERROR"];
						}
					}
				}
			}
			[valueString appendString:globalVar];
		} else {
			cellData = NSArrayObjectAtIndex(csvRowArray, mapColumn);

			// If import column isn't specified import the table column default value
			if ([cellData isSPNotLoaded])
				cellData = NSArrayObjectAtIndex(fieldMappingTableDefaultValues, i);

			// Insert a NULL if the cell is an NSNull, or is a nullable numeric field and empty
			if ([cellData isNSNull] || ([nullableNumericFieldsMapIndex containsIndex:i] && [[cellData description] isEqualToString:@""])) {
				[valueString appendString:@"NULL"];

			} else {
				// Apply ST_GeomFromText() for each geometry field
				if([geometryFields count] && [geometryFieldsMapIndex containsIndex:i]) {
					[valueString appendString:[(NSString*)cellData getGeomFromTextString]];
				} else if([bitFields count] && [bitFieldsMapIndex containsIndex:i]) {
					[valueString appendString:@"b"];
					[valueString appendString:[mySQLConnection escapeAndQuoteString:cellData]];
				} else {
					[valueString appendString:[mySQLConnection escapeAndQuoteString:cellData]];
				}
			}
		}
	}

	[valueString appendString:@")"];
	
	return valueString;
}

#pragma mark -
#pragma mark Import delegate notifications

/**
 * Called when the selection within an open/save panel changes.
 */
- (void)panelSelectionDidChange:(NSOpenPanel *)sender
{
	NSArray *selectedUrls = sender.URLs;

	// If a single file is selected and the extension is recognised, change the format dropdown automatically
	if (selectedUrls.count != 1) return;

	NSString *pathExtension = [[selectedUrls[0] pathExtension] uppercaseString];

	// If the file has an extension '.gz' or '.bz2' indicating gzip or bzip2 compression, fetch the next extension
	if ([pathExtension isEqualToString:@"GZ"] || [pathExtension isEqualToString:@"BZ2"]) {
		NSMutableString *pathString = [NSMutableString stringWithString:[selectedUrls[0] path]];
		
		BOOL isGzip = [pathExtension isEqualToString:@"GZ"];
		
		[pathString deleteCharactersInRange:NSMakeRange([pathString length] - (isGzip ? 3 : 4), (isGzip ? 3 : 4))];
		
		pathExtension = [[pathString pathExtension] uppercaseString];		
	}
	
	if ([pathExtension isEqualToString:@"SQL"]) {
		[importFormatPopup selectItemWithTitle:@"SQL"];

		[self changeFormat:self];
	}
	else if ([pathExtension isEqualToString:@"CSV"] || [pathExtension isEqualToString:@"TSV"]) {
		[importFormatPopup selectItemWithTitle:@"CSV"];

		[self changeFormat:self];

		// Set the cell delineator based on extension
		if ([pathExtension isEqualToString:@"CSV"]) {
			[importFieldsTerminatedField setStringValue:@","];
		} else if ([pathExtension isEqualToString:@"TSV"]) {
			[importFieldsTerminatedField setStringValue:@"\\t"];
		}

		NSString *lineEnding = [self _getLineEndingForFile:[selectedUrls[0] path]];

		if (lineEnding) [importLinesTerminatedField setStringValue:lineEnding];
	}
}

#pragma mark -
#pragma mark Other

/**
 * Sets the connection (received from SPDatabaseDocument) and makes things that have to be done only once.
 */
- (void)setConnection:(SPMySQLConnection *)theConnection
{
	NSButtonCell *switchButton = [[NSButtonCell alloc] init];
	
	prefs = [NSUserDefaults standardUserDefaults];
	
	mySQLConnection = theConnection;
	
	// Set up the interface
	[switchButton setButtonType:NSSwitchButton];
	[switchButton setControlSize:NSControlSizeSmall];

	[errorsView setFont:[NSUserDefaults getFont]];
}

/**
 * Selectable toolbar identifiers.
 */
- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
	NSArray *array = [toolbar items];
	NSMutableArray *items = [NSMutableArray arrayWithCapacity:6];
	
	for (NSToolbarItem *item in array)
	{
		[items addObject:[item itemIdentifier]];
	}
	
    return items;
}

/**
 * Displays the import error sheet with the supplied error message.
 */
- (void)showErrorSheetWithMessage:(NSString*)message
{
	if (![NSThread isMainThread]) {
		[[self onMainThread] showErrorSheetWithMessage:message];
		return;
	}
	
	[errorsView setString:message];
	[[tableDocumentInstance parentWindow] beginSheet:errorsSheet completionHandler:nil];
}

#pragma mark -
#pragma mark Private API

/**
 * Starts the import process on a background thread.
 *
 * MUST BE CALLED ON THE UI THREAD!
 */
- (void)_startBackgroundImportTaskForFilename:(NSString *)filename
{
	NSDictionary *userInfo = @{
		@"filename": filename,
		@"fileType": [[importFormatPopup selectedItem] title],
	};
	
	[NSThread detachNewThreadWithName:SPCtxt(@"SPDataImport background import task",tableDocumentInstance)
	                           target:self
	                         selector:@selector(_importBackgroundProcess:)
	                           object:userInfo];
}

/**
 * Background thread worker method for -_startBackgroundImportTaskForFilename:
 */
- (void)_importBackgroundProcess:(NSDictionary *)userInfo
{
	NSString *filename = [userInfo objectForKey:@"filename"];
	NSString *fileType = [userInfo objectForKey:@"fileType"];

	// Use the appropriate processing function for the file type
		 if ([fileType isEqualToString:@"SQL"]) [self importSQLFile:filename];
	else if ([fileType isEqualToString:@"CSV"]) [self importCSVFile:filename];
}

/**
 * Convenience method for closing and restoring the progress sheet to default state.
 */
- (void)_closeAndStopProgressSheet
{
	SPMainQSync(^{
		[NSApp endSheet:self->singleProgressSheet];
		[self->singleProgressBar setIndeterminate:YES];
		[self->singleProgressSheet orderOut:nil];
		[self->singleProgressBar stopAnimation:self];
		[self->singleProgressBar setMaxValue:100];
	});
}

/**
 * Tries to determine the line endings of the specified file using the 'file' command.
 */
- (NSString *)_getLineEndingForFile:(NSString *)filePath
{
	NSString *lineEnding = nil;

	NSTask *fileTask = [[NSTask alloc] init];
	NSPipe *filePipe = [[NSPipe alloc] init];

	[fileTask setLaunchPath:@"/usr/bin/file"];
	[fileTask setArguments:[NSArray arrayWithObjects:@"-L", @"-b", filePath, nil]];
	[fileTask setStandardOutput:filePipe];

	NSFileHandle *fileHandle = [filePipe fileHandleForReading];

	[fileTask launch];

	NSString *fileCheckOutput = [[NSString alloc] initWithData:[fileHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];

	if (fileCheckOutput && [fileCheckOutput length]) {

		NSString *lineEndingString = [fileCheckOutput stringByMatching:@"with ([A-Z]{2,4}) line terminators" capture:1L];

		if (!lineEndingString && [fileCheckOutput isMatchedByRegex:@"text"]) {
			lineEndingString = @"LF";
		}

		if (lineEndingString) {
			if ([lineEndingString isEqualToString:@"LF"]) {
				lineEnding = @"\\n";
			}
			else if ([lineEnding isEqualToString:@"CR"]){
				lineEnding = @"\\r";
			}
			else if ([lineEnding isEqualToString:@"CRLF"]) {
				lineEnding = @"\\r\\n";
			}
		}
	}

	return lineEnding;
}

@end
