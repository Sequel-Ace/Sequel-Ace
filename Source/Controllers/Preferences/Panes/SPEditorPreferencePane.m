//
//  SPEditorPreferencePane.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on October 31, 2010.
//  Copyright (c) 2010 Stuart Connolly. All rights reserved.
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

#import "SPEditorPreferencePane.h"
#import "SPPreferenceController.h"
#import "SPColorWellCell.h"
#import "SPAlertSheets.h"
#import "SPCategoryAdditions.h"
#import "SPFunctions.h"

// Constants
static NSString *SPSaveColorScheme          = @"SaveColorScheme";
static NSString *SPDefaultColorSchemeName   = @"Default";
static NSString *SPDefaultColorSchemeNameLC = @"default";
static NSString *SPCustomColorSchemeName    = @"User-defined";
static NSString *SPCustomColorSchemeNameLC  = @"user-defined";

#define SP_EXPORT_COLOR_SCHEME_NAME_STRING NSLocalizedString(@"MyTheme", @"Preferences : Themes : Initial filename for 'Export'")

@interface SPEditorPreferencePane ()

- (BOOL)_checkForUnsavedTheme;
- (NSArray *)_getAvailableThemes;
- (void)_saveColorThemeAtPath:(NSString *)path;
- (BOOL)_loadColorSchemeFromFile:(NSString *)filename;

@property (readwrite, retain) NSFileManager *fileManager;

@end

@implementation SPEditorPreferencePane

@synthesize fileManager;


#pragma mark -
#pragma mark Initialisation

- (id)init
{
	if ((self = [super init])) {
		
		fileManager = [NSFileManager defaultManager];

		themePath = [[fileManager applicationSupportDirectoryForSubDirectory:SPThemesSupportFolder error:nil] retain];
		
		editThemeListItems = [[NSArray arrayWithArray:[self _getAvailableThemes]] retain];
		
		editorColors = [@[
			SPCustomQueryEditorTextColor,
			SPCustomQueryEditorBackgroundColor,
			SPCustomQueryEditorCaretColor,
			SPCustomQueryEditorCommentColor,
			SPCustomQueryEditorSQLKeywordColor,
			SPCustomQueryEditorNumericColor,
			SPCustomQueryEditorQuoteColor,
			SPCustomQueryEditorBacktickColor,
			SPCustomQueryEditorVariableColor,
			SPCustomQueryEditorHighlightQueryColor,
			SPCustomQueryEditorSelectionColor
		] retain];
		
		editorNameForColors = [@[
			NSLocalizedString(@"Text", @"text label for color table (Prefs > Editor)"),
			NSLocalizedString(@"Background", @"background label for color table (Prefs > Editor)"),
			NSLocalizedString(@"Caret", @"caret label for color table (Prefs > Editor)"),
			NSLocalizedString(@"Comment", @"comment label"),
			NSLocalizedString(@"Keyword", @"keyword label for color table (Prefs > Editor)"),
			NSLocalizedString(@"Numeric", @"numeric label for color table (Prefs > Editor)"),
			NSLocalizedString(@"Quote", @"quote label for color table (Prefs > Editor)"),
			NSLocalizedString(@"Backtick Quote", @"backtick quote label for color table (Prefs > Editor)"),
			NSLocalizedString(@"Variable", @"variable label for color table (Prefs > Editor)"),
			NSLocalizedString(@"Query Background", @"query background label for color table (Prefs > Editor)"),
			NSLocalizedString(@"Selection", @"selection label for color table (Prefs > Editor)")
		] retain];
	}
	
	return self;
}

/**
 * Initialise the UI, specifically the colours table view.
 */
- (void)awakeFromNib
{
	[NSColor setIgnoresAlpha:NO];
	
	NSTableColumn *column = [[colorSettingTableView tableColumns] objectAtIndex:0];
	NSTextFieldCell *textCell = [[[NSTextFieldCell alloc] init] autorelease];
	
	[textCell setFont:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorFont]]];
	
	column = [[colorSettingTableView tableColumns] objectAtIndex: 1];
	
	SPColorWellCell *colorCell = [[[SPColorWellCell alloc] init] autorelease];
	
	[colorCell setEditable:YES];
	[colorCell setTarget:self];
	[colorCell setAction:@selector(colorClick:)];
	
	[column setDataCell:colorCell];

	[colorSettingTableView setBackgroundColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorBackgroundColor]]];
}

#pragma mark -
#pragma mark IB action methods

- (IBAction)exportColorScheme:(id)sender
{
	NSSavePanel *panel = [NSSavePanel savePanel];
	
	[panel setAllowedFileTypes:@[SPColorThemeFileExtension]];
	
	[panel setExtensionHidden:NO];
	[panel setAllowsOtherFileTypes:NO];
	[panel setCanSelectHiddenExtension:YES];
	[panel setCanCreateDirectories:YES];
	[panel setNameFieldStringValue:[SP_EXPORT_COLOR_SCHEME_NAME_STRING stringByAppendingPathExtension:SPColorThemeFileExtension]];

	[panel beginSheetModalForWindow:[[self view] window] completionHandler:^(NSInteger returnCode)
	{
		if (returnCode == NSModalResponseOK) {
			[self _saveColorThemeAtPath:[[panel URL] path]];
		}
	}];
}

- (IBAction)importColorScheme:(id)sender
{
	if (![self _checkForUnsavedTheme]) return;	
	
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	
	[panel setCanSelectHiddenExtension:YES];
	[panel setDelegate:self];
	[panel setCanChooseDirectories:NO];
	[panel setAllowsMultipleSelection:NO];
	[panel setAllowedFileTypes:@[SPColorThemeFileExtension, @"tmTheme"]];

	[panel beginSheetModalForWindow:[[self view] window] completionHandler:^(NSInteger returnCode)
	{
		if (returnCode == NSModalResponseOK) {
			if ([self _loadColorSchemeFromFile:[[[panel URLs] objectAtIndex:0] path] ]) {
				[prefs setObject:SPCustomColorSchemeName forKey:SPCustomQueryEditorThemeName];

				[self updateDisplayColorThemeName];
			}
		}
	}];
}

- (IBAction)loadColorScheme:(id)sender
{
	if (![self _checkForUnsavedTheme]) return;
	
	if ([self _loadColorSchemeFromFile:[NSString stringWithFormat:@"%@/%@.%@", themePath, [sender title], SPColorThemeFileExtension]]) {
		[prefs setObject:[sender title] forKey:SPCustomQueryEditorThemeName];
		
		[self updateDisplayColorThemeName];
	}
}

- (IBAction)saveAsColorScheme:(id)sender
{
	[[NSColorPanel sharedColorPanel] close];
	
	[enterNameAlertField setHidden:YES];
	[enterNameInputField setStringValue:@""];
	[enterNameLabel setStringValue:NSLocalizedString(@"Theme Name:", @"theme name label")];
	
	[NSApp beginSheet:enterNameWindow
	   modalForWindow:[[self view] window]
	    modalDelegate:self
	   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
	      contextInfo:SPSaveColorScheme];
	
}

- (IBAction)duplicateTheme:(id)sender
{
	if ([editThemeListTable numberOfSelectedRows] != 1) return;
	
	NSString *selectedPath = [NSString stringWithFormat:@"%@/%@_copy.%@", themePath, [editThemeListItems objectAtIndex:[editThemeListTable selectedRow]], SPColorThemeFileExtension];
		
	if (![fileManager fileExistsAtPath:selectedPath isDirectory:nil]) {
		if ([fileManager copyItemAtPath:[NSString stringWithFormat:@"%@/%@.%@", themePath, [editThemeListItems objectAtIndex:[editThemeListTable selectedRow]], SPColorThemeFileExtension] toPath:selectedPath error:nil]) {
			
			if (editThemeListItems) SPClear(editThemeListItems);
			
			editThemeListItems = [[NSArray arrayWithArray:[self _getAvailableThemes]] retain];
			
			[editThemeListTable reloadData];
			
			[self updateDisplayColorThemeName];
			[self updateColorSchemeSelectionMenu];
			
			return;
		}
	}
	
	[editThemeListTable reloadData];
}

- (IBAction)removeTheme:(id)sender
{
	if ([editThemeListTable numberOfSelectedRows] != 1) return;
	
	NSString *selectedPath = [NSString stringWithFormat:@"%@/%@.%@", themePath, [editThemeListItems objectAtIndex:[editThemeListTable selectedRow]], SPColorThemeFileExtension];
		
	if ([fileManager fileExistsAtPath:selectedPath isDirectory:nil]) {
		if ([fileManager removeItemAtPath:selectedPath error:nil]) {
			
			// Refresh current color theme setting name
			if ([[[prefs objectForKey:SPCustomQueryEditorThemeName] lowercaseString] isEqualToString:[[editThemeListItems objectAtIndex:[editThemeListTable selectedRow]] lowercaseString]]) {
				[prefs setObject:SPCustomColorSchemeName forKey:SPCustomQueryEditorThemeName];
			}
			
			if (editThemeListItems) SPClear(editThemeListItems);
			
			editThemeListItems = [[NSArray arrayWithArray:[self _getAvailableThemes]] retain];
			
			[editThemeListTable reloadData];
			
			[self updateDisplayColorThemeName];
			[self updateColorSchemeSelectionMenu];
			
			return;
		}
	}
	
	[editThemeListTable reloadData];
}

- (IBAction)closePanelSheet:(id)sender
{
	[NSApp endSheet:[sender window] returnCode:[sender tag]];
	[[sender window] orderOut:self];
}

/**
 * Opens the font panel.
 */
- (IBAction)showCustomQueryFontPanel:(id)sender
{
	[(SPPreferenceController *)[[[self view] window] delegate] setFontChangeTarget:SPPrefFontChangeTargetEditor];
	
	[[NSFontPanel sharedFontPanel] setPanelFont:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorFont]] isMultiple:NO];
	[[NSFontPanel sharedFontPanel] makeKeyAndOrderFront:self];
}

/**
 * Sets the syntax colours back to there defaults.
 */
- (IBAction)setDefaultColors:(id)sender
{
	if (![self _checkForUnsavedTheme]) return;
	
	[[NSColorPanel sharedColorPanel] close];
	
	[prefs setObject:SPDefaultColorSchemeName forKey:SPCustomQueryEditorThemeName];
	
	NSDictionary *vendorDefaults = [prefs volatileDomainForName:NSRegistrationDomain]; // corresponds to -registerDefaults: in the app controller
	
	NSArray *copyKeys = @[
		SPCustomQueryEditorCommentColor,
		SPCustomQueryEditorQuoteColor,
		SPCustomQueryEditorSQLKeywordColor,
		SPCustomQueryEditorBacktickColor,
		SPCustomQueryEditorNumericColor,
		SPCustomQueryEditorVariableColor,
		SPCustomQueryEditorHighlightQueryColor,
		SPCustomQueryEditorSelectionColor,
		SPCustomQueryEditorTextColor,
		SPCustomQueryEditorCaretColor,
		SPCustomQueryEditorBackgroundColor,
	];
	
	for(NSString *key in copyKeys) {
		[prefs setObject:[vendorDefaults objectForKey:key] forKey:key];
	}

	[colorSettingTableView setBackgroundColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorBackgroundColor]]];
	[colorSettingTableView reloadData];
	
	[self updateDisplayColorThemeName];
}

/**
 * Opens the theme liste sheet.
 */
- (IBAction)editThemeList:(id)sender
{
	[[NSColorPanel sharedColorPanel] close];
	
	if (editThemeListItems) SPClear(editThemeListItems);
	
	editThemeListItems = [[NSArray arrayWithArray:[self _getAvailableThemes]] retain];
	
	[editThemeListTable reloadData];
	
	[NSApp beginSheet:editThemeListWindow
	   modalForWindow:[[self view] window]
	    modalDelegate:self
	   didEndSelector:nil
	      contextInfo:nil];
}

#pragma mark -
#pragma mark Public API

/**
 * Updates the displayed font according to the user's preferences.
 */
- (void)updateDisplayedEditorFontName
{
	NSFont *font = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorFont]];
	
	[editorFontName setFont:font];
	
	[colorSettingTableView reloadData];
}

/**
 * Updates the colour scheme selection menu according to the available schemes.
 */
- (void)updateColorSchemeSelectionMenu
{	
	NSMenuItem *defaultItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Default", @"default label") 
	                                                     action:@selector(setDefaultColors:) 
	                                              keyEquivalent:@""];
	
	[defaultItem setTarget:self];
	
	// Build theme selection submenu
	[themeSelectionMenu removeAllItems];
	[themeSelectionMenu addItem:defaultItem];
	[themeSelectionMenu addItem:[NSMenuItem separatorItem]];
	
	[defaultItem release];
	
	NSArray *foundThemes = [self _getAvailableThemes];
	
	if ([foundThemes count]) {
		for (NSString* item in foundThemes)
		{
			NSMenuItem *loadItem = [[NSMenuItem alloc] initWithTitle:item action:@selector(loadColorScheme:) keyEquivalent:@""];
			
			[loadItem setTarget:self];
			
			[themeSelectionMenu addItem:loadItem];
			
			[loadItem release];
		}
		
		[themeSelectionMenu addItem:[NSMenuItem separatorItem]];
	}
	
	NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Edit Theme List…", @"edit theme list label") 
	                                                  action:@selector(editThemeList:)
	                                           keyEquivalent:@""];
	
	[editItem setTarget:self];
	
	[themeSelectionMenu addItem:editItem];
	
	[editItem release];
}

/**
 * Updates the currently selected colour scheme theme name.
 */
- (void)updateDisplayColorThemeName
{
	if (![prefs objectForKey:SPCustomQueryEditorThemeName]) {
		[colorThemeName setHidden:YES];
		[colorThemeNameLabel setHidden:YES];
		
		return;
	}
	
	if ([[[prefs objectForKey:SPCustomQueryEditorThemeName] lowercaseString] isEqualToString:SPCustomColorSchemeNameLC]) {
		[colorThemeName setHidden:YES];
		[colorThemeNameLabel setHidden:YES];
		
		return;
	}
	
	NSString *currentThemeName = [[prefs objectForKey:SPCustomQueryEditorThemeName] lowercaseString];
	
	if ([currentThemeName isEqualToString:SPDefaultColorSchemeNameLC]) {
		[colorThemeName setHidden:NO];
		[colorThemeNameLabel setHidden:NO];
		
		return;
	}
	
	BOOL nameValid = NO;
	
	for (NSString* item in [self _getAvailableThemes]) 
	{
		if ([[item lowercaseString] isEqualToString:currentThemeName]) {
			nameValid = YES;
			break;
		}
	}
	
	if (nameValid) {
		[colorThemeName setHidden:NO];
		[colorThemeNameLabel setHidden:NO];
	} 
	else {
		[prefs setObject:SPCustomColorSchemeName forKey:SPCustomQueryEditorThemeName];
		[colorThemeName setHidden:YES];
		[colorThemeNameLabel setHidden:YES];
		
		[self updateColorSchemeSelectionMenu];
	}
}

#pragma mark -
#pragma mark Font panel methods

/**
 * Invoked when the user clicks a colour cell.
 */
- (void)colorClick:(id)sender
{	
	colorRow = [sender clickedRow];
	
	NSColorPanel *panel = [NSColorPanel sharedColorPanel];
	
	[panel setTarget:self];
	[panel setAction:@selector(colorChanged:)];
	[panel setColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:[editorColors objectAtIndex:colorRow]]]];
	
	[colorSettingTableView deselectAll:nil];
	
	[panel makeKeyAndOrderFront:self];
}

/**
 * Invoked when the user changes and editor colour.
 */
- (void)colorChanged:(id)sender
{
	if (![[NSColorPanel sharedColorPanel] isVisible]) return;
	
	[prefs setObject:[NSArchiver archivedDataWithRootObject:[sender color]] forKey:[editorColors objectAtIndex:colorRow]];

	if ([[editorColors objectAtIndex:colorRow] isEqualTo:SPCustomQueryEditorBackgroundColor]) {
		[colorSettingTableView setBackgroundColor:[sender color]];
	}

	[colorSettingTableView reloadData];

	[prefs setObject:SPCustomColorSchemeName forKey:SPCustomQueryEditorThemeName];
	
	[self updateDisplayColorThemeName];
}

/**
 * Sets the font panel's valid modes.
 */
- (NSFontPanelModeMask)validModesForFontPanel:(NSFontPanel *)fontPanel
{
	return (NSFontPanelSizeModeMask | NSFontPanelCollectionModeMask);
}

#pragma mark -
#pragma mark Sheet callbacks

- (void)checkForUnsavedThemeDidEndSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	checkForUnsavedThemeSheetStatus = returnCode;
}

- (void)sheetDidEnd:(id)sheet returnCode:(NSInteger)returnCode contextInfo:(NSString *)contextInfo
{
	// Order out current sheet to suppress overlapping of sheets
	if ([sheet respondsToSelector:@selector(orderOut:)]) {
		[sheet orderOut:nil];
	}
	else if ([sheet respondsToSelector:@selector(window)]) {
		[[sheet window] orderOut:nil];
	}
	
	if ([contextInfo isEqualToString:SPSaveColorScheme]) {
		if (returnCode == NSModalResponseOK) {
			
			if (![fileManager fileExistsAtPath:themePath isDirectory:nil]) {
				NSError *error = nil;
				if (![fileManager createDirectoryAtPath:themePath withIntermediateDirectories:YES attributes:nil error:&error]) {
					SPLog(@"Failed to create directory '%@'. error=%@", themePath, error);
					NSBeep();
					return;
				}
			}
			
			[self _saveColorThemeAtPath:[NSString stringWithFormat:@"%@/%@.%@", themePath, [enterNameInputField stringValue], SPColorThemeFileExtension]];
			[self updateColorSchemeSelectionMenu];
			
			[prefs setObject:[enterNameInputField stringValue] forKey:SPCustomQueryEditorThemeName];
			
			[self updateDisplayColorThemeName];
		}
	}
}

#pragma mark -
#pragma mark TableView datasource methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if (tableView == colorSettingTableView) {
		return [editorColors count];
	}
	else if (tableView == editThemeListTable) {
		return [editThemeListItems count];
	}
	
	return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if (tableView == colorSettingTableView) {
		return ([[tableColumn identifier] isEqualToString:@"name"]) ? [editorNameForColors objectAtIndex:rowIndex] : [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:[editorColors objectAtIndex:rowIndex]]];
	} 
	else if (tableView == editThemeListTable) {
		return [editThemeListItems objectAtIndex:rowIndex];
	} 
	
	return nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if (tableView == editThemeListTable) {
		
		// Theme name editing
		NSString *newName = (NSString*)anObject;
		
		// Check for non-valid names
		if (![newName length] || [[newName lowercaseString] isEqualToString:SPDefaultColorSchemeNameLC] || [[newName lowercaseString] isEqualToString:SPCustomColorSchemeNameLC]) {
			NSBeep();
			[editThemeListTable reloadData];
			return;
		}
		
		// Check if new name already exists
		for (NSString* item in editThemeListItems) 
		{
			if ([[item lowercaseString] isEqualToString:newName]) {
				NSBeep();
				[editThemeListTable reloadData];
				return;
			}
		}
		
		// Rename theme file
		if (![fileManager moveItemAtPath:[NSString stringWithFormat:@"%@/%@.%@", themePath, [editThemeListItems objectAtIndex:rowIndex], SPColorThemeFileExtension] toPath:[NSString stringWithFormat:@"%@/%@.%@", themePath, newName, SPColorThemeFileExtension] error:nil]) {
			NSBeep();
			[editThemeListTable reloadData];
			return;
		}
		
		// Refresh current color theme setting name
		if ([[[prefs objectForKey:SPCustomQueryEditorThemeName] lowercaseString] isEqualToString:[[editThemeListItems objectAtIndex:rowIndex] lowercaseString]]) {
			[prefs setObject:newName forKey:SPCustomQueryEditorThemeName];
		}
		
		// Reload everything needed
		if (editThemeListItems) SPClear(editThemeListItems);
		editThemeListItems = [[NSArray arrayWithArray:[self _getAvailableThemes]] retain];
		
		[editThemeListTable reloadData];
		
		[self updateDisplayColorThemeName];
		[self updateColorSchemeSelectionMenu];
	}
}

#pragma mark -
#pragma mark TableView delegate methods

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if(aTableView == colorSettingTableView) {
		
		NSColorPanel* panel;
		
		colorRow = rowIndex;
		panel = [NSColorPanel sharedColorPanel];
		
		[panel setTarget:self];
		[panel setAction:@selector(colorChanged:)];
		[panel setColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:[editorColors objectAtIndex:colorRow]]]];
		[colorSettingTableView deselectAll:nil];
		[panel makeKeyAndOrderFront:self];
		
		return NO;
	}
	
	return YES;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)index
{
	if (tableView == colorSettingTableView && [[tableColumn identifier] isEqualToString:@"name"]) {
		if ([cell isKindOfClass:[NSTextFieldCell class]]) {
			[cell setDrawsBackground:YES];
			
			NSFont *nf = [NSFont fontWithName:[[[NSFontPanel sharedFontPanel] panelConvertFont:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorFont]]] fontName] size:13.0f];
			
			[cell setFont:nf];
			
			switch (index) 
			{
				case 1:
					[cell setTextColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorTextColor]]];
					[cell setBackgroundColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorBackgroundColor]]];
					break;
				case 9:
					[cell setTextColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorTextColor]]];
					[cell setBackgroundColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorHighlightQueryColor]]];
					break;
				case 10:
					[cell setTextColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorTextColor]]];
					[cell setBackgroundColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorSelectionColor]]];
					break;
				default:
					[cell setTextColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:[editorColors objectAtIndex:index]]]];
					[cell setBackgroundColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorBackgroundColor]]];
			}
		}
	}
}

#pragma mark -
#pragma mark TextField delegate methods

/**
 * Trap and control the 'name' field of the selected favorite. If the user pressed
 * 'Add Favorite' the 'name' field is set to "New Favorite". If the user do not
 * change the 'name' field or delete that field it will be set to user@host automatically.
 */
- (void)controlTextDidChange:(NSNotification *)aNotification
{
	id field = [aNotification object];
	
	// Validate 'Save' button for entering a valid theme name
	if (field == enterNameInputField) {
		NSString *name = [[enterNameInputField stringValue] lowercaseString];
		
		if (![name length] || [name isEqualToString:SPDefaultColorSchemeNameLC] || [name isEqualToString:SPCustomColorSchemeNameLC]) {
			[themeNameSaveButton setEnabled:NO];
		} 
		else {
			BOOL hide = YES;
			
			for (NSString* item in [self _getAvailableThemes]) 
			{
				if ([[item lowercaseString] isEqualToString:name]) {
					hide = NO;
					break;
				}
			}
			
			[enterNameAlertField setHidden:hide];
			[themeNameSaveButton setEnabled:YES];
		}
		
		return;
	}
}

#pragma mark -
#pragma mark Preference pane protocol methods

- (NSView *)preferencePaneView
{
	return [self view];
}

- (NSImage *)preferencePaneIcon
{
	return [NSImage imageNamed:@"toolbar-switch-to-sql"];
}

- (NSString *)preferencePaneName
{
	return NSLocalizedString(@"Query Editor", @"query editor preference pane name");
}

- (NSString *)preferencePaneIdentifier
{
	return SPPreferenceToolbarEditor;
}

- (NSString *)preferencePaneToolTip
{
	return NSLocalizedString(@"Query Editor Preferences", @"query editor preference pane tooltip");
}

- (BOOL)preferencePaneAllowsResizing
{
	return NO;
}

- (void)preferencePaneWillBeShown
{
	[self updateColorSchemeSelectionMenu];
	[self updateDisplayColorThemeName];
	
	[self updateDisplayedEditorFontName];
}

#pragma mark -
#pragma mark Private API

- (BOOL)_checkForUnsavedTheme
{
	if (![prefs objectForKey:SPCustomQueryEditorThemeName] || [[[prefs objectForKey:SPCustomQueryEditorThemeName] lowercaseString] isEqualToString:SPCustomColorSchemeNameLC]) {
		
		[[NSColorPanel sharedColorPanel] close];
		
		[SPAlertSheets beginWaitingAlertSheetWithTitle:NSLocalizedString(@"Unsaved Theme", @"unsaved theme message")
		                                 defaultButton:NSLocalizedString(@"Proceed", @"proceed button")
		                               alternateButton:NSLocalizedString(@"Cancel", @"cancel button")
		                                   otherButton:nil
		                                    alertStyle:NSWarningAlertStyle
		                                     docWindow:[[self view] window]
		                                 modalDelegate:self
		                                didEndSelector:@selector(checkForUnsavedThemeDidEndSheet:returnCode:contextInfo:)
		                                   contextInfo:nil
		                                      infoText:NSLocalizedString(@"The current color theme is unsaved. Do you want to proceed without saving it?", @"unsaved theme informative message")
		                                    returnCode:&checkForUnsavedThemeSheetStatus];
		
		return (checkForUnsavedThemeSheetStatus == NSAlertDefaultReturn);
	}
	
	[[NSColorPanel sharedColorPanel] close];
	
	return YES;
}

- (NSArray *)_getAvailableThemes
{
	// Read ~/Library/Application Support/Sequel Ace/Themes
	if ([fileManager fileExistsAtPath:themePath isDirectory:nil]) {
		NSError *error = nil;
		NSArray *allItemsRaw = [fileManager contentsOfDirectoryAtPath:themePath error:&error];
		
		if(!allItemsRaw || error) {
			SPLog(@"Failed to list contents of path '%@'. error=%@", themePath, error);
			return @[];
		}
		
		// Filter out all themes
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF ENDSWITH %@", [NSString stringWithFormat:@".%@", SPColorThemeFileExtension]];
		NSMutableArray *allItems = [NSMutableArray arrayWithArray:allItemsRaw];
		
		[allItems filterUsingPredicate:predicate];
		
		allItemsRaw = [NSArray arrayWithArray:allItems];
		
		[allItems removeAllObjects];
		
		// Remove file extension
		for (NSString* item in allItemsRaw)
		{
			[allItems addObject:[item substringToIndex:[item length]-[SPColorThemeFileExtension length]-1]];
		}
		
		return (NSArray *)allItems;
	}
	
	return @[];
}

- (void)_saveColorThemeAtPath:(NSString *)path
{
	// Build plist dictionary
	NSMutableDictionary *scheme = [NSMutableDictionary dictionary];
	NSMutableDictionary *mainsettings = [NSMutableDictionary dictionary];
	NSMutableArray *settings = [NSMutableArray array];
		
	[prefs synchronize];
	
	NSColor *aColor = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorBackgroundColor]];
	[mainsettings setObject:[aColor rgbHexString] forKey:@"background"];
	
	aColor = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorCaretColor]];
	[mainsettings setObject:[aColor rgbHexString] forKey:@"caret"];
	
	aColor = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorTextColor]];
	[mainsettings setObject:[aColor rgbHexString] forKey:@"foreground"];
	
	aColor = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorHighlightQueryColor]];
	[mainsettings setObject:[aColor rgbHexString] forKey:@"lineHighlight"];
	
	aColor = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorSelectionColor]];
	[mainsettings setObject:[aColor rgbHexString] forKey:@"selection"];
	
	[settings addObject:[NSDictionary dictionaryWithObjectsAndKeys:mainsettings, @"settings", nil]];
	
	aColor = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorCommentColor]];
	[settings addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						 @"Comment", @"name",
						 [NSDictionary dictionaryWithObjectsAndKeys:
						  [aColor rgbHexString], @"foreground",
						  nil
						  ], @"settings",
						 nil
						 ]];
	
	aColor = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorQuoteColor]];
	[settings addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						 @"String", @"name",
						 [NSDictionary dictionaryWithObjectsAndKeys:
						  [aColor rgbHexString], @"foreground",
						  nil
						  ], @"settings",
						 nil
						 ]];
	
	aColor = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorSQLKeywordColor]];
	[settings addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						 @"Keyword", @"name",
						 [NSDictionary dictionaryWithObjectsAndKeys:
						  [aColor rgbHexString], @"foreground",
						  nil
						  ], @"settings",
						 nil
						 ]];
	
	aColor = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorBacktickColor]];
	[settings addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						 @"User-defined constant", @"name",
						 [NSDictionary dictionaryWithObjectsAndKeys:
						  [aColor rgbHexString], @"foreground",
						  nil
						  ], @"settings",
						 nil
						 ]];
	
	aColor = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorNumericColor]];
	[settings addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						 @"Number", @"name",
						 [NSDictionary dictionaryWithObjectsAndKeys:
						  [aColor rgbHexString], @"foreground",
						  nil
						  ], @"settings",
						 nil
						 ]];
	
	aColor = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorVariableColor]];
	[settings addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						 @"Variable", @"name",
						 [NSDictionary dictionaryWithObjectsAndKeys:
						  [aColor rgbHexString], @"foreground",
						  nil
						  ], @"settings",
						 nil
						 ]];
	
	[scheme setObject:settings forKey:@"settings"];
	
	NSError *error = nil;
	NSData *plist = [NSPropertyListSerialization dataWithPropertyList:scheme
	                                                           format:NSPropertyListXMLFormat_v1_0
	                                                          options:0
	                                                            error:&error];
	
	if(error) {
		NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Error while converting color scheme data", @"error while converting color scheme data")
		                                 defaultButton:NSLocalizedString(@"OK", @"OK button") 
		                               alternateButton:nil 
		                                   otherButton:nil 
		                     informativeTextWithFormat:@"%@", [error localizedDescription]];
		
		[alert setAlertStyle:NSCriticalAlertStyle];
		[alert runModal];
		
		return;
	}
	
	[plist writeToFile:path options:NSAtomicWrite error:&error];
	
	if (error) [[NSAlert alertWithError:error] runModal];
}

- (BOOL)_loadColorSchemeFromFile:(NSString *)filename
{
	NSDictionary *theme = nil;

	{
		NSError *error = nil;
		NSData *pData = [NSData dataWithContentsOfFile:filename options:NSUncachedRead error:&error];
		
		if(pData && !error) {
			theme = [NSPropertyListSerialization propertyListWithData:pData
			                                                  options:NSPropertyListImmutable
			                                                   format:NULL
			                                                    error:&error];
		}
		
		if (!theme || error) {
			NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:NSLocalizedString(@"Error while reading data file", @"error while reading data file")]
			                                 defaultButton:NSLocalizedString(@"OK", @"OK button")
			                               alternateButton:nil
			                                   otherButton:nil
			                     informativeTextWithFormat:NSLocalizedString(@"File couldn't be read. (%@)", @"error while reading data file"), [error localizedDescription]];
			
			[alert setAlertStyle:NSCriticalAlertStyle];
			[alert runModal];
			
			[self updateDisplayColorThemeName];
			return NO;
		}
	}
	
	Class NSDictionaryClass = [NSDictionary class];
	Class NSStringClass = [NSString class];
	
	NSUInteger actuallyLoaded = 0;
	NSArray *themeElements;
	if ([theme isKindOfClass:NSDictionaryClass]
		&& (themeElements = [theme objectForKey:@"settings"])
		&& [themeElements isKindOfClass:[NSArray class]]
		&& [themeElements count]) {
		
		NSInteger counter = -1;
		
		NSDictionary *mainPairs = @{
			@"background":    SPCustomQueryEditorBackgroundColor,
			@"caret":         SPCustomQueryEditorCaretColor,
			@"foreground":    SPCustomQueryEditorTextColor,
			@"lineHighlight": SPCustomQueryEditorHighlightQueryColor,
			@"selection":     SPCustomQueryEditorSelectionColor,
		};
		
		NSDictionary *optPairs = @{
			@"Comment":               SPCustomQueryEditorCommentColor,
			@"String":                SPCustomQueryEditorQuoteColor,
			@"Keyword":               SPCustomQueryEditorSQLKeywordColor,
			@"User-defined constant": SPCustomQueryEditorBacktickColor,
			@"Number":                SPCustomQueryEditorNumericColor,
			@"Variable":              SPCustomQueryEditorVariableColor,
		};
		
		for (NSDictionary *dict in themeElements)
		{
			counter++;
			
			if(![dict isKindOfClass:NSDictionaryClass]) {
				SPLog(@"skipping unexpected object at settings[%ld]!",(long)counter);
				continue;
			}
			
			//the first item is special and contains all the main theme colors
			if (counter == 0) {
				NSDictionary *dic = [dict objectForKey:@"settings"];
				if ([dic isKindOfClass:NSDictionaryClass]) {
					for(NSString *key in mainPairs) {
						NSString *rgbHex = [dic objectForKey:key];
						NSColor *color;
						if([rgbHex isKindOfClass:NSStringClass] && (color = [NSColor colorWithRGBHexString:rgbHex])) {
							[prefs setObject:[NSArchiver archivedDataWithRootObject:color] forKey:[mainPairs objectForKey:key]];
							actuallyLoaded++;
						}
						else {
							SPLog(@"Main color key '%@' is either missing in theme or failed parsing as hex color (at settings[0].settings)!", key);
						}
					}
				}
				else {
					SPLog(@"Unexpected type for object main settings (at settings[0].settings)");
				}
			} 
			else {
				NSString *optName = [dict objectForKey:@"name"];
				NSDictionary *optSettings = [dict objectForKey:@"settings"];
				
				if ([optName isKindOfClass:NSStringClass] && [optSettings isKindOfClass:NSDictionaryClass]) {
					NSString *prefName = [optPairs objectForKey:optName];
					if(prefName) {
						NSString *rgbHex = [optSettings objectForKey:@"foreground"];
						NSColor *color;
						if([rgbHex isKindOfClass:NSStringClass] && (color = [NSColor colorWithRGBHexString:rgbHex])) {
							[prefs setObject:[NSArchiver archivedDataWithRootObject:color] forKey:prefName];
							actuallyLoaded++;
						}
						else {
							SPLog(@"Color for entry '%@' is either missing in theme or failed parsing as hex color (at settings[%ld].settings.foreground)!", optName, counter);
						}
					}
					else {
						SPLog(@"Skipping unknown color entry '%@' (at settings[%ld].name)", optName, counter);
					}
				}
				else {
					SPLog(@"Skipping invalid color entry: Either missing keys and/or unexpected objects (at settings[%ld])!", counter);
				}
			}
		}
	}
	else {
		SPLog(@"root key 'settings' is missing, has an unexpected type or is empty in theme file!");
	}

	if(actuallyLoaded > 0) {
		[colorSettingTableView setBackgroundColor:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorBackgroundColor]]];
		[colorSettingTableView reloadData];
	} 
	else {
		NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:NSLocalizedString(@"Error while reading data file", @"error while reading data file")]
		                                 defaultButton:NSLocalizedString(@"OK", @"OK button") 
		                               alternateButton:nil 
		                                   otherButton:nil 
		                     informativeTextWithFormat:NSLocalizedString(@"No color theme data found.", @"error that no color theme found")];
		
		[alert setAlertStyle:NSInformationalAlertStyle];
		[alert runModal];
		
		return NO;
	}
	
	return YES;
}

#pragma mark -

/**
 * Dealloc.
 */
- (void)dealloc
{
	if (themePath)           SPClear(themePath);
	if (editThemeListItems)  SPClear(editThemeListItems);
	if (editorColors)        SPClear(editorColors);
	if (editorNameForColors) SPClear(editorNameForColors);
	
	[super dealloc];
}

@end
