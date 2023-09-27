//
//  SPPreferenceController.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on December 10, 2008.
//  Copyright (c) 2008 Stuart Connolly. All rights reserved.
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

#import "SPPreferenceController.h"
#import "SPTablesPreferencePane.h"
#import "SPEditorPreferencePane.h"
#import "SPGeneralPreferencePane.h"
#import "SPNotificationsPreferencePane.h"
#import "SPNetworkPreferencePane.h"
#import "SPFilePreferencePane.h"

#import "sequel-ace-Swift.h"

@interface SPPreferenceController () <NSWindowDelegate>

- (void)_resizeWindowForContentView:(NSView *)view;

@end

#pragma mark -

@implementation SPPreferenceController

@synthesize generalPreferencePane;
@synthesize tablesPreferencePane;
@synthesize notificationsPreferencePane;
@synthesize editorPreferencePane;
@synthesize networkPreferencePane;
@synthesize filePreferencePane;
@synthesize fontChangeTarget;

- (instancetype)init
{
	if ((self = [super initWithWindowNibName:@"Preferences"])) {		
		fontChangeTarget = 0;
	}

	return self;
}

/**
 * Sets up various interface controls once the window is loaded.
 */
- (void)windowDidLoad
{		
	[self setupToolbar];

	if (@available(macOS 10.14, *)) {
		[appearancePopUp setEnabled:YES];
	} else {
		[appearancePopUp setEnabled:NO];
		[appearanceMacOSVersionLabel setHidden:NO];
	}

	preferencePanes = [[NSArray alloc] initWithObjects:
					   generalPreferencePane,
					   tablesPreferencePane,
					   notificationsPreferencePane,
					   editorPreferencePane,
					   networkPreferencePane,
					   filePreferencePane,
					   nil];
    [super windowDidLoad];
}

#pragma mark -
#pragma mark Toolbar item IBAction methods

- (IBAction)displayPreferencePane:(id)sender
{	
	SPPreferencePane <SPPreferencePaneProtocol> *preferencePane = nil;
	
	if (!sender) {
		preferencePane = generalPreferencePane;
	}
	else {
		for (SPPreferencePane <SPPreferencePaneProtocol> *prefPane in preferencePanes)
		{
			if ([[prefPane preferencePaneIdentifier] isEqualToString:[sender itemIdentifier]]) {
				preferencePane = prefPane;
				break;
			}
		}
	}
	
	[[self window] setMinSize:NSMakeSize(500, 450)];
	[[self window] setShowsResizeIndicator:YES];
	
	[toolbar setSelectedItemIdentifier:[preferencePane preferencePaneIdentifier]];
	
	[preferencePane preferencePaneWillBeShown];
	
	[self _resizeWindowForContentView:[preferencePane preferencePaneView]];
}

#pragma mark -
#pragma mark Other

/**
 * Called when the user changes the selected font. This method is defined here as the specific preference
 * pane controllers (NSViewController subclasses) don't seem to be in the responder chain so we need to catch
 * it here.
 */
- (void)changeDefaultFont:(id)sender
{
	NSFont *font;
	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
	
	switch (fontChangeTarget)
	{
		case SPPrefFontChangeTargetGeneral:
			font = [[NSFontPanel sharedFontPanel] panelConvertFont:[NSUserDefaults getFont]];
			[NSUserDefaults saveFont:font];
            [generalPreferencePane updateDisplayedFontName];
			break;
		case SPPrefFontChangeTargetEditor:
			font = [[NSFontPanel sharedFontPanel] panelConvertFont:[NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPCustomQueryEditorFont]]];
			
			[prefs setObject:[NSArchiver archivedDataWithRootObject:font] forKey:SPCustomQueryEditorFont];
			
			[editorPreferencePane updateDisplayedEditorFontName];
			break;
	}
}

#pragma mark -
#pragma mark Private API

/**
 * Constructs the preferences' window toolbar.
 */
- (void)setupToolbar
{
	toolbar = [[NSToolbar alloc] initWithIdentifier:@"Preference Toolbar"];

	// General preferences
	generalItem = [[NSToolbarItem alloc] initWithItemIdentifier:[generalPreferencePane preferencePaneIdentifier]];

	[generalItem setLabel:[generalPreferencePane preferencePaneName]];
	[generalItem setImage:[generalPreferencePane preferencePaneIcon]];
	[generalItem setToolTip:[generalPreferencePane preferencePaneToolTip]];
	[generalItem setTarget:self];
	[generalItem setAction:@selector(displayPreferencePane:)];

	// Table preferences
	tablesItem = [[NSToolbarItem alloc] initWithItemIdentifier:[tablesPreferencePane preferencePaneIdentifier]];

	[tablesItem setLabel:[tablesPreferencePane preferencePaneName]];
	[tablesItem setImage:[tablesPreferencePane preferencePaneIcon]];
	[tablesItem setToolTip:[tablesPreferencePane preferencePaneToolTip]];
	[tablesItem setTarget:self];
	[tablesItem setAction:@selector(displayPreferencePane:)];

	// Notification preferences
	notificationsItem = [[NSToolbarItem alloc] initWithItemIdentifier:[notificationsPreferencePane preferencePaneIdentifier]];

	[notificationsItem setLabel:[notificationsPreferencePane preferencePaneName]];
	[notificationsItem setImage:[notificationsPreferencePane preferencePaneIcon]];
	[notificationsItem setToolTip:[notificationsPreferencePane preferencePaneToolTip]];
	[notificationsItem setTarget:self];
	[notificationsItem setAction:@selector(displayPreferencePane:)];

	// Editor preferences
	editorItem = [[NSToolbarItem alloc] initWithItemIdentifier:[editorPreferencePane preferencePaneIdentifier]];
	
	[editorItem setLabel:[editorPreferencePane preferencePaneName]];
	[editorItem setImage:[editorPreferencePane preferencePaneIcon]];
	[editorItem setToolTip:[editorPreferencePane preferencePaneToolTip]];
	[editorItem setTarget:self];
	[editorItem setAction:@selector(displayPreferencePane:)];

	// Network preferences
	networkItem = [[NSToolbarItem alloc] initWithItemIdentifier:[networkPreferencePane preferencePaneIdentifier]];

	[networkItem setLabel:[networkPreferencePane preferencePaneName]];
	[networkItem setImage:[networkPreferencePane preferencePaneIcon]];
	[networkItem setToolTip:[networkPreferencePane preferencePaneToolTip]];
	[networkItem setTarget:self];
	[networkItem setAction:@selector(displayPreferencePane:)];
	
	// File preferences
	
	fileItem = [[NSToolbarItem alloc] initWithItemIdentifier:[filePreferencePane preferencePaneIdentifier]];
	
	[fileItem setLabel:[filePreferencePane preferencePaneName]];
	[fileItem setImage:[filePreferencePane preferencePaneIcon]];
	[fileItem setToolTip:[filePreferencePane preferencePaneToolTip]];
	[fileItem setTarget:self];
	[fileItem setAction:@selector(displayPreferencePane:)];

	[toolbar setDelegate:self];
	[toolbar setSelectedItemIdentifier:[generalPreferencePane preferencePaneIdentifier]];
	[toolbar setAllowsUserCustomization:NO];

	[[self window] setToolbar:toolbar];
	[[self window] setShowsToolbarButton:NO];

	[self displayPreferencePane:nil];
}

/**
 * Resizes the window to the size of the supplied view.
 */
- (void)_resizeWindowForContentView:(NSView *)view
{
	// Handle expanding
	[[self window] resizeForContentView:view];

	// Add view
	[self window].contentView = view;

	// Handle contracting
	[[self window] resizeForContentView:view];
}

#pragma mark - SPPreferenceControllerDelegate

#pragma mark Window delegate methods

/**
 * Trap window close notifications and use them to ensure changes are saved.
 */
- (void)windowWillClose:(NSNotification *)notification
{
	[[NSColorPanel sharedColorPanel] close];

	// Mark the currently selected field in the window as having finished editing, to trigger saves.
	if ([[self window] firstResponder]) {
		[[self window] endEditingFor:[[self window] firstResponder]];
	}
}

#pragma mark -
#pragma mark Toolbar delegate methods

- (NSToolbarItem *)toolbar:(NSToolbar *)aToolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	if ([itemIdentifier isEqualToString:SPPreferenceToolbarGeneral]) {
		return generalItem;
	}
	else if ([itemIdentifier isEqualToString:SPPreferenceToolbarTables]) {
		return tablesItem;
	}
	else if ([itemIdentifier isEqualToString:SPPreferenceToolbarNotifications]) {
		return notificationsItem;
	}
	else if ([itemIdentifier isEqualToString:SPPreferenceToolbarNetwork]) {
		return networkItem;
	}
	else if ([itemIdentifier isEqualToString:SPPreferenceToolbarEditor]) {
		return editorItem;
	}
	else if ([itemIdentifier isEqualToString:SPPreferenceToolbarShortcuts]) {
		return shortcutItem;
	}
	else if ([itemIdentifier isEqualToString:SPPreferenceToolbarFile]) {
		return fileItem;
	}

	return [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)aToolbar
{
	return @[
			 SPPreferenceToolbarGeneral,
			 SPPreferenceToolbarTables,
			 SPPreferenceToolbarNotifications,
			 SPPreferenceToolbarEditor,
			 SPPreferenceToolbarShortcuts,
			 SPPreferenceToolbarNetwork,
			 SPPreferenceToolbarFile
			 ];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)aToolbar
{
	return @[
			 SPPreferenceToolbarGeneral,
			 SPPreferenceToolbarTables,
			 SPPreferenceToolbarNotifications,
			 SPPreferenceToolbarEditor,
			 SPPreferenceToolbarShortcuts,
			 SPPreferenceToolbarNetwork,
			 SPPreferenceToolbarFile
			 ];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)aToolbar
{
	return @[
			 SPPreferenceToolbarGeneral,
			 SPPreferenceToolbarTables,
			 SPPreferenceToolbarNotifications,
			 SPPreferenceToolbarEditor,
			 SPPreferenceToolbarShortcuts,
			 SPPreferenceToolbarNetwork,
			 SPPreferenceToolbarFile
			 ];
}

@end
