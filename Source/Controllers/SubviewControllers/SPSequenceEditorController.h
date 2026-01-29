//
//  SPSequenceEditorController.h
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

#import <Cocoa/Cocoa.h>

@class SPDatabaseDocument;
@class SPPostgresConnection;

/**
 * @class SPSequenceEditorController SPSequenceEditorController.h
 *
 * This class provides a sheet for creating and editing PostgreSQL sequences.
 * Sequences are database objects that generate unique numeric identifiers.
 */
@interface SPSequenceEditorController : NSWindowController
{
	// Main sheet
	IBOutlet NSPanel *sequenceSheet;

	// Sequence properties
	IBOutlet NSTextField *sequenceNameField;
	IBOutlet NSTextField *startValueField;
	IBOutlet NSTextField *incrementByField;
	IBOutlet NSTextField *minValueField;
	IBOutlet NSTextField *maxValueField;
	IBOutlet NSTextField *cacheValueField;
	IBOutlet NSButton *cycleCheckbox;
	IBOutlet NSPopUpButton *dataTypePopup;
	IBOutlet NSPopUpButton *ownerPopup;

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
	NSString *editingSequenceName;
	BOOL isEditMode;
}

@property (nonatomic, strong) SPDatabaseDocument *tableDocumentInstance;
@property (nonatomic, copy) NSString *currentSchema;

#pragma mark - Initialization

/**
 * Initialize with a database document reference.
 */
- (instancetype)initWithDocument:(SPDatabaseDocument *)document;

#pragma mark - Sheet Management

/**
 * Display the sheet for creating a new sequence.
 */
- (void)showCreateSequenceSheetAttachedToWindow:(NSWindow *)window;

/**
 * Display the sheet for editing an existing sequence.
 */
- (void)showEditSequenceSheet:(NSString *)sequenceName attachedToWindow:(NSWindow *)window;

#pragma mark - Actions

/**
 * Create or update the sequence.
 */
- (IBAction)confirmSequence:(id)sender;

/**
 * Cancel and close the sheet.
 */
- (IBAction)cancelSequence:(id)sender;

/**
 * Reset all fields to defaults.
 */
- (IBAction)resetToDefaults:(id)sender;

#pragma mark - Sequence Operations

/**
 * Create a new sequence in the database.
 */
- (BOOL)createSequence;

/**
 * Alter an existing sequence.
 */
- (BOOL)alterSequence;

/**
 * Load sequence properties for editing.
 */
- (void)loadSequenceProperties:(NSString *)sequenceName;

/**
 * Get the CREATE SEQUENCE SQL statement.
 */
- (NSString *)createSequenceSQL;

/**
 * Get the ALTER SEQUENCE SQL statement.
 */
- (NSString *)alterSequenceSQL;

@end

@protocol SPSequenceEditorControllerDelegate <NSObject>

@optional
/**
 * Called when a sequence has been successfully created or modified.
 */
- (void)sequenceEditorDidFinish:(SPSequenceEditorController *)editor success:(BOOL)success;

@end
