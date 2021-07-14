//
//  SPDatabaseDocument.h
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

@class SPConnectionController;
@class SPProcessListController;
@class SPServerVariablesController;
@class SPUserManager;
@class SPWindowController;
@class SPSplitView;
@class SPDatabaseData;
@class SPTablesList;
@class SPTableStructure;
@class SPTableContent;
@class SPTableData;
@class SPServerSupport;
@class SPCustomQuery;
@class SPDatabaseStructure;
@class SPMySQLConnection;
@class SPCharsetCollationHelper;
@class SPGotoDatabaseController;
@class SPCreateDatabaseInfo;
@class SPExtendedTableInfo;
@class SPTableTriggers;
@class SPTableRelations;
@class SPHelpViewerClient;
@class SPDataImport;

#import "SPDatabaseContentViewDelegate.h"
#import "SPConnectionControllerDelegateProtocol.h"
#import "SPThreadAdditions.h"
#import "SPConstants.h"

#import <WebKit/WebKit.h>
#import <SPMySQL/SPMySQLConnectionDelegate.h>

/**
 * The SPDatabaseDocument class controls the primary database view window.
 */
@interface SPDatabaseDocument : NSObject <SPConnectionControllerDelegateProtocol, SPMySQLConnectionDelegate, NSTextFieldDelegate, NSToolbarDelegate, SPCountedObject, WebFrameLoadDelegate>
{
	// IBOutlets
	IBOutlet SPTablesList *tablesListInstance;
	IBOutlet SPTableStructure *tableSourceInstance;
	IBOutlet SPTableContent <SPDatabaseContentViewDelegate> *tableContentInstance;
	IBOutlet SPTableRelations *tableRelationsInstance;
	IBOutlet SPTableTriggers *tableTriggersInstance;
	IBOutlet SPCustomQuery *customQueryInstance;
	IBOutlet SPDataImport *tableDumpInstance;
	@public IBOutlet SPTableData *tableDataInstance;
	@public IBOutlet SPExtendedTableInfo *extendedTableInfoInstance;
	IBOutlet SPDatabaseData *databaseDataInstance;
	IBOutlet id spHistoryControllerInstance;
	IBOutlet id exportControllerInstance;
	IBOutlet SPHelpViewerClient *helpViewerClientInstance;

	IBOutlet id statusTableAccessoryView;
	IBOutlet id statusTableView;
	IBOutlet id statusTableCopyChecksum;

    SPUserManager *userManagerInstance;
	SPServerSupport *serverSupport;
	
	IBOutlet NSSearchField *listFilterField;

	IBOutlet NSScrollView *tableInfoScrollView;
	IBOutlet NSScrollView *documentActivityScrollView;

	IBOutlet NSView *parentView;
	
	IBOutlet id databaseSheet;
	IBOutlet id databaseCopySheet;
	IBOutlet id databaseRenameSheet;
	
	IBOutlet id databaseAlterSheet;
	IBOutlet NSPopUpButton *databaseAlterEncodingButton;
	IBOutlet NSPopUpButton *databaseAlterCollationButton;
	
	SPCharsetCollationHelper *alterDatabaseCharsetHelper;

	@public IBOutlet NSProgressIndicator* queryProgressBar;
	IBOutlet NSBox *taskProgressLayer;
	IBOutlet id taskProgressIndicator;
	IBOutlet id taskDescriptionText;
	IBOutlet id taskDurationTime;
	IBOutlet NSButton *taskCancelButton;
	
	IBOutlet id databaseNameField;
	IBOutlet id databaseEncodingButton;
	IBOutlet id databaseCollationButton;
	IBOutlet id addDatabaseButton;
	
	SPCharsetCollationHelper *addDatabaseCharsetHelper;

	IBOutlet id databaseCopyNameField;
	IBOutlet NSButton *copyDatabaseDataButton;
	IBOutlet id copyDatabaseMessageField;
	IBOutlet id copyDatabaseButton;
	
	IBOutlet id databaseRenameNameField;
	IBOutlet id renameDatabaseMessageField;
	IBOutlet id renameDatabaseButton;

	IBOutlet NSPopUpButton *chooseDatabaseButton;
	IBOutlet NSSegmentedControl *historyControl;
	IBOutlet NSTabView *tableTabView;
	
	IBOutlet NSTableView *tableInfoTable;
	@public IBOutlet SPSplitView *contentViewSplitter;
	IBOutlet SPSplitView *tableInfoSplitView;
	
	IBOutlet NSPopUpButton *encodingPopUp;

	IBOutlet NSTextView *customQueryTextView;
	
	IBOutlet NSTableView *dbTablesTableView;

	IBOutlet NSTextField *createTableSyntaxTextField;
	IBOutlet NSTextView *createTableSyntaxTextView;
	IBOutlet NSWindow *createTableSyntaxWindow;
	IBOutlet NSWindow *connectionErrorDialog;

	IBOutlet id saveConnectionAccessory;
	IBOutlet NSButton *saveConnectionIncludeData;
	IBOutlet NSButton *saveConnectionIncludeQuery;
	IBOutlet NSButton *saveConnectionSavePassword;
	IBOutlet id saveConnectionSavePasswordAlert;
	IBOutlet NSButton *saveConnectionEncrypt;
	IBOutlet NSButton *saveConnectionAutoConnect;
	IBOutlet NSSecureTextField *saveConnectionEncryptString;
	
	IBOutlet id inputTextWindow;
	IBOutlet id inputTextWindowHeader;
	IBOutlet id inputTextWindowMessage;
	IBOutlet id inputTextWindowSecureTextField;
	NSInteger passwordSheetReturnCode;

	// Master connection
	SPMySQLConnection *mySQLConnection;

	// Controllers
	SPConnectionController *connectionController;
	SPProcessListController *processListController;
	SPServerVariablesController *serverVariablesController;
	NSString *selectedTableName;
	SPTableType selectedTableType;

	BOOL structureLoaded;
	BOOL contentLoaded;
	BOOL statusLoaded;
	BOOL triggersLoaded;
	BOOL relationsLoaded;
	BOOL initComplete;
	BOOL allowSplitViewResizing;

	NSString *selectedDatabase;
	NSString *mySQLVersion;
	NSString *selectedDatabaseEncoding;
	NSUserDefaults *prefs;
	NSUndoManager *undoManager;

	NSMenu *selectEncodingMenu;
	BOOL _supportsEncoding;
	BOOL _isConnected;
	NSInteger _isWorkingLevel;
	BOOL _mainNibLoaded;
	BOOL databaseListIsSelectable;
	NSInteger _queryMode;
	BOOL _isSavedInBundle;

	BOOL _workingTimeout;

	NSWindow *taskProgressWindow;
	BOOL taskDisplayIsIndeterminate;
	CGFloat taskProgressValue;
	CGFloat taskDisplayLastValue;
	CGFloat taskProgressValueDisplayInterval;
	NSTimer *taskDrawTimer;
	NSTimer *queryExecutionTimer;
	NSDate *taskFadeInStartDate;
	NSDate *queryStartDate;
	BOOL taskCanBeCancelled;
	id taskCancellationCallbackObject;
	SEL taskCancellationCallbackSelector;

	NSToolbarItem *chooseDatabaseToolbarItem;
	
	WebView *printWebView;

	NSMutableArray *allDatabases;
	NSMutableArray *allSystemDatabases;
	
	NSString *queryEditorInitString;
	
	NSURL *sqlFileURL;
	NSStringEncoding sqlFileEncoding;
	NSURL *spfFileURL;
	NSDictionary *spfSession;
	NSMutableDictionary *spfPreferences;
	NSMutableDictionary *spfDocData;

	NSMutableArray *runningActivitiesArray;

	NSThread *printThread;
	
	NSArray *statusValues;

	// Alert return codes
	NSInteger saveDocPrefSheetStatus;
	NSInteger confirmCopyDatabaseReturnCode;

	// Properties
	BOOL isProcessing;
	NSString *processID;
	BOOL windowTitleStatusViewIsVisible;
	SPDatabaseStructure *databaseStructureRetrieval;
	SPGotoDatabaseController *gotoDatabaseController;
	
	int64_t instanceId;
}

@property (nonatomic, strong) NSTableView *dbTablesTableView;
@property (readwrite, strong) NSURL *sqlFileURL;
@property (readwrite) NSStringEncoding sqlFileEncoding;
@property (readwrite) BOOL isProcessing;
@property (readwrite, copy) NSString *processID;
@property (readonly, nonatomic, strong) NSToolbar *mainToolbar;

@property (nonatomic, strong, readonly) SPWindowController *parentWindowController;
@property (readonly, strong) SPServerSupport *serverSupport;
@property (readonly, strong) SPDatabaseStructure *databaseStructureRetrieval;
@property (readonly, strong) SPDataImport *tableDumpInstance;
@property (readonly, strong) SPTablesList *tablesListInstance;
@property (readonly, strong) SPCustomQuery *customQueryInstance;
@property (readonly, strong) SPTableContent <SPDatabaseContentViewDelegate> *tableContentInstance;

@property (readonly) int64_t instanceId;
@property (strong) IBOutlet NSButton *multipleLineEditingButton;

- (instancetype)initWithWindowController:(SPWindowController *)windowController;

- (SPHelpViewerClient *)helpViewerClient;

- (BOOL)isUntitled;
- (BOOL)couldCommitCurrentViewActions;

- (void)initQueryEditorWithString:(NSString *)query;

// Connection callback and methods
- (void)setConnection:(SPMySQLConnection *)theConnection;
- (SPMySQLConnection *)getConnection;

// Database methods
- (IBAction)chooseDatabase:(id)sender;
- (void)selectDatabase:(NSString *)aDatabase item:(NSString *)anItem;
- (IBAction)makeTableListFilterHaveFocus:(id)sender;
- (NSArray *)allDatabaseNames;
- (NSArray *)allSystemDatabaseNames;
- (NSDictionary *)getDbStructure;
- (NSArray *)allSchemaKeys;

// Task progress and notification methods
- (void)startTaskWithDescription:(NSString *)description;
- (void)fadeInTaskProgressWindow:(NSTimer *)theTimer;
- (void)setTaskDescription:(NSString *)description;
- (void)setTaskPercentage:(CGFloat)taskPercentage;
- (void)setTaskProgressToIndeterminateAfterDelay:(BOOL)afterDelay;
- (void)endTask;
- (void)enableTaskCancellationWithTitle:(NSString *)buttonTitle callbackObject:(id)callbackObject callbackFunction:(SEL)callbackFunction;
- (void)disableTaskCancellation;
- (IBAction)cancelTask:(id)sender;
- (BOOL)isWorking;
- (void)setDatabaseListIsSelectable:(BOOL)isSelectable;
- (void)centerTaskWindow;
- (void)setTaskIndicatorShouldAnimate:(BOOL)shouldAnimate;

// Encoding methods
- (void)setConnectionEncoding:(NSString *)mysqlEncoding reloadingViews:(BOOL)reloadViews;
- (NSString *)databaseEncoding;
- (void)detectDatabaseEncoding;
- (BOOL)supportsEncoding;
- (void)updateEncodingMenuWithSelectedEncoding:(NSNumber *)encodingTag;
- (NSNumber *)encodingTagFromMySQLEncoding:(NSString *)mysqlEncoding;
- (NSString *)mysqlEncodingFromEncodingTag:(NSNumber *)encodingTag;

// Table methods
- (IBAction)saveCreateSyntax:(id)sender;
- (IBAction)copyCreateTableSyntaxFromSheet:(id)sender;
- (IBAction)exportSelectedTablesAs:(id)sender;
- (IBAction)multipleLineEditingButtonClicked:(NSButton *)sender;

// Other methods
- (IBAction)closeSheet:(id)sender;
- (IBAction)closePanelSheet:(id)sender;
- (IBAction)validateSaveConnectionAccessory:(id)sender;
- (IBAction)closePasswordSheet:(id)sender;
- (IBAction)copyChecksumFromSheet:(id)sender;

- (void)setQueryMode:(NSInteger)theQueryMode;
- (void)doPerformQueryService:(NSString *)query;
- (void)doPerformLoadQueryService:(NSString *)query;
- (void)closeConnection;
- (NSWindow *)getCreateTableSyntaxWindow;

- (void)refreshCurrentDatabase;

- (void)saveConnectionPanelDidEnd:(NSSavePanel *)panel returnCode:(NSInteger)returnCode  contextInfo:(void  *)contextInfo;
- (BOOL)saveDocumentWithFilePath:(NSString *)fileName inBackground:(BOOL)saveInBackground onlyPreferences:(BOOL)saveOnlyPreferences contextInfo:(NSDictionary*)contextInfo;
- (void)setIsSavedInBundle:(BOOL)savedInBundle;
- (void)setFileURL:(NSURL *)fileURL;
- (void)connect;

// Accessor methods
- (NSString *)host;
- (NSString *)name;
- (NSString *)database;
- (NSString *)port;
- (NSString *)mySQLVersion;
- (NSString *)user;
- (NSString *)connectionID;
- (NSString *)tabTitleForTooltip;
- (BOOL)isSaveInBundle;
- (NSURL *)fileURL;
- (NSString *)displayName;
- (NSUndoManager *)undoManager;
- (NSArray *)allTableNames;
- (SPCreateDatabaseInfo *)createDatabaseInfo;
- (SPTableViewType) currentlySelectedView;

// Notification center methods
- (void)willPerformQuery:(NSNotification *)notification;
- (void)hasPerformedQuery:(NSNotification *)notification;
- (void)applicationWillTerminate:(NSNotification *)notification;

// Menu methods
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
- (IBAction)saveConnectionSheet:(id)sender;
- (BOOL)isCustomQuerySelected;
- (IBAction)showConnectionDebugMessages:(id)sender;

// Toolbar methods
- (void)updateWindowTitle:(id)sender;
- (NSString *)selectedToolbarItemIdentifier;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag;

// Tab methods
- (BOOL)parentTabShouldClose;

- (void)setIsProcessing:(BOOL)value;
- (BOOL)isProcessing;

- (NSWindow *)parentWindowControllerWindow;

// Scripting
- (void)handleSchemeCommand:(NSDictionary*)commandDict;
- (void)registerActivity:(NSDictionary*)commandDict;
- (void)removeRegisteredActivity:(NSInteger)pid;
- (void)setActivityPaneHidden:(NSNumber*)hide;
- (NSArray*)runningActivities;
- (NSDictionary*)shellVariables;

// State saving and setting
- (NSDictionary *) stateIncludingDetails:(NSDictionary *)detailsToReturn;
- (BOOL)setState:(NSDictionary *)stateDetails;
- (BOOL)setState:(NSDictionary *)stateDetails fromFile:(BOOL)spfBased;
- (BOOL)setStateFromConnectionFile:(NSString *)path;
- (void)restoreSession;

- (SPConnectionController*)connectionController;

#pragma mark - SPDatabaseViewController

// Accessors
- (NSString *)table;
- (SPTableType)tableType;

- (BOOL)structureLoaded;
- (BOOL)contentLoaded;
- (BOOL)statusLoaded;

- (void)setStructureRequiresReload:(BOOL)reload;
- (void)setContentRequiresReload:(BOOL)reload;
- (void)setStatusRequiresReload:(BOOL)reload;
- (void)setRelationsRequiresReload:(BOOL)reload;

// Table control
- (void)loadTable:(NSString *)aTable ofType:(SPTableType)aTableType;

- (NSView *)databaseView;

#pragma mark - SPPrintController

- (void)startPrintDocumentOperation;
- (void)generateHTMLForPrinting;
- (void)generateTableInfoHTMLForPrinting;

- (NSArray *)columnNames;
- (NSMutableDictionary *)connectionInformation;

#pragma mark - Menu actions called from SPAppController

#pragma mark File menu

- (void)exportData;
- (void)addConnectionToFavorites;
- (void)importFile;
- (void)importFromClipboard;
- (void)printDocument;

#pragma mark View menu

- (void)viewStructure;
- (void)viewContent;
- (void)viewQuery;
- (void)viewStatus;
- (void)viewRelations;
- (void)viewTriggers;
- (void)backForwardInHistory:(id)sender;
- (void)toggleConsole;
- (void)showConsole;
- (void)toggleNavigator;

#pragma mark Database menu

- (void)showGotoDatabase;
- (void)addDatabase:(id)sender;
- (void)removeDatabase:(id)sender;
- (void)copyDatabase;
- (void)renameDatabase;
- (void)alterDatabase;
- (void)refreshTables;
- (void)flushPrivileges;
- (void)setDatabases;
- (void)showUserManager;
- (void)chooseEncoding:(id)sender;
- (void)openDatabaseInNewTab;
- (void)showServerVariables;
- (void)showServerProcesses;
- (void)shutdownServer;

#pragma mark Table menu

- (void)focusOnTableContentFilter;
- (void)showFilterTable;
- (void)copyCreateTableSyntax:(SPDatabaseDocument *)sender;
- (void)showCreateTableSyntax:(SPDatabaseDocument *)sender;
- (void)checkTable;
- (void)repairTable;
- (void)analyzeTable;
- (void)optimizeTable;
- (void)flushTable;
- (void)checksumTable;

#pragma mark Help menu

- (void)showMySQLHelp;

@end
