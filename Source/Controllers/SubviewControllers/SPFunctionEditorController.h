//
//  SPFunctionEditorController.h
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

#import <Cocoa/Cocoa.h>

@class SPDatabaseDocument;
@class SPPostgresConnection;

/**
 * Enumeration for the type of routine being edited.
 */
typedef NS_ENUM(NSInteger, SPRoutineType) {
	SPRoutineTypeFunction = 0,
	SPRoutineTypeProcedure = 1
};

/**
 * @class SPFunctionEditorController SPFunctionEditorController.h
 *
 * This class provides a sheet for creating and editing PostgreSQL functions and procedures.
 */
@interface SPFunctionEditorController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
{
	// Main sheet
	IBOutlet NSPanel *functionSheet;

	// Function properties
	IBOutlet NSTextField *functionNameField;
	IBOutlet NSPopUpButton *routineTypePopup;
	IBOutlet NSPopUpButton *returnTypePopup;
	IBOutlet NSPopUpButton *languagePopup;
	IBOutlet NSPopUpButton *volatilityPopup;
	IBOutlet NSPopUpButton *securityPopup;
	IBOutlet NSButton *strictCheckbox;
	IBOutlet NSButton *leakproofCheckbox;

	// Parameters table
	IBOutlet NSTableView *parametersTableView;
	IBOutlet NSButton *addParameterButton;
	IBOutlet NSButton *removeParameterButton;

	// Function body
	IBOutlet NSTextView *functionBodyTextView;
	IBOutlet NSScrollView *functionBodyScrollView;

	// Buttons
	IBOutlet NSButton *createButton;
	IBOutlet NSButton *cancelButton;

	// Status
	IBOutlet NSTextField *statusLabel;
	IBOutlet NSProgressIndicator *progressIndicator;

	// Internal state
	SPDatabaseDocument *tableDocumentInstance;
	SPPostgresConnection *connection;
	NSString *currentSchema;
	NSString *editingFunctionName;
	NSMutableArray *parameters;
	BOOL isEditMode;
}

@property (nonatomic, strong) SPDatabaseDocument *tableDocumentInstance;
@property (nonatomic, copy) NSString *currentSchema;
@property (nonatomic, strong) NSMutableArray *parameters;

#pragma mark - Initialization

/**
 * Initialize with a database document reference.
 */
- (instancetype)initWithDocument:(SPDatabaseDocument *)document;

#pragma mark - Sheet Management

/**
 * Display the sheet for creating a new function.
 */
- (void)showCreateFunctionSheetAttachedToWindow:(NSWindow *)window;

/**
 * Display the sheet for creating a new procedure.
 */
- (void)showCreateProcedureSheetAttachedToWindow:(NSWindow *)window;

/**
 * Display the sheet for editing an existing function.
 */
- (void)showEditFunctionSheet:(NSString *)functionName attachedToWindow:(NSWindow *)window;

/**
 * Display the sheet for editing an existing procedure.
 */
- (void)showEditProcedureSheet:(NSString *)procedureName attachedToWindow:(NSWindow *)window;

#pragma mark - Actions

/**
 * Create or update the function/procedure.
 */
- (IBAction)confirmFunction:(id)sender;

/**
 * Cancel and close the sheet.
 */
- (IBAction)cancelFunction:(id)sender;

/**
 * Add a new parameter.
 */
- (IBAction)addParameter:(id)sender;

/**
 * Remove the selected parameter.
 */
- (IBAction)removeParameter:(id)sender;

/**
 * Called when routine type changes.
 */
- (IBAction)routineTypeChanged:(id)sender;

#pragma mark - Function Operations

/**
 * Create a new function in the database.
 */
- (BOOL)createFunction;

/**
 * Replace an existing function.
 */
- (BOOL)replaceFunction;

/**
 * Load function properties for editing.
 */
- (void)loadFunctionProperties:(NSString *)functionName;

/**
 * Get the CREATE FUNCTION SQL statement.
 */
- (NSString *)createFunctionSQL;

/**
 * Get the CREATE PROCEDURE SQL statement.
 */
- (NSString *)createProcedureSQL;

@end

@protocol SPFunctionEditorControllerDelegate <NSObject>

@optional
/**
 * Called when a function has been successfully created or modified.
 */
- (void)functionEditorDidFinish:(SPFunctionEditorController *)editor success:(BOOL)success;

@end
