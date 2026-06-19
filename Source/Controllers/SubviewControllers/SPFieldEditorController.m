//
//  SPFieldEditorController.m
//  sequel-pro
//
//  Created by Hans-Jörg Bibiko on July 16, 2009.
//  Copyright (c) 2009 Hans-Jörg Bibiko. All rights reserved.
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

#import "SPFieldEditorController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "RegexKitLite.h"
#import "SPTooltip.h"
#import "SPGeometryDataView.h"
#import "SPCopyTable.h"
#import "SPWindow.h"
#include <objc/objc-runtime.h>
#include <stdlib.h>
#import "SPCustomQuery.h"
#import "SPTableContent.h"
#import "SPJSONFormatter.h"
#import <SPMySQL/SPMySQL.h>
#import "SPFunctions.h"
#import "SAPHPSerializedValue.h"

#import "sequel-ace-Swift.h"

typedef enum {
	TextSegment = 0,
	ImageSegment,
	HexSegment,
	JsonSegment,
} FieldEditorSegment;

@interface SPFieldEditorController () <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property(nonatomic, strong) NSMenuItem *phpSerializedEditorMenuItem;
@property(nonatomic, strong) NSPanel *phpSerializedEditorSheet;
@property(nonatomic, strong) NSOutlineView *phpSerializedOutlineView;
@property(nonatomic, strong) NSTextView *phpSerializedValueTextView;
@property(nonatomic, strong) NSPopUpButton *phpSerializedTypePopup;
@property(nonatomic, strong) NSTextField *phpSerializedSelectionLabel;
@property(nonatomic, strong) NSButton *phpSerializedUpdateButton;
@property(nonatomic, strong) NSButton *phpSerializedAddButton;
@property(nonatomic, strong) NSButton *phpSerializedDeleteButton;
@property(nonatomic, strong) SAPHPSerializedEntry *phpSerializedRootEntry;
@property(nonatomic, weak) SAPHPSerializedEntry *phpSerializedSelectedEntry;
@property(nonatomic) BOOL phpSerializedEditorAutomaticallyOpened;

- (void)refreshPHPSerializedEditorAvailability;
- (void)openPHPSerializedEditorIfCurrentTextIsStructured;
- (IBAction)openPHPSerializedEditor:(id)sender;
- (IBAction)applyPHPSerializedEditor:(id)sender;
- (IBAction)cancelPHPSerializedEditor:(id)sender;
- (IBAction)updatePHPSerializedSelectedValue:(id)sender;
- (IBAction)addPHPSerializedChild:(id)sender;
- (IBAction)deletePHPSerializedEntry:(id)sender;
- (void)buildPHPSerializedEditorSheetIfNeeded;
- (BOOL)populatePHPSerializedEditorFromCurrentTextShowingError:(BOOL)showError;
- (BOOL)commitPHPSerializedSelectedValueShowingError:(BOOL)showError;

@end

@implementation SPFieldEditorController

@synthesize editedFieldInfo;
@synthesize textMaxLength = maxTextLength;
@synthesize fieldType;
@synthesize fieldEncoding;
@synthesize displayFormatter;
@synthesize allowNULL = _allowNULL;

/**
 * Initialise an instance of SPFieldEditorController using the XIB “FieldEditorSheet.xib”. Init the available Quciklook format by reading
 * EditorQuickLookTypes.plist and if given user-defined format store in the Preferences for key (SPQuickLookTypes).
 */
- (instancetype)init
{
	if ((self = [super initWithWindowNibName:@"FieldEditorSheet"]))
	{
		// force the nib to be loaded
		(void) [self window];
		counter = 0;
		maxTextLength = 0;
		stringValue = nil;
		_isEditable = NO;
		_isBlob = NO;
		_allowNULL = YES;
		_isGeometry = NO;
		contextInfo = nil;
		callerInstance = nil;
		doGroupDueToChars = NO;

		prefs = [NSUserDefaults standardUserDefaults];

		// Used for max text length recognition if last typed char is a non-space char
		editTextViewWasChanged = NO;

		// Allow the user to enter cmd+return to close the edit sheet in addition to fn+return
		[editSheetOkButton setKeyEquivalentModifierMask:NSEventModifierFlagCommand];

        if([editTextView respondsToSelector:@selector(setUsesFindBar:)]) {
			// 10.7+
			// Stealing the main window from the actual main window will cause
			// a UI bug with the tab bar and the find panel was really the only
			// thing that had an issue with not working with sheets.
			// The find bar works fine without hackery.
			[editTextView setUsesFindBar:YES];
        } else {
			// Permit the field edit sheet to become main if necessary; this allows fields within the sheet to
			// support full interactivity, for example use of the NSFindPanel inside NSTextViews.
			[editSheet setIsSheetWhichCanBecomeMain:YES];
		}

        if([jsonTextView respondsToSelector:@selector(setUsesFindBar:)]) {
            // 10.7+
            // Stealing the main window from the actual main window will cause
            // a UI bug with the tab bar and the find panel was really the only
            // thing that had an issue with not working with sheets.
            // The find bar works fine without hackery.
            [jsonTextView setUsesFindBar:YES];
        }
		
		[editTextView setAutomaticDashSubstitutionEnabled:NO];
		[editTextView setAutomaticQuoteSubstitutionEnabled:NO];

		allowUndo = YES;
		selectionChanged = NO;

		tmpDirPath = NSTemporaryDirectory();
		tmpFileName = nil;

		NSMenu *menu = [editSheetQuickLookButton menu];
		[menu setAutoenablesItems:NO];
		NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Interpret data as:", @"Interpret data as:") action:NULL keyEquivalent:@""];
		[menuItem setTag:1];
		[menuItem setEnabled:NO];
		[menu addItem:menuItem];
		NSUInteger tag = 2;

		// Load default QL types
		NSMutableArray *qlTypesItems = [[NSMutableArray alloc] init];
		NSError *readError = nil;

		NSString *filePath = [NSBundle pathForResource:@"EditorQuickLookTypes"
												ofType:@"plist"
										   inDirectory:[[NSBundle mainBundle] bundlePath]];

        NSData *defaultTypeData = nil;

        if(filePath != nil){
            defaultTypeData = [NSData dataWithContentsOfFile:filePath
                                                     options:NSMappedRead
                                                       error:&readError];
        }

		NSDictionary *defaultQLTypes = nil;
		if(defaultTypeData && !readError) {
			defaultQLTypes = [NSPropertyListSerialization propertyListWithData:defaultTypeData
																	   options:NSPropertyListImmutable
																		format:NULL
																		 error:&readError];
		}
		
		if(defaultQLTypes == nil || readError ) {
			NSLog(@"Error while reading 'EditorQuickLookTypes.plist':\n%@", readError);
		}
		else if(defaultQLTypes != nil && [defaultQLTypes objectForKey:@"QuickLookTypes"]) {
			for(id type in [defaultQLTypes objectForKey:@"QuickLookTypes"]) {
				NSMenuItem *aMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithString:[type objectForKey:@"MenuLabel"]] action:NULL keyEquivalent:@""];
				[aMenuItem setTag:tag];
				[aMenuItem setAction:@selector(quickLookFormatButton:)];
				[menu addItem:aMenuItem];
				tag++;
				[qlTypesItems addObject:type];
			}
		}
		// Load user-defined QL types
		if([prefs objectForKey:SPQuickLookTypes]) {
			for(id type in [prefs objectForKey:SPQuickLookTypes]) {
				NSMenuItem *aMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithString:[type objectForKey:@"MenuLabel"]] action:NULL keyEquivalent:@""];
				[aMenuItem setTag:tag];
				[aMenuItem setAction:@selector(quickLookFormatButton:)];
				[menu addItem:aMenuItem];
				tag++;
				[qlTypesItems addObject:type];
			}
		}

		[menu addItem:[NSMenuItem separatorItem]];
		self.phpSerializedEditorMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Edit PHP Serialized Data as Tree", @"PHP serialized data editor menu item")
																	 action:@selector(openPHPSerializedEditor:)
															  keyEquivalent:@""];
		[self.phpSerializedEditorMenuItem setTarget:self];
		[self.phpSerializedEditorMenuItem setEnabled:NO];
		[menu addItem:self.phpSerializedEditorMenuItem];

		qlTypes = @{SPQuickLookTypes : qlTypesItems};

		fieldType = @"";
		fieldEncoding = @"";
	}

	return self;
}

/**
 * Dealloc SPFieldEditorController and closes Quicklook window if visible.
 */
- (void)dealloc
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

	[self setEditedFieldInfo:nil];

}

#pragma mark -

- (unsigned long long)maxLengthDateWithOverride {
	return self.displayFormatter.maxLengthOverride != 0 ? self.displayFormatter.maxLengthOverride : maxTextLength;
}

/**
 * Main method for editing data. It will validate several settings and display a modal sheet for theWindow whioch waits until the user closes the sheet.
 *
 * @param data The to be edited table field data.
 * @param fieldName The name of the currently edited table field.
 * @param anEncoding The used encoding while editing.
 * @param isFieldBlob If YES the underlying table field is a TEXT/BLOB field. This setting handles several controls which are offered in the sheet to the user.
 * @param isEditable If YES the underlying table field is editable, if NO the field is not editable and the SPFieldEditorController sheet do not show a "OK" button for saving.
 * @param theWindow The window for displaying the sheet.
 * @param sender The calling instance.
 * @param contextInfo context info for processing the edited data in sender.
 */
- (void)editWithObject:(id)data
			 fieldName:(NSString *)fieldName
		 usingEncoding:(NSStringEncoding)anEncoding
		  isObjectBlob:(BOOL)isFieldBlob
			isEditable:(BOOL)isEditable
			withWindow:(NSWindow *)theWindow
				sender:(id)sender
		   contextInfo:(NSDictionary *)theContextInfo
{
	usedSheet       = nil;
	_isEditable     = isEditable;
	contextInfo     = theContextInfo;
	callerInstance  = sender;
	self.phpSerializedRootEntry = nil;
	self.phpSerializedSelectedEntry = nil;
	self.phpSerializedEditorAutomaticallyOpened = NO;
	[self.phpSerializedEditorMenuItem setEnabled:NO];
	_isGeometry     = ([[fieldType uppercaseString] isEqualToString:@"GEOMETRY"]) ? YES : NO;
	_isJSON         = ([[fieldType uppercaseString] isEqualToString:SPMySQLJsonType]);
	NSString *label = [self buildLabelForField:fieldName];

	if ([fieldType length] && [[fieldType uppercaseString] isEqualToString:@"BIT"]) {
		usedSheet     = bitSheet;
		sheetEditData = (NSString*)data;

		[bitSheetNULLButton setEnabled:_allowNULL];
		[bitSheetFieldName setStringValue:label];

		// Check for NULL
		if ([sheetEditData isEqualToString:[prefs objectForKey:SPNullValue]]) {
			[bitSheetNULLButton setState:NSControlStateValueOn];
			[self setToNull:bitSheetNULLButton];
		}
		else {
			[bitSheetNULLButton setState:NSControlStateValueOff];
		}

		// Init according bit check boxes
		NSUInteger i = 0;
		NSUInteger maxBit = (NSUInteger)((maxTextLength > 64) ? 64 : maxTextLength);

		if ([bitSheetNULLButton state] == NSControlStateValueOff && maxBit <= [(NSString*)sheetEditData length]) {
			for (i = 0; i < maxBit; i++) {
				[(NSButton *)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%ld", (long)i]]
				 setState:([(NSString*)sheetEditData characterAtIndex:(maxBit - i - 1)] == '1') ? NSControlStateValueOn : NSControlStateValueOff];
			}
		}

		for (i = maxBit; i < 64; i++) {
			[[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%ld", (long)i]] setEnabled:NO];
		}

		[self updateBitSheet];

		[theWindow beginSheet:usedSheet completionHandler:^(NSModalResponse returnCode) {
			// Remember spell cheecker status
			[self->prefs setBool:[self->editTextView isContinuousSpellCheckingEnabled] forKey:SPBlobTextEditorSpellCheckingEnabled];
		}];
	}
	else {
		usedSheet                  = editSheet;
		sheetEditData              = data;
		editSheetWillBeInitialized = YES;
		encoding                   = anEncoding;
		_isBlob                    = (!_isJSON && isFieldBlob); // we don't want the hex/image controls for JSON
		BOOL isBinary              = ([[fieldType uppercaseString] isEqualToString:@"BINARY"] || [[fieldType uppercaseString] isEqualToString:@"VARBINARY"]);

		[editTextView setFont:[self selectFont]];
		[editTextView setContinuousSpellCheckingEnabled:[prefs boolForKey:SPBlobTextEditorSpellCheckingEnabled]];
		[editTextView setEditable:_isEditable];
		[editSheetFieldName setStringValue:[NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"Field", @"Field"), label]];

		if (!_isEditable) {
			[editSheetOkButton setHidden:YES];
			[editSheetCancelButton setHidden:YES];
			[editSheetIsNotEditableCancelButton setHidden:NO];
			[editSheetOpenButton setEnabled:NO];
		}

		// Hide all views in editSheet
		[self showEditText:NO];
		[self showHexText:NO];
		[self showJsonText:NO];
		[self showImage:NO];
		[editImage setEditable:_isEditable];

		// Set window's min size since no segment and quicklook buttons are hidden
		if (_isBlob || isBinary || _isGeometry) {
			[usedSheet setFrameAutosaveName:@"SPFieldEditorBlobSheet"];
			[usedSheet setMinSize:NSMakeSize(650, 200)];
		}
		else {
			[usedSheet setFrameAutosaveName:@"SPFieldEditorTextSheet"];
			[usedSheet setMinSize:NSMakeSize(390, 150)];
		}

		NSSize screen = [[NSScreen mainScreen] visibleFrame].size;
		NSRect sheet = [usedSheet frame];

		[usedSheet setFrame:
		 NSMakeRect(sheet.origin.x, sheet.origin.y, 
					(sheet.size.width > screen.width) ? screen.width : sheet.size.width, 
					(sheet.size.height > screen.height) ? screen.height - 100 : sheet.size.height)
					display:YES];

		[theWindow beginSheet:usedSheet completionHandler:^(NSModalResponse returnCode) {
			// Remember spell cheecker status
			[self->prefs setBool:[self->editTextView isContinuousSpellCheckingEnabled] forKey:SPBlobTextEditorSpellCheckingEnabled];
		}];

		[editSheetProgressBar startAnimation:self];
		[editSheetSegmentControl setEnabled:NO forSegment:ImageSegment];
		[hexTextView setString:@""]; // Set hex view to "" - load on demand only

		NSImage *image = nil;
		if (self.displayFormatter) {
			// data comes with it's own display formatter so let's use that.
			stringValue = [self.displayFormatter stringForObjectValue: sheetEditData];
			[self showEditText:YES];
			[editSheetSegmentControl setSelectedSegment:TextSegment];
		}
		else if ([sheetEditData isKindOfClass:[NSData class]]) {
			image       = [[NSImage alloc] initWithData:sheetEditData];
			stringValue = [[NSString alloc] initWithData:sheetEditData encoding:encoding];

			if (stringValue == nil) {
				stringValue = [[NSString alloc] initWithData:sheetEditData encoding:NSASCIIStringEncoding];
			}

			if (isBinary) {
				stringValue	= [[NSString alloc] initWithFormat:@"0x%@", [sheetEditData dataToHexString]];
			}

			[editSheetSegmentControl setSelectedSegment:HexSegment];
			[self showHexText:YES];
		}
		else if ([sheetEditData isKindOfClass:[SPMySQLGeometryData class]]) {
			SPGeometryDataView *v = [[SPGeometryDataView alloc] initWithCoordinates:[sheetEditData coordinates] targetDimension:2000.0f];
			image = [v thumbnailImage];
			stringValue = [sheetEditData wktString];

			[editSheetSegmentControl setEnabled:NO forSegment:HexSegment];
			[editSheetSegmentControl setSelectedSegment:TextSegment];
			[self showEditText:YES];
		}
		else {
			// If the input is a JSON type column we can format it.
			// Since MySQL internally stores JSON in binary, it does not retain any formatting
      BOOL useSoftIndent = [prefs boolForKey:SPCustomQuerySoftIndent];
      NSInteger indentWidth = [prefs integerForKey:SPCustomQuerySoftIndentWidth];

			do {
				if (_isJSON) {
          NSString *formatted = [SPJSONFormatter stringByFormattingString:sheetEditData useSoftIndent:useSoftIndent indentWidth:indentWidth];
					if (formatted) {
						stringValue = formatted;
						break;
					}
				}
				stringValue = sheetEditData;
			} while(0);

			[hexTextView setString:@""];

			[self showEditText:YES];
			[editSheetSegmentControl setSelectedSegment:TextSegment];
		}

		[editImage setImage:image];
		if (image) {
			[editSheetSegmentControl setEnabled:YES forSegment:ImageSegment];
			if(!_isGeometry) {
				[self showImage:YES];
				[editSheetSegmentControl setSelectedSegment:ImageSegment];
			}
		}

		if (stringValue) {
			[editTextView setString:stringValue];

			if (image == nil) {
				if (!isBinary) {
					[self showHexText:NO];
				}
				else {
					[editSheetSegmentControl setEnabled:NO forSegment:ImageSegment];
				}

				[self showEditText:YES];
				[editSheetSegmentControl setSelectedSegment:TextSegment];
			}

			// Locate the caret in editTextView
			// (restore a given selection coming from the in-cell editing mode)
			NSRange selRange = [callerInstance fieldEditorSelectedRange];

			[editTextView setSelectedRange:selRange];
			[callerInstance setFieldEditorSelectedRange:NSMakeRange(0,0)];

			// If the string content is NULL select NULL for convenience
			if ([stringValue isEqualToString:[prefs objectForKey:SPNullValue]]) {
				[editTextView setSelectedRange:NSMakeRange(0,[[editTextView string] length])];
			}

			// Set focus
			[usedSheet makeFirstResponder:image == nil || _isGeometry ? editTextView : editImage];
			[self refreshPHPSerializedEditorAvailability];
			[self performSelector:@selector(openPHPSerializedEditorIfCurrentTextIsStructured) withObject:nil afterDelay:0.15];
		}

		editSheetWillBeInitialized = NO;
		[editSheetProgressBar stopAnimation:self];
	}
}

- (NSString *)buildLabelForField:(NSString *)fieldName {
	// Set field label
	NSMutableString *label = [NSMutableString string];

	[label appendFormat:@"“%@”", fieldName];

	if ([fieldType length] || maxTextLength > 0 || [fieldEncoding length] || !_allowNULL)
		[label appendString:@" – "];

	if ([fieldType length])
		[label appendString:fieldType];

	//skip length for JSON type since it's a constant and MySQL doesn't display it either
	if (maxTextLength > 0 && !_isJSON)
		[label appendFormat:@"(%lld) ", maxTextLength];

	if (self.displayFormatter)
		[label appendFormat:@"– %@ ", self.displayFormatter.label];

	if (!_allowNULL)
		[label appendString:@"NOT NULL "];

	if ([fieldEncoding length])
		[label appendString:fieldEncoding];

	return label;
}

- (NSFont *)selectFont {
	NSFont *textEditorFont = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	// Based on user preferences, either use:
	// 1. The font specifically chosen for the editor sheet textView (FieldEditorSheetFont, right-click in the textView, and choose "Font > Show Fonts" to do that);
	// 2. The font used for the table view (SPGlobalFontSettings, per the "MySQL Content Font" preference option);
	if ([prefs objectForKey:SPFieldEditorSheetFont]) {
		textEditorFont = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPFieldEditorSheetFont]];
	} else if ([prefs objectForKey:SPGlobalFontSettings]) {
		textEditorFont = [NSUserDefaults getFont];
	}
	return textEditorFont;
}

/**
 * Segement controller for text/image/hex buttons in editSheet
 */
- (IBAction)segmentControllerChanged:(id)sender
{
	switch((FieldEditorSegment)[sender selectedSegment]){
		case TextSegment:
			[self showEditText:YES];
			[usedSheet makeFirstResponder:editTextView];
			break;
		case ImageSegment:
			[self showImage:YES];
			[usedSheet makeFirstResponder:editImage];
			break;
		case HexSegment:
			[usedSheet makeFirstResponder:hexTextView];
			if([[hexTextView string] isEqualToString:@""]) {
				[editSheetProgressBar startAnimation:self];
				if([sheetEditData isKindOfClass:[NSData class]]) {
					[hexTextView setString:[sheetEditData dataToFormattedHexString]];
				} else {
					[hexTextView setString:[[sheetEditData dataUsingEncoding:encoding allowLossyConversion:YES] dataToFormattedHexString]];
				}
				[editSheetProgressBar stopAnimation:self];
			}
			[self showHexText:YES];
			break;
		case JsonSegment:
			[usedSheet makeFirstResponder:jsonTextView];
      
			if([[jsonTextView string] isEqualToString:@""]) {
        // 0. If sheet data is not NSData or NSString, then stop to process as potential JSON
        if(![sheetEditData isKindOfClass:[NSData class]] && ![sheetEditData isKindOfClass:[NSString class]]) {
          SPLog(@"sheetEditData not of NSData or NSString class: %@", [sheetEditData class]);
          [jsonTextView setString:NSLocalizedString(@"Invalid JSON",@"Message for field editor JSON segment when JSON is invalid")];
          break;
        }
        
        // 1. Validate if JSON is valid
        NSData *jsonData = nil;
        if ([sheetEditData respondsToSelector:@selector(dataUsingEncoding:)]) {
          jsonData = [sheetEditData dataUsingEncoding:NSUTF8StringEncoding];
        } else if ([sheetEditData isKindOfClass:[NSData class]]) {
          jsonData = sheetEditData;
        } else{
          SPLog(@"sheetEditData does not respond to dataUsingEncoding: %@", [sheetEditData class]);
          [jsonTextView setString:NSLocalizedString(@"Invalid JSON",@"Message for field editor JSON segment when JSON is invalid")];
#ifdef DEBUG
          NSArray *arr = DumpObjCMethods(sheetEditData);
          SPLog(@"sheetEditData class methods = %@", arr);
#endif
          break;
        }
        
        NSError *error = nil;
        id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&error];
        if(error != nil){
          SPLog(@"JSONObjectWithData error : %@", error.localizedDescription);
          [jsonTextView setString:NSLocalizedString(@"Invalid JSON",@"Message for field editor JSON segment when JSON is invalid")];
          break;
        }
        
        
        // 2. Convert data to raw string then beautify it as JSON
        NSString *rawJson = nil;
        if ([sheetEditData isKindOfClass:[NSData class]]) {
          rawJson = [[NSString alloc] initWithData:sheetEditData encoding:NSUTF8StringEncoding];
        } else{
          rawJson = sheetEditData;
        }
        
        BOOL useSoftIndent = [prefs boolForKey:SPCustomQuerySoftIndent];
        NSInteger indentWidth = [prefs integerForKey:SPCustomQuerySoftIndentWidth];

        // Re-format by custom formatter instead of using NSJSONSerialization
        // to avoid the data conversion issues of NSJSONSerialization (e.g: float number convertion, keys ordering)
        NSString *prettyPrintedJson = [SPJSONFormatter stringByFormattingString:rawJson useSoftIndent:useSoftIndent indentWidth:indentWidth];
        if(prettyPrintedJson != nil){
          SPLog(@"prettyPrintedJson : %@", prettyPrintedJson);
          [jsonTextView setString:prettyPrintedJson];
        }
        else{
          SPLog(@"prettyPrintedJson is nil");
          [jsonTextView setString:NSLocalizedString(@"Invalid JSON",@"Message for field editor JSON segment when JSON is invalid")];
        }
			}
			[self showJsonText:YES];
			break;
	}
}

/**
 * Open the open file panel to load a file (text/image) into the editSheet
 */
- (IBAction)openEditSheet:(id)sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];

	[panel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger returnCode)
	{
		[self openPanelDidEnd:panel returnCode:returnCode contextInfo:nil];
	}];
}

/**
 * Open the save file panel to save the content of the editSheet according to its type as NSData or NSString atomically into the past file.
 */
- (IBAction)saveEditSheet:(id)sender
{
	NSSavePanel *panel = [NSSavePanel savePanel];

	if ([editSheetSegmentControl selectedSegment] == ImageSegment && [sheetEditData isKindOfClass:[SPMySQLGeometryData class]]) {
		[panel setAllowedContentTypes:@[[UTType typeWithFilenameExtension:@"pdf"]]];
		[panel setAllowsOtherFileTypes:NO];
	}
	else {
		[panel setAllowsOtherFileTypes:YES];
	}

	[panel setCanSelectHiddenExtension:YES];
	[panel setExtensionHidden:NO];

	[panel beginSheetModalForWindow:usedSheet completionHandler:^(NSInteger returnCode)
	{
		[self savePanelDidEnd:panel returnCode:returnCode contextInfo:nil];
	}];
}

/**
 * Close the editSheet. Before closing it validates the editSheet data against maximum text size.
 * If data size is too long select the part which is to long for better editing and keep the sheet opened.
 * If any temporary Quicklook files were created delete them before clsoing the sheet.
 */
- (IBAction)closeEditSheet:(id)sender
{
	editSheetReturnCode = 0;

	// Validate the sheet data before saving them.
	// - for max text length (except for NULL value string) select the part which won't be saved
	//   and suppress closing the sheet
	if (sender == editSheetOkButton) {

		unsigned long long maxLength = self.maxLengthDateWithOverride;

		// For FLOAT fields ignore the decimal point in the text when comparing lengths
		if ([[fieldType uppercaseString] isEqualToString:@"FLOAT"] && ([[[editTextView textStorage] string] rangeOfString:@"."].location != NSNotFound)) {
			maxLength++;
		}

        // SPNullValue = @"NULL"
        NSString *nullValue = [[NSUserDefaults standardUserDefaults] objectForKey:SPNullValue];
        NSTextStorage *editTVtextStorage = [editTextView textStorage];
        NSString *editTVString = [editTVtextStorage string];

		if (maxLength > 0 && [editTVString characterCount] > (NSInteger)maxLength && ![editTVString isEqualToString:nullValue] && [nullValue contains:editTVString] == NO) {
			[editTextView setSelectedRange:NSMakeRange((NSUInteger)maxLength, [editTVString characterCount] - (NSUInteger)maxLength)];
			[editTextView scrollRangeToVisible:NSMakeRange([editTextView selectedRange].location,0)];
			[SPTooltip showWithObject:[NSString stringWithFormat:NSLocalizedString(@"Text is too long. Maximum text length is set to %llu.", @"Text is too long. Maximum text length is set to %llu."), maxLength]];

			return;
		}

		if (self.displayFormatter) {
			NSString *_Nullable err = nil;
			BOOL isValid = [self.displayFormatter getObjectValue:nil forString:[editTextView string] errorDescription:&err];
			if (!isValid) {
				NSBeep();
				if (err != nil) {
					[SPTooltip showWithObject: err];
				}
				return;
			}
		}

		editSheetReturnCode = 1;
	}
	else if (sender == bitSheetOkButton && _isEditable) {
		editSheetReturnCode = 1;
	}

	// Delete all QuickLook temp files if it was invoked
	if(tmpFileName != nil) {
		NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmpDirPath error:nil];
		for (NSString *file in dirContents) {
			if ([file hasPrefix:@"SequelProQuickLook"]) {
				if(![[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@/%@", tmpDirPath, file] error:NULL]) {
					NSLog(@"QL: Couldn't delete temporary file '%@/%@'.", tmpDirPath, file);
				}
			}
		}
	}

	[NSApp endSheet:usedSheet returnCode:editSheetReturnCode];
	[usedSheet orderOut:self];

	if(callerInstance) {
		id returnData = ( editSheetReturnCode && _isEditable ) ? (_isGeometry) ? [editTextView string] : sheetEditData : nil;

		//for MySQLs JSON type remove the formatting again, since it won't be stored anyway
		if(_isJSON) {
			NSString *unformatted = [SPJSONFormatter stringByUnformattingString:returnData];
			if(unformatted) returnData = unformatted;
		}
    else if (self.displayFormatter) {
      id convertedData;
      [self.displayFormatter getObjectValue:&convertedData forString:[editTextView string] errorDescription:nil];
      returnData = convertedData;
    }

		if([callerInstance respondsToSelector:@selector(processFieldEditorResult:contextInfo:)]) {
			[(id <SPFieldEditorControllerDelegate>)callerInstance processFieldEditorResult:returnData contextInfo:contextInfo];
		}
	}
}

/**
 * Open file panel didEndSelector. If the returnCode == NSModalResponseOK it opens the selected file in the editSheet.
 */
- (void)openPanelDidEnd:(NSOpenPanel *)panel returnCode:(NSInteger)returnCode  contextInfo:(void  *)contextInfo
{
	if (returnCode == NSModalResponseOK) {
		NSString *contents = nil;
		editSheetWillBeInitialized = YES;
		[editSheetProgressBar startAnimation:self];
		sheetEditData = [[NSData alloc] initWithContentsOfURL:[panel URL]]; // load new data/images

		NSImage *image = [[NSImage alloc] initWithData:sheetEditData];
		contents = [[NSString alloc] initWithData:sheetEditData encoding:encoding];
		if (contents == nil)
			contents = [[NSString alloc] initWithData:sheetEditData encoding:NSASCIIStringEncoding];

		if(contents)
			[editTextView setString:contents];
		else
			[editTextView setString:@""];

		// Load hex data only if user has already displayed them
		if(![[hexTextView string] isEqualToString:@""])
			[hexTextView setString:[sheetEditData dataToFormattedHexString]];

		// set the image preview, string contents and hex representation
		[editImage setImage:image];
		if (image) { // If the image cell now contains a valid image, select the image view
			[editSheetSegmentControl setSelectedSegment:ImageSegment];
			[self showImage:YES];
		}
		else { // Otherwise deselect the image view
			[editSheetSegmentControl setSelectedSegment:TextSegment];
			[self showEditText:YES];
		}
		if(contents)
		[editSheetProgressBar stopAnimation:self];
		editSheetWillBeInitialized = NO;
	}
}

/**
 * Save file panel didEndSelector. If the returnCode == NSModalResponseOK it writes the current content of editSheet according to its type as NSData or NSString atomically into the past file.
 */
- (void)savePanelDidEnd:(NSSavePanel *)panel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode == NSModalResponseOK) {

		[editSheetProgressBar startAnimation:self];

		NSURL *fileURL = [panel URL];

		// Write binary field types directly to the file
		if ( [sheetEditData isKindOfClass:[NSData class]] ) {
			[sheetEditData writeToURL:fileURL atomically:YES];

		}
		else if ( [sheetEditData isKindOfClass:[SPMySQLGeometryData class]] ) {

			if ( [editSheetSegmentControl selectedSegment] == TextSegment || editImage == nil ) {

				[[editTextView string] writeToURL:fileURL
										atomically:YES
										  encoding:encoding
											 error:NULL];

			} else if (editImage != nil){

				SPGeometryDataView *v = [[SPGeometryDataView alloc] initWithCoordinates:[sheetEditData coordinates] targetDimension:2000.0f];
				NSData *pdf = [v pdfData];
				if(pdf)
					[pdf writeToURL:fileURL atomically:YES];

			}
		}
		// Write other field types' representations to the file via the current encoding
		else {
			[[sheetEditData description] writeToURL:fileURL
										  atomically:YES
											encoding:encoding
											   error:NULL];
		}

		[editSheetProgressBar stopAnimation:self];
	}
}

#pragma mark -
#pragma mark Drop methods

/**
 * If the image was deleted reset all views in editSheet.
 * The actual dropped image process is handled by (processUpdatedImageData:).
 */
- (IBAction)dropImage:(id)sender
{
	if ([editImage image] == nil ) {
		sheetEditData = [[NSData alloc] init];
		[editTextView setString:@""];
		[hexTextView setString:@""];
		return;
	}
}

#pragma mark -
#pragma mark QuickLook

/**
 * Invoked if a Quicklook format was chosen
 */
- (IBAction)quickLookFormatButton:(id)sender
{
	if(qlTypes != nil && [[qlTypes objectForKey:@"QuickLookTypes"] count] > (NSUInteger)[sender tag] - 2) {
		NSDictionary *type = [[qlTypes objectForKey:@"QuickLookTypes"] objectAtIndex:[sender tag] - 2];
		[self invokeQuickLookOfType:[type objectForKey:@"Extension"] treatAsText:([[type objectForKey:@"treatAsText"] integerValue])];
	}
}

/**
 * Create a temporary file in NSTemporaryDirectory() with the chosen extension type which will be called by Apple's Quicklook generator
 *
 * @param type The type as file extension for Apple's default Quicklook generator.
 *
 * @param isText If YES the content of editSheet will be treates as pure text.
 */
- (void)createTemporaryQuickLookFileOfType:(NSString *)type treatAsText:(BOOL)isText
{
	// Create a temporary file name to store the data as file
	// since QuickLook only works on files.
	// Alternate the file name to suppress caching by using counter%2.
	tmpFileName = [[NSString alloc] initWithFormat:@"%@SequelProQuickLook%ld.%@", tmpDirPath, (long)(counter%2), type];

	// if data are binary
	if ( [sheetEditData isKindOfClass:[NSData class]] && !isText) {
		[sheetEditData writeToFile:tmpFileName atomically:YES];

	// write other field types' representations to the file via the current encoding
	} else {

		// if "html" type try to set the HTML charset - not yet completed
		if([type isEqualToString:@"html"]) {

			NSString *enc;
			switch(encoding) {
				case NSASCIIStringEncoding:
				enc = @"US-ASCII";break;
				case NSUTF8StringEncoding:
				enc = @"UTF-8";break;
				case NSISOLatin1StringEncoding:
				enc = @"ISO-8859-1";break;
				default:
				enc = @"US-ASCII";
			}
			[[NSString stringWithFormat:@"<META HTTP-EQUIV='Content-Type' CONTENT='text/html; charset=%@'>%@", enc, [editTextView string]] writeToFile:tmpFileName
										atomically:YES
										encoding:encoding
										error:NULL];
		} else {
			[[sheetEditData description] writeToFile:tmpFileName
										atomically:YES
										encoding:encoding
										error:NULL];
		}
	}
}

/**
 * Opens QuickLook for current data if QuickLook is available
 *
 * @param type The type as file extension for Apple's default Quicklook generator.
 *
 * @param isText If YES the content of editSheet will be treates as pure text.
 */
- (void)invokeQuickLookOfType:(NSString *)type treatAsText:(BOOL)isText
{
	// See Developer example "QuickLookDownloader"
	// file:///Developer/Documentation/DocSets/com.apple.adc.documentation.AppleSnowLeopard.CoreReference.docset/Contents/Resources/Documents/samplecode/QuickLookDownloader/index.html#//apple_ref/doc/uid/DTS40009082

	[editSheetProgressBar startAnimation:self];

	[self createTemporaryQuickLookFileOfType:type treatAsText:isText];

	counter++;

	// TODO: If QL is  visible reload it - but how?
	// Up to now QL will close and the user has to redo it.
	if([[QLPreviewPanel sharedPreviewPanel] isVisible]) {
		[[QLPreviewPanel sharedPreviewPanel] orderOut:nil];
	}

	[[QLPreviewPanel sharedPreviewPanel] makeKeyAndOrderFront:nil];

	[editSheetProgressBar stopAnimation:self];

}

#pragma mark - QLPreviewPanelController methods

/**
 * QuickLook delegate for SDK 10.6. Set the Quicklook delegate to self and suppress setShowsAddToiPhotoButton since the format is unknow.
 */
- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel
{
	// This document is now responsible of the preview panel
	[panel setDelegate:self];
	[panel setDataSource:self];
}

/**
 * QuickLook delegate for SDK 10.6 - not in usage.
 */
- (void)endPreviewPanelControl:(QLPreviewPanel *)panel
{
	// This document loses its responsisibility on the preview panel
	// Until the next call to -beginPreviewPanelControl: it must not
	// change the panel's delegate, data source or refresh it.
}

/**
 * QuickLook delegate for SDK 10.6
 */
- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel;
{
	return YES;
}

#pragma mark - QLPreviewPanelDataSource methods

/**
 * QuickLook delegate for SDK 10.6.
 *
 * @return It always returns 1.
 */
- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel
{
	return 1;
}

/**
 * QuickLook delegate for SDK 10.6.
 *
 * @return It returns as NSURL the temporarily created file.
 */
- (id)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)anIndex
{
	if(tmpFileName)
		return [NSURL fileURLWithPath:tmpFileName];

	return nil;
}

#pragma mark - QLPreviewPanelDelegate methods

// QuickLook delegates for SDK 10.6
// - (BOOL)previewPanel:(QLPreviewPanel *)panel handleEvent:(NSEvent *)event
// {
// }

/**
 * QuickLook delegate for SDK 10.6.
 *
 * @return It returns the frame of the application's middle. If an empty frame is returned then the panel will fade in/out instead.
 */
- (NSRect)previewPanel:(QLPreviewPanel *)panel sourceFrameOnScreenForPreviewItem:(id)item
{
	// Return the App's middle point
	NSRect mwf = [[NSApp mainWindow] frame];
	return NSMakeRect(
				  mwf.origin.x+mwf.size.width/2,
				  mwf.origin.y+mwf.size.height/2,
				  5, 5);
}

// QuickLook delegates for SDK 10.6
// - (id)previewPanel:(id)panel transitionImageForPreviewItem:(id)item contentRect:(NSRect *)contentRect
// {
// 	return [NSImage imageNamed:@"database"];
// }

#pragma mark -

/**
 * Called by (SPImageView) if an image was pasted into the editSheet
 */
-(void)processPasteImageData
{
	editSheetWillBeInitialized = YES;
	NSImage *image = [[NSImage alloc] initWithPasteboard:[NSPasteboard generalPasteboard]];
	if (image) {
		[editImage setImage:image];
		sheetEditData = [[NSData alloc] initWithData:[image TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1]];
		NSString *contents = [[NSString alloc] initWithData:sheetEditData encoding:encoding];
		
		if (contents == nil)
			contents = [[NSString alloc] initWithData:sheetEditData encoding:NSASCIIStringEncoding];

		// Set the string contents and hex representation
		if(contents)
			[editTextView setString:contents];
		if(![[hexTextView string] isEqualToString:@""])
			[hexTextView setString:[sheetEditData dataToFormattedHexString]];
	}

	editSheetWillBeInitialized = NO;
}

/**
 * Invoked if the imageView was changed or a file dragged and dropped onto it.
 *
 * @param data The image data. If data == nil the reset all views in editSheet.
 */
- (void)processUpdatedImageData:(NSData *)data
{
	editSheetWillBeInitialized = YES;

	// If the image was not processed, set a blank string as the contents of the edit and hex views.
	if ( data == nil ) {
		sheetEditData = [[NSData alloc] init];
		[editTextView setString:@""];
		[hexTextView setString:@""];
		editSheetWillBeInitialized = NO;
		return;
	}

	// Process the provided image
	sheetEditData = [[NSData alloc] initWithData:data];
	NSString *contents = [[NSString alloc] initWithData:data encoding:encoding];
	if (contents == nil)
		contents = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];

	// Set the string contents and hex representation
	if(contents)
		[editTextView setString:contents];
	if(![[hexTextView string] isEqualToString:@""])
		[hexTextView setString:[sheetEditData dataToFormattedHexString]];
	editSheetWillBeInitialized = NO;
}

#pragma mark -
#pragma mark BIT Field Sheet

/**
 * Update all controls in the bitSheet
 */
- (void)updateBitSheet
{
	NSUInteger i = 0;
	NSUInteger maxBit = (NSUInteger)((maxTextLength > 64) ? 64 : maxTextLength);

	if([bitSheetNULLButton state] == NSControlStateValueOn) {
		NSString *nullString = [prefs objectForKey:SPNullValue];
		sheetEditData = [NSString stringWithString:nullString];
		[bitSheetIntegerTextField setStringValue:nullString];
		[bitSheetHexTextField setStringValue:nullString];
		[bitSheetOctalTextField setStringValue:nullString];
		return;
	}

	NSMutableString *bitString = [NSMutableString string];
	[bitString setString:@""];
	for( i = 0; i<maxBit; i++ )
		[bitString appendString:@"0"];

	NSUInteger intValue = 0;
	NSUInteger bitValue = 0x1;

	for(i=0; i<maxBit; i++) {
		if([(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", (unsigned long)i]] state] == NSControlStateValueOn) {
			intValue += bitValue;
			[bitString replaceCharactersInRange:NSMakeRange((NSUInteger)maxTextLength-i-1, 1) withString:@"1"];
		}
		bitValue <<= 1;
	}
	[bitSheetIntegerTextField setStringValue:[[NSNumber numberWithUnsignedLongLong:intValue] stringValue]];
	[bitSheetHexTextField setStringValue:[NSString stringWithFormat:@"%lX", (unsigned long)intValue]];
	[bitSheetOctalTextField setStringValue:[NSString stringWithFormat:@"%llo", (unsigned long long)intValue]];

	// set edit data to text
	sheetEditData = [NSString stringWithString:bitString];

}

/**
 * Selector of any operator in the bitSheet. The different buttons will be distinguished by the sender's tag.
 */
- (IBAction)bitSheetOperatorButtonWasClicked:(id)sender
{
	unsigned long i = 0;
	unsigned long aBit;
	unsigned long maxBit = (unsigned long)((maxTextLength > 64) ? 64 : maxTextLength);

	switch([sender tag]) {
		case 0: // all to 1
		for(i=0; i<maxBit; i++)
			[(NSButton *)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] setState:NSControlStateValueOn];
		break;
		case 1: // all to 0
		for(i=0; i<maxBit; i++)
			[(NSButton *)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] setState:NSControlStateValueOff];
		break;
		case 2: // negate
		for(i=0; i<maxBit; i++)
			[(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] setState:![(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] state]];
		break;
		case 3: // shift left
		for(i=maxBit-1; i>0; i--) {
			[(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] setState:[(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i-1]] state]];
		}
		[(NSButton *)[self valueForKeyPath:@"bitSheetBitButton0"] setState:NSControlStateValueOff];
		break;
		case 4: // shift right
		for(i=0; i<maxBit-1; i++) {
			[(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] setState:[(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i+1]] state]];
		}
		[(NSButton *)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", maxBit-1]] setState:NSControlStateValueOff];
		break;
		case 5: // rotate left
		aBit = [(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%ld", maxBit-1]] state];
		for(i=maxBit-1; i>0; i--) {
			[(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] setState:[(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i-1]] state]];
		}
		[(NSButton *)[self valueForKeyPath:@"bitSheetBitButton0"] setState:aBit];
		break;
		case 6: // rotate right
		aBit = [(NSButton*)[self valueForKeyPath:@"bitSheetBitButton0"] state];
		for(i=0; i<maxBit-1; i++) {
			[(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] setState:[(NSButton*)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i+1]] state]];
		}
		[(NSButton *)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", maxBit-1]] setState:aBit];
		break;
	}
	[self updateBitSheet];
}

/**
 * Selector to set the focus to the first bit - but it doesn't work (⌘B).
 */
- (IBAction)bitSheetSelectBit0:(id)sender
{
	[usedSheet makeFirstResponder:[self valueForKeyPath:@"bitSheetBitButton0"]];
}

/**
 * Selector to set the to be edited data to NULL or not according to [sender state].
 * If NULL processes several validations.
 */
- (IBAction)setToNull:(id)sender
{
	unsigned long i;
	unsigned long maxBit = (unsigned long)((maxTextLength > 64) ? 64 : maxTextLength);

	if([(NSButton*)sender state] == NSControlStateValueOn) {
		for(i=0; i<maxBit; i++)
			[[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] setEnabled:NO];
		[bitSheetHexTextField setEnabled:NO];
		[bitSheetIntegerTextField setEnabled:NO];
		[bitSheetOctalTextField setEnabled:NO];
	} else {
		for(i=0; i<maxBit; i++)
			[[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] setEnabled:YES];
		[bitSheetHexTextField setEnabled:YES];
		[bitSheetIntegerTextField setEnabled:YES];
		[bitSheetOctalTextField setEnabled:YES];
	}

	[self updateBitSheet];
}

/**
 * Selector if any bit NSButton was pressed to update any controls in bitSheet.
 */
- (IBAction)bitSheetBitButtonWasClicked:(id)sender
{
	[self updateBitSheet];
}

#pragma mark -
#pragma mark TextView delegate methods

/**
 * Performs interface validation for various controls. Esp. if user changed the value in bitSheetIntegerTextField or bitSheetHexTextField.
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
	id object = [notification object];

	if (object == bitSheetIntegerTextField) {

		unsigned long i = 0;
		unsigned long maxBit = (NSUInteger)((maxTextLength > 64) ? 64 : maxTextLength);

		NSUInteger intValue = (NSUInteger)strtoull([[bitSheetIntegerTextField stringValue] UTF8String], NULL, 0);

		for(i=0; i<maxBit; i++)
			[(NSButton *)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] setState:NSControlStateValueOff];

		[bitSheetHexTextField setStringValue:[NSString stringWithFormat:@"%lX", (unsigned long)intValue]];
		[bitSheetOctalTextField setStringValue:[NSString stringWithFormat:@"%llo", (long long)intValue]];

		i = 0;
		while( intValue && i < maxBit )
		{
			[(NSButton *)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%lu", i]] setState:( (intValue & 0x1) == 0) ? NSControlStateValueOff : NSControlStateValueOn];
			intValue >>= 1;
			i++;
		}
		[self updateBitSheet];
	}
	else if (object == bitSheetHexTextField) {

		NSUInteger i = 0;
		NSUInteger maxBit = (NSUInteger)((maxTextLength > 64) ? 64 : maxTextLength);

		unsigned long long intValue;

		[[NSScanner scannerWithString:[bitSheetHexTextField stringValue]] scanHexLongLong: &intValue];

		for(i=0; i<maxBit; i++)
			[(NSButton *)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%ld", (long)i]] setState:NSControlStateValueOff];

		[bitSheetHexTextField setStringValue:[NSString stringWithFormat:@"%qX", intValue]];
		[bitSheetOctalTextField setStringValue:[NSString stringWithFormat:@"%llo", intValue]];

		i = 0;
		while( intValue && i < maxBit )
		{
			[(NSButton *)[self valueForKeyPath:[NSString stringWithFormat:@"bitSheetBitButton%ld", (long)i]] setState:( (intValue & 0x1) == 0) ? NSControlStateValueOff : NSControlStateValueOn];
			intValue >>= 1;
			i++;
		}

		[self updateBitSheet];
	}
}

/**
 * Validate editTextView for maximum text length except for NULL as value string
 */
- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)r replacementString:(NSString *)replacementString
{
	if (replacementString == nil || [replacementString characterCount] == 0) {
		editTextViewWasChanged = YES; // Backspace
		return YES;
	}

	unsigned long long adjTextMaxTextLength = self.maxLengthDateWithOverride;

	if (textView == editTextView && (adjTextMaxTextLength > 0) &&
			![[[[editTextView textStorage] string] stringByAppendingString:replacementString] isEqualToString:[prefs objectForKey:SPNullValue]])
	{
		NSInteger newLength;

		// Auxilary to ensure that eg textViewDidChangeSelection:
		// saves a non-space char + base char if that combination
		// occurs at the end of a sequence of typing before saving
		// (OK button).
		editTextViewWasChanged = ([replacementString length] == 1) || wasCutPaste;

		// Pure attribute changes are ok
		if (!replacementString) return YES;

		// The exact change isn't known. Disallow the change to be safe.
		if (r.location == NSNotFound) return NO;

		// Length checking while using the Input Manager (eg for Japanese)
		if ([textView hasMarkedText] && (adjTextMaxTextLength > 0) && (r.location < adjTextMaxTextLength)) {

			// User tries to insert a new char but max text length was already reached - return NO
			if (!r.length && ([[[textView textStorage] string] characterCount] >= (NSInteger)adjTextMaxTextLength)) {
				[SPTooltip showWithObject:[NSString stringWithFormat:NSLocalizedString(@"Maximum text length is set to %llu.", @"Maximum text length is set to %llu."), adjTextMaxTextLength]];
				[textView unmarkText];

				return NO;
			}
			// Otherwise allow it if insertion point is valid for eg
			// a VARCHAR(3) field filled with two Chinese chars and one inserts the
			// third char by typing its pronounciation "wo" - 2 Chinese chars plus "wo" would give
			// 4 which is larger than max length.
			// TODO this doesn't solve the problem of inserting more than one char. For now
			// that part which won't be saved will be hilited if user pressed the OK button.
			else if (r.location < adjTextMaxTextLength) {
				return YES;
			}
		}

		// Calculate the length of the text after the change.
		newLength = [[[textView textStorage] string] characterCount] + [replacementString characterCount] - r.length;

		NSUInteger textLength = [[[textView textStorage] string] characterCount];

		unsigned long long originalMaxTextLength = adjTextMaxTextLength;

		// For FLOAT fields ignore the decimal point in the text when comparing lengths
		if ([[fieldType uppercaseString] isEqualToString:@"FLOAT"] &&
				([[[textView textStorage] string] rangeOfString:@"."].location != NSNotFound)) {

			if ((NSUInteger)newLength == (adjTextMaxTextLength + 1)) {
				adjTextMaxTextLength++;
				textLength--;
			}
			else if ((NSUInteger)newLength > adjTextMaxTextLength) {
				textLength--;
			}
		}

		// If it's too long, disallow the change but try
		// to insert a text chunk partially to maxTextLength.
		if ((NSUInteger)newLength > adjTextMaxTextLength) {
			if ((adjTextMaxTextLength - textLength + [textView selectedRange].length) <= [replacementString characterCount]) {

				NSString *tooltip = nil;

				if (adjTextMaxTextLength - textLength + [textView selectedRange].length) {
					tooltip = [NSString stringWithFormat:NSLocalizedString(@"Maximum text length is set to %llu. Inserted text was truncated.", @"Maximum text length is set to %llu. Inserted text was truncated."), adjTextMaxTextLength];
				}
				else {
					tooltip = [NSString stringWithFormat:NSLocalizedString(@"Maximum text length is set to %llu.", @"Maximum text length is set to %llu."), adjTextMaxTextLength];
				}

				[SPTooltip showWithObject:tooltip];

				[textView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:[replacementString substringToIndex:(NSUInteger)adjTextMaxTextLength - textLength +[textView selectedRange].length]]];
			}

			adjTextMaxTextLength = originalMaxTextLength;

			return NO;
		}

		adjTextMaxTextLength = originalMaxTextLength;

		if (self.displayFormatter) {
			NSString *err = nil;
			NSString *newStr = nil;
			BOOL isValid = [self.displayFormatter isPartialStringValid:replacementString newEditingString:&newStr errorDescription:&err];
			if (!isValid) {
				NSBeep();
				if (err != nil) {
					[SPTooltip showWithObject: err];
				}
				return NO;
			}
		}

		// Otherwise, allow it
		return YES;
	}

	return YES;
}

/**
 * Invoked when the user changes the string in the editSheet
 */
- (void)textViewDidChangeSelection:(NSNotification *)notification
{
	if([notification object] == editTextView) {
		// Do nothing if user really didn't changed text (e.g. for font size changing return)
		if(!editTextViewWasChanged && (editSheetWillBeInitialized
			|| (([[[notification object] textStorage] editedRange].location == NSNotFound)
			&& ([[[notification object] textStorage] changeInLength] == 0)))) {
			// Inform the undo-grouping about the caret movement
			selectionChanged = YES;
			return;
		}

		// clear the image and hex (since i doubt someone can "type" a gif)
		[editImage setImage:nil];
		[hexTextView setString:@""];

		// set edit data to text
		sheetEditData = [NSString stringWithString:[editTextView string]];
		[self refreshPHPSerializedEditorAvailability];
	}
}

/**
 * Traps enter and return key and closes editSheet instead of inserting a linebreak when user hits return.
 */
- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
	if ( aTextView == editTextView ) {
		if ( [aTextView methodForSelector:aSelector] == [aTextView methodForSelector:@selector(insertNewline:)] &&
			[[[NSApp currentEvent] characters] isEqualToString:@"\003"] )
		{
			[self closeEditSheet:editSheetOkButton];
			return YES;
		}
	}

	return NO;
}

/**
 * Traps any editing in editTextView to allow undo grouping only if the text buffer was really changed.
 * Inform the run loop delayed for larger undo groups.
 */
- (void)textDidChange:(NSNotification *)aNotification
{

	[NSObject cancelPreviousPerformRequestsWithTarget:self
								selector:@selector(setAllowedUndo)
								object:nil];

	// If conditions match create an undo group
	NSInteger cycleCounter;
	if( ( wasCutPaste || allowUndo || doGroupDueToChars ) && ![esUndoManager isUndoing] && ![esUndoManager isRedoing] ) {
		allowUndo = NO;
		wasCutPaste = NO;
		doGroupDueToChars = NO;
		selectionChanged = NO;

		cycleCounter = 0;
		while([esUndoManager groupingLevel] > 0) {
			[esUndoManager endUndoGrouping];
			cycleCounter++;
		}
		while([esUndoManager groupingLevel] < cycleCounter)
			[esUndoManager beginUndoGrouping];

		cycleCounter = 0;
	}

	[self performSelector:@selector(setAllowedUndo) withObject:nil afterDelay:0.09];

}

#pragma mark -
#pragma mark PHP Serialized Editor

- (NSString *)currentPHPSerializedText
{
	return ([[editTextView string] length]) ? [editTextView string] : @"";
}

- (BOOL)populatePHPSerializedEditorFromCurrentTextShowingError:(BOOL)showError
{
	NSString *errorMessage = nil;
	SAPHPSerializedValue *rootValue = [SAPHPSerializedParser parseString:[self currentPHPSerializedText] encoding:encoding error:&errorMessage];

	if (!rootValue) {
		if (showError) {
			[SPTooltip showWithObject:errorMessage ?: NSLocalizedString(@"The current field does not contain valid PHP serialized data.", @"PHP serialized editor invalid tooltip")];
		}
		return NO;
	}

	SAPHPSerializedEntry *rootEntry = [[SAPHPSerializedEntry alloc] init];
	rootEntry.key = @"root";
	rootEntry.keyIsInteger = NO;
	rootEntry.value = rootValue;

	[self assignPHPSerializedParentForEntry:rootEntry];
	self.phpSerializedRootEntry = rootEntry;
	self.phpSerializedSelectedEntry = rootEntry;
	return YES;
}

- (void)assignPHPSerializedParentForEntry:(SAPHPSerializedEntry *)entry
{
	for (SAPHPSerializedEntry *child in entry.value.children) {
		child.parent = entry;
		[self assignPHPSerializedParentForEntry:child];
	}
}

- (void)refreshPHPSerializedEditorAvailability
{
	NSString *errorMessage = nil;
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:[self currentPHPSerializedText] encoding:encoding error:&errorMessage];
	[self.phpSerializedEditorMenuItem setEnabled:(value != nil && _isEditable && !_isJSON && !_isGeometry)];
}

- (void)openPHPSerializedEditorIfCurrentTextIsStructured
{
	if (self.phpSerializedEditorAutomaticallyOpened || ![self.phpSerializedEditorMenuItem isEnabled]) return;

	NSString *errorMessage = nil;
	SAPHPSerializedValue *value = [SAPHPSerializedParser parseString:[self currentPHPSerializedText] encoding:encoding error:&errorMessage];
	if (![value isContainer] && value.type != SAPHPSerializedValueTypeCustomSerialized) return;

	self.phpSerializedEditorAutomaticallyOpened = YES;
	[self openPHPSerializedEditor:self];
}

- (IBAction)openPHPSerializedEditor:(id)sender
{
	if (![self populatePHPSerializedEditorFromCurrentTextShowingError:YES]) return;

	[self buildPHPSerializedEditorSheetIfNeeded];
	[self.phpSerializedOutlineView reloadData];
	[self.phpSerializedOutlineView expandItem:self.phpSerializedRootEntry expandChildren:YES];
	[self.phpSerializedOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	[self updatePHPSerializedInspectorForEntry:self.phpSerializedRootEntry];

	if ([self.phpSerializedEditorSheet isSheet]) return;

	[editSheet beginSheet:self.phpSerializedEditorSheet completionHandler:nil];
}

- (void)buildPHPSerializedEditorSheetIfNeeded
{
	if (self.phpSerializedEditorSheet) return;

	NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 820, 520)
												styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
												  backing:NSBackingStoreBuffered
													defer:NO];
	[panel setTitle:NSLocalizedString(@"PHP Serialized Data", @"PHP serialized editor sheet title")];
	[panel setMinSize:NSMakeSize(650, 420)];
	self.phpSerializedEditorSheet = panel;

	NSView *contentView = [panel contentView];

	NSScrollView *outlineScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	[outlineScrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
	[outlineScrollView setHasVerticalScroller:YES];
	[outlineScrollView setHasHorizontalScroller:YES];
	[outlineScrollView setBorderType:NSBezelBorder];

	NSOutlineView *outlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
	NSTableColumn *keyColumn = [[NSTableColumn alloc] initWithIdentifier:@"key"];
	[keyColumn setTitle:NSLocalizedString(@"Key", @"PHP serialized editor key column")];
	[keyColumn setWidth:170];
	NSTableColumn *typeColumn = [[NSTableColumn alloc] initWithIdentifier:@"type"];
	[typeColumn setTitle:NSLocalizedString(@"Type", @"PHP serialized editor type column")];
	[typeColumn setWidth:130];
	NSTableColumn *valueColumn = [[NSTableColumn alloc] initWithIdentifier:@"value"];
	[valueColumn setTitle:NSLocalizedString(@"Value", @"PHP serialized editor value column")];
	[valueColumn setWidth:260];

	[outlineView addTableColumn:keyColumn];
	[outlineView addTableColumn:typeColumn];
	[outlineView addTableColumn:valueColumn];
	[outlineView setOutlineTableColumn:keyColumn];
	[outlineView setDelegate:self];
	[outlineView setDataSource:self];
	[outlineView setUsesAlternatingRowBackgroundColors:YES];
	[outlineView setAllowsColumnResizing:YES];
	[outlineView setAllowsMultipleSelection:NO];
	[outlineScrollView setDocumentView:outlineView];
	self.phpSerializedOutlineView = outlineView;

	NSView *inspectorView = [[NSView alloc] initWithFrame:NSZeroRect];
	[inspectorView setTranslatesAutoresizingMaskIntoConstraints:NO];

	NSTextField *selectionLabel = [NSTextField wrappingLabelWithString:@""];
	[selectionLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
	self.phpSerializedSelectionLabel = selectionLabel;

	NSPopUpButton *typePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	[typePopup setTranslatesAutoresizingMaskIntoConstraints:NO];
	[typePopup addItemsWithTitles:@[
		NSLocalizedString(@"String", @"PHP serialized editor string type"),
		NSLocalizedString(@"Integer", @"PHP serialized editor integer type"),
		NSLocalizedString(@"Float", @"PHP serialized editor float type"),
		NSLocalizedString(@"Boolean", @"PHP serialized editor boolean type"),
		NSLocalizedString(@"Array", @"PHP serialized editor array type"),
		NSLocalizedString(@"Null", @"PHP serialized editor null type")
	]];
	self.phpSerializedTypePopup = typePopup;

	NSScrollView *valueScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	[valueScrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
	[valueScrollView setHasVerticalScroller:YES];
	[valueScrollView setBorderType:NSBezelBorder];

	NSTextView *valueTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
	[valueTextView setRichText:NO];
	[valueTextView setUsesFindBar:YES];
	[valueTextView setAutomaticDashSubstitutionEnabled:NO];
	[valueTextView setAutomaticQuoteSubstitutionEnabled:NO];
	[valueTextView setFont:[self selectFont]];
	[valueScrollView setDocumentView:valueTextView];
	self.phpSerializedValueTextView = valueTextView;

	NSButton *updateButton = [NSButton buttonWithTitle:NSLocalizedString(@"Update Selected", @"PHP serialized editor update selected button")
											   target:self
											   action:@selector(updatePHPSerializedSelectedValue:)];
	[updateButton setTranslatesAutoresizingMaskIntoConstraints:NO];
	self.phpSerializedUpdateButton = updateButton;

	NSButton *addButton = [NSButton buttonWithTitle:NSLocalizedString(@"Add Child", @"PHP serialized editor add child button")
											target:self
											action:@selector(addPHPSerializedChild:)];
	[addButton setTranslatesAutoresizingMaskIntoConstraints:NO];
	self.phpSerializedAddButton = addButton;

	NSButton *deleteButton = [NSButton buttonWithTitle:NSLocalizedString(@"Delete", @"PHP serialized editor delete button")
											   target:self
											   action:@selector(deletePHPSerializedEntry:)];
	[deleteButton setTranslatesAutoresizingMaskIntoConstraints:NO];
	self.phpSerializedDeleteButton = deleteButton;

	NSButton *cancelButton = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", @"cancel button")
											   target:self
											   action:@selector(cancelPHPSerializedEditor:)];
	[cancelButton setTranslatesAutoresizingMaskIntoConstraints:NO];

	NSButton *applyButton = [NSButton buttonWithTitle:NSLocalizedString(@"Apply to Field", @"PHP serialized editor apply button")
											  target:self
											  action:@selector(applyPHPSerializedEditor:)];
	[applyButton setTranslatesAutoresizingMaskIntoConstraints:NO];
	[applyButton setKeyEquivalent:@"\r"];

	[contentView addSubview:outlineScrollView];
	[contentView addSubview:inspectorView];
	[contentView addSubview:addButton];
	[contentView addSubview:deleteButton];
	[contentView addSubview:cancelButton];
	[contentView addSubview:applyButton];

	[inspectorView addSubview:selectionLabel];
	[inspectorView addSubview:typePopup];
	[inspectorView addSubview:valueScrollView];
	[inspectorView addSubview:updateButton];

	[NSLayoutConstraint activateConstraints:@[
		[outlineScrollView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:14],
		[outlineScrollView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:14],
		[outlineScrollView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-58],
		[outlineScrollView.widthAnchor constraintEqualToConstant:470],

		[inspectorView.leadingAnchor constraintEqualToAnchor:outlineScrollView.trailingAnchor constant:12],
		[inspectorView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-14],
		[inspectorView.topAnchor constraintEqualToAnchor:outlineScrollView.topAnchor],
		[inspectorView.bottomAnchor constraintEqualToAnchor:outlineScrollView.bottomAnchor],

		[selectionLabel.leadingAnchor constraintEqualToAnchor:inspectorView.leadingAnchor],
		[selectionLabel.trailingAnchor constraintEqualToAnchor:inspectorView.trailingAnchor],
		[selectionLabel.topAnchor constraintEqualToAnchor:inspectorView.topAnchor],

		[typePopup.leadingAnchor constraintEqualToAnchor:inspectorView.leadingAnchor],
		[typePopup.topAnchor constraintEqualToAnchor:selectionLabel.bottomAnchor constant:12],
		[typePopup.widthAnchor constraintEqualToConstant:160],

		[valueScrollView.leadingAnchor constraintEqualToAnchor:inspectorView.leadingAnchor],
		[valueScrollView.trailingAnchor constraintEqualToAnchor:inspectorView.trailingAnchor],
		[valueScrollView.topAnchor constraintEqualToAnchor:typePopup.bottomAnchor constant:10],
		[valueScrollView.bottomAnchor constraintEqualToAnchor:updateButton.topAnchor constant:-10],

		[updateButton.trailingAnchor constraintEqualToAnchor:inspectorView.trailingAnchor],
		[updateButton.bottomAnchor constraintEqualToAnchor:inspectorView.bottomAnchor],

		[addButton.leadingAnchor constraintEqualToAnchor:outlineScrollView.leadingAnchor],
		[addButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-14],
		[deleteButton.leadingAnchor constraintEqualToAnchor:addButton.trailingAnchor constant:8],
		[deleteButton.centerYAnchor constraintEqualToAnchor:addButton.centerYAnchor],

		[applyButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-14],
		[applyButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-14],
		[cancelButton.trailingAnchor constraintEqualToAnchor:applyButton.leadingAnchor constant:-8],
		[cancelButton.centerYAnchor constraintEqualToAnchor:applyButton.centerYAnchor],
	]];
}

- (NSString *)keyLabelForPHPSerializedEntry:(SAPHPSerializedEntry *)entry
{
	if (entry == self.phpSerializedRootEntry) return @"root";
	if (entry.keyIsInteger) return [NSString stringWithFormat:@"[%@]", [entry.key description]];
	return (entry.key)?:@"";
}

- (void)updatePHPSerializedInspectorForEntry:(SAPHPSerializedEntry *)entry
{
	self.phpSerializedSelectedEntry = entry;
	SAPHPSerializedValue *value = entry.value;
	[self.phpSerializedSelectionLabel setStringValue:[NSString stringWithFormat:@"%@  %@", [self keyLabelForPHPSerializedEntry:entry], [value typeLabel]]];

	BOOL canEditScalar = [value isScalarEditable];
	BOOL canEditStructure = _isEditable && ![self.phpSerializedRootEntry.value containsReference];
	[self.phpSerializedTypePopup setEnabled:canEditScalar && _isEditable];
	[self.phpSerializedValueTextView setEditable:canEditScalar && _isEditable];
	[self.phpSerializedUpdateButton setEnabled:canEditScalar && _isEditable];
	[self.phpSerializedAddButton setEnabled:[value isContainer] && canEditStructure];
	[self.phpSerializedDeleteButton setEnabled:(entry != self.phpSerializedRootEntry && canEditStructure)];

	switch (value.type) {
		case SAPHPSerializedValueTypeString:
			[self.phpSerializedTypePopup selectItemWithTitle:NSLocalizedString(@"String", @"PHP serialized editor string type")];
			break;
		case SAPHPSerializedValueTypeInteger:
			[self.phpSerializedTypePopup selectItemWithTitle:NSLocalizedString(@"Integer", @"PHP serialized editor integer type")];
			break;
		case SAPHPSerializedValueTypeDouble:
			[self.phpSerializedTypePopup selectItemWithTitle:NSLocalizedString(@"Float", @"PHP serialized editor float type")];
			break;
		case SAPHPSerializedValueTypeBoolean:
			[self.phpSerializedTypePopup selectItemWithTitle:NSLocalizedString(@"Boolean", @"PHP serialized editor boolean type")];
			break;
		case SAPHPSerializedValueTypeArray:
			[self.phpSerializedTypePopup selectItemWithTitle:NSLocalizedString(@"Array", @"PHP serialized editor array type")];
			break;
		case SAPHPSerializedValueTypeNull:
			[self.phpSerializedTypePopup selectItemWithTitle:NSLocalizedString(@"Null", @"PHP serialized editor null type")];
			break;
		default:
			[self.phpSerializedTypePopup selectItemAtIndex:0];
			break;
	}

	if (canEditScalar || value.type == SAPHPSerializedValueTypeCustomSerialized || value.type == SAPHPSerializedValueTypeEnum || value.type == SAPHPSerializedValueTypeReference) {
		[self.phpSerializedValueTextView setString:[value displayValue]];
	}
	else {
		[self.phpSerializedValueTextView setString:NSLocalizedString(@"Select a scalar value to edit it. Arrays and objects can be expanded in the tree.", @"PHP serialized editor container inspector text")];
	}
}

- (BOOL)commitPHPSerializedSelectedValueShowingError:(BOOL)showError
{
	SAPHPSerializedEntry *entry = self.phpSerializedSelectedEntry;
	if (!entry || ![entry.value isScalarEditable]) return YES;

	NSString *selectedType = [[self.phpSerializedTypePopup selectedItem] title];
	NSString *rawValue = [self.phpSerializedValueTextView string] ?: @"";

	if ([selectedType isEqualToString:NSLocalizedString(@"String", @"PHP serialized editor string type")]) {
		entry.value.type = SAPHPSerializedValueTypeString;
		entry.value.scalarValue = rawValue;
	}
	else if ([selectedType isEqualToString:NSLocalizedString(@"Integer", @"PHP serialized editor integer type")]) {
		NSString *trimmedValue = [SAPHPSerializedValue normalizedIntegerStringFromEditedString:rawValue];
		if (!trimmedValue) {
			if (showError) [SPTooltip showWithObject:NSLocalizedString(@"Integer values may only contain digits and an optional leading minus sign.", @"PHP serialized editor integer validation error")];
			return NO;
		}
		entry.value.type = SAPHPSerializedValueTypeInteger;
		entry.value.scalarValue = trimmedValue;
	}
	else if ([selectedType isEqualToString:NSLocalizedString(@"Float", @"PHP serialized editor float type")]) {
		NSString *trimmedValue = [rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (![trimmedValue length]) {
			if (showError) [SPTooltip showWithObject:NSLocalizedString(@"Float values cannot be empty.", @"PHP serialized editor float validation error")];
			return NO;
		}
		if (![SAPHPSerializedValue isValidPHPFloatString:trimmedValue]) {
			if (showError) [SPTooltip showWithObject:NSLocalizedString(@"Float values must be a valid number, INF, -INF, or NAN.", @"PHP serialized editor float validation error")];
			return NO;
		}
		entry.value.type = SAPHPSerializedValueTypeDouble;
		entry.value.scalarValue = trimmedValue;
	}
	else if ([selectedType isEqualToString:NSLocalizedString(@"Boolean", @"PHP serialized editor boolean type")]) {
		NSString *normalized = [[rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
		if ([normalized isEqualToString:@"1"] || [normalized isEqualToString:@"true"] || [normalized isEqualToString:@"yes"]) {
			entry.value.scalarValue = @"1";
		}
		else if ([normalized isEqualToString:@"0"] || [normalized isEqualToString:@"false"] || [normalized isEqualToString:@"no"] || ![normalized length]) {
			entry.value.scalarValue = @"0";
		}
		else {
			if (showError) [SPTooltip showWithObject:NSLocalizedString(@"Boolean values must be true/false or 1/0.", @"PHP serialized editor boolean validation error")];
			return NO;
		}
		entry.value.type = SAPHPSerializedValueTypeBoolean;
	}
	else if ([selectedType isEqualToString:NSLocalizedString(@"Array", @"PHP serialized editor array type")]) {
		if ([self.phpSerializedRootEntry.value containsReference]) {
			if (showError) [SPTooltip showWithObject:NSLocalizedString(@"Cannot change serialized structure while PHP references are present.", @"PHP serialized editor reference structure validation error")];
			return NO;
		}
		entry.value.type = SAPHPSerializedValueTypeArray;
		entry.value.scalarValue = @"";
		entry.value.className = nil;
		entry.value.referenceType = nil;
		[entry.value.children removeAllObjects];
	}
	else {
		entry.value.type = SAPHPSerializedValueTypeNull;
		entry.value.scalarValue = @"";
	}

	return YES;
}

- (IBAction)updatePHPSerializedSelectedValue:(id)sender
{
	if (![self commitPHPSerializedSelectedValueShowingError:YES]) return;
	[self.phpSerializedOutlineView reloadData];
	[self updatePHPSerializedInspectorForEntry:self.phpSerializedSelectedEntry];
}

- (IBAction)addPHPSerializedChild:(id)sender
{
	SAPHPSerializedEntry *selectedEntry = self.phpSerializedSelectedEntry;
	if (![selectedEntry.value isContainer]) return;
	if ([self.phpSerializedRootEntry.value containsReference]) {
		[SPTooltip showWithObject:NSLocalizedString(@"Cannot add entries while PHP references are present.", @"PHP serialized editor reference add validation error")];
		return;
	}

	SAPHPSerializedEntry *newEntry = [[SAPHPSerializedEntry alloc] init];
	newEntry.parent = selectedEntry;
	newEntry.value = [SAPHPSerializedValue valueWithType:SAPHPSerializedValueTypeString];
	newEntry.value.scalarValue = @"";

	if (selectedEntry.value.type == SAPHPSerializedValueTypeArray) {
		newEntry.keyIsInteger = YES;
		newEntry.key = [selectedEntry.value nextAvailableArrayKey];
	}
	else {
		newEntry.keyIsInteger = NO;
		newEntry.key = [selectedEntry.value uniqueObjectPropertyName];
	}

	[selectedEntry.value.children addObject:newEntry];
	[self.phpSerializedOutlineView reloadData];
	[self.phpSerializedOutlineView expandItem:selectedEntry];
	NSInteger row = [self.phpSerializedOutlineView rowForItem:newEntry];
	if (row >= 0) {
		[self.phpSerializedOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
	}
}

- (IBAction)deletePHPSerializedEntry:(id)sender
{
	SAPHPSerializedEntry *selectedEntry = self.phpSerializedSelectedEntry;
	if (!selectedEntry || selectedEntry == self.phpSerializedRootEntry || !selectedEntry.parent) return;
	if ([self.phpSerializedRootEntry.value containsReference]) {
		[SPTooltip showWithObject:NSLocalizedString(@"Cannot delete entries while PHP references are present.", @"PHP serialized editor reference delete validation error")];
		return;
	}

	SAPHPSerializedEntry *parent = selectedEntry.parent;
	[parent.value.children removeObject:selectedEntry];
	self.phpSerializedSelectedEntry = parent;
	[self.phpSerializedOutlineView reloadData];
	NSInteger parentRow = [self.phpSerializedOutlineView rowForItem:parent];
	if (parentRow >= 0) {
		[self.phpSerializedOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)parentRow] byExtendingSelection:NO];
	}
}

- (IBAction)applyPHPSerializedEditor:(id)sender
{
	if (![self commitPHPSerializedSelectedValueShowingError:YES]) return;

	NSString *errorMessage = nil;
	NSString *serialized = [self.phpSerializedRootEntry.value serializedStringWithError:&errorMessage];
	if (!serialized) {
		[SPTooltip showWithObject:errorMessage ?: NSLocalizedString(@"Unable to serialize PHP data.", @"PHP serialized editor output error")];
		return;
	}
	[editTextView setString:serialized];
	sheetEditData = serialized;
	editTextViewWasChanged = YES;
	[hexTextView setString:@""];
	[self refreshPHPSerializedEditorAvailability];
	[editSheet endSheet:self.phpSerializedEditorSheet returnCode:NSModalResponseOK];
	[self.phpSerializedEditorSheet orderOut:self];
}

- (IBAction)cancelPHPSerializedEditor:(id)sender
{
	[editSheet endSheet:self.phpSerializedEditorSheet returnCode:NSModalResponseCancel];
	[self.phpSerializedEditorSheet orderOut:self];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (outlineView != self.phpSerializedOutlineView) return 0;
	if (!item) return self.phpSerializedRootEntry ? 1 : 0;
	SAPHPSerializedEntry *entry = item;
	return [entry.value.children count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	if (outlineView != self.phpSerializedOutlineView) return nil;
	if (!item) return self.phpSerializedRootEntry;
	SAPHPSerializedEntry *entry = item;
	return [entry.value.children objectAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	if (outlineView != self.phpSerializedOutlineView) return NO;
	SAPHPSerializedEntry *entry = item;
	return [entry.value.children count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	if (outlineView != self.phpSerializedOutlineView) return @"";
	SAPHPSerializedEntry *entry = item;
	NSString *identifier = [tableColumn identifier];
	if ([identifier isEqualToString:@"key"]) return [self keyLabelForPHPSerializedEntry:entry];
	if ([identifier isEqualToString:@"type"]) return [entry.value typeLabel];
	if ([identifier isEqualToString:@"value"]) return [entry.value displayValue];
	return @"";
}

- (BOOL)selectionShouldChangeInOutlineView:(NSOutlineView *)outlineView
{
	if (outlineView != self.phpSerializedOutlineView) return YES;
	return [self commitPHPSerializedSelectedValueShowingError:YES];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	if ([notification object] != self.phpSerializedOutlineView) return;

	NSInteger row = [self.phpSerializedOutlineView selectedRow];
	SAPHPSerializedEntry *entry = (row >= 0) ? [self.phpSerializedOutlineView itemAtRow:row] : self.phpSerializedRootEntry;
	if (entry) {
		[self updatePHPSerializedInspectorForEntry:entry];
	}
}

#pragma mark -
#pragma mark UndoManager methods

/**
 * Establish and return an UndoManager for editTextView
 */
- (NSUndoManager*)undoManagerForTextView:(NSTextView*)aTextView
{
	if (!esUndoManager)
		esUndoManager = [[NSUndoManager alloc] init];

	return esUndoManager;
}

/**
 * Set variable if something in editTextView was cutted or pasted for creating better undo grouping.
 */
- (void)setWasCutPaste
{
	wasCutPaste = YES;
}

/**
 * Will be invoke delayed for creating better undo grouping according to type speed (see [self textDidChange:]).
 */
- (void)setAllowedUndo
{
	allowUndo = YES;
}

/**
 * Will be set if according to characters typed in editTextView for creating better undo grouping.
 */
- (void)setDoGroupDueToChars
{
	doGroupDueToChars = YES;
}

#pragma mark -
#pragma mark UI Helper Methods

- (void)showHexText:(BOOL)show {
	BOOL hidden = !show;
	[hexTextView setHidden:hidden];
	[hexTextScrollView setHidden:hidden];
	if (show) { // hide others
		[self showEditText:hidden];
		[self showJsonText:hidden];
		[self showImage:hidden];
	}
}

- (void)showEditText:(BOOL)show {
	BOOL hidden = !show;
	[editTextView setHidden:hidden];
	[editTextScrollView setHidden:hidden];
	if (show) { // hide others
		[self showHexText:hidden];
		[self showJsonText:hidden];
		[self showImage:hidden];
	}
}

- (void)showJsonText:(BOOL)show {
	BOOL hidden = !show;
	[jsonTextView setHidden:hidden];
	[jsonTextScrollView setHidden:hidden];
	if (show) { // hide others
		[self showHexText:hidden];
		[self showEditText:hidden];
		[self showImage:hidden];
	}
}

- (void)showImage:(BOOL)show {
	BOOL hidden = !show;
	[editImage setHidden:hidden];
	if (show) { // hide others
		[self showHexText:hidden];
		[self showEditText:hidden];
		[self showJsonText:hidden];
	}
}

@end
