//
//  SPExportController.m
//  sequel-pro
//
//  Created by Ben Perry (benperry.com.au) on February 12, 2009.
//  Copyright (c) 2010 Ben Perry. All rights reserved.
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

#import "SPExportController.h"
#import "SPTablesList.h"
#import "SPTableData.h"
#import "SPTableContent.h"
#import "SPExportFile.h"
#import "SPExportFileNameTokenObject.h"
#import "SPDatabaseDocument.h"
#import "SPThreadAdditions.h"
#import "SPPreferenceController.h"
#import "SPGeneralPreferencePane.h"
#import "SPAppController.h"
#import "SPCustomQuery.h"
#import "SPCSVExporter.h"
#import "SPSQLExporter.h"
#import "SPXMLExporter.h"
#import "SPDotExporter.h"
#import "SPExporter.h"
#import "SPCSVExporterProtocol.h"
#import "SPSQLExporterProtocol.h"
#import "SPXMLExporterProtocol.h"
#import "SPDotExporterProtocol.h"
#import "SPPDFExporterProtocol.h"
#import "SPHTMLExporterProtocol.h"
#import "SPFunctions.h"
#import "sequel-ace-Swift.h"

#import <SPMySQL/SPMySQL.h>

// Constants
static const NSUInteger SPExportUIPadding = 20;

static NSString * const SPTableViewStructureColumnID = @"structure";
static NSString * const SPTableViewContentColumnID   = @"content";
static NSString * const SPTableViewDropColumnID      = @"drop";

static const NSString *SPSQLExportStructureEnabled  = @"SQLExportStructureEnabled";
static const NSString *SPSQLExportContentEnabled    = @"SQLExportContentEnabled";
static const NSString *SPSQLExportDropEnabled       = @"SQLExportDropEnabled";

typedef enum
{
	SPExportErrorCancelExport   = 0,
	SPExportErrorReplaceFiles   = 1,
	SPExportErrorSkipErrorFiles = 2
}
SPExportErrorChoice;

static inline BOOL IS_TOKEN(id x);
static inline BOOL IS_STRING(id x);

/**
 * converts a ([obj state] == NSOnState) to @YES / @NO
 * (because doing @([obj state] == NSOnState) will result in an integer 0/1)
 */
static inline NSNumber *IsOn(id obj);

/**
 * Sets the state of obj to NSOnState or NSOffState based on the value of ref
 */
static inline void SetOnOff(NSNumber *ref,id obj);

@interface SPExportController () <SPCSVExporterProtocol, SPSQLExporterProtocol, SPXMLExporterProtocol, SPDotExporterProtocol, SPPDFExporterProtocol, SPHTMLExporterProtocol>

- (void)_switchTab;
- (void)_checkForDatabaseChanges;
- (void)_displayExportTypeOptions:(BOOL)display;
- (void)_updateExportFormatInformation;
- (void)_updateExportAdvancedOptionsLabel;

- (void)_toggleExportButton:(id)uiStateDict;
- (void)_toggleExportButtonOnBackgroundThread;
- (void)_toggleExportButtonWithBool:(NSNumber *)enable;

- (void)_resizeWindowForCustomFilenameViewByHeightDelta:(NSInteger)delta;
- (void)_resizeWindowForAdvancedOptionsViewByHeightDelta:(NSInteger)delta;

- (void)_waitUntilQueueIsEmptyAfterCancelling:(id)sender;
- (void)_queueIsEmptyAfterCancelling:(id)sender;

#pragma mark - SPExportFileUtilitiesPrivateAPI

- (void)_reopenExportSheet;

#pragma mark - SPExportControllerDelegate

- (NSArray *)_updateTokensForMixedContent:(NSArray *)tokens;
- (void)_tokenizeCustomFilenameTokenField;

#pragma mark - SPExportSettingsPersistence

// those methods will convert the name of a C enum constant to a NSString
+ (NSString *)describeExportSource:(SPExportSource)es;
+ (NSString *)describeExportType:(SPExportType)et;
+ (NSString *)describeCompressionFormat:(SPFileCompressionFormat)cf;
+ (NSString *)describeXMLExportFormat:(SPXMLExportFormat)xf;
+ (NSString *)describeSQLExportInsertDivider:(SPSQLExportInsertDivider)eid;

// these will store the C enum constant named by NSString in dst and return YES,
// if a valid mapping exists. Otherwise will just return NO and not modify dst.
+ (BOOL)copyExportSourceForDescription:(NSString *)esd to:(SPExportSource *)dst;
+ (BOOL)copyCompressionFormatForDescription:(NSString *)esd to:(SPFileCompressionFormat *)dst;
+ (BOOL)copyExportTypeForDescription:(NSString *)esd to:(SPExportType *)dst;
+ (BOOL)copyXMLExportFormatForDescription:(NSString *)xfd to:(SPXMLExportFormat *)dst;
+ (BOOL)copySQLExportInsertDividerForDescription:(NSString *)xfd to:(SPSQLExportInsertDivider *)dst;

- (NSDictionary *)exporterSettings;
- (NSDictionary *)csvSettings;
- (NSDictionary *)dotSettings;
- (NSDictionary *)xmlSettings;
- (NSDictionary *)sqlSettings;

- (void)applyExporterSettings:(NSDictionary *)settings;
- (void)applyCsvSettings:(NSDictionary *)settings;
- (void)applyDotSettings:(NSDictionary *)settings;
- (void)applyXmlSettings:(NSDictionary *)settings;
- (void)applySqlSettings:(NSDictionary *)settings;

- (id)exporterSpecificSettingsForSchemaObject:(NSString *)name ofType:(SPTableType)type;
- (id)dotSpecificSettingsForSchemaObject:(NSString *)name ofType:(SPTableType)type;
- (id)xmlSpecificSettingsForSchemaObject:(NSString *)name ofType:(SPTableType)type;
- (id)csvSpecificSettingsForSchemaObject:(NSString *)name ofType:(SPTableType)type;
- (id)sqlSpecificSettingsForSchemaObject:(NSString *)name ofType:(SPTableType)type;

- (void)applyExporterSpecificSettings:(id)settings forSchemaObject:(NSString *)name ofType:(SPTableType)type;
- (void)applyDotSpecificSettings:(id)settings forSchemaObject:(NSString *)name ofType:(SPTableType)type;
- (void)applyXmlSpecificSettings:(id)settings forSchemaObject:(NSString *)name ofType:(SPTableType)type;
- (void)applyCsvSpecificSettings:(id)settings forSchemaObject:(NSString *)name ofType:(SPTableType)type;
- (void)applySqlSpecificSettings:(id)settings forSchemaObject:(NSString *)name ofType:(SPTableType)type;

#pragma mark - Shared Private

- (void)_hideExportProgress;

@end

@implementation SPExportController

@synthesize connection;
@synthesize serverSupport = serverSupport;
@synthesize exportToMultipleFiles;
@synthesize exportCancelled;
@synthesize appScopedBookmark;
@synthesize userChosenDirectory;
@synthesize changeExportOutputPathPanel;
@synthesize bookmarks;
@synthesize startTime;
#pragma mark -
#pragma mark Initialisation

/**
 * Initializes an instance of SPExportController.
 */
- (instancetype)init
{
	if ((self = [super initWithWindowNibName:@"ExportDialog"])) {
		
		[self setExportCancelled:NO];
		[self setExportToMultipleFiles:YES];

		mainNibLoaded = NO;

		exportType = SPSQLExport;
		exportSource = SPTableExport;
		exportTableCount = 0;
		currentTableExportIndex = 0;
		
		exportFilename = [[NSMutableString alloc] init];
		exportTypeLabel = @"";
		
		createCustomFilename = NO;
		previousConnectionEncodingViaLatin1 = NO;
		
		tables = [[NSMutableArray alloc] init];
		exporters = [[NSMutableArray alloc] init];
		exportFiles = [[NSMutableArray alloc] init];
		operationQueue = [[NSOperationQueue alloc] init];
        bookmarks = [NSMutableArray arrayWithArray:SecureBookmarkManager.sharedInstance.bookmarks];

		showAdvancedView = NO;
		showCustomFilenameView = NO;
		serverLowerCaseTableNameValue = NSNotFound;

		heightOffset1 = 0;
		heightOffset2 = 0;
		
		prefs = [NSUserDefaults standardUserDefaults];
		
		localizedTokenNames = @{
			SPFileNameHostTokenName:       NSLocalizedString(@"Host", @"export filename host token"),
			SPFileNameDatabaseTokenName:   NSLocalizedString(@"Database", @"export filename database token"),
			SPFileNameTableTokenName:      NSLocalizedString(@"Table", @"table"),
			SPFileNameDateTokenName:       NSLocalizedString(@"Date", @"export filename date token"),
			SPFileNameYearTokenName:       NSLocalizedString(@"Year", @"export filename date token"),
			SPFileNameMonthTokenName:      NSLocalizedString(@"Month", @"export filename date token"),
			SPFileNameDayTokenName:        NSLocalizedString(@"Day", @"export filename date token"),
			SPFileNameTimeTokenName:       NSLocalizedString(@"Time", @"export filename time token"),
			SPFileName24HourTimeTokenName: NSLocalizedString(@"24-Hour Time", @"export filename time token"),
			SPFileNameFavoriteTokenName:   NSLocalizedString(@"Favorite", @"export filename favorite name token")
		};
	}
	
	return self;
}

/**
 * Upon awakening select the first toolbar item
 */
- (void)awakeFromNib
{
	// As this controller also loads its own nib, it may call awakeFromNib multiple times; perform setup only once.
	if (mainNibLoaded) return;
	
	mainNibLoaded = YES;
	
	windowMinWidth = [[self window] minSize].width;
	windowMinHeigth = [[self window] minSize].height;

	// Select the 'selected tables' option
	[exportInputPopUpButton selectItemAtIndex:SPTableExport];
	
	// Select the SQL tab
	[[exportTypeTabBar tabViewItemAtIndex:0] setView:exporterView];
	[exportTypeTabBar selectTabViewItemAtIndex:0];
	
	// By default a new SQL INSERT statement should be created every 250KiB of data
	[exportSQLInsertNValueTextField setIntegerValue:250];
	
	// Prevents the background colour from changing when clicked
	[[exportCustomFilenameViewLabelButton cell] setHighlightsBy:NSNoCellMask];
	
	// Set the progress indicator's max value
	[exportProgressIndicator setMaxValue:(NSInteger)[exportProgressIndicator bounds].size.width];

	// Empty the tokenizing character set for the filename field
	[exportCustomFilenameTokenField setTokenizingCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@""]];

	// Accept Core Animation
	[exportOptionsTabBar wantsLayer];
	[exportTablelistScrollView wantsLayer];
	[exportTableListButtonBar wantsLayer];
}

#pragma mark -
#pragma mark Export methods

/**
 * Displays the export window with the supplied tables and export type/format selected.
 *
 * @param exportTables The array of table names to be exported
 * @param format       The export format to be used. See SPExportType constants.
 * @param source       The source of the export. See SPExportSource constants.
 */
- (void)exportTables:(NSArray *)exportTables asFormat:(SPExportType)format usingSource:(SPExportSource)source
{
	// set some defaults
	[exportCSVNULLValuesAsTextField setStringValue:[prefs stringForKey:SPNullValue]];
	[exportXMLNULLValuesAsTextField setStringValue:[prefs stringForKey:SPNullValue]];

	// MARK: removed default export location
	
	// initially popuplate the tables list
	[self refreshTableList:nil];
		
	// overwrite defaults with user settings from last export
	[self applySettingsFromDictionary:[prefs objectForKey:SPLastExportSettings] error:NULL];
	
	// overwrite those with settings for the current export
	
	// Select the correct tab
	if(format != SPAnyExportType) [exportTypeTabBar selectTabViewItemAtIndex:format];
	
	[self updateDisplayedExportFilename];
	
	[exporters removeAllObjects];
	[exportFiles removeAllObjects];
			
	// If tables were supplied, select them
	if (exportTables) {
		
		// Disable all tables
		for (NSMutableArray *table in tables)
		{
			[table safeReplaceObjectAtIndex:1 withObject:@NO];
			[table safeReplaceObjectAtIndex:2 withObject:@NO];
			[table safeReplaceObjectAtIndex:3 withObject:@NO];
		}
		
		// Select the supplied tables
		for (NSMutableArray *table in tables)
		{
			for (NSString *exportTable in exportTables)
			{
				if ([exportTable isEqualToString:[table objectAtIndex:0]]) {
					[table safeReplaceObjectAtIndex:1 withObject:@YES];
					[table safeReplaceObjectAtIndex:2 withObject:@YES];
					[table safeReplaceObjectAtIndex:3 withObject:@YES];
				}
			}
		}
		
		[exportTableList reloadData];
	}
	
	// Ensure interface validation
	[self _switchTab];
	[self _updateExportAdvancedOptionsLabel];
	[self setExportInput:source];

	[[tableDocumentInstance parentWindowControllerWindow] beginSheet:self.window completionHandler:^(NSModalResponse returnCode) {
		// Perform the export
		if (returnCode == NSModalResponseOK) {

			[self->prefs setObject:[self currentSettingsAsDictionary] forKey:SPLastExportSettings];

			// If we are about to perform a table export, cache the current number of tables within the list,
			// refresh the list and then compare the numbers to accommodate situations where new tables are
			// added by external applications.
			if ((self->exportSource == SPTableExport) && (self->exportType != SPDotExport)) {

				// Give the export sheet a chance to close
				[self performSelector:@selector(_checkForDatabaseChanges) withObject:nil afterDelay:0.5];
			}
			else {
				// Initialize the export after a short delay to give the alert a chance to close
				[self performSelector:@selector(initializeExportUsingSelectedOptions) withObject:nil afterDelay:0.5];
			}
		}
	}];
}

/**
 * Opens the errors sheet and displays the supplied errors string.
 *
 * @param errors The errors string to be displayed
 */
- (void)openExportErrorsSheetWithString:(NSString *)errors
{
	[errorsTextView setString:@""];
	[errorsTextView setString:errors];

	[[tableDocumentInstance parentWindowControllerWindow] beginSheet:errorsWindow completionHandler:nil];
}

/**
 * Displays the export finished notification.
 */
- (void)displayExportFinishedNotification
{
	// Export finished notification
	NSUserNotification *notification = [[NSUserNotification alloc] init];
	notification.title = @"Export Finished";
	notification.informativeText=[NSString stringWithFormat:NSLocalizedString(@"Finished exporting to %@", @"description for finished exporting notification"), exportFilename];
	notification.soundName = NSUserNotificationDefaultSoundName;

	[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

#pragma mark -
#pragma mark IB action methods

/**
 * Opens the export dialog selecting the appropriate export type and source based on the current context.
 * For example, if either the table content view or custom query editor views are active and there is 
 * data available, these options will be selected as the export source ('Filtered' or 'Query Result'). If 
 * either of these views are not active then the default source are the currently selected tables. If no 
 * tables are currently selected then all tables are checked. Note that in this instance the default export 
 * type is SQL where as in the case of filtered or query result export the default type is CSV.
 *
 * @param sender The caller (can be anything or nil as it is not currently used).
 */
- (void)exportData {
	SPExportType selectedExportType = SPAnyExportType;
	SPExportSource selectedExportSource = SPTableExport;

    // if they are exporting and haven't selected a table
    // loadTableValues will fail, so select the last table
    if([tablesListInstance selectedTableItems].count == 0){
        [tablesListInstance selectTableAtIndex:@(tablesListInstance.tables.count-1)];
    }
	
	NSArray *selectedTables = [tablesListInstance selectedTableItems];
	
	BOOL isCustomQuerySelected = ([tableDocumentInstance isCustomQuerySelected] && ([[customQueryInstance currentResult] count] > 1)); 
	BOOL isContentSelected     = ([[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableContent] && ([[tableContentInstance currentResult] count] > 1));
	
	if (isContentSelected) {		
		selectedTables = nil;
		selectedExportType = SPCSVExport;
		selectedExportSource = SPFilteredExport;
	}
	else if (isCustomQuerySelected) {
		selectedTables = nil;
		selectedExportType = SPCSVExport;
		selectedExportSource = SPQueryExport;
	}
	else {
		selectedTables = ([selectedTables count]) ? selectedTables : nil; 
	}
	
	[self exportTables:selectedTables asFormat:selectedExportType usingSource:selectedExportSource];
}

/**
 * Closes the export dialog.
 */
- (IBAction)closeSheet:(id)sender
{
	
	// if they clicked export
	// Cancel tag = 0
	// Export tag = 1
	if ([(NSButton*)sender tag] == 1){
		// but nothing is in the export path field
		if([exportPathField stringValue] == nil || [[exportPathField stringValue] isEqualToString:@""] ){
			NSLog(@"ERROR: no path!");
			NSLog(@"sender title: %@, sender tag: %ld", [(NSButton*)sender title], (long)[(NSButton*)sender tag]);
			
			NSAlert *alert = [[NSAlert alloc] init];
			[alert setAlertStyle:NSAlertStyleCritical];
			[alert setMessageText:NSLocalizedString(@"No directory selected.", @"No directory selected.")];
			[alert setInformativeText:NSLocalizedString(@"Please select a new export location and try again.", @"Please select a new export location and try again")];
			
			[alert beginSheetModalForWindow:[tableDocumentInstance parentWindowControllerWindow] completionHandler:^(NSInteger returnCode) {
				[self performSelector:@selector(_reopenExportSheet) withObject:nil afterDelay:0.1];
			}];
			
			// we don't want to close the sheet so return here
			return;
		}
	}
	
	if ([sender window] == [self window]) {
		
		// Close the advanced options view if it's open
		[exportAdvancedOptionsView setHidden:YES];
		[exportAdvancedOptionsViewButton setState:NSOffState];
		showAdvancedView = NO;
		
		// Close the customize filename view if it's open
		[exportCustomFilenameView setHidden:YES];
		[exportCustomFilenameViewButton setState:NSOffState];
		showCustomFilenameView = NO;
		
		// If open close the advanced options view and custom filename view
		[self _resizeWindowForAdvancedOptionsViewByHeightDelta:0];
		[self _resizeWindowForCustomFilenameViewByHeightDelta:0];
	}
	
	// should we reliquish access here?
	// user clicked cancel, they may just click export again
	// without selecting a folder again..
	// tried it ... doesn't give good UX.
	
	[NSApp endSheet:[sender window] returnCode:[(NSButton*)sender tag]];
	[[sender window] orderOut:self];
}

- (BOOL)setExportInput:(SPExportSource)input
{
	SPExportSource actualInput = input;
	// Dot will always be a TableExport
	if(exportType == SPDotExport) {
		actualInput = SPTableExport;
	}
	//check if the type actually is valid
	else if(![[exportInputPopUpButton itemAtIndex:input] isEnabled]) {
		//...no, pick a valid one instead
		for (NSMenuItem *item in [exportInputPopUpButton itemArray]) {
			if([item isEnabled]) {
				actualInput = [exportInputPopUpButton indexOfItem:item];
				goto set_input; //MARK: a goto in the WILD!
			}
		}
		// nothing found (should not happen)
		SPLog(@"did not find any valid export input!?");
		return NO;
	}
set_input:
	exportSource = actualInput;
	
	[exportInputPopUpButton selectItemAtIndex:exportSource];
	
	BOOL isSelectedTables = (exportSource == SPTableExport);
	
	[exportFilePerTableCheck setHidden:(!isSelectedTables) || (exportType == SPSQLExport)];
	[exportTableList setEnabled:isSelectedTables];
	[exportSelectAllTablesButton setEnabled:isSelectedTables];
	[exportDeselectAllTablesButton setEnabled:isSelectedTables];
	[exportRefreshTablesButton setEnabled:isSelectedTables];
	
	[self updateAvailableExportFilenameTokens]; // will also update the filename itself
	
	return (actualInput == input);
}

/**
 * Enables/disables and shows/hides various interface controls depending on the selected item.
 */
- (IBAction)switchInput:(id)sender
{
	[self setExportInput:(SPExportSource)[exportInputPopUpButton indexOfSelectedItem]];
}

/**
 * Sets the sender to a dict for error display by the real cancelExport: method
 */
- (void)cancelExportForFile:(NSString*)fileName{

    SPLog(@"self.exportOutputFile.fileHandleError == YES, cancelling. Filename: %@", fileName);
    [self cancelExport:@{ @"type" : SPExportFileHandleError, @"fileName" : fileName }];
}

/**
 * Cancel's the export operation by stopping the current table export loop and marking any current SPExporter
 * NSOperation subclasses as cancelled.
 */
- (IBAction)cancelExport:(id)sender
{
    if ([sender isKindOfClass:[NSDictionary class]]) {
        if([[sender safeObjectForKey:@"type"] isEqualToString:SPExportFileHandleError]){
            NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Error while writing to the export file. Could not open file: %@", @"Error while writing to the export file"), [sender safeObjectForKey:@"fileName"]];
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Export Error", @"Export Error") message:message callback:nil];
        }
    }

	[self setExportCancelled:YES];
	
	[exportProgressIndicator setIndeterminate:YES];
	[exportProgressIndicator setUsesThreadedAnimation:YES];
	[exportProgressIndicator startAnimation:self];
	
	[exportProgressTitle setStringValue:NSLocalizedString(@"Cancelling...", @"cancelling task status message")];
	[exportProgressText setStringValue:NSLocalizedString(@"Cleaning up...", @"cancelling export cleaning up message")];
	
	// Disable the cancel button
    if ([sender isKindOfClass:[NSButton class]]) {
        [sender setEnabled:NO];
    }
	
	// should we reliquish access here?
	// user clicked cancel, they may just click export again
	// without selecting a folder again..
	// let's try it
	// No, bad UX.
	
	// Cancel all of the currently running operations
	[operationQueue cancelAllOperations]; // async call
	[NSThread detachNewThreadWithName:SPCtxt(@"SPExportController cancelExport: waiting for empty queue", tableDocumentInstance) target:self selector:@selector(_waitUntilQueueIsEmptyAfterCancelling:) object:sender];
}

- (void)_waitUntilQueueIsEmptyAfterCancelling:(id)sender
{
	[operationQueue waitUntilAllOperationsAreFinished];
	[self performSelectorOnMainThread:@selector(_queueIsEmptyAfterCancelling:) withObject:sender waitUntilDone:NO];
}

- (void)_queueIsEmptyAfterCancelling:(id)sender
{
	// Loop the cached export file paths and remove them from disk if they exist
	for (SPExportFile *file in exportFiles)
	{
		[file delete];
	}
	
	[self _hideExportProgress];

	// Restore the connection encoding to it's pre-export value
	[tableDocumentInstance setConnectionEncoding:[NSString stringWithFormat:@"%@%@", previousConnectionEncoding, (previousConnectionEncodingViaLatin1) ? @"-" : @""] reloadingViews:NO];

	// Re-enable the cancel button for future exports
    if ([sender isKindOfClass:[NSButton class]]) {
        [sender setEnabled:YES];
    }
	
	// Finally get rid of all the exporters and files
	[exportFiles removeAllObjects];
	[exporters removeAllObjects];
}

- (void)_hideExportProgress
{
	// Close the progress sheet
	[NSApp endSheet:exportProgressWindow returnCode:0];
	[exportProgressWindow orderOut:self];

	// Stop the progress indicator
	[exportProgressIndicator stopAnimation:self];
	[exportProgressIndicator setUsesThreadedAnimation:NO];
}

// NSOpenSavePanelDelegate - not sure why this wasn't enabled before...
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url{
	return YES;
}

/**
 * Opens the open panel when user selects to change the output path.
 */
- (IBAction)changeExportOutputPath:(id)sender
{	
	self.changeExportOutputPathPanel = [NSOpenPanel openPanel]; 	// need to retain, so we can relinquish access via stopAccessingSecurityScopedResource
																	// I'm not sure though, haven't written non-ARC code for years.
	
	changeExportOutputPathPanel.delegate = self;
	
	[changeExportOutputPathPanel setCanChooseFiles:NO];
	[changeExportOutputPathPanel setCanChooseDirectories:YES];
	[changeExportOutputPathPanel setCanCreateDirectories:YES];

    [changeExportOutputPathPanel setDirectoryURL:[NSURL URLWithString:[exportPathField stringValue]]];
    [changeExportOutputPathPanel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger returnCode) {
        if (returnCode == NSModalResponseOK) {

            NSMutableString *path = [[NSMutableString alloc] initWithCapacity:self->changeExportOutputPathPanel.directoryURL.absoluteString.length];
            [path setString:[[self->changeExportOutputPathPanel directoryURL] path]];

			if(!path) {
				@throw [NSException exceptionWithName:NSInternalInconsistencyException
											   reason:[NSString stringWithFormat:@"File panel ended with OK, but returned nil for path!? directoryURL=%@,isFileURL=%d",[self->changeExportOutputPathPanel directoryURL],[[self->changeExportOutputPathPanel directoryURL] isFileURL]]
											 userInfo:nil];
			}

            [self->exportPathField setStringValue:path];

            NSMutableString *classStr = [NSMutableString string];
            [classStr appendStringOrNil:NSStringFromClass(self->changeExportOutputPathPanel.URL.class)];

            SPLog(@"self->changeExportOutputPathPanel.URL.class: %@", classStr);

            // check it's really a URL
            if(![self->changeExportOutputPathPanel.URL isKindOfClass:[NSURL class]]){

                SPLog(@"self->changeExportOutputPathPanel.URL is not a valid URL: %@", classStr);

                NSView __block *helpView;

                SPMainQSync(^{
                    // call windowDidLoad to alloc the panes
                    [[SPAppDelegate preferenceController] window];
                    helpView = [[[SPAppDelegate preferenceController] generalPreferencePane] modifyAndReturnBookmarkHelpView];
                });
                
                NSString *alertMessage = [NSString stringWithFormat:NSLocalizedString(@"The selected file is not a valid file.\n\nPlease try again.\n\nClass: %@", @"error while selecting file message"),
                                          classStr];

                [NSAlert createAccessoryWarningAlertWithTitle:NSLocalizedString(@"File Selection Error", @"error while selecting file message") message:alertMessage accessoryView:helpView callback:^{

                    NSDictionary *userInfo = @{
                        NSLocalizedDescriptionKey: @"self->changeExportOutputPathPanel.URL is not a valid URL",
                        @"func": [NSString stringWithFormat:@"%s", __PRETTY_FUNCTION__],
                        @"class": classStr
                    };

                    SPLog(@"userInfo: %@", userInfo);
                }];
            }
            else{
                // this needs to be read-write
                if([SecureBookmarkManager.sharedInstance addBookmarkForUrl:self->changeExportOutputPathPanel.URL options:(NSURLBookmarkCreationWithSecurityScope) isForStaleBookmark:NO isForKnownHostsFile:NO] == YES){
                    SPLog(@"addBookmarkForUrl success: %@", self->changeExportOutputPathPanel.URL.absoluteString);
                } else{
                    SPLog(@"addBookmarkForUrl failed: %@", self->changeExportOutputPathPanel.URL);
                }
            }
        }// end of OK
        else if(returnCode == NSModalResponseCancel){
            SPLog(@"User clicked cancel, didn't change the output path");
        }
    }];
}

/**
 * Refreshes the table list.
 */
- (IBAction)refreshTableList:(id)sender
{		
	NSMutableDictionary *tableDict = [[NSMutableDictionary alloc] init];
	
	// Before refreshing the list, preserve the user's table selection, but only if it was triggered by the UI.
	if (sender) {
		for (NSMutableArray *item in tables)
		{
			[tableDict safeSetObject:[NSArray arrayWithObjects:
								  [item safeObjectAtIndex:1],
								  [item safeObjectAtIndex:2],
								  [item safeObjectAtIndex:3],
								  [item safeObjectAtIndex:4],
								  nil] 
						  forKey:[item firstObject]];
		}
	}
	
	[tables removeAllObjects];
	
	// For all modes, retrieve table and view names
	{
		NSArray *tablesAndViews = [tablesListInstance allTableAndViewNames];

		for (id itemName in tablesAndViews) {
			[tables safeAddObject:[NSMutableArray arrayWithObjects:
					            itemName,
			                    @YES,
			                    @YES,
			                    @YES,
			                    [NSNumber numberWithInt:SPTableTypeTable],
			                    nil]];
		}
	} // The purpose of this extra { } is to limit visibility and thus catch copy&paste errors
	
	// For SQL only, add procedures and functions
	if (exportType == SPSQLExport) {
		// Procedures
		{
			NSArray *procedures = [tablesListInstance allProcedureNames];

			for (id procName in procedures) {
				[tables safeAddObject:[NSMutableArray arrayWithObjects:
				                    procName,
				                    @YES,
				                    @YES,
				                    @YES,
				                    [NSNumber numberWithInt:SPTableTypeProc],
				                    nil]];
			}
		}
		// Functions
		{
			NSArray *functions = [tablesListInstance allFunctionNames];

			for (id funcName in functions) {
				[tables safeAddObject:[NSMutableArray arrayWithObjects:
				                    funcName,
				                    @YES,
				                    @YES,
				                    @YES,
				                    [NSNumber numberWithInt:SPTableTypeFunc],
				                    nil]];
			}
		}
	}
	
	if (sender) {
		// Restore the user's table selection
		for (NSUInteger i = 0; i < [tables count]; i++)
		{
			NSMutableArray *oldSelection = [tableDict objectForKey:[[tables safeObjectAtIndex:i] firstObject]];
			
			if (oldSelection) {
				
				NSMutableArray *newItem = [[NSMutableArray alloc] initWithArray:oldSelection];
				
				[newItem insertObject:[[tables safeObjectAtIndex:i] firstObject] atIndex:0];
				
				[tables safeReplaceObjectAtIndex:i withObject:newItem];
			}
		}
	}
	
	[exportTableList reloadData];
}

/**
 * Selects or de-selects all tables.
 */
- (IBAction)selectDeselectAllTables:(id)sender
{
	BOOL toggleStructure = NO;
	BOOL toggleDropTable = NO;

	[self refreshTableList:nil];

	// Determine whether the structure and drop items should also be toggled
	if (exportType == SPSQLExport) {
		if ([exportSQLIncludeStructureCheck state]) toggleStructure = YES;
		if ([exportSQLIncludeDropSyntaxCheck state]) toggleDropTable = YES;
	}

	for (NSMutableArray *table in tables)
	{
		if (toggleStructure) [table safeReplaceObjectAtIndex:1 withObject:[NSNumber numberWithBool:[(NSButton*)sender tag]]];
		
		[table safeReplaceObjectAtIndex:2 withObject:[NSNumber numberWithBool:[(NSButton*)sender tag]]];
		
		if (toggleDropTable) [table safeReplaceObjectAtIndex:3 withObject:[NSNumber numberWithBool:[(NSButton*)sender tag]]];
	}
	
	[exportTableList reloadData];

	[self _updateExportFormatInformation];
	[self _toggleExportButtonOnBackgroundThread];
}

/**
 * Updates the default filename extenstion based on the selected output compression format.
 */
- (IBAction)changeExportCompressionFormat:(id)sender
{
	[self updateDisplayedExportFilename];
}

/**
 * Toggles the state of the custom filename format token fields.
 */
- (IBAction)toggleCustomFilenameFormatView:(id)sender
{
	showCustomFilenameView = !showCustomFilenameView;

	if (!showCustomFilenameView) {
		[exportFilenameDividerBox setHidden:NO];
		[exportCustomFilenameView setHidden:YES];
	}

	[self _resizeWindowForCustomFilenameViewByHeightDelta:showCustomFilenameView ? [exportCustomFilenameView frame].size.height : 0];

	if (showCustomFilenameView) {
		[exportFilenameDividerBox setHidden:YES];
		[exportCustomFilenameView setHidden:NO];
	}

	[exportCustomFilenameViewButton setState:showCustomFilenameView];
}

/**
 * Toggles the options available depending on the selected XML output format.
 */
- (IBAction)toggleXMLOutputFormat:(id)sender
{
	if ([sender indexOfSelectedItem] == SPXMLExportMySQLFormat) {
		[exportXMLIncludeStructure setEnabled:YES];
		[exportXMLIncludeContent setEnabled:YES];
		[exportXMLNULLValuesAsTextField setEnabled:NO];
	}
	else if ([sender indexOfSelectedItem] == SPXMLExportPlainFormat) {
		[exportXMLIncludeStructure setEnabled:NO];
		[exportXMLIncludeContent setEnabled:NO];
		[exportXMLNULLValuesAsTextField setEnabled:YES];
	}
}

/**
 * Toggles the display of the advanced options box.
 */
- (IBAction)toggleAdvancedExportOptionsView:(id)sender
{
	showAdvancedView = !showAdvancedView;

	if (!showAdvancedView) {
		[exportAdvancedOptionsView setHidden:YES];
	}

	[self _updateExportAdvancedOptionsLabel];
	[self _resizeWindowForAdvancedOptionsViewByHeightDelta:showAdvancedView ? [exportAdvancedOptionsView frame].size.height + 10 : 0];

	if (showAdvancedView) {
		[exportAdvancedOptionsView setHidden:NO];
	}

	[exportAdvancedOptionsViewButton setState:showAdvancedView];
}

/**
 * Toggles the export button when choosing to include or table structures in an SQL export.
 */
- (IBAction)toggleSQLIncludeStructure:(NSButton *)sender
{
	if (![sender state])
	{
		[exportSQLIncludeDropSyntaxCheck setState:NSOffState];
	}
	
	[exportSQLIncludeDropSyntaxCheck setEnabled:[sender state]];
	[exportSQLIncludeAutoIncrementValueButton setEnabled:[sender state]];
	
	[[exportTableList tableColumnWithIdentifier:SPTableViewDropColumnID] setHidden:(![sender state])];
	[[exportTableList tableColumnWithIdentifier:SPTableViewStructureColumnID] setHidden:(![sender state])];
	
	[self _toggleExportButtonOnBackgroundThread];
}

/**
 * Toggles the export button when choosing to include or exclude table contents in an SQL export.
 */
- (IBAction)toggleSQLIncludeContent:(NSButton *)sender
{
	[[exportTableList tableColumnWithIdentifier:SPTableViewContentColumnID] setHidden:(![sender state])];
	
	[self _toggleExportButtonOnBackgroundThread];
}

/**
 * Toggles the export button when choosing to include or exclude table drop syntax in an SQL export.
 */
- (IBAction)toggleSQLIncludeDropSyntax:(NSButton *)sender
{
	[[exportTableList tableColumnWithIdentifier:SPTableViewDropColumnID] setHidden:(![sender state])];
	
	[self _toggleExportButtonOnBackgroundThread];
}

/**
 * Toggles whether XML and CSV files should be combined into a single file.
 */
- (IBAction)toggleNewFilePerTable:(NSButton *)sender
{
	[self _updateExportFormatInformation];
	[self updateAvailableExportFilenameTokens];
}

/**
 * Opens the export sheet, selecting custom query as the export source.
 */
- (IBAction)exportCustomQueryResultAsFormat:(id)sender
{	
	[self exportTables:nil asFormat:[(NSMenuItem*)sender tag] usingSource:SPQueryExport];
}

#pragma mark -
#pragma mark Other 

- (void)tableListChangedAlertDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{

}

/**
 * Menu item validation.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if ([menuItem action] == @selector(exportCustomQueryResultAsFormat:)) {
		return (([customQueryInstance currentResultRowCount] > 0) && (![tableDocumentInstance isProcessing]));		
	}
	
	return YES;
}

#pragma mark -
#pragma mark Private API

/**
 * Changes the selected export format and updates the UI accordingly.
 */
- (void)_switchTab
{		
	// Selected export format
	NSString *type = [[[exportTypeTabBar selectedTabViewItem] identifier] lowercaseString];
	
	// Determine the export type
	exportType = [exportTypeTabBar indexOfTabViewItemWithIdentifier:type];
	
	// Determine what data to use (filtered result, custom query result or selected table(s)) for the export operation
	exportSource = (exportType == SPDotExport) ? SPTableExport : [exportInputPopUpButton indexOfSelectedItem];
		
	[exportOptionsTabBar selectTabViewItemWithIdentifier:type];
	
	BOOL isSQL  = (exportType == SPSQLExport);
	BOOL isCSV  = (exportType == SPCSVExport);
	BOOL isXML  = (exportType == SPXMLExport);
	//BOOL isHTML = (exportType == SPHTMLExport);
	//BOOL isPDF  = (exportType == SPPDFExport);
	BOOL isDot  = (exportType == SPDotExport);
	
	BOOL enable = (isCSV || isXML /* || isHTML || isPDF  */ || isDot);
	
	[exportFilePerTableCheck setHidden:(isSQL || isDot)];		
	[exportTableList setEnabled:(!isDot)];
	[exportSelectAllTablesButton setEnabled:(!isDot)];
	[exportDeselectAllTablesButton setEnabled:(!isDot)];
	[exportRefreshTablesButton setEnabled:(!isDot)];
	
	[[[exportInputPopUpButton menu] itemAtIndex:SPTableExport] setEnabled:(!isDot)];
	
	[exportInputPopUpButton setEnabled:(!isDot)];
	
	// When exporting to SQL, only the selected tables option should be enabled
	if (isSQL) {
		// Programmatically changing the selected item of a popup button does not fire it's action, so update
		// the selected export source manually.
		exportSource = SPTableExport;
		
		[exportInputPopUpButton selectItemAtIndex:SPTableExport];
		[[[exportInputPopUpButton menu] itemAtIndex:SPFilteredExport] setEnabled:NO];
		[[[exportInputPopUpButton menu] itemAtIndex:SPQueryExport] setEnabled:NO];
	}
	else {
		// Enable/disable the 'filtered result' and 'query result' options
		// Note that the result count check is always greater than one as the first row is always the field names
		[[[exportInputPopUpButton menu] itemAtIndex:SPFilteredExport] setEnabled:((enable) && ([[tableContentInstance currentResult] count] > 1))];
		[[[exportInputPopUpButton menu] itemAtIndex:SPQueryExport] setEnabled:((enable) && ([[customQueryInstance currentResult] count] > 1))];
	}
	
	[[exportTableList tableColumnWithIdentifier:SPTableViewStructureColumnID] setHidden:(isSQL) ? (![exportSQLIncludeStructureCheck state]) : YES];
	[[exportTableList tableColumnWithIdentifier:SPTableViewDropColumnID] setHidden:(isSQL) ? (![exportSQLIncludeDropSyntaxCheck state]) : YES];
	
	[[[exportTableList tableColumnWithIdentifier:SPTableViewContentColumnID] headerCell] setStringValue:(enable) ? @"" : @"C"]; 
	
	// Set the tooltip
	[[exportTableList tableColumnWithIdentifier:SPTableViewContentColumnID] setHeaderToolTip:(enable) ? @"" : NSLocalizedString(@"Include content", @"include content table column tooltip")];
	
	// When switching to Dot export, ensure the server's lower_case_table_names value is checked the first time
	// to set the export's link case sensitivity setting
	if (isDot && serverLowerCaseTableNameValue == NSNotFound) {
		
		SPMySQLResult *caseResult = [connection queryString:@"SHOW VARIABLES LIKE 'lower_case_table_names'"];
		
		[caseResult setReturnDataAsStrings:YES];
		
		if ([caseResult numberOfRows] == 1) {
			serverLowerCaseTableNameValue = [[[caseResult getRowAsDictionary] objectForKey:@"Value"] integerValue];
		} 
		else {
			serverLowerCaseTableNameValue = 0;
		}
		
		[exportDotForceLowerTableNamesCheck setState:(serverLowerCaseTableNameValue == 0)?NSOffState:NSOnState];
	}
	
	[self _displayExportTypeOptions:(isSQL || isCSV || isXML || isDot)];
	[self updateAvailableExportFilenameTokens];
	
	[self updateDisplayedExportFilename];
	[self _updateExportFormatInformation];
}

/**
 * Checks for changes in the current database, by refreshing the table list and warning the user if required.
 */
- (void)_checkForDatabaseChanges
{
	NSUInteger i = [tables count];
	
	[tablesListInstance updateTables:self];
		
	NSUInteger j = [[tablesListInstance allTableAndViewNames] count];
	
	// If this is an SQL export, include procs and functions
	if (exportType == SPSQLExport) {
		j += ([[tablesListInstance allProcedureNames] count] + [[tablesListInstance allFunctionNames] count]);
	}
		
	if (j > i) {
		NSUInteger diff = j - i;
		[NSAlert createDefaultAlertWithTitle:NSLocalizedString(@"The list of tables has changed", @"table list change alert message") message:[NSString stringWithFormat:NSLocalizedString(@"The number of tables in this database has changed since the export dialog was opened. There are now %lu additional table(s), most likely added by an external application.\n\nHow would you like to proceed?", @"table list change alert informative message"), (unsigned long)diff] primaryButtonTitle:NSLocalizedString(@"Continue", @"continue button") primaryButtonHandler:^{
			// Initialize the export after a short delay to give the alert a chance to close
			[self performSelector:@selector(initializeExportUsingSelectedOptions) withObject:nil afterDelay:0.5];
		} cancelButtonHandler:^{
			// Cancel the export and redisplay the export dialog after a short delay
			[self performSelector:@selector(exportData) withObject:self afterDelay:0.5];
		}];
	}
	else {
		[self initializeExportUsingSelectedOptions];
	}
}

/**
 * Toggles the display of the export type options view.
 *
 * @param display A BOOL indicating whether or not the view should be visible
 */
- (void)_displayExportTypeOptions:(BOOL)display
{
	NSRect windowFrame = [[exportTablelistScrollView window] frame];
	NSRect viewFrame   = [exportTablelistScrollView frame];
	NSRect barFrame    = [exportTableListButtonBar frame];
	
	NSUInteger padding = (2 * SPExportUIPadding);
	
	CGFloat width  = (!display) ? (windowFrame.size.width - (padding + 2)) : (windowFrame.size.width - ([exportOptionsTabBar frame].size.width + (padding + 4)));
	
	[NSAnimationContext beginGrouping];
	[[NSAnimationContext currentContext] setDuration:0.3];
	
	[[exportOptionsTabBar animator] setHidden:(!display)];
	[[exportTablelistScrollView animator] setFrame:NSMakeRect(viewFrame.origin.x, viewFrame.origin.y, width, viewFrame.size.height)];
	[[exportTableListButtonBar animator] setFrame:NSMakeRect(barFrame.origin.x, barFrame.origin.y, width, barFrame.size.height)];
	
	[NSAnimationContext endGrouping];
}

/**
 * Updates the information note in the window based on the current export settings.
 */
- (void)_updateExportFormatInformation
{
	NSString *noteText = @"";

	// If the selected format is XML, Dot, or multiple tables in one CSV file, display a warning note.
	switch (exportType) {
		case SPCSVExport:
			if ([exportFilePerTableCheck state]) break;
			
			NSUInteger numberOfTables = 0;
			
			for (NSMutableArray *eachTable in tables) 
			{
				if ([[eachTable safeObjectAtIndex:2] boolValue]) numberOfTables++;
			}
			
			if (numberOfTables <= 1) break;
		case SPXMLExport:
		case SPDotExport:
			noteText = NSLocalizedString(@"Import of the selected data is currently not supported.", @"Export file format cannot be imported warning");
			break;
		default:
			break;
	}

	[exportFormatInfoText setStringValue:noteText];
}

/**
 * Update the export advanced options label to show a summary if the options are hidden.
 */
- (void)_updateExportAdvancedOptionsLabel
{
	if (showAdvancedView) {
		[exportAdvancedOptionsViewLabelButton setTitle:NSLocalizedString(@"Advanced", @"Advanced options short title")];
		return;
	}

	NSMutableArray *optionsSummary = [NSMutableArray array];

	if ([exportProcessLowMemoryButton state]) {
		[optionsSummary addObject:NSLocalizedString(@"Low memory", @"Low memory export summary")];
	} 
	else {
		[optionsSummary addObject:NSLocalizedString(@"Standard memory", @"Standard memory export summary")];
	}

	if ([exportOutputCompressionFormatPopupButton indexOfSelectedItem] == SPNoCompression) {
		[optionsSummary addObject:NSLocalizedString(@"no compression", @"No compression export summary - within a sentence")];
	} 
	else if ([exportOutputCompressionFormatPopupButton indexOfSelectedItem] == SPGzipCompression) {
		[optionsSummary addObject:NSLocalizedString(@"Gzip compression", @"Gzip compression export summary - within a sentence")];
	} 
	else if ([exportOutputCompressionFormatPopupButton indexOfSelectedItem] == SPBzip2Compression) {
		[optionsSummary addObject:NSLocalizedString(@"bzip2 compression", @"bzip2 compression export summary - within a sentence")];
	}

	[exportAdvancedOptionsViewLabelButton setTitle:[NSString stringWithFormat:@"%@ (%@)", NSLocalizedString(@"Advanced", @"Advanced options short title"), [optionsSummary componentsJoinedByString:@", "]]];
}

/**
 * Enables or disables the export button based on the state of various interface controls. 
 *
 * @param uiStateDict A dictionary containing the state of various UI controls.
 */
- (void)_toggleExportButton:(id)uiStateDict
{
	@autoreleasepool {
		BOOL enable = NO;

		BOOL isSQL  = (exportType == SPSQLExport);
		BOOL isCSV  = (exportType == SPCSVExport);
		BOOL isXML  = (exportType == SPXMLExport);
		BOOL isHTML = (exportType == SPHTMLExport);
		BOOL isPDF  = (exportType == SPPDFExport);

		BOOL structureEnabled = [[uiStateDict objectForKey:SPSQLExportStructureEnabled] boolValue];
		BOOL contentEnabled   = [[uiStateDict objectForKey:SPSQLExportContentEnabled] boolValue];
		BOOL dropEnabled      = [[uiStateDict objectForKey:SPSQLExportDropEnabled] boolValue];

		if (isCSV || isXML || isHTML || isPDF || (isSQL && ((!structureEnabled) || (!dropEnabled)))) {
			enable = NO;

			// Only enable the button if at least one table is selected
			for (NSArray *table in tables)
			{
				if ([[table safeObjectAtIndex:2] boolValue]) {
					enable = YES;
					break;
				}
			}
		}
		else if (isSQL) {

			// Disable if all are unchecked
			if ((!contentEnabled) && (!structureEnabled) && (!dropEnabled)) {
				enable = NO;
			}
				// If they are all checked, check to see if any of the tables are checked
			else if (contentEnabled && structureEnabled && dropEnabled) {

				// Only enable the button if at least one table is selected
				for (NSArray *table in tables)
				{
					if ([[table safeObjectAtIndex:1] boolValue] ||
						[[table safeObjectAtIndex:2] boolValue] ||
						[[table safeObjectAtIndex:3] boolValue])
					{
						enable = YES;
						break;
					}
				}
			}
				// Disable if structure is unchecked, but content and drop are as dropping a
				// table then trying to insert into it is obviously an error.
			else if (contentEnabled && (!structureEnabled) && (dropEnabled)) {
				enable = NO;
			}
			else {
				enable = (contentEnabled || (structureEnabled || dropEnabled));
			}
		}

		[self performSelectorOnMainThread:@selector(_toggleExportButtonWithBool:) withObject:@(enable) waitUntilDone:NO];
	}
}

/**
 * Calls the above method on a background thread to determine whether or not the export button should be enabled.
 */
- (void)_toggleExportButtonOnBackgroundThread
{
	NSMutableDictionary *uiStateDict = [[NSMutableDictionary alloc] init];
		
	[uiStateDict setObject:[NSNumber numberWithInteger:[exportSQLIncludeStructureCheck state]] forKey:SPSQLExportStructureEnabled];
	[uiStateDict setObject:[NSNumber numberWithInteger:[exportSQLIncludeContentCheck state]] forKey:SPSQLExportContentEnabled];
	[uiStateDict setObject:[NSNumber numberWithInteger:[exportSQLIncludeDropSyntaxCheck state]] forKey:SPSQLExportDropEnabled];

	[NSThread detachNewThreadWithName:SPCtxt(@"SPExportController export button updater",tableDocumentInstance) target:self selector:@selector(_toggleExportButton:) object:uiStateDict];
}

/**
 * Enables or disables the export button based on the supplied number (boolean).
 *
 * @param enable A boolean indicating the state.
 */
- (void)_toggleExportButtonWithBool:(NSNumber *)enable
{
	[exportButton setEnabled:[enable boolValue]];
}

#pragma mark - SPExportInitializer

/**
 * Starts the export process by placing the first exporter on the operation queue. Also opens the progress
 * sheet if it's not already visible.
 */
- (void)startExport
{
	self.startTime = [NSDate date];
	// Start progress indicator
	[exportProgressTitle setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Exporting %@", @"text showing that the application is importing a supplied format"), exportTypeLabel]];
	[exportProgressText setStringValue:NSLocalizedString(@"Writing...", @"text showing that app is writing text file")];

	[exportProgressIndicator setUsesThreadedAnimation:NO];
	[exportProgressIndicator setIndeterminate:NO];
	[exportProgressIndicator setDoubleValue:0];

	// If it's not already displayed, open the progress sheet
	if (![exportProgressWindow isVisible]) {
		[[tableDocumentInstance parentWindowControllerWindow] beginSheet:exportProgressWindow completionHandler:nil];
	}

	// cache the current connection encoding so the exporter can do what it wants.
	previousConnectionEncoding = [[NSString alloc] initWithString:[connection encoding]];
	previousConnectionEncodingViaLatin1 = [connection encodingUsesLatin1Transport];

	// Add the first exporter to the operation queue
	[operationQueue addOperation:[exporters firstObject]];

	// Remove the exporter we just added to the operation queue from our list of exporters
	// so we know it's already been done.
	[exporters safeRemoveObjectAtIndex:0];
}

/**
 * @see _queueIsEmptyAfterCancelling:
 */
- (void)exportEnded
{
    SPLog(@"Time to export: %f", -[startTime timeIntervalSinceNow]);
	// if the export was really quick
	if((-[startTime timeIntervalSinceNow]) < 2){
		// give the user a second to see the progress
        SPLog(@"give the user a second to see the progress");
		[self performSelector:@selector(_hideExportProgress) withObject:nil afterDelay:1.0];
	}
	else{
		SPLog(@"hide instantly");
		[self _hideExportProgress];
	}
	
	// Restore query mode
	[tableDocumentInstance setQueryMode:SPInterfaceQueryMode];

	// Display export finished notification
	[self displayExportFinishedNotification];

	// Restore the connection encoding to it's pre-export value
	[tableDocumentInstance setConnectionEncoding:[NSString stringWithFormat:@"%@%@", previousConnectionEncoding, (previousConnectionEncodingViaLatin1) ? @"-" : @""] reloadingViews:NO];
}

/**
 * Initializes the export process by analysing the selected criteria.
 */
- (void)initializeExportUsingSelectedOptions
{
	NSArray *dataArray = nil;

	// Get rid of the cached connection encoding


	createCustomFilename = ([[exportCustomFilenameTokenField stringValue] length] > 0);

	NSMutableArray *exportTables = [NSMutableArray array];

	// Set whether or not we are to export to multiple files
	[self setExportToMultipleFiles:[exportFilePerTableCheck state]];

	// Get the data depending on the source
	switch (exportSource)
	{
		case SPFilteredExport:
			dataArray = [tableContentInstance currentDataResultWithNULLs:YES hideBLOBs:NO];
			break;
		case SPQueryExport:
			dataArray = [customQueryInstance currentDataResultWithNULLs:YES truncateDataFields:NO];
			break;
		case SPTableExport:
			// Create an array of tables to export
			for (NSMutableArray *table in tables)
			{
				if (exportType == SPSQLExport) {
					if ([[table safeObjectAtIndex:1] boolValue] || [[table safeObjectAtIndex:2] boolValue] || [[table safeObjectAtIndex:3] boolValue]) {

						// Check the overall export settings
						if ([[table safeObjectAtIndex:1] boolValue] && (![exportSQLIncludeStructureCheck state])) {
							[table safeReplaceObjectAtIndex:1 withObject:@NO];
						}

						if ([[table safeObjectAtIndex:2] boolValue] && (![exportSQLIncludeContentCheck state])) {
							[table safeReplaceObjectAtIndex:2 withObject:@NO];
						}

						if ([[table safeObjectAtIndex:3] boolValue] && (![exportSQLIncludeDropSyntaxCheck state])) {
							[table safeReplaceObjectAtIndex:3 withObject:@NO];
						}

						[exportTables safeAddObject:table];
					}
				}
				else if (exportType == SPDotExport) {
					[exportTables safeAddObject:[table firstObject]];
				}
				else {
					if ([[table safeObjectAtIndex:2] boolValue]) {
						[exportTables safeAddObject:[table firstObject]];
					}
				}
			}

			break;
	}

	// Set the export type label
	switch (exportType)
	{
		case SPSQLExport:
			exportTypeLabel = @"SQL";
			break;
		case SPCSVExport:
			exportTypeLabel = @"CSV";
			break;
		case SPXMLExport:
			exportTypeLabel = @"XML";
			break;
		case SPDotExport:
			exportTypeLabel = @"Dot";
			break;
		case SPPDFExport:
		case SPHTMLExport:
		case SPExcelExport:
		default:
			[NSException raise:NSInvalidArgumentException format:@"unsupported exportType=%lu",exportType];
			return;
	}

	// Begin the export based on the source
	switch (exportSource)
	{
		case SPFilteredExport:
		case SPQueryExport:
			[self exportTables:nil orDataArray:dataArray];
			break;
		case SPTableExport:
			[self exportTables:exportTables orDataArray:nil];
			break;
	}
}

/**
 * Exports the contents of the supplied array of tables or data array.
 *
 * Note that at least one of these parameters must not be nil.
 *
 * @param exportTables An array of table/view names to be exported (can be nil).
 * @param dataArray    A MySQL result set array to be exported (can be nil).
 */
- (void)exportTables:(NSArray *)exportTables orDataArray:(NSArray *)dataArray
{
	BOOL singleFileHandleSet = NO;
	SPExportFile *singleExportFile = nil, *file = nil;

	// Change query logging mode
	[tableDocumentInstance setQueryMode:SPImportExportQueryMode];

	// Setup the progress sheet
	[exportProgressTitle setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Exporting %@", @"text showing that the application is importing a supplied format"), exportTypeLabel]];
	[exportProgressText setStringValue:NSLocalizedString(@"Initializing...", @"initializing export label")];

	[exportProgressIndicator setIndeterminate:YES];
	[exportProgressIndicator setUsesThreadedAnimation:YES];

	// Open the progress sheet
	[[tableDocumentInstance parentWindowControllerWindow] beginSheet:exportProgressWindow completionHandler:nil];

	// CSV export
	if (exportType == SPCSVExport) {

		SPCSVExporter *csvExporter = nil;

		// If the user has selected to only export to a single file or this is a filtered or custom query
		// export, create the single file now and assign it to all subsequently created exporters.
		if ((![self exportToMultipleFiles]) || (exportSource == SPFilteredExport) || (exportSource == SPQueryExport)) {
			NSString *selectedTableName = nil;

			if (exportSource == SPTableExport && [exportTables count] == 1) selectedTableName = [exportTables firstObject];

			[exportFilename setString:createCustomFilename ? [self expandCustomFilenameFormatUsingTableName:selectedTableName] : [self generateDefaultExportFilename]];

			// Only append the extension if necessary
			if (![[exportFilename pathExtension] length]) {
				[exportFilename setString:[exportFilename stringByAppendingPathExtension:[self currentDefaultExportFileExtension]]];
			}

			singleExportFile = [SPExportFile exportFileAtPath:[[exportPathField stringValue] stringByAppendingPathComponent:exportFilename]];
		}

		// Start the export process depending on the data source
		if (exportSource == SPTableExport) {

			// Cache the number of tables being exported
			exportTableCount = [exportTables count];

			// Loop through the tables, creating an exporter for each
			for (NSString *table in exportTables)
			{
				csvExporter = [self initializeCSVExporterForTable:table orDataArray:nil];

				// If required create a single file handle for all CSV exports
				if (![self exportToMultipleFiles]) {
					if (!singleFileHandleSet) {
						[singleExportFile setExportFileNeedsCSVHeader:YES];

						[exportFiles safeAddObject:singleExportFile];

						singleFileHandleSet = YES;
					}

					[csvExporter setExportOutputFile:singleExportFile];
				}

				[exporters addObject:csvExporter];
			}
		}
		else {
			csvExporter = [self initializeCSVExporterForTable:nil orDataArray:dataArray];

			[exportFiles safeAddObject:singleExportFile];

			[csvExporter setExportOutputFile:singleExportFile];

			[exporters safeAddObject:csvExporter];
		}
	}
	// SQL export
	else if (exportType == SPSQLExport) {

		// Cache the number of tables being exported
		exportTableCount = [exportTables count];

		SPSQLExporter *sqlExporter = [[SPSQLExporter alloc] initWithDelegate:self];

		[sqlExporter setSqlDatabaseHost:[tableDocumentInstance host]];
		[sqlExporter setSqlDatabaseName:[tableDocumentInstance database]];
		[sqlExporter setSqlDatabaseVersion:[tableDocumentInstance mySQLVersion]];

		[sqlExporter setSqlOutputIncludeUTF8BOM:[exportUseUTF8BOMButton state]];
		[sqlExporter setSqlOutputEncodeBLOBasHex:[exportSQLBLOBFieldsAsHexCheck state]];
		[sqlExporter setSqlOutputIncludeErrors:[exportSQLIncludeErrorsCheck state]];
		[sqlExporter setSqlOutputIncludeAutoIncrement:([exportSQLIncludeStructureCheck state] && [exportSQLIncludeAutoIncrementValueButton state])];
        [sqlExporter setSqlOutputIncludeGeneratedColumns:[exportSQLIncludeGeneratedColumnsCheck state]];

		[sqlExporter setSqlInsertAfterNValue:[exportSQLInsertNValueTextField integerValue]];
		[sqlExporter setSqlInsertDivider:[exportSQLInsertDividerPopUpButton indexOfSelectedItem]];

		[sqlExporter setSqlExportTables:exportTables];

		// Create custom filename if required
		NSString *selectedTableName = (exportSource == SPTableExport && [exportTables count] == 1)? [[exportTables firstObject] firstObject] : nil;
		[exportFilename setString:(createCustomFilename) ? [self expandCustomFilenameFormatUsingTableName:selectedTableName] : [self generateDefaultExportFilename]];

		// Only append the extension if necessary
		if (![[exportFilename pathExtension] length]) {
			[exportFilename setString:[exportFilename stringByAppendingPathExtension:[self currentDefaultExportFileExtension]]];
		}

		file = [SPExportFile exportFileAtPath:[[exportPathField stringValue] stringByAppendingPathComponent:exportFilename]];

		[exportFiles addObject:file];

		[sqlExporter setExportOutputFile:file];

		[exporters addObject:sqlExporter];
	}
	// XML export
	else if (exportType == SPXMLExport) {

		SPXMLExporter *xmlExporter = nil;

		// If the user has selected to only export to a single file or this is a filtered or custom query
		// export, create the single file now and assign it to all subsequently created exporters.
		if ((![self exportToMultipleFiles]) || (exportSource == SPFilteredExport) || (exportSource == SPQueryExport)) {
			NSString *selectedTableName = nil;
			if (exportSource == SPTableExport && [exportTables count] == 1) selectedTableName = [exportTables firstObject];

			[exportFilename setString:(createCustomFilename) ? [self expandCustomFilenameFormatUsingTableName:selectedTableName] : [self generateDefaultExportFilename]];

			// Only append the extension if necessary
			if (![[exportFilename pathExtension] length]) {
				[exportFilename setString:[exportFilename stringByAppendingPathExtension:[self currentDefaultExportFileExtension]]];
			}

			singleExportFile = [SPExportFile exportFileAtPath:[[exportPathField stringValue] stringByAppendingPathComponent:exportFilename]];
		}

		// Start the export process depending on the data source
		if (exportSource == SPTableExport) {

			// Cache the number of tables being exported
			exportTableCount = [exportTables count];

			// Loop through the tables, creating an exporter for each
			for (NSString *table in exportTables)
			{
				xmlExporter = [self initializeXMLExporterForTable:table orDataArray:nil];

				// If required create a single file handle for all XML exports
				if (![self exportToMultipleFiles]) {
					if (!singleFileHandleSet) {
						[singleExportFile setExportFileNeedsXMLHeader:YES];

						[exportFiles safeAddObject:singleExportFile];

						singleFileHandleSet = YES;
					}

					[xmlExporter setExportOutputFile:singleExportFile];
				}

				[exporters addObject:xmlExporter];
			}
		}
		else {
			xmlExporter = [self initializeXMLExporterForTable:nil orDataArray:dataArray];

			[singleExportFile setExportFileNeedsXMLHeader:YES];

			[exportFiles safeAddObject:singleExportFile];

			[xmlExporter setExportOutputFile:singleExportFile];

			[exporters safeAddObject:xmlExporter];
		}
	}
	// Dot export
	else if (exportType == SPDotExport) {

		// Cache the number of tables being exported
		exportTableCount = [exportTables count];

		SPDotExporter *dotExporter = [[SPDotExporter alloc] initWithDelegate:self];

		[dotExporter setDotTableData:tableDataInstance];
		[dotExporter setDotForceLowerTableNames:[exportDotForceLowerTableNamesCheck state]];
		[dotExporter setDotDatabaseHost:[tableDocumentInstance host]];
		[dotExporter setDotDatabaseName:[tableDocumentInstance database]];
		[dotExporter setDotDatabaseVersion:[tableDocumentInstance mySQLVersion]];

		[dotExporter setDotExportTables:exportTables];

		// Create custom filename if required
		if (createCustomFilename) {
			[exportFilename setString:[self expandCustomFilenameFormatUsingTableName:nil]];
		}
		else {
			[exportFilename setString:[tableDocumentInstance database]];
		}

		// Only append the extension if necessary
		if (![[exportFilename pathExtension] length]) {
			[exportFilename setString:[exportFilename stringByAppendingPathExtension:[self currentDefaultExportFileExtension]]];
		}

		file = [SPExportFile exportFileAtPath:[[exportPathField stringValue] stringByAppendingPathComponent:exportFilename]];

		[exportFiles addObject:file];

		[dotExporter setExportOutputFile:file];

		[exporters addObject:dotExporter];
	}

	// For each of the created exporters, set their generic properties
	for (SPExporter *exporter in exporters)
	{
		[exporter setConnection:connection];
		[exporter setServerSupport:[self serverSupport]];
		[exporter setExportOutputEncoding:[connection stringEncoding]];
		[exporter setExportMaxProgress:(NSInteger)[exportProgressIndicator bounds].size.width];
		[exporter setExportUsingLowMemoryBlockingStreaming:([exportProcessLowMemoryButton state] == NSOnState)];
		[exporter setExportOutputCompressionFormat:(SPFileCompressionFormat)[exportOutputCompressionFormatPopupButton indexOfSelectedItem]];
		[exporter setExportOutputCompressFile:([exportOutputCompressionFormatPopupButton indexOfSelectedItem] != SPNoCompression)];
	}

	NSMutableArray *problemFiles = [[NSMutableArray alloc] init];

	// Create the actual file handles while dealing with errors (e.g. file already exists, etc) during creation
	for (SPExportFile *exportFile in exportFiles)
	{
		if ([exportFile createExportFileHandle:NO] == SPExportFileHandleCreated) {

			[exportFile setCompressionFormat:(SPFileCompressionFormat)[exportOutputCompressionFormatPopupButton indexOfSelectedItem]];

			if ([exportFile exportFileNeedsCSVHeader]) {
				[self writeCSVHeaderToExportFile:exportFile];
			}
			else if ([exportFile exportFileNeedsXMLHeader]) {
				[self writeXMLHeaderToExportFile:exportFile];
			}
		}
		else {
			[problemFiles addObject:exportFile];
		}

		// This checks if the user has chosen a location and not just clicked export
		// actually I think exportFile.exportFilePath.length will always be > 0
		// might remove that condition
		if(exportFile.exportFilePath.length == 0 || exportFile.exportFilePath.pathComponents.count < 2 ){
			[exportFile setExportFileNeedsUserChosenDir:YES];
			[problemFiles addObject:exportFile];
		}
	}

	// Deal with any file handles that we failed to create for whatever reason
	if ([problemFiles count] > 0) {
		[self errorCreatingExportFileHandles:problemFiles];
	}
	else {
		[self startExport];
	}
}

/**
 * Initialises a CSV exporter for the supplied table name or data array.
 *
 * @param table     The table name for which the exporter should be cerated for (can be nil).
 * @param dataArray The MySQL result data array for which the exporter should be created for (can be nil).
 */
- (SPCSVExporter *)initializeCSVExporterForTable:(NSString *)table orDataArray:(NSArray *)dataArray
{
	SPCSVExporter *csvExporter = [[SPCSVExporter alloc] initWithDelegate:self];

	// Depeding on the export source, set the table name or data array
	if (exportSource == SPTableExport) {
		[csvExporter setCsvTableName:table];
	}
	else {
		[csvExporter setCsvDataArray:dataArray];
	}

	[csvExporter setCsvTableData:tableDataInstance];
	[csvExporter setCsvOutputFieldNames:[exportCSVIncludeFieldNamesCheck state]];
	[csvExporter setCsvFieldSeparatorString:[exportCSVFieldsTerminatedField stringValue]];
	[csvExporter setCsvEnclosingCharacterString:[exportCSVFieldsWrappedField stringValue]];
	[csvExporter setCsvLineEndingString:[exportCSVLinesTerminatedField stringValue]];
	[csvExporter setCsvEscapeString:[exportCSVFieldsEscapedField stringValue]];
	[csvExporter setCsvNULLString:[exportCSVNULLValuesAsTextField stringValue]];

	// If required create separate files
	if (exportSource == SPTableExport && [self exportToMultipleFiles]) {

		if (createCustomFilename) {

			// Create custom filename based on the selected format
			[exportFilename setString:[self expandCustomFilenameFormatUsingTableName:table]];

			// If the user chose to use a custom filename format and we exporting to multiple files, make
			// sure the table name is included to ensure the output files are unique.
			if (exportTableCount > 1) {
				BOOL tableNameInTokens = NO;
				NSArray *representedObjects = [exportCustomFilenameTokenField objectValue];
				for (id representedObject in representedObjects) {
					if ([representedObject isKindOfClass:[SPExportFileNameTokenObject class]] && [[representedObject tokenId] isEqualToString:SPFileNameTableTokenName]) tableNameInTokens = YES;
				}
				[exportFilename setString:(tableNameInTokens ? exportFilename : [exportFilename stringByAppendingFormat:@"_%@", table])];
			}
		}
		else {
			[exportFilename setString:(dataArray) ? [tableDocumentInstance database] : table];
		}

		// Only append the extension if necessary
		if (![[exportFilename pathExtension] length]) {
			[exportFilename setString:[exportFilename stringByAppendingPathExtension:[self currentDefaultExportFileExtension]]];
		}

		SPExportFile *file = [SPExportFile exportFileAtPath:[[exportPathField stringValue] stringByAppendingPathComponent:exportFilename]];

		[exportFiles addObject:file];

		[csvExporter setExportOutputFile:file];
	}

	return csvExporter;
}

/**
 * Initialises a XML exporter for the supplied table name or data array.
 *
 * @param table     The table name for which the exporter should be cerated for (can be nil).
 * @param dataArray The MySQL result data array for which the exporter should be created for (can be nil).
 */
- (SPXMLExporter *)initializeXMLExporterForTable:(NSString *)table orDataArray:(NSArray *)dataArray
{
	SPXMLExporter *xmlExporter = [[SPXMLExporter alloc] initWithDelegate:self];

	// if required set the data array
	if (exportSource != SPTableExport) {
		[xmlExporter setXmlDataArray:dataArray];
	}

	// Regardless of the export source, set exporter's table name as it's used in the output
	// of table and table content exports.
	[xmlExporter setXmlTableName:table];

	[xmlExporter setXmlFormat:[exportXMLFormatPopUpButton indexOfSelectedItem]];
	[xmlExporter setXmlOutputIncludeStructure:[exportXMLIncludeStructure state]];
	[xmlExporter setXmlOutputIncludeContent:[exportXMLIncludeContent state]];
	[xmlExporter setXmlNULLString:[exportXMLNULLValuesAsTextField stringValue]];

	// If required create separate files
	if ((exportSource == SPTableExport) && exportToMultipleFiles && (exportTableCount > 0)) {

		if (createCustomFilename) {

			// Create custom filename based on the selected format
			[exportFilename setString:[self expandCustomFilenameFormatUsingTableName:table]];

			// If the user chose to use a custom filename format and we exporting to multiple files, make
			// sure the table name is included to ensure the output files are unique.
			if (exportTableCount > 1) {
				BOOL tableNameInTokens = NO;
				NSArray *representedObjects = [exportCustomFilenameTokenField objectValue];
				for (id representedObject in representedObjects) {
					if ([representedObject isKindOfClass:[SPExportFileNameTokenObject class]] && [[representedObject tokenId] isEqualToString:SPFileNameTableTokenName]) tableNameInTokens = YES;
				}
				[exportFilename setString:(tableNameInTokens ? exportFilename : [exportFilename stringByAppendingFormat:@"_%@", table])];
			}
		}
		else {
			[exportFilename setString:(dataArray) ? [tableDocumentInstance database] : table];
		}

		// Only append the extension if necessary
		if (![[exportFilename pathExtension] length]) {
			[exportFilename setString:[exportFilename stringByAppendingPathExtension:[self currentDefaultExportFileExtension]]];
		}

		SPExportFile *file = [SPExportFile exportFileAtPath:[[exportPathField stringValue] stringByAppendingPathComponent:exportFilename]];

		[file setExportFileNeedsXMLHeader:YES];

		[exportFiles addObject:file];

		[xmlExporter setExportOutputFile:file];
	}

	return xmlExporter;
}

#pragma mark - SPExportFileUtilitiesPrivateAPI

/**
 * Writes the CSV file header to the supplied export file.
 *
 * @param file The export file to write the header to.
 */
- (void)writeCSVHeaderToExportFile:(SPExportFile *)file
{
	NSMutableString *lineEnding = [NSMutableString stringWithString:[exportCSVLinesTerminatedField stringValue]];

	// Escape tabs, line endings and carriage returns
	[lineEnding replaceOccurrencesOfString:@"\\t" withString:@"\t"
								   options:NSLiteralSearch
									 range:NSMakeRange(0, [lineEnding length])];

	[lineEnding replaceOccurrencesOfString:@"\\n" withString:@"\n"
								   options:NSLiteralSearch
									 range:NSMakeRange(0, [lineEnding length])];

	[lineEnding replaceOccurrencesOfString:@"\\r" withString:@"\r"
								   options:NSLiteralSearch
									 range:NSMakeRange(0, [lineEnding length])];

	// Write the file header and the first table name
	[file writeData:[[NSMutableString stringWithFormat:@"%@: %@   %@: %@    %@: %@%@%@%@ %@%@%@",
					  NSLocalizedString(@"Host", @"export header host label"),
					  [tableDocumentInstance host],
					  NSLocalizedString(@"Database", @"export header database label"),
					  [tableDocumentInstance database],
					  NSLocalizedString(@"Generation Time", @"export header generation time label"),
					  [NSDate date],
					  lineEnding,
					  lineEnding,
					  NSLocalizedString(@"Table", @"csv export table heading"),
					  [[tables firstObject] firstObject],
					  lineEnding,
					  lineEnding] dataUsingEncoding:[connection stringEncoding]]];
}

/**
 * Writes the XML file header to the supplied export file.
 *
 * @param file The export file to write the header to.
 */
- (void)writeXMLHeaderToExportFile:(SPExportFile *)file
{
	NSMutableString *header = [NSMutableString string];

	[header setString:@"<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n\n"];
	[header appendString:@"<!--\n-\n"];
	[header appendString:@"- Sequel Ace XML dump\n"];
	[header appendFormat:@"- %@ %@\n-\n", NSLocalizedString(@"Version", @"export header version label"), [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
	[header appendFormat:@"- %@\n- %@\n-\n", SPLOCALIZEDURL_HOMEPAGE, SPDevURL];
	[header appendFormat:@"- %@: %@ (MySQL %@)\n", NSLocalizedString(@"Host", @"export header host label"), [tableDocumentInstance host], [tableDocumentInstance mySQLVersion]];
	[header appendFormat:@"- %@: %@\n", NSLocalizedString(@"Database", @"export header database label"), [tableDocumentInstance database]];
	[header appendFormat:@"- %@ Time: %@\n", NSLocalizedString(@"Generation Time", @"export header generation time label"), [NSDate date]];
	[header appendString:@"-\n-->\n\n"];

	if ([exportXMLFormatPopUpButton indexOfSelectedItem] == SPXMLExportMySQLFormat) {

		NSString *tag;

		if (exportSource == SPTableExport) {
			tag = [NSString stringWithFormat:@"<mysqldump xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">\n<database name=\"%@\">\n\n", [tableDocumentInstance database]];
		}
		else {
			tag = [NSString stringWithFormat:@"<resultset statement=\"%@\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">\n\n", (exportSource == SPFilteredExport) ? [tableContentInstance usedQuery] : [customQueryInstance usedQuery]];
		}

		[header appendString:tag];
	}
	else {
		[header appendFormat:@"<%@>\n\n", [[tableDocumentInstance database] HTMLEscapeString]];
	}

	[file writeData:[header dataUsingEncoding:NSUTF8StringEncoding]];
}

/**
 * Indicates that one or more errors occurred while attempting to create the export file handles. Asks the
 * user how to proceed.
 *
 * @param files An array of export files (SPExportFile) that failed to be created.
 */
- (void)errorCreatingExportFileHandles:(NSArray *)files
{
	// We don't know where "files" came from, but we know 2 things:
	// - NSAlert will NOT retain it as contextInfo
	// - This method continues execution after [alert beginSheet:...], thus even if files was retained before, it could be released before the alert ends

	// Get the number of files that already exist as well as couldn't be created because of other reasons
	NSUInteger filesAlreadyExisting = 0;
	NSUInteger parentFoldersMissing = 0;
	NSUInteger parentFoldersNotWritable = 0;
	NSUInteger filesFailed = 0;
	NSUInteger noExportDirChosen = 0;

	for (SPExportFile *file in files)
	{
		if (file.exportFileNeedsUserChosenDir == YES){
			noExportDirChosen++;
			filesFailed++;
		}
		else if ([file exportFileHandleStatus] == SPExportFileHandleExists) {
			filesAlreadyExisting++;
		}
		// For file handles that we failed to create for some unknown reason, ignore them and remove any
		// exporters that are associated with them.
		else if ([file exportFileHandleStatus] == SPExportFileHandleFailed) {

			filesFailed++;

			NSMutableArray *exportersToRemove = [[NSMutableArray alloc] init];

			for (SPExporter *exporter in exporters)
			{
				if ([[exporter exportOutputFile] isEqualTo:file]) {
					[exportersToRemove addObject:exporter];
				}
			}

			[exporters removeObjectsInArray:exportersToRemove];

			// Check the parent folder to see if it still is present
			BOOL parentIsFolder = NO;
			if (![[NSFileManager defaultManager] fileExistsAtPath:[[[file exportFilePath] stringByDeletingLastPathComponent] stringByExpandingTildeInPath] isDirectory:&parentIsFolder] || !parentIsFolder) {
				parentFoldersMissing++;
			} else if (![[NSFileManager defaultManager] isWritableFileAtPath:[[[file exportFilePath] stringByDeletingLastPathComponent] stringByExpandingTildeInPath]]) {
				parentFoldersNotWritable++;
			}
		}
	}

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setAlertStyle:NSAlertStyleCritical];

	// If files failed because they already existed, show a OS-like dialog.
	if (filesAlreadyExisting) {

		// Set up a string for use if files had to be skipped.
		NSString *additionalErrors = filesFailed ? NSLocalizedString(@"\n\n(In addition, one or more errors occurred while attempting to create the export files: %lu could not be created. These files will be ignored.)", @"Additional export file errors") : @"";

		if (filesAlreadyExisting == 1) {
			[alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"“%@” already exists. Do you want to replace it?", @"Export file already exists message"), [[[files firstObject] exportFilePath] lastPathComponent]]];
			[alert setInformativeText:[NSString stringWithFormat:@"%@%@", NSLocalizedString(@"A file with the same name already exists in the target folder. Replacing it will overwrite its current contents.", @"Export file already exists explanatory text"), additionalErrors]];
		}
		else if (filesAlreadyExisting == [exportFiles count]) {
			[alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"All the export files already exist. Do you want to replace them?", @"All export files already exist message")]];
			[alert setInformativeText:[NSString stringWithFormat:@"%@%@", NSLocalizedString(@"Files with the same names already exist in the target folder. Replacing them will overwrite their current contents.", @"All export files already exist explanatory text"), additionalErrors]];
		}
		else {
			[alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"%lu files already exist. Do you want to replace them?", @"Export file already exists message"), filesAlreadyExisting]];
			[alert setInformativeText:[NSString stringWithFormat:@"%@%@", [NSString stringWithFormat:NSLocalizedString(@"%lu files with the same names already exist in the target folder. Replacing them will overwrite their current contents.", @"Some export files already exist explanatory text"), filesAlreadyExisting], additionalErrors]];
		}

		[alert addButtonWithTitle:NSLocalizedString(@"Replace", @"Replace button")];
		[[[alert buttons] objectAtIndex:0] setTag:SPExportErrorReplaceFiles];
		[[[alert buttons] objectAtIndex:0] setKeyEquivalent:@"r"];
		[[[alert buttons] objectAtIndex:0] setKeyEquivalentModifierMask:NSEventModifierFlagCommand];

		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"cancel button")];
		[[[alert buttons] objectAtIndex:1] setTag:SPExportErrorCancelExport];
		[[[alert buttons] objectAtIndex:1] setKeyEquivalent:@"\r"];

		if ((filesAlreadyExisting + filesFailed) != [exportFiles count]) {
			[alert addButtonWithTitle:NSLocalizedString(@"Skip existing", @"skip existing button")];
			[[[alert buttons] objectAtIndex:2] setTag:SPExportErrorSkipErrorFiles];
			[[[alert buttons] objectAtIndex:2] setKeyEquivalent:@"s"];
			[[[alert buttons] objectAtIndex:2] setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
		}
	}
	// If one or multiple files failed, but only due to unhandled errors, show a short dialog
	else {
		if (filesFailed == 1) {
			[alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"“%@” could not be created", @"Export file creation error title"), [[[files firstObject] exportFilePath] lastPathComponent]]];
			if (parentFoldersMissing) {
				[alert setInformativeText:NSLocalizedString(@"The target export folder no longer exists.  Please select a new export location and try again.", @"Export folder missing explanatory text")];
			} else if (parentFoldersNotWritable) {
				[alert setInformativeText:NSLocalizedString(@"The target export folder is not writable.  Please select a new export location and try again.", @"Export folder not writable explanatory text")];
			}
			else if (noExportDirChosen) {
				[alert setInformativeText:NSLocalizedString(@"No directory selected.  Please select a new export location and try again.", @"Export folder not chosen by user")];
			}
			else {
				[alert setInformativeText:NSLocalizedString(@"An unhandled error occurred when attempting to create the export file.  Please check the details and try again.", @"Export file creation error explanatory text")];
			}
		}
		else if (filesFailed == [exportFiles count]) {
			[alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"No files could be created", @"All export files creation error title")]];
			if (parentFoldersMissing == [exportFiles count]) {
				[alert setInformativeText:NSLocalizedString(@"The target export folder no longer exists.  Please select a new export location and try again.", @"Export folder missing explanatory text")];
			} else if (parentFoldersMissing) {
				[alert setInformativeText:NSLocalizedString(@"Some of the target export folders no longer exist.  Please select a new export location and try again.", @"Some export folders missing explanatory text")];
			} else if (parentFoldersNotWritable) {
				[alert setInformativeText:NSLocalizedString(@"Some of the target export folders are not writable.  Please select a new export location and try again.", @"Some export folders not writable explanatory text")];
			} else {
				[alert setInformativeText:NSLocalizedString(@"An unhandled error occurred when attempting to create each of the export files.  Please check the details and try again.", @"All export files creation error explanatory text")];
			}
		}
		else {
			[alert setMessageText:[NSString stringWithFormat:NSLocalizedString(@"%lu files could not be created", @"Export files creation error title"), filesFailed]];
			if (parentFoldersMissing) {
				[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"%lu of the export files could not be created because their target export folder no longer exists; please select a new export location and try again.", @"Export folder missing for some files explanatory text"), parentFoldersMissing]];
			} else if (parentFoldersNotWritable) {
				[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"%lu of the export files could not be created because their target export folder is not writable; please select a new export location and try again.", @"Export folder not writable for some files explanatory text"), parentFoldersNotWritable]];
			} else {
				[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"An unhandled error occurred when attempting to create %lu of the export files.  Please check the details and try again.", @"Export files creation error explanatory text"), filesFailed]];
			}
		}

		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"cancel button")];
		[[[alert buttons] objectAtIndex:0] setTag:SPExportErrorCancelExport];

		if (filesFailed != [exportFiles count]) {
			[alert addButtonWithTitle:NSLocalizedString(@"Skip problems", @"skip problems button")];
			[[[alert buttons] objectAtIndex:1] setTag:SPExportErrorSkipErrorFiles];
			[[[alert buttons] objectAtIndex:1] setKeyEquivalent:@"s"];
			[[[alert buttons] objectAtIndex:1] setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
		}
	}

	[self _hideExportProgress];

	NSInteger returnCode = [alert runModal];

	// Ignore the files that exist and remove the associated exporters
	if (returnCode == SPExportErrorSkipErrorFiles) {

		for (SPExportFile *file in files) {

			// Use a numerically controlled loop to avoid mutating the collection while enumerating
			NSUInteger i;
			for (i = 0; i < [exporters count]; i++) {
				SPExporter *exporter = [exporters safeObjectAtIndex:i];
				if ([[exporter exportOutputFile] isEqualTo:file]) {
					[exporters safeRemoveObjectAtIndex:i];
					i--;
				}
			}
		}

		// If we're now left with no exporters, cancel the export operation
		if ([exporters count] == 0) {
			[exportFiles removeAllObjects];

			// Trigger restoration of the export interface
			[self performSelector:@selector(_reopenExportSheet) withObject:nil afterDelay:0.1];
		}
		else {
			// Start the export after a short delay to give this sheet a chance to close
			[self performSelector:@selector(startExport) withObject:nil afterDelay:0.1];
		}
	}
	// Overwrite the files and continue
	else if (returnCode == SPExportErrorReplaceFiles) {

		for (SPExportFile *file in files)
		{
			if ([file exportFileHandleStatus] == SPExportFileHandleExists) {

				if ([file createExportFileHandle:YES] == SPExportFileHandleCreated) {
					[file setCompressionFormat:(SPFileCompressionFormat)[exportOutputCompressionFormatPopupButton indexOfSelectedItem]];

					if ([file exportFileNeedsCSVHeader]) {
						[self writeCSVHeaderToExportFile:file];
					}
					else if ([file exportFileNeedsXMLHeader]) {
						[self writeXMLHeaderToExportFile:file];
					}
				}
			}
		}

		// Start the export after a short delay to give this sheet a chance to close
		[self performSelector:@selector(startExport) withObject:nil afterDelay:0.1];

	}
	// Cancel the entire export operation
	else if (returnCode == SPExportErrorCancelExport) {

		// Loop the cached export files and remove those we've already created
		for (SPExportFile *file in exportFiles)
		{
			[file delete];
		}

		// Finally get rid of all the exporters and files
		[exportFiles removeAllObjects];
		[exporters removeAllObjects];

		// Trigger restoration of the export interface
		[self performSelector:@selector(_reopenExportSheet) withObject:nil afterDelay:0.1];
	}
}

/**
 * Re-open the export sheet without resetting the interface - for use on error.
 */
- (void)_reopenExportSheet {
	[[tableDocumentInstance parentWindowControllerWindow] beginSheet:self.window completionHandler:nil];
}

#pragma mark - SPExportFilenameUtilities

/**
 * Updates the displayed export filename, either custom or default.
 */
- (void)updateDisplayedExportFilename
{
	NSString *filename  = @"";

	if ([[exportCustomFilenameTokenField stringValue] length] > 0) {

		// Get the current export file extension
		NSString *extension = [self currentDefaultExportFileExtension];

		//note that there will be no tableName if the export is done from a query result without a database selected (or empty).
		filename = [self expandCustomFilenameFormatUsingTableName:[[tablesListInstance tables] safeObjectAtIndex:1]];

		if (![[self customFilenamePathExtension] length] && [extension length] > 0) filename = [filename stringByAppendingPathExtension:extension];
	}
	else {
		filename = [self generateDefaultExportFilename];
	}

	[exportCustomFilenameViewLabelButton setTitle:[NSString stringWithFormat:NSLocalizedString(@"Customize Filename (%@)", @"customize file name label"), filename]];
}

- (NSString *)customFilenamePathExtension
{
	NSMutableString *flatted = [NSMutableString string];

	// This time we replace every token with "/a". This has the following effect:
	// "{host}.{database}"     -> "/a./a"     -> extension=""
	// "{database}_{date}.sql" -> "/a_/a.sql" -> extension="sql"
	// That seems to be the easiest way to let NSString correctly determine if an extension is present
	for (id filenamePart in [exportCustomFilenameTokenField objectValue])
	{
		if([filenamePart isKindOfClass:[NSString class]])
			[flatted appendString:filenamePart];
		else if([filenamePart isKindOfClass:[SPExportFileNameTokenObject class]])
			[flatted appendString:@"/a"];
		else
			[NSException raise:NSInternalInconsistencyException format:@"unknown object in token list: %@",filenamePart];
	}

	return [flatted pathExtension];
}

- (BOOL)isTableTokenAllowed
{
	NSUInteger i = 0;
	BOOL removeTable = NO;

	BOOL isSQL = exportType == SPSQLExport;
	BOOL isCSV = exportType == SPCSVExport;
	BOOL isDot = exportType == SPDotExport;
	BOOL isXML = exportType == SPXMLExport;

	// Determine whether to remove the table from the tokens list
	if (exportSource == SPQueryExport || isDot) {
		removeTable = YES;
	}
	else if (isSQL || isCSV || isXML) {
		for (NSArray *table in tables)
		{
			if ([[table safeObjectAtIndex:2] boolValue]) {
				i++;
				if (i == 2) break;
			}
		}

		if (i > 1) {
			removeTable = isSQL ? YES : ![exportFilePerTableCheck state];
		}
	}

	return (removeTable == NO);
}

/**
 * Updates the available export filename tokens based on the currently selected options.
 */
- (void)updateAvailableExportFilenameTokens
{
	SPExportFileNameTokenObject *tableObject;
	NSMutableArray *exportTokens = [NSMutableArray arrayWithObjects:
									[SPExportFileNameTokenObject tokenWithId:SPFileNameDatabaseTokenName],
									[SPExportFileNameTokenObject tokenWithId:SPFileNameHostTokenName],
									[SPExportFileNameTokenObject tokenWithId:SPFileNameDateTokenName],
									[SPExportFileNameTokenObject tokenWithId:SPFileNameYearTokenName],
									[SPExportFileNameTokenObject tokenWithId:SPFileNameMonthTokenName],
									[SPExportFileNameTokenObject tokenWithId:SPFileNameDayTokenName],
									[SPExportFileNameTokenObject tokenWithId:SPFileNameTimeTokenName],
									[SPExportFileNameTokenObject tokenWithId:SPFileName24HourTimeTokenName],
									[SPExportFileNameTokenObject tokenWithId:SPFileNameFavoriteTokenName],
									(tableObject = [SPExportFileNameTokenObject tokenWithId:SPFileNameTableTokenName]),
									nil
									];

	if (![self isTableTokenAllowed]) {
		[exportTokens removeObject:tableObject];
		NSArray *tokenParts = [exportCustomFilenameTokenField objectValue];

		for (id token in tokenParts)
		{
			if([token isEqual:tableObject]) {
				NSMutableArray *newTokens = [NSMutableArray arrayWithArray:tokenParts];

				[newTokens removeObject:tableObject]; //removes all occurances

				[exportCustomFilenameTokenField setObjectValue:newTokens];
				break;
			}
		}
	}

	[exportCustomFilenameTokenPool setObjectValue:exportTokens];
	//update preview name as programmatically changing the exportCustomFilenameTokenField does not fire a notification
	[self updateDisplayedExportFilename];
}

- (NSArray *)currentAllowedExportFilenameTokens
{
	NSArray *mixed = [exportCustomFilenameTokenPool objectValue];
	NSMutableArray *tokens = [NSMutableArray arrayWithCapacity:[mixed count]]; // ...or less

	for (id obj in mixed) {
		if([obj isKindOfClass:[SPExportFileNameTokenObject class]]) [tokens addObject:obj];
	}

	return tokens;
}

/**
 * Generates the default export filename based on the selected export options.
 *
 * @return The default filename.
 */
- (NSString *)generateDefaultExportFilename
{
	NSString *filename = @"";
	NSString *extension = [self currentDefaultExportFileExtension];

	// Determine what the file name should be
	switch (exportSource)
	{
		case SPFilteredExport:
			filename = [NSString stringWithFormat:@"%@_view", [tableDocumentInstance table]];
			break;
		case SPQueryExport:
			filename = @"query_result";
			break;
		case SPTableExport:
			filename = [NSString stringWithFormat:@"%@_%@",
						[tableDocumentInstance database],
						[[NSDate date] stringWithFormat:@"yyyy-MM-dd"
												 locale:[NSLocale autoupdatingCurrentLocale]
											   timeZone:[NSTimeZone localTimeZone]]];
			
			;
			break;
	}

	return ([extension length] > 0) ? [filename stringByAppendingPathExtension:extension] : filename;
}

/**
 * Returns the current default export file extension based on the selected export type.
 *
 * @return The default filename extension.
 */
- (NSString *)currentDefaultExportFileExtension
{
	NSString *extension = @"";

	switch (exportType) {
		case SPSQLExport:
			extension = SPFileExtensionSQL;
			break;
		case SPCSVExport:
			// If the tab character (\t) is selected as the feild separator return the extension as .tsv
			extension = ([exportCSVFieldsTerminatedField indexOfSelectedItem] == 2) ? @"tsv" : @"csv";
			break;
		case SPXMLExport:
			extension = @"xml";
			break;
		case SPDotExport:
			extension = @"dot";
			break;
		case SPPDFExport:
		case SPHTMLExport:
		case SPExcelExport:
		default:
			[NSException raise:NSInvalidArgumentException format:@"unsupported exportType=%lu",exportType];
			return nil;
	}

	if ([exportOutputCompressionFormatPopupButton indexOfSelectedItem] != SPNoCompression) {

		SPFileCompressionFormat compressionFormat = (SPFileCompressionFormat)[exportOutputCompressionFormatPopupButton indexOfSelectedItem];

		if ([extension length] > 0) {
			extension = [extension stringByAppendingPathExtension:(compressionFormat == SPGzipCompression) ? @"gz" : @"bz2"];
		}
		else {
			extension = (compressionFormat == SPGzipCompression) ? @"gz" : @"bz2";
		}
	}

	return extension;
}

/**
 * Expands the custom filename format based on the selected tokens.
 * Uses the current custom filename field as a data source.
 *
 * @param table  A table name to be used within the expanded filename.
 *               Can be nil.
 *
 * @return The expanded filename.
 */
- (NSString *)expandCustomFilenameFormatUsingTableName:(NSString *)table
{
	NSMutableString *string = [NSMutableString string];

	// Walk through the token field, appending token replacements or strings
	NSArray *representedFilenameParts = [exportCustomFilenameTokenField objectValue];

	for (id filenamePart in representedFilenameParts)
	{
		if ([filenamePart isKindOfClass:[SPExportFileNameTokenObject class]]) {
			NSString *tokenContent = [filenamePart tokenId];

			if ([tokenContent isEqualToString:SPFileNameHostTokenName]) {
				[string appendStringOrNil:[tableDocumentInstance host]];

			}
			else if ([tokenContent isEqualToString:SPFileNameDatabaseTokenName]) {
				[string appendStringOrNil:[tableDocumentInstance database]];

			}
			else if ([tokenContent isEqualToString:SPFileNameTableTokenName]) {
				[string appendStringOrNil:table];
			}
			else if ([tokenContent isEqualToString:SPFileNameDateTokenName]) {
				[string appendString:[NSDateFormatter.shortStyleNoTimeFormatter stringFromDate:[NSDate date]]];
			}
			else if ([tokenContent isEqualToString:SPFileNameYearTokenName]) {
				[string appendString:[[NSDate date] stringWithFormat:@"yyyy" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]]];
			}
			else if ([tokenContent isEqualToString:SPFileNameMonthTokenName]) {
				[string appendString:[[NSDate date] stringWithFormat:@"MM" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]]];
			}
			else if ([tokenContent isEqualToString:SPFileNameDayTokenName]) {
				[string appendString:[[NSDate date] stringWithFormat:@"dd" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]]];
			}
			else if ([tokenContent isEqualToString:SPFileNameTimeTokenName]) {
				[string appendString:[NSDateFormatter.shortStyleNoDateFormatter stringFromDate:[NSDate date]]];
			}
			else if ([tokenContent isEqualToString:SPFileName24HourTimeTokenName]) {
				[string appendString:[[NSDate date] stringWithFormat:@"HH:mm:ss" locale:[NSLocale autoupdatingCurrentLocale] timeZone:[NSTimeZone localTimeZone]]];
			}
			else if ([tokenContent isEqualToString:SPFileNameFavoriteTokenName]) {
				[string appendStringOrNil:[tableDocumentInstance name]];
			}
		}
		else {
			[string appendString:filenamePart];
		}
	}

	// Replace colons with hyphens
	[string replaceOccurrencesOfString:@":"
							withString:@"-"
							   options:NSLiteralSearch
								 range:NSMakeRange(0, [string length])];

	// Replace forward slashes with hyphens
	[string replaceOccurrencesOfString:@"/"
							withString:@"-"
							   options:NSLiteralSearch
								 range:NSMakeRange(0, [string length])];

	 // Replace forward dots with hyphens
	 [string replaceOccurrencesOfString:@"."
							 withString:@"-"
								options:NSLiteralSearch
								  range:NSMakeRange(0, [string length])];

	// Don't allow empty strings - if an empty string resulted, revert to the default string
	if (![string length]) [string setString:[self generateDefaultExportFilename]];

	return string;
}

#pragma mark - SPExportInterfaceController

/**
 * Resizes the export window's height by the supplied delta, while retaining the position of
 * all interface controls to accommodate the custom filename view.
 *
 * @param delta The height delta for which the height should be adjusted for.
 */
- (void)_resizeWindowForCustomFilenameViewByHeightDelta:(NSInteger)delta
{
	NSAutoresizingMaskOptions popUpMask              = [exportInputPopUpButton autoresizingMask];
	NSAutoresizingMaskOptions fileCheckMask          = [exportFilePerTableCheck autoresizingMask];
	NSAutoresizingMaskOptions scrollMask             = [exportTablelistScrollView autoresizingMask];
	NSAutoresizingMaskOptions buttonBarMask          = [exportTableListButtonBar autoresizingMask];
	NSAutoresizingMaskOptions buttonMask             = [exportCustomFilenameViewButton autoresizingMask];
	NSAutoresizingMaskOptions textFieldMask          = [exportCustomFilenameViewLabelButton autoresizingMask];
	NSAutoresizingMaskOptions customFilenameViewMask = [exportCustomFilenameView autoresizingMask];
	NSAutoresizingMaskOptions tabBarMask             = [exportOptionsTabBar autoresizingMask];

	NSRect frame = [[self window] frame];

	if (frame.size.height > 600 && delta > heightOffset1) {
		frame.origin.y += [exportCustomFilenameView frame].size.height;
		frame.size.height -= [exportCustomFilenameView frame].size.height;

		[[self window] setFrame:frame display:YES animate:YES];
	}

	[exportInputPopUpButton setAutoresizingMask:NSViewNotSizable | NSViewMaxYMargin];
	[exportFilePerTableCheck setAutoresizingMask:NSViewNotSizable | NSViewMaxYMargin];
	[exportTablelistScrollView setAutoresizingMask:NSViewNotSizable | NSViewMaxYMargin];
	[exportTableListButtonBar setAutoresizingMask:NSViewNotSizable | NSViewMaxYMargin];
	[exportOptionsTabBar setAutoresizingMask:NSViewNotSizable | NSViewMaxYMargin];
	[exportCustomFilenameViewButton setAutoresizingMask:NSViewNotSizable | NSViewMinYMargin];
	[exportCustomFilenameViewLabelButton setAutoresizingMask:NSViewNotSizable | NSViewMinYMargin];
	[exportCustomFilenameView setAutoresizingMask:NSViewNotSizable | NSViewMinYMargin];

	NSInteger newMinHeight = (windowMinHeigth - heightOffset1 + delta < windowMinHeigth) ? windowMinHeigth : windowMinHeigth - heightOffset1 + delta;

	[[self window] setMinSize:NSMakeSize(windowMinWidth, newMinHeight)];

	frame.origin.y += heightOffset1;
	frame.size.height -= heightOffset1;

	heightOffset1 = delta;

	frame.origin.y -= heightOffset1;
	frame.size.height += heightOffset1;

	[[self window] setFrame:frame display:YES animate:YES];

	[exportInputPopUpButton setAutoresizingMask:popUpMask];
	[exportFilePerTableCheck setAutoresizingMask:fileCheckMask];
	[exportTablelistScrollView setAutoresizingMask:scrollMask];
	[exportTableListButtonBar setAutoresizingMask:buttonBarMask];
	[exportCustomFilenameViewButton setAutoresizingMask:buttonMask];
	[exportCustomFilenameViewLabelButton setAutoresizingMask:textFieldMask];
	[exportCustomFilenameView setAutoresizingMask:customFilenameViewMask];
	[exportOptionsTabBar setAutoresizingMask:tabBarMask];
}

/**
 * Resizes the export window's height by the supplied delta, while retaining the position of
 * all interface controls to accommodate the advanced options view.
 *
 * @param delta The height delta for which the height should be adjusted for.
 */
- (void)_resizeWindowForAdvancedOptionsViewByHeightDelta:(NSInteger)delta
{
	NSAutoresizingMaskOptions scrollMask        = [exportTablelistScrollView autoresizingMask];
	NSAutoresizingMaskOptions buttonBarMask     = [exportTableListButtonBar autoresizingMask];
	NSAutoresizingMaskOptions tabBarMask        = [exportTypeTabBar autoresizingMask];
	NSAutoresizingMaskOptions optionsTabBarMask = [exportOptionsTabBar autoresizingMask];
	NSAutoresizingMaskOptions buttonMask        = [exportAdvancedOptionsViewButton autoresizingMask];
	NSAutoresizingMaskOptions textFieldMask     = [exportAdvancedOptionsViewLabelButton autoresizingMask];
	NSAutoresizingMaskOptions advancedViewMask  = [exportAdvancedOptionsView autoresizingMask];

	NSRect frame = [[self window] frame];

	if (frame.size.height > 600 && delta > heightOffset2) {
		frame.origin.y += [exportAdvancedOptionsView frame].size.height;
		frame.size.height -= [exportAdvancedOptionsView frame].size.height;

		[[self window] setFrame:frame display:YES animate:YES];
	}

	[exportTablelistScrollView setAutoresizingMask:NSViewNotSizable | NSViewMinYMargin];
	[exportTableListButtonBar setAutoresizingMask:NSViewNotSizable | NSViewMinYMargin];
	[exportTypeTabBar setAutoresizingMask:NSViewNotSizable | NSViewMinYMargin];
	[exportOptionsTabBar setAutoresizingMask:NSViewNotSizable | NSViewMinYMargin];
	[exportAdvancedOptionsViewButton setAutoresizingMask:NSViewNotSizable | NSViewMinYMargin];
	[exportAdvancedOptionsViewLabelButton setAutoresizingMask:NSViewNotSizable | NSViewMinYMargin];
	[exportAdvancedOptionsView setAutoresizingMask:NSViewNotSizable | NSViewMinYMargin];

	NSInteger newMinHeight = (windowMinHeigth - heightOffset2 + delta < windowMinHeigth) ? windowMinHeigth : windowMinHeigth - heightOffset2 + delta;

	[[self window] setMinSize:NSMakeSize(windowMinWidth, newMinHeight)];

	frame.origin.y += heightOffset2;
	frame.size.height -= heightOffset2;

	heightOffset2 = delta;

	frame.origin.y -= heightOffset2;
	frame.size.height += heightOffset2;

	[[self window] setFrame:frame display:YES animate:YES];

	[exportTablelistScrollView setAutoresizingMask:scrollMask];
	[exportTableListButtonBar setAutoresizingMask:buttonBarMask];
	[exportTypeTabBar setAutoresizingMask:tabBarMask];
	[exportOptionsTabBar setAutoresizingMask:optionsTabBarMask];
	[exportAdvancedOptionsViewButton setAutoresizingMask:buttonMask];
	[exportAdvancedOptionsViewLabelButton setAutoresizingMask:textFieldMask];
	[exportAdvancedOptionsView setAutoresizingMask:advancedViewMask];
}

#pragma mark - SPExportControllerDelegate

#pragma mark Table view datasource methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView;
{
	return [tables count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
    return [[tables safeObjectAtIndex:rowIndex] safeObjectAtIndex:[exportTableList columnWithIdentifier:[tableColumn identifier]]];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	[[tables safeObjectAtIndex:rowIndex] safeReplaceObjectAtIndex:[exportTableList columnWithIdentifier:[tableColumn identifier]] withObject:anObject];

	[self updateAvailableExportFilenameTokens];
	[self _toggleExportButtonOnBackgroundThread];
	[self _updateExportFormatInformation];
}

#pragma mark -
#pragma mark Table view delegate methods

- (BOOL)tableView:(NSTableView *)tableView shouldTrackCell:(NSCell *)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	return (tableView == exportTableList);
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	[cell setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
}

#pragma mark -
#pragma mark Tabview delegate methods

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	[tabViewItem setView:exporterView];

	[self _switchTab];
}

#pragma mark -
#pragma mark Token field delegate methods

/**
 * Use the default token style for matched tokens, plain text for all other text.
 */
- (NSTokenStyle)tokenField:(NSTokenField *)tokenField styleForRepresentedObject:(id)representedObject
{
	if (IS_TOKEN(representedObject)) return NSDefaultTokenStyle;

	return NSPlainTextTokenStyle;
}

- (BOOL)tokenField:(NSTokenField *)tokenField writeRepresentedObjects:(NSArray *)objects toPasteboard:(NSPasteboard *)pboard
{
	NSMutableArray *mixed = [NSMutableArray arrayWithCapacity:[objects count]];
	NSMutableString *flatted = [NSMutableString string];

	for(id item in objects) {
		if(IS_TOKEN(item)) {
			[mixed safeAddObject:@{@"tokenId": [item tokenId]}];
			[flatted appendFormat:@"{%@}",[item tokenId]];
		}
		else if(IS_STRING(item)) {
			[mixed safeAddObject:item];
			[flatted appendString:item];
		}
		else {
			[NSException raise:NSInternalInconsistencyException format:@"tokenField %@ contains unexpected object %@",tokenField,item];
		}
	}

	[pboard setString:flatted forType:NSPasteboardTypeString];
	[pboard setPropertyList:mixed forType:SPExportCustomFileNameTokenPlistType];
	return YES;
}

- (NSArray *)tokenField:(NSTokenField *)tokenField readFromPasteboard:(NSPasteboard *)pboard
{
	NSArray *items = [pboard propertyListForType:SPExportCustomFileNameTokenPlistType];
	// if we have our preferred object type use it
	if(items) {
		NSMutableArray *res = [NSMutableArray arrayWithCapacity:[items count]];
		for (id item in items) {
			if (IS_STRING(item)) {
				[res safeAddObject:item];
			}
			else if([item isKindOfClass:[NSDictionary class]]) {
				NSString *name = [item safeObjectForKey:@"tokenId"];
				if(name) {
					SPExportFileNameTokenObject *tok = [SPExportFileNameTokenObject tokenWithId:name];
					[res safeAddObject:tok];
				}
			}
			else {
				[NSException raise:NSInternalInconsistencyException format:@"pasteboard %@ contains unexpected object %@",pboard,item];
			}
		}
		return res;
	}
	// if the string came from another app, paste it literal, tokenfield will take care of any conversions
	NSString *raw = [pboard stringForType:NSPasteboardTypeString];
	if(raw) {
		return @[[raw stringByReplacingCharactersInSet:[NSCharacterSet newlineCharacterSet]	withString:@" "]];
	}

	return nil;
}

/**
 * Take the default suggestion of new tokens - all untokenized text, as no tokenizing character is set - and
 * split/recombine strings that contain tokens. This preserves all supplied characters and allows tokens to be typed.
 */
- (NSArray *)tokenField:(NSTokenField *)tokenField shouldAddObjects:(NSArray *)tokens atIndex:(NSUInteger)index
{
	return [self _updateTokensForMixedContent:tokens];
}

- (NSString *)tokenField:(NSTokenField *)tokenField displayStringForRepresentedObject:(id)representedObject
{
	if (IS_TOKEN(representedObject)) {
		return [localizedTokenNames objectForKey:[(SPExportFileNameTokenObject *)representedObject tokenId]];
	}

	return representedObject;
}

/**
 * Return the editing string untouched - implementing this method prevents whitespace trimming.
 */
- (id)tokenField:(NSTokenField *)tokenField representedObjectForEditingString:(NSString *)editingString
{
	return editingString;
}

/**
 * During text entry into the token field, update the displayed filename and also
 * trigger tokenization after a short delay.
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
	// this method can either be called by typing, or by copy&paste.
	// In the latter case tokenization will already be done by now.
	if ([notification object] == exportCustomFilenameTokenField) {
		[self updateDisplayedExportFilename];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_tokenizeCustomFilenameTokenField) object:nil];
		// do not queue a call if the key causing this change was the return key.
		// This is to prevent a loop with _tokenizeCustomFilenameTokenField.
		if([[NSApp currentEvent] type] != NSEventTypeKeyDown || [[NSApp currentEvent] keyCode] != 0x24) {
			[self performSelector:@selector(_tokenizeCustomFilenameTokenField) withObject:nil afterDelay:0.5];
		}
	}
}

#pragma mark -
#pragma mark Combo box delegate methods

- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{
	if ([notification object] == exportCSVFieldsTerminatedField) {
		[self updateDisplayedExportFilename];
	}
}

#pragma mark -

/**
 * Takes a mixed array of strings and tokens and converts
 * any valid tokens inside the strings into real tokens
 */
- (NSArray *)_updateTokensForMixedContent:(NSArray *)tokens
{
	//if two consecutive tokens are strings, merge them
	NSMutableArray *mergedTokens = [NSMutableArray array];
	for (id inputToken in tokens)
	{
		if(IS_TOKEN(inputToken)) {
			[mergedTokens safeAddObject:inputToken];
		}
		else if(IS_STRING(inputToken)) {
			id prev = [mergedTokens lastObject];
			if(IS_STRING(prev)) {
				[mergedTokens removeLastObject];
				[mergedTokens safeAddObject:[prev stringByAppendingString:inputToken]];
			}
			else {
				[mergedTokens safeAddObject:inputToken];
			}
		}
	}

	// create a mapping dict of tokenId => token
	NSMutableDictionary *replacement = [NSMutableDictionary dictionary];
	for (SPExportFileNameTokenObject *realToken in [exportCustomFilenameTokenPool objectValue]) {
		NSString *serializedName = [NSString stringWithFormat:@"{%@}",[realToken tokenId]];
		[replacement safeSetObject:realToken forKey:serializedName];
	}

	//now we can look for real tokens to convert inside the strings
	NSMutableArray *processedTokens = [NSMutableArray array];
	for (id token in mergedTokens) {
		if(IS_TOKEN(token)) {
			[processedTokens safeAddObject:token];
			continue;
		}

		NSString *remainder = token;
		while(true) {
			NSRange openCurl = [remainder rangeOfString:@"{"];
			if(openCurl.location == NSNotFound) {
				break;
			}
			NSString *before = [remainder substringToIndex:openCurl.location];
			if([before length]) {
				[processedTokens safeAddObject:before];
			}
			remainder = [remainder substringFromIndex:openCurl.location];
			NSRange closeCurl = [remainder rangeOfString:@"}"];
			if(closeCurl.location == NSNotFound) {
				break; //we've hit an unterminated token
			}
			NSString *tokenString = [remainder substringToIndex:closeCurl.location+1];
			SPExportFileNameTokenObject *tokenObject = [replacement objectForKey:[tokenString lowercaseString]];
			if(tokenObject) {
				[processedTokens safeAddObject:tokenObject];
			}
			else {
				[processedTokens safeAddObject:tokenString]; // no token with this name, add it as string
			}
			remainder = [remainder substringFromIndex:closeCurl.location+1];
		}
		if([remainder length]) {
			[processedTokens safeAddObject:remainder];
		}
	}

	return processedTokens;
}

- (void)_tokenizeCustomFilenameTokenField
{
	// if we are currently inside or at the end of a string segment we can
	// call for tokenization to happen by simulating a return press

	if ([exportCustomFilenameTokenField currentEditor] == nil) return;

	NSRange selectedRange = [[exportCustomFilenameTokenField currentEditor] selectedRange];

	if (selectedRange.location == NSNotFound) return;
	if (selectedRange.location == 0) return; // the beginning of the field is not valid for tokenization
	if (selectedRange.length > 0) return;

	NSUInteger start = 0;
	for(id obj in [exportCustomFilenameTokenField objectValue]) {
		
		SPLog(@"obj = %@", obj);
		
		NSUInteger length;
		BOOL isText = NO;
		if(IS_STRING(obj)) {
			NSString *objString = (NSString *)obj;
			length = [objString length];
			isText = YES;
			
			// only attempt tokenization if string contains a { or }
			if([objString containsString:@"{"] == NO && [objString containsString:@"}"] == NO){
				SPLog(@"string does not contain token delimiters");
				return;
			}
		}
		else if(IS_TOKEN(obj)) {
			length = 1; // tokens are seen as one char by the textview
		}
		else {
			[NSException raise:NSInternalInconsistencyException format:@"Unknown object type in token field: %@",obj];
		}
		NSUInteger end = start+length;
		if(selectedRange.location >= start && selectedRange.location <= end) {
			if(!isText) return; // cursor is at the end of a token
			break;
		}
		start += length;
	}

	// All conditions met - synthesize the return key to trigger tokenization.
	NSEvent *tokenizingEvent = [NSEvent keyEventWithType:NSEventTypeKeyDown
												location:NSMakePoint(0,0)
										   modifierFlags:0
											   timestamp:0
											windowNumber:[[exportCustomFilenameTokenField window] windowNumber]
												 context:[NSGraphicsContext currentContext]
											  characters:@""
							 charactersIgnoringModifiers:@""
											   isARepeat:NO
												 keyCode:0x24];

	[NSApp postEvent:tokenizingEvent atStart:NO];
}

#pragma mark - SPExportSettingsPersistence

#define NAMEOF(x) case x: return @#x
#define VALUEOF(x,y,dst) if([y isEqualToString:@#x]) { *dst = x; return YES; }

+ (NSString *)describeExportSource:(SPExportSource)es
{
	switch (es) {
			NAMEOF(SPFilteredExport);
			NAMEOF(SPQueryExport);
			NAMEOF(SPTableExport);
	}
	return nil;
}

+ (BOOL)copyExportSourceForDescription:(NSString *)esd to:(SPExportSource *)dst
{
	VALUEOF(SPFilteredExport, esd,dst);
	VALUEOF(SPQueryExport,    esd,dst);
	VALUEOF(SPTableExport,    esd,dst);
	return NO;
}

+ (NSString *)describeExportType:(SPExportType)et
{
	switch (et) {
			NAMEOF(SPSQLExport);
			NAMEOF(SPCSVExport);
			NAMEOF(SPXMLExport);
			NAMEOF(SPDotExport);
			NAMEOF(SPPDFExport);
			NAMEOF(SPHTMLExport);
			NAMEOF(SPExcelExport);
			NAMEOF(SPAnyExportType);
	}
	return nil;
}

+ (BOOL)copyExportTypeForDescription:(NSString *)etd to:(SPExportType *)dst
{
	VALUEOF(SPSQLExport, etd, dst);
	VALUEOF(SPCSVExport, etd, dst);
	VALUEOF(SPXMLExport, etd, dst);
	VALUEOF(SPDotExport, etd, dst);
	//VALUEOF(SPPDFExport, etd, dst);
	//VALUEOF(SPHTMLExport, etd, dst);
	//VALUEOF(SPExcelExport, etd, dst);
	return NO;
}

+ (NSString *)describeCompressionFormat:(SPFileCompressionFormat)cf
{
	switch (cf) {
			NAMEOF(SPNoCompression);
			NAMEOF(SPGzipCompression);
			NAMEOF(SPBzip2Compression);
	}
	return nil;
}

+ (BOOL)copyCompressionFormatForDescription:(NSString *)cfd to:(SPFileCompressionFormat *)dst
{
	VALUEOF(SPNoCompression,    cfd, dst);
	VALUEOF(SPGzipCompression,  cfd, dst);
	VALUEOF(SPBzip2Compression, cfd, dst);
	return NO;
}

+ (NSString *)describeXMLExportFormat:(SPXMLExportFormat)xf
{
	switch (xf) {
			NAMEOF(SPXMLExportMySQLFormat);
			NAMEOF(SPXMLExportPlainFormat);
	}
	return nil;
}

+ (BOOL)copyXMLExportFormatForDescription:(NSString *)xfd to:(SPXMLExportFormat *)dst
{
	VALUEOF(SPXMLExportMySQLFormat, xfd, dst);
	VALUEOF(SPXMLExportPlainFormat, xfd, dst);
	return NO;
}

+ (NSString *)describeSQLExportInsertDivider:(SPSQLExportInsertDivider)eid
{
	switch (eid) {
			NAMEOF(SPSQLInsertEveryNDataBytes);
			NAMEOF(SPSQLInsertEveryNRows);
	}
	return nil;
}

+ (BOOL)copySQLExportInsertDividerForDescription:(NSString *)eidd to:(SPSQLExportInsertDivider *)dst
{
	VALUEOF(SPSQLInsertEveryNDataBytes, eidd, dst);
	VALUEOF(SPSQLInsertEveryNRows,      eidd, dst);
	return NO;
}

#undef NAMEOF
#undef VALUEOF

- (IBAction)importCurrentSettings:(id)sender
{
	//show open file dialog
	NSOpenPanel *panel = [NSOpenPanel openPanel];

	[panel setAllowedFileTypes:@[SPFileExtensionDefault]];
	[panel setAllowsOtherFileTypes:YES];

	[panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) {
		if(result != NSFileHandlingPanelOKButton) return;

		[panel orderOut:nil]; // Panel is still on screen. Hide it first. (This is Apple's recommended way)

		NSError *err = nil;
		NSData *plist = [NSData dataWithContentsOfURL:[panel URL]
											  options:0
												error:&err];

		NSDictionary *settings = nil;
		if(!err) {
			settings = [NSPropertyListSerialization propertyListWithData:plist
																 options:NSPropertyListImmutable
																  format:NULL
																   error:&err];
		}

		if(!err) {
			[self applySettingsFromDictionary:settings error:&err];
			if(!err) return;
		}

		// give an explanation for some errors
		if([[err domain] isEqualToString:SPErrorDomain]) {
			if([err code] == SPErrorWrongTypeOrNil) {
				NSDictionary *info = @{
									   NSLocalizedDescriptionKey:             NSLocalizedString(@"Invalid file supplied!", @"export : import settings : file error title"),
									   NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"The selected file is either not a valid SPF file or severely corrupted.", @"export : import settings : file error description"),
									   };
				err = [NSError errorWithDomain:[err domain] code:[err code] userInfo:info];
			}
			else if([err code] == SPErrorWrongContentType) {
				NSDictionary *info = @{
									   NSLocalizedDescriptionKey:             NSLocalizedString(@"Wrong SPF content type!", @"export : import settings : spf content type error title"),
									   NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:NSLocalizedString(@"The selected file contains data of type “%1$@”, but type “%2$@” is needed. Please choose a different file.", @"export : import settings : spf content type error description"),[[err userInfo] objectForKey:@"isType"],[[err userInfo] objectForKey:@"expectedType"]],
									   };
				err = [NSError errorWithDomain:[err domain] code:[err code] userInfo:info];
			}
		}

		NSAlert *alert = [NSAlert alertWithError:err];
		[alert setAlertStyle:NSAlertStyleCritical];
		[alert runModal];
	}];
}

- (IBAction)exportCurrentSettings:(id)sender
{
	//show save file dialog
	NSSavePanel *panel = [NSSavePanel savePanel];

	[panel setAllowedFileTypes:@[SPFileExtensionDefault]];

	[panel setExtensionHidden:NO];
	[panel setAllowsOtherFileTypes:NO];
	[panel setCanSelectHiddenExtension:YES];
	[panel setCanCreateDirectories:YES];

	[panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger returnCode) {
		if(returnCode != NSFileHandlingPanelOKButton) return;

		// Panel is still on screen. Hide it first. (This is Apple's recommended way)
		[panel orderOut:nil];

		NSError *err = nil;
		NSData *plist = [NSPropertyListSerialization dataWithPropertyList:[self currentSettingsAsDictionary]
																   format:NSPropertyListXMLFormat_v1_0
																  options:0
																	error:&err];
		if(!err) {
			[plist writeToURL:[panel URL] options:NSAtomicWrite error:&err];
			if(!err) return;
		}

		NSAlert *alert = [NSAlert alertWithError:err];
		[alert setAlertStyle:NSAlertStyleCritical];
		[alert runModal];
	}];
}

- (NSArray *)currentCustomFilenameAsArray
{
	NSArray *tokenListIn = [exportCustomFilenameTokenField objectValue];
	NSMutableArray *tokenListOut = [NSMutableArray arrayWithCapacity:[tokenListIn count]];

	for (id obj in tokenListIn) {
		if([obj isKindOfClass:[NSString class]]) {
			[tokenListOut addObject:obj];
		}
		else if([obj isKindOfClass:[SPExportFileNameTokenObject class]]) {
			NSDictionary *tokenProperties = @{@"tokenId": [obj tokenId]};
			// in the future the dict can be used to store per-token settings
			[tokenListOut addObject:tokenProperties];
		}
		else {
			SPLog(@"unknown object in token list: %@",obj);
		}
	}

	return tokenListOut;
}

- (void)setCustomFilenameFromArray:(NSArray *)tokenList
{
	NSMutableArray *tokenListOut = [NSMutableArray arrayWithCapacity:[tokenList count]];
	NSArray *allowedTokens = [self currentAllowedExportFilenameTokens];

	for (id obj in tokenList) {
		if([obj isKindOfClass:[NSString class]]) {
			[tokenListOut addObject:obj];
		}
		else if([obj isKindOfClass:[NSDictionary class]]) {
			//there must be at least a non-empty tokenId that is also in the token pool
			NSString *tokenId = [obj objectForKey:@"tokenId"];
			if([tokenId length]) {
				SPExportFileNameTokenObject *token = [SPExportFileNameTokenObject tokenWithId:tokenId];
				if([allowedTokens containsObject:token]) {
					[tokenListOut addObject:token];
					continue;
				}
			}
			SPLog(@"Ignoring an invalid or unknown token with tokenId=%@",tokenId);
		}
		else {
			SPLog(@"unknown object in import token list: %@",obj);
		}
	}

	[exportCustomFilenameTokenField setObjectValue:tokenListOut];

	[self updateDisplayedExportFilename];
}

- (NSDictionary *)currentSettingsAsDictionary
{
	NSMutableDictionary *root = [NSMutableDictionary dictionary];

	[root setObject:SPFExportSettingsContentType forKey:SPFFormatKey];
	[root setObject:@1 forKey:SPFVersionKey];

	[root setObject:[exportPathField stringValue] forKey:@"exportPath"];

	[root setObject:[[self class] describeExportSource:exportSource] forKey:@"exportSource"];
	[root setObject:[[self class] describeExportType:exportType] forKey:@"exportType"];

	if([[exportCustomFilenameTokenField stringValue] length] > 0) {
		[root setObject:[self currentCustomFilenameAsArray] forKey:@"customFilename"];
	}

	[root setObject:[self exporterSettings] forKey:@"settings"];

	if(exportSource == SPTableExport) {
		NSMutableDictionary *perObjectSettings = [NSMutableDictionary dictionaryWithCapacity:[tables count]];

		for (NSMutableArray *table in tables) {
			NSString *key = [table firstObject];
			id settings = [self exporterSpecificSettingsForSchemaObject:key ofType:SPTableTypeTable];
			if(settings)
				[perObjectSettings safeSetObject:settings forKey:key];
		}

		[root safeSetObject:perObjectSettings forKey:@"schemaObjects"];
	}

	[root safeSetObject:IsOn(exportProcessLowMemoryButton) forKey:@"lowMemoryStreaming"];
	[root safeSetObject:[[self class] describeCompressionFormat:(SPFileCompressionFormat)[exportOutputCompressionFormatPopupButton indexOfSelectedItem]] forKey:@"compressionFormat"];

	return root;
}

- (BOOL)applySettingsFromDictionary:(NSDictionary *)dict error:(NSError **)err
{
	//check for dict/nil
	if(![dict isKindOfClass:[NSDictionary class]]) {
		if(err) {
			*err = [NSError errorWithDomain:SPErrorDomain
									   code:SPErrorWrongTypeOrNil
								   userInfo:nil]; // we don't know where data came from, so we can't provide meaningful help to the user
		}
		return NO;
	}

	//check for export settings
	NSString *ctype = [dict objectForKey:SPFFormatKey];
	if (![SPFExportSettingsContentType isEqualToString:ctype]) {
		if(err) {
			NSDictionary *errInfo = @{
									  @"isType":       ctype,
									  @"expectedType": SPFExportSettingsContentType
									  };
			*err = [NSError errorWithDomain:SPErrorDomain
									   code:SPErrorWrongContentType
								   userInfo:errInfo];
		}
		return NO;
	}

	//check for version
	NSInteger version = [[dict objectForKey:SPFVersionKey] integerValue];
	if(version != 1) {
		if(err) {
			NSDictionary *errInfo = @{
									  @"isVersion":                          @(version),
									  NSLocalizedDescriptionKey:             NSLocalizedString(@"Unsupported version for export settings!", @"export : import settings : file version error title"),
									  NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:NSLocalizedString(@"The selected export settings were stored with version\u00A0%1$ld, but only settings with the following versions can be imported: %2$@.\n\nEither save the settings in a backwards compatible way or update your version of Sequel Ace.", @"export : import settings : file version error description ($1 = is version, $2 = list of supported versions); note: the u00A0 is a non-breaking space, do not add more whitespace."),version,@"1"],
									  };
			*err = [NSError errorWithDomain:SPErrorDomain
									   code:SPErrorWrongContentVersion
								   userInfo:errInfo];
		}
		return NO;
	}

	//ok, we can try to import that...

	[exporters removeAllObjects];
	[exportFiles removeAllObjects];
	
	id o;
	// if we have some bookmarks, populate the last used export path
	// look up that bookmark and request access
	if(bookmarks.count > 0){
		if((o = [dict objectForKey:@"exportPath"])) [exportPathField setStringValue:o];

        NSString *fileURLString = [NSURL fileURLWithPath:[exportPathField stringValue] isDirectory:YES].absoluteString;

        // ret value can be nil
        userChosenDirectory = [SecureBookmarkManager.sharedInstance bookmarkForFilename:fileURLString];
	}
	
	SPExportType et;
	if((o = [dict safeObjectForKey:@"exportType"]) && [[self class] copyExportTypeForDescription:o to:&et]) {
		[exportTypeTabBar selectTabViewItemAtIndex:et];
	}

	//exportType should be changed first, as exportSource depends on it
	SPExportSource es;
	if((o = [dict safeObjectForKey:@"exportSource"]) && [[self class] copyExportSourceForDescription:o to:&es]) {
		[self setExportInput:es]; //try to set it. might fail e.g. if the settings were saved with "query result" but right now no custom query result exists
	}

	// set exporter specific settings
	[self applyExporterSettings:[dict safeObjectForKey:@"settings"]];

	// load schema object settings
	if(exportSource == SPTableExport) {
		NSDictionary *perObjectSettings = [dict safeObjectForKey:@"schemaObjects"];

		for (NSString *table in [perObjectSettings allKeys]) {
			id settings = [perObjectSettings safeObjectForKey:table];
			[self applyExporterSpecificSettings:settings forSchemaObject:table ofType:SPTableTypeTable];
		}

		[exportTableList reloadData];
	}

	if((o = [dict safeObjectForKey:@"lowMemoryStreaming"])) [exportProcessLowMemoryButton setState:([o boolValue] ? NSOnState : NSOffState)];

	SPFileCompressionFormat cf;
	if((o = [dict safeObjectForKey:@"compressionFormat"]) && [[self class] copyCompressionFormatForDescription:o to:&cf]) [exportOutputCompressionFormatPopupButton selectItemAtIndex:cf];

	// might have changed
	[self _updateExportAdvancedOptionsLabel];

	// token pool is only valid once the schema object selection is done
	[self updateAvailableExportFilenameTokens];
	if((o = [dict safeObjectForKey:@"customFilename"]) && [o isKindOfClass:[NSArray class]]) [self setCustomFilenameFromArray:o];

	return YES;
}

- (NSDictionary *)exporterSettings
{
	switch (exportType) {
		case SPCSVExport:
			return [self csvSettings];
		case SPSQLExport:
			return [self sqlSettings];
		case SPXMLExport:
			return [self xmlSettings];
		case SPDotExport:
			return [self dotSettings];
		case SPExcelExport:
		case SPHTMLExport:
		case SPPDFExport:
		default:
			@throw [NSException exceptionWithName:NSInternalInconsistencyException
										   reason:@"exportType not implemented!"
										 userInfo:@{@"exportType": @(exportType)}];
	}
}

- (void)applyExporterSettings:(NSDictionary *)settings
{
	switch (exportType) {
		case SPCSVExport:
			return [self applyCsvSettings:settings];
		case SPSQLExport:
			return [self applySqlSettings:settings];
		case SPXMLExport:
			return [self applyXmlSettings:settings];
		case SPDotExport:
			return [self applyDotSettings:settings];
		case SPExcelExport:
		case SPHTMLExport:
		case SPPDFExport:
		default:
			@throw [NSException exceptionWithName:NSInternalInconsistencyException
										   reason:@"exportType not implemented!"
										 userInfo:@{@"exportType": @(exportType)}];
	}
}

- (NSDictionary *)csvSettings
{
	return @{
			 @"exportToMultipleFiles": IsOn(exportFilePerTableCheck),
			 @"CSVIncludeFieldNames":  IsOn(exportCSVIncludeFieldNamesCheck),
			 @"CSVFieldsTerminated":   [exportCSVFieldsTerminatedField stringValue],
			 @"CSVFieldsWrapped":      [exportCSVFieldsWrappedField stringValue],
			 @"CSVLinesTerminated":    [exportCSVLinesTerminatedField stringValue],
			 @"CSVFieldsEscaped":      [exportCSVFieldsEscapedField stringValue],
			 @"CSVNULLValuesAsText":   [exportCSVNULLValuesAsTextField stringValue]
			 };
}

- (void)applyCsvSettings:(NSDictionary *)settings
{
	id o;
	if((o = [settings safeObjectForKey:@"exportToMultipleFiles"])) SetOnOff(o,exportFilePerTableCheck);
	[self toggleNewFilePerTable:nil];

	if((o = [settings safeObjectForKey:@"CSVIncludeFieldNames"]))  SetOnOff(o, exportCSVIncludeFieldNamesCheck);
	if((o = [settings safeObjectForKey:@"CSVFieldsTerminated"]))   [exportCSVFieldsTerminatedField setStringValue:o];
	if((o = [settings safeObjectForKey:@"CSVFieldsWrapped"]))      [exportCSVFieldsWrappedField setStringValue:o];
	if((o = [settings safeObjectForKey:@"CSVLinesTerminated"]))    [exportCSVLinesTerminatedField setStringValue:o];
	if((o = [settings safeObjectForKey:@"CSVFieldsEscaped"]))      [exportCSVFieldsEscapedField setStringValue:o];
	if((o = [settings safeObjectForKey:@"CSVNULLValuesAsText"]))   [exportCSVNULLValuesAsTextField setStringValue:o];
}

- (NSDictionary *)dotSettings
{
	return @{@"DotForceLowerTableNames": IsOn(exportDotForceLowerTableNamesCheck)};
}

- (void)applyDotSettings:(NSDictionary *)settings
{
	id o;
	if((o = [settings objectForKey:@"DotForceLowerTableNames"])) SetOnOff(o, exportDotForceLowerTableNamesCheck);
}

- (NSDictionary *)xmlSettings
{
	return @{
			 @"exportToMultipleFiles":     IsOn(exportFilePerTableCheck),
			 @"XMLFormat":                 [[self class] describeXMLExportFormat:(SPXMLExportFormat)[exportXMLFormatPopUpButton indexOfSelectedItem]],
			 @"XMLOutputIncludeStructure": IsOn(exportXMLIncludeStructure),
			 @"XMLOutputIncludeContent":   IsOn(exportXMLIncludeContent),
			 @"XMLNULLString":             [exportXMLNULLValuesAsTextField stringValue]
			 };
}

- (void)applyXmlSettings:(NSDictionary *)settings
{
	id o;
	SPXMLExportFormat xmlf;
	if((o = [settings safeObjectForKey:@"exportToMultipleFiles"]))     SetOnOff(o, exportFilePerTableCheck);
	[self toggleNewFilePerTable:nil];

	if((o = [settings safeObjectForKey:@"XMLFormat"]) && [[self class] copyXMLExportFormatForDescription:o to:&xmlf]) [exportXMLFormatPopUpButton selectItemAtIndex:xmlf];
	if((o = [settings safeObjectForKey:@"XMLOutputIncludeStructure"])) SetOnOff(o, exportXMLIncludeStructure);
	if((o = [settings safeObjectForKey:@"XMLOutputIncludeContent"]))   SetOnOff(o, exportXMLIncludeContent);
	if((o = [settings safeObjectForKey:@"XMLNULLString"]))             [exportXMLNULLValuesAsTextField setStringValue:o];

	[self toggleXMLOutputFormat:exportXMLFormatPopUpButton];
}

- (NSDictionary *)sqlSettings
{
	BOOL includeStructure = ([exportSQLIncludeStructureCheck state] == NSOnState);

	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
																				@"SQLIncludeStructure": IsOn(exportSQLIncludeStructureCheck),
																				@"SQLIncludeContent":   IsOn(exportSQLIncludeContentCheck),
																				@"SQLIncludeErrors":    IsOn(exportSQLIncludeErrorsCheck),
																				@"SQLIncludeDROP":      IsOn(exportSQLIncludeDropSyntaxCheck),
																				@"SQLUseUTF8BOM":       IsOn(exportUseUTF8BOMButton),
																				@"SQLBLOBFieldsAsHex":  IsOn(exportSQLBLOBFieldsAsHexCheck),
                                                                                @"SQLIncludeGenerated": IsOn(exportSQLIncludeGeneratedColumnsCheck),
																				@"SQLInsertNValue":     @([exportSQLInsertNValueTextField integerValue]),
																				@"SQLInsertDivider":    [[self class] describeSQLExportInsertDivider:(SPSQLExportInsertDivider)[exportSQLInsertDividerPopUpButton indexOfSelectedItem]]
																				}];

	if(includeStructure) {
		[dict addEntriesFromDictionary:@{
										 @"SQLIncludeAutoIncrementValue":  IsOn(exportSQLIncludeAutoIncrementValueButton),
										 @"SQLIncludeDropSyntax":          IsOn(exportSQLIncludeDropSyntaxCheck)
										 }];
	}

	return dict;
}

- (void)applySqlSettings:(NSDictionary *)settings
{
	id o;
	SPSQLExportInsertDivider div;

	if((o = [settings safeObjectForKey:@"SQLIncludeContent"]))   SetOnOff(o, exportSQLIncludeContentCheck);
	[self toggleSQLIncludeContent:exportSQLIncludeContentCheck];

	if((o = [settings safeObjectForKey:@"SQLIncludeDROP"]))    SetOnOff(o, exportSQLIncludeDropSyntaxCheck);
	[self toggleSQLIncludeDropSyntax:exportSQLIncludeDropSyntaxCheck];

	if((o = [settings safeObjectForKey:@"SQLIncludeStructure"])) SetOnOff(o, exportSQLIncludeStructureCheck);
	[self toggleSQLIncludeStructure:exportSQLIncludeStructureCheck];

	if((o = [settings safeObjectForKey:@"SQLIncludeErrors"]))    SetOnOff(o, exportSQLIncludeErrorsCheck);
	if((o = [settings safeObjectForKey:@"SQLUseUTF8BOM"]))       SetOnOff(o, exportUseUTF8BOMButton);
	if((o = [settings safeObjectForKey:@"SQLBLOBFieldsAsHex"]))  SetOnOff(o, exportSQLBLOBFieldsAsHexCheck);
    if((o = [settings safeObjectForKey:@"SQLIncludeGenerated"])) SetOnOff(o, exportSQLIncludeGeneratedColumnsCheck);
	if((o = [settings safeObjectForKey:@"SQLInsertNValue"]))     [exportSQLInsertNValueTextField setIntegerValue:[o integerValue]];
	if((o = [settings safeObjectForKey:@"SQLInsertDivider"]) && [[self class] copySQLExportInsertDividerForDescription:o to:&div]) [exportSQLInsertDividerPopUpButton selectItemAtIndex:div];

	if([exportSQLIncludeStructureCheck state] == NSOnState) {
		if((o = [settings safeObjectForKey:@"SQLIncludeAutoIncrementValue"]))  SetOnOff(o, exportSQLIncludeAutoIncrementValueButton);
		if((o = [settings safeObjectForKey:@"SQLIncludeDropSyntax"]))  SetOnOff(o, exportSQLIncludeDropSyntaxCheck);
	}
}

- (id)exporterSpecificSettingsForSchemaObject:(NSString *)name ofType:(SPTableType)type
{
	switch (exportType) {
		case SPCSVExport:
			return [self csvSpecificSettingsForSchemaObject:name ofType:type];
		case SPSQLExport:
			return [self sqlSpecificSettingsForSchemaObject:name ofType:type];
		case SPXMLExport:
			return [self xmlSpecificSettingsForSchemaObject:name ofType:type];
		case SPDotExport:
			return [self dotSpecificSettingsForSchemaObject:name ofType:type];
		case SPExcelExport:
		case SPHTMLExport:
		case SPPDFExport:
		default:
			@throw [NSException exceptionWithName:NSInternalInconsistencyException
										   reason:@"exportType not implemented!"
										 userInfo:@{@"exportType": @(exportType)}];
	}
}

- (void)applyExporterSpecificSettings:(id)settings forSchemaObject:(NSString *)name ofType:(SPTableType)type
{
	switch (exportType) {
		case SPCSVExport:
			return [self applyCsvSpecificSettings:settings forSchemaObject:name ofType:type];
		case SPSQLExport:
			return [self applySqlSpecificSettings:settings forSchemaObject:name ofType:type];
		case SPXMLExport:
			return [self applyXmlSpecificSettings:settings forSchemaObject:name ofType:type];
		case SPDotExport:
			return [self applyDotSpecificSettings:settings forSchemaObject:name ofType:type];
		case SPExcelExport:
		case SPHTMLExport:
		case SPPDFExport:
		default:
			@throw [NSException exceptionWithName:NSInternalInconsistencyException
										   reason:@"exportType not implemented!"
										 userInfo:@{@"exportType": @(exportType)}];
	}
}

- (id)dotSpecificSettingsForSchemaObject:(NSString *)name ofType:(SPTableType)type
{
	// Dot is a graph of the whole database - nothing to pick from
	return nil;
}

- (void)applyDotSpecificSettings:(id)settings forSchemaObject:(NSString *)name ofType:(SPTableType)type
{
	//should never be called
}

- (id)xmlSpecificSettingsForSchemaObject:(NSString *)name ofType:(SPTableType)type
{
	// XML per table setting is only yes/no
	if(type == SPTableTypeTable) {
		// we have to look through the table views' rows to find the current checkbox value...
		for (NSArray *table in tables) {
			if([[table firstObject] isEqualTo:name]) {
				return @([[table safeObjectAtIndex:2] boolValue]);
			}
		}
	}
	return nil;
}

- (void)applyXmlSpecificSettings:(id)settings forSchemaObject:(NSString *)name ofType:(SPTableType)type
{
	// XML per table setting is only yes/no
	if(type == SPTableTypeTable) {
		// we have to look through the table views' rows to find the appropriate table...
		for (NSMutableArray *table in tables) {
			if([[table firstObject] isEqualTo:name]) {
				[table safeReplaceObjectAtIndex:2 withObject:@([settings boolValue])];
				return;
			}
		}
	}
}

- (id)csvSpecificSettingsForSchemaObject:(NSString *)name ofType:(SPTableType)type
{
	// CSV per table setting is only yes/no
	if(type == SPTableTypeTable) {
		// we have to look through the table views rows to find the current checkbox value...
		for (NSArray *table in tables) {
			if([[table firstObject] isEqualTo:name]) {
				return @([[table safeObjectAtIndex:2] boolValue]);
			}
		}
	}
	return nil;
}

- (void)applyCsvSpecificSettings:(id)settings forSchemaObject:(NSString *)name ofType:(SPTableType)type
{
	// CSV per table setting is only yes/no
	if(type == SPTableTypeTable) {
		// we have to look through the table views' rows to find the appropriate table...
		for (NSMutableArray *table in tables) {
			if([[table firstObject] isEqualTo:name]) {
				[table safeReplaceObjectAtIndex:2 withObject:@([settings boolValue])];
				return;
			}
		}
	}
}

- (id)sqlSpecificSettingsForSchemaObject:(NSString *)name ofType:(SPTableType)type
{
	BOOL structure = ([exportSQLIncludeStructureCheck state] == NSOnState);
	BOOL content   = ([exportSQLIncludeContentCheck state] == NSOnState);
	BOOL drop      = ([exportSQLIncludeDropSyntaxCheck state] == NSOnState);

	// SQL allows per table setting of structure/content/drop table
	if(type == SPTableTypeTable) {
		// we have to look through the table views rows to find the current checkbox value...
		for (NSArray *table in tables) {
			if([[table firstObject] isEqualTo:name]) {
				NSMutableArray *flags = [NSMutableArray arrayWithCapacity:3];

				if (structure && [[table safeObjectAtIndex:1] boolValue]) {
					[flags safeAddObject:@"structure"];
				}

				if (content && [[table safeObjectAtIndex:2] boolValue]) {
					[flags safeAddObject:@"content"];
				}

				if (drop && [[table safeObjectAtIndex:3] boolValue]) {
					[flags safeAddObject:@"drop"];
				}

				return flags;
			}
		}
	}
	return nil;
}

- (void)applySqlSpecificSettings:(id)settings forSchemaObject:(NSString *)name ofType:(SPTableType)type
{
	BOOL structure = ([exportSQLIncludeStructureCheck state] == NSOnState);
	BOOL content   = ([exportSQLIncludeContentCheck state] == NSOnState);
	BOOL drop      = ([exportSQLIncludeDropSyntaxCheck state] == NSOnState);

	// SQL allows per table setting of structure/content/drop table
	if(type == SPTableTypeTable) {
		// we have to look through the table views' rows to find the appropriate table...
		for (NSMutableArray *table in tables) {
			if([[table objectAtIndex:0] isEqualTo:name]) {
				NSArray *flags = settings;

				[table safeReplaceObjectAtIndex:1 withObject:@((structure && [flags containsObject:@"structure"]))];
				[table safeReplaceObjectAtIndex:2 withObject:@((content   && [flags containsObject:@"content"]))];
				[table safeReplaceObjectAtIndex:3 withObject:@((drop      && [flags containsObject:@"drop"]))];
				return;
			}
		}
	}
}

#pragma mark - SPCSVExporterDelegate

- (void)csvExportProcessWillBegin:(SPCSVExporter *)exporter
{
	[exportProgressText displayIfNeeded];

	[exportProgressIndicator setIndeterminate:YES];
	[exportProgressIndicator setUsesThreadedAnimation:YES];
	[exportProgressIndicator startAnimation:self];

	// Only update the progress text if this is a table export
	if (exportSource == SPTableExport) {
		// Update the current table export index
		currentTableExportIndex = (exportTableCount - [exporters count]);

		[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Fetching data...", @"export label showing that the app is fetching data for a specific table"), currentTableExportIndex, exportTableCount, [exporter csvTableName]]];
	}
	else {
		[exportProgressText setStringValue:NSLocalizedString(@"Fetching data...", @"export label showing that the app is fetching data")];
	}

	[exportProgressText displayIfNeeded];
}

- (void)csvExportProcessComplete:(SPCSVExporter *)exporter
{
	NSUInteger exportCount = [exporters count];

	// If required add the next exporter to the operation queue
	if ((exportCount > 0) && (exportSource == SPTableExport)) {

		// If we're only exporting to a single file then write a header for the next table
		if (!exportToMultipleFiles) {

			// If we're exporting multiple tables to a single file then append some space and the next table's
			// name, but only if there is at least 2 exportes left.
			[[exporter exportOutputFile] writeData:[[NSString stringWithFormat:@"%@%@%@ %@%@%@",
													 [exporter csvLineEndingString],
													 [exporter csvLineEndingString],
													 NSLocalizedString(@"Table", @"csv export table heading"),
													 [(SPCSVExporter *)[exporters firstObject] csvTableName],
													 [exporter csvLineEndingString],
													 [exporter csvLineEndingString]] dataUsingEncoding:[exporter exportOutputEncoding]]];
		}
		// Otherwise close the file handle of the exporter that just finished
		// ensuring it's data is written to disk.
		else {
			[[exporter exportOutputFile] close];
		}

		[operationQueue addOperation:[exporters firstObject]];

		// Remove the exporter we just added to the operation queue from our list of exporters
		// so we know it's already been done.
		[exporters safeRemoveObjectAtIndex:0];
	}
	// Otherwise if the exporter list is empty, close the progress sheet
	else {
		// Close the last exporter's file handle
		[[exporter exportOutputFile] close];

		[self exportEnded];
	}
}

- (void)csvExportProcessWillBeginWritingData:(SPCSVExporter *)exporter
{
	// Only update the progress text if this is a table export
	if (exportSource == SPTableExport) {
		[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Writing data...", @"export label showing app if writing data for a specific table"), currentTableExportIndex, exportTableCount, [exporter csvTableName]]];
	}
	else {
		[exportProgressText setStringValue:NSLocalizedString(@"Writing data...", @"export label showing app is writing data")];
	}

	[exportProgressText displayIfNeeded];

	[exportProgressIndicator stopAnimation:self];
	[exportProgressIndicator setUsesThreadedAnimation:NO];
	[exportProgressIndicator setIndeterminate:NO];
	[exportProgressIndicator setDoubleValue:0];
}

- (void)csvExportProcessProgressUpdated:(SPCSVExporter *)exporter
{
	[exportProgressIndicator setDoubleValue:[exporter exportProgressValue]];
}

#pragma mark - SPSQLExporterDelegate

- (void)sqlExportProcessWillBegin:(SPSQLExporter *)exporter
{
	[exportProgressTitle setStringValue:NSLocalizedString(@"Exporting SQL", @"text showing that the application is exporting SQL")];
	[exportProgressText setStringValue:NSLocalizedString(@"Dumping...", @"text showing that app is writing dump")];

	[exportProgressTitle displayIfNeeded];
	[exportProgressText displayIfNeeded];
}

- (void)sqlExportProcessComplete:(SPSQLExporter *)exporter
{
	[self exportEnded];

	// Check for errors and display the errors sheet if necessary
	if ([exporter didExportErrorsOccur]) {
		[self openExportErrorsSheetWithString:[exporter sqlExportErrors]];
	}
}

- (void)sqlExportProcessProgressUpdated:(SPSQLExporter *)exporter
{
	if ([exportProgressIndicator doubleValue] == 0) {
		[exportProgressIndicator stopAnimation:self];
		[exportProgressIndicator setIndeterminate:NO];
	}

	[exportProgressIndicator setDoubleValue:[exporter exportProgressValue]];
}

- (void)sqlExportProcessWillBeginFetchingData:(SPSQLExporter *)exporter
{
	[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Fetching data...", @"export label showing that the app is fetching data for a specific table"), [exporter sqlCurrentTableExportIndex], exportTableCount, [exporter sqlExportCurrentTable]]];

	[exportProgressIndicator startAnimation:self];
	[exportProgressIndicator setUsesThreadedAnimation:YES];
	[exportProgressIndicator setIndeterminate:YES];
	[exportProgressIndicator setDoubleValue:0];
}

- (void)sqlExportProcessWillBeginWritingData:(SPSQLExporter *)exporter
{
	[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Writing data...", @"export label showing app if writing data for a specific table"), [exporter sqlCurrentTableExportIndex], exportTableCount, [exporter sqlExportCurrentTable]]];
}

#pragma mark - SPXMLExporterDelegate

- (void)xmlExportProcessWillBegin:(SPXMLExporter *)exporter
{
	[exportProgressText displayIfNeeded];

	[exportProgressIndicator setIndeterminate:YES];
	[exportProgressIndicator setUsesThreadedAnimation:YES];
	[exportProgressIndicator startAnimation:self];

	// Only update the progress text if this is a table export
	if (exportSource == SPTableExport) {

		// Update the current table export index
		currentTableExportIndex = (exportTableCount - [exporters count]);

		[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Fetching data...", @"export label showing that the app is fetching data for a specific table"), currentTableExportIndex, exportTableCount, [exporter xmlTableName]]];
	}
	else {
		[exportProgressText setStringValue:NSLocalizedString(@"Fetching data...", @"export label showing that the app is fetching data")];
	}

	[exportProgressText displayIfNeeded];
}

- (void)xmlExportProcessComplete:(SPXMLExporter *)exporter
{
	NSUInteger exportCount = [exporters count];

	// If required add the next exporter to the operation queue
	if ((exportCount > 0) && (exportSource == SPTableExport)) {

		// If we're exporting to multiple files then close the file handle of the exporter
		// that just finished, ensuring its data is written to disk.
		if (exportToMultipleFiles) {
			NSString *string = @"";

			if ([exporter xmlFormat] == SPXMLExportMySQLFormat) {
				string = (exportSource == SPTableExport) ? @"</database>\n</mysqldump>\n" : @"</resultset>\n";;
			}
			else if ([exporter xmlFormat] == SPXMLExportPlainFormat) {
				string = [NSString stringWithFormat:@"</%@>\n", [[tableDocumentInstance database] HTMLEscapeString]];
			}

			[[exporter exportOutputFile] writeData:[string dataUsingEncoding:[connection stringEncoding]]];
			[[exporter exportOutputFile] close];
		}

		[operationQueue addOperation:[exporters firstObject]];

		// Remove the exporter we just added to the operation queue from our list of exporters
		// so we know it's already been done.
		[exporters safeRemoveObjectAtIndex:0];
	}
	// Otherwise if the exporter list is empty, close the progress sheet
	else {
		NSString *string = @"";

		if ([exporter xmlFormat] == SPXMLExportMySQLFormat) {
			string = (exportSource == SPTableExport) ? @"</database>\n</mysqldump>\n" : @"</resultset>\n";;
		}
		else if ([exporter xmlFormat] == SPXMLExportPlainFormat) {
			string = [NSString stringWithFormat:@"</%@>\n", [[tableDocumentInstance database] HTMLEscapeString]];
		}

		[[exporter exportOutputFile] writeData:[string dataUsingEncoding:[connection stringEncoding]]];
		[[exporter exportOutputFile] close];

		[self exportEnded];
	}
}

- (void)xmlExportProcessProgressUpdated:(SPXMLExporter *)exporter
{
	[[exportProgressIndicator onMainThread] setDoubleValue:[exporter exportProgressValue]];
}

- (void)xmlExportProcessWillBeginWritingData:(SPXMLExporter *)exporter
{
	// Only update the progress text if this is a table export
	if (exportSource == SPTableExport) {
		[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Writing data...", @"export label showing app if writing data for a specific table"), currentTableExportIndex, exportTableCount, [exporter xmlTableName]]];
	}
	else {
		[exportProgressText setStringValue:NSLocalizedString(@"Writing data...", @"export label showing app is writing data")];
	}

	[exportProgressText displayIfNeeded];

	[exportProgressIndicator stopAnimation:self];
	[exportProgressIndicator setUsesThreadedAnimation:NO];
	[exportProgressIndicator setIndeterminate:NO];
	[exportProgressIndicator setDoubleValue:0];
}

#pragma mark - SPDotExporterDelegate

- (void)dotExportProcessWillBegin:(SPDotExporter *)exporter
{
	[exportProgressTitle setStringValue:NSLocalizedString(@"Exporting Dot File", @"text showing that the application is exporting a Dot file")];
	[exportProgressText setStringValue:NSLocalizedString(@"Dumping...", @"text showing that app is writing dump")];

	[exportProgressTitle displayIfNeeded];
	[exportProgressText displayIfNeeded];
	[exportProgressIndicator stopAnimation:self];
	[exportProgressIndicator setIndeterminate:NO];
}

- (void)dotExportProcessComplete:(SPDotExporter *)exporter
{
	[self exportEnded];
}

- (void)dotExportProcessProgressUpdated:(SPDotExporter *)exporter
{
	[exportProgressIndicator setDoubleValue:[exporter exportProgressValue]];
}

- (void)dotExportProcessWillBeginFetchingData:(SPDotExporter *)exporter forTableWithIndex:(NSUInteger)tableIndex
{
	// Update the current table export index
	currentTableExportIndex = tableIndex;

	[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Fetching data...", @"export label showing that the app is fetching data for a specific table"), currentTableExportIndex, exportTableCount, [exporter dotExportCurrentTable]]];

	[exportProgressText displayIfNeeded];
}

- (void)dotExportProcessWillBeginFetchingRelationsData:(SPDotExporter *)exporter
{
	[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Fetching relations data...", @"export label showing app is fetching relations data for a specific table"), currentTableExportIndex, exportTableCount, [exporter dotExportCurrentTable]]];

	[exportProgressText displayIfNeeded];
	[exportProgressIndicator setIndeterminate:YES];
	[exportProgressIndicator setUsesThreadedAnimation:YES];
	[exportProgressIndicator startAnimation:self];
}

#pragma mark - SPPDFExporterDelegate

- (void)pdfExportProcessWillBegin:(SPPDFExporter *)exporter
{
}

- (void)pdfExportProcessComplete:(SPPDFExporter *)exporter
{
	[self exportEnded];
}

- (void)pdfExportProcessWillBeginWritingData:(SPPDFExporter *)exporter
{
}

#pragma mark - SPHTMLExporterDelegate

- (void)htmlExportProcessWillBegin:(SPHTMLExporter *)exporter
{
}

- (void)htmlExportProcessComplete:(SPHTMLExporter *)exporter
{
	[self exportEnded];
}

- (void)htmlExportProcessWillBeginWritingData:(SPHTMLExporter *)exporter
{
}

#pragma mark -
#pragma mark Memory Management
- (void)dealloc
{
	// relinquish access to userChosenDirectory
	[userChosenDirectory stopAccessingSecurityScopedResource];
	[changeExportOutputPathPanel.URL stopAccessingSecurityScopedResource];

	[self setServerSupport:nil];
	
}

@end

#pragma mark -

BOOL IS_TOKEN(id x)
{
	return [x isKindOfClass:[SPExportFileNameTokenObject class]];
}

BOOL IS_STRING(id x)
{
	return [x isKindOfClass:[NSString class]];
}

NSNumber *IsOn(NSButton *obj)
{
	return (([obj state] == NSOnState)? @YES : @NO);
}

void SetOnOff(NSNumber *ref,NSButton *obj)
{
	[obj setState:([ref boolValue] ? NSOnState : NSOffState)];
}
